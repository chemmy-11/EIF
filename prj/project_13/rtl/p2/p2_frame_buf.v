//=============================================================================
// p2_frame_buf.v — prj13 P2 integration: single-clock frame-granular elasticity
//-----------------------------------------------------------------------------
// 为什么需要它（不是"多此一举"的缓冲）：
//   P2 链路两侧的**生产者都不支持反压** ——
//     · 以太网 MAC 侧：gmii_rxd/gmii_rx_dv 按线速到达，不能暂停；
//     · Aurora 解包侧：axis_word_unpack 的 out_valid 没有 ready 口
//       （实测 rtl/axis_word_unpack.v:163-193：帧内零空拍，帧间恰好 1 拍 gap）。
//   而 P2 的三个单元件是 valid/ready 字节流（ipv4_packet_extract 会整帧
//   收完再发、eth_rewrap 要先吐 14 B 头），直接相连必然**在帧中间丢字节**
//   —— 那是"残帧上电路"，比丢整帧恶劣得多。
//   本模块做的正是：**整帧粒度**的弹性缓冲 —— 要么整帧收下，要么整帧丢弃并
//   计数（o_wr_drop_cnt），绝不留半帧。
//
// ★为什么还要在缓冲里"顺手记以太头"（o_rd_eth_dst/o_rd_eth_type）：
//   P2 判决（local_steer）需要 eth_dst/eth_type，而这两个字段只在帧首 14 B 里。
//   若在缓冲**外面**用一条旁路嗅探器去抓，第二帧的帧首会在第一帧还在读侧的
//   时候把嗅探寄存器覆盖掉 —— 背靠背帧（集成 TB 的 I04）就会误判。
//   所以侧带信息必须**跟帧走**：写侧按字节偏移锁存，帧尾落到该 bank，
//   读侧起帧时取出，与数据同寿命。
//
// 结构：2 bank 乒乓（每 bank 2^AW 字节），单时钟域，指针用 toggle 对
//   （wr_tog/rd_tog 各自单驱动，绝不多驱动 —— 坑账本 #25）。
//
// 语义：
//   写侧（wr_en 有效字节流）：wr_en 上升=帧首，下降=帧尾（与 frame_fifo_pump
//     同口径，可直接接 gmii_rx_dv / unpack_en）。
//   读侧：valid/ready，sop 在首字节、eop 在末字节；只有 rd_ready 才推进。
//   超长（>= 2^AW）强制丢弃整帧（不截断）。
//
// 编码：Verilog-2001，单时钟，异步低有效复位。
//=============================================================================
`timescale 1ns / 1ps

module p2_frame_buf #(
    parameter integer AW = 11                    // bank 深度 = 2^AW（默认 2048 B）
)(
    input  wire        clk,
    input  wire        rst_n,
    // ---- 写侧：字节 + 使能（en 的上升/下降界定帧）----
    input  wire [7:0]  wr_data,
    input  wire        wr_en,
    output reg  [15:0] o_wr_frame_cnt,
    output reg  [15:0] o_wr_drop_cnt,
    // ---- 读侧：valid/ready 字节流 ----
    output reg  [7:0]  rd_data,
    output reg         rd_valid,
    output reg         rd_sop,
    output reg         rd_eop,
    input  wire        rd_ready,
    output reg  [15:0] o_rd_frame_cnt,
    // ---- 侧带：本帧的以太头（起帧时有效，保持到 eop）----
    output reg  [47:0] o_rd_eth_dst,
    output reg  [15:0] o_rd_eth_type,
    output wire [1:0]  o_bank_busy                 // {bank1,bank0} 占用观测
);

    localparam integer BD = (1 << AW);

    reg [7:0] ram [0:2*BD-1];

    reg  [1:0]  wr_tog, rd_tog;
    reg         wr_bank, rd_bank;
    reg  [AW:0] wr_cnt;                            // 帧内字节数（AW+1 位防溢出）
    reg  [AW-1:0] wr_addr, rd_addr;
    reg  [15:0] len0, len1, rd_len;
    reg  [15:0] rd_cnt;
    reg         wr_active, wr_dropping;
    reg         wr_toobig;                         // 本帧超 bank 容量 -> 整帧丢弃
    reg         wr_dv_d;

    // 侧带按 bank 存储（与 len 同寿命）
    reg  [47:0] sd_dst0, sd_dst1;
    reg  [15:0] sd_typ0, sd_typ1;
    reg  [47:0] sn_dst;                            // 写侧嗅探累加器
    reg  [15:0] sn_typ;

    wire wr_start = wr_en & ~wr_dv_d;
    wire wr_end   = ~wr_en &  wr_dv_d;
    wire bank_free= (wr_tog[wr_bank] == rd_tog[wr_bank]);
    wire accept   = wr_start & ~wr_active & ~wr_dropping & bank_free;
    // 容量边界（2026-11-08 修，由 p2-rtl 静态复核查出）：
    //   wr_cnt 是"下一个待写字节序号"，合法下标 0..BD-1，所以满的条件是 wr_cnt>=BD。
    //   原写法 `>= BD-1` 会少存 1 字节，而且 wr_cnt 被掐住不再自增、帧尾仍把
    //   2047 B 的**半帧**当完整帧发布（读侧截断，违反"零泄漏"）。现在改为：
    //   超容量 -> wr_toobig 置位，帧尾只进 o_wr_drop_cnt，不发布、不翻转 bank。
    wire ovf      = (wr_cnt >= BD[AW:0]);
    wire byte_we  = wr_en & (wr_active | accept) & ~ovf;

    assign o_bank_busy = {wr_tog[1]^rd_tog[1], wr_tog[0]^rd_tog[0]};

    //-------------------------------------------------------------------------
    // 写侧（指针与计数在此块唯一驱动；RAM 数据在独立块 —— 坑 #25/#33）
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_tog <= 2'b00; wr_bank <= 1'b0; wr_cnt <= {(AW+1){1'b0}};
            wr_addr <= {AW{1'b0}}; len0 <= 16'd0; len1 <= 16'd0;
            wr_active <= 1'b0; wr_dropping <= 1'b0; wr_dv_d <= 1'b0;
            wr_toobig <= 1'b0;
            o_wr_frame_cnt <= 16'd0; o_wr_drop_cnt <= 16'd0;
            sd_dst0 <= 48'd0; sd_dst1 <= 48'd0; sd_typ0 <= 16'd0; sd_typ1 <= 16'd0;
            sn_dst <= 48'd0; sn_typ <= 16'd0;
        end else begin
            wr_dv_d <= wr_en;

            if (byte_we) begin
                wr_addr <= wr_addr + 1'b1;
                wr_cnt  <= wr_cnt  + 1'b1;
            end else if (wr_en & ovf & (wr_active | accept)) begin
                wr_toobig <= 1'b1;                 // 超容量：整帧丢弃，绝不留半帧
            end

            // 以太头嗅探（按帧内偏移；wr_cnt 是"下一个待写字节"的序号）
            if (wr_en) begin
                if (wr_cnt == {(AW+1){1'b0}})          sn_dst <= {40'd0, wr_data};
                else if (wr_cnt <= 6'd5)               sn_dst <= {sn_dst[39:0], wr_data};
                if (wr_cnt == 6'd12)                   sn_typ[15:8] <= wr_data;
                if (wr_cnt == 6'd13)                   sn_typ[7:0]  <= wr_data;
            end

            if (wr_start) begin
                if (accept) wr_active   <= 1'b1;
                else        wr_dropping <= 1'b1;
            end

            if (wr_end) begin
                if (wr_active & ~wr_toobig) begin
                    // 正常提交：发布该 bank（侧带与长度同寿命）
                    if (wr_bank == 1'b0) begin
                        len0 <= wr_cnt; sd_dst0 <= sn_dst; sd_typ0 <= sn_typ;
                    end else begin
                        len1 <= wr_cnt; sd_dst1 <= sn_dst; sd_typ1 <= sn_typ;
                    end
                    wr_tog[wr_bank] <= ~wr_tog[wr_bank];
                    wr_bank         <= ~wr_bank;
                    o_wr_frame_cnt  <= o_wr_frame_cnt + 16'd1;
                end else if (wr_active & wr_toobig) begin
                    // 超容量：整帧丢弃，不发布、不翻 bank（bank 仍空闲可复用）
                    o_wr_drop_cnt <= o_wr_drop_cnt + 16'd1;
                end
                if (wr_dropping) begin
                    o_wr_drop_cnt <= o_wr_drop_cnt + 16'd1;
                    wr_dropping   <= 1'b0;
                end
                wr_active <= 1'b0;
                wr_toobig <= 1'b0;
                wr_cnt    <= {(AW+1){1'b0}};
                wr_addr   <= {AW{1'b0}};
            end
        end
    end

    // 独立 always 块：只写数据（RAM 推断，坑 #33）
    always @(posedge clk) begin
        if (byte_we) ram[{wr_bank, wr_addr}] <= wr_data;
    end

    //-------------------------------------------------------------------------
    // 读侧（valid/ready）
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data <= 8'd0; rd_valid <= 1'b0; rd_sop <= 1'b0; rd_eop <= 1'b0;
            rd_addr <= {AW{1'b0}}; rd_len <= 16'd0; rd_cnt <= 16'd0;
            rd_tog <= 2'b00; rd_bank <= 1'b0; o_rd_frame_cnt <= 16'd0;
            o_rd_eth_dst <= 48'd0; o_rd_eth_type <= 16'd0;
        end else if (!rd_valid) begin
            // 有帧可读 => 起一帧（侧带与数据同拍取出）
            if (wr_tog[rd_bank] != rd_tog[rd_bank]) begin
                rd_len   <= rd_bank ? len1 : len0;
                rd_addr  <= {AW{1'b0}};
                rd_cnt   <= 16'd0;
                rd_data  <= ram[{rd_bank, {AW{1'b0}}}];
                rd_valid <= 1'b1;
                rd_sop   <= 1'b1;
                rd_eop   <= ((rd_bank ? len1 : len0) == 16'd1);
                o_rd_eth_dst <= rd_bank ? sd_dst1 : sd_dst0;
                o_rd_eth_type<= rd_bank ? sd_typ1 : sd_typ0;
            end
        end else if (rd_ready) begin
            if (rd_cnt + 16'd1 >= rd_len) begin
                // 帧尾已交出：释放 bank
                rd_valid <= 1'b0; rd_sop <= 1'b0; rd_eop <= 1'b0;
                rd_tog[rd_bank] <= ~rd_tog[rd_bank];
                rd_bank         <= ~rd_bank;
                o_rd_frame_cnt  <= o_rd_frame_cnt + 16'd1;
            end else begin
                rd_cnt   <= rd_cnt + 16'd1;
                rd_addr  <= rd_addr + 1'b1;
                rd_data  <= ram[{rd_bank, rd_addr + 1'b1}];
                rd_sop   <= 1'b0;
                rd_eop   <= ((rd_cnt + 16'd2) == rd_len);
            end
        end
    end

endmodule
