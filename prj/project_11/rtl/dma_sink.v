//=============================================================================
// dma_sink.v — AXI4-Stream 捕获器（prj11 B3-1a 冒烟判据数据源，ui_clk 域）
//-----------------------------------------------------------------------------
// 用途: axi_dma MM2S 从 DDR 槽区读出的 512 bit 流, 在换层(B3-1b 接 shim)之前
//   先由本件捕获, 一次验完「时钟域(300M) + 512b + 地址映射 + TKEEP 语义」:
//     q0 = {beats[15:0], bytes[15:0]}   拍数 / 字节数(按 TKEEP 计)
//     q1 = 首拍低 32 bit                 (PC 知道槽内容 -> 直接比对)
//     q2 = {done_cnt[7:0], tlast_seen, busy, 21'd0}
//
// ★时序结构(2026-10-12 首建 WNS -0.134 的修复): 整个流(tdata/tkeep/tlast)
//   先打一拍进 skid 式寄存组 {data_q, keep_q, last_q}(popcount 的 64 位锥
//   终结在 keep_q 上), FSM 消费这组延迟流 —— TLAST 结算拍只剩 16b+7b 浅加法。
//   打一拍对流协议无损(tready 恒 1, 无反压), 只是判决整体后移一拍。
// 输出经 2FF 镜像到 user 域(axi_lite_regs 采样侧)。
//=============================================================================
`timescale 1ns / 1ps

module dma_sink (
    input  wire         clk,          // ui_clk 300 MHz (与 M_AXIS 同域)
    input  wire         rst_n,
    input  wire         clk_user,     // 输出镜像域
    input  wire         rst_user_n,

    input  wire [511:0] s_tdata,
    input  wire [63:0]  s_tkeep,
    input  wire         s_tlast,
    input  wire         s_tvalid,
    output wire         s_tready,

    output wire [31:0]  q0,
    output wire [31:0]  q1,
    output wire [31:0]  q2
);

    assign s_tready = 1'b1;

    function [6:0] popcnt64(input [63:0] v);
        integer i;
        begin
            popcnt64 = 7'd0;
            for (i = 0; i < 64; i = i + 1)
                if (v[i]) popcnt64 = popcnt64 + 7'd1;
        end
    endfunction

    // ---- 输入打一拍(时序修复): FSM 消费 d_* (延迟一拍的流) ----
    reg [511:0] data_q;
    reg [63:0]  keep_q;
    reg [6:0]   keep_n;     // keep_q 的 popcount(锥终结点)
    reg         last_q, valid_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_q <= 512'd0; keep_q <= 64'd0; last_q <= 1'b0; valid_q <= 1'b0;
            keep_n <= 7'd0;
        end else begin
            valid_q <= s_tvalid;
            if (s_tvalid) begin
                data_q <= s_tdata;
                keep_q <= s_tkeep;
                last_q <= s_tlast;
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) keep_n <= 7'd0;
        else if (s_tvalid) keep_n <= popcnt64(s_tkeep);   // 与 keep_q 同拍
    end

    localparam ST_IDLE = 1'b0, ST_RUN = 1'b1;
    reg         st;
    reg [31:0]  q0i, q1i, q2i;
    reg [15:0]  beats, bytes;
    reg [31:0]  first_beat;
    reg [7:0]   done_cnt;
    reg         tlast_seen, busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; beats <= 16'd0; bytes <= 16'd0; first_beat <= 32'd0;
            done_cnt <= 8'd0; tlast_seen <= 1'b0; busy <= 1'b0;
            q0i <= 32'd0; q1i <= 32'd0; q2i <= 32'd0;
        end else begin
            busy <= (st == ST_RUN);
            case (st)
            ST_IDLE: begin
                if (valid_q) begin
                    first_beat <= data_q[31:0];
                    if (last_q) begin              // 单拍帧
                        q0i <= {16'd1, {9'd0, keep_n}};
                        q1i <= data_q[31:0];
                        done_cnt   <= done_cnt + 8'd1;
                        tlast_seen <= 1'b1;
                    end else begin
                        beats      <= 16'd1;
                        bytes      <= {9'd0, keep_n};
                        tlast_seen <= 1'b0;
                        st         <= ST_RUN;
                    end
                end
            end
            ST_RUN: begin
                if (valid_q) begin
                    if (last_q) begin
                        q0i <= {beats + 16'd1, bytes + {9'd0, keep_n}};
                        q1i <= first_beat;
                        done_cnt   <= done_cnt + 8'd1;
                        tlast_seen <= 1'b1;
                        st         <= ST_IDLE;
                    end else begin
                        beats <= beats + 16'd1;
                        bytes <= bytes + {9'd0, keep_n};
                    end
                end
            end
            default: st <= ST_IDLE;
            endcase
            q2i <= {done_cnt, tlast_seen, busy, 22'd0};   // 8+1+1+22=32
        end
    end

    // ---- 输出 2FF 镜像 (ui -> user; 值准静态) ----
    reg [31:0] q0_s1, q0_s2, q1_s1, q1_s2, q2_s1, q2_s2;
    always @(posedge clk_user or negedge rst_user_n) begin
        if (!rst_user_n) begin
            q0_s1 <= 32'd0; q0_s2 <= 32'd0;
            q1_s1 <= 32'd0; q1_s2 <= 32'd0;
            q2_s1 <= 32'd0; q2_s2 <= 32'd0;
        end else begin
            q0_s1 <= q0i; q0_s2 <= q0_s1;
            q1_s1 <= q1i; q1_s2 <= q1_s1;
            q2_s1 <= q2i; q2_s2 <= q2_s1;
        end
    end
    assign q0 = q0_s2;
    assign q1 = q1_s2;
    assign q2 = q2_s2;

endmodule
