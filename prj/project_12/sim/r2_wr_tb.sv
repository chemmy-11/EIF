//=============================================================================
// r2_wr_tb.sv -- R2（B3-2）桥① 写侧换层 S2MM 独立 TB（白盒，xsim）
//-----------------------------------------------------------------------------
// DUT : frame_mem_if #(.HAS_DMA(1))（内含 axi4_master_bridge + dma_rd_shim_v2）
// 被测 : B3-2 DMA 写引擎 WD_* / 规则号 1（写槽 = 帧计数 mod 256）等价性
// 模型 :
//   * S2MM 行为模型(ui_clk)：按 TKEEP 掩码把 512b AXIS 拍写 RAM；逐拍校验
//     TKEEP/TLAST；完成后经 lite 域 2FF 拉 s2mm_introut 电平（直到模型清 IOC）。
//     只证 DUT 输出流正确，不模拟厂商 TKEEP->WSTRB 内部实现（见审计 A9）。
//   * 软核行为模型(user_clk)：轮询 ro_dma_wr_req{pending,toggle} -> 编程 SA/LEN
//     -> 清 IOC -> 翻 dma_wr_go；含 fault 恢复（清 IOC+复位模型+翻 dma_wr_ack）。
// 用例（tag 供 run_r2_wr_tb.bat 的负向轮 grep，坑 #43）:
//   T1 整拍64B / T2 尾拍70B / T3 背靠背3帧 / T4 满槽拒收(不覆盖+游标推进)
//   T5 超长拒收 + 空帧不可达说明 / T6 GO缺失超时(真实等 24'hFFFFFF) 丢帧不停泊
//   T7 连续帧 GO先于清IOC 的闸门顺序
//   T8 规则号1 golden model 随机 100 帧（含 256 回绕 + 满槽拒收）
//   T9 WAITDONE 看门狗 fail-stop(HALT)+软核 ACK 恢复（力加速，仅缩短时基）
// 负向对照（另用缺陷副本编译）:
//   * 游标被拒不推进 -> "[FAIL-T4-CURSOR]"
//   * 尾拍 TKEEP 用满 64 -> "[FAIL-KEEP-MASK]"
//=============================================================================
`timescale 1ns/1ps

module r2_wr_tb;

    localparam [31:0] SLOT_BASE = 32'h0010_0000;
    localparam integer MAXLEN   = 1538;
    localparam integer SLOT_SZ  = 4096;
    localparam integer RAMBYTES = 2*1024*1024;
    localparam integer EXPMEM   = 256*MAXLEN;

    //-------------------------------------------------------------------------
    // 0. 时钟 / 复位
    //-------------------------------------------------------------------------
    reg user_clk, ui_clk, lite_clk;
    initial begin user_clk = 1'b0; forever #3.3  user_clk = ~user_clk; end  // 151.5 MHz
    initial begin ui_clk   = 1'b0; forever #1.6665 ui_clk = ~ui_clk;  end   // 300 MHz
    initial begin lite_clk = 1'b0; forever #5.0  lite_clk = ~lite_clk; end  // 100 MHz
    reg user_rst_n, ui_rst_n, lite_rst_n, calib_ok;

    //-------------------------------------------------------------------------
    // 1. DUT（端口列表按 Lead 2026-10-17 冻结版）
    //-------------------------------------------------------------------------
    reg  [7:0]  wr_data;
    reg         wr_en;
    wire        wr_hold;
    wire [7:0]  rd_data;   wire rd_en;
    wire [7:0]  rd_slot_o; wire [15:0] rd_len_o;
    wire        rd_frame_done; wire rd_busy;
    reg         rd_req, cfg_mode;
    reg  [7:0]  cfg_rd_slot;
    wire [15:0] ro_u_wr_frame, ro_u_rd_frame, ro_u_buf_drop;
    wire [31:0] ro_u_hold_cycles; wire [8:0] ro_outstanding_sync;
    wire [15:0] ro_lat_w, ro_lat_r;
    reg         dma_engine;
    wire [31:0] ro_dbg_emit;
    reg  [511:0] dma_s_tdata; reg [63:0] dma_s_tkeep;
    reg         dma_s_tlast, dma_s_tvalid; wire dma_s_tready;
    wire [31:0] ro_dma_req;
    reg         dma_wr_go, dma_wr_ack, s2mm_introut;
    wire [511:0] dma_wr_tdata; wire [63:0] dma_wr_tkeep;
    wire        dma_wr_tlast, dma_wr_tvalid;
    reg         dma_wr_tready;
    wire [31:0] ro_dma_wr_req, ro_dma_wr_dbg;
    wire [15:0] ro_stat_wr_timeout; wire [2:0] ro_dbg_wr_state;
    wire [15:0] ro_wm, ro_wr_frame, ro_wr_stall, ro_rd_frame, ro_ill_rd;
    wire [15:0] ro_noframe, ro_bresp_err, ro_len_err;
    wire [8:0]  ro_outstanding;
    wire [7:0]  ro_dbg_wr_slot, ro_dbg_rd_slot;
    wire [31:0] dbg_wr_cycles, dbg_rd_cycles, dbg_wr_beats, dbg_rd_beats;
    wire [31:0] m_axi_awaddr; wire [7:0] m_axi_awlen;
    wire [2:0]  m_axi_awsize; wire [1:0] m_axi_awburst;
    wire        m_axi_awvalid;
    wire [511:0] m_axi_wdata; wire [63:0] m_axi_wstrb;
    wire        m_axi_wlast, m_axi_wvalid, m_axi_bready;
    wire [31:0] m_axi_araddr; wire [7:0] m_axi_arlen;
    wire [2:0]  m_axi_arsize; wire [1:0] m_axi_arburst;
    wire        m_axi_arvalid, m_axi_rready;
    wire [3:0]  m_axi_awid; wire [0:0] m_axi_awlock;
    wire [3:0]  m_axi_awcache; wire [2:0] m_axi_awprot; wire [3:0] m_axi_awqos;
    wire [3:0]  m_axi_arid; wire [0:0] m_axi_arlock;
    wire [3:0]  m_axi_arcache; wire [2:0] m_axi_arprot; wire [3:0] m_axi_arqos;

    frame_mem_if #(
        .SLOT_BASE (SLOT_BASE),
        .MAX_LEN   (16'd1538),
        .HAS_DMA   (1)
    ) dut (
        .user_clk        (user_clk),
        .user_rst_n      (user_rst_n),
        .wr_data         (wr_data),
        .wr_en           (wr_en),
        .wr_hold         (wr_hold),
        .rd_data         (rd_data),
        .rd_en           (rd_en),
        .rd_slot_o       (rd_slot_o),
        .rd_len_o        (rd_len_o),
        .rd_frame_done   (rd_frame_done),
        .rd_req          (rd_req),
        .rd_busy         (rd_busy),
        .cfg_mode        (cfg_mode),
        .cfg_rd_slot     (cfg_rd_slot),
        .ro_u_wr_frame   (ro_u_wr_frame),
        .ro_u_rd_frame   (ro_u_rd_frame),
        .ro_u_buf_drop   (ro_u_buf_drop),
        .ro_u_hold_cycles(ro_u_hold_cycles),
        .ro_outstanding_sync(ro_outstanding_sync),
        .ro_lat_w        (ro_lat_w),
        .ro_lat_r        (ro_lat_r),
        .dma_engine      (dma_engine),
        .ro_dbg_emit     (ro_dbg_emit),
        .dma_s_tdata     (dma_s_tdata),
        .dma_s_tkeep     (dma_s_tkeep),
        .dma_s_tlast     (dma_s_tlast),
        .dma_s_tvalid    (dma_s_tvalid),
        .dma_s_tready    (dma_s_tready),
        .ro_dma_req      (ro_dma_req),
        .dma_wr_go       (dma_wr_go),
        .dma_wr_ack      (dma_wr_ack),
        .s2mm_introut    (s2mm_introut),
        .dma_wr_tdata    (dma_wr_tdata),
        .dma_wr_tkeep    (dma_wr_tkeep),
        .dma_wr_tlast    (dma_wr_tlast),
        .dma_wr_tvalid   (dma_wr_tvalid),
        .dma_wr_tready   (dma_wr_tready),
        .ro_dma_wr_req   (ro_dma_wr_req),
        .ro_dma_wr_dbg   (ro_dma_wr_dbg),
        .ro_stat_wr_timeout(ro_stat_wr_timeout),
        .ro_dbg_wr_state (ro_dbg_wr_state),
        .ui_clk          (ui_clk),
        .ui_rst_n        (ui_rst_n),
        .calib_ok        (calib_ok),
        .ro_wm           (ro_wm),
        .ro_wr_frame     (ro_wr_frame),
        .ro_wr_stall     (ro_wr_stall),
        .ro_rd_frame     (ro_rd_frame),
        .ro_ill_rd       (ro_ill_rd),
        .ro_noframe      (ro_noframe),
        .ro_bresp_err    (ro_bresp_err),
        .ro_len_err      (ro_len_err),
        .ro_outstanding  (ro_outstanding),
        .ro_dbg_wr_slot  (ro_dbg_wr_slot),
        .ro_dbg_rd_slot  (ro_dbg_rd_slot),
        .dbg_wr_cycles   (dbg_wr_cycles),
        .dbg_rd_cycles   (dbg_rd_cycles),
        .dbg_wr_beats    (dbg_wr_beats),
        .dbg_rd_beats    (dbg_rd_beats),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (1'b0),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (1'b0),
        .m_axi_bresp     (2'b00),
        .m_axi_bvalid    (1'b0),
        .m_axi_bready    (m_axi_bready),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (1'b0),
        .m_axi_rdata     (512'd0),
        .m_axi_rresp     (2'b00),
        .m_axi_rlast     (1'b0),
        .m_axi_rvalid    (1'b0),
        .m_axi_rready    (m_axi_rready),
        .m_axi_awid      (m_axi_awid),
        .m_axi_awlock    (m_axi_awlock),
        .m_axi_awcache   (m_axi_awcache),
        .m_axi_awprot    (m_axi_awprot),
        .m_axi_awqos     (m_axi_awqos),
        .m_axi_bid       (4'd0),
        .m_axi_arid      (m_axi_arid),
        .m_axi_arlock    (m_axi_arlock),
        .m_axi_arcache   (m_axi_arcache),
        .m_axi_arprot    (m_axi_arprot),
        .m_axi_arqos     (m_axi_arqos),
        .m_axi_rid       (4'd0)
    );

    //-------------------------------------------------------------------------
    // 2. 全局记账 / golden 模型
    //-------------------------------------------------------------------------
    integer tb_errors;
    integer cmt_seq;
    integer exp_total;
    integer seed;
    integer fast_mode;
    integer exp_slot_arr [0:255];
    reg [15:0] exp_len_arr [0:255];
    reg [7:0] exp_mem [0:EXPMEM-1];
    integer gm_cursor;
    reg     gm_full [0:255];
    reg [7:0] gen_buf [0:2047];
    reg [15:0] force_ptr;             // force_cursor 用的静态 RHS（force 不允许 automatic 变量）
    integer frame_id;
    integer mdl_xfers;
    reg [31:0] mdl_rec_sa [0:255];
    reg [15:0] mdl_rec_len [0:255];
    integer    mdl_rec_beats [0:255];
    integer last_req_count;
    reg [7:0]  last_req_slot;
    reg [15:0] last_req_len;
    reg        last_req_toggle;
    reg inject_nogo, inject_drop_intr, inject_go_before_clr, t7_window;
    reg fault_latched, halt_latched;

    //-------------------------------------------------------------------------
    // 3. S2MM 行为模型（ui_clk）+ 2MB RAM
    //-------------------------------------------------------------------------
    reg [7:0] ram [0:RAMBYTES-1];
    integer ri;
    initial begin
        for (ri = 0; ri < RAMBYTES; ri = ri + 1) ram[ri] = 8'h00;
    end

    reg        prog_tg;
    reg [31:0] prog_sa;
    reg [15:0] prog_len;
    reg        done_tg;
    reg        clr_tg;
    // 上电初值：done_tg 只由 S2MM 模型在完成拍翻转，若无初值会永久为 X
    initial begin done_tg = 1'b0; prog_tg = 1'b0; clr_tg = 1'b0; end

    function [63:0] exp_keep_mask;
        input [15:0] off;
        input [15:0] len;
        integer rem;
        begin
            if (len > off) begin
                rem = len - off;
                if (rem >= 64) exp_keep_mask = 64'hFFFF_FFFF_FFFF_FFFF;
                else           exp_keep_mask = (64'hFFFF_FFFF_FFFF_FFFF >> (64-rem));
            end else begin
                exp_keep_mask = 64'd0;
            end
        end
    endfunction

    reg        ptg_s1, ptg_s2, ptg_prev;
    reg        mdl_armed, mdl_done, mdl_wait_resp;
    reg [31:0] mdl_sa;
    reg [15:0] mdl_len, mdl_off;
    integer    mdl_beats;
    integer    mdl_resp_cnt;
    reg [63:0] mdl_keep_exp;

    always @(posedge ui_clk or negedge ui_rst_n) begin
        if (!ui_rst_n) begin
            ptg_s1 <= 1'b0; ptg_s2 <= 1'b0; ptg_prev <= 1'b0;
            mdl_armed <= 1'b0; mdl_done <= 1'b0; mdl_wait_resp <= 1'b0;
            mdl_sa <= 32'd0; mdl_len <= 16'd0; mdl_off <= 16'd0;
            mdl_beats <= 0; mdl_resp_cnt <= 0;
            dma_wr_tready <= 1'b0;
        end else begin
            ptg_s1 <= prog_tg; ptg_s2 <= ptg_s1;
            if (ptg_s2 != ptg_prev) begin
                ptg_prev   <= ptg_s2;
                mdl_sa     <= prog_sa;
                mdl_len    <= prog_len;
                mdl_off    <= 16'd0;
                mdl_beats  <= 0;
                mdl_done   <= 1'b0;
                mdl_wait_resp <= 1'b0;
                dma_wr_tready <= (prog_len != 16'd0);
                mdl_armed  <= (prog_len != 16'd0);
            end else if (mdl_armed && !mdl_done && !mdl_wait_resp) begin
                dma_wr_tready <= 1'b1;
                if (dma_wr_tvalid && dma_wr_tready) begin
                    mdl_keep_exp = exp_keep_mask(mdl_off, mdl_len);
                    if (dma_wr_tkeep !== mdl_keep_exp) begin
                        tb_errors = tb_errors + 1;
                        $display("[FAIL-KEEP-MASK] sa=0x%08h beat=%0d off=%0d exp=0x%016h got=0x%016h",
                                 mdl_sa, mdl_beats, mdl_off, mdl_keep_exp, dma_wr_tkeep);
                    end
                    if (dma_wr_tlast !== ((mdl_off + 16'd64) >= mdl_len)) begin
                        tb_errors = tb_errors + 1;
                        $display("[FAIL-TLAST] sa=0x%08h beat=%0d off=%0d len=%0d got_tlast=%0b",
                                 mdl_sa, mdl_beats, mdl_off, mdl_len, dma_wr_tlast);
                    end
                    for (ri = 0; ri < 64; ri = ri + 1) begin
                        if (dma_wr_tkeep[ri])
                            ram[mdl_sa + mdl_off + ri] <= dma_wr_tdata[ri*8 +: 8];
                    end
                    mdl_beats <= mdl_beats + 1;
                    mdl_off   <= mdl_off + 16'd64;
                    if (dma_wr_tlast) begin
                        mdl_done      <= 1'b1;
                        mdl_wait_resp <= 1'b1;
                        mdl_resp_cnt  <= 0;
                        dma_wr_tready <= 1'b0;
                    end
                end
            end else if (mdl_wait_resp) begin
                dma_wr_tready <= 1'b0;
                if (mdl_resp_cnt == 8) begin
                    mdl_wait_resp <= 1'b0;
                    if (!inject_drop_intr) begin
                        // 只有"上报了完成"的传送才进记录（T9 中被 fail-stop 的帧不算一次提交）
                        mdl_rec_sa[mdl_xfers]    <= mdl_sa;
                        mdl_rec_len[mdl_xfers]   <= mdl_len;
                        mdl_rec_beats[mdl_xfers] <= mdl_beats;
                        mdl_xfers <= mdl_xfers + 1;
                        done_tg <= ~done_tg;
                    end
                end else begin
                    mdl_resp_cnt <= mdl_resp_cnt + 1;
                end
            end
        end
    end

    // 3b. lite 域：done_tg / clr_tg 事件 -> s2mm_introut 电平（模拟 BD 直出中断）
    reg done_l_s1, done_l_s2, done_l_prev;
    reg clr_l_s1,  clr_l_s2,  clr_l_prev;
    always @(posedge lite_clk or negedge lite_rst_n) begin
        if (!lite_rst_n) begin
            done_l_s1 <= 1'b0; done_l_s2 <= 1'b0; done_l_prev <= 1'b0;
            clr_l_s1  <= 1'b0; clr_l_s2  <= 1'b0; clr_l_prev  <= 1'b0;
            s2mm_introut <= 1'b0;
        end else begin
            done_l_s1 <= done_tg; done_l_s2 <= done_l_s1;
            clr_l_s1  <= clr_tg;  clr_l_s2  <= clr_l_s1;
            if (done_l_s2 != done_l_prev) begin
                done_l_prev  <= done_l_s2;
                s2mm_introut <= 1'b1;
            end
            if (clr_l_s2 != clr_l_prev) begin
                clr_l_prev   <= clr_l_s2;
                s2mm_introut <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // 4. 软核行为模型（user_clk）
    //-------------------------------------------------------------------------
    localparam SS_IDLE = 3'd0, SS_GO = 3'd1, SS_WAIT = 3'd2,
               SS_REC  = 3'd3, SS_REC2 = 3'd4;
    reg [2:0] sst;
    integer   ss_cnt;

    always @(posedge user_clk or negedge user_rst_n) begin
        if (!user_rst_n) begin
            sst <= SS_IDLE; ss_cnt <= 0;
            last_req_toggle <= 1'b0; last_req_slot <= 8'd0; last_req_len <= 16'd0;
            last_req_count <= 0;
            prog_tg <= 1'b0; prog_sa <= 32'd0; prog_len <= 16'd0;
            clr_tg <= 1'b0; dma_wr_go <= 1'b0; dma_wr_ack <= 1'b0;
            t7_window <= 1'b0;
        end else begin
            case (sst)
            SS_IDLE: begin
                if (ro_dma_wr_dbg[31]) begin
                    sst <= SS_REC; ss_cnt <= 0;
                    clr_tg   <= ~clr_tg;
                    prog_len <= 16'd0;
                    prog_tg  <= ~prog_tg;
                end else if (ro_dma_wr_req[31] && (ro_dma_wr_req[24] !== last_req_toggle)) begin
                    last_req_toggle <= ro_dma_wr_req[24];
                    last_req_slot   <= ro_dma_wr_req[23:16];
                    last_req_len    <= ro_dma_wr_req[15:0];
                    last_req_count  <= last_req_count + 1;
                    if (inject_nogo) begin
                        // T6：软核"不驻留"，不编程/不清 IOC/不翻 GO
                    end else begin
                        prog_sa  <= SLOT_BASE + {ro_dma_wr_req[23:16], 12'b0};
                        prog_len <= ro_dma_wr_req[15:0];
                        prog_tg  <= ~prog_tg;
                        sst      <= SS_GO;
                        ss_cnt   <= 0;
                    end
                end
            end
            SS_GO: begin
                ss_cnt <= ss_cnt + 1;
                if (!inject_go_before_clr) begin
                    if (ss_cnt == 2) clr_tg <= ~clr_tg;
                    if (ss_cnt == 8) begin
                        dma_wr_go <= ~dma_wr_go;
                        sst <= SS_WAIT;
                    end
                end else begin
                    if (ss_cnt == 2) begin
                        dma_wr_go <= ~dma_wr_go;
                        t7_window <= 1'b1;
                    end
                    if (ss_cnt == 8) begin
                        clr_tg <= ~clr_tg;
                        t7_window <= 1'b0;
                        sst <= SS_WAIT;
                    end
                end
            end
            SS_WAIT: begin
                // 本帧结束（提交/丢弃）或下一帧请求已紧接到达（back-to-back）
                if (!ro_dma_wr_req[31] || (ro_dma_wr_req[24] !== last_req_toggle))
                    sst <= SS_IDLE;
            end
            SS_REC: begin
                ss_cnt <= ss_cnt + 1;
                if (ss_cnt == 6) begin
                    dma_wr_ack <= ~dma_wr_ack;
                    sst <= SS_REC2; ss_cnt <= 0;
                end
            end
            SS_REC2: begin
                ss_cnt <= ss_cnt + 1;
                if (ss_cnt == 8) sst <= SS_IDLE;
            end
            default: sst <= SS_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // 5. 监视与逐项判据（ui_clk）
    //-------------------------------------------------------------------------
    reg [15:0] wm_prev;
    integer chk_wait, chk_idx, axi_viol;

    always @(posedge ui_clk) begin
        if (ui_rst_n) begin
            if (m_axi_awvalid !== 1'b0 || m_axi_wvalid !== 1'b0 || m_axi_arvalid !== 1'b0) begin
                axi_viol = axi_viol + 1;
                if (axi_viol < 4)
                    $display("[FAIL-AXI-WRITE] retired bridge AXI port active aw=%0b w=%0b ar=%0b",
                             m_axi_awvalid, m_axi_wvalid, m_axi_arvalid);
            end
        end
    end

    always @(posedge ui_clk) begin
        if (!ui_rst_n) begin
            fault_latched <= 1'b0;
            halt_latched  <= 1'b0;
        end else begin
            if (ro_dma_wr_dbg[31] === 1'b1) fault_latched <= 1'b1;
            if (ro_dbg_wr_state === 3'd6)   halt_latched  <= 1'b1;
        end
    end

    always @(posedge ui_clk) begin
        if (ui_rst_n && t7_window && s2mm_introut) begin
            if (ro_dbg_wr_state === 3'd2 || ro_dbg_wr_state === 3'd3) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T7-GO-GATE] stream started (state=%0d) while introut=1", ro_dbg_wr_state);
            end
        end
    end

    task automatic cmp_commit;
        input integer idx;
        integer slot, base, k, ntail;
        begin
            if (idx >= exp_total) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-COMMIT] commit idx=%0d but only %0d expected", idx, exp_total);
            end else begin
                slot = exp_slot_arr[idx];
                base = SLOT_BASE + slot*SLOT_SZ;
                if (mdl_xfers <= idx) begin
                    tb_errors = tb_errors + 1;
                    $display("[FAIL-SLOT-MAP] idx=%0d: S2MM model only %0d xfers", idx, mdl_xfers);
                end else begin
                    if (mdl_rec_sa[idx] !== base) begin
                        tb_errors = tb_errors + 1;
                        $display("[FAIL-SLOT-MAP] idx=%0d exp_sa=0x%08h got=0x%08h exp_slot=%0d",
                                 idx, base, mdl_rec_sa[idx], slot);
                    end
                    if (mdl_rec_len[idx] !== exp_len_arr[idx]) begin
                        tb_errors = tb_errors + 1;
                        $display("[FAIL-SLOT-MAP] idx=%0d exp_len=%0d got=%0d",
                                 idx, exp_len_arr[idx], mdl_rec_len[idx]);
                    end
                    if (mdl_rec_beats[idx] !== ((exp_len_arr[idx] + 63)/64)) begin
                        tb_errors = tb_errors + 1;
                        $display("[FAIL-BEATS] idx=%0d exp=%0d got=%0d",
                                 idx, (exp_len_arr[idx]+63)/64, mdl_rec_beats[idx]);
                    end
                end
                if (dut.u_bridge.full_bit[slot] !== 1'b1) begin
                    tb_errors = tb_errors + 1;
                    $display("[FAIL-FULLBIT] idx=%0d slot=%0d full_bit!=1", idx, slot);
                end
                if (dut.u_bridge.len_tab[slot] !== exp_len_arr[idx]) begin
                    tb_errors = tb_errors + 1;
                    $display("[FAIL-LENTAB] idx=%0d slot=%0d exp=%0d got=%0d",
                             idx, slot, exp_len_arr[idx], dut.u_bridge.len_tab[slot]);
                end
                for (k = 0; k < exp_len_arr[idx]; k = k + 1) begin
                    if (ram[base+k] !== exp_mem[idx*MAXLEN + k]) begin
                        tb_errors = tb_errors + 1;
                        if (tb_errors < 40)
                            $display("[FAIL-BYTE] idx=%0d slot=%0d k=%0d exp=0x%02h got=0x%02h",
                                     idx, slot, k, exp_mem[idx*MAXLEN+k], ram[base+k]);
                    end
                end
                ntail = ((exp_len_arr[idx] + 63)/64)*64;
                for (k = exp_len_arr[idx]; k < ntail; k = k + 1) begin
                    if (ram[base+k] !== 8'h00) begin
                        tb_errors = tb_errors + 1;
                        if (tb_errors < 40)
                            $display("[FAIL-TAIL-WRITE] idx=%0d slot=%0d k=%0d got=0x%02h",
                                     idx, slot, k, ram[base+k]);
                    end
                end
                if (idx < 12)
                    $display("[T] commit idx=%0d slot=%0d len=%0d beats=%0d checked",
                             idx, slot, exp_len_arr[idx], mdl_rec_beats[idx]);
            end
        end
    endtask

    always @(posedge ui_clk or negedge ui_rst_n) begin
        if (!ui_rst_n) begin
            wm_prev  <= 16'd0;
            cmt_seq  <= 0;
            chk_wait <= 0;
            chk_idx  <= 0;
            axi_viol <= 0;
        end else begin
            wm_prev <= ro_wm;
            if (ro_wm !== wm_prev) begin
                chk_idx  <= cmt_seq;
                cmt_seq  <= cmt_seq + 1;
                chk_wait <= 3;
            end else if (chk_wait > 0) begin
                chk_wait <= chk_wait - 1;
                if (chk_wait == 1) cmp_commit(chk_idx);
            end
        end
    end

    //-------------------------------------------------------------------------
    // 6. 帧激励（user_clk）
    //-------------------------------------------------------------------------
    function [7:0] pat_byte;
        input integer fid;
        input integer k;
        begin
            pat_byte = (fid[7:0]*8'h3B) ^ (k[7:0]*8'h1D) ^ (k[15:8]*8'h57) ^ 8'hA5;
        end
    endfunction

    task automatic fill_frame;
        input integer fid;
        input integer len;
        input integer is_random;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                if (is_random) gen_buf[k] = $random(seed);
                else           gen_buf[k] = pat_byte(fid, k);
            end
        end
    endtask

    task automatic drive_frame;
        input integer len;
        integer k;
        begin
            while (wr_hold) @(negedge user_clk);
            @(negedge user_clk);
            for (k = 0; k < len; k = k + 1) begin
                wr_en   = 1'b1;
                wr_data = gen_buf[k];
                @(negedge user_clk);
            end
            wr_en   = 1'b0;
            wr_data = 8'd0;
            @(negedge user_clk);
        end
    endtask

    task automatic wait_commit;
        input integer target;
        input integer max_ui;
        output integer ok;
        integer n;
        begin
            n = 0;
            while ((cmt_seq < target) && (n < max_ui)) begin
                @(posedge ui_clk); n = n + 1;
            end
            ok = (cmt_seq >= target);
            if (!ok) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-TIMEOUT] commit target=%0d got=%0d waited=%0d", target, cmt_seq, n);
            end
        end
    endtask

    task automatic wait_req_count;
        input integer target;
        input integer max_ui;
        output integer ok;
        integer n;
        begin
            n = 0;
            while ((last_req_count < target) && (n < max_ui)) begin
                @(posedge ui_clk); n = n + 1;
            end
            ok = (last_req_count >= target);
        end
    endtask

    task automatic send_expect_commit;
        input integer len;
        input integer is_random;
        integer slot, k, ok;
        begin
            slot = gm_cursor % 256;
            if (gm_full[slot]) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-GM] expect commit into full slot=%0d cursor=%0d", slot, gm_cursor);
            end
            fill_frame(frame_id, len, is_random);
            for (k = 0; k < len; k = k + 1) exp_mem[exp_total*MAXLEN + k] = gen_buf[k];
            exp_slot_arr[exp_total] = slot;
            exp_len_arr[exp_total]  = len;
            exp_total = exp_total + 1;
            gm_full[slot] = 1'b1;
            gm_cursor = gm_cursor + 1;
            frame_id = frame_id + 1;
            drive_frame(len);
            wait_commit(exp_total, 900000, ok);
            if (!ok) $display("[FAIL-TIMEOUT] frame len=%0d slot=%0d not committed", len, slot);
        end
    endtask

    task automatic force_cursor;
        input integer ptr;
        begin
            // force 的 RHS 是连续赋值语义，不能用 automatic 变量 -> 先写静态 reg
            force_ptr = ptr[15:0];
            force dut.u_bridge.wr_slot_ptr = force_ptr;
            repeat (4) @(posedge ui_clk);
            release dut.u_bridge.wr_slot_ptr;
            repeat (2) @(posedge ui_clk);
            gm_cursor = ptr;
        end
    endtask

    //-------------------------------------------------------------------------
    // 7. 测试主序
    //-------------------------------------------------------------------------
    integer i, k, ok, c0, ref_slot, ref_len, st_base, len_err_base, timeout_base, wm_base;
    integer n_refusals;
    reg [7:0] ref_b0, ref_b1;
    time t_start, t_end;

    initial begin
        tb_errors = 0; cmt_seq = 0; exp_total = 0; seed = 32'h0517_2026;
        frame_id = 0; gm_cursor = 0; mdl_xfers = 0;
        last_req_count = 0; axi_viol = 0;
        fault_latched = 1'b0; halt_latched = 1'b0;
        user_rst_n = 1'b0; ui_rst_n = 1'b0; lite_rst_n = 1'b0;
        calib_ok = 1'b0; wr_data = 8'd0; wr_en = 1'b0; rd_req = 1'b0;
        cfg_mode = 1'b0; cfg_rd_slot = 8'd0; dma_engine = 1'b0;
        dma_s_tdata = 512'd0; dma_s_tkeep = 64'd0;
        dma_s_tlast = 1'b0; dma_s_tvalid = 1'b0; dma_wr_tready = 1'b0;
        dma_wr_go = 1'b0; dma_wr_ack = 1'b0;
        inject_nogo = 0; inject_drop_intr = 0; inject_go_before_clr = 0; t7_window = 0;
        for (i = 0; i < 256; i = i + 1) gm_full[i] = 1'b0;
        if (!$value$plusargs("SEED=%d", seed)) seed = 32'h0517_2026;
        if (!$value$plusargs("FAST=%d", fast_mode)) fast_mode = 0;
`ifdef R2_FAST
        fast_mode = 1;      // 负向对照轮：xvlog -d R2_FAST，仅省 T6 的 16.7M 拍等待
`endif

        $display("=== R2 WR TB user=151.5M ui=300M lite=100M HAS_DMA=1 seed=0x%08h fast=%0d ===",
                 seed, fast_mode);
        repeat (20) @(posedge ui_clk);
        user_rst_n = 1'b1; ui_rst_n = 1'b1; lite_rst_n = 1'b1;
        repeat (20) @(posedge user_clk);
        calib_ok = 1'b1;
        repeat (100) @(posedge user_clk);
        wm_base = ro_wm; st_base = ro_wr_stall; len_err_base = ro_len_err;
        timeout_base = ro_stat_wr_timeout;

        //================================================================== T1
        $display("[T1] single full-beat frame len=64");
        send_expect_commit(64, 0);
        $display("[T1] done cmt=%0d", cmt_seq);

        //================================================================== T2
        $display("[T2] tail-beat frame len=70 (tail keep = 6 lanes)");
        send_expect_commit(70, 0);
        $display("[T2] done cmt=%0d", cmt_seq);
`ifdef R2_NEG_TKEEP
        // 负向对照轮专用早停：命中 [FAIL-KEEP-MASK] 后立刻给出 FAIL 判词
        if (tb_errors > 0) begin
            $display("=== R2 WR TB: FAIL (%0d errors) [NEG-TKEEP early stop] ===", tb_errors);
            $finish;
        end
`endif

        //================================================================== T3
        $display("[T3] 3 back-to-back frames len=96/130/64");
        begin : t3
            integer tl [0:2];
            integer tj, ts, tk;
            tl[0] = 96; tl[1] = 130; tl[2] = 64;
            for (tj = 0; tj < 3; tj = tj + 1) begin
                ts = gm_cursor % 256;
                fill_frame(frame_id, tl[tj], 0);
                for (tk = 0; tk < tl[tj]; tk = tk + 1)
                    exp_mem[exp_total*MAXLEN + tk] = gen_buf[tk];
                exp_slot_arr[exp_total] = ts;
                exp_len_arr[exp_total]  = tl[tj];
                exp_total = exp_total + 1;
                gm_full[ts] = 1'b1;
                gm_cursor = gm_cursor + 1;
                frame_id = frame_id + 1;
                drive_frame(tl[tj]);
            end
            wait_commit(exp_total, 900000, ok);
            $display("[T3] done cmt=%0d", cmt_seq);
        end

        //================================================================== T4
        $display("[T4] full-slot refusal (no overwrite, cursor advances)");
        send_expect_commit(150, 0);
        ref_slot = (gm_cursor - 1) % 256;
        ref_len  = exp_len_arr[exp_total-1];
        ref_b0 = ram[SLOT_BASE + ref_slot*SLOT_SZ + 0];
        ref_b1 = ram[SLOT_BASE + ref_slot*SLOT_SZ + 1];
        force_cursor(gm_cursor - 1 + 256);
        begin : t4
            integer c_ref, exp_next, slot_now;
            c_ref = cmt_seq;
            fill_frame(frame_id, 200, 0);
            gm_cursor = gm_cursor + 1;
            frame_id = frame_id + 1;
            drive_frame(200);
            repeat (800) @(posedge ui_clk);
            if (cmt_seq !== c_ref) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T4-OVERWRITE] refused frame committed cmt %0d->%0d", c_ref, cmt_seq);
            end
            if (ro_wr_stall !== (st_base + 1)) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T4-STALL] stat_wr_stall exp=%0d got=%0d", st_base+1, ro_wr_stall);
            end
            if (ram[SLOT_BASE + ref_slot*SLOT_SZ + 0] !== ref_b0 ||
                ram[SLOT_BASE + ref_slot*SLOT_SZ + 1] !== ref_b1) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T4-OVERWRITE] slot=%0d bytes changed by refused frame", ref_slot);
            end
            if (dut.u_bridge.full_bit[ref_slot] !== 1'b1 ||
                dut.u_bridge.len_tab[ref_slot]  !== ref_len[15:0]) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T4-OVERWRITE] slot=%0d full/len_tab changed", ref_slot);
            end
            exp_next = gm_cursor % 256;
            fill_frame(frame_id, 120, 0);
            for (k = 0; k < 120; k = k + 1) exp_mem[exp_total*MAXLEN + k] = gen_buf[k];
            exp_slot_arr[exp_total] = exp_next;
            exp_len_arr[exp_total]  = 120;
            exp_total = exp_total + 1;
            gm_full[exp_next] = 1'b1;
            gm_cursor = gm_cursor + 1;
            frame_id = frame_id + 1;
            c0 = last_req_count;
            drive_frame(120);
            wait_req_count(c0 + 1, 20000, ok);
            if (!ok) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T4-CURSOR] no request after refusal (cursor not advanced)");
            end else begin
                slot_now = last_req_slot;
                if (slot_now !== exp_next) begin
                    tb_errors = tb_errors + 1;
                    $display("[FAIL-T4-CURSOR] req slot=%0d exp=%0d (refused frame did not advance cursor)",
                             slot_now, exp_next);
                end
            end
            wait_commit(exp_total, 900000, ok);
            if (!ok) $display("[FAIL-T4-CURSOR] commit after refused frame never came");
        end
        $display("[T4] done cmt=%0d stall=%0d", cmt_seq, ro_wr_stall);
`ifdef R2_NEG_CURSOR
        // 负向对照轮专用早停：命中 [FAIL-T4-CURSOR] 后立刻给出 FAIL 判词，省后续用例时间
        if (tb_errors > 0) begin
            $display("=== R2 WR TB: FAIL (%0d errors) [NEG-CURSOR early stop] ===", tb_errors);
            $finish;
        end
`endif

        //================================================================== T5
        $display("[T5] over-length refusal len=1600 > MAX_LEN=1538 (len==0 unreachable at fmi)");
        begin : t5
            integer c5;
            c5 = cmt_seq;
            ref_slot = gm_cursor % 256;
            fill_frame(frame_id, 1600, 0);
            gm_cursor = gm_cursor + 1;
            frame_id = frame_id + 1;
            drive_frame(1600);
            repeat (4000) @(posedge ui_clk);
            if (cmt_seq !== c5) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T5] over-length frame committed");
            end
            if (ro_len_err !== (len_err_base + 1)) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T5] stat_len_err exp=%0d got=%0d", len_err_base+1, ro_len_err);
            end
            if (dut.u_bridge.full_bit[ref_slot] !== 1'b0) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T5] slot=%0d marked full by over-length frame", ref_slot);
            end
            $display("[T5] refused len_err=%0d cursor=%0d", ro_len_err, gm_cursor);
            repeat (100) @(posedge user_clk);
        end

        //================================================================== T6
        if (fast_mode) begin
            $display("[T6] SKIPPED (FAST mode)");
        end else begin
            $display("[T6] GO-missing timeout (real wait ~16.7M ui cycles) -- drop, no stall");
            begin : t6
                integer to0, n;
                to0 = ro_stat_wr_timeout;
                inject_nogo = 1'b1;
                fill_frame(frame_id, 200, 0);
                gm_cursor = gm_cursor + 1;
                frame_id = frame_id + 1;
                drive_frame(200);
                t_start = $time;
                n = 0;
                while ((ro_stat_wr_timeout == to0) && (n < 20000000)) begin
                    @(posedge ui_clk); n = n + 1;
                end
                t_end = $time;
                if (ro_stat_wr_timeout !== (to0 + 1)) begin
                    tb_errors = tb_errors + 1;
                    $display("[FAIL-T6] GO-missing watchdog not observed exp=%0d got=%0d",
                             to0+1, ro_stat_wr_timeout);
                end else begin
                    $display("[T6] WAITGO watchdog fired ui_cycles=%0d sim_time=%0t timeout=%0d",
                             n, t_end - t_start, ro_stat_wr_timeout);
                end
                inject_nogo = 1'b0;
                if (cmt_seq !== exp_total) begin
                    tb_errors = tb_errors + 1;
                    $display("[FAIL-T6] dropped frame committed cmt=%0d exp=%0d", cmt_seq, exp_total);
                end
                if (ro_dma_wr_dbg[31] !== 1'b0) begin
                    tb_errors = tb_errors + 1;
                    $display("[FAIL-T6] fault set by WAITGO timeout (should stay 0)");
                end
                send_expect_commit(200, 0);
                $display("[T6] not stalled: next frame committed cmt=%0d", cmt_seq);
            end
        end

        //================================================================== T7
        $display("[T7] GO-before-IOC-clear gate (continuous frames)");
        inject_go_before_clr = 1'b1;
        send_expect_commit(140, 0);
        inject_go_before_clr = 1'b0;
        send_expect_commit(90, 0);
        $display("[T7] done cmt=%0d timeout=%0d (no double commit)", cmt_seq, ro_stat_wr_timeout);

        //================================================================== T8
        $display("[T8] rule#1 golden model random 100 frames (wrap at 256, forced cursor=220)");
        force_cursor(220);
        n_refusals = 0;
        begin : t8
            integer pre_cmt, pre_stall, exp_ref, slot8, j, c8;
            reg [15:0] len8;
            integer lens_tab [0:15];
            lens_tab[0]=1;   lens_tab[1]=63;  lens_tab[2]=64;  lens_tab[3]=65;
            lens_tab[4]=70;  lens_tab[5]=127; lens_tab[6]=128; lens_tab[7]=129;
            lens_tab[8]=255; lens_tab[9]=256; lens_tab[10]=511;lens_tab[11]=512;
            lens_tab[12]=1023; lens_tab[13]=1024; lens_tab[14]=1537; lens_tab[15]=1538;
            pre_cmt = cmt_seq; pre_stall = ro_wr_stall; exp_ref = 0;
            for (j = 0; j < 100; j = j + 1) begin
                slot8 = gm_cursor % 256;
                if (j < 16) len8 = lens_tab[j];
                else        len8 = ($random(seed) & 32'h7FFF) % 1538 + 1;
                if (gm_full[slot8]) begin
                    c8 = cmt_seq;
                    fill_frame(frame_id, len8, 0);
                    gm_cursor = gm_cursor + 1;
                    frame_id = frame_id + 1;
                    n_refusals = n_refusals + 1;
                    exp_ref = exp_ref + 1;
                    drive_frame(len8);
                    repeat (500) @(posedge ui_clk);
                    if (cmt_seq !== c8) begin
                        tb_errors = tb_errors + 1;
                        $display("[FAIL-T8-REFUSE] frame %0d into FULL slot=%0d committed", j, slot8);
                    end
                end else begin
                    send_expect_commit(len8, 1);
                end
                if ((j % 10) == 9)
                    $display("[T8] progress %0d/100 cmt=%0d refuses=%0d cursor=%0d",
                             j+1, cmt_seq, n_refusals, gm_cursor);
            end
            if (gm_cursor !== 320) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T8] golden cursor exp=320 got=%0d", gm_cursor);
            end
            if (cmt_seq !== (pre_cmt + 100 - exp_ref)) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T8] commit count exp=%0d got=%0d", pre_cmt+100-exp_ref, cmt_seq);
            end
            if (ro_wr_stall !== (pre_stall + exp_ref)) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T8] stat_wr_stall exp=%0d got=%0d", pre_stall+exp_ref, ro_wr_stall);
            end
            for (k = exp_total-5; k < exp_total; k = k + 1) begin
                if (k >= 0) cmp_commit(k);
            end
            $display("[T8] done cursor=%0d cmt_total=%0d refused=%0d stall=%0d",
                     gm_cursor, cmt_seq, n_refusals, ro_wr_stall);
        end

        //================================================================== T9
        $display("[T9] WAITDONE watchdog -> fail-stop(HALT) -> soft-core ACK recovery");
        begin : t9
            integer to1, c9, n;
            to1 = ro_stat_wr_timeout;
            c9 = cmt_seq;
            inject_drop_intr = 1'b1;
            fill_frame(frame_id, 180, 0);
            gm_cursor = gm_cursor + 1;
            frame_id = frame_id + 1;
            drive_frame(180);
            n = 0;
            while ((ro_dbg_wr_state !== 3'd4) && (n < 50000)) begin
                @(posedge ui_clk); n = n + 1;
            end
            if (ro_dbg_wr_state !== 3'd4) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T9] bridge never reached WAITDONE (state=%0d)", ro_dbg_wr_state);
            end else begin
                // 时基加速（仅仿真）：wd_done_cnt 预置 24'hFFFFFC，等 ~3 拍超时
                force dut.u_bridge.g_wr_dma.wd_done_cnt = 24'hFFFFFC;
                repeat (2) @(posedge ui_clk);
                release dut.u_bridge.g_wr_dma.wd_done_cnt;
            end
            repeat (40) @(posedge ui_clk);
            inject_drop_intr = 1'b0;
            if (ro_stat_wr_timeout !== (to1 + 1)) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T9] timeout count exp=%0d got=%0d", to1+1, ro_stat_wr_timeout);
            end
            if (!halt_latched) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T9] HALT state never observed (fail-stop missing)");
            end
            if (!fault_latched) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T9] fault bit never observed (fail-stop flag missing)");
            end
            n = 0;
            while ((ro_dbg_wr_state !== 3'd0) && (n < 200000)) begin
                @(posedge ui_clk); n = n + 1;
            end
            if (ro_dbg_wr_state !== 3'd0) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T9] recovery did not return to IDLE (state=%0d)", ro_dbg_wr_state);
            end
            if (ro_dma_wr_dbg[31] !== 1'b0) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T9] fault sticky not cleared after WRACK recovery");
            end
            if (cmt_seq !== c9) begin
                tb_errors = tb_errors + 1;
                $display("[FAIL-T9] timed-out frame committed cmt %0d->%0d", c9, cmt_seq);
            end else begin
                $display("[T9] HALT/fault/recovery OK timeout=%0d", ro_stat_wr_timeout);
            end
            send_expect_commit(160, 0);
            $display("[T9] post-recovery commit OK cmt=%0d", cmt_seq);
        end

        //============================================================== 总判据
        repeat (200) @(posedge ui_clk);
        $display("-------------------------------------------------------------");
        $display("[SUMMARY] commits=%0d exp=%0d stall=%0d len_err=%0d timeout=%0d wm=%0d",
                 cmt_seq, exp_total, ro_wr_stall, ro_len_err, ro_stat_wr_timeout, ro_wm);
        if ($isunknown({dut.u_bridge.wr_slot_ptr, ro_wm, ro_dma_wr_req})) begin
            tb_errors = tb_errors + 1;
            $display("[FAIL-X] X detected on wr_slot_ptr/ro_wm/ro_dma_wr_req");
        end
        if ((cmt_seq !== exp_total) || (axi_viol != 0)) tb_errors = tb_errors + 1;
        if (tb_errors == 0)
            $display("=== R2 WR TB: PASS (0 errors) ===");
        else
            $display("=== R2 WR TB: FAIL (%0d errors) ===", tb_errors);
        $finish;
    end

    // 全局兜底：TB 自身缺陷不得让 xsim 永久挂（300ms 仿真时间 >> T6 的 56ms）
    initial begin
        #300_000_000;
        $display("[FAIL-GLOBAL-TIMEOUT] TB watchdog at %0t", $time);
        $display("=== R2 WR TB: FAIL (global timeout) ===");
        $finish;
    end

endmodule
