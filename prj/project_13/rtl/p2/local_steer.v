//=============================================================================
// local_steer.v  --  prj13 P2 (v0.2 contract) local / relay / drop classifier
//-----------------------------------------------------------------------------
// 依据: D:\GSnFPipe-FPGA-PP\docs\protocol_v1.md §2.5（A 侧转发模型）与 issue #10
//
// 判决表（顺序即优先级，与契约逐条对应）：
//   1) i_eth_type == 0x0806            -> ARP(3)    任何 ARP 永不 RELAY
//      （PROXY_ARP_EN=1 且 target==PEER_IP 时仍是 ARP/LOCAL 语义；代理应答
//        由后续 ARP 应答件实现，本模块判决不因该开关改变）
//   2) eth_dst 广播（非 ARP）:
//        i_ip_dst == BOARD_IP -> LOCAL(1)；否则 -> DROP + DROP_BROADCAST
//   3) eth_dst 组播（首字节 bit0=1 且非广播）-> DROP + DROP_MULTICAST
//   4) eth_dst != BOARD_MAC 且非广播/组播   -> DROP + DROP_MAC
//   5) i_ip_hdr_ok == 0                -> DROP + DROP_NONE（reason 由上游沿给出）
//   6) ip_dst == 255.255.255.255 或 0.0.0.0/8 -> DROP + DROP_BROADCAST
//      ip_dst[31:28] == 4'hE（224/4 组播）  -> DROP + DROP_MULTICAST
//   7) ip_dst == BOARD_IP -> LOCAL(1)
//      ip_dst == PEER_IP  -> RELAY(2)
//   8) 其它                            -> DROP + DROP_UNKNOWN_DST
//
// **防乒乓红线**：只有 dst==PEER_IP 才 RELAY；绝不"非本板 IP 都转发"，
// 否则 PC 发 8.8.8.8 会让 A→B→A→B 成环。第 8 条就是这条红线。
//
// 组合判决部分为纯组合输出，上游同拍即可用；计数器组为 clk 域 32 bit 粘滞。
//
// 编码：纯 Verilog-2001，单时钟域，异步低有效复位。
//=============================================================================
`timescale 1ns / 1ps

module local_steer #(
    parameter [47:0] BOARD_MAC    = 48'h02_00_00_00_0A_01,               // 板 A；板 B 0B:01
    parameter [31:0] BOARD_IP     = {8'd192, 8'd168, 8'd50, 8'd11},      // 板 A；板 B .12
    parameter [31:0] PEER_IP      = {8'd192, 8'd168, 8'd50, 8'd2},       // 板 A 的对端 PC2；板 B .1
    parameter [31:0] PC_IP        = {8'd192, 8'd168, 8'd50, 8'd1},       // 本板直连 PC；板 B .2
    parameter        PROXY_ARP_EN = 1'b0
)(
    // ---- 时钟/复位（公共约定：单时钟域，异步低有效复位）----
    input  wire        clk,
    input  wire        rst_n,
    // ---- 组合判决输入 ----
    input  wire [47:0] i_eth_dst,
    input  wire [15:0] i_eth_type,
    input  wire [31:0] i_ip_dst,
    input  wire [15:0] i_ip_total_len,
    input  wire        i_ip_hdr_ok,
    input  wire [15:0] i_frame_len,
    output reg  [2:0]  o_decision,      // 0=DROP 1=LOCAL 2=RELAY 3=ARP
    output reg  [3:0]  o_drop_reason,
    // ---- 计数器事件输入 ----
    input  wire        i_frame_pulse,
    input  wire        i_relay_pulse,
    input  wire        i_local_pulse,
    input  wire        i_arp_pulse,
    input  wire        i_drop_pulse,
    input  wire [3:0]  i_drop_reason,
    // ---- 32 bit 粘滞计数器 ----
    output reg  [31:0] o_cnt_rx_frames,
    output reg  [31:0] o_cnt_relay,
    output reg  [31:0] o_cnt_local,
    output reg  [31:0] o_cnt_arp,
    output reg  [31:0] o_cnt_drop_vlan,
    output reg  [31:0] o_cnt_drop_ipv6,
    output reg  [31:0] o_cnt_drop_ethertype,
    output reg  [31:0] o_cnt_drop_broadcast,
    output reg  [31:0] o_cnt_drop_multicast,
    output reg  [31:0] o_cnt_drop_unknown_dst,
    output reg  [31:0] o_cnt_drop_oversize,
    output reg  [31:0] o_cnt_drop_bad_csum,
    output reg  [31:0] o_cnt_drop_truncated,
    output reg  [31:0] o_cnt_drop_mac
);

    //-------------------------------------------------------------------------
    // 判决枚举
    //-------------------------------------------------------------------------
    localparam [2:0] DEC_DROP  = 3'd0;
    localparam [2:0] DEC_LOCAL = 3'd1;
    localparam [2:0] DEC_RELAY = 3'd2;
    localparam [2:0] DEC_ARP   = 3'd3;

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

    localparam [47:0] MAC_BCAST       = 48'hFFFF_FFFF_FFFF;
    localparam [31:0] IP_BCAST        = 32'hFFFF_FFFF;

    //-------------------------------------------------------------------------
    // 组合判决
    //-------------------------------------------------------------------------
    wire eth_is_bcast = (i_eth_dst == MAC_BCAST);
    wire eth_is_mcast = (i_eth_dst[40] == 1'b1) && !eth_is_bcast;
    wire eth_is_arp   = (i_eth_type == 16'h0806);
    wire ip_is_bcast  = (i_ip_dst == IP_BCAST) || (i_ip_dst[31:24] == 8'h00);
    wire ip_is_mcast  = (i_ip_dst[31:28] == 4'hE);

    always @* begin
        o_decision    = DEC_DROP;
        o_drop_reason = DROP_NONE;

        if (eth_is_arp) begin
            // 1) 任何 ARP 都在本地终结，永不 RELAY
            o_decision    = DEC_ARP;
            o_drop_reason = DROP_NONE;
        end else if (eth_is_bcast) begin
            // 2) 以太网广播（非 ARP）
            if (i_ip_dst == BOARD_IP) begin
                o_decision    = DEC_LOCAL;
                o_drop_reason = DROP_NONE;
            end else begin
                o_decision    = DEC_DROP;
                o_drop_reason = DROP_BROADCAST;
            end
        end else if (eth_is_mcast) begin
            // 3) 以太网组播
            o_decision    = DEC_DROP;
            o_drop_reason = DROP_MULTICAST;
        end else if (i_eth_dst != BOARD_MAC) begin
            // 4) 非本板 MAC（非混杂模式）
            o_decision    = DEC_DROP;
            o_drop_reason = DROP_MAC;
        end else if (!i_ip_hdr_ok) begin
            // 5) IP 头没解析通过：reason 由上游结构检查沿给出
            o_decision    = DEC_DROP;
            o_drop_reason = DROP_NONE;
        end else if (ip_is_bcast) begin
            // 6a) IP 定向/受限广播或 0.0.0.0/8
            o_decision    = DEC_DROP;
            o_drop_reason = DROP_BROADCAST;
        end else if (ip_is_mcast) begin
            // 6b) IP 组播 224.0.0.0/4
            o_decision    = DEC_DROP;
            o_drop_reason = DROP_MULTICAST;
        end else if (i_ip_dst == BOARD_IP) begin
            // 7a) 本板
            o_decision    = DEC_LOCAL;
            o_drop_reason = DROP_NONE;
        end else if (i_ip_dst == PEER_IP) begin
            // 7b) 对端 —— 唯一允许跨板的判决
            o_decision    = DEC_RELAY;
            o_drop_reason = DROP_NONE;
        end else begin
            // 8) 其它（含 8.8.8.8）：DROP。防乒乓红线。
            o_decision    = DEC_DROP;
            o_drop_reason = DROP_UNKNOWN_DST;
        end
    end

    //-------------------------------------------------------------------------
    // 计数器组（32 bit 粘滞，异步低有效复位）
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_cnt_rx_frames          <= 32'd0;
            o_cnt_relay              <= 32'd0;
            o_cnt_local              <= 32'd0;
            o_cnt_arp                <= 32'd0;
            o_cnt_drop_vlan          <= 32'd0;
            o_cnt_drop_ipv6          <= 32'd0;
            o_cnt_drop_ethertype     <= 32'd0;
            o_cnt_drop_broadcast     <= 32'd0;
            o_cnt_drop_multicast     <= 32'd0;
            o_cnt_drop_unknown_dst   <= 32'd0;
            o_cnt_drop_oversize      <= 32'd0;
            o_cnt_drop_bad_csum      <= 32'd0;
            o_cnt_drop_truncated     <= 32'd0;
            o_cnt_drop_mac           <= 32'd0;
        end else begin
            if (i_frame_pulse) o_cnt_rx_frames <= o_cnt_rx_frames + 32'd1;
            if (i_relay_pulse) o_cnt_relay     <= o_cnt_relay     + 32'd1;
            if (i_local_pulse) o_cnt_local     <= o_cnt_local     + 32'd1;
            if (i_arp_pulse)   o_cnt_arp       <= o_cnt_arp       + 32'd1;

            if (i_drop_pulse) begin
                case (i_drop_reason)
                    DROP_VLAN:        o_cnt_drop_vlan        <= o_cnt_drop_vlan        + 32'd1;
                    DROP_IPV6:        o_cnt_drop_ipv6        <= o_cnt_drop_ipv6        + 32'd1;
                    DROP_ETHERTYPE:   o_cnt_drop_ethertype   <= o_cnt_drop_ethertype   + 32'd1;
                    DROP_BROADCAST:   o_cnt_drop_broadcast   <= o_cnt_drop_broadcast   + 32'd1;
                    DROP_MULTICAST:   o_cnt_drop_multicast   <= o_cnt_drop_multicast   + 32'd1;
                    DROP_UNKNOWN_DST: o_cnt_drop_unknown_dst <= o_cnt_drop_unknown_dst + 32'd1;
                    DROP_OVERSIZE:    o_cnt_drop_oversize    <= o_cnt_drop_oversize    + 32'd1;
                    DROP_BAD_CSUM:    o_cnt_drop_bad_csum    <= o_cnt_drop_bad_csum    + 32'd1;
                    DROP_TRUNCATED:   o_cnt_drop_truncated   <= o_cnt_drop_truncated   + 32'd1;
                    DROP_MAC:         o_cnt_drop_mac         <= o_cnt_drop_mac         + 32'd1;
                    default: ;   // DROP_NONE(0) 不加任何 drop 计数
                endcase
            end
        end
    end

endmodule
