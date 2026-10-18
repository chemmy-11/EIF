// =============================================================================
// tb_axi_dma_s2mm.sv -- prj11 R2 offline IP-level testbench for xilinx axi_dma
//
// Scope:
//   * official xilinx.com:ip:axi_dma:7.1, same config as prj11 R2 BD
//     (direct register mode, 512-bit MM/stream, S2MM burst 16, DRE off)
//   * S2MM 86-byte packet at 0x0010_0000: byte-lane mapping check
//   * S2MM_LENGTH / S2MM_DMASR semantics check
//   * short-packet case with S2MM_LENGTH=256 but only 86 bytes sent
//   * MM2S read-back of the same 86 bytes (bonus)
//
// The RAM is a simple AXI4 slave (axi_ram_model.sv) initialised to 0xEE.
// =============================================================================
`timescale 1ns/1ps

module tb_axi_dma_s2mm;

    // ------------------------------------------------------------------ clock
    logic clk  = 1'b0;
    logic rstn = 1'b0;

    always #5 clk = ~clk;   // 100 MHz

    initial begin
        $timeformat(-9, 3, " ns", 12);
        repeat (20) @(posedge clk);
        rstn <= 1'b1;
    end

    // Compact VCD: only the TB-level interface signals (not the 2 MiB RAM).
    initial begin
        $dumpfile("tb_axi_dma_s2mm.vcd");
        $dumpvars(0, tb_axi_dma_s2mm.clk);
        $dumpvars(0, tb_axi_dma_s2mm.rstn);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_awaddr);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_awvalid);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_awready);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_wdata);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_wvalid);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_wready);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_bvalid);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_bready);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_araddr);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_arvalid);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_rdata);
        $dumpvars(0, tb_axi_dma_s2mm.s_axi_lite_rvalid);
        $dumpvars(0, tb_axi_dma_s2mm.s_axis_s2mm_tdata);
        $dumpvars(0, tb_axi_dma_s2mm.s_axis_s2mm_tkeep);
        $dumpvars(0, tb_axi_dma_s2mm.s_axis_s2mm_tvalid);
        $dumpvars(0, tb_axi_dma_s2mm.s_axis_s2mm_tready);
        $dumpvars(0, tb_axi_dma_s2mm.s_axis_s2mm_tlast);
        $dumpvars(0, tb_axi_dma_s2mm.m_axis_mm2s_tdata);
        $dumpvars(0, tb_axi_dma_s2mm.m_axis_mm2s_tkeep);
        $dumpvars(0, tb_axi_dma_s2mm.m_axis_mm2s_tvalid);
        $dumpvars(0, tb_axi_dma_s2mm.m_axis_mm2s_tlast);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_awaddr);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_awlen);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_awvalid);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_awready);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_wdata);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_wstrb);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_wlast);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_wvalid);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_wready);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_s2mm_bvalid);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_araddr);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_arlen);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_arvalid);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_arready);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_rdata);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_rlast);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_rvalid);
        $dumpvars(0, tb_axi_dma_s2mm.m_axi_mm2s_rready);
        $dumpvars(0, tb_axi_dma_s2mm.s2mm_introut);
        $dumpvars(0, tb_axi_dma_s2mm.mm2s_introut);
        $dumpvars(0, tb_axi_dma_s2mm.dbg_addr);
        $dumpvars(0, tb_axi_dma_s2mm.dbg_data);
    end

    // -------------------------------------------------------------- AXI-Lite
    logic [9:0]  s_axi_lite_awaddr  = '0;
    logic        s_axi_lite_awvalid = 1'b0;
    logic        s_axi_lite_awready;
    logic [31:0] s_axi_lite_wdata   = '0;
    logic        s_axi_lite_wvalid  = 1'b0;
    logic        s_axi_lite_wready;
    logic [1:0]  s_axi_lite_bresp;
    logic        s_axi_lite_bvalid;
    logic        s_axi_lite_bready  = 1'b0;
    logic [9:0]  s_axi_lite_araddr  = '0;
    logic        s_axi_lite_arvalid = 1'b0;
    logic        s_axi_lite_arready;
    logic [31:0] s_axi_lite_rdata;
    logic [1:0]  s_axi_lite_rresp;
    logic        s_axi_lite_rvalid;
    logic        s_axi_lite_rready  = 1'b0;

    // -------------------------------------------------- AXI4 S2MM (write side)
    logic [31:0]  m_axi_s2mm_awaddr;
    logic [7:0]   m_axi_s2mm_awlen;
    logic [2:0]   m_axi_s2mm_awsize;
    logic [1:0]   m_axi_s2mm_awburst;
    logic [2:0]   m_axi_s2mm_awprot;
    logic [3:0]   m_axi_s2mm_awcache;
    logic         m_axi_s2mm_awvalid;
    logic         m_axi_s2mm_awready;
    logic [511:0] m_axi_s2mm_wdata;
    logic [63:0]  m_axi_s2mm_wstrb;
    logic         m_axi_s2mm_wlast;
    logic         m_axi_s2mm_wvalid;
    logic         m_axi_s2mm_wready;
    logic [1:0]   m_axi_s2mm_bresp;
    logic         m_axi_s2mm_bvalid;
    logic         m_axi_s2mm_bready;

    // -------------------------------------------------- AXI4 MM2S (read side)
    logic [31:0]  m_axi_mm2s_araddr;
    logic [7:0]   m_axi_mm2s_arlen;
    logic [2:0]   m_axi_mm2s_arsize;
    logic [1:0]   m_axi_mm2s_arburst;
    logic [2:0]   m_axi_mm2s_arprot;
    logic [3:0]   m_axi_mm2s_arcache;
    logic         m_axi_mm2s_arvalid;
    logic         m_axi_mm2s_arready;
    logic [511:0] m_axi_mm2s_rdata;
    logic [1:0]   m_axi_mm2s_rresp;
    logic         m_axi_mm2s_rlast;
    logic         m_axi_mm2s_rvalid;
    logic         m_axi_mm2s_rready;

    // ------------------------------------------------------- AXI4-Streams
    logic [511:0] s_axis_s2mm_tdata  = '0;
    logic [63:0]  s_axis_s2mm_tkeep  = '0;
    logic         s_axis_s2mm_tvalid = 1'b0;
    logic         s_axis_s2mm_tready;
    logic         s_axis_s2mm_tlast  = 1'b0;

    logic [511:0] m_axis_mm2s_tdata;
    logic [63:0]  m_axis_mm2s_tkeep;
    logic         m_axis_mm2s_tvalid;
    logic         m_axis_mm2s_tready = 1'b1;
    logic         m_axis_mm2s_tlast;

    logic         mm2s_introut;
    logic         s2mm_introut;
    logic [31:0]  axi_dma_tstvec;
    logic         mm2s_prmry_reset_out_n;
    logic         s2mm_prmry_reset_out_n;

    // ------------------------------------------------------------------- DUT
    axi_dma_0 u_dma (
        .s_axi_lite_aclk        (clk),
        .m_axi_mm2s_aclk        (clk),
        .m_axi_s2mm_aclk        (clk),
        .axi_resetn             (rstn),
        .s_axi_lite_awvalid     (s_axi_lite_awvalid),
        .s_axi_lite_awready     (s_axi_lite_awready),
        .s_axi_lite_awaddr      (s_axi_lite_awaddr),
        .s_axi_lite_wvalid      (s_axi_lite_wvalid),
        .s_axi_lite_wready      (s_axi_lite_wready),
        .s_axi_lite_wdata       (s_axi_lite_wdata),
        .s_axi_lite_bresp       (s_axi_lite_bresp),
        .s_axi_lite_bvalid      (s_axi_lite_bvalid),
        .s_axi_lite_bready      (s_axi_lite_bready),
        .s_axi_lite_arvalid     (s_axi_lite_arvalid),
        .s_axi_lite_arready     (s_axi_lite_arready),
        .s_axi_lite_araddr      (s_axi_lite_araddr),
        .s_axi_lite_rvalid      (s_axi_lite_rvalid),
        .s_axi_lite_rready      (s_axi_lite_rready),
        .s_axi_lite_rdata       (s_axi_lite_rdata),
        .s_axi_lite_rresp       (s_axi_lite_rresp),
        .m_axi_mm2s_araddr      (m_axi_mm2s_araddr),
        .m_axi_mm2s_arlen       (m_axi_mm2s_arlen),
        .m_axi_mm2s_arsize      (m_axi_mm2s_arsize),
        .m_axi_mm2s_arburst     (m_axi_mm2s_arburst),
        .m_axi_mm2s_arprot      (m_axi_mm2s_arprot),
        .m_axi_mm2s_arcache     (m_axi_mm2s_arcache),
        .m_axi_mm2s_arvalid     (m_axi_mm2s_arvalid),
        .m_axi_mm2s_arready     (m_axi_mm2s_arready),
        .m_axi_mm2s_rdata       (m_axi_mm2s_rdata),
        .m_axi_mm2s_rresp       (m_axi_mm2s_rresp),
        .m_axi_mm2s_rlast       (m_axi_mm2s_rlast),
        .m_axi_mm2s_rvalid      (m_axi_mm2s_rvalid),
        .m_axi_mm2s_rready      (m_axi_mm2s_rready),
        .mm2s_prmry_reset_out_n (mm2s_prmry_reset_out_n),
        .m_axis_mm2s_tdata      (m_axis_mm2s_tdata),
        .m_axis_mm2s_tkeep      (m_axis_mm2s_tkeep),
        .m_axis_mm2s_tvalid     (m_axis_mm2s_tvalid),
        .m_axis_mm2s_tready     (m_axis_mm2s_tready),
        .m_axis_mm2s_tlast      (m_axis_mm2s_tlast),
        .m_axi_s2mm_awaddr      (m_axi_s2mm_awaddr),
        .m_axi_s2mm_awlen       (m_axi_s2mm_awlen),
        .m_axi_s2mm_awsize      (m_axi_s2mm_awsize),
        .m_axi_s2mm_awburst     (m_axi_s2mm_awburst),
        .m_axi_s2mm_awprot      (m_axi_s2mm_awprot),
        .m_axi_s2mm_awcache     (m_axi_s2mm_awcache),
        .m_axi_s2mm_awvalid     (m_axi_s2mm_awvalid),
        .m_axi_s2mm_awready     (m_axi_s2mm_awready),
        .m_axi_s2mm_wdata       (m_axi_s2mm_wdata),
        .m_axi_s2mm_wstrb       (m_axi_s2mm_wstrb),
        .m_axi_s2mm_wlast       (m_axi_s2mm_wlast),
        .m_axi_s2mm_wvalid      (m_axi_s2mm_wvalid),
        .m_axi_s2mm_wready      (m_axi_s2mm_wready),
        .m_axi_s2mm_bresp       (m_axi_s2mm_bresp),
        .m_axi_s2mm_bvalid      (m_axi_s2mm_bvalid),
        .m_axi_s2mm_bready      (m_axi_s2mm_bready),
        .s2mm_prmry_reset_out_n (s2mm_prmry_reset_out_n),
        .s_axis_s2mm_tdata      (s_axis_s2mm_tdata),
        .s_axis_s2mm_tkeep      (s_axis_s2mm_tkeep),
        .s_axis_s2mm_tvalid     (s_axis_s2mm_tvalid),
        .s_axis_s2mm_tready     (s_axis_s2mm_tready),
        .s_axis_s2mm_tlast      (s_axis_s2mm_tlast),
        .mm2s_introut           (mm2s_introut),
        .s2mm_introut           (s2mm_introut),
        .axi_dma_tstvec         (axi_dma_tstvec)
    );

    // ------------------------------------------------------------------- RAM
    logic [31:0] dbg_addr = '0;
    logic [7:0]  dbg_data;

    axi_ram_model u_ram (
        .aclk    (clk),
        .aresetn (rstn),
        .awaddr  (m_axi_s2mm_awaddr),
        .awlen   (m_axi_s2mm_awlen),
        .awsize  (m_axi_s2mm_awsize),
        .awburst (m_axi_s2mm_awburst),
        .awvalid (m_axi_s2mm_awvalid),
        .awready (m_axi_s2mm_awready),
        .wdata   (m_axi_s2mm_wdata),
        .wstrb   (m_axi_s2mm_wstrb),
        .wlast   (m_axi_s2mm_wlast),
        .wvalid  (m_axi_s2mm_wvalid),
        .wready  (m_axi_s2mm_wready),
        .bresp   (m_axi_s2mm_bresp),
        .bvalid  (m_axi_s2mm_bvalid),
        .bready  (m_axi_s2mm_bready),
        .araddr  (m_axi_mm2s_araddr),
        .arlen   (m_axi_mm2s_arlen),
        .arsize  (m_axi_mm2s_arsize),
        .arburst (m_axi_mm2s_arburst),
        .arvalid (m_axi_mm2s_arvalid),
        .arready (m_axi_mm2s_arready),
        .rdata   (m_axi_mm2s_rdata),
        .rresp   (m_axi_mm2s_rresp),
        .rlast   (m_axi_mm2s_rlast),
        .rvalid  (m_axi_mm2s_rvalid),
        .rready  (m_axi_mm2s_rready),
        .dbg_addr(dbg_addr),
        .dbg_data(dbg_data)
    );

    // ----------------------------------------------------------- bookkeeping
    localparam [9:0]  MM2S_DMACR  = 10'h00;
    localparam [9:0]  MM2S_DMASR  = 10'h04;
    localparam [9:0]  MM2S_SA     = 10'h18;
    localparam [9:0]  MM2S_LENGTH = 10'h28;
    localparam [9:0]  S2MM_DMACR  = 10'h30;
    localparam [9:0]  S2MM_DMASR  = 10'h34;
    localparam [9:0]  S2MM_DA     = 10'h48;
    localparam [9:0]  S2MM_LENGTH = 10'h58;

    localparam [31:0] SLOT0 = 32'h0010_0000;
    localparam [31:0] SLOT1 = 32'h0010_1000;
    localparam [31:0] SLOT2 = 32'h0010_2000;

    localparam [31:0] DMACR_RS_IOC = 32'h0000_1001;
    localparam [63:0] KEEP_ALL     = 64'hFFFF_FFFF_FFFF_FFFF;
    localparam [63:0] KEEP_22      = 64'h0000_0000_003F_FFFF;  // low 22 lanes
    localparam [31:0] IOC_BIT      = 32'h0000_1000;

    int fails = 0;

    logic [511:0] beat0_d5;
    logic [511:0] beat1_pat;
    logic [511:0] beat2_sig;
    logic [511:0] beat2_sig_last;
    logic [31:0]  sr1, sr2, sr3, sr4;
    logic [31:0]  len1, len2, len3, len4;

    initial begin
        beat0_d5 = {8{64'hD555_5555_5555_5555}};
        beat1_pat = '0;
        for (int k = 0; k < 22; k++) begin
            beat1_pat[k*8 +: 8] = 8'h11 * k;
        end
        beat2_sig = '0;
        for (int k = 0; k < 64; k++) begin
            beat2_sig[k*8 +: 8] = k[7:0];
        end
        beat2_sig_last = '0;
        for (int k = 0; k < 22; k++) begin
            beat2_sig_last[k*8 +: 8] = 8'h40 + k[7:0];
        end
    end

    // ------------------------------------------------------- MM2S beat capture
    logic [511:0] mm2s_cap_data [0:7];
    logic [63:0]  mm2s_cap_keep [0:7];
    logic         mm2s_cap_last [0:7];
    int           mm2s_beat_count = 0;

    always_ff @(posedge clk) begin
        if (rstn && m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
            if (mm2s_beat_count < 8) begin
                mm2s_cap_data[mm2s_beat_count] <= m_axis_mm2s_tdata;
                mm2s_cap_keep[mm2s_beat_count] <= m_axis_mm2s_tkeep;
                mm2s_cap_last[mm2s_beat_count] <= m_axis_mm2s_tlast;
            end
            $display("MM2S_BEAT t=%0t idx=%0d tdata[63:0]=0x%016h tdata[191:128]=0x%016h tkeep=0x%016h tlast=%0d",
                     $time, mm2s_beat_count, m_axis_mm2s_tdata[63:0],
                     m_axis_mm2s_tdata[191:128], m_axis_mm2s_tkeep, m_axis_mm2s_tlast);
            mm2s_beat_count <= mm2s_beat_count + 1;
        end
    end

    // ------------------------------------------------------------ IRQ monitor
    logic s2mm_intr_q = 1'b0;
    logic mm2s_intr_q = 1'b0;

    always_ff @(posedge clk) begin
        s2mm_intr_q <= s2mm_introut;
        mm2s_intr_q <= mm2s_introut;
        if (rstn && s2mm_introut && !s2mm_intr_q) $display("IRQ_RISE s2mm t=%0t", $time);
        if (rstn && mm2s_introut && !mm2s_intr_q) $display("IRQ_RISE mm2s t=%0t", $time);
    end

    // ------------------------------------------------------------------ tasks
    task automatic axil_write(input logic [9:0] addr, input logic [31:0] data);
        bit aw_done;
        bit w_done;
        int guard;
        aw_done = 1'b0;
        w_done  = 1'b0;
        guard   = 0;
        $display("AXIL_WR_ENTER t=%0t addr=0x%03h data=0x%08h", $time, addr, data);
        @(posedge clk);
        s_axi_lite_awaddr  <= addr;
        s_axi_lite_awvalid <= 1'b1;
        s_axi_lite_wdata   <= data;
        s_axi_lite_wvalid  <= 1'b1;
        s_axi_lite_bready  <= 1'b1;
        // AW and W handshakes may complete in the same cycle; track both.
        while (!(aw_done && w_done) && (guard < 200)) begin
            @(posedge clk);
            if (s_axi_lite_awvalid && s_axi_lite_awready) begin
                s_axi_lite_awvalid <= 1'b0;
                aw_done = 1'b1;
            end
            if (s_axi_lite_wvalid && s_axi_lite_wready) begin
                s_axi_lite_wvalid <= 1'b0;
                w_done = 1'b1;
            end
            guard = guard + 1;
            if ((guard % 50) == 0) begin
                $display("AXIL_WR_POLL t=%0t guard=%0d awv=%0d awr=%0d wv=%0d wr=%0d bv=%0d",
                         $time, guard, s_axi_lite_awvalid, s_axi_lite_awready,
                         s_axi_lite_wvalid, s_axi_lite_wready, s_axi_lite_bvalid);
            end
        end
        if (!(aw_done && w_done)) begin
            fails++;
            $display("AXIL_WR_TIMEOUT_AW_W addr=0x%03h aw_done=%0d w_done=%0d",
                     addr, aw_done, w_done);
        end
        guard = 0;
        while (!s_axi_lite_bvalid && (guard < 200)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (!s_axi_lite_bvalid) begin
            fails++;
            $display("AXIL_WR_TIMEOUT_B addr=0x%03h", addr);
        end
        s_axi_lite_bready <= 1'b0;
        $display("AXIL_WR t=%0t addr=0x%03h data=0x%08h", $time, addr, data);
    endtask

    task automatic axil_read(input logic [9:0] addr, output logic [31:0] data);
        int guard;
        guard = 0;
        @(posedge clk);
        s_axi_lite_araddr  <= addr;
        s_axi_lite_arvalid <= 1'b1;
        s_axi_lite_rready  <= 1'b1;
        while (!s_axi_lite_arready && (guard < 200)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        s_axi_lite_arvalid <= 1'b0;
        guard = 0;
        while (!s_axi_lite_rvalid && (guard < 200)) begin
            @(posedge clk);
            guard = guard + 1;
        end
        if (s_axi_lite_rvalid) begin
            data = s_axi_lite_rdata;
            s_axi_lite_rready <= 1'b0;
        end else begin
            data = 32'hDEAD_BEEF;
            fails++;
            $display("AXIL_RD_TIMEOUT addr=0x%03h", addr);
        end
        $display("AXIL_RD t=%0t addr=0x%03h data=0x%08h", $time, addr, data);
    endtask

    task automatic s2mm_beat(input logic [511:0] data, input logic [63:0] keep, input logic last);
        s_axis_s2mm_tdata  <= data;
        s_axis_s2mm_tkeep  <= keep;
        s_axis_s2mm_tlast  <= last;
        s_axis_s2mm_tvalid <= 1'b1;
        do @(posedge clk); while (!s_axis_s2mm_tready);
        s_axis_s2mm_tvalid <= 1'b0;
        s_axis_s2mm_tlast  <= 1'b0;
        $display("S2MM_STREAM t=%0t tdata[63:0]=0x%016h tkeep=0x%016h tlast=%0d",
                 $time, data[63:0], keep, last);
    endtask

    task automatic decode_dmasr(input logic [31:0] sr, input string tag);
        $display("DMASR %s = 0x%08h | Halted=%0d Idle=%0d SGIncld=%0d DMAIntErr=%0d SLVErr=%0d DecErr=%0d SGIntErr=%0d SGSLVErr=%0d SGDecErr=%0d IOC_Irq=%0d Dly_Irq=%0d Err_Irq=%0d IRQThreshold=%0d",
                 tag, sr, sr[0], sr[1], sr[2], sr[4], sr[5], sr[6],
                 sr[8], sr[9], sr[10], sr[12], sr[13], sr[14], sr[23:16]);
    endtask

    task automatic clear_ioc(input logic [9:0] addr, input string tag);
        axil_write(addr, IOC_BIT);
        $display("CLEAR_IOC %s addr=0x%03h", tag, addr);
    endtask

    task automatic wait_s2mm_ioc(input int max_polls, input string tag);
        logic [31:0] sr;
        int n;
        sr = '0;
        for (n = 0; n < max_polls; n = n + 1) begin
            axil_read(S2MM_DMASR, sr);
            if (sr[12]) begin
                $display("WAIT %s done poll=%0d sr=0x%08h", tag, n, sr);
                return;
            end
            repeat (20) @(posedge clk);
        end
        fails++;
        $display("WAIT %s TIMEOUT sr=0x%08h", tag, sr);
    endtask

    task automatic wait_mm2s_ioc(input int max_polls, input string tag);
        logic [31:0] sr;
        int n;
        sr = '0;
        for (n = 0; n < max_polls; n = n + 1) begin
            axil_read(MM2S_DMASR, sr);
            if (sr[12]) begin
                $display("WAIT %s done poll=%0d sr=0x%08h", tag, n, sr);
                return;
            end
            repeat (20) @(posedge clk);
        end
        fails++;
        $display("WAIT %s TIMEOUT sr=0x%08h", tag, n - 1, sr);
    endtask

    task automatic check_byte(input logic [31:0] addr, input logic [7:0] exp, input string tag);
        dbg_addr = addr;
        #1;
        if (dbg_data !== exp) begin
            fails++;
            $display("CHECK_FAIL %s addr=0x%08h exp=0x%02h got=0x%02h", tag, addr, exp, dbg_data);
        end
    endtask

    task automatic dump_mem(input logic [31:0] base, input int n, input string tag);
        int i;
        int j;
        for (i = 0; i < n; i = i + 16) begin
            $write("MEMDUMP %s base=0x%08h off=0x%03h :", tag, base, i);
            for (j = 0; j < 16; j = j + 1) begin
                if ((i + j) < n) begin
                    dbg_addr = base + i + j;
                    #1;
                    $write(" %02h", dbg_data);
                end
            end
            $write("\n");
        end
    endtask

    // --------------------------------------------------------------- stimulus
    initial begin
        logic [31:0] rd;
        logic [7:0]  expb;

        wait (rstn === 1'b1);
        repeat (10) @(posedge clk);

        $display("TB_START t=%0t", $time);
        $display("TB_CFG ip=xilinx.com:ip:axi_dma:7.1 part=xcku060-ffva1156-2-i");
        $display("TB_CFG C_INCLUDE_SG=0 C_M_AXI_S2MM_DATA_WIDTH=512 C_S_AXIS_S2MM_TDATA_WIDTH=512");
        $display("TB_CFG C_S2MM_BURST_SIZE=16 C_INCLUDE_S2MM_DRE=0 C_INCLUDE_S2MM_SF=1");
        $display("TB_CFG SLOT0=0x%08h SLOT1=0x%08h SLOT2=0x%08h", SLOT0, SLOT1, SLOT2);

        // ---- initial register snapshot (before any config) ----
        axil_read(S2MM_DMASR, rd);  decode_dmasr(rd, "S2MM_DMASR_INITIAL");
        axil_read(MM2S_DMASR, rd);  decode_dmasr(rd, "MM2S_DMASR_INITIAL");
        axil_read(S2MM_DMACR, rd);  $display("S2MM_DMACR_INITIAL = 0x%08h", rd);
        axil_read(MM2S_DMACR, rd);  $display("MM2S_DMACR_INITIAL = 0x%08h", rd);

        // =====================================================================
        // TEST 1: S2MM 86 bytes at slot 0, exact board stimulus
        // =====================================================================
        $display("TEST1_BEGIN S2MM_86B_SLOT0");
        clear_ioc(S2MM_DMASR, "T1");
        axil_write(S2MM_DMACR, DMACR_RS_IOC);
        axil_read(S2MM_DMACR, rd);
        $display("TEST1 S2MM_DMACR=0x%08h RS=%0d IOCEN=%0d", rd, rd[0], rd[12]);
        axil_write(S2MM_DA, SLOT0);
        axil_write(S2MM_LENGTH, 32'd86);

        s2mm_beat(beat0_d5, KEEP_ALL, 1'b0);
        s2mm_beat(beat1_pat, KEEP_22, 1'b1);

        wait_s2mm_ioc(400, "S2MM_T1");
        axil_read(S2MM_DMASR, sr1);  decode_dmasr(sr1, "S2MM_T1");
        axil_read(S2MM_LENGTH, len1);
        $display("TEST1 S2MM_LENGTH_AFTER=0x%08h (%0d)", len1, len1);

        dump_mem(SLOT0, 86, "T1");
        for (int k = 0; k < 86; k++) begin
            if (k < 64) expb = beat0_d5[k*8 +: 8];
            else        expb = beat1_pat[(k-64)*8 +: 8];
            check_byte(SLOT0 + k, expb, "T1");
        end
        $display("TEST1 checks_done fails=%0d", fails);

        if (sr1[12] !== 1'b1) begin fails++; $display("CHECK_FAIL T1 IOC_Irq=0"); end
        if (sr1[1]  !== 1'b1) begin fails++; $display("CHECK_FAIL T1 Idle=0");    end
        if (sr1[0]  !== 1'b0) begin fails++; $display("CHECK_FAIL T1 Halted=1");  end
        if ((sr1 & 32'h0000_0770) !== 32'h0) begin
            fails++; $display("CHECK_FAIL T1 error bits set sr=0x%08h", sr1);
        end
        if (len1 !== 32'd86) begin fails++; $display("CHECK_FAIL T1 S2MM_LENGTH=%0d exp=86", len1); end

        // =====================================================================
        // TEST 2: lane-signature packet, byte k = k, proves no lane swap
        // =====================================================================
        $display("TEST2_BEGIN LANE_SIGNATURE_SLOT1");
        clear_ioc(S2MM_DMASR, "T2");
        axil_write(S2MM_DA, SLOT1);
        axil_write(S2MM_LENGTH, 32'd86);
        s2mm_beat(beat2_sig, KEEP_ALL, 1'b0);
        s2mm_beat(beat2_sig_last, KEEP_22, 1'b1);

        wait_s2mm_ioc(400, "S2MM_T2");
        axil_read(S2MM_DMASR, sr2);  decode_dmasr(sr2, "S2MM_T2");
        axil_read(S2MM_LENGTH, len2);
        $display("TEST2 S2MM_LENGTH_AFTER=0x%08h (%0d)", len2, len2);
        dump_mem(SLOT1, 86, "T2");
        for (int k = 0; k < 86; k++) begin
            check_byte(SLOT1 + k, k[7:0], "T2");
        end
        $display("TEST2 checks_done fails=%0d", fails);

        // =====================================================================
        // TEST 4: short packet with S2MM_LENGTH=256 -> actual length semantics
        // =====================================================================
        $display("TEST4_BEGIN SHORT_PACKET_SLOT2 len_reg=256 pkt=86");
        clear_ioc(S2MM_DMASR, "T4");
        axil_write(S2MM_DA, SLOT2);
        axil_write(S2MM_LENGTH, 32'd256);
        s2mm_beat(beat0_d5, KEEP_ALL, 1'b0);
        s2mm_beat(beat1_pat, KEEP_22, 1'b1);

        wait_s2mm_ioc(400, "S2MM_T4");
        axil_read(S2MM_DMASR, sr4);  decode_dmasr(sr4, "S2MM_T4");
        axil_read(S2MM_LENGTH, len4);
        $display("TEST4 S2MM_LENGTH_AFTER=0x%08h (%0d) expect_actual=86", len4, len4);
        dump_mem(SLOT2, 96, "T4");
        for (int k = 0; k < 86; k++) begin
            if (k < 64) expb = beat0_d5[k*8 +: 8];
            else        expb = beat1_pat[(k-64)*8 +: 8];
            check_byte(SLOT2 + k, expb, "T4");
        end
        for (int k = 86; k < 256; k++) begin
            check_byte(SLOT2 + k, 8'hEE, "T4_UNTOUCHED");
        end
        if (len4 !== 32'd86) begin
            fails++;
            $display("CHECK_FAIL T4 S2MM_LENGTH_AFTER=%0d exp=86 (PG021 actual bytes)", len4);
        end
        $display("TEST4 checks_done fails=%0d", fails);

        // =====================================================================
        // TEST 3 (bonus): MM2S read back the same 86 bytes from slot 0
        // =====================================================================
        $display("TEST3_BEGIN MM2S_86B_SLOT0");
        clear_ioc(MM2S_DMASR, "T3");
        axil_write(MM2S_DMACR, DMACR_RS_IOC);
        axil_write(MM2S_SA, SLOT0);
        axil_write(MM2S_LENGTH, 32'd86);

        wait_mm2s_ioc(400, "MM2S_T3");
        axil_read(MM2S_DMASR, sr3);  decode_dmasr(sr3, "MM2S_T3");
        axil_read(MM2S_LENGTH, len3);
        $display("TEST3 MM2S_LENGTH_AFTER=0x%08h (%0d)", len3, len3);
        repeat (20) @(posedge clk);

        $display("TEST3 mm2s_beat_count=%0d", mm2s_beat_count);
        if (mm2s_beat_count !== 2) begin
            fails++; $display("CHECK_FAIL T3 beat_count=%0d exp=2", mm2s_beat_count);
        end
        if (mm2s_beat_count >= 1) begin
            $display("TEST3 beat0 tdata[63:0]=0x%016h tdata[191:128]=0x%016h tkeep=0x%016h tlast=%0d",
                     mm2s_cap_data[0][63:0], mm2s_cap_data[0][191:128],
                     mm2s_cap_keep[0], mm2s_cap_last[0]);
            if (mm2s_cap_data[0] !== beat0_d5) begin fails++; $display("CHECK_FAIL T3 beat0 data"); end
            if (mm2s_cap_keep[0] !== KEEP_ALL) begin fails++; $display("CHECK_FAIL T3 beat0 keep"); end
            if (mm2s_cap_last[0] !== 1'b0)     begin fails++; $display("CHECK_FAIL T3 beat0 last"); end
        end
        if (mm2s_beat_count >= 2) begin
            $display("TEST3 beat1 tdata[63:0]=0x%016h tdata[191:128]=0x%016h tkeep=0x%016h tlast=%0d",
                     mm2s_cap_data[1][63:0], mm2s_cap_data[1][191:128],
                     mm2s_cap_keep[1], mm2s_cap_last[1]);
            if (mm2s_cap_data[1][175:0] !== beat1_pat[175:0]) begin
                fails++; $display("CHECK_FAIL T3 beat1 low22 data");
            end
            if (mm2s_cap_keep[1] !== KEEP_22) begin fails++; $display("CHECK_FAIL T3 beat1 keep"); end
            if (mm2s_cap_last[1] !== 1'b1)    begin fails++; $display("CHECK_FAIL T3 beat1 last"); end
        end
        if (sr3[12] !== 1'b1) begin fails++; $display("CHECK_FAIL T3 IOC_Irq=0"); end
        if (sr3[1]  !== 1'b1) begin fails++; $display("CHECK_FAIL T3 Idle=0");    end

        // ------------------------------------------------------------- summary
        $display("============================================================");
        $display("TEST_SUMMARY fails=%0d", fails);
        if (fails == 0) $display("TEST_PASS");
        else            $display("TEST_FAIL");
        $display("============================================================");
        $finish;
    end

    // --------------------------------------------------------------- watchdog
    initial begin
        #1_000_000;
        $display("WATCHDOG_TIMEOUT t=%0t", $time);
        $display("TEST_FAIL");
        $finish;
    end

endmodule
