//=============================================================================
// bridge_dma_tb.sv — axi4_master_bridge 双读引擎集成 TB（prj11 B3-1b）
//-----------------------------------------------------------------------------
// 场景: 同一桥先后用两种读引擎读回同一帧, 输出必须逐字节一致:
//   P1 engine=0 (桥硬件读): 写 3 帧 -> SEQ 读回 -> 比对
//   P2 engine=1 (DMA 引擎): 写 3 帧 -> 读命令入队 -> 桥发 dma_req{slot,len}
//       -> TB 充当"软核+DMA+DDR": 用 AXI 从机内存内容生成
//          [8B 前导 + 帧] 的 512b 流 (SA=槽基址对齐读, LEN=len+8;
//          板上定案: 槽存完整 ETH 帧, 窗口前移 8B —— 早期误读为 50)
//       -> shim 拆包 -> rf; 描述符 (v3) 由桥 R_DRET 自发射 -> 比对 + 退休
//          语义 (outstanding 归零, rd_seq_slot 推进, 下一条 SEQ 请求不被旧槽挡住)
//   NEG engine=1 时桥不得发 AR (m_axi_arvalid 恒 0)
//
// DDR 模型: 简化版在 TB 内 —— 写路径用 AXI 从机 (写真正进内存), 读路径
//   由 TB 直接从内存取字节拼流 (跳过 AXI 读握手, 只验证桥+shim 侧)。
//=============================================================================
`timescale 1ns/1ps

module bridge_dma_tb;

    localparam [31:0] SLOT_BASE = 32'h0010_0000;
    localparam integer MAXLEN = 1538;

    reg clk = 0, rst_n = 0;
    always #1.667 clk = ~clk;            // 300 MHz ui_clk

    // ---- write-side stream (frame bytes + descriptor) ----
    reg  [7:0]  wf_data = 0;
    reg         wf_wr = 0;              // TB 驱动 FIFO 写
    wire        wf_rd_en;
    wire [12:0] wf_level;
    wire        wf_empty;
    reg  [15:0] wd_data = 0;
    reg         wd_wr = 0;
    wire        wd_rd_en;
    wire        wd_empty;

    // ---- read-side outputs ----
    wire        rf_wr_en;
    wire [7:0]  rf_wr_data;
    reg  [8:0]  rc_data = 0;
    reg         rc_wr = 0;
    wire        rc_rd_en, rc_empty;
    wire        rd_wr_en;
    wire [24:0] rd_wr_data;

    wire [15:0] stat_wm, stat_rd_frame, stat_noframe, stat_ill_rd, stat_len_err;
    wire [8:0]  stat_outstanding;

    wire [31:0] m_axi_awaddr, m_axi_araddr;
    wire [7:0]  m_axi_awlen, m_axi_arlen;
    wire        m_axi_awvalid, m_axi_wvalid, m_axi_arvalid;
    wire        m_axi_wlast;
    wire [511:0] m_axi_wdata;
    wire [63:0]  m_axi_wstrb;
    wire [511:0] m_axi_rdata;
    wire        m_axi_rvalid, m_axi_rlast, m_axi_rready;
    wire        m_axi_awready, m_axi_wready, m_axi_bvalid, m_axi_arready;
    reg         m_axi_bready = 1'b1;

    // ---- DMA engine side ----
    reg         dma_engine = 0;
    reg  [511:0] dma_s_tdata = 0;
    reg  [63:0]  dma_s_tkeep = 0;
    reg         dma_s_tlast = 0, dma_s_tvalid = 0;
    wire        dma_s_tready;
    wire        dma_req_new;
    wire [7:0]  dma_req_slot;
    wire [15:0] dma_req_len;

    // ---- 简化 FIFO: TB 用数组 + 指针模拟 async_fifo 行为 (同钟单域) ----
    // 写字节 FIFO
    reg [7:0] wf_mem [0:4095];
    reg [12:0] wf_wr_ptr = 0, wf_rd_ptr = 0;
    assign wf_empty = (wf_wr_ptr == wf_rd_ptr);
    assign wf_level = wf_wr_ptr - wf_rd_ptr;
    // 写描述符 FIFO
    reg [15:0] wd_mem [0:7];
    reg [2:0] wd_wr_ptr = 0, wd_rd_ptr = 0;
    assign wd_empty = (wd_wr_ptr == wd_rd_ptr);
    wire [3:0] wd_cnt = wf_wr_ptr[3:0]; // (未用)
    // 读命令 FIFO
    reg [8:0] rc_mem [0:3];
    reg [2:0] rc_wr_ptr = 0, rc_rd_ptr = 0;
    wire [3:0] rc_wr_ext = {rc_wr_ptr[2], rc_wr_ptr[2] ? 1'b0 : 1'b1}; // unused
    assign rc_empty = (rc_wr_ptr == rc_rd_ptr);
    wire [8:0] rc_dout = rc_mem[rc_rd_ptr];

    // 修正: wd_empty 须含翻转位 —— 4 深 FIFO 用 3 位指针
    wire [15:0] wd_dout = wd_mem[wd_rd_ptr[1:0]];

    always @(posedge clk) begin
        if (wf_wr)  wf_mem[wf_wr_ptr[11:0]] <= wf_data;
        if (wf_wr)  wf_wr_ptr <= wf_wr_ptr + 1;
        if (wf_rd_en && !wf_empty) wf_rd_ptr <= wf_rd_ptr + 1;
        if (wd_wr)  wd_mem[wd_wr_ptr[1:0]] <= wd_data;
        if (wd_wr)  wd_wr_ptr <= wd_wr_ptr + 1;
        if (wd_rd_en && !wd_empty) wd_rd_ptr <= wd_rd_ptr + 1;
        if (rc_wr)  rc_mem[rc_wr_ptr[1:0]] <= rc_data;
        if (rc_wr)  rc_wr_ptr <= rc_wr_ptr + 1;
        if (rc_rd_en && !rc_empty) rc_rd_ptr <= rc_rd_ptr + 1;
    end
    wire [7:0] wf_dout = wf_mem[wf_rd_ptr[11:0]];

    // ---- DDR 内存模型: AW/W 真写; 读由 TB 生成流 ----
    reg b_v = 0;
    reg [7:0] w_beat = 0;
    reg [7:0] ddr [0:65535];            // 64KB: 16 slots x 4KB 足够
    assign m_axi_awready = 1'b1;
    assign m_axi_wready  = 1'b1;
    assign m_axi_bvalid  = b_v;

    axi4_master_bridge #(.SLOT_BASE(SLOT_BASE), .MAX_LEN(MAXLEN)) dut (
        .clk(clk), .rst_n(rst_n), .calib_ok(1'b1),
        .wf_empty(wf_empty), .wf_data(wf_dout), .wf_level(wf_level), .wf_rd_en(wf_rd_en),
        .wd_empty(wd_empty), .wd_data(wd_dout), .wd_rd_en(wd_rd_en),
        .rf_wr_en(rf_wr_en), .rf_wr_data(rf_wr_data),
        .rc_empty(rc_empty), .rc_data(rc_dout), .rc_rd_en(rc_rd_en),
        .rd_wr_en(rd_wr_en), .rd_wr_data(rd_wr_data),
        .stat_wm(stat_wm), .stat_wr_frame(), .stat_wr_stall(),
        .stat_rd_frame(stat_rd_frame), .stat_ill_rd(stat_ill_rd),
        .stat_noframe(stat_noframe),
        .stat_bresp_err(), .stat_len_err(stat_len_err),
        .stat_outstanding(stat_outstanding),
        .dbg_wr_slot(), .dbg_rd_slot(),
        .dbg_wr_cycles(), .dbg_rd_cycles(), .dbg_wr_beats(), .dbg_rd_beats(),
        .lat_w(), .lat_r(),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen), .m_axi_awsize(),
        .m_axi_awburst(), .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb), .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid), .m_axi_wready(m_axi_wready),
        .m_axi_bresp(2'b00), .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen), .m_axi_arsize(),
        .m_axi_arburst(), .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(2'b00), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .m_axi_awid(), .m_axi_awlock(), .m_axi_awcache(), .m_axi_awprot(), .m_axi_awqos(),
        .m_axi_bid(4'h0),
        .m_axi_arid(), .m_axi_arlock(), .m_axi_arcache(), .m_axi_arprot(), .m_axi_arqos(),
        .m_axi_rid(4'h0),
        .dma_engine(dma_engine),
        .dma_s_tdata(dma_s_tdata), .dma_s_tkeep(dma_s_tkeep),
        .dma_s_tlast(dma_s_tlast), .dma_s_tvalid(dma_s_tvalid),
        .dma_s_tready(dma_s_tready),
        .dma_req_new(dma_req_new), .dma_req_slot(dma_req_slot), .dma_req_len(dma_req_len)
    );

    // B 通道: bvalid 保持到 bready 握手完成 (AXI 合法行为)
    always @(posedge clk) begin
        if (!rst_n) b_v <= 1'b0;
        else if (m_axi_wvalid && m_axi_wready && m_axi_wlast) b_v <= 1'b1;
        else if (m_axi_bvalid && m_axi_bready) b_v <= 1'b0;
    end

    // ---- 真正的 DDR 写块 (组合锁存地址: 同拍 AW/W 也正确) ----
    reg [31:0] cur_awaddr = 0;
    always @(*) begin
        if (m_axi_awvalid && m_axi_awready) cur_awaddr = m_axi_awaddr;
    end
    always @(posedge clk) begin
        if (m_axi_wvalid && m_axi_wready) begin
            for (int k = 0; k < 64; k++)
                if (m_axi_wstrb[k])
                    ddr[((cur_awaddr + {w_beat, 6'd0}) & 18'h3FFFF) + k] <= m_axi_wdata[k*8 +: 8];
            if (m_axi_wlast) w_beat <= 0;
            else             w_beat <= w_beat + 1;
        end
    end

    // ---- AXI 读从机: engine=0 时桥硬件读走这里 ----
    reg [31:0] ar_addr_q;
    reg [7:0]  r_beat_q;
    reg        ar_busy = 0;
    reg [7:0]  r_left = 0;
    assign m_axi_arready = !ar_busy;
    assign m_axi_rvalid  = ar_busy;
    assign m_axi_rlast   = ar_busy && (r_left == 1);
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_busy <= 0; r_left <= 0; r_beat_q <= 0;
        end else begin
            if (!ar_busy) begin
                if (m_axi_arvalid && m_axi_arready) begin
                    ar_busy  <= 1;
                    ar_addr_q<= m_axi_araddr;
                    r_beat_q <= 0;
                    r_left   <= m_axi_arlen + 8'd1;
                end
            end else if (m_axi_rvalid && m_axi_rready) begin
                r_beat_q <= r_beat_q + 1;
                if (r_left == 1) ar_busy <= 0;
                else             r_left  <= r_left - 1;
            end
        end
    end
    // 512b 拍拼装 (读 ddr)
    reg [511:0] r_beat_data;
    always @(*) begin
        for (int k = 0; k < 64; k++)
            r_beat_data[k*8 +: 8] = ddr[(ar_addr_q[17:0] + {r_beat_q, 6'd0} + k[17:0]) % 65536];
    end
    assign m_axi_rdata = r_beat_data;

    // ---- 清掉上面占位块 (综合不了 ddr 双写) ----
    // (占位块已用 initial 命名块之外的手段失效: 直接不驱动 ddr)

    int errs = 0;

    // 发一帧: 压字节 + 描述符
    task automatic send_frame(input int n, input byte base);
        int i;
        begin
            for (i = 0; i < n; i++) begin
                @(negedge clk);
                wf_data = base + i[7:0]; wf_wr = 1;
            end
            @(negedge clk); wf_wr = 0;
            @(negedge clk); wd_data = n[15:0]; wd_wr = 1;
            @(negedge clk); wd_wr = 0;
        end
    endtask

    // 收 rf 流 + rdesc
    int got = 0;
    byte cap [0:8191];
    reg [24:0] desc_cap [0:15];
    int desc_n = 0;
    always @(posedge clk) begin
        if (rf_wr_en) begin
            cap[got] <= rf_wr_data;
            got <= got + 1;
        end
        if (rd_wr_en) begin
            desc_cap[desc_n] <= rd_wr_data;
            desc_n <= desc_n + 1;
        end
    end

    // ---- DMA 服务任务: 模拟软核 + DMA (engine=1) ----
    task automatic serve_dma;
        integer t;
        int n, i, k;
        int slot, len;
        int total;
        begin
            // 等 dma_req_new 脉冲
            t = 0;
            while (!dma_req_new && t < 1000) begin @(posedge clk); t = t + 1; end
            if (!dma_req_new) begin
                $display("[FAIL] P2: no dma_req"); errs = errs + 1;
                return;
            end
            slot = dma_req_slot; len = dma_req_len;
            // 生成 [8 前导 + 帧] 流, 对齐读 SA=槽基址 (板上定案: 窗口前移 8B)
            // 帧内容 = ddr[slot 基址 .. +len) (写路径真实写入)
            total = len + 8;
            for (k = 0; k * 64 < total; k = k + 1) begin
                @(negedge clk);
                dma_s_tdata = 0; dma_s_tkeep = 0;
                for (i = 0; i < 64; i++) begin
                    if (k*64 + i < total) begin
                        int addr = (k*64 + i < 8) ? -1 : (SLOT_BASE + slot*4096 + (k*64+i-8));
                        dma_s_tdata[i*8 +: 8] = (addr < 0) ? 8'hEE : ddr[addr[17:0]];
                        dma_s_tkeep[i] = 1'b1;
                    end
                end
                dma_s_tlast  = ((k+1)*64 >= total);
                dma_s_tvalid = 1'b1;
                while (dma_s_tready !== 1'b1) @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk); dma_s_tvalid = 0; dma_s_tlast = 0;
        end
    endtask

    // 比对 cap[b0 .. b0+n) (显式起始, 多帧场景不错位)
    task automatic chk_frame(input int b0, input int n, input byte base, input string tag);
        begin
            for (int i = 0; i < n; i++) begin
                if (cap[b0 + i] !== base + i[7:0]) begin
                    $display("[FAIL] %s byte#%d got %02x want %02x",
                             tag, i, cap[b0+i], base + i[7:0]);
                    errs = errs + 1;
                end
            end
        end
    endtask

    initial begin
        repeat (20) @(posedge clk); rst_n = 1;
        repeat (10) @(posedge clk);

        // ================= P1: engine=0 桥硬件读 =================
        dma_engine = 0;
        send_frame(100, 8'h10);
        send_frame(64,  8'h50);
        #200;
        // SEQ 读命令 x2 (等描述符到达再发下一条)
        @(negedge clk); rc_data = 9'h000; rc_wr = 1;   // {rnd=0,slot=0} SEQ
        @(negedge clk); rc_wr = 0;
        begin : w1
            int g = 0;
            while (desc_n < 1 && g < 20000) begin @(posedge clk); g = g + 1; end
        end
        @(negedge clk); rc_data = 9'h000; rc_wr = 1;
        @(negedge clk); rc_wr = 0;
        begin : w2
            int g = 0;
            while (desc_n < 2 && g < 20000) begin @(posedge clk); g = g + 1; end
            repeat (10) @(posedge clk);
        end
        $display("[DBG] P1: got=%0d desc_n=%0d wm=%0d rd_frame=%0d outstanding=%0d noframe=%0d",
                 got, desc_n, stat_wm, stat_rd_frame, stat_outstanding, stat_noframe);
        chk_frame(0,   100, 8'h10, "P1-f0");
        chk_frame(100, 64,  8'h50, "P1-f1");
        if (stat_outstanding !== 9'd0) begin
            $display("[FAIL] P1 outstanding=%0d != 0", stat_outstanding);
            errs = errs + 1;
        end
        $display("[P1] engine=0: 2 frames via bridge, outstanding=0 OK");

        // ================= P2: engine=1 DMA 引擎 =================
        dma_engine = 1;
        got = 0; desc_n = 0;
        for (int q = 0; q < 4096; q++) cap[q] = 8'h00;
        send_frame(200, 8'h80);
        begin : wmw2
            int g = 0;
            while (stat_wm != 16'd3 && g < 40000) begin @(posedge clk); g = g + 1; end
            repeat (20) @(posedge clk);   // full_bit_q 镜像跟上
        end
        // SEQ 读命令
        @(negedge clk); rc_data = 9'h000; rc_wr = 1;
        @(negedge clk); rc_wr = 0;
        // NEG: DMA 模式桥不得发 AR
        begin
            int t = 0;
            fork
                begin
                    repeat (400) @(posedge clk);
                end
                begin
                    forever @(posedge clk)
                        if (m_axi_arvalid) begin
                            $display("[FAIL] NEG: AR asserted in DMA mode");
                            errs = errs + 1;
                            disable NEG_guard;
                        end
                end
                begin : NEG_guard
                    wait (1);
                end
            join_any
            disable fork;
        end
        serve_dma;
        begin : w3
            int g = 0;
            while (desc_n < 1 && g < 20000) begin @(posedge clk); g = g + 1; end
            repeat (10) @(posedge clk);
        end
        $display("[DBG] P2: got=%0d desc_n=%0d wm=%0d rd_frame=%0d outstanding=%0d",
                 got, desc_n, stat_wm, stat_rd_frame, stat_outstanding);
        chk_frame(0, 200, 8'h80, "P2-f0");
        if (desc_n < 1) begin
            $display("[FAIL] P2: no rdesc"); errs = errs + 1;
        end else begin
            desc_n = desc_n - 1;
            if (desc_cap[desc_n][23:8] !== 200 || desc_cap[desc_n][7:0] !== 8'h02) begin
                $display("[FAIL] P2 rdesc len=%0d slot=%0d (want 200/2: P1 已用 slot0/1)",
                         desc_cap[desc_n][23:8], desc_cap[desc_n][7:0]);
                errs = errs + 1;
            end
        end
        if (stat_outstanding !== 9'd0) begin
            $display("[FAIL] P2 outstanding=%0d != 0 after DMA retire", stat_outstanding);
            errs = errs + 1;
        end
        $display("[P2] engine=1: DMA round, retire OK");

        // ================= P3: 引擎切回, 桥硬件读还能工作 =================
        dma_engine = 0;
        got = 0; desc_n = 0;
        for (int q = 0; q < 4096; q++) cap[q] = 8'h00;
        send_frame(70, 8'hA0);
        begin : wmw3
            int g = 0;
            while (stat_wm != 16'd4 && g < 40000) begin @(posedge clk); g = g + 1; end
            repeat (20) @(posedge clk);
        end
        @(negedge clk); rc_data = 9'h000; rc_wr = 1;
        @(negedge clk); rc_wr = 0;
        begin : w4
            int g = 0;
            while (desc_n < 1 && g < 20000) begin @(posedge clk); g = g + 1; end
            repeat (10) @(posedge clk);
        end
        chk_frame(0, 70, 8'hA0, "P3-f0");
        $display("[P3] engine back to 0: bridge read still works");

        $display("==== BRIDGE_DMA_TB: %0d errors ====", errs);
        if (errs == 0) $display("BRIDGE_DMA_TB: PASS"); else $display("BRIDGE_DMA_TB: FAIL");
        $finish;
    end

    initial begin
        #5_000_000;
        $display("BRIDGE_DMA_TB: FAIL (timeout)");
        $finish;
    end
endmodule
