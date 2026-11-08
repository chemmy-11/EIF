//=============================================================================
// udp_payload_extract.v — prj12 P2 候选件①：从 UDP 数据报里取出 payload
//-----------------------------------------------------------------------------
// 定位：**候选设计，不并入 P1 位流**（草案 §4.1 P0-07/P0-08）。
// 数据流（P2）：eth RX → local_steer=RELAY → [本件] → mem1 写（复用 prj11 帧泵/桥）
//
// 输入约定（刻意收窄，便于单元验证）：
//   * 字节流从 **UDP 头第一个字节** 开始（IP/UDP 解析由既有以太网栈/steer 完成）
//   * sop 标记 UDP 头首字节所在拍；last 标记该数据报最后一字节
// 输出：payload 字节流（不含 8B UDP 头），m_len = 实际 payload 字节数
// 判据（TB）：长度 26/40/63/100/200/1200/1496 逐字节一致；零长/超长/长度不符/头截断 报错
//
// 错误标志（粘滞到帧尾，随 m_len_valid 一起给出）：
//   err_zero      payload 长度 0（协议上合法，但 P2 数据面视为无效帧）
//   err_oversize  payload > MAX_PAYLOAD（1538-42=1496；1538 是 prj11 帧上限）
//   err_len_mismatch  实际字节数 != udp_len-8
//   err_trunc     udp_len < 8 或流在头部/帧中意外结束
//=============================================================================
`timescale 1ns/1ps

module udp_payload_extract #(
    parameter integer MAX_PAYLOAD = 1496      // 1538 - 42（ETH+IP+UDP 头）
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- UDP 段输入（8bit 字节流）----
    input  wire [7:0]  s_data,
    input  wire        s_valid,
    input  wire        s_sop,
    input  wire        s_last,
    output wire        s_ready,

    // ---- payload 输出（8bit 字节流）----
    output reg  [7:0]  m_data,
    output reg         m_valid,
    output reg         m_last,
    input  wire        m_ready,

    // ---- 帧级结果 ----
    output reg  [15:0] m_len,
    output reg         m_len_valid,
    output reg         err_zero,
    output reg         err_oversize,
    output reg         err_len_mismatch,
    output reg         err_trunc
);
    localparam [1:0] ST_IDLE = 2'd0, ST_HDR = 2'd1, ST_PAY = 2'd2, ST_END = 2'd3;

    reg [1:0]  st;
    reg [2:0]  hdr_idx;
    reg [15:0] udp_len_q;
    reg [15:0] cnt;
    reg        last_seen;

    // 输出寄存器 slice：满时反压输入（1 深度弹性格，吞吐不掉）
    assign s_ready = (!m_valid) || m_ready;

    wire in_fire = s_valid && s_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st             <= ST_IDLE;
            hdr_idx        <= 3'd0;
            udp_len_q      <= 16'd0;
            cnt            <= 16'd0;
            last_seen      <= 1'b0;
            m_data         <= 8'd0;
            m_valid        <= 1'b0;
            m_last         <= 1'b0;
            m_len          <= 16'd0;
            m_len_valid    <= 1'b0;
            err_zero       <= 1'b0;
            err_oversize   <= 1'b0;
            err_len_mismatch <= 1'b0;
            err_trunc      <= 1'b0;
        end else begin
            // 输出弹性格出队
            if (m_valid && m_ready) begin
                m_valid <= 1'b0;
                m_last  <= 1'b0;
            end
            m_len_valid <= 1'b0;

            case (st)
            ST_IDLE: begin
                if (in_fire) begin
                    if (s_sop) begin
                        // UDP 头 8B: sport[0:1] dport[2:3] len[4:5] cksum[6:7]
                        st        <= ST_HDR;
                        hdr_idx   <= 3'd1;
                        udp_len_q <= 16'd0;
                        cnt       <= 16'd0;
                        last_seen <= s_last;
                        err_zero <= 1'b0; err_oversize <= 1'b0;
                        err_len_mismatch <= 1'b0; err_trunc <= 1'b0;
                        if (s_last) begin
                            // 只有 1 字节就结束：头都不全
                            err_trunc <= 1'b1;
                            st <= ST_END;
                        end
                    end else begin
                        err_trunc <= 1'b1;      // 未给 sop：流不同步
                        st <= ST_END;
                    end
                end
            end
            ST_HDR: begin
                if (in_fire) begin
                    if (hdr_idx == 3'd4)      udp_len_q[15:8] <= s_data;
                    if (hdr_idx == 3'd5)      udp_len_q[7:0]  <= s_data;
                    if (hdr_idx == 3'd7) begin
                        // 头部收齐，判长度
                        if (udp_len_q < 16'd8)      err_trunc <= 1'b1;
                        if (udp_len_q == 16'd8)     err_zero  <= 1'b1;
                        if ((udp_len_q - 16'd8) > MAX_PAYLOAD) err_oversize <= 1'b1;
                        st <= s_last ? ST_END : ST_PAY;
                        last_seen <= s_last;
                    end else begin
                        hdr_idx <= hdr_idx + 3'd1;
                        if (s_last) begin
                            err_trunc <= 1'b1;  // 头没齐就 last
                            st <= ST_END;
                        end
                    end
                end
            end
            ST_PAY: begin
                if (in_fire) begin
                    m_valid <= 1'b1;
                    m_data  <= s_data;
                    m_last  <= s_last;
                    cnt     <= cnt + 16'd1;
                    last_seen <= s_last;
                    if (s_last) st <= ST_END;
                end
            end
            ST_END: begin
                m_len       <= cnt;
                m_len_valid <= 1'b1;
                if (udp_len_q >= 16'd8 && cnt != (udp_len_q - 16'd8))
                    err_len_mismatch <= 1'b1;
                st <= ST_IDLE;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end
endmodule
