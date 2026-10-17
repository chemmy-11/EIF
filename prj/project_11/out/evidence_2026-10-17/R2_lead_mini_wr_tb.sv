`timescale 1ns/1ps
// mini_wr_tb.sv -- Lead 快速定位 R2 写引擎卡点 (只测单帧 64B 通路)
module mini_wr_tb;
  reg user_clk=0, ui_clk=0, lite_clk=0;
  reg user_rst_n=0, ui_rst_n=0, lite_rst_n=0;
  always #3.3  user_clk = ~user_clk;   // 151.5MHz
  always #1.666 ui_clk  = ~ui_clk;     // 300MHz
  always #5.0  lite_clk = ~lite_clk;   // 100MHz

  reg [7:0] wr_data=0; reg wr_en=0; wire wr_hold;
  wire [7:0] rd_data; wire rd_en; wire [7:0] rd_slot_o; wire [15:0] rd_len_o;
  wire rd_frame_done; reg rd_req=0; wire rd_busy;
  reg cfg_mode=0; reg [7:0] cfg_rd_slot=0;
  wire [15:0] ro_u_wr_frame, ro_u_rd_frame, ro_u_buf_drop; wire [31:0] ro_u_hold_cycles;
  wire [8:0] ro_outstanding_sync; wire [15:0] ro_lat_w, ro_lat_r;
  reg dma_engine=0; wire [31:0] ro_dbg_emit;
  reg [511:0] dma_s_tdata=0; reg [63:0] dma_s_tkeep=0; reg dma_s_tlast=0, dma_s_tvalid=0;
  wire dma_s_tready, ro_dma_req;
  wire [31:0] ro_dma_req_w;
  reg dma_wr_go=0, dma_wr_ack=0, s2mm_introut=0;
  wire [511:0] dma_wr_tdata; wire [63:0] dma_wr_tkeep;
  wire dma_wr_tlast, dma_wr_tvalid; reg dma_wr_tready=1'b0;
  wire [31:0] ro_dma_wr_req, ro_dma_wr_dbg;
  wire [15:0] ro_stat_wr_timeout; wire [2:0] ro_dbg_wr_state;
  reg calib_ok=0;
  wire [15:0] ro_wm, ro_wr_frame, ro_wr_stall, ro_rd_frame, ro_ill_rd, ro_noframe, ro_bresp_err, ro_len_err;
  wire [8:0] ro_outstanding; wire [7:0] ro_dbg_wr_slot, ro_dbg_rd_slot;
  wire [31:0] dbg_wr_cycles, dbg_rd_cycles, dbg_wr_beats, dbg_rd_beats;
  wire [31:0] m_axi_awaddr; wire [7:0] m_axi_awlen; wire [2:0] m_axi_awsize; wire [1:0] m_axi_awburst;
  wire m_axi_awvalid; wire [511:0] m_axi_wdata; wire [63:0] m_axi_wstrb; wire m_axi_wlast, m_axi_wvalid, m_axi_bready;
  wire [31:0] m_axi_araddr; wire [7:0] m_axi_arlen; wire [2:0] m_axi_arsize; wire [1:0] m_axi_arburst;
  wire m_axi_arvalid, m_axi_rready; wire [3:0] m_axi_awid, m_axi_arid; wire [0:0] m_axi_awlock, m_axi_arlock;
  wire [3:0] m_axi_awcache, m_axi_arcache; wire [2:0] m_axi_awprot, m_axi_arprot; wire [3:0] m_axi_awqos, m_axi_arqos;

  frame_mem_if #(.SLOT_BASE(32'h0010_0000), .MAX_LEN(16'd1538), .HAS_DMA(1)) dut (
    .user_clk(user_clk), .user_rst_n(user_rst_n),
    .wr_data(wr_data), .wr_en(wr_en), .wr_hold(wr_hold),
    .rd_data(rd_data), .rd_en(rd_en), .rd_slot_o(rd_slot_o), .rd_len_o(rd_len_o),
    .rd_frame_done(rd_frame_done), .rd_req(rd_req), .rd_busy(rd_busy),
    .cfg_mode(cfg_mode), .cfg_rd_slot(cfg_rd_slot),
    .ro_u_wr_frame(ro_u_wr_frame), .ro_u_rd_frame(ro_u_rd_frame), .ro_u_buf_drop(ro_u_buf_drop),
    .ro_u_hold_cycles(ro_u_hold_cycles), .ro_outstanding_sync(ro_outstanding_sync),
    .ro_lat_w(ro_lat_w), .ro_lat_r(ro_lat_r),
    .dma_engine(dma_engine), .ro_dbg_emit(ro_dbg_emit),
    .dma_s_tdata(dma_s_tdata), .dma_s_tkeep(dma_s_tkeep), .dma_s_tlast(dma_s_tlast),
    .dma_s_tvalid(dma_s_tvalid), .dma_s_tready(dma_s_tready), .ro_dma_req(ro_dma_req_w),
    .dma_wr_go(dma_wr_go), .dma_wr_ack(dma_wr_ack), .s2mm_introut(s2mm_introut),
    .dma_wr_tdata(dma_wr_tdata), .dma_wr_tkeep(dma_wr_tkeep), .dma_wr_tlast(dma_wr_tlast),
    .dma_wr_tvalid(dma_wr_tvalid), .dma_wr_tready(dma_wr_tready),
    .ro_dma_wr_req(ro_dma_wr_req), .ro_dma_wr_dbg(ro_dma_wr_dbg),
    .ro_stat_wr_timeout(ro_stat_wr_timeout), .ro_dbg_wr_state(ro_dbg_wr_state),
    .ui_clk(ui_clk), .ui_rst_n(ui_rst_n), .calib_ok(calib_ok),
    .ro_wm(ro_wm), .ro_wr_frame(ro_wr_frame), .ro_wr_stall(ro_wr_stall),
    .ro_rd_frame(ro_rd_frame), .ro_ill_rd(ro_ill_rd), .ro_noframe(ro_noframe),
    .ro_bresp_err(ro_bresp_err), .ro_len_err(ro_len_err), .ro_outstanding(ro_outstanding),
    .ro_dbg_wr_slot(ro_dbg_wr_slot), .ro_dbg_rd_slot(ro_dbg_rd_slot),
    .dbg_wr_cycles(dbg_wr_cycles), .dbg_rd_cycles(dbg_rd_cycles),
    .dbg_wr_beats(dbg_wr_beats), .dbg_rd_beats(dbg_rd_beats),
    .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(1'b0),
    .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(1'b0),
    .m_axi_bresp(2'b00), .m_axi_bvalid(1'b0), .m_axi_bready(m_axi_bready),
    .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(1'b0),
    .m_axi_rdata(512'd0), .m_axi_rresp(2'b00), .m_axi_rlast(1'b0), .m_axi_rvalid(1'b0),
    .m_axi_rready(m_axi_rready),
    .m_axi_awid(m_axi_awid), .m_axi_awlock(m_axi_awlock), .m_axi_awcache(m_axi_awcache),
    .m_axi_awprot(m_axi_awprot), .m_axi_awqos(m_axi_awqos), .m_axi_bid(4'd0),
    .m_axi_arid(m_axi_arid), .m_axi_arlock(m_axi_arlock), .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot(m_axi_arprot), .m_axi_arqos(m_axi_arqos), .m_axi_rid(4'd0)
  );
  wire [31:0] ro_dma_req_unused = ro_dma_req_w;
  wire ro_dma_req_bit0 = ro_dma_req_w[0];

  integer n;
  reg [7:0] fbuf [0:255];
  initial begin
    for (n=0;n<64;n=n+1) fbuf[n] = n+8'h40;
    repeat (20) @(posedge ui_clk);
    user_rst_n=1; ui_rst_n=1; lite_rst_n=1;
    repeat (20) @(posedge user_clk);
    calib_ok=1;
    repeat (50) @(posedge user_clk);
    // drive one 64B frame
    @(negedge user_clk);
    for (n=0;n<64;n=n+1) begin
      wr_en=1; wr_data=fbuf[n]; @(negedge user_clk);
    end
    wr_en=0; wr_data=0; @(negedge user_clk);
    $display("[mini] frame driven, t=%0t", $time);
    // 打印 3us 内状态变化
    for (n=0;n<400;n=n+1) begin
      @(posedge ui_clk);
      if (n % 5 == 0)
        $display("[mini] t=%0t st=%0d pend=%b tog=%b slot=%0d len=%0d wf_lvl=%0d go_ok=%b go_seen=%b go_sig=%b intr=%b tvalid=%b tready=%b commit_wm=%0d",
          $time, ro_dbg_wr_state, ro_dma_wr_req[31], ro_dma_wr_req[24],
          ro_dma_wr_req[23:16], ro_dma_wr_req[15:0], dut.ub_rl,
          dut.u_bridge.g_wr_dma.wd_go_ok, dut.u_bridge.g_wr_dma.wd_go_seen, dut.dma_wr_go_ui,
          dut.s2mm_introut_ui, dma_wr_tvalid, dut.u_bridge.m_axis_s2mm_tready,
          ro_wm);
    end
    $display("[mini] DONE wm=%0d dbg=%08h req=%08h", ro_wm, ro_dma_wr_dbg, ro_dma_wr_req);
    $finish;
  end

  // 软核模型 (user 域): pending 且 toggle 变化 -> 翻 GO (不模拟 S2MM 完成)
  reg last_tog=0;
  always @(posedge user_clk) begin
    if (!user_rst_n) last_tog <= 0;
    else if (ro_dma_wr_req[31] && (ro_dma_wr_req[24] !== last_tog)) begin
      last_tog <= ro_dma_wr_req[24];
      @(posedge user_clk);
      dma_wr_go <= ~dma_wr_go;
      $display("[mini] SW arm: slot=%0d len=%0d -> GO=%b t=%0t", ro_dma_wr_req[23:16], ro_dma_wr_req[15:0], ~dma_wr_go, $time);
    end
  end

  // S2MM 流模型 (ui 域): GO 后 tready=1, 收拍; TLAST 后 8 拍拉 intr (lite 域 2FF)
  reg model_armed=0;
  always @(posedge ui_clk) begin
    if (!ui_rst_n) begin model_armed<=0; dma_wr_tready<=0; end
    else begin
      if (dut.dma_wr_go_ui != 1'b0) model_armed <= 1'b1;
      dma_wr_tready <= model_armed;
      if (dma_wr_tvalid && dma_wr_tready) begin
        $display("[mini] S2MM beat tkeep=%016h tlast=%b", dma_wr_tkeep, dma_wr_tlast);
        if (dma_wr_tlast) begin
          repeat (8) @(posedge ui_clk);
          s2mm_introut <= 1'b1;
          $display("[mini] S2MM intr set t=%0t", $time);
        end
      end
    end
  end
endmodule
