//=============================================================================
// local_steer.v — prj12 P2 候选件③：本地控制面 vs 跨板数据面的分流判决
//-----------------------------------------------------------------------------
// 定位：**候选设计，不并入 P1 位流**（草案 §3.2「本地/转发分流」）。
// 为什么必须有它：prj11 的以太网栈对收到的帧"终止+回显"（des_mac=src_mac,
//   des_ip=src_ip）。跨板后如果 ARP/ICMP/命令应答也走 Aurora，PC1 的 ARP 会被
//   送到板 B 的网口出去（PC2 看到一堆不属于它的 ARP），控制面直接崩。
//   => P2 必须把 **本地控制面**（ARP/ICMP/命令端口）留在本板栈，
//      只把 **数据面 UDP payload** 送 mem1 → Aurora → 对端 relay_tx。
//
// 判决表（纯组合，1 拍；P2 集成时在 eth RX 的帧头解析后打一拍即可）：
//   eth_type == 0x0806 (ARP)                      -> LOCAL_ARP
//   eth_type == 0x0800 && ip_proto == 1 (ICMP)    -> LOCAL_ICMP
//   ipv4/udp && dst_ip==BOARD_IP && dport==1235   -> LOCAL_CMD     （现有命令通道）
//   ipv4/udp && dport==1234                       -> RELAY         （数据面）
//   ipv4/udp && dst_ip==BOARD_IP                  -> LOCAL_STACK   （栈的其它服务）
//   其余                                          -> DROP
//=============================================================================
`timescale 1ns/1ps

module local_steer #(
    parameter [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10},
    parameter [15:0] CMD_PORT  = 16'd1235,
    parameter [15:0] DATA_PORT = 16'd1234
) (
    input  wire [15:0] eth_type,      // 0x0806 ARP / 0x0800 IPv4
    input  wire [7:0]  ip_proto,      // 1 ICMP / 17 UDP
    input  wire [31:0] dst_ip,
    input  wire [15:0] dst_port,
    output reg  [2:0]  cls,
    output wire        is_local,
    output wire        is_relay,
    output wire        is_drop
);
    localparam [2:0] CLS_DROP  = 3'd0,
                     CLS_ARP   = 3'd1,
                     CLS_ICMP  = 3'd2,
                     CLS_CMD   = 3'd3,
                     CLS_STACK = 3'd4,
                     CLS_RELAY = 3'd5;

    always @* begin
        if (eth_type == 16'h0806) begin
            cls = CLS_ARP;                       // ARP 永远本地
        end else if (eth_type == 16'h0800) begin
            if (ip_proto == 8'd1) begin
                cls = CLS_ICMP;                  // ping 永远本地
            end else if (ip_proto == 8'd17) begin
                if (dst_ip == BOARD_IP && dst_port == CMD_PORT)
                    cls = CLS_CMD;               // 命令通道（magic "P10C" 判据在栈里）
                else if (dst_port == DATA_PORT)
                    cls = CLS_RELAY;             // 数据面 -> mem1 -> Aurora
                else if (dst_ip == BOARD_IP)
                    cls = CLS_STACK;             // 其它本板 UDP 服务
                else
                    cls = CLS_DROP;              // 广播/陌生地址：不转发
            end else begin
                cls = CLS_DROP;
            end
        end else begin
            cls = CLS_DROP;
        end
    end

    assign is_local = (cls == CLS_ARP) || (cls == CLS_ICMP) ||
                      (cls == CLS_CMD) || (cls == CLS_STACK);
    assign is_relay = (cls == CLS_RELAY);
    assign is_drop  = (cls == CLS_DROP);
endmodule
