//=============================================================================
// axi_lite_regs.v -- prj11 B1: AXI4-Lite slave wrapping the W5 register
//                    semantics (soft-core control plane, Q3)
//-----------------------------------------------------------------------------
// What it is (one line): the SAME four command semantics as the UDP command
// channel (SET_MODE / READ_SLOT / GET_WATERMARK / GET_SLOT_MAP), exposed as a
// memory-mapped AXI4-Lite slave so MicroBlaze C code can drive the memory
// bridge instead of the PC.
//
// Register map (32-bit, word aligned):
//   offset 0x00  MODE    W   bit0: 0 = SEQ, 1 = RND            (= SET_MODE)
//   offset 0x04  RD_SLOT W   [7:0]: slot to read; the write ALSO forces
//                                  cfg_mode=1 and fires ONE rd_req_pulse
//                                  (= READ_SLOT; identical settle-then-pulse
//                                   sequence as cmd_channel U_PULSE)
//   offset 0x08  WM_WR    R   [15:0] u_wr_frame
//   offset 0x0C  WM_RD    R   [15:0] u_rd_frame
//   offset 0x10  WM_DROP  R   [15:0] u_buf_drop
//   offset 0x14  SLOTMAP  R   [31:24] rule id = 1, [23:16] wr slot ptr
//   offset 0x18  STATUS   R   [17:16] ctl_owner (0 = UDP, 1 = soft-core),
//                                  [15:0] lite rd trigger count
//   offset 0x1C  ID       R   0x50314231 ("P1B1") -- software sanity
//   Other offsets: reads return 0 (OKAY), writes ignored (OKAY).
//
// CDC (house rule, same 4-phase discipline as cmd_channel):
//   * writes : mailbox A lite->user {a_req, a_data[16]} / a_ack
//   * reads  : mailbox C lite->user {r_req, r_addr[6]}  / r_ack, then
//              mailbox D user->lite {d_req, d_data[32]} / d_ack.
//   Every side fully waits for the synchronized deassertion of the counter
//   level before raising a new request -- a quick req glitch can otherwise be
//   missed by the 2FF synchronizer and a write silently lost.
//
// Owner arbitration (at the TOP level): cfg_wr_pulse is a single user_clk
// strobe on every MODE/RD_SLOT write; the top flips ctl_owner to the most
// recent writer and muxes cfg_mode/cfg_rd_slot into frame_mem_if.  The two
// rd_req_pulse sources are OR-ed (a read trigger is idempotent w.r.t. the
// currently selected slot).
//
// Defect build for the negative control:
//   `ifdef AXI_LITE_REGS_DEFECT -- rd_req_pulse is held for 2 clocks (width
//   2) instead of the contracted single cycle; the bench pulse-width monitor
//   MUST fail on this build (proves the width check is not vacuous).
//=============================================================================
`timescale 1ns/1ps

module axi_lite_regs (
    // ------------- AXI4-Lite slave (aclk domain, 100 MHz from BD) ----------
    input  wire        aclk,
    input  wire        aresetn,          // active low, synchronous to aclk
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // ------------- user_clk domain (same as cmd_channel user side) ----------
    input  wire        clk_user,
    input  wire        rst_user_n,       // active low (~aurora_rst)
    input  wire [15:0] u_wr_frame,       // frame_mem_if.ro_u_wr_frame
    input  wire [15:0] u_rd_frame,       // frame_mem_if.ro_u_rd_frame
    input  wire [15:0] u_buf_drop,       // frame_mem_if.ro_u_buf_drop
    input  wire [15:0] lat_w,            // B3-0: MIG write latency (ui cycles)
    input  wire [15:0] lat_r,            // B3-0: MIG read latency (ui cycles)
    input  wire [31:0] dma_q0,           // B3-1a: {dma_beats, dma_bytes} (ui dom, 慢变)
    input  wire [31:0] dma_q1,           // B3-1a: 首拍低 32 bit
    input  wire [31:0] dma_q2,           // B3-1a: {done_cnt[7:0], busy, err, tlast_seen, ...}
    input  wire        ctl_owner,        // top-level owner flag (status read)
    // B3-1b: DMA 读引擎 (user 域) —— engine 选择位 + 请求 {sticky,slot,len}
    output reg         cfg_rd_engine,    // 0 = 桥硬件读, 1 = DMA+软件读
    input  wire [31:0] dma_req,          // {sticky_new, engine, slot[7:0], len[15:0]}
    input  wire [31:0] dma_arl,          // B3-1b: 最近一笔 DMA AR 地址 (user 域镜像)
    input  wire [31:0] dbg_emit,         // B3-1b 取证: 发射帧 {len,slot,首字节}(user 域)
    output reg  [15:0] lite_engine_cnt,  // SET_ENGINE 执行计数 (user dom)
    output reg         cfg_mode,         // 0 = SEQ, 1 = RND   -> owner mux
    output reg  [7:0]  cfg_rd_slot,      //                    -> owner mux
    output reg         rd_req_pulse,     // single user_clk pulse
    output reg         cfg_wr_pulse,     // single user_clk strobe (owner flip)
    output reg  [15:0] lite_exec_cnt,    // lite commands executed (user dom)
    output reg  [15:0] lite_rd_trig_cnt, // read triggers (= RD_SLOT writes)
    // ---- B3-2 (2026-10-17): DMA 写引擎 (S2MM) 握手 ----
    input  wire [31:0] dma_wr_req,       // {pending,6'b0,toggle,slot,len} (user 域镜像)
    input  wire [31:0] dma_wr_dbg,       // {fault,7'b0,last_alloc_slot,last_commit_len}
    output reg         cfg_wr_go,        // 软核 S2MM 编程完成后翻转 (桥见翻转才放流)
    output reg         cfg_wr_ack        // 软核 fault 恢复确认翻转 (桥 WD_HALT 出口)
);

    localparam [7:0] OP_SET_MODE   = 8'h01;   // same codes as cmd_channel
    localparam [7:0] OP_READ_SLOT  = 8'h02;
    localparam [7:0] OP_SET_ENGINE = 8'h03;   // B3-1b: 读引擎选择 0=桥 1=DMA
    localparam [7:0] OP_SET_WRGO   = 8'h05;   // B3-2: +0x48 写, 翻转 cfg_wr_go (S2MM 已编程)
    localparam [7:0] OP_SET_WRACK  = 8'h06;   // B3-2: +0x4C 写, 翻转 cfg_wr_ack (写引擎 fault 恢复)

    localparam [31:0] REG_ID = 32'h5031_4231;  // "P1B1"

    // B3-1b build9 时序: dbg_emit 输入打一拍再进快照 mux (读路径锥 -1 级)
    reg [31:0] dbg_emit_q1;
    always @(posedge clk_user or negedge rst_user_n) begin
        if (!rst_user_n) dbg_emit_q1 <= 32'd0;
        else             dbg_emit_q1 <= dbg_emit;
    end

    //=========================================================================
    // mailbox registers
    //=========================================================================
    reg        a_req;                    // A: lite -> user (write command)
    reg [15:0] a_data;                   // {opcode, arg}
    reg        a_ack;                    // A: user -> lite
    reg        r_req;                    // C: lite -> user (read request)
    reg [5:0]  r_addr;                   // word offset (awaddr[7:2])
    reg        r_ack;                    // C: user -> lite
    reg        d_req;                    // D: user -> lite (read data)
    reg [31:0] d_data;
    reg        d_ack;                    // D: lite -> user

    (* ASYNC_REG = "TRUE" *) reg [1:0] a_ack_s, r_ack_s, d_req_s;   // lite side
    (* ASYNC_REG = "TRUE" *) reg [1:0] a_req_s, r_req_s, d_ack_s;   // user side

    always @(posedge aclk) begin
        if (!aresetn) begin
            a_ack_s <= 2'b00;  r_ack_s <= 2'b00;  d_req_s <= 2'b00;
        end
        else begin
            a_ack_s <= {a_ack_s[0], a_ack};
            r_ack_s <= {r_ack_s[0], r_ack};
            d_req_s <= {d_req_s[0], d_req};
        end
    end

    always @(posedge clk_user) begin
        if (!rst_user_n) begin
            a_req_s <= 2'b00;  r_req_s <= 2'b00;  d_ack_s <= 2'b00;
        end
        else begin
            a_req_s <= {a_req_s[0], a_req};
            r_req_s <= {r_req_s[0], r_req};
            d_ack_s <= {d_ack_s[0], d_ack};
        end
    end

    //=========================================================================
    // lite domain: write channel -- AW and W are latched SEPARATELY, each on
    // its own channel handshake (Xilinx canonical Lite-slave shape).
    // WHY: an AXI4->AXI4-Lite conversion master (SmartConnect) may present AW
    // in an earlier cycle than W; accepting only on awvalid&&wvalid in the
    // SAME cycle consumes-and-forgets the AW handshake -> bvalid never comes
    // -> the fabric wedges (2026-10-10 on-board isolation: reads OK, UART
    // writes OK, only this slave's write stalled the bus).
    //=========================================================================
    localparam [1:0] LW_IDLE = 2'd0, LW_EXEC = 2'd1, LW_CLOSE = 2'd2;
    reg [1:0] lwst;
    reg       aw_pending, w_pending;
    reg [5:0] aw_word;                    // latched awaddr[7:2]
    reg [7:0] wd_byte;                    // latched wdata[7:0]

    always @(posedge aclk) begin
        if (!aresetn) begin
            lwst          <= LW_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            a_req         <= 1'b0;
            a_data        <= 16'd0;
            aw_pending    <= 1'b0;
            w_pending     <= 1'b0;
            aw_word       <= 6'd0;
            wd_byte       <= 8'd0;
        end
        else begin
            // ★FIX(2026-10-18): AXI 要求握手后下一拍立即撤销 VALID。
            //   原实现只在 LW_IDLE 清 -> LW_EXEC/LW_CLOSE 期间 BVALID 多拍为高,
            //   单次写会产生多次 B 握手（AXI4-Lite 协议违例, 会把互连的写跟踪弄乱）。
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            case (lwst)
            LW_IDLE: begin
                // ★FIX2(2026-10-18): ready 单拍握手模式。
                //   原实现 "s_axi_awready <= !aw_pending" 在握手后的下一拍
                //   仍输出 1 (空间窗口) -> 若主端/互连连续推进第二笔 AW/W,
                //   会被总线握手但 FSM 丢弃 -> 互连永等 B -> 后续读被阻塞/椰死。
                //   现在: ready 只拉高到握手为止, 握手拍立即拉低。
                //   另: 写响应 (bvalid) 未完成前不接受新写 (AXI 单笔 B 未消费不得再接新写)。
                if (!aw_pending && !s_axi_bvalid) begin
                    if (!s_axi_awready) s_axi_awready <= 1'b1;
                    else if (s_axi_awvalid) begin
                        s_axi_awready <= 1'b0;
                        aw_word       <= s_axi_awaddr[7:2];
                        aw_pending    <= 1'b1;
                    end
                end else s_axi_awready <= 1'b0;
                if (!w_pending && !s_axi_bvalid) begin
                    if (!s_axi_wready) s_axi_wready <= 1'b1;
                    else if (s_axi_wvalid) begin
                        s_axi_wready <= 1'b0;
                        wd_byte      <= s_axi_wdata[7:0];
                        w_pending    <= 1'b1;
                    end
                end else s_axi_wready <= 1'b0;
                // both captured -> decode and fire the mailbox
                if (aw_pending && w_pending) begin
                    if (aw_word == 6'h00)
                        a_data <= {OP_SET_MODE,  wd_byte};
                    else if (aw_word == 6'h01)
                        a_data <= {OP_READ_SLOT, wd_byte};
                    else if (aw_word == 6'h03)         // B3-1b: +0x0C SET_ENGINE
                        a_data <= {OP_SET_ENGINE, wd_byte};
                    else if (aw_word == 6'h12)         // B3-2: +0x48 SET_WRGO (翻转)
                        a_data <= {OP_SET_WRGO, wd_byte};
                    else if (aw_word == 6'h13)         // B3-2: +0x4C SET_WRACK (翻转)
                        a_data <= {OP_SET_WRACK, wd_byte};
                    else
                        a_data <= 16'd0;              // ignored offset, OKAY
                    a_req      <= 1'b1;
                    aw_pending <= 1'b0;
                    w_pending  <= 1'b0;
                    lwst       <= LW_EXEC;
                end
            end
            LW_EXEC: begin
                s_axi_awready <= 1'b0;   // ★FIX: 非 IDLE 态不得让 ready 保持上一拍的 1
                s_axi_wready  <= 1'b0;
                if (a_ack_s[1]) begin
                    a_req        <= 1'b0;             // user has the command
                    s_axi_bvalid <= 1'b1;
                    lwst         <= LW_CLOSE;
                end
            end
            LW_CLOSE: begin
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b0;
                // full 4-phase close: wait ack deasserted before next write
                if (!a_ack_s[1]) lwst <= LW_IDLE;
            end
            default: lwst <= LW_IDLE;
            endcase
        end
    end

    //=========================================================================
    // lite domain: read channel (ar accepted at once; rvalid when the user
    // snapshot returns; Lite has no latency limit)
    //=========================================================================
    localparam [1:0] LR_IDLE = 2'd0, LR_RACK = 2'd1, LR_DRQ = 2'd2, LR_DACK = 2'd3;
    reg [1:0] lrst;

    always @(posedge aclk) begin
        if (!aresetn) begin
            lrst          <= LR_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= 2'b00;
            r_req         <= 1'b0;
            r_addr        <= 6'd0;
            d_ack         <= 1'b0;
        end
        else begin
            d_ack <= d_ack;                             // default hold
            // ★FIX(2026-10-18): 同 BVALID: RVALID 必须在握手后立即撤销。
            //   原实现只在 LR_IDLE 清 -> LR_DACK 期间 RVALID 多拍为高, rready 常高
            //   时单次读会产生多次 R 握手（实测 1 AR -> 5 R）, 互连读跟踪错位/楔死。
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            case (lrst)
            LR_IDLE: begin
                // strictly serialized reads: never accept a new AR while the
                // previous rvalid is still pending (a pending rvalid makes a
                // naive master sample the OLD rdata -> stale reads).
                // arready STAYS HIGH through the accept (a level-polling
                // master would otherwise never see it high while arvalid is
                // held -> endless accepts; found by the bench, 2026-10-10).
                // ★FIX: 单拍 arready（先拉高一拍, 下一拍握手并立即撤销; 避免接受后
                //   多一拍 arready=1 导致流水主端的第二个 AR 被总线握手但被 FSM 丢弃）。
                // ★FIX2: 写事务未完全关闭 (FSM/待锁存/B) 前不接受新 AR：
                //   消除 "写命令后紧接读" 的跨通道竞争窗口。
                if (!s_axi_rvalid && !r_ack_s[1] && !s_axi_arready &&
                    (lwst == LW_IDLE) && !aw_pending && !w_pending && !s_axi_bvalid) begin
                    s_axi_arready <= 1'b1;
                end
                else if (s_axi_arready) begin
                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b0;
                        r_addr        <= s_axi_araddr[7:2];
                        r_req         <= 1'b1;
                        lrst          <= LR_RACK;
                    end
                end
                else begin
                    s_axi_arready <= 1'b0;
                end
            end
            LR_RACK: begin
                s_axi_arready <= 1'b0;     // busy: drop ready once accepted
                                          // (held-high through the mailbox
                                          // round made level masters issue
                                          // the next AR into a busy slave)
                if (r_ack_s[1]) begin
                    r_req <= 1'b0;                      // snapshot taken
                    lrst  <= LR_DRQ;
                end
            end
            LR_DRQ: begin
                if (d_req_s[1]) begin
                    s_axi_rdata  <= d_data;
                    s_axi_rvalid <= 1'b1;
                    d_ack        <= 1'b1;
                    lrst         <= LR_DACK;
                end
            end
            LR_DACK: begin
                if (!d_req_s[1]) begin
                    d_ack <= 1'b0;                      // full 4-phase close
                    lrst  <= LR_IDLE;
                end
            end
            default: lrst <= LR_IDLE;
            endcase
        end
    end

    //=========================================================================
    // user domain: command execution (mirror of cmd_channel U_* states)
    // U_CLOSE waits for the synchronized req deassertion before re-arming --
    // without it the req LEVEL re-triggers U_IDLE once per clock during the
    // 2FF round trip and the same command executes several times.
    //=========================================================================
    localparam [1:0] U_IDLE = 2'd0, U_SETTLE = 2'd1, U_PULSE = 2'd2;
    localparam       U_CLOSE = 2'd3;
    reg [1:0] ust;

    always @(posedge clk_user) begin
        if (!rst_user_n) begin
            ust              <= U_IDLE;
            a_ack            <= 1'b0;
            cfg_mode         <= 1'b0;                  // SEQ after reset
            cfg_rd_slot      <= 8'd0;
            cfg_rd_engine    <= 1'b0;                  // B3-1b: 桥硬件读
            cfg_wr_go        <= 1'b0;                  // B3-2: DMA 写 GO 翻转位
            cfg_wr_ack       <= 1'b0;                  // B3-2: DMA 写 fault 恢复 ACK 翻转位
            lite_engine_cnt  <= 16'd0;
            rd_req_pulse     <= 1'b0;
            cfg_wr_pulse     <= 1'b0;
            lite_exec_cnt    <= 16'd0;
            lite_rd_trig_cnt <= 16'd0;
        end
        else begin
            rd_req_pulse <= 1'b0;
            cfg_wr_pulse <= 1'b0;
            case (ust)
            U_IDLE: begin
`ifdef AXI_LITE_REGS_DEFECT
                // DEFECT: pulse in the same cycle the slot is written -- a
                // downstream capture flop (frame_mem_if style) samples the OLD
                // slot, violating "cfg stable >= 1 clk before the pulse".
                if (a_req_s[1]) begin
                    a_ack <= 1'b1;
                    if (a_data[15:8] == OP_SET_MODE) begin
                        cfg_mode       <= a_data[0];
                        cfg_wr_pulse   <= 1'b1;
                        lite_exec_cnt  <= lite_exec_cnt + 16'd1;
                        ust            <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_SET_ENGINE) begin  // B3-1b
                        cfg_rd_engine  <= a_data[0];   // (缺陷路径语义同正路)
                        cfg_wr_pulse   <= 1'b1;
                        lite_exec_cnt  <= lite_exec_cnt + 16'd1;
                        ust            <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_SET_WRGO) begin    // B3-2
                        cfg_wr_go     <= ~cfg_wr_go;
                        lite_exec_cnt <= lite_exec_cnt + 16'd1;
                        ust           <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_SET_WRACK) begin   // B3-2: fault 恢复 ACK
                        cfg_wr_ack    <= ~cfg_wr_ack;
                        lite_exec_cnt <= lite_exec_cnt + 16'd1;
                        ust           <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_READ_SLOT) begin
                        cfg_mode         <= 1'b1;
                        cfg_rd_slot      <= a_data[7:0];
                        rd_req_pulse     <= 1'b1;
                        cfg_wr_pulse     <= 1'b1;
                        lite_exec_cnt    <= lite_exec_cnt + 16'd1;
                        lite_rd_trig_cnt <= lite_rd_trig_cnt + 16'd1;
                        ust              <= U_PULSE;
                    end
                    else ust <= U_CLOSE;                // ignored opcode
                end
`else
                if (a_req_s[1]) begin
                    a_ack <= 1'b1;
                    if (a_data[15:8] == OP_SET_MODE) begin
                        cfg_mode      <= a_data[0];     // bit0 only
                        cfg_wr_pulse  <= 1'b1;
                        lite_exec_cnt <= lite_exec_cnt + 16'd1;
                        ust           <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_SET_ENGINE) begin  // B3-1b
                        cfg_rd_engine  <= a_data[0];    // 0=桥 1=DMA
                        cfg_wr_pulse   <= 1'b1;
                        lite_exec_cnt  <= lite_exec_cnt + 16'd1;
                        lite_engine_cnt<= lite_engine_cnt + 16'd1;
                        ust            <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_SET_WRGO) begin    // B3-2: S2MM 已编程, 翻 GO
                        cfg_wr_go     <= ~cfg_wr_go;
                        lite_exec_cnt <= lite_exec_cnt + 16'd1;
                        ust           <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_SET_WRACK) begin   // B3-2: 写引擎 fault 恢复 ACK
                        cfg_wr_ack    <= ~cfg_wr_ack;
                        lite_exec_cnt <= lite_exec_cnt + 16'd1;
                        ust           <= U_CLOSE;
                    end
                    else if (a_data[15:8] == OP_READ_SLOT) begin
                        cfg_mode      <= 1'b1;          // reads imply RND
                        cfg_rd_slot   <= a_data[7:0];
                        cfg_wr_pulse  <= 1'b1;
                        lite_exec_cnt <= lite_exec_cnt + 16'd1;
                        ust           <= U_SETTLE;      // settle first
                    end
                    else ust <= U_CLOSE;                 // ignored opcode
                end
`endif
            end
`ifndef AXI_LITE_REGS_DEFECT
            U_SETTLE: begin
                rd_req_pulse     <= 1'b1;               // cfg stable >= 1 clk
                lite_rd_trig_cnt <= lite_rd_trig_cnt + 16'd1;
                ust              <= U_PULSE;
            end
`endif
            U_PULSE: begin
`ifdef AXI_LITE_REGS_DEFECT
                // DEFECT: hold the pulse a SECOND clock (width 2) -- violates
                // the W5 "single user_clk pulse" contract; in RND mode this
                // double-triggers the read. Observable at the module boundary
                // (pulse width monitor), unlike a same-cycle cfg-write defect
                // which is invisible through register boundaries.
                rd_req_pulse <= 1'b1;
`else
                rd_req_pulse <= 1'b0;
`endif
                ust          <= U_CLOSE;
            end
            U_CLOSE: begin
                if (!a_req_s[1]) begin
                    a_ack <= 1'b0;                      // close mailbox A
                    ust   <= U_IDLE;
                end
            end
            default: ust <= U_IDLE;
            endcase
        end
    end

    //=========================================================================
    // user domain: read snapshot (mailbox C ack + mailbox D data)
    //=========================================================================
    localparam [1:0] UR_IDLE = 2'd0, UR_CLOSE = 2'd1, UR_RACKCL = 2'd2;
    reg [1:0] urst;

    always @(posedge clk_user) begin
        if (!rst_user_n) begin
            urst   <= UR_IDLE;
            r_ack  <= 1'b0;
            d_req  <= 1'b0;
            d_data <= 32'd0;
        end
        else begin
            case (urst)
            UR_IDLE: begin
                if (r_req_s[1]) begin
                    r_ack <= 1'b1;
                    // snapshot ALL readable regs in ONE clock (stable copy)
                    case (r_addr)
                        6'h02: d_data <= {16'd0, u_wr_frame};
                        6'h03: d_data <= {16'd0, u_rd_frame};
                        6'h04: d_data <= {16'd0, u_buf_drop};
                        6'h05: d_data <= {8'd1, u_wr_frame[7:0], 16'd0};
                        6'h06: d_data <= {ctl_owner, 1'b0, lite_rd_trig_cnt};
                        6'h07: d_data <= REG_ID;
                        // B3-0: +0x20 LAT_W / +0x24 LAT_R (r_addr = awaddr[7:2])
                        6'h08: d_data <= {16'd0, lat_w};
                        6'h09: d_data <= {16'd0, lat_r};
                        // B3-1a: +0x28 DMA_Q0 / +0x2C DMA_Q1 / +0x30 DMA_Q2
                        6'h0A: d_data <= dma_q0;
                        6'h0B: d_data <= dma_q1;
                        6'h0C: d_data <= dma_q2;
                        // B3-1b: +0x34 DMA_REQ / +0x38 DMA_ARL
                        6'h0D: d_data <= dma_req;
                        6'h0E: d_data <= dma_arl;
                        6'h0F: d_data <= dbg_emit_q1;   // B3-1b: {len,slot,byte0}
                        // B3-2: +0x40 WR_REQ / +0x44 WR_DBG (DMA 写引擎取证)
                        6'h10: d_data <= dma_wr_req;
                        6'h11: d_data <= dma_wr_dbg;
                        default: d_data <= 32'd0;
                    endcase
                    d_req <= 1'b1;                      // data held stable
                    urst  <= UR_CLOSE;
                end
            end
            UR_CLOSE: begin
                if (d_ack_s[1]) begin
                    d_req <= 1'b0;                      // data consumed
                    urst  <= UR_RACKCL;
                end
            end
            UR_RACKCL: begin
                if (!r_req_s[1]) begin
                    r_ack <= 1'b0;                      // close mailbox C
                    urst  <= UR_IDLE;
                end
            end
            default: urst <= UR_IDLE;
            endcase
        end
    end

endmodule
