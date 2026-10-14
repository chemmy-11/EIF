//=============================================================================
// dma_rd_shim.v — AXI4-Stream(512b) → 字节流 + 读描述符（prj11 B3-1b，ui_clk）
//-----------------------------------------------------------------------------
// 职责: 接替 axi4_master_bridge 读引擎的"拆包"部分 —— DMA MM2S 从 DDR 槽区
//   读出的 512b 流, 经本件还原成 frame_mem_if 期望的两路输出:
//     1) 字节流 rf_wr_en/rf_wr_data (1 字节/拍, 与原桥 R_UNPACK 同速率)
//     2) 读描述符 rdesc_wr_data = {1'b0, len[15:0], slot[7:0]} (TLAST 时发)
//   长度语义: **按 TKEEP 计** —— 尾拍有效字节 = popcount(tkeep), 不是整 64,
//   否则帧长非 64 倍数时会拖尾 (设计决策 3)。
//
// ★前导丢弃 DROP_BYTES (2026-10-13 板上实证):
//   DMA 读窗口起点比帧首字节早 DROP_BYTES 字节。板上两族独立帧逐字节反推,
//   确认 DROP_BYTES = 50 (0x32):
//     · 载荷族 build_payload: 槽108 seq=70020, 读 SA=base+0x40 得载荷字节
//       [14..17]; 由 payload[i]=(i*37+(seq&0xFFFF)*131+63)&0xFF 复算得
//       0xD1 0xF6 0x1B 0x40 == 实测 0x401bf6d1 ✓ (槽111/117 同偏移)
//     · 特征帧 byte[i]=(i>>2): 槽111 在 base+{64,128,...,448} 共 8 点全部满足
//       stream[0]=feat[(SA-base)-50] ✓ (偏移 51 会得 3,3,3,4, 与实测 3,3,4,4 矛盾)
//   "对齐读 SA=SLOT_BASE、LEN=帧长+DROP_BYTES" 配合本丢弃, 无论该 50 发生在
//   读地址侧还是槽存储侧(两者对按帧读回完全等价 = 纯字节窗口平移), 输出都
//   正好是帧字节 0..len-1。丢弃按"有效(TKEEP=1)字节"计数, 只在帧首生效。
//
// 槽号从哪来: 流本身不带槽号 —— 由描述符写入方(下发的命令侧)经 tag_fifo
//   提供: tag_valid/tag_slot 推入, 本件在 TLAST 结算时 pop 一次。
//   direct 模式 DMA 单笔在飞 -> 顺序即配对顺序, 无需 ID 匹配。
//
// 节拍: 每个流拍需 1 + popcount(tkeep) 拍拆包(地址翻转 + 字节压入), tready
//   在拆包期间为 0(内部 beat 寄存器缓冲当前拍)。82.67k fps 预算 12.3us vs
//   最坏 1538B 帧 ~5.2us(24 拍 × 64 + 首拍), 余量 2.3x。
//=============================================================================
`timescale 1ns / 1ps

module dma_rd_shim #(
    // 帧首丢弃的有效字节数 (0 = 不丢, 兼容既有单元回归 shim_tb)
    parameter integer DROP_BYTES = 0
)(
    input  wire         clk,
    input  wire         rst_n,

    // ---- AXI4-Stream S (512b) ----
    input  wire [511:0] s_tdata,
    input  wire [63:0]  s_tkeep,
    input  wire         s_tlast,
    input  wire         s_tvalid,
    output wire         s_tready,

    // ---- 字节流 out (1/拍) ----
    output reg          rf_wr_en,
    output reg  [7:0]   rf_wr_data,

    // ---- 读描述符 out (TLAST 结算) ----
    output reg          rdesc_wr_en,
    output reg  [24:0]  rdesc_wr_data,    // {1'b0, len[15:0], slot[7:0]}

    // ---- 槽号 tag in (描述符写入方推送; TLAST 时 pop) ----
    input  wire [7:0]   tag_slot,
    input  wire         tag_valid,
    output reg          tag_pop
);

    localparam [15:0] DROP_N = DROP_BYTES[15:0];

    localparam ST_IDLE = 2'd0;   // 等流首拍
    localparam ST_UNPK = 2'd1;   // 拆当前拍 (逐字节)
    localparam ST_LAST = 2'd2;   // 尾字节 + 描述符结算

    reg [1:0]   st;
    reg [511:0] beat_data;
    reg [63:0]  beat_keep;
    reg         beat_last;
    reg [5:0]   bi;              // 当前拍内字节下标 0..63
    reg [15:0]  len_cnt;         // 本帧累计字节数(已扣前导)
    reg [15:0]  drop_left;       // 本帧尚需丢弃的前导字节数
    reg         drop_busy;       // 丢弃进行中(寄存器标志 —— 2026-10-15 板场次:
                                 // 16 位比较直连字节路径在 DROP=8 常量下触发
                                 // Vivado 2023.1 "Mimic Skeleton" 综合崩溃,
                                 // 2/2 复现; W5 R_PRE2 同位置同病, 结构扰动绕开)
    reg         in_frame;        // 帧内标志: 从首拍置位到 TLAST 结算清零

    assign s_tready = (st == ST_IDLE);

    // ★2026-10-14 时序修正: 去 64 位 popcount 归约锥 (keep_n = popcount-1 参与
    //   bi 的下一状态与发射判断 -> 9 级 LUT 锥 @300MHz, WNS -0.339 被门限拒;
    //   与坑 #47 同族: 宽归约+比较锥既可能被静默误优化又必然吃时序)。
    //   改为"每拍固定扫描 64 个 lane、TKEEP 逐 lane 门控发射": 尾拍多扫几拍
    //   (最坏 24 拍 × 64 = 1536 拍 ≈ 5.2us @300MHz, 仍 ≪ 12.3us 帧预算),
    //   锥退化为 bi 计数 + lane 选择, 与本桥 R_UNPACK 同构。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; rf_wr_en <= 1'b0; rdesc_wr_en <= 1'b0; tag_pop <= 1'b0;
            beat_data <= 512'd0; beat_keep <= 64'd0; beat_last <= 1'b0;
            bi <= 6'd0; len_cnt <= 16'd0; drop_left <= 16'd0;
            drop_busy <= 1'b0; in_frame <= 1'b0;
            rf_wr_data <= 8'd0; rdesc_wr_data <= 25'd0;
        end else begin
            rf_wr_en   <= 1'b0;
            rdesc_wr_en <= 1'b0;
            tag_pop    <= 1'b0;
            case (st)
            //-------------------------------------------------------------- idle
            ST_IDLE: begin
                // len 只在"帧首拍"清零(in_frame 标志) —— 帧中 beats 之间的
                // IDLE 过渡(等下一拍)绝不能清, 否则多拍帧只剩尾拍计数。
                if (s_tvalid) begin
                    if (!in_frame) begin
                        len_cnt   <= 16'd0;
                        drop_left <= DROP_N;    // 帧首: 重置前导丢弃预算
                        drop_busy <= (DROP_N != 16'd0);
                    end
                    beat_data <= s_tdata;
                    beat_keep <= s_tkeep;
                    beat_last <= s_tlast;
                    bi        <= 6'd0;
                    in_frame  <= 1'b1;
                    st        <= ST_UNPK;
                end
            end
            //-------------------------------------------------------- unpack
            ST_UNPK: begin
                if (beat_keep[bi]) begin
                    if (drop_busy) begin
                        drop_left <= drop_left - 16'd1;   // 前导: 丢弃不发射
                        if (drop_left == 16'd1)           // 这是最后一拍丢弃
                            drop_busy <= 1'b0;
                    end else begin
                        rf_wr_en   <= 1'b1;
                        rf_wr_data <= beat_data[bi*8 +: 8];
                        len_cnt    <= len_cnt + 16'd1;
                    end
                end
                // 本拍 64 个 lane 扫完 -> 拍边界 (TKEEP 只门控发射, 不参与拍边界)
                if (bi == 6'd63) begin
                    if (beat_last) st <= ST_LAST;      // 拍末=帧末 -> 结算
                    else begin
                        bi <= 6'd0;
                        st <= ST_IDLE;                 // 回收下一拍
                    end
                end else begin
                    bi <= bi + 6'd1;
                end
            end
            //--------------------------------------------------- last settle
            ST_LAST: begin
                // 描述符在进入本态的下一拍发出 (len 已含尾字节, 已扣前导)
                rdesc_wr_en  <= 1'b1;
                rdesc_wr_data <= {1'b0, len_cnt, tag_slot};
                tag_pop      <= 1'b1;
                in_frame     <= 1'b0;          // 帧边界: 下一帧重新计长
                st           <= ST_IDLE;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
