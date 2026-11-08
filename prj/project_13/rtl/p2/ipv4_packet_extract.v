//=============================================================================
// ipv4_packet_extract.v  --  prj13 P2 (v0.2 contract) IPv4 packet extractor
//-----------------------------------------------------------------------------
// 地址：本模块**不含 IP 地址参数**（只做结构检查 + 元数据提取），BOARD_IP /
//       PEER_IP / PC_IP 全在 local_steer 里，默认按开工手册 §8 的 10.10.0.x。
//       这里只有 BOARD_MAC（MAC 方案未变）。
//       （TB 的 C22 用例验证：旧 192.168.50.11 已不是本板 IP -> DROP_UNKNOWN_DST）
//
// 功能
//   输入: 完整以太网帧字节流（14 B 以太网头 + IPv4 包 + 可选 padding）
//   输出: 只输出 IPv4 包本身（byte0 = version/IHL），长度严格 = total_len
//         （padding 被剥掉），外加 IP 头元数据。
//   结构检查（顺序即优先级，命中即整帧丢弃，仍把该帧消费到 eop）：
//     1) 帧长 < 14+20                        -> DROP_TRUNCATED
//     2) eth_type in {0x8100, 0x88A8}        -> DROP_VLAN
//     3) eth_type == 0x86DD                  -> DROP_IPV6
//     4) eth_type != 0x0800                  -> DROP_ETHERTYPE
//        （ARP 0x0806 走本条，但**不产生 drop 事件/计数**：ARP 的 LOCAL 记账
//          由 local_steer 负责，见任务契约）
//     5) version!=4 || ihl<5 || ihl*4>total_len -> DROP_TRUNCATED
//     6) total_len > MAX_IP_LEN              -> DROP_OVERSIZE
//     7) 帧长 < 14+total_len                 -> DROP_TRUNCATED
//     8) IP 头 ones'-complement 累加 != 0xFFFF -> DROP_BAD_CSUM
//     9) eth_dst 既非 BOARD_MAC 也非广播/组播 -> DROP_MAC
//
// 为什么是 store-and-forward（先收完整帧再判决）
//   契约要求被 DROP 的帧**不产生任何输出字节**，而 eth_rewrap 没有 abort 口，
//   一旦漏出半包就会在 PC 侧形成 runt/残帧。检查 1/7（帧长相关）只有到 eop
//   才知道结果，所以任何"边收边发"的切通实现都无法保证零输出。故本模块把帧
//   存进 BUF_DEPTH 字节的缓冲区（默认 14+1500 上取整到 64 = 1536 B），判决
//   通过后再以 m_* 流出。代价是单帧 50% 占空（收一段、发一段）；收益是"坏帧
//   零泄漏"这一硬语义。若后续要恢复线速，可在上层做双缓冲乒乓，或在本模块
//   加一个下游 abort 口后改成切通——都属集成阶段的事，不在本单元件范围内。
//
// 背压
//   输出侧 m_ready 拉低时字节原地保持（不丢、不重）。输入侧在 S_SEND/S_VERDICT
//   期间 s_ready=0，上游自然被反压。
//
// 编码
//   纯 Verilog-2001，单时钟域，异步低有效复位。禁用 SystemVerilog 语法。
//=============================================================================
`timescale 1ns / 1ps

module ipv4_packet_extract #(
    parameter [15:0] MAX_IP_LEN = 16'd1500,
    parameter [47:0] BOARD_MAC  = 48'h02_00_00_00_0A_01   // 板 A；板 B 改 48'h02_00_00_00_0B_01
)(
    input  wire        clk,
    input  wire        rst_n,
    // ---- 以太网帧输入（含 14 B 头、可能带 padding）----
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [7:0]  s_data,
    input  wire        s_sop,
    input  wire        s_eop,
    // ---- IPv4 包输出（byte0 = version/IHL，长度严格 = total_len）----
    output wire        m_valid,
    input  wire        m_ready,
    output wire [7:0]  m_data,
    output wire        m_sop,
    output wire        m_eop,
    // ---- 元数据（m_sop 被接收起有效，保持到 m_eop）----
    output wire [31:0] m_ip_src,
    output wire [31:0] m_ip_dst,
    output wire [15:0] m_total_len,
    output wire [15:0] m_ip_id,
    output wire [15:0] m_csum,
    output wire [7:0]  m_proto,
    output wire [7:0]  m_ttl,
    output wire [7:0]  m_tos,
    output wire [3:0]  m_ihl,
    output wire [2:0]  m_ip_flags,
    output wire [12:0] m_frag_off,
    output wire        m_is_fragment,   // MF=1 或 frag_off!=0
    // ---- 事件脉冲 ----
    output wire        o_frame_pulse,   // 每收到一帧 1 拍（判决拍，与 o_drop_pulse 同拍）
    output wire        o_parse_pulse,   // 每发出一包（m_eop 握手那拍）
    output wire        o_drop_pulse,
    output wire [3:0]  o_drop_reason
);

    //-------------------------------------------------------------------------
    // 常量
    //-------------------------------------------------------------------------
    localparam [3:0] DROP_NONE        = 4'd0;
    localparam [3:0] DROP_VLAN        = 4'd1;
    localparam [3:0] DROP_IPV6        = 4'd2;
    localparam [3:0] DROP_ETHERTYPE   = 4'd3;
    localparam [3:0] DROP_BROADCAST   = 4'd4;
    localparam [3:0] DROP_MULTICAST   = 4'd5;
    localparam [3:0] DROP_UNKNOWN_DST = 4'd6;
    localparam [3:0] DROP_OVERSIZE    = 4'd7;
    localparam [3:0] DROP_BAD_CSUM    = 4'd8;
    localparam [3:0] DROP_TRUNCATED   = 4'd9;
    localparam [3:0] DROP_MAC         = 4'd10;

    localparam [1:0] S_IDLE = 2'd0,
                     S_RECV = 2'd1,
                     S_VRD  = 2'd2,
                     S_SEND = 2'd3;

    // 缓冲区深度：够放 14 + MAX_IP_LEN，按 64 B 对齐（1500 -> 1536）
    localparam       BUF_DEPTH = ((16'd14 + MAX_IP_LEN + 16'd63) / 16'd64) * 16'd64;

    localparam [15:0] ETH_HDR_LEN = 16'd14;
    localparam [15:0] MIN_IP_HDR  = 16'd20;

    //-------------------------------------------------------------------------
    // 状态与寄存器
    //-------------------------------------------------------------------------
    reg [1:0]  state;

    reg [7:0]  pkt_buf [0:BUF_DEPTH-1];

    reg [15:0] wr_cnt;        // 输入帧内字节序号（0 起）
    reg [15:0] frame_len;     // 本帧实际收到的字节数
    reg [15:0] rd_cnt;        // 输出时读取的帧内绝对序号（从 14 起）
    reg [15:0] send_end_m1;   // 最后一个输出字节的绝对序号 = 14+total_len-1

    // 接收期影子寄存器（判决后 m_* 直接驱动，保持到 m_eop）
    reg [47:0] sh_eth_dst;
    reg [47:0] sh_eth_src;    // 不对外，仅便于调试观测
    reg [15:0] sh_eth_type;
    reg [7:0]  sh_ver_ihl;
    reg [7:0]  sh_tos;
    reg [15:0] sh_total_len;
    reg [15:0] sh_ip_id;
    reg [2:0]  sh_flags;
    reg [12:0] sh_frag_off;
    reg [7:0]  sh_ttl;
    reg [7:0]  sh_proto;
    reg [15:0] sh_csum;
    reg [31:0] sh_ip_src;
    reg [31:0] sh_ip_dst;

    // IP 头 ones'-complement 累加器
    reg [7:0]  csum_hi;
    reg [31:0] csum_acc;

    // 事件脉冲寄存器（只有 drop reason 需要保持，便于观测上一次判决结果）
    reg [3:0]  drop_reason_r;

    //-------------------------------------------------------------------------
    // 握手
    //-------------------------------------------------------------------------
    assign s_ready = (state == S_IDLE) || (state == S_RECV);
    wire in_ace = s_valid & s_ready;

    assign m_valid = (state == S_SEND);
    wire out_ace   = m_valid & m_ready;

    assign m_data = pkt_buf[rd_cnt];
    assign m_sop  = (state == S_SEND) && (rd_cnt == ETH_HDR_LEN);
    assign m_eop  = (state == S_SEND) && (rd_cnt == send_end_m1);

    //-------------------------------------------------------------------------
    // 元数据输出（发送期由影子寄存器保持，单帧在飞所以无需二次锁存）
    //-------------------------------------------------------------------------
    assign m_ip_src      = sh_ip_src;
    assign m_ip_dst      = sh_ip_dst;
    assign m_total_len   = sh_total_len;
    assign m_ip_id       = sh_ip_id;
    assign m_csum        = sh_csum;
    assign m_proto       = sh_proto;
    assign m_ttl         = sh_ttl;
    assign m_tos         = sh_tos;
    assign m_ihl         = sh_ver_ihl[3:0];
    assign m_ip_flags    = sh_flags;
    assign m_frag_off    = sh_frag_off;
    assign m_is_fragment = (sh_flags[0] == 1'b1) || (sh_frag_off != 13'd0);

    // 事件脉冲（组合、恰好 1 拍）在判决逻辑之后赋值（v_drop_now / v_reason
    // 需要先声明）：o_frame_pulse 在 S_VRD 拍高 —— 该拍**先于**第一个输出字节
    // （S_SEND 从下一拍开始），所以上层用这拍锁存 o_drop_reason / 判决结果，
    // 到 S_SEND 首拍时已经稳定。若把脉冲寄存到 S_SEND 同拍，上层就没有建立
    // 时间了。

    //-------------------------------------------------------------------------
    // 地址判定辅助（组合）
    //-------------------------------------------------------------------------
    wire        eth_is_bcast = (sh_eth_dst == 48'hFFFF_FFFF_FFFF);
    wire        eth_is_mcast = (sh_eth_dst[40] == 1'b1) && !eth_is_bcast;
    wire        eth_dst_ok   = (sh_eth_dst == BOARD_MAC) || eth_is_bcast || eth_is_mcast;
    wire [15:0] hdr_len_byte = {10'd0, sh_ver_ihl[3:0], 2'b00};   // ihl*4

    // IP 头校验和折叠（ones' complement，端回卷两次以吃掉进位）
    wire [16:0] cs_t1    = {1'b0, csum_acc[15:0]} + {1'b0, csum_acc[31:16]};
    wire [16:0] cs_t2    = {1'b0, cs_t1[15:0]} + {16'd0, cs_t1[16]};
    wire [15:0] cs_fold  = cs_t2[16] ? (cs_t2[15:0] + 16'd1) : cs_t2[15:0];
    // 反码里 0x0000 与 0xFFFF 都表示"零"：合法头折叠后二者之一
    wire        csum_ok  = (cs_fold == 16'hFFFF) || (cs_fold == 16'h0000);

    wire [16:0] need_len = {1'b0, sh_total_len} + 17'd14;

    //-------------------------------------------------------------------------
    // 判决（组合，S_VRD 拍采样）
    //-------------------------------------------------------------------------
    reg [3:0] v_reason;
    always @* begin
        if (frame_len < (ETH_HDR_LEN + MIN_IP_HDR))                                  // 1
            v_reason = DROP_TRUNCATED;
        else if ((sh_eth_type == 16'h8100) || (sh_eth_type == 16'h88A8))             // 2
            v_reason = DROP_VLAN;
        else if (sh_eth_type == 16'h86DD)                                            // 3
            v_reason = DROP_IPV6;
        else if (sh_eth_type != 16'h0800)                                            // 4
            v_reason = DROP_ETHERTYPE;
        else if ((sh_ver_ihl[7:4] != 4'h4) || (sh_ver_ihl[3:0] < 4'd5) ||
                 (hdr_len_byte > sh_total_len))                                      // 5
            v_reason = DROP_TRUNCATED;
        else if (sh_total_len > MAX_IP_LEN)                                          // 6
            v_reason = DROP_OVERSIZE;
        else if ({1'b0, frame_len} < need_len)                                       // 7
            v_reason = DROP_TRUNCATED;
        else if (!csum_ok)                                                           // 8
            v_reason = DROP_BAD_CSUM;
        else if (!eth_dst_ok)                                                        // 9
            v_reason = DROP_MAC;
        else
            v_reason = DROP_NONE;
    end

    // ARP 不计 drop（LOCAL 记账归 local_steer），但也绝不能进 S_SEND
    wire v_arp      = (sh_eth_type == 16'h0806);
    wire v_pass     = (v_reason == DROP_NONE);
    wire v_drop_now = (v_reason != DROP_NONE) && !((v_reason == DROP_ETHERTYPE) && v_arp);

    // 事件脉冲（组合、恰好 1 拍）
    assign o_frame_pulse = (state == S_VRD);
    assign o_parse_pulse = (state == S_SEND) && m_eop && m_ready;
    assign o_drop_pulse  = (state == S_VRD) && v_drop_now;
    // 判决拍给当前判决，其余时间保持上一次判决（纯观测便利，无功能依赖）
    assign o_drop_reason = (state == S_VRD) ? v_reason : drop_reason_r;

    //-------------------------------------------------------------------------
    // 主状态机
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            wr_cnt        <= 16'd0;
            frame_len     <= 16'd0;
            rd_cnt        <= 16'd0;
            send_end_m1   <= 16'd0;
            sh_eth_dst    <= 48'd0;
            sh_eth_src    <= 48'd0;
            sh_eth_type   <= 16'd0;
            sh_ver_ihl    <= 8'd0;
            sh_tos        <= 8'd0;
            sh_total_len  <= 16'd0;
            sh_ip_id      <= 16'd0;
            sh_flags      <= 3'd0;
            sh_frag_off   <= 13'd0;
            sh_ttl        <= 8'd0;
            sh_proto      <= 8'd0;
            sh_csum       <= 16'd0;
            sh_ip_src     <= 32'd0;
            sh_ip_dst     <= 32'd0;
            csum_hi       <= 8'd0;
            csum_acc      <= 32'd0;
            drop_reason_r <= DROP_NONE;
        end else begin
            //-------------------------------------------------------------
            // 收帧侧：S_IDLE / S_RECV 都按 wr_cnt 解析
            //-------------------------------------------------------------
            if (in_ace) begin
                // -- 缓冲（只有 14+total_len 需要，超出部分丢弃即可）--
                if (wr_cnt < BUF_DEPTH) begin
                    pkt_buf[wr_cnt] <= s_data;
                end

                // -- 帧内计数 --
                wr_cnt    <= wr_cnt + 16'd1;
                frame_len <= frame_len + 16'd1;

                // -- 以太网头解析 --
                if (wr_cnt <= 16'd5) begin
                    sh_eth_dst <= {sh_eth_dst[39:0], s_data};
                end
                if ((wr_cnt >= 16'd6) && (wr_cnt <= 16'd11)) begin
                    sh_eth_src <= {sh_eth_src[39:0], s_data};
                end
                if (wr_cnt == 16'd12) begin
                    sh_eth_type[15:8] <= s_data;
                end
                if (wr_cnt == 16'd13) begin
                    sh_eth_type[7:0]  <= s_data;
                end

                // -- IPv4 头解析（绝对偏移 14 起）--
                if (wr_cnt == 16'd14) sh_ver_ihl  <= s_data;
                if (wr_cnt == 16'd15) sh_tos      <= s_data;
                if (wr_cnt == 16'd16) sh_total_len[15:8] <= s_data;
                if (wr_cnt == 16'd17) sh_total_len[7:0]  <= s_data;
                if (wr_cnt == 16'd18) sh_ip_id[15:8]     <= s_data;
                if (wr_cnt == 16'd19) sh_ip_id[7:0]      <= s_data;
                if (wr_cnt == 16'd20) sh_flags           <= s_data[7:5];
                if (wr_cnt == 16'd20) sh_frag_off[12:8]  <= s_data[4:0];
                if (wr_cnt == 16'd21) sh_frag_off[7:0]   <= s_data;
                if (wr_cnt == 16'd22) sh_ttl             <= s_data;
                if (wr_cnt == 16'd23) sh_proto           <= s_data;
                if (wr_cnt == 16'd24) sh_csum[15:8]      <= s_data;
                if (wr_cnt == 16'd25) sh_csum[7:0]       <= s_data;
                if (wr_cnt == 16'd26) sh_ip_src[31:24]   <= s_data;
                if (wr_cnt == 16'd27) sh_ip_src[23:16]   <= s_data;
                if (wr_cnt == 16'd28) sh_ip_src[15:8]    <= s_data;
                if (wr_cnt == 16'd29) sh_ip_src[7:0]     <= s_data;
                if (wr_cnt == 16'd30) sh_ip_dst[31:24]   <= s_data;
                if (wr_cnt == 16'd31) sh_ip_dst[23:16]   <= s_data;
                if (wr_cnt == 16'd32) sh_ip_dst[15:8]    <= s_data;
                if (wr_cnt == 16'd33) sh_ip_dst[7:0]     <= s_data;

                // -- IP 头 ones'-complement 累加（只累 ihl*4 字节，且跳过非法 ihl）--
                if (wr_cnt >= ETH_HDR_LEN) begin
                    if (((wr_cnt - ETH_HDR_LEN) & 16'h0001) == 16'h0000) begin
                        csum_hi <= s_data;                       // 每字的高字节
                    end else if ((wr_cnt - ETH_HDR_LEN) < hdr_len_byte) begin
                        csum_acc <= csum_acc + {16'd0, csum_hi, s_data};
                    end
                end

                // -- 状态推进 --
                if (state == S_IDLE) begin
                    state <= s_eop ? S_VRD : S_RECV;
                end else if (s_eop) begin
                    state <= S_VRD;
                end
            end

            //-------------------------------------------------------------
            // 判决拍
            //-------------------------------------------------------------
            if (state == S_VRD) begin
                drop_reason_r <= v_reason;

                if (!v_pass) begin
                    // 丢弃（ARP 也走这里，只是不产生 drop 脉冲/计数）
                    state     <= S_IDLE;
                    wr_cnt    <= 16'd0;
                    frame_len <= 16'd0;
                end else begin
                    // 通过：准备发送
                    rd_cnt      <= ETH_HDR_LEN;
                    send_end_m1 <= sh_total_len + ETH_HDR_LEN - 16'd1;
                    state       <= S_SEND;
                end

                // 收帧累加器复位（元数据影子寄存器保持，供 S_SEND 使用）
                sh_eth_dst <= 48'd0;
                sh_eth_src <= 48'd0;
                csum_hi    <= 8'd0;
                csum_acc   <= 32'd0;
            end

            //-------------------------------------------------------------
            // 发帧拍
            //-------------------------------------------------------------
            if (out_ace) begin
                if (m_eop) begin
                    state     <= S_IDLE;
                    wr_cnt    <= 16'd0;
                    frame_len <= 16'd0;
                    rd_cnt    <= 16'd0;
                end else begin
                    rd_cnt <= rd_cnt + 16'd1;
                end
            end
        end
    end

endmodule
