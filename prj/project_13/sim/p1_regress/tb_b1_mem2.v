//=============================================================================
// tb_b1_mem2.v -- B1 reset-pairing regression, REVERSE direction (bridge 2)
//                 prj13 P1-5 suite, derived from prj12 evidence TB
//                 prj12/out/evidence_2026-11-07_dma_stall/sim/tb_frame_mem_stall.v
//-----------------------------------------------------------------------------
// WHY A SECOND TB:
//   u_mem2 (aurora_mem_bridge.v L982/L994) has EXACTLY the same reset wiring as
//   u_mem (L825/L838) but is instantiated with HAS_DMA(0): the reply / B->A
//   direction still writes DDR through the bridge's OWN hardware AXI4 write FSM
//   instead of the axi_dma S2MM shim.  The 2026-11-07 audit only proved the
//   A->B direction in simulation; this TB closes that gap by exercising the same
//   one-sided reset injection against a HAS_DMA(0) instance.
//   AUDIT_mechanism.md section 7 predicts: mem2_wr_frm / mem2_ost freeze while
//   the upstream counters keep counting -- i.e. the same self-lock, mirrored.
//
// DIFFERENCES FROM tb_b1_matrix.v:
//   * DUT parameter HAS_DMA = 0 (same as u_mem2)
//   * no MicroBlaze/S2MM model: a minimal always-ready AXI4 write slave stands in
//     for the MIG (awready/wready=1, bvalid held until bready, bresp=OKAY)
//   * commit content is captured off m_axi_wvalid/m_axi_wdata/m_axi_wstrb
//   * the read engine is left parked (rd_req tied 0, arready tied 0) because this
//     TB is about the WRITE path only
//
// SCENARIOS / ASSERTIONS: identical names and semantics to tb_b1_matrix.v
//   (PRE / FLAPS / POST / BOTH plusargs; A1..A5 + A9; same RESULT line format).
//=============================================================================
`timescale 1ns/1ps

module tb_b1_mem2;

    localparam FRAME_WR_CLKS = 154;
    localparam FRAME_BYTES   = 155;
    localparam CAP_MAX       = 128;

`ifdef B1_PATCHED
    localparam B1_ON = 1;
`else
    localparam B1_ON = 0;
`endif

    //-------------------------------------------------------------------------
    // clocks
    //-------------------------------------------------------------------------
    reg user_clk = 1'b0;
    reg ui_clk   = 1'b0;
    always #5.000 user_clk = ~user_clk;
    always #2.500 ui_clk   = ~ui_clk;

    reg user_rst_n = 1'b0;
    reg ui_rst_n   = 1'b0;

    //-------------------------------------------------------------------------
    // frame stream in
    //-------------------------------------------------------------------------
    reg  [7:0] wr_data = 8'h00;
    reg        wr_en   = 1'b0;
    wire       wr_hold;

    // frame stream out (not observed)
    wire [7:0]  rd_data;
    wire        rd_en;
    wire [7:0]  rd_slot_o;
    wire [15:0] rd_len_o;
    wire        rd_frame_done;
    wire        rd_busy;

    // user domain status
    wire [15:0] u_wr_frame;
    wire [15:0] u_rd_frame;
    wire [15:0] u_buf_drop;
    wire [31:0] u_hold_cycles;
    wire [8:0]  outstanding_sync;
    wire [15:0] lat_w, lat_r;

    // ui domain status
    wire [15:0] ro_wm;
    wire [15:0] ro_wr_frame;
    wire [15:0] ro_wr_stall;
    wire [15:0] ro_rd_frame;
    wire [15:0] ro_ill_rd;
    wire [15:0] ro_noframe;
    wire [15:0] ro_bresp_err;
    wire [15:0] ro_len_err;
    wire [8:0]  ro_outstanding;
    wire [7:0]  ro_dbg_wr_slot;
    wire [7:0]  ro_dbg_rd_slot;
    wire [31:0] dbg_wr_cycles, dbg_rd_cycles, dbg_wr_beats, dbg_rd_beats;

    // DMA-side ports (HAS_DMA=0 -> driven constant 0 inside the bridge)
    reg          dma_wr_go     = 1'b0;
    reg          dma_wr_ack    = 1'b0;
    reg          s2mm_introut  = 1'b0;
    reg          dma_wr_tready = 1'b1;
    wire [511:0] dma_wr_tdata;
    wire [63:0]  dma_wr_tkeep;
    wire         dma_wr_tlast;
    wire         dma_wr_tvalid;
    wire [31:0]  ro_dma_wr_req;
    wire [31:0]  ro_dma_wr_dbg;
    wire [15:0]  ro_stat_wr_timeout;
    wire [2:0]   ro_dbg_wr_state;

    wire [31:0]  ro_dma_req;
    wire [31:0]  ro_dbg_emit;
    wire         dma_s_tready;

    //-------------------------------------------------------------------------
    // AXI4 write slave model standing in for the MIG (write channel only)
    //-------------------------------------------------------------------------
    reg        axi_awready = 1'b1;
    reg        axi_wready  = 1'b1;
    reg        axi_bvalid  = 1'b0;
    reg        axi_bpend   = 1'b0;
    reg  [1:0] axi_bresp   = 2'b00;

    wire [31:0]  m_axi_awaddr;
    wire [7:0]   m_axi_awlen;
    wire [2:0]   m_axi_awsize;
    wire [1:0]   m_axi_awburst;
    wire         m_axi_awvalid;
    wire [511:0] m_axi_wdata;
    wire [63:0]  m_axi_wstrb;
    wire         m_axi_wlast;
    wire         m_axi_wvalid;
    wire         m_axi_bready;
    wire [31:0]  m_axi_araddr;
    wire [7:0]   m_axi_arlen;
    wire [2:0]   m_axi_arsize;
    wire [1:0]   m_axi_arburst;
    wire         m_axi_arvalid;
    wire         m_axi_rready;
    wire [3:0]   m_axi_awid;
    wire [0:0]   m_axi_awlock;
    wire [3:0]   m_axi_awcache;
    wire [2:0]   m_axi_awprot;
    wire [3:0]   m_axi_awqos;
    wire [3:0]   m_axi_arid;
    wire [0:0]   m_axi_arlock;
    wire [3:0]   m_axi_arcache;
    wire [2:0]   m_axi_arprot;
    wire [3:0]   m_axi_arqos;

    always @(posedge ui_clk) begin
        if (!ui_rst_n) begin
            axi_bvalid <= 1'b0;
            axi_bpend  <= 1'b0;
        end else begin
            if (m_axi_wvalid && axi_wready && m_axi_wlast) axi_bpend <= 1'b1;
            if (axi_bvalid && m_axi_bready) begin
                axi_bvalid <= 1'b0;
                axi_bpend  <= 1'b0;
            end else if (axi_bpend) begin
                axi_bvalid <= 1'b1;
            end
        end
    end

    //-------------------------------------------------------------------------
    // B1 switch (identical to tb_b1_matrix.v)
    //-------------------------------------------------------------------------
`ifdef B1_PATCHED
    wire aurora_rst_tb = ~user_rst_n;
    reg  [3:0] arst_ui_pipe_tb;
    always @(posedge ui_clk or negedge ui_rst_n) begin
        if (!ui_rst_n) arst_ui_pipe_tb <= 4'hF;
        else           arst_ui_pipe_tb <= {arst_ui_pipe_tb[2:0], aurora_rst_tb};
    end
    wire ui_link_rst_n = ui_rst_n & ~(|arst_ui_pipe_tb);
`endif

    // read engine parked: this TB observes the write path only
    reg mem_rd_req = 1'b0;

    //-------------------------------------------------------------------------
    // DUT: real frame_mem_if with HAS_DMA=0 (same parameters as u_mem2)
    //-------------------------------------------------------------------------
    frame_mem_if #(
        .SLOT_BASE (32'h0020_0000),
        .MAX_LEN   (16'd1538),
        .BF_AW     (12),
        .DF_AW     (3),
        .HAS_DMA   (0)
    ) dut (
        .user_clk(user_clk), .user_rst_n(user_rst_n),
        .wr_data(wr_data), .wr_en(wr_en), .wr_hold(wr_hold),
        .rd_data(rd_data), .rd_en(rd_en),
        .rd_slot_o(rd_slot_o), .rd_len_o(rd_len_o),
        .rd_frame_done(rd_frame_done),
        .rd_req(mem_rd_req), .rd_busy(rd_busy),
        .cfg_mode(1'b0), .cfg_rd_slot(8'd0),
        .ro_u_wr_frame(u_wr_frame), .ro_u_rd_frame(u_rd_frame),
        .ro_u_buf_drop(u_buf_drop), .ro_u_hold_cycles(u_hold_cycles),
        .ro_outstanding_sync(outstanding_sync),
        .ro_lat_w(lat_w), .ro_lat_r(lat_r),
        .dma_engine(1'b0),
        .ro_dbg_emit(ro_dbg_emit),
        .dma_s_tdata(512'd0), .dma_s_tkeep(64'd0), .dma_s_tlast(1'b0),
        .dma_s_tvalid(1'b0), .dma_s_tready(dma_s_tready),
        .ro_dma_req(ro_dma_req),
        .dma_wr_go(dma_wr_go), .dma_wr_ack(dma_wr_ack),
        .s2mm_introut(s2mm_introut),
        .dma_wr_tdata(dma_wr_tdata), .dma_wr_tkeep(dma_wr_tkeep),
        .dma_wr_tlast(dma_wr_tlast), .dma_wr_tvalid(dma_wr_tvalid),
        .dma_wr_tready(dma_wr_tready),
        .ro_dma_wr_req(ro_dma_wr_req), .ro_dma_wr_dbg(ro_dma_wr_dbg),
        .ro_stat_wr_timeout(ro_stat_wr_timeout),
        .ro_dbg_wr_state(ro_dbg_wr_state),
        .ui_clk(ui_clk), .ui_rst_n(ui_rst_n), .calib_ok(1'b1),
`ifdef B1_PATCHED
        .ui_link_rst_n(ui_link_rst_n),
`endif
        .ro_wm(ro_wm), .ro_wr_frame(ro_wr_frame), .ro_wr_stall(ro_wr_stall),
        .ro_rd_frame(ro_rd_frame), .ro_ill_rd(ro_ill_rd), .ro_noframe(ro_noframe),
        .ro_bresp_err(ro_bresp_err), .ro_len_err(ro_len_err),
        .ro_outstanding(ro_outstanding),
        .ro_dbg_wr_slot(ro_dbg_wr_slot), .ro_dbg_rd_slot(ro_dbg_rd_slot),
        .dbg_wr_cycles(dbg_wr_cycles), .dbg_rd_cycles(dbg_rd_cycles),
        .dbg_wr_beats(dbg_wr_beats), .dbg_rd_beats(dbg_rd_beats),
        // ---- AXI4 master -> local always-ready write slave ----
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bresp(axi_bresp), .m_axi_bvalid(axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(1'b0),
        .m_axi_rdata(512'd0), .m_axi_rresp(2'b00), .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0), .m_axi_rready(m_axi_rready),
        .m_axi_awid(m_axi_awid), .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache), .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos), .m_axi_bid(4'd0),
        .m_axi_arid(m_axi_arid), .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache), .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos), .m_axi_rid(4'd0)
    );

    //-------------------------------------------------------------------------
    // power-on RAM deposit (TB side only, RTL untouched)
    //-------------------------------------------------------------------------
    integer k;
    initial begin
        for (k = 0; k < 4096; k = k + 1) begin
            dut.u_wr_bytes.ram[k] = 8'h00;
            dut.u_rd_bytes.ram[k] = 8'h00;
        end
        for (k = 0; k < 8; k = k + 1) begin
            dut.u_wr_desc.ram[k] = 16'h0000;
            dut.u_rd_desc.ram[k] = 25'h0;
        end
        for (k = 0; k < 4; k = k + 1) dut.u_rd_cmd.ram[k] = 9'h0;
    end

    //-------------------------------------------------------------------------
    // stimulus / bookkeeping (same as tb_b1_matrix.v)
    //-------------------------------------------------------------------------
    task send_frame(input integer len, input [7:0] seed);
        integer i;
        begin
            @(negedge user_clk);
            wr_en   = 1'b1;
            wr_data = seed;
            for (i = 0; i < len; i = i + 1) begin
                @(negedge user_clk);
                wr_data = seed + i;
            end
            @(negedge user_clk);
            wr_en   = 1'b0;
            wr_data = 8'h00;
            repeat (60) @(posedge user_clk);
        end
    endtask

    task snap(input [255:0] label);
        begin
            $display("[SNAP] %0s u_wr=%0d u_drop=%0d hold_cyc=%0d wr_hold=%b | wr_bytes wr_bin=%0d rd_bin=%0d level=%0d | wr_desc wr_bin=%0d rd_bin=%0d | ui wr_frm=%0d len_err=%0d stall=%0d ost=%0d",
                     label, u_wr_frame, u_buf_drop, u_hold_cycles, wr_hold,
                     dut.u_wr_bytes.wr_bin, dut.u_wr_bytes.rd_bin, dut.u_wr_bytes.wr_level,
                     dut.u_wr_desc.wr_bin, dut.u_wr_desc.rd_bin,
                     ro_wr_frame, ro_len_err, ro_wr_stall, ro_outstanding);
        end
    endtask

    integer errors = 0;

    task pass(input [8*128-1:0] name);
        begin
            $display("[ASSERT-PASS] %0s", name);
        end
    endtask

    task fail(input [8*128-1:0] name, input [8*96-1:0] detail);
        begin
            errors = errors + 1;
            $display("[ASSERT-FAIL] %0s : %0s", name, detail);
        end
    endtask

    // per-event trace (no g_wr_dma reference: that generate block is absent here)
    reg [15:0] t_wr = 16'hffff, t_le = 16'hffff, t_ost = 16'hffff;
    always @(posedge ui_clk) begin
        if (ro_wr_frame !== t_wr || ro_len_err !== t_le || ro_outstanding !== t_ost) begin
            $display("[TRACE] t=%0t wr_frm=%0d len_err=%0d ost=%0d | wf_rd_bin=%0d wf_level=%0d | awlen=%0d",
                     $time, ro_wr_frame, ro_len_err, ro_outstanding,
                     dut.u_wr_bytes.rd_bin, dut.u_wr_bytes.wr_level, m_axi_awlen);
            t_wr = ro_wr_frame; t_le = ro_len_err; t_ost = ro_outstanding;
        end
    end

    integer hold_run = 0;
    integer hold_max = 0;
    always @(posedge user_clk) begin
        if (wr_hold) begin
            hold_run = hold_run + 1;
            if (hold_run > hold_max) hold_max = hold_run;
        end else hold_run = 0;
    end

    //-------------------------------------------------------------------------
    // COMMIT CAPTURE off the AXI4 write channel (never reset -> survives flaps)
    //-------------------------------------------------------------------------
    integer   cap_n;
    reg [7:0] cap_first [0:CAP_MAX-1];
    integer   cap_bytes [0:CAP_MAX-1];
    reg       cap_in;
    integer   cap_cur_bytes;
    reg [7:0] cap_cur_first;

    function integer popc64(input [63:0] v);
        integer ii;
        begin
            popc64 = 0;
            for (ii = 0; ii < 64; ii = ii + 1) if (v[ii]) popc64 = popc64 + 1;
        end
    endfunction

    initial begin
        cap_n = 0; cap_in = 1'b0; cap_cur_bytes = 0; cap_cur_first = 8'h00;
    end

    always @(posedge ui_clk) begin
        if (m_axi_wvalid && axi_wready) begin
            if (!cap_in) begin
                cap_cur_first <= m_axi_wdata[7:0];
                cap_cur_bytes <= popc64(m_axi_wstrb);
                cap_in        <= 1'b1;
            end else begin
                cap_cur_bytes <= cap_cur_bytes + popc64(m_axi_wstrb);
            end
            if (m_axi_wlast) begin
                if (cap_n < CAP_MAX) begin
                    cap_first[cap_n] <= cap_in ? cap_cur_first : m_axi_wdata[7:0];
                    cap_bytes[cap_n] <= (cap_in ? cap_cur_bytes : 0) + popc64(m_axi_wstrb);
                end
                cap_n <= cap_n + 1;
                cap_in <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // main flow
    //-------------------------------------------------------------------------
    integer pre_frames, flaps, post_frames, both_resets;
    integer i, f, wc;
    integer pre_ok;
    integer frm0, len_err0, cap_mark, commits, cd, bad;

    localparam WAIT_MAX = 60000;

    initial begin
        if (!$value$plusargs("PRE=%d",   pre_frames))  pre_frames  = 3;
        if (!$value$plusargs("FLAPS=%d", flaps))       flaps       = 1;
        if (!$value$plusargs("POST=%d",  post_frames)) post_frames = 3;
        if (!$value$plusargs("BOTH=%d",  both_resets)) both_resets = 0;

        $display("=========================================================");
        $display(" TB_PARAMS: PRE=%0d FLAPS=%0d POST=%0d BOTH=%0d B1=%0d DUT=mem2(HAS_DMA=0)",
                 pre_frames, flaps, post_frames, both_resets, B1_ON);
        $display("=========================================================");

        user_rst_n = 1'b0; ui_rst_n = 1'b0;
        repeat (20) @(posedge ui_clk);
        ui_rst_n = 1'b1;
        repeat (20) @(posedge ui_clk);
        user_rst_n = 1'b1;
        repeat (200) @(posedge user_clk);
        snap("T0_after_power_on");

        if (pre_frames > 0) begin
            for (i = 0; i < pre_frames; i = i + 1) send_frame(FRAME_WR_CLKS, 8'h10 + i);
            pre_ok = 0;
            for (wc = 0; wc < WAIT_MAX; wc = wc + 1) begin
                @(posedge ui_clk);
                if (ro_wr_frame >= pre_frames) begin pre_ok = 1; wc = WAIT_MAX; end
            end
            snap("T1_probe_pre");
            if (pre_ok && ro_len_err == 16'd0 && !wr_hold)
                pass("A1_HEALTHY_BASELINE pre-frames committed, len_err=0, hold=0");
            else
                fail("A1_HEALTHY_BASELINE", "baseline unhealthy = harness problem, not the DUT bug");
        end else begin
            if ((ro_len_err == 16'd0) && !wr_hold && (ro_wr_frame == 16'd0))
                pass("A1_HEALTHY_BASELINE clean power-on, no traffic, len_err=0, hold=0");
            else
                fail("A1_HEALTHY_BASELINE", "clean power-on window already dirty");
        end

        for (f = 0; f < flaps; f = f + 1) begin
            frm0     = ro_wr_frame;
            cap_mark = cap_n;

            $display("[EVENT] t=%0t flap %0d/%0d: user_rst_n=0 for 2us%s",
                     $time, f + 1, flaps, (both_resets != 0) ? " + ui_rst_n=0 (BOTH)" : " ; ui_rst_n stays 1");
            user_rst_n = 1'b0;
            if (both_resets != 0) ui_rst_n = 1'b0;
            repeat (400) @(posedge ui_clk);
            user_rst_n = 1'b1;
            if (both_resets != 0) ui_rst_n = 1'b1;
            repeat (400) @(posedge user_clk);
            snap("T2_after_flap");

            if (both_resets != 0) frm0 = ro_wr_frame;
            len_err0 = ro_len_err;

            for (i = 0; i < post_frames; i = i + 1)
                send_frame(FRAME_WR_CLKS, 8'h80 + i);

            for (wc = 0; wc < WAIT_MAX; wc = wc + 1) begin
                @(posedge ui_clk);
                if ((ro_wr_frame - frm0) >= post_frames) begin wc = WAIT_MAX; end
            end
            repeat (200) @(posedge ui_clk);
            snap("T3_after_post_frames");

            commits = ro_wr_frame - frm0;
            if (commits == post_frames)
                pass("A2_EXACT_COMMITS exact count after flap");
            else begin
                $display("[INFO] flap %0d: expected %0d commits, saw %0d", f + 1, post_frames, commits);
                fail("A2_EXACT_COMMITS", "write path lost or replayed frames after the flap");
            end

            if (u_hold_cycles <= 32'd200)
                pass("A3_NO_PERMANENT_HOLD wr_hold not stuck");
            else begin
                $display("[INFO] u_hold_cycles since user reset = %0d user_clk", u_hold_cycles);
                fail("A3_NO_PERMANENT_HOLD", "wr_hold stuck high -> accept policy permanently closed");
            end

            if (ro_len_err == len_err0)
                pass("A4_LEN_ERR_UNCHANGED real 155B frames left len_err alone");
            else begin
                $display("[INFO] len_err %0d -> %0d during real frames", len_err0, ro_len_err);
                fail("A4_LEN_ERR_UNCHANGED", "len_err moved although every real frame is 155B");
            end

            cd  = cap_n - cap_mark;
            bad = 0;
            $display("[INFO] flap %0d: captured %0d commits (expected %0d)", f + 1, cd, post_frames);
            for (i = 0; i < post_frames; i = i + 1) begin
                if ((i < cd) && ((cap_mark + i) < CAP_MAX)) begin
                    $display("[INFO]   frame %0d: first_byte=%02h bytes=%0d (expect %02h / %0d)",
                             i, cap_first[cap_mark + i], cap_bytes[cap_mark + i],
                             8'h80 + i, FRAME_BYTES);
                    if (cap_first[cap_mark + i] !== (8'h80 + i)) bad = bad + 1;
                    if (cap_bytes[cap_mark + i] != FRAME_BYTES) bad = bad + 1;
                end
            end
            if ((cd == post_frames) && (bad == 0))
                pass("A5_COMMIT_CONTENT_OK every committed frame carried the bytes we sent");
            else
                fail("A5_COMMIT_CONTENT_OK", "garbage / stale / missing frame content after the flap");
        end

        $display("[EVENT] t=%0t full reconfiguration equivalent: pulse BOTH resets", $time);
        user_rst_n = 1'b0; ui_rst_n = 1'b0;
        repeat (400) @(posedge ui_clk);
        user_rst_n = 1'b1; ui_rst_n = 1'b1;
        repeat (400) @(posedge user_clk);
        frm0     = ro_wr_frame;
        cap_mark = cap_n;
        for (i = 0; i < post_frames; i = i + 1) send_frame(FRAME_WR_CLKS, 8'hC0 + i);
        for (wc = 0; wc < WAIT_MAX; wc = wc + 1) begin
            @(posedge ui_clk);
            if ((ro_wr_frame - frm0) >= post_frames) begin wc = WAIT_MAX; end
        end
        repeat (200) @(posedge ui_clk);
        snap("T4_after_full_reset");

        cd  = cap_n - cap_mark;
        bad = 0;
        for (i = 0; i < post_frames; i = i + 1) begin
            if ((i < cd) && ((cap_mark + i) < CAP_MAX)) begin
                if (cap_first[cap_mark + i] !== (8'hC0 + i)) bad = bad + 1;
                if (cap_bytes[cap_mark + i] != FRAME_BYTES)  bad = bad + 1;
            end
        end
        if (((ro_wr_frame - frm0) == post_frames) && (cd == post_frames) && (bad == 0))
            pass("A9_RECOVER_BY_FULL_RESET write path restored by a both-domain reset");
        else
            fail("A9_RECOVER_BY_FULL_RESET", "even a full reset did not restore: analysis incomplete");

        $display("---------------------------------------------------------");
        if (errors == 0)
            $display("RESULT: PASS  params=%0d/%0d/%0d/%0d b1=%0d dut=mem2 failed_asserts=%0d",
                     pre_frames, flaps, post_frames, both_resets, B1_ON, errors);
        else
            $display("RESULT: FAIL  params=%0d/%0d/%0d/%0d b1=%0d dut=mem2 failed_asserts=%0d",
                     pre_frames, flaps, post_frames, both_resets, B1_ON, errors);
        $display("---------------------------------------------------------");
        if (errors != 0) $fatal(1, "tb_b1_mem2: assertions failed");
        $finish;
    end

    initial begin
        #20000000;
        $display("[FATAL] global timeout 20 ms");
        $fatal(1, "global timeout");
    end

endmodule
