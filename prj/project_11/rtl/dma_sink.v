//=============================================================================
// dma_sink.v — AXI4-Stream 捕获器（prj11 B3-1a 冒烟判据数据源，ui_clk 域）
//-----------------------------------------------------------------------------
// 用途: axi_dma MM2S 从 DDR 槽区读出的 512 bit 流, 在换层(B3-1b 接 shim)之前
//   先由本件捕获, 一次验完「时钟域(300M) + 512b + 地址映射 + TKEEP 语义」:
//     q0 = {beats[15:0], full_beats[15:0]}  总拍数 / "TKEEP 全 1"的拍数
//     q1 = 首拍低 32 bit                    (PC 知道槽内容 -> 直接比对)
//     q2 = {done_cnt, tlast_seen, busy, saw_keep, tail_keep[7:0], 13'd0}
//          saw_keep = 任一拍 TKEEP≠0 (粘滞); tail_keep = TLAST 拍 keep 低 8 位
//
// ★★ 2026-10-13 重写(板上实证): 原版用 64 位 popcount(function+for) 计字节,
//   Vivado 2023.1 综合在该锥上发生 netlist 名冲突([Synth 8-6858/6859] x14,
//   "multi-driven net Q"), **keep_n 寄存器被常量驱动顶掉** -> bytes 恒 0,
//   整条 tkeep 链被删(netlist 里 dma_tkeep 无网络) -> 板上冒烟 q0 恒
//   {1,0}/{64,0}、q1 恒等、DMA 状态却全部正常。教训: 宽 popcount/归约锥
//   在"事件结算拍"路径上不仅有时序风险(#44 同族), 还可能触发工具级
//   静默误优化 —— 改为"全有效拍计数 + 尾拍采样 + 粘滞位", 全部合成友好。
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

    // ---- 输入打一拍(时序纪律): FSM 消费延迟一拍的流 ----
    reg [31:0]  data_q;        // 只用低 32 位 -> 只寄存 32
    reg [7:0]   tail_keep_q;   // keep 低字节 (尾拍长度证据)
    reg         keep_any_q;    // 本拍 keep != 0
    reg         keep_full_q;   // 本拍 keep == 全 1
    reg         last_q, valid_q;

    wire keep_full_c = (s_tkeep == 64'hFFFF_FFFF_FFFF_FFFF);
    wire keep_any_c  = |s_tkeep;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_q <= 32'd0; tail_keep_q <= 8'd0;
            keep_any_q <= 1'b0; keep_full_q <= 1'b0;
            last_q <= 1'b0; valid_q <= 1'b0;
        end else begin
            valid_q <= s_tvalid;
            if (s_tvalid) begin
                data_q      <= s_tdata[31:0];
                tail_keep_q <= s_tkeep[7:0];
                keep_any_q  <= keep_any_c;
                keep_full_q <= keep_full_c;
                last_q      <= s_tlast;
            end
        end
    end

    localparam ST_IDLE = 1'b0, ST_RUN = 1'b1;
    reg         st;
    reg [31:0]  q0i, q1i, q2i;
    reg [15:0]  beats, full_beats;
    reg [31:0]  first_beat;
    reg [7:0]   done_cnt;
    reg         tlast_seen, busy, saw_keep;
    reg [7:0]   tail_keep_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; beats <= 16'd0; full_beats <= 16'd0; first_beat <= 32'd0;
            done_cnt <= 8'd0; tlast_seen <= 1'b0; busy <= 1'b0;
            saw_keep <= 1'b0; tail_keep_r <= 1'b0;
            q0i <= 32'd0; q1i <= 32'd0; q2i <= 32'd0;
        end else begin
            busy <= (st == ST_RUN);
            if (valid_q && keep_any_q) saw_keep <= 1'b1;
            case (st)
            ST_IDLE: begin
                if (valid_q) begin
                    first_beat <= data_q;
                    if (last_q) begin              // 单拍帧
                        beats      <= 16'd1;
                        full_beats <= {15'd0, keep_full_q};
                        tail_keep_r <= tail_keep_q;
                        q0i <= {16'd1, {15'd0, keep_full_q}};
                        q1i <= data_q;
                        done_cnt   <= done_cnt + 8'd1;
                        tlast_seen <= 1'b1;
                    end else begin
                        beats      <= 16'd1;
                        full_beats <= {15'd0, keep_full_q};
                        tlast_seen <= 1'b0;
                        st         <= ST_RUN;
                    end
                end
            end
            ST_RUN: begin
                if (valid_q) begin
                    if (last_q) begin
                        q0i <= {beats + 16'd1, full_beats + {15'd0, keep_full_q}};
                        q1i <= first_beat;
                        tail_keep_r <= tail_keep_q;
                        done_cnt   <= done_cnt + 8'd1;
                        tlast_seen <= 1'b1;
                        st         <= ST_IDLE;
                    end else begin
                        beats      <= beats + 16'd1;
                        full_beats <= full_beats + {15'd0, keep_full_q};
                    end
                end
            end
            default: st <= ST_IDLE;
            endcase
            // q2 = {done[7:0], tlast_seen, busy, saw_keep, tail_keep[7:0], 13'd0}
            q2i <= {done_cnt, tlast_seen, busy, saw_keep, tail_keep_r, 13'd0};
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
