//=============================================================================
// dma_rd_shim_v2.v — B3-1b shim v2 (2026-10-15): len 由 frame_len 端口提供。
// v1->v2 更名原因: 板上取证发现综合 worker 对旧文件名缓存了旧内容(build13 产物
// len_cnt×365/frame_len×0, 尽管日志行号=新文件) —— 更名彻底绕开文件级缓存。
// 长度语义: len 不再逐字节计数(网表取证: 计数 CE 锥被综合器改写, 坑 #47 第四案),
// 直接引用软件下发的 frame_len(同 tag_slot 稳定期先例)。

//-----------------------------------------------------------------------------
// 职责: 接替 axi4_master_bridge 读引擎的"拆包"部分 —— DMA MM2S 从 DDR 槽区
//   读出的 512b 流, 经本件还原成 frame_mem_if 期望的两路输出:
//     1) 字节流 rf_wr_en/rf_wr_data (1 字节/拍, 与原桥 R_UNPACK 同速率)
//     2) 读描述符 rdesc_wr_data = {1'b0, len[15:0], slot[7:0]} (TLAST 时发)
//   长度语义: ★2026-10-15 网表取证定案 (坑 #47 第四案): 逐字节计数器的
//   CE 锥在板上被综合器改写 (真值表与 RTL 语义不符, ST_UNPK 之外也计数,
//   板上现象 = rdesc.len 每帧 +1 而非帧长)。修法照 dma_sink 先例: **计数锥
//   彻底退出逐字节路径** —— 帧长由 frame_len 端口直接提供 (软件下发的
//   dma_req_len, R_DRET 全程稳定, 同 tag_slot 的既有先例), 结算时引用。
//   TKEEP 仅门控发射(哪些 lane 有效), 不再参与长度计算。
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

module dma_rd_shim_v2 #(
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

    // ---- 帧完成 out (TLAST 结算的下一拍, 单拍) ----
    // ★2026-10-15 结构重构成 v3 语义: rdesc/tag 全部移出 shim —— 板上网表取证
    //   (build12/13/14 三版位流) 证实本模块的 rdesc/tag 输出在综合后反复损坏
    //   (len_cnt 计数 CE 改写 / tag_slot=0 / frame_len↔slot 错位, 坑 #47 家族
    //   第四案多形态)。描述符改由桥在 frame_done 时用自身寄存器发射 (与硬件
    //   路径 R_FIN 同款结构, 板上久经验证)。
    output reg          frame_done,

    // ---- 帧长 in (软件下发, 帧全程稳定; 仅供桥侧参考, shim 不再用) ----
    input  wire [15:0]  frame_len,
    input  wire [7:0]   tag_slot,
    input  wire         tag_valid
);

    localparam [15:0] DROP_N = DROP_BYTES[15:0];

    localparam ST_IDLE = 2'd0;   // 等流首拍
    localparam ST_UNPK = 2'd1;   // 拆当前拍 (逐字节)
    localparam ST_LAST = 2'd2;   // 尾字节 + frame_done 结算

    reg [1:0]   st;
    reg [511:0] beat_data;
    reg [63:0]  beat_keep;
    reg         beat_last;
    reg [5:0]   bi;              // 当前拍内字节下标 0..63
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
            st <= ST_IDLE; rf_wr_en <= 1'b0; frame_done <= 1'b0;
            beat_data <= 512'd0; beat_keep <= 64'd0; beat_last <= 1'b0;
            bi <= 6'd0; drop_left <= 16'd0;
            drop_busy <= 1'b0; in_frame <= 1'b0;
            rf_wr_data <= 8'd0;
        end else begin
            rf_wr_en   <= 1'b0;
            frame_done <= 1'b0;
            case (st)
            //-------------------------------------------------------------- idle
            ST_IDLE: begin
                // len 只在"帧首拍"清零(in_frame 标志) —— 帧中 beats 之间的
                // IDLE 过渡(等下一拍)绝不能清, 否则多拍帧只剩尾拍计数。
                if (s_tvalid) begin
                    if (!in_frame) begin
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
                // 帧完成脉冲 (描述符由桥发射: {0, frame_len, tag_slot})
                frame_done   <= 1'b1;
                in_frame     <= 1'b0;          // 帧边界: 下一帧重新计长
                st           <= ST_IDLE;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
