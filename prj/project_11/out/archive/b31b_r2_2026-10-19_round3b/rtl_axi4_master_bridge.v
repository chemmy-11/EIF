//=============================================================================
// axi4_master_bridge.v -- self-developed AXI4 512-bit master + slot manager
//                         prj10 W2 (memory-in-the-loop), ui_clk domain only
//-----------------------------------------------------------------------------
// WHY (design rationale, for the defence):
//  * AXI4 requires AWLEN with/before the write data, so a frame must be fully
//    known before its burst is issued. That is the project's proven
//    "store-and-forward a whole frame" policy (prj9 frame pump), not a new idea.
//  * 4KB slots: frame <= 1538 B -> <= 24 beats of 64 B <= 1536 B < 4096 B, so a
//    burst can NEVER cross an AXI 4KB boundary. No split logic is needed; the
//    simulation monitor checks the arithmetic anyway.
//  * The slot table (valid/len) is a single-clock (ui_clk) table; the frame side
//    only receives (len, slot) through the read descriptor FIFO. One clock per
//    table = no dual-domain table hazard.
//  * Hard gate: no AW/AR is issued until init_calib_complete is seen in THIS
//    clock domain (prj4 lesson: touching MIG before calibration hangs the FSM).
//
// SLOT POLICY (the "random read" contract, simulated in mem_bridge_tb.sv)
//   FULL[slot] : the slot holds a frame that has not been read yet.
//   write  : slot = wm[7:0]. If FULL[slot] -> REFUSE (stat_wr_stall++), the frame
//            is drained and discarded: an unread frame is NEVER overwritten.
//   read SEQ: serve rd_seq_slot (oldest unread), retire it, advance the pointer.
//   read RND: slot = command slot. Slot never written (cmd >= wm while wm < 256)
//            -> stat_ill_rd++ and clamp to wm-1. Clamped/commanded slot not FULL
//            (already read or empty) -> stat_ill_rd++ and a defined empty answer.
//            Random read of an unwritten slot is therefore DEFINED and COUNTED,
//            never undefined behaviour.
//-----------------------------------------------------------------------------
// W5 TIMING FIX (2026-10-07, first-principles re-diagnosis):
//   * Symptom: with a live cfg_mode the whole read-decision cone failed at
//     300 MHz (worst 25 paths all: u_rd_cmd/rd_bin -> uc_dout (FWFT *combinational*
//     RAM read!) -> in_range adder -> eff_slot mux -> full_bit/len_tab 256:1
//     lookup -> CE/D of stat_ill_rd / r_len / r_beats / rd_wr_data;
//     4.226 ns data path vs 3.333 ns budget, 5011 failing endpoints).
//   * Not an RND-only cone: cmd_rnd is the SELECT of that cone, so with a live
//     command FIFO it lights up in SEQ too. W4 had survived only because the
//     constant cfg_mode=1'b0 folded it away AND rd_seq_slot (a register) was the
//     surviving index -- at +0.008 ns, i.e. the underlying "reg-index -> len_tab
//     -> +63 adder -> r_beats" chain had ZERO margin even then.
//   * FINAL fix (2026-10-08, measured WNS -1.121 -> +0.001), three cuts:
//     1) R_IDLE prefetch: pop the command FIFO AND do the range math there
//        (c_eff/c_in_rng off cmd_slot + stat_wm), latching pre_eff/pre_in_rng;
//     2) R_PRE: the 256:1 table lookups (full_bit/len_tab/len_beats_tab) are
//        indexed by the REGISTER pre_eff only -- never the FIFO output;
//     3) len_beats_tab[]: beat budget precomputed at write-commit time, so the
//        read path does two PARALLEL lookups instead of len -> +63 adder.
//     PLUS: full_bit_q -- a keep-protected registered mirror of full_bit for
//     the CONTROL lookups (w_no_room / seq_ok / SEQ pointer scan), removing the
//     256:1 tree from both FSM CE cones. p_target_ok keeps the combinational
//     read (a slot committed this cycle must be seen FULL by the decision).
//     NOTE: without (* keep *), synthesis MERGES the mirror back into the tree
//     and the gain vanishes (measured: -0.121 both with and without).
//     W2/joint/arb/cmd regressions all green, counters byte-identical.
//   * rc_rd_en still gates on seq_ok (unchanged: its full_bit[rd_seq_slot]
//     index is a register, never on the bad path).
//=============================================================================
`timescale 1ns/1ps

module axi4_master_bridge #(
    parameter [31:0] SLOT_BASE = 32'h0010_0000,   // 4KB-aligned slot region
    parameter [15:0] MAX_LEN   = 16'd1538,        // prj9 frame contract (chunk=1466)
    // B3-1b: 0 = 不例化 DMA shim (桥② 等纯硬件读实例)。板上取证(10-15): 死 shim
    // (tvalid 恒 0 被全折叠) 在 DROP=8 常量下触发 2023.1 "Mimic Skeleton" 综合
    // 崩溃 3/3 复现 —— 与 W5 R_PRE2 同病; 消灭死实例即绕开。
    parameter        HAS_DMA   = 1
)(
    // ---------------- ui_clk / reset / MIG gate ----------------
    input  wire         clk,            // ui_clk  (~300 MHz per MIG report)
    input  wire         rst_n,          // ui_clk domain reset, active low
    input  wire         calib_ok,       // init_calib_complete, ui_clk domain

    // ---------------- write byte stream (ui side of user->ui FIFO) ----------------
    input  wire         wf_empty,
    input  wire [7:0]   wf_data,
    input  wire [12:0]  wf_level,       // conservative byte count available
    output wire         wf_rd_en,
    // ---------------- write descriptor (ui side of user->ui desc FIFO) ----------------
    input  wire         wd_empty,
    input  wire [15:0]  wd_data,        // frame length in bytes
    output wire         wd_rd_en,

    // ---------------- read byte stream (ui side of ui->user FIFO) ----------------
    // B3-1b: 端口改 wire —— 桥硬件读 FSM 与 DMA shim 两引擎在端口处合并
    // (互斥: engine=1 时读 FSM 自 R_PRE 起泊在 R_DRET, 不再驱动这两个口)。
    output wire         rf_wr_en,
    output wire [7:0]   rf_wr_data,
    // ---------------- read command (ui side of user->ui cmd FIFO) ----------------
    input  wire         rc_empty,
    input  wire [8:0]   rc_data,        // {rnd, slot[7:0]}
    output wire         rc_rd_en,
    // ---------------- read descriptor (ui side of ui->user desc FIFO) ----------------
    // B3-1b: wire 合并双引擎 (硬件读 FSM 与 shim 互斥, 永不同拍)
    output wire         rd_wr_en,
    output wire [24:0]  rd_wr_data,     // {none, len[15:0], slot[7:0]}

    // ---------------- status / counters (ui_clk domain, ILA-friendly) ----------------
    output reg  [15:0]  stat_wm,        // write watermark = frames committed
    output reg  [15:0]  stat_wr_frame,
    output reg  [15:0]  stat_wr_stall,  // refused: no free slot (unread frame preserved)
    output reg  [15:0]  stat_rd_frame,
    output reg  [15:0]  stat_ill_rd,    // illegal / out-of-range random read
    output reg  [15:0]  stat_noframe,   // SEQ read with no resident frame
    output reg  [15:0]  stat_bresp_err,
    output reg  [15:0]  stat_len_err,   // W2-review D2: frames refused for length
                                        // (>MAX_LEN / 0) + W_DRAIN bail-outs
    output reg  [8:0]   stat_outstanding, // slots currently FULL
    output reg  [7:0]   dbg_wr_slot,
    output reg  [7:0]   dbg_rd_slot,
    output reg  [31:0]  dbg_wr_cycles,  // ui cycles spent servicing a write frame
    output reg  [31:0]  dbg_rd_cycles,  // ui cycles spent servicing a read frame
    output reg  [31:0]  dbg_wr_beats,
    output reg  [31:0]  dbg_rd_beats,
    // ---- B3-0 (2026-10-12): MIG read/write latency observability ----
    // lat_w = cycles from AW handshake (this frame enters the commit queue)
    //         to that frame's B dequeue; lat_r = AR handshake to first R beat.
    // "Latest value" only -- min/max/distribution are computed on the READ
    // side (user domain) so the ui_clk critical cone gains nothing beyond two
    // 16b registers + an adder (96b of counters here once cost WNS -1.142).
    output reg  [15:0]  lat_w,
    output reg  [15:0]  lat_r,

    // ---------------- AXI4 master (512-bit data) ----------------
    output wire [31:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [511:0] m_axi_wdata,
    output wire [63:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output reg          m_axi_bready,
    output wire [31:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [511:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output reg          m_axi_rready,

    // ---------------- AXI4 sideband (W3/A1: required by the real MIG) ----------------
    // The real ddr4_0 exposes 37 s_axi signals; the W2 stand-in model only had 25.
    // Evidence (project_4/D1_MIG断点核查 §3.1): awid/arid are FUNCTIONAL inside the
    // MIG (r_channel.sv moves the ID into the read-transaction buffer and drives rid
    // from it); bid/rid may dangle but the PORTS must exist.
    output wire [3:0]   m_axi_awid,
    output wire [0:0]   m_axi_awlock,
    output wire [3:0]   m_axi_awcache,
    output wire [2:0]   m_axi_awprot,
    output wire [3:0]   m_axi_awqos,
    input  wire [3:0]   m_axi_bid,
    output wire [3:0]   m_axi_arid,
    output wire [0:0]   m_axi_arlock,
    output wire [3:0]   m_axi_arcache,
    output wire [2:0]   m_axi_arprot,
    output wire [3:0]   m_axi_arqos,
    input  wire [3:0]   m_axi_rid,

    // ---------------- B3-1b (2026-10-14): DMA 读引擎 ----------------
    // engine=1 时读请求不再由桥硬件读出, 而是锁进 dma_req_* 交给软件
    // (MicroBlaze 逐帧编程 axi_dma MM2S); shim 把 DMA 流拆包回灌本桥的
    // 读字节流/描述符输出, 退休与桥读 FSM 走同一套槽表/计数 (双引擎互斥,
    // 输出在端口处合并)。engine 与 AXI4-Stream 全部同步于本桥 clk (ui_clk)。
    input  wire         dma_engine,      // 0 = 桥硬件读, 1 = DMA+软件读
    input  wire [511:0] dma_s_tdata,     // ← axi_dma M_AXIS_MM2S (ui_clk 域)
    input  wire [63:0]  dma_s_tkeep,
    input  wire         dma_s_tlast,
    input  wire         dma_s_tvalid,
    output wire         dma_s_tready,
    output reg          dma_req_new,     // 电平: R_DRET 泊住期间=1 (请求待服务), 退休清 0
    output reg  [7:0]   dma_req_slot,
    output reg  [15:0]  dma_req_len,

    // ---------------- B3-2 (2026-10-17): DMA 写引擎 (S2MM) ----------------
    // 仅 HAS_DMA=1 生效 (桥①); HAS_DMA=0 (桥②) 时新输出全部常量 0、输入忽略,
    // 写路径仍为旧硬件 W FSM —— 坑 #55 纪律: 退役只在参数化分支内做。
    // 握手: 桥把 {pending,toggle,slot,len} 镜像给软核; 软核编程 S2MM 后翻 GO;
    //       完成由 axi_dma s2mm_introut (ui 域 2FF 后) 退休, 与旧 B 响应同语义。
    input  wire         dma_wr_go,           // ui 域: 软核 GO 翻转 (来自 lite_regs, 经 frame_mem_if 2FF)
    input  wire         dma_wr_ack,          // ui 域: 软核 fault 恢复确认翻转 (经 frame_mem_if 2FF)
    input  wire         s2mm_introut,        // ui 域: S2MM 完成中断 (已完成 100M->ui 2FF)
    output wire         dma_wr_req_toggle,   // 每发一笔新请求翻转
    output wire         dma_wr_req_pending,  // 请求待服务 (电平)
    output wire [7:0]   dma_wr_req_slot,
    output wire [15:0]  dma_wr_req_len,
    output wire [511:0] m_axis_s2mm_tdata,   // -> axi_dma S_AXIS_S2MM (ui_clk 域)
    output wire [63:0]  m_axis_s2mm_tkeep,
    output wire         m_axis_s2mm_tlast,
    output wire         m_axis_s2mm_tvalid,
    input  wire         m_axis_s2mm_tready,
    output wire [15:0]  stat_wr_timeout,     // 写请求超时/完成中断丢失计数 (ui 域)
    output wire         dbg_wr_fault,        // 粘滞: 流已发但完成中断超时 (不提交)
    output wire [7:0]   dbg_wr_last_slot,    // 最近一次分配的槽号 (取证)
    output wire [15:0]  dbg_wr_last_len,     // 最近一次提交的帧长 (取证)
    output wire [2:0]   dbg_wr_state         // 写引擎状态 (0=IDLE, 1=WAITGO, 2=STREAM, 3=PUSH, 4=WAITDONE, 5=DRAIN)
);

    //=========================================================================
    // 1. slot table (single clock domain: this one)
    //=========================================================================
    reg        full_bit [0:255];
    reg [15:0] len_tab  [0:255];
    // W5 timing fix (2026-10-07): precomputed beat budget per slot.
    // The old read path computed (len+63)>>6 at issue time -- that adder sat ON the
    // critical cone (W4 rpt: rd_seq_slot -> len_tab -> +63 -> r_beats was the +0.008
    // survivor). Precomputing at write-commit time removes it from the read path
    // entirely; r_len (16b lookup) and r_beats (6b lookup) become parallel lookups.
    reg [7:0]  len_beats_tab [0:255];
    reg [7:0]  rd_seq_slot;

    integer ti;
    reg        wr_commit;
    reg [7:0]  wr_commit_slot;
    reg [15:0] wr_commit_len;
    reg        rd_retire;
    reg [7:0]  rd_retire_slot;

    // ---- W5 final fix (2026-10-08): registered mirror of full_bit ----
    // The 256:1 read of full_bit is the last structural cost on the critical
    // paths (worst: full_bit[76] -> wst FSM, full_bit[5] -> rstate FSM). A
    // registered mirror removes the tree from the CE paths of both FSMs and
    // the SEQ pointer scan. FUNCTIONAL note: p_target_ok keeps the
    // COMBINATIONAL read (correctness: a slot committed this cycle must be
    // seen as FULL by the decision beat); only the "may I advance / may I
    // write" lookups use the 1-cycle-late mirror, where the effect is a
    // harmless 1-cycle bubble on retire->rewrite.
    (* keep = "true" *) reg full_bit_q [0:255];   // keep: 阻止综合器把镜像合并回组合树(实测会被合并, 时序收益归零)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ti = 0; ti < 256; ti = ti + 1) begin
                full_bit[ti] <= 1'b0;
                full_bit_q[ti] <= 1'b0;
                len_tab[ti]  <= 16'd0;
                len_beats_tab[ti] <= 8'd0;
            end
        end else begin
            if (wr_commit) begin
                full_bit[wr_commit_slot] <= 1'b1;
                full_bit_q[wr_commit_slot] <= 1'b1;
                len_tab [wr_commit_slot] <= wr_commit_len;
                len_beats_tab[wr_commit_slot] <= (wr_commit_len + 16'd63) >> 6;
            end
            if (rd_retire) begin
                full_bit[rd_retire_slot] <= 1'b0;   // retire wins on collision
                full_bit_q[rd_retire_slot] <= 1'b0;
            end
        end
    end

    //=========================================================================
    // 2. slot occupancy counter (single driver)
    //=========================================================================
    reg out_inc, out_dec;

    // W2-review D1 FIX -- ONE DRIVER PER REG.
    // out_inc is owned by the write FSM block (pulsed on commit in W_B),
    // out_dec is owned by the read FSM block (pulsed on retire in R_FIN).
    // They used to be cleared HERE as well, i.e. two procedural drivers on one
    // reg.  Vivado resolves that as
    //   CRITICAL WARNING [Synth 8-6859] multi-driven net on pin Q ...
    //   CRITICAL WARNING [Synth 8-6858] ... constant driver preserved, other
    //                                     driver is ignored
    // so on hardware out_inc/out_dec were tied to 0 and stat_outstanding stayed
    // FROZEN AT 0: no slot-full refusal, no SEQ pointer scan.  This block now
    // only CONSUMES the two pulses.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_outstanding <= 9'd0;
        end else begin
            if (out_inc & ~out_dec)      stat_outstanding <= stat_outstanding + 9'd1;
            else if (~out_inc & out_dec) stat_outstanding <= stat_outstanding - 9'd1;
        end
    end

    //=========================================================================
    // 3. write FSM
    //=========================================================================
    localparam W_IDLE=3'd0, W_WAIT=3'd1, W_AW=3'd2, W_FILL=3'd3,
               W_PUSH=3'd4, W_B=3'd5, W_DRAIN=3'd6;

    reg [2:0]   wst;
    reg [7:0]   w_slot, w_beat, w_bi;
    reg [7:0]   w_beats;
    reg [15:0]  w_len, w_pop;
    reg [11:0]  w_bidx;
    reg [511:0] w_data_r;
    reg [63:0]  w_strb_r;
    reg         w_beat_full, w_slotfull;
    reg [3:0]   w_drain_wait;           // W2-review D2: W_DRAIN liveness bound

    //=========================================================================
    // ★L2 FIX (2026-10-09, 上板实测 20.3us/帧固定开销) —— 写路径流水化
    //
    // 实测: 写槽路径每帧耗时 T = 20.3us + 11.9ns/字节, 其中 20.3us 是
    //   **每帧固定开销**; 且 RND 模式下把读路径与二级桥全部停掉, 速率
    //   一点没变(26.4k vs 26.5k fps) => 纯**延迟**受限, 不是带宽(MIG 占用仅 3-5%)。
    // 根因: 原 W_FSM 每帧必须走 W_B 等 DDR 写响应(BVALID)才回到 W_IDLE,
    //   于是每帧白白串行一个 Lw。AXI 允许同 ID 多笔 outstanding 且响应保序,
    //   所以把「出队提交」与「取下一帧」解耦即可把 Lw 藏在流水线里。
    // 做法: 最后一拍压 {槽号,长度} 入 4 深提交队列后立即回 W_IDLE;
    //   B 响应由本 always 块顶部的独立逻辑按序出队提交(FIFO 保序 = 同 ID 保序)。
    //=========================================================================
    reg [7:0]   cqs0, cqs1, cqs2, cqs3;   // 提交队列: 槽号(按序)
    reg [15:0]  cql0, cql1, cql2, cql3;   // 提交队列: 帧长(按序)
    reg [2:0]   cq_cnt;                   // 在途笔数 (0..4)
    wire        w_last_beat = (w_beat == (w_beats - 8'd1));

    //=========================================================================
    // ★W5 FIX (2026-10-08, 上板实测死锁) —— 写槽游标与提交计数解耦
    //
    // 缺陷现场（ILA 实测）：dbg_mem_u_wr=334（user 域"接受"帧数）而
    //   dbg_mem_wm=278（ui 域"提交"帧数），发散 56 帧；此后 READ_SLOT 命令
    //   全部被应答（通道正常）但读回 0 帧 —— 桥① 永久卡死。
    //
    // 机制：写槽号取自 stat_wm[7:0]，而 stat_wm 只在 B 响应（提交成功）时 +1。
    //   RND 模式下没有自动读，未被读走的槽会一直 FULL；一旦游标推进到某个
    //   未读满槽，w_no_room=1 → 该帧被拒 → stat_wm 不动 → **下一帧仍指向同一个
    //   满槽** → 全部被拒，永久卡死。同时 u_wr_frame（接受计数）继续 +1，
    //   两者发散 ⇒ 上位机按「写槽 = u_wr_frame mod 256」算出的槽号全错 ⇒
    //   连"该读哪个槽来解锁"都无法推断 ⇒ 不可恢复。
    //
    // 修法：槽号分配用**独立游标** wr_slot_ptr —— 每处理一帧（无论提交成功
    //   还是被拒）都 +1，因此 wr_slot_ptr ≡ user 域接受计数 u_wr_frame，
    //   槽号映射恢复正确；被拒帧仍按契约整帧丢弃、不覆盖未读槽（原槽字节
    //   仍可被读出），但游标不会停 ⇒ 死锁消除。
    //   stat_wm / stat_wr_frame 语义**不变**（仍是"已提交帧数"），W2 判据不受影响。
    //=========================================================================
    reg  [15:0] wr_slot_ptr;
    wire [7:0]  w_slot_next = wr_slot_ptr[7:0];
    wire        w_no_room   = full_bit_q[w_slot_next];  // W5: 1-cycle-late mirror (retire->rewrite bubble)
    wire        w_bad_len   = (wd_data == 16'd0) || (wd_data > MAX_LEN);
    wire        w_consume   = (wst == W_FILL) && !wf_empty && !w_beat_full;
    wire        w_drain_pop = (wst == W_DRAIN) && !wf_empty && (w_pop < w_len);

    // B3-2: 写引擎二选一 (结构常量分派; HAS_DMA=1 -> DMA/S2MM 新引擎, HAS_DMA=0 -> 旧硬件 W FSM)
    wire dma_wf_rd_en, dma_wd_rd_en;
    assign wf_rd_en = (HAS_DMA == 0) ? (w_consume | w_drain_pop)                  : dma_wf_rd_en;
    assign wd_rd_en = (HAS_DMA == 0) ? ((wst == W_IDLE) && calib_ok && !wd_empty) : dma_wd_rd_en;

    // ---- A1: sideband constants -------------------------------------------
    // awid/arid MUST be legal values. One ID per direction keeps the two streams
    // distinguishable inside the MIG's ID-ordered buffers; each FSM here keeps
    // exactly one burst in flight, so no re-order tracking is needed and bid/rid
    // are intentionally not compared (only qualified by VALID).
    assign m_axi_awid    = 4'h0;
    assign m_axi_arid    = 4'h1;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_awcache = 4'h0;   // Normal Non-cacheable, non-bufferable
    assign m_axi_arcache = 4'h0;
    assign m_axi_awprot  = 3'h0;   // unprivileged, data, secure
    assign m_axi_arprot  = 3'h0;
    assign m_axi_awqos   = 4'h0;
    assign m_axi_arqos   = 4'h0;

    //=========================================================================
    // 3b. B3-2 (2026-10-17): 写路径按 HAS_DMA 结构分派
    //   HAS_DMA=1 (桥①/u_mem): 旧硬件写 FSM 整体退役 -> S2MM 写引擎 (下一 generate 分支);
    //                          仲裁器 S00 已改接 axi_dma M_AXI_S2MM, 本桥 AXI 写口不再驱动。
    //   HAS_DMA=0 (桥②/u_mem2): 旧硬件写 FSM 原样 (文本零改动), 写 AXI 口照旧 -> 仲裁器 S01。
    //   坑 #55 纪律: 作用域用参数 (结构常量), 不用运行态位 (dma_engine); 桥② 两条路径禁改。
    //=========================================================================
    generate if (!HAS_DMA) begin : g_wr_hw
    // ---- 旧硬件写 FSM 的 AXI4 写口 (仅 HAS_DMA=0 例化) ----
    assign m_axi_awaddr  = SLOT_BASE + {w_slot, 12'b0};
    assign m_axi_awlen   = w_beats - 8'd1;
    assign m_axi_awsize  = 3'b110;      // 64 bytes per beat (512-bit)
    assign m_axi_awburst = 2'b01;       // INCR
    assign m_axi_wdata   = w_data_r;
    assign m_axi_wstrb   = w_strb_r;
    assign m_axi_wlast   = (w_beat == (w_beats - 8'd1));
    // ---- B3-2 新输出在 HAS_DMA=0 实例恒 0 (桥② 无 DMA shim/写引擎) ----
    assign dma_wr_req_toggle  = 1'b0;
    assign dma_wr_req_pending = 1'b0;
    assign dma_wr_req_slot    = 8'd0;
    assign dma_wr_req_len     = 16'd0;
    assign m_axis_s2mm_tdata  = 512'd0;
    assign m_axis_s2mm_tkeep  = 64'd0;
    assign m_axis_s2mm_tlast  = 1'b0;
    assign m_axis_s2mm_tvalid = 1'b0;
    assign stat_wr_timeout    = 16'd0;
    assign dbg_wr_fault       = 1'b0;
    assign dbg_wr_last_slot   = 8'd0;
    assign dbg_wr_last_len    = 16'd0;
    assign dbg_wr_state       = 3'd0;
    assign dma_wf_rd_en       = 1'b0;
    assign dma_wd_rd_en       = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wst <= W_IDLE; m_axi_awvalid <= 0; m_axi_wvalid <= 0; m_axi_bready <= 0;
            w_slot <= 0; w_beat <= 0; w_bi <= 0; w_beats <= 0; w_len <= 0; w_pop <= 0;
            w_bidx <= 0; w_data_r <= 0; w_strb_r <= 0; w_beat_full <= 0; w_slotfull <= 0;
            wr_commit <= 0; wr_commit_slot <= 0; wr_commit_len <= 0;
            stat_wm <= 0; stat_wr_frame <= 0; stat_wr_stall <= 0; stat_bresp_err <= 0;
            wr_slot_ptr <= 16'd0;
            stat_len_err <= 0; out_inc <= 1'b0; w_drain_wait <= 4'd0;
            dbg_wr_slot <= 0; dbg_wr_cycles <= 0; dbg_wr_beats <= 0;
            cqs0 <= 0; cqs1 <= 0; cqs2 <= 0; cqs3 <= 0;
            cql0 <= 0; cql1 <= 0; cql2 <= 0; cql3 <= 0; cq_cnt <= 3'd0;
        end else begin
            wr_commit <= 1'b0;
            out_inc   <= 1'b0;     // D1 FIX: this block is the ONLY driver of out_inc

            // ---- ★L2: B 响应出队提交(与写 FSM 解耦, 同 ID 保序 = FIFO 保序) ----
            m_axi_bready <= (cq_cnt != 3'd0);
            if (m_axi_bvalid && m_axi_bready) begin
                if (m_axi_bresp == 2'b00) begin
                    wr_commit      <= 1'b1;
                    wr_commit_slot <= cqs0;
                    wr_commit_len  <= cql0;
                    out_inc        <= 1'b1;
                    stat_wm        <= stat_wm + 16'd1;
                    stat_wr_frame  <= stat_wr_frame + 16'd1;
                end else begin
                    stat_bresp_err <= stat_bresp_err + 16'd1;
                end
                cqs0   <= cqs1; cqs1 <= cqs2; cqs2 <= cqs3;
                cql0   <= cql1; cql1 <= cql2; cql2 <= cql3;
                cq_cnt <= cq_cnt - 3'd1;
            end

            // byte assembly (only inside W_FILL); see W_PUSH for the handover
            if (w_consume) begin
                w_data_r[w_bi*8 +: 8] <= wf_data;
                w_strb_r[w_bi]        <= (w_bidx < w_len);
                w_bidx                <= w_bidx + 12'd1;
                // beat complete when 64 bytes are in OR the frame is exhausted
                // (tail beat: wstrb marks exactly the valid bytes)
                if ((w_bi == 8'd63) || ((w_bidx + 12'd1) == w_len)) w_beat_full <= 1'b1;
                else                                                 w_bi        <= w_bi + 8'd1;
            end
            if (wst != W_IDLE) dbg_wr_cycles <= dbg_wr_cycles + 32'd1;

            case (wst)
            //-----------------------------------------------------------------
            W_IDLE: begin
                m_axi_awvalid <= 1'b0;
                m_axi_wvalid  <= 1'b0;
                // ★L2: bready 改由顶部 B 出队逻辑统一驱动(此处不再清零)
                if (wd_rd_en) begin                       // descriptor pops this cycle
                    w_len     <= wd_data;
                    w_pop     <= 16'd0;
                    w_slot    <= w_slot_next;
                    w_slotfull<= w_no_room;
                    dbg_wr_slot <= w_slot_next;
                    w_beat <= 8'd0; w_bi <= 8'd0; w_bidx <= 12'd0;
                    w_beat_full <= 1'b0; w_data_r <= 0; w_strb_r <= 0;
                    // ★L2: 槽游标在**接收时**推进(流水化后提交是滞后的, 不能再由提交驱动,
                    //   否则连续多帧会抢同一个槽号)。被拒帧同样消耗槽号(沿用 W5 死锁修法)。
                    wr_slot_ptr <= wr_slot_ptr + 16'd1;
                    if (w_no_room | w_bad_len) begin
                        wst          <= W_DRAIN;          // refuse: never overwrite
                        w_drain_wait <= 4'd0;
                        if (w_bad_len) stat_len_err <= stat_len_err + 16'd1;
                    end else begin
                        w_beats <= (wd_data + 16'd63) >> 6;
                        wst     <= W_WAIT;
                    end
                end
            end
            //-----------------------------------------------------------------
            W_WAIT: begin   // wait until every byte of this frame is visible
                if (wf_level >= w_len[12:0]) wst <= W_AW;
            end
            //-----------------------------------------------------------------
            W_AW: begin
                m_axi_awvalid <= 1'b1;
                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                    wst <= W_FILL;
                end
            end
            //-----------------------------------------------------------------
            W_FILL: begin
                if (w_beat_full) wst <= W_PUSH;
            end
            //-----------------------------------------------------------------
            W_PUSH: begin
                // ★L2: 最后一拍发出前先确认提交队列有空位, 否则握停
                //   (拍一旦发出就必须有地方记录, 否则会重复发同一拍)
                if (w_last_beat && (cq_cnt == 3'd4)) begin
                    m_axi_wvalid <= 1'b0;
                end else begin
                m_axi_wvalid <= 1'b1;
                if (m_axi_wvalid && m_axi_wready) begin
                    m_axi_wvalid <= 1'b0;
                    w_beat_full  <= 1'b0;
                    w_bi         <= 8'd0;
                    // ---- A3 FIX (2026-10-01) ----------------------------------
                    // w_strb_r used to be cleared only at frame start, so on the
                    // TAIL beat the lanes beyond the frame length kept the previous
                    // beat's 1s: every frame whose length is not a multiple of 64 B
                    // asserted a full 64-lane WSTRB and wrote up to 63 stale bytes
                    // past the frame (measured: 64/64 beats "full", tail=0).
                    // Clearing the mask per beat makes the tail beat exactly
                    // (len mod 64) lanes wide; wstrb=0 lanes are not written by AXI.
                    w_strb_r     <= 64'd0;
                    dbg_wr_beats <= dbg_wr_beats + 32'd1;
                    if (w_last_beat) begin
                        // ★L2: 入提交队列后立即回 W_IDLE —— 不再等 BVALID
                        cqs3 <= cqs2; cqs2 <= cqs1; cqs1 <= cqs0; cqs0 <= w_slot;
                        cql3 <= cql2; cql2 <= cql1; cql1 <= cql0; cql0 <= w_len;
                        cq_cnt <= cq_cnt + 3'd1;
                        wst <= W_IDLE;
                    end else begin
                        w_beat <= w_beat + 8'd1;
                        wst    <= W_FILL;
                    end
                end
                end
            end
            //-----------------------------------------------------------------
            // ★L2: W_B 已停用(保留状态编码避免改动面扩大); B 响应由块顶部出队逻辑处理。
            W_B: begin
                // ★L2: 本状态已停用(不会再进入)。提交/出队全部由块顶部逻辑完成;
                //   槽游标改在 W_IDLE 接收时推进。保留编码仅为缩小改动面。
                wst <= W_IDLE;
            end
            //-----------------------------------------------------------------
            W_DRAIN: begin   // refused frame: pull its bytes back out of the FIFO
                if (w_pop >= w_len) begin
                    if (w_slotfull) stat_wr_stall <= stat_wr_stall + 16'd1;
                    // ★W5/L2: 被拒帧同样占用一个槽号(整帧丢弃、不覆盖未读槽), 否则
                    //   游标会停在满槽上造成永久卡死; 但自 L2 起推进点已统一到
                    //   W_IDLE 接收时, 此处**不得**再推(否则被拒帧推两次)。
                    w_drain_wait <= 4'd0;
                    wst          <= W_IDLE;
                end else if (w_drain_pop) begin
                    w_pop        <= w_pop + 16'd1;
                    w_drain_wait <= 4'd0;
                end else if (w_drain_wait == 4'd15) begin
                    // W2-review D2 FIX -- liveness.  The descriptor claims more
                    // bytes than the byte FIFO will ever supply (frame-side /
                    // descriptor desync).  Never spin here: give up, count it and
                    // resynchronise on the next descriptor.  An unrecoverable
                    // hang must be structurally impossible.
                    stat_len_err <= stat_len_err + 16'd1;
                    w_drain_wait <= 4'd0;
                    wst          <= W_IDLE;
                end else begin
                    w_drain_wait <= w_drain_wait + 4'd1;
                end
            end
            default: wst <= W_IDLE;
            endcase
        end
    end
    end else begin : g_wr_dma
    //=========================================================================
    // B3-2 写引擎 (HAS_DMA=1): 逐帧 512b AXI4-Stream -> axi_dma S2MM
    //-------------------------------------------------------------------------
    // 规则号 1 (写槽 = 帧计数 mod 256) 逐字等价点:
    //   * 槽游标 wr_slot_ptr 在【描述符接收拍】推进, 被拒帧同样推进 (W5/L2 语义);
    //   * 槽地址 SLOT_BASE+{slot,12'b0}: 桥把 slot 交给软核, 软核换算 S2MM_SA;
    //   * 长度 = 字节 FIFO 实际入队字节数 (描述符 wd_data), 提交时写 len_tab;
    //   * 槽置满 (wr_commit) 时刻 = S2MM 完成中断 = DDR 写已提交 (与旧 B 响应同语义);
    //   * 满槽拒收整帧丢弃/不覆盖未读槽/游标推进/stat_wr_stall 计数 (同旧 W_DRAIN)。
    // 协议: 请求 {pending,toggle,slot,len} 经 frame_mem_if 镜像到 user 域给软核;
    //       软核编程 S2MM (SA/LENGTH) 后翻 GO (ui 域 2FF); 完成后 s2mm_introut 退休。
    //       toggle 非电平: 帧到达是外部驱动, 连续请求可能在 2FF 窗口内无缝衔接。
    //=========================================================================
    localparam WD_IDLE=3'd0, WD_WAITGO=3'd1, WD_STREAM=3'd2, WD_PUSH=3'd3,
               WD_WAITDONE=3'd4, WD_DRAIN=3'd5, WD_HALT=3'd6, WD_ARM=3'd7;
    // ★WD_ARM=7 (2026-10-18 时序修复): 进入 STREAM 前独立一拍清拼帧寄存器.
    //   失败轮实测: WAITGO 的完成条件 `wf_level >= wd_len` (12b 比较, 3x CARRY8)
    //   被逻辑并进了 wd_data_r/wd_keep_r 的 512 CE (clear-on-transition), 使
    //   gray 同步指针->level 比较->512 CE 成为 300MHz 关键路径 (slack -0.127)。
    //   拆出 ARM 后: 清寄存器 CE = 状态译码 (FF), level 比较只驱动 wdst (3 FF)。
    //   编码取 7 而非插入中间值, 保持既有 HALT=6 不变 (板验/判据工具文档口径)。
    reg [2:0]   wdst;
    // ★注意: 不得在本分支内再声明 wr_slot_ptr (会遮蔽模块级同名信号, 读 FSM 的
    //   c_clamp/c_in_rng/p_target_ok 用的是模块级副本 -> 静默断源)。本分支直接驱动模块级。
    reg [7:0]   wd_slot, wd_beats, wd_beat, wd_bi;
    reg [15:0]  wd_len, wd_pop, wd_rxc;
    reg [511:0] wd_data_r;
    reg [63:0]  wd_keep_r;
    reg         wd_beat_full, wd_noroom, wd_go_ok;
    // ★2026-10-18 round2d 时序修复: 满槽/坏长判定拆到"注册判据 + WAITGO 首拍执行"
    //   避免 full_bit_q[slot] (256:1 组合读, 4xLUT6+2xMUXF) 直接进 wd_wait_cnt[23:0] 的 CE
    //   (round2d ExtraTimingOpt 30/30 最差路径 = full_bit_q_reg[179] -> wd_wait_cnt[*]/CE,
    //    route 2.27ns/80%). 现在 full_bit 读只驱动 wd_noroom/wd_badlen_r 两个 FF,
    //    request/pending/beats/计数器在 WAITGO 首拍按注册判据执行.
    reg         wd_badlen_r, wd_arm_pend;
    reg         wd_go_seen, wd_req_pending, wd_req_toggle;
    reg [7:0]   wd_req_slot_r;
    reg [15:0]  wd_req_len_r;
    reg [23:0]  wd_wait_cnt;
    reg [23:0]  wd_stall_cnt;
    reg [23:0]  wd_done_cnt;
    reg [3:0]   wd_drain_wait;
    reg         wd_ack_seen;
    // ★2026-10-18 (R2 构建失败轮 [L2] 关键路径修复): 字节捕获 1 级流水.
    //   失败轮 25/30 最差路径 = u_wr_bytes/wr_gray_s2 (同步化写指针) -> gray 比较(3x CARRY8)
    //   -> wd_fill -> 64:1 lane 译码 -> wd_data_r[*]/CE (512 CE, route 56.6%, slack -0.175ns).
    //   加一级后: FIFO 读使能只驱动 8 FF (轻负载); 512 lane CE 由寄存器 byte_valid_q/byte_q 驱动.
    //   吞吐仍 1 byte/cycle (取字节与消费字节流水并行).
    reg  [7:0]  byte_q;
    reg         byte_valid_q;
    reg [15:0]  wr_timeout_r;
    reg         wr_fault_r;
    reg [7:0]   wr_last_slot_r;
    reg [15:0]  wr_last_len_r;

    wire [7:0]  wd_slot_next = wr_slot_ptr[7:0];
    wire        wd_noroom_n  = full_bit_q[wd_slot_next];
    wire        wd_badlen_n  = (wd_data == 16'd0) || (wd_data > MAX_LEN);
    wire        wd_desc_av   = (wdst == WD_IDLE) && calib_ok && !wd_empty;
    // ★字节捕获流水 (2026-10-18): 取字节条件只含轻量锥 (FIFO 读使能 + 8 FF CE);
    //   预取计数 = 已消费 wd_rxc + 流水内 1 字节, 严格不超过 wd_len (不预取下一帧).
    //   ★审计复核必要门控 `!wd_beat_full`: 满拍保持拍 (beat 已满、等 PUSH) 不得再 fetch,
    //   否则会覆盖尚未消费的跨拍预取字节 (每非末拍丢 1 字节; 审计 rtl-auditor 2026-10-18 抓到).
    //   跨拍预取发生在"末字节消费当拍" (此时 wd_beat_full 旧值=0), 之后保持拍禁取 => 无吞吐损失.
    wire        wd_fetch     = (wdst == WD_STREAM) && !wf_empty && !wd_beat_full &&
                               ((wd_rxc + (byte_valid_q ? 16'd1 : 16'd0)) < wd_len);
    wire        wd_drain_pop = (wdst == WD_DRAIN) && !wf_empty && (wd_pop < wd_len);
    assign dma_wd_rd_en = wd_desc_av;
    assign dma_wf_rd_en = wd_fetch | wd_drain_pop;

    assign dma_wr_req_toggle  = wd_req_toggle;
    assign dma_wr_req_pending = wd_req_pending;
    assign dma_wr_req_slot    = wd_req_slot_r;
    assign dma_wr_req_len     = wd_req_len_r;
    assign m_axis_s2mm_tdata  = wd_data_r;
    assign m_axis_s2mm_tkeep  = wd_keep_r;
    assign m_axis_s2mm_tlast  = (wdst == WD_PUSH) && (wd_beat == (wd_beats - 8'd1));
    assign m_axis_s2mm_tvalid = (wdst == WD_PUSH);
    assign stat_wr_timeout    = wr_timeout_r;
    assign dbg_wr_fault       = wr_fault_r;
    assign dbg_wr_last_slot   = wr_last_slot_r;
    assign dbg_wr_last_len    = wr_last_len_r;
    assign dbg_wr_state       = wdst;
    // HAS_DMA=1: 桥① AXI4 写口整体退役 —— 输出钉 0 (仲裁器 S00 已改接 S2MM;
    // 顶层对 u_mem 这些端口保持悬空, 不得再接/再 assign, 否则构成多驱动)
    assign m_axi_awaddr  = 32'd0;
    assign m_axi_awlen   = 8'd0;
    assign m_axi_awsize  = 3'd0;
    assign m_axi_awburst = 2'd0;
    assign m_axi_wdata   = 512'd0;
    assign m_axi_wstrb   = 64'd0;
    assign m_axi_wlast   = 1'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdst <= WD_IDLE; wr_slot_ptr <= 16'd0;
            wd_slot <= 8'd0; wd_beats <= 8'd0; wd_beat <= 8'd0; wd_bi <= 8'd0;
            wd_len <= 16'd0; wd_pop <= 16'd0; wd_rxc <= 16'd0;
            wd_data_r <= 512'd0; wd_keep_r <= 64'd0;
            wd_beat_full <= 1'b0; wd_noroom <= 1'b0; wd_go_ok <= 1'b0;
            wd_badlen_r <= 1'b0; wd_arm_pend <= 1'b0;
            byte_q <= 8'd0; byte_valid_q <= 1'b0;
            wd_go_seen <= 1'b0; wd_req_pending <= 1'b0; wd_req_toggle <= 1'b0;
            wd_req_slot_r <= 8'd0; wd_req_len_r <= 16'd0;
            wd_wait_cnt <= 24'd0; wd_stall_cnt <= 24'd0; wd_done_cnt <= 24'd0;
            wd_drain_wait <= 4'd0; wd_ack_seen <= 1'b0;
            wr_timeout_r <= 16'd0; wr_fault_r <= 1'b0;
            wr_last_slot_r <= 8'd0; wr_last_len_r <= 16'd0;
            wr_commit <= 1'b0; wr_commit_slot <= 8'd0; wr_commit_len <= 16'd0;
            stat_wm <= 16'd0; stat_wr_frame <= 16'd0; stat_wr_stall <= 16'd0;
            stat_bresp_err <= 16'd0; stat_len_err <= 16'd0;
            dbg_wr_slot <= 8'd0; dbg_wr_cycles <= 32'd0; dbg_wr_beats <= 32'd0;
            out_inc <= 1'b0;
            m_axi_awvalid <= 1'b0; m_axi_wvalid <= 1'b0; m_axi_bready <= 1'b0;
        end else begin
            wr_commit     <= 1'b0;
            out_inc       <= 1'b0;
            // HAS_DMA=1: 桥① AXI4 写口退役 (仲裁器 S00 已改接 axi_dma M_AXI_S2MM)
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            if (wdst != WD_IDLE) dbg_wr_cycles <= dbg_wr_cycles + 32'd1;

            case (wdst)
            //-----------------------------------------------------------------
            WD_IDLE: begin
                byte_valid_q <= 1'b0;      // 新帧清字节流水 (上一帧超时/拒收可能残留)
                if (wd_desc_av) begin
                    wd_len       <= wd_data;
                    wd_slot      <= wd_slot_next;
                    wd_pop       <= 16'd0;
                    wd_rxc       <= 16'd0;
                    wd_beat      <= 8'd0;
                    wd_bi        <= 8'd0;
                    wd_beat_full <= 1'b0;
                    wd_data_r    <= 512'd0;
                    wd_keep_r    <= 64'd0;
                    wd_noroom    <= wd_noroom_n;   // 只驱动 FF (不再进等待计数器 CE)
                    wd_badlen_r  <= wd_badlen_n;
                    wd_arm_pend  <= 1'b1;          // WAITGO 首拍按注册判据执行
                    dbg_wr_slot     <= wd_slot_next;
                    wr_last_slot_r  <= wd_slot_next;
                    // ★规则号 1: 接收时推进 (被拒帧同样消耗槽号; 同旧 W5/L2 语义)
                    wr_slot_ptr <= wr_slot_ptr + 16'd1;
                    wdst <= WD_WAITGO;
                end
            end
            //-----------------------------------------------------------------
            WD_WAITGO: begin
                // ★首拍: 按注册判据 (wd_noroom/wd_badlen_r) 决定拒收或正式发请求。
                // ★FIX(2026-10-18 round2e): 首拍分支与等待分支必须互斥 (else) ——
                //   原实现两段 if 并行执行, 首拍会用上一帧残留的 wd_wait_cnt==0xFFFFFF
                //   误触发超时 (且 wd_wait_cnt<=0 被后面 else 的 +1 覆盖), 导致
                //   "一次 WAITGO 超时后, 此后所有帧都被静默丢弃" (TB 实测 FAIL-TIMEOUT).
                if (wd_arm_pend) begin
                    wd_arm_pend    <= 1'b0;
                    wd_drain_wait  <= 4'd0;
                    wd_pop         <= 16'd0;
                    wd_go_ok       <= 1'b0;
                    wd_go_seen     <= dma_wr_go;
                    wd_wait_cnt    <= 24'd0;
                    if (wd_noroom | wd_badlen_r) begin
                        // 满槽/坏长度: 整帧丢弃, 不覆盖未读槽 (同旧 W_DRAIN)
                        if (wd_badlen_r) stat_len_err <= stat_len_err + 16'd1;
                        wdst <= WD_DRAIN;
                    end else begin
                        wd_beats       <= (wd_len + 16'd63) >> 6;
                        wd_req_slot_r  <= wd_slot;
                        wd_req_len_r   <= wd_len;
                        wd_req_pending <= 1'b1;
                        wd_req_toggle  <= ~wd_req_toggle;
                    end
                end
                else begin
                    // 等软核: ① GO 翻转 ② 整帧字节可见 (同旧 W_WAIT) ③ introut 已清
                    if (!wd_go_ok && (dma_wr_go != wd_go_seen)) begin
                        wd_go_seen <= dma_wr_go;
                        wd_go_ok   <= 1'b1;
                    end
                    if (wd_go_ok && (wf_level >= wd_len[12:0]) && !s2mm_introut) begin
                        // ★2026-10-18 时序修复: 本拍不再清 512 数据寄存器
                        wdst <= WD_ARM;
                    end else if (wd_wait_cnt == 24'hFFFFFF) begin
                        // 超时 (~56ms @300MHz): 软核未驻留/未编程 -> 整帧丢弃 (不停泊)
                        wr_timeout_r   <= wr_timeout_r + 16'd1;
                        wd_req_pending <= 1'b0;
                        wd_pop         <= 16'd0;
                        wd_drain_wait  <= 4'd0;
                        wdst <= WD_DRAIN;
                    end else begin
                        wd_wait_cnt <= wd_wait_cnt + 24'd1;
                    end
                end
            end
            //-----------------------------------------------------------------
            WD_ARM: begin      // ★2026-10-18: 独立一拍清拼帧寄存器 (CE 只依赖状态译码)
                wd_beat      <= 8'd0;
                wd_bi        <= 8'd0;
                wd_rxc       <= 16'd0;
                wd_beat_full <= 1'b0;
                wd_data_r    <= 512'd0;
                wd_keep_r    <= 64'd0;
                wd_stall_cnt <= 24'd0;
                byte_valid_q <= 1'b0;
                wdst <= WD_STREAM;
            end
            //-----------------------------------------------------------------
            WD_STREAM: begin   // 逐字节攒拍 (尾拍 TKEEP 精确到字节, 与旧 WSTRB 等价)
                // ★字节捕获 1 级流水 (2026-10-18 时序修复): 消费(寄存器->512 lane / 推进)
                //   与取字节(FIFO->byte_q) 同拍并行 => 吞吐仍 1 byte/cycle。
                if (byte_valid_q && !wd_beat_full) begin
                    wd_data_r[wd_bi*8 +: 8] <= byte_q;
                    wd_keep_r[wd_bi]        <= 1'b1;
                    wd_rxc                  <= wd_rxc + 16'd1;
                    wd_stall_cnt            <= 24'd0;
                    byte_valid_q            <= 1'b0;
                    if ((wd_bi == 8'd63) || ((wd_rxc + 16'd1) == wd_len)) begin
                        wd_beat_full <= 1'b1;
                    end else begin
                        wd_bi <= wd_bi + 8'd1;
                    end
                end
                if (wd_fetch) begin            // 取下一字节入流水 (预取不超过 wd_len)
                    byte_q       <= wf_data;
                    byte_valid_q <= 1'b1;
                end
                if (wd_beat_full) begin
                    wdst <= WD_PUSH;
                end else if (!wd_fetch && !(byte_valid_q && !wd_beat_full)) begin
                    if (wd_stall_cnt == 24'hFFFFFF) begin
                        // ★fail-stop: 帧字节迟迟不到 (~56ms) -> 不提交、粘滞 fault、停泊 HALT
                        wr_timeout_r   <= wr_timeout_r + 16'd1;
                        wr_fault_r     <= 1'b1;
                        wd_req_pending <= 1'b0;
                        wd_ack_seen    <= dma_wr_ack;
                        wdst <= WD_HALT;
                    end else begin
                        wd_stall_cnt <= wd_stall_cnt + 24'd1;
                    end
                end
            end
            //-----------------------------------------------------------------
            WD_PUSH: begin     // AXI4-Stream 握手 (S_AXIS_S2MM)
                if (m_axis_s2mm_tready) begin
                    wd_beat_full <= 1'b0;
                    wd_bi        <= 8'd0;
                    wd_keep_r    <= 64'd0;
                    wd_data_r    <= 512'd0;
                    wd_stall_cnt <= 24'd0;
                    dbg_wr_beats <= dbg_wr_beats + 32'd1;
                    if (wd_beat == (wd_beats - 8'd1)) begin
                        wd_done_cnt <= 24'd0;
                        wdst <= WD_WAITDONE;
                    end else begin
                        wd_beat <= wd_beat + 8'd1;
                        wdst <= WD_STREAM;
                    end
                end else if (wd_stall_cnt == 24'hFFFFFF) begin
                    // ★fail-stop: S2MM 不接流 (halt/未编程, ~56ms) -> 粘滞 fault、停泊 HALT
                    wr_timeout_r   <= wr_timeout_r + 16'd1;
                    wr_fault_r     <= 1'b1;
                    wd_req_pending <= 1'b0;
                    wd_ack_seen    <= dma_wr_ack;
                    wdst <= WD_HALT;
                end else begin
                    wd_stall_cnt <= wd_stall_cnt + 24'd1;
                end
            end
            //-----------------------------------------------------------------
            WD_WAITDONE: begin // 等 S2MM 完成中断 (=DDR 写已提交, 与旧 B 响应同语义)
                if (s2mm_introut) begin
                    wr_commit      <= 1'b1;
                    wr_commit_slot <= wd_slot;
                    wr_commit_len  <= wd_len;
                    out_inc        <= 1'b1;
                    stat_wm        <= stat_wm + 16'd1;
                    stat_wr_frame  <= stat_wr_frame + 16'd1;
                    wr_last_len_r  <= wd_len;
                    wd_req_pending <= 1'b0;
                    wdst <= WD_IDLE;
                end else if (wd_done_cnt == 24'hFFFFFF) begin
                    // 完成中断未到 (~56ms): 不提交 (fail-stop, 等软核复位 S2MM + ACK)
                    wr_timeout_r   <= wr_timeout_r + 16'd1;
                    wr_fault_r     <= 1'b1;
                    wd_req_pending <= 1'b0;
                    wd_ack_seen    <= dma_wr_ack;
                    wdst <= WD_HALT;
                end else begin
                    wd_done_cnt <= wd_done_cnt + 24'd1;
                end
            end
            //-----------------------------------------------------------------
            WD_DRAIN: begin    // 拒收帧: 把整帧字节抽掉 (liveness 有界, 同旧 W_DRAIN)
                if (wd_pop >= wd_len) begin
                    if (wd_noroom) stat_wr_stall <= stat_wr_stall + 16'd1;
                    wd_drain_wait <= 4'd0;
                    wdst <= WD_IDLE;
                end else if (wd_drain_pop) begin
                    wd_pop        <= wd_pop + 16'd1;
                    wd_drain_wait <= 4'd0;
                end else if (wd_drain_wait == 4'd15) begin
                    stat_len_err  <= stat_len_err + 16'd1;
                    wd_drain_wait <= 4'd0;
                    wdst <= WD_IDLE;
                end else begin
                    wd_drain_wait <= wd_drain_wait + 4'd1;
                end
            end
            //-----------------------------------------------------------------
            WD_HALT: begin     // ★fail-stop: 等软核复位 S2MM 通道并翻 ACK 才恢复
                // (坑 #55 纪律: 任何超时后的不可恢复挂起必须在结构上有出口;
                //  恢复动作 = 软核 DMACR 复位->RS + 清 IOC + 写 WRACK(翻转))
                if (dma_wr_ack != wd_ack_seen) begin
                    wd_ack_seen    <= dma_wr_ack;
                    wr_fault_r     <= 1'b0;
                    wd_req_pending <= 1'b0;
                    wd_go_ok       <= 1'b0;
                    wd_stall_cnt   <= 24'd0;
                    wdst <= WD_IDLE;
                end
            end
            default: wdst <= WD_IDLE;
            endcase
        end
    end
    end endgenerate

    //=========================================================================
    // 4. read FSM
    //=========================================================================
    localparam R_IDLE=3'd0, R_AR=3'd1, R_R=3'd2, R_UNPACK=3'd3, R_FIN=3'd4,
               R_PRE=3'd5,   // R_PRE2 removed: triggered a Vivado 2023.1 synth crash (3x reproducible)
               R_DRET=3'd6;  // B3-1b: DMA 引擎 —— 等 shim rdesc, 统一退休

    reg [2:0]   rstate;
    reg [7:0]   r_slot, r_beat, r_bi, r_beats;
    reg [15:0]  r_len;
    reg [6:0]   r_nbytes;        // meaningful bytes in the current beat (<=64)
    reg [511:0] r_beat_data;
    reg         r_rnd;

    //=========================================================================
    // ★B3-1b (2026-10-14): DMA 读引擎 shim + 双引擎输出合并
    //-------------------------------------------------------------------------
    // 桥硬件读 FSM 的 rf/rdesc 输出改用内部名 brf_*/brd_*, 与 shim 输出在
    // 端口处 OR 合并 —— 两引擎由 dma_engine 互斥 (engine=1 时读 FSM 自 R_PRE
    // 泊在 R_DRET, brf/brd 恒 0), 单驱动纪律不破(各归各的 always 块)。
    // shim 输入 tvalid 用 engine 门控: engine=0 时 dma_sink 占用 M_AXIS
    // ('D' 冒烟), shim 不偷拍。
    // ★DROP_BYTES=0 + DMA_LENGTH=len_tab (2026-10-16 板上 ILA 发射字节流实证; 修正 10-14 的 DROP=8):
    //   槽内存的是【8B 以太网前导+SFD (55×7,D5) + 完整 ETH/IP/UDP 帧(含尾 4B FCS)】,
    //   全长 = len_tab(写路径提交长度)。桥硬件读引擎把这 len_tab 字节【原样】发射给下游
    //   (前导由数据流携带, 下游直接上线) —— 桥模式回显因此逐字节正确。
    //   DMA 路径必须与之【逐字节同构】: DMA_SA=槽基址, DMA_LENGTH=len_tab, shim 不丢任何字节。
    //   旧口径(DROP=8 + LEN=len+8)把前导+SFD 丢掉、并在尾部多读 8B ⇒ 发射流 =
    //   【帧(无前导) + FCS + 8B 垃圾】⇒ 接收侧 MAC 无法定界 ⇒ 网卡静默丢弃、PC 零到达。
    //   实证(2026-10-16, 同一 slot 同一帧): 桥=[前导][帧][FCS] 1526B  vs  E=[帧][FCS][8B 垃圾] 1526B。
    //=========================================================================
    reg         brf_wr_en;
    reg  [7:0]  brf_wr_data;
    reg         brd_wr_en;
    reg  [24:0] brd_wr_data;

    wire        shim_rf_wr_en;
    wire [7:0]  shim_rf_wr_data;
    wire        shim_frame_done;

    generate if (HAS_DMA) begin : gen_dma_engine
        dma_rd_shim_v2 #(.DROP_BYTES(0)) u_rd_shim (
            .clk(clk), .rst_n(rst_n),
            .s_tdata (dma_s_tdata),
            .s_tkeep (dma_s_tkeep),
            .s_tlast (dma_s_tlast),
            .s_tvalid(dma_s_tvalid),               // ★B3-1c: shim 是唯一消费者
                                                   // (硬件读引擎退役; 冒烟用 dma_sink 已在顶层让路)
            .s_tready(dma_s_tready),
            .rf_wr_en (shim_rf_wr_en),  .rf_wr_data (shim_rf_wr_data),
            .frame_done(shim_frame_done),
            .frame_len(dma_req_len), .tag_slot(dma_req_slot), .tag_valid(1'b0)
        );

        assign rf_wr_en   = shim_rf_wr_en;      // ★B3-1c: 不再与桥硬件读 OR
        assign rf_wr_data = shim_rf_wr_data;
        // v3: 描述符由读 FSM 在 frame_done 拍自发射 (见 R_DRET, brd_wr_*)
        assign rd_wr_en   = brd_wr_en;
        assign rd_wr_data = brd_wr_data;
    end else begin : gen_no_dma
        assign rf_wr_en   = brf_wr_en;
        assign rf_wr_data = brf_wr_data;
        assign rd_wr_en   = brd_wr_en;
        assign rd_wr_data = brd_wr_data;
        assign dma_s_tready = 1'b0;
        assign shim_frame_done = 1'b0;   // 该实例无 shim; R_DRET 不可达, 仅避免悬空网
    end endgenerate

    // ---- W5 timing fix (2026-10-07): command prefetch registers ----
    // Old single-cycle cone: rc_data (FWFT comb RAM read of u_rd_cmd!) -> compare
    // in_range -> mux eff_slot -> full_bit/len_tab 256:1 lookup -> CE/D of
    // stat_ill_rd / r_len / r_beats / rd_wr_data  == 4.226ns vs 3.333ns budget.
    // Split into two beats: this beat only registers {rnd, slot} off the FIFO
    // (short), next beat (R_PRE) does range math + table lookup off REGISTERS.
    // SEQ semantics unchanged: still "oldest unread slot"; only the decision is
    // one cycle later. cmd_rnd kept as a live wire only where its input is a
    // registered value (prefetched), never straight off the FWFT RAM output.
    reg         pre_rnd;
    reg [7:0]   pre_slot;
    // NOTE (2026-10-08): a second cut (state R_PRE2 registering the range
    // decision before the table lookup) was implemented and measured, but
    // Vivado 2023.1 synthesis CRASHED on it (EXCEPTION_ACCESS_VIOLATION, 3x
    // reproducible at "Mimic Skeleton from Reference") while single-module
    // out-of-context synthesis of the same file passed. It was reverted; the
    // dead registers are removed. See
    // 调试记录/阶段三_prj10_W5时序收敛_第二轮根因重定与修复_2026-10-08.md

    wire        cmd_rnd    = rc_data[8];
    wire [7:0]  cmd_slot   = rc_data[7:0];
    // ---- W5 final fix (2026-10-08): range math moved INTO the prefetch beat ----
    // Measured chain (run C): stat_wm -> compare(CARRY8) -> p_eff mux -> 256:1 tree
    // -> r_len/r_beats  == 3.6ns vs 3.333ns (-0.494). The range math + slot select
    // is computed here off the PREFETCHED command and registered (pre_eff/pre_in_rng),
    // so the R_PRE beat sees REGISTER-INDEXED lookups only (like the W4-era cone,
    // which closed at +0.008 even WITH an adder; ours has none).
    // 槽域判断一律用「槽游标」wr_slot_ptr（已分配的槽号范围），与上位机
    // 「写槽 = 接受帧计数 mod 256」的口径一致；stat_wm 只表示"已提交"。
    wire [7:0]  c_clamp    = (wr_slot_ptr == 16'd0) ? 8'd0 : (wr_slot_ptr[7:0] - 8'd1);
    wire        c_in_rng   = (wr_slot_ptr >= 16'd256) || (cmd_slot < wr_slot_ptr[7:0]);
    wire [7:0]  c_eff      = cmd_rnd ? (c_in_rng ? cmd_slot : c_clamp) : rd_seq_slot;
    reg  [7:0]  pre_eff;      // registered effective slot (latched in R_IDLE)
    reg         pre_in_rng;   // registered range decision (latched in R_IDLE)
    // R_PRE side: all lookups are indexed by the REGISTER pre_eff
    wire [7:0]  p_eff      = pre_eff;
    wire        p_in_rng   = pre_in_rng;
    wire        p_target_ok  = (wr_slot_ptr != 16'd0) && full_bit[pre_eff];
    // SEQ = "oldest unread slot". The pointer is scanned forward until it lands on
    // a FULL slot, so SEQ stays correct even if RND reads have already retired
    // arbitrary slots (mixed-mode safety, see the W2 note 6.3).
    wire        seq_ok   = cmd_rnd | full_bit_q[rd_seq_slot] | (stat_outstanding == 9'd0); // W5: mirror

    assign rc_rd_en = (rstate == R_IDLE) && calib_ok && !rc_empty && seq_ok;

    assign m_axi_araddr  = SLOT_BASE + {r_slot, 12'b0};
    assign m_axi_arlen   = r_beats - 8'd1;
    assign m_axi_arsize  = 3'b110;
    assign m_axi_arburst = 2'b01;

    // meaningful bytes in the current read beat
    always @(*) begin
        if (r_beat == (r_beats - 8'd1))
            r_nbytes = (r_len[5:0] == 6'd0) ? 7'd64 : {1'b0, r_len[5:0]};
        else
            r_nbytes = 7'd64;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate <= R_IDLE; m_axi_arvalid <= 0; m_axi_rready <= 0;
            brf_wr_en <= 0; brf_wr_data <= 0; brd_wr_en <= 0; brd_wr_data <= 0;
            r_slot <= 0; r_beat <= 0; r_bi <= 0; r_beats <= 0; r_len <= 0;
            r_beat_data <= 0; r_rnd <= 0;
            pre_rnd <= 1'b0; pre_slot <= 8'd0;
            pre_eff <= 8'd0; pre_in_rng <= 1'b0;
            rd_retire <= 0; rd_retire_slot <= 0; rd_seq_slot <= 0;
            stat_rd_frame <= 0; stat_ill_rd <= 0; stat_noframe <= 0; dbg_rd_slot <= 0;
            dbg_rd_cycles <= 0; dbg_rd_beats <= 0; out_dec <= 1'b0;
            dma_req_new <= 1'b0; dma_req_slot <= 8'd0; dma_req_len <= 16'd0;
        end else begin
            rd_retire <= 1'b0;
            out_dec   <= 1'b0;     // D1 FIX: this block is the ONLY driver of out_dec
            brf_wr_en <= 1'b0;
            brd_wr_en <= 1'b0;
            // dma_req_new 不在此清零: 电平语义 (板上实证 10-14: 1 拍 ui 脉冲
            // 3.3ns 过 2FF 到 151.5MHz 采样域会被随机漏采, 请求待服务状态
            // 对软核不可见 -> 服务循环停摆。电平 = R_DRET 全程保持。)
            if (rstate != R_IDLE) dbg_rd_cycles <= dbg_rd_cycles + 32'd1;

            case (rstate)
            //-----------------------------------------------------------------
            R_IDLE: begin
                m_axi_arvalid <= 1'b0;
                m_axi_rready  <= 1'b0;
                // SEQ pointer scan (1 slot / ui cycle, no command is consumed).
                // Guard uses only registered values (rd_seq_slot is a reg) --
                // deliberately NOT cmd_rnd: that would revive the FIFO-output cone.
                if (!full_bit_q[rd_seq_slot] && (stat_outstanding != 9'd0))
                    rd_seq_slot <= rd_seq_slot + 8'd1;
                if (rc_rd_en) begin
                    // prefetch beat: capture the command AND do the range math
                    // (compare + select) here, so the next beat is register-indexed
                    // lookups only. Inputs: cmd_slot/cmd_rnd (FIFO comb read, short
                    // hop to these regs) + stat_wm/rd_seq_slot (registers).
                    pre_rnd    <= cmd_rnd;
                    pre_slot   <= cmd_slot;
                    pre_eff    <= c_eff;
                    pre_in_rng <= c_in_rng;
                    rstate     <= R_PRE;
                end
            end
            //-----------------------------------------------------------------
            // W5 cut-1: decision beat. Range math (compare + select) and the
            // table lookups share this beat -- measured WNS -0.494 @3.333ns, i.e.
            // one more cut is still needed. All inputs here are REGISTERS
            // (pre_rnd/pre_slot/rd_seq_slot/stat_wm), never the FWFT RAM output.
            R_PRE: begin
                r_rnd <= pre_rnd;
                if (pre_rnd && !p_in_rng) stat_ill_rd <= stat_ill_rd + 16'd1;
                if (!p_target_ok) begin
                    if (!pre_rnd)            stat_noframe <= stat_noframe + 16'd1;
                    else if (p_in_rng)       stat_ill_rd  <= stat_ill_rd  + 16'd1;
                    brd_wr_en   <= 1'b1;
                    brd_wr_data <= {1'b1, 16'd0, 8'hFF};
                    dbg_rd_slot <= 8'hFF;
                    rstate      <= R_IDLE;
                end else if (HAS_DMA) begin
                    // ★B3-1c(2026-10-16): 桥硬件读引擎【已退役】—— 唯一读出路径 =
                    //   DMA 描述符 (软核编程 MM2S, 数据由 shim 拆包回灌, 退休由 shim
                    //   的 frame_done 脉冲触发)。原 R_AR/R_R/R_UNPACK/R_FIN 分支与其
                    //   dma_engine 二选一已删除; 读请求一律泊在 R_DRET。
                    //   ★只对 HAS_DMA=1 实例(桥①)生效 —— DMA shim 只存在于该实例。
                    dma_req_new  <= 1'b1;
                    dma_req_slot <= p_eff;
                    dma_req_len  <= len_tab[p_eff];
                    dbg_rd_slot  <= p_eff;
                    rstate       <= R_DRET;     // 等 shim frame_done (或空答直接回)
                end else begin
                    // ★2026-10-17 修正: HAS_DMA=0 实例(桥②/u_mem2)必须保留硬件读引擎。
                    //   退役改动曾把它无条件删除, 导致桥②: ①读 FSM 永泊 R_DRET
                    //   (shim_frame_done 在该实例不存在) ②rf 无数据源 ⇒ 泵B 恒空
                    //   ⇒ 所有出向帧(含栈自发 ARP/ICMP)不上线。DMA shim 只在桥①,
                    //   无人能服务桥② ⇒ 退役只能作用于 HAS_DMA=1 实例。
                    r_slot  <= p_eff;
                    r_len   <= len_tab[p_eff];
                    r_beats <= len_beats_tab[p_eff];
                    r_beat  <= 8'd0;
                    dbg_rd_slot <= p_eff;
                    rstate  <= R_AR;
                end
            end
            //-----------------------------------------------------------------
            // ★2026-10-17: 硬件读引擎(HAS_DMA=0 实例专用, 桥② EGR 出口)。
            //   与 R_PRE 的 HAS_DMA 分支配套: HAS_DMA=1 时这些状态不可达(综合剪枝),
            //   读出路径为 DMA; HAS_DMA=0 时读出路径为下列四态。
            R_AR: begin
                m_axi_arvalid <= 1'b1;
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid <= 1'b0;
                    rstate <= R_R;
                end
            end
            //-----------------------------------------------------------------
            R_R: begin
                // AXI handshake: READY must be high in the SAME cycle that VALID
                // is sampled. Asserting rready only while rvalid is still low (and
                // dropping it on the first rvalid) never completes the transfer on
                // the slave side -> the slave stays mid-burst and the next AR is
                // never accepted (W2 bring-up bug: bridge stuck in R_AR).
                m_axi_rready <= 1'b1;
                if (m_axi_rvalid && m_axi_rready) begin
                    m_axi_rready <= 1'b0;
                    r_beat_data  <= m_axi_rdata;
                    r_bi         <= 8'd0;
                    dbg_rd_beats <= dbg_rd_beats + 32'd1;
                    rstate       <= R_UNPACK;
                end
            end
            //-----------------------------------------------------------------
            R_UNPACK: begin   // 1 byte / ui cycle into the ui->user byte FIFO
                brf_wr_en   <= 1'b1;
                brf_wr_data <= r_beat_data[r_bi*8 +: 8];
                if (r_bi == (r_nbytes - 7'd1)) begin
                    r_bi <= 8'd0;
                    if (r_beat == (r_beats - 8'd1)) rstate <= R_FIN;
                    else begin r_beat <= r_beat + 8'd1; rstate <= R_R; end
                end else begin
                    r_bi <= r_bi + 8'd1;
                end
            end
            //-----------------------------------------------------------------
            R_FIN: begin
                rd_retire      <= 1'b1;
                rd_retire_slot <= r_slot;
                out_dec        <= 1'b1;
                stat_rd_frame  <= stat_rd_frame + 16'd1;
                if (!r_rnd) rd_seq_slot <= rd_seq_slot + 8'd1;
                brd_wr_en   <= 1'b1;
                brd_wr_data <= {1'b0, r_len, r_slot};
                rstate     <= R_IDLE;
            end
            //-----------------------------------------------------------------
            // ★B3-1b: DMA 引擎退休等待。shim 在 TLAST 结算时发 frame_done
            // 脉冲 (v3: shim 不再发描述符); 描述符由本 FSM 用锁存
            // {dma_req_len,dma_req_slot} 自发射, 同拍统一退休 (与 R_FIN 同一
            // 套槽表/计数/指针语义 —— 单驱动纪律: 都在本 always 块)。若软件
            // 读失败/超时, 软件可经 Lite 引擎位清零让 DMA 让路。
            R_DRET: begin
                m_axi_arvalid <= 1'b0;
                m_axi_rready  <= 1'b0;
                if (shim_frame_done) begin
                    rd_retire      <= 1'b1;
                    rd_retire_slot <= dma_req_slot;
                    out_dec        <= 1'b1;
                    stat_rd_frame  <= stat_rd_frame + 16'd1;
                    if (!r_rnd) rd_seq_slot <= dma_req_slot + 8'd1;
                    dbg_rd_beats   <= dbg_rd_beats + 32'd1;
                    dma_req_new    <= 1'b0;     // 电平随退休清零 (板上实证:
                                                // 1 拍脉冲跨域漏采, 见镜像注释)
                    // 描述符由桥自发射 (brd_wr_*, frame_done 的下一拍)
                    brd_wr_en   <= 1'b1;
                    brd_wr_data <= {1'b0, dma_req_len, dma_req_slot};
                    rstate      <= R_IDLE;
                end
            end
            default: rstate <= R_IDLE;
            endcase
        end
    end

    //=========================================================================
    // 10. B3-0: MIG latency observability (own always block -- RAM/FSM
    //     partition discipline, Correction #33/#34). Latest-value only.
    //
    //  lat_w: AW handshake (frame enters the 4-deep commit queue) -> the SAME
    //         frame's B dequeue. Same-ID FIFO order guarantees the dequeued
    //         entry (cqs0) is the oldest un-committed one; the queue position
    //         is tracked in a 2-bit counter to pair the right enqueue.
    //  lat_r: AR handshake -> first R beat of that burst (the MIG's data
    //         return delay -- the number the Lw/Lr study needs).
    //  Saturating: if a response never comes the counter freezes at its max
    //  and the EXISTING timeout paths (stat_bresp_err / W_DRAIN / R_ARB
    //  sticky) handle recovery -- no new FSM states, no cone cost.
    //=========================================================================
    reg [15:0] lat_w_cnt;
    reg        lat_w_arm;      // counting: armed at AW accept, closed at B dequeue
    reg [15:0] lat_r_cnt;
    reg        lat_r_arm;      // counting: armed at AR accept, closed at first R

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lat_w     <= 16'd0;
            lat_r     <= 16'd0;
            lat_w_cnt <= 16'd0;
            lat_r_cnt <= 16'd0;
            lat_w_arm <= 1'b0;
            lat_r_arm <= 1'b0;
        end else begin
            // ---- write path: arm only when the commit queue is EMPTY, so the
            //      next B dequeue provably pairs with THIS frame's AW (same-ID
            //      FIFO). Back-to-back frames with a busy queue are simply not
            //      sampled -- keeps every recorded lat_w an isolated-frame true
            //      latency instead of a queue-depth artifact. ----
            if (m_axi_awvalid && m_axi_awready && !lat_w_arm && (cq_cnt == 3'd0)) begin
                lat_w_cnt <= 16'd1;
                lat_w_arm <= 1'b1;
            end else if (lat_w_arm) begin
                if (m_axi_bvalid && m_axi_bready) begin
                    lat_w     <= lat_w_cnt;    // snapshot on dequeue
                    lat_w_arm <= 1'b0;
                end else if (lat_w_cnt != 16'hFFFF) begin
                    lat_w_cnt <= lat_w_cnt + 16'd1;
                end
            end
            // ---- read path: arm on AR accept ----
            if (m_axi_arvalid && m_axi_arready && !lat_r_arm) begin
                lat_r_cnt <= 16'd1;
                lat_r_arm <= 1'b1;
            end else if (lat_r_arm) begin
                if (m_axi_rvalid && m_axi_rready) begin
                    lat_r     <= lat_r_cnt;    // snapshot on first data beat
                    lat_r_arm <= 1'b0;
                end else if (lat_r_cnt != 16'hFFFF) begin
                    lat_r_cnt <= lat_r_cnt + 16'd1;
                end
            end
        end
    end

endmodule
