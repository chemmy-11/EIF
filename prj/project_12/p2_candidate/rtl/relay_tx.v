//=============================================================================
// relay_tx.v — prj12 P2 候选件②：把 payload 重建成一整帧以太网/IPv4/UDP
//-----------------------------------------------------------------------------
// 定位：**候选设计，不并入 P1 位流**（草案 §3.2 / §4.1 P0-07/P0-08）。
// 数据流（P2）：Aurora RX → unpack → mem2（存对端 payload）→ [本件] → RGMII TX → 本板 PC
//
// 为什么需要它：prj11 的以太网栈是"终止+回显"，回显帧 des_mac/des_ip = 源 PC
// （aurora_mem_bridge.v 里 assign des_mac = src_mac）。跨板后这种帧只能在对端
// 网口"看到"，不会被 OS 交付。P2 必须按**本板 PC 的 MAC/IP** 重建帧。
//
// 设计取舍（先静态，后续再做 ARP 学习）：
//   * 源 MAC/IP/端口 = 本板编译期参数（SRC_MAC/SRC_IP/SRC_PORT）
//   * 目的 MAC/IP/端口 = 运行时输入 dst_mac/dst_ip/dst_port
//   * IP 头校验和硬件算；**UDP 校验和写 0**（IPv4 合法，表示未计算）
//   * 长度上限：payload_len <= 1496（1538 帧上限 - 42 头），超限只置错不发送
//   * start 为 1 拍脉冲，同拍 payload_len 与 dst_* 必须有效
//
// TB 判据：42B 头 + payload 与参考模型逐字节一致；IP 校验和自校验（累加=0xFFFF）；
//           长度 0 / 26 / 100 / 1496 / 1497(超限) 各验一遍。
//=============================================================================
`timescale 1ns/1ps

module relay_tx #(
    parameter [47:0] SRC_MAC  = 48'h00_11_22_33_44_55,
    parameter [31:0] SRC_IP   = {8'd192, 8'd168, 8'd1, 8'd10},
    parameter [15:0] SRC_PORT = 16'd1234,
    parameter integer MAX_PAYLOAD = 1496
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 目的端（本板 PC；P2 先静态配置）----
    input  wire [47:0] dst_mac,
    input  wire [31:0] dst_ip,
    input  wire [15:0] dst_port,

    // ---- 帧启动 ----
    input  wire        start,
    input  wire [15:0] payload_len,

    // ---- payload 入 ----
    input  wire [7:0]  p_data,
    input  wire        p_valid,
    input  wire        p_last,
    output wire        p_ready,

    // ---- 整帧出（ETH+IP+UDP+payload）----
    output reg  [7:0]  m_data,
    output reg         m_valid,
    output reg         m_last,
    input  wire        m_ready,

    // ---- 状态/错误 ----
    output reg         busy,
    output reg         done,
    output reg         err_oversize,
    output reg         err_short
);
    localparam [1:0] ST_IDLE = 2'd0, ST_HDR = 2'd1, ST_PAY = 2'd2, ST_END = 2'd3;
    localparam [15:0] HDR_BYTES = 16'd42;

    reg [1:0]   st;
    reg [335:0] hdr;         // 42B 头部（byte0 在最高 8 位）
    reg [15:0]  hdr_cnt;
    reg [15:0]  pay_cnt;
    reg [15:0]  len_q;
    reg         shorts;

    // ---------------- IP 头校验和（20B 头，checksum 字段按 0 计入） ----------
    function [15:0] ip_cksum(input [15:0] tot_len, input [31:0] dip);
        reg [31:0] s;
        begin
            s = 32'h0000_4500                        // ver/ihl/tos
              + {16'h0000, tot_len}                  // total length
              + 32'h0000_0000                        // identification
              + 32'h0000_4000                        // flags(DF)/frag
              + 32'h0000_4011                        // ttl=64, proto=17
              + {16'h0000, SRC_IP[31:16]} + {16'h0000, SRC_IP[15:0]}
              + {16'h0000, dip[31:16]}    + {16'h0000, dip[15:0]};
            s = (s & 32'h0000_FFFF) + (s >> 16);
            s = (s & 32'h0000_FFFF) + (s >> 16);
            ip_cksum = ~s[15:0];
        end
    endfunction

    // ★注意：头部长度字段必须用**本拍输入的 payload_len** 计算，
    //   不能用 len_q（它在本拍才被赋值，会拿到上一帧的长度）。
    wire [15:0] total_len_i = 16'd28 + payload_len;
    wire [15:0] udp_len_i   = 16'd8  + payload_len;
    wire [15:0] cksum_i     = ip_cksum(16'd28 + payload_len, dst_ip);

    assign p_ready = (st == ST_PAY) && m_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st           <= ST_IDLE;
            hdr          <= 336'd0;
            hdr_cnt      <= 16'd0;
            pay_cnt      <= 16'd0;
            len_q        <= 16'd0;
            m_data       <= 8'd0;
            m_valid      <= 1'b0;
            m_last       <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
            err_oversize <= 1'b0;
            err_short    <= 1'b0;
            shorts       <= 1'b0;
        end else begin
            done <= 1'b0;
            if (m_valid && m_ready) begin
                m_valid <= 1'b0;
                m_last  <= 1'b0;
            end

            case (st)
            ST_IDLE: begin
                if (start) begin
                    err_oversize <= 1'b0;
                    err_short    <= 1'b0;
                    shorts       <= 1'b0;
                    if (payload_len > MAX_PAYLOAD) begin
                        err_oversize <= 1'b1;
                        busy         <= 1'b0;
                    end else begin
                        len_q   <= payload_len;
                        busy    <= 1'b1;
                        pay_cnt <= 16'd0;
                        hdr_cnt <= 16'd0;
                        hdr <= { dst_mac, SRC_MAC, 16'h0800,
                                 8'h45, 8'h00, total_len_i,
                                 16'h0000, 16'h4000,
                                 8'd64, 8'd17, cksum_i,
                                 SRC_IP, dst_ip,
                                 SRC_PORT, dst_port, udp_len_i, 16'h0000 };
                        st <= ST_HDR;
                    end
                end
            end
            ST_HDR: begin
                if (!m_valid || m_ready) begin
                    m_valid <= 1'b1;
                    m_data  <= hdr[335:328];
                    m_last  <= 1'b0;
                    hdr     <= {hdr[327:0], 8'h00};
                    hdr_cnt <= hdr_cnt + 16'd1;
                    if (hdr_cnt == HDR_BYTES - 16'd1)
                        st <= (len_q == 16'd0) ? ST_END : ST_PAY;
                end
            end
            ST_PAY: begin
                if (p_valid && p_ready) begin
                    m_valid <= 1'b1;
                    m_data  <= p_data;
                    m_last  <= (pay_cnt == len_q - 16'd1);
                    pay_cnt <= pay_cnt + 16'd1;
                    shorts  <= shorts | ~p_last;
                    if (pay_cnt == len_q - 16'd1) st <= ST_END;
                end
            end
            ST_END: begin
                done <= 1'b1;
                busy <= 1'b0;
                if (shorts || (pay_cnt != len_q)) err_short <= 1'b1;
                st <= ST_IDLE;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end
endmodule
