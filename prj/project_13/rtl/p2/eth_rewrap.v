//=============================================================================
// eth_rewrap.v  --  prj13 P2 (v0.2 contract) Ethernet re-wrapper
//-----------------------------------------------------------------------------
// 地址：本模块只有 MAC 参数（门控方案未变，顶层填实际 MAC）；IP 地址
//       （BOARD_IP/PEER_IP/PC_IP）全在 local_steer，默认按开工手册 §8 的 10.10.0.x。
//
// 功能
//   输入: 一个 IPv4 包的字节流（sop/eop 包住，共 i_pkt_len 字节）
//   输出: 一个完整以太网帧字节流
//           [14 B 新头: DST_MAC | SRC_MAC | 0x0800]
//           [IP 包字节 1:1 原样透传，**不修改任何字节**]
//           [若 14+i_pkt_len < MIN_FRAME_LEN，补 0x00 到 MIN_FRAME_LEN]
//   总长 m_frame_len = 14 + max(i_pkt_len, MIN_FRAME_LEN-14)
//   o_len_err: i_pkt_len 与实际收到的字节数不符时脉冲（1 拍）
//
// 语义要点
//   - 只加/换 14 B 以太网头，IP 包内部（源/目的 IP、端口、TTL、IP/UDP
//     checksum、DSCP、options、分片字段）一个 bit 都不动 —— 这是 P2 v0.2
//     的核心判据（protocol_v1.md §2.5）。
//   - 14 B 头期间 s_ready=0（需要先把头吐出去），上游被反压 14 拍；之后
//     s_ready = m_ready，1 byte/beat 直通。输出侧 m_ready 拉低时字节原地保持。
//
// 编码：纯 Verilog-2001，单时钟域，异步低有效复位。
//=============================================================================
`timescale 1ns / 1ps

module eth_rewrap #(
    parameter [47:0] SRC_MAC       = 48'h02_00_00_00_0A_01,  // 板 A；板 B 0B:01
    parameter [47:0] DST_MAC       = 48'h00_00_00_00_00_00,  // 对端 PC MAC（板 A 填 PC2 的）
    parameter [15:0] MIN_FRAME_LEN = 16'd60                  // 不含前导/FCS 的最小帧长
)(
    input  wire        clk,
    input  wire        rst_n,
    // ---- IP 包输入 ----
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [7:0]  s_data,
    input  wire        s_sop,
    input  wire        s_eop,
    input  wire [15:0] i_pkt_len,    // 在 s_sop 被接收那拍有效
    // ---- 以太网帧输出 ----
    output wire        m_valid,
    input  wire        m_ready,
    output wire [7:0]  m_data,
    output wire        m_sop,
    output wire        m_eop,
    output wire [15:0] m_frame_len,  // 最后一拍给出总字节数（本实现在整帧第 1 拍即稳定）
    output wire        o_len_err
);

    //-------------------------------------------------------------------------
    // 常量
    //-------------------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0,   // 等包首字节
                     S_HDR  = 3'd1,   // 吐 14 B 新以太网头
                     S_FIRST= 3'd2,   // 吐被暂存的首个 IP 字节
                     S_DATA = 3'd3,   // 1:1 直通
                     S_PAD  = 3'd4,
                     S_FCS  = 3'd5,   // 2026-11-20 D1 fix: 4B FCS
                     S_PRE  = 3'd6;   // 2026-11-20 D1 fix: 8B 前导码+SFD (7x55 + D5)   // 补零到 MIN_FRAME_LEN

    localparam [15:0] ETH_HDR_LEN = 16'd14;
    localparam [15:0] MIN_PAYLOAD = MIN_FRAME_LEN - ETH_HDR_LEN;  // 默认 46

    //-------------------------------------------------------------------------
    // 寄存器
    //-------------------------------------------------------------------------
    reg [2:0]  state;
    reg [3:0]  hdr_idx;      // 0..13
    reg [7:0]  hold_byte;    // 暂存的 IP 首字节
    reg [15:0] lat_pkt_len;  // sop 拍锁存的 i_pkt_len
    reg [15:0] tot_len;      // 本帧输出总长 = 14 + max(lat_pkt_len, MIN_PAYLOAD)
    reg [15:0] out_pos;      // 已输出字节数（也是下一个输出字节的序号）
    reg [15:0] in_cnt;       // 已收到的 IP 字节数
    reg        in_done;      // 输入包已收完（s_eop 已见）
    reg        len_err_r;
    // 2026-11-20 D1 fix: 前导码/SFD + FCS 相关声明
    reg  [3:0] pre_idx;      // 0..7 前导码/SFD
    reg  [1:0] fcs_idx;
    reg  [7:0] fcs_byte;
    reg        crc_clr_w;
    wire [31:0] crc_data_w, crc_next_w;
    localparam [7:0] PRE_SFD = 8'hD5;   // 前 7 字节恒 0x55，第 8 字节为 SFD

    //-------------------------------------------------------------------------
    // 输出字节选择
    //-------------------------------------------------------------------------
    reg [7:0] hdr_byte;
    always @* begin
        case (hdr_idx)
            4'd0:    hdr_byte = DST_MAC[47:40];
            4'd1:    hdr_byte = DST_MAC[39:32];
            4'd2:    hdr_byte = DST_MAC[31:24];
            4'd3:    hdr_byte = DST_MAC[23:16];
            4'd4:    hdr_byte = DST_MAC[15:8];
            4'd5:    hdr_byte = DST_MAC[7:0];
            4'd6:    hdr_byte = SRC_MAC[47:40];
            4'd7:    hdr_byte = SRC_MAC[39:32];
            4'd8:    hdr_byte = SRC_MAC[31:24];
            4'd9:    hdr_byte = SRC_MAC[23:16];
            4'd10:   hdr_byte = SRC_MAC[15:8];
            4'd11:   hdr_byte = SRC_MAC[7:0];
            4'd12:   hdr_byte = 8'h08;
            default: hdr_byte = 8'h00;          // idx 13
        endcase
    end

    //-------------------------------------------------------------------------
    // 握手
    //-------------------------------------------------------------------------
    // S_DATA 是直通态：s_ready 必须跟随 m_ready，否则输入侧会在下游反压时
    // 抢跑丢字节（in_ace 必须与 out_ace 等价）
    assign s_ready = (state == S_IDLE) ? 1'b1 :
                     ((state == S_DATA) ? m_ready : 1'b0);

    assign m_sop  = (state == S_HDR) && (hdr_idx == 4'd0);
    // 2026-11-20 D1 fix: EOP 移到 4 字节 FCS 的最后一拍
    assign m_eop  = (state == S_FCS) && (fcs_idx == 2'd3);

    assign m_frame_len = tot_len + 16'd12;   // 2026-11-20 D1 fix: +8 前导/SFD +4 FCS
    assign o_len_err   = len_err_r;

    // 输出有效与数据
    reg        m_valid_r;
    reg [7:0]  m_data_r;
    always @* begin
        m_valid_r = 1'b0;
        m_data_r  = 8'h00;
        case (state)
            S_PRE: begin
                m_valid_r = 1'b1;
                m_data_r  = (pre_idx == 4'd7) ? PRE_SFD : 8'h55;   // 7x55 + D5
            end
            S_HDR: begin
                m_valid_r = 1'b1;
                m_data_r  = hdr_byte;
            end
            S_FIRST: begin
                m_valid_r = 1'b1;
                m_data_r  = hold_byte;
            end
            S_DATA: begin
                m_valid_r = s_valid;
                m_data_r  = s_data;
            end
            S_PAD: begin
                m_valid_r = 1'b1;
                m_data_r  = 8'h00;
            end
            S_FCS: begin
                m_valid_r = 1'b1;
                m_data_r  = fcs_byte;
            end
            default: begin
                m_valid_r = 1'b0;
                m_data_r  = 8'h00;
            end
        endcase
    end

    assign m_valid = m_valid_r;
    assign m_data  = m_data_r;

    wire out_ace = m_valid_r && m_ready;
    wire in_ace  = s_valid && s_ready;

    //-------------------------------------------------------------------------
    // 2026-11-20 D1 修复：CRC32 (FCS) 生成
    // CRC 只覆盖 MAC 头 + IP + 填充（不含前导码/SFD，不含 FCS 自身）
    wire crc_en_w = out_ace && (state != S_FCS) && (state != S_PRE);
    // 新帧起始时清零（S_IDLE 收到首个字节那一拍）
    always @* crc_clr_w = (!rst_n) || ((state == S_IDLE) && s_valid);

    crc32_d8 u_fcs_crc (
        .clk      (clk       ),
        .rst_n    (rst_n     ),
        .data     (m_data_r  ),
        .crc_en   (crc_en_w  ),
        .crc_clr  (crc_clr_w ),
        .crc_data (crc_data_w),
        .crc_next (crc_next_w)
    );

    always @* begin
        case (fcs_idx)
            2'd0: fcs_byte = {~crc_data_w[24], ~crc_data_w[25], ~crc_data_w[26], ~crc_data_w[27],
                              ~crc_data_w[28], ~crc_data_w[29], ~crc_data_w[30], ~crc_data_w[31]};
            2'd1: fcs_byte = {~crc_data_w[16], ~crc_data_w[17], ~crc_data_w[18], ~crc_data_w[19],
                              ~crc_data_w[20], ~crc_data_w[21], ~crc_data_w[22], ~crc_data_w[23]};
            2'd2: fcs_byte = {~crc_data_w[8],  ~crc_data_w[9],  ~crc_data_w[10], ~crc_data_w[11],
                              ~crc_data_w[12], ~crc_data_w[13], ~crc_data_w[14], ~crc_data_w[15]};
            default: fcs_byte = {~crc_data_w[0], ~crc_data_w[1], ~crc_data_w[2], ~crc_data_w[3],
                              ~crc_data_w[4], ~crc_data_w[5], ~crc_data_w[6], ~crc_data_w[7]};
        endcase
    end

    //-------------------------------------------------------------------------
    // 主状态机
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            hdr_idx    <= 4'd0;
            hold_byte  <= 8'd0;
            lat_pkt_len<= 16'd0;
            tot_len    <= 16'd0;
            out_pos    <= 16'd0;
            in_cnt     <= 16'd0;
            in_done    <= 1'b0;
            len_err_r  <= 1'b0;
            pre_idx    <= 4'd0;
            fcs_idx    <= 2'd0;
        end else begin
            len_err_r <= 1'b0;

            //-------------------------------------------------------------
            // 收包首字节
            //-------------------------------------------------------------
            if ((state == S_IDLE) && s_valid) begin
                hold_byte   <= s_data;
                lat_pkt_len <= i_pkt_len;
                in_cnt      <= 16'd1;
                in_done     <= s_eop;
                hdr_idx     <= 4'd0;
                out_pos     <= 16'd0;
                // tot_len = 14 + max(pkt_len, MIN_PAYLOAD)
                if (i_pkt_len >= MIN_PAYLOAD) tot_len <= i_pkt_len + ETH_HDR_LEN;
                else                          tot_len <= MIN_FRAME_LEN;
                // 只有一个字节的包：立刻能判长度不符
                if (s_eop && (i_pkt_len != 16'd1)) len_err_r <= 1'b1;
                pre_idx     <= 4'd0;
                state       <= S_PRE;      // 2026-11-20: 先出前导码/SFD
            end

            //-------------------------------------------------------------
            // 2026-11-20 D1 fix: 前导码 7x55 + SFD D5（CRC 不覆盖此段）
            //-------------------------------------------------------------
            if ((state == S_PRE) && out_ace) begin
                if (pre_idx == 4'd7) begin
                    pre_idx <= 4'd0;
                    state   <= S_HDR;
                end else begin
                    pre_idx <= pre_idx + 4'd1;
                end
            end

            //-------------------------------------------------------------
            // 吐以太网头
            //-------------------------------------------------------------
            if ((state == S_HDR) && out_ace) begin
                if (hdr_idx == 4'd13) begin
                    hdr_idx <= 4'd0;
                    state   <= S_FIRST;
                end else begin
                    hdr_idx <= hdr_idx + 4'd1;
                end
                out_pos <= out_pos + 16'd1;
            end

            //-------------------------------------------------------------
            // 吐首个 IP 字节
            //-------------------------------------------------------------
            if ((state == S_FIRST) && out_ace) begin
                out_pos <= out_pos + 16'd1;
                if (in_done) begin
                    // 输入包只有 1 字节：该补零就补零，否则正好结束
                    if ((out_pos + 16'd1) >= tot_len) begin state <= S_FCS; fcs_idx <= 2'd0; end
                    else                              state <= S_PAD;
                end else begin
                    state <= S_DATA;
                end
            end

            //-------------------------------------------------------------
            // 1:1 直通
            //-------------------------------------------------------------
            if (state == S_DATA) begin
                if (in_ace) begin
                    in_cnt  <= in_cnt + 16'd1;
                    out_pos <= out_pos + 16'd1;
                    if (s_eop) begin
                        in_done <= 1'b1;
                        if (in_cnt + 16'd1 != lat_pkt_len) len_err_r <= 1'b1;
                        if ((out_pos + 16'd1) >= tot_len) begin state <= S_FCS; fcs_idx <= 2'd0; end
                        else                              state <= S_PAD;
                    end
                end
            end

            //-------------------------------------------------------------
            // 补零
            //-------------------------------------------------------------
            if ((state == S_PAD) && out_ace) begin
                if (out_pos == (tot_len - 16'd1)) begin state <= S_FCS; fcs_idx <= 2'd0; end
                else                              out_pos <= out_pos + 16'd1;
            end

            //-------------------------------------------------------------
            // 2026-11-20 D1 修复：追加 4 B FCS
            //-------------------------------------------------------------
            if ((state == S_FCS) && out_ace) begin
                if (fcs_idx == 2'd3) begin
                    fcs_idx <= 2'd0;
                    state   <= S_IDLE;
                end else begin
                    fcs_idx <= fcs_idx + 2'd1;
                end
            end
        end
    end

endmodule
