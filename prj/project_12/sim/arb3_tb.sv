//=============================================================================
// arb3_tb.sv — axi_arb_3to1 单元仿真（prj11 B3-1, 2026-10-12）
//-----------------------------------------------------------------------------
// 判据（照 W4 仲裁器的教训，坑账本 #23）:
//   T1 轮转公平   : 三主并发请求 -> 授权次数差 <= 1（不饿死任一方）
//   T2 写响应路由 : **三主 awid 全给同一值(4'h0)**，各发 K 笔写 ->
//                   每主收到的 B 笔数必须**恰好等于自己发出的 AW 笔数**
//                   （按 ID 路由的缺陷实现会把 B 全送给某一家 -> 本项必挂）
//   T3 读响应路由 : 同上，三主 arid 全同 -> 各主的 R 笔数 == 自己的 AR 笔数
//   T4 读写并行   : 读事务可在写事务进行中获授权（两方向独立）
// 负向对照: sim/axi_arb_3to1_defect.v（响应按 bid/rid 路由）必须让 T2/T3 FAIL。
//=============================================================================
`timescale 1ns / 1ps

module arb3_tb;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // ---- 三主侧信号 ----
    reg  [3:0]   awid [0:2];   reg [31:0] awaddr [0:2]; reg [7:0] awlen [0:2];
    reg  [2:0]   awsize[0:2];  reg [1:0]  awburst[0:2]; reg awlock [0:2];
    reg  [3:0]   awcache[0:2]; reg [2:0]  awprot[0:2];  reg [3:0] awqos[0:2];
    reg          awvalid[0:2]; wire       awready[0:2];
    reg  [511:0] wdata [0:2];  reg [63:0] wstrb [0:2];
    reg          wlast [0:2];  reg        wvalid[0:2];  wire wready[0:2];
    wire [1:0]   bresp [0:2];  wire       bvalid[0:2];  reg  bready[0:2];
    wire [3:0]   bid   [0:2];
    reg  [3:0]   arid [0:2];   reg [31:0] araddr[0:2];  reg [7:0] arlen[0:2];
    reg  [2:0]   arsize[0:2];  reg [1:0]  arburst[0:2]; reg arlock[0:2];
    reg  [3:0]   arcache[0:2]; reg [2:0]  arprot[0:2];  reg [3:0] arqos[0:2];
    reg          arvalid[0:2]; wire       arready[0:2];
    wire [511:0] rdata [0:2];  wire [1:0] rresp[0:2];
    wire         rlast [0:2];  wire       rvalid[0:2];  reg  rready[0:2];
    wire [3:0]   rid   [0:2];

    // ---- M 侧 ----
    wire [3:0]   m_awid;   wire [31:0] m_awaddr; wire [7:0] m_awlen;
    wire [2:0]   m_awsize; wire [1:0]  m_awburst;wire m_awlock;
    wire [3:0]   m_awcache;wire [2:0]  m_awprot; wire [3:0] m_awqos;
    wire         m_awvalid;reg          m_awready;
    wire [511:0] m_wdata;  wire [63:0] m_wstrb;  wire m_wlast, m_wvalid;
    reg          m_wready;
    reg  [1:0]   m_bresp;  reg          m_bvalid; wire m_bready; reg [3:0] m_bid;
    wire [3:0]   m_arid;   wire [31:0] m_araddr; wire [7:0] m_arlen;
    wire [2:0]   m_arsize; wire [1:0]  m_arburst;wire m_arlock;
    wire [3:0]   m_arcache;wire [2:0]  m_arprot; wire [3:0] m_arqos;
    wire         m_arvalid;reg          m_arready;
    reg  [511:0] m_rdata;  reg  [1:0]  m_rresp;  reg m_rlast, m_rvalid; wire m_rready;
    reg  [3:0]   m_rid;

    axi_arb_3to1 dut (
        .clk(clk), .rst_n(rst_n),
        .s00_axi_awid(awid[0]), .s00_axi_awaddr(awaddr[0]), .s00_axi_awlen(awlen[0]),
        .s00_axi_awsize(awsize[0]), .s00_axi_awburst(awburst[0]), .s00_axi_awlock(awlock[0]),
        .s00_axi_awcache(awcache[0]), .s00_axi_awprot(awprot[0]), .s00_axi_awqos(awqos[0]),
        .s00_axi_awvalid(awvalid[0]), .s00_axi_awready(awready[0]),
        .s00_axi_wdata(wdata[0]), .s00_axi_wstrb(wstrb[0]), .s00_axi_wlast(wlast[0]),
        .s00_axi_wvalid(wvalid[0]), .s00_axi_wready(wready[0]),
        .s00_axi_bresp(bresp[0]), .s00_axi_bvalid(bvalid[0]), .s00_axi_bready(bready[0]),
        .s00_axi_bid(bid[0]),
        .s00_axi_arid(arid[0]), .s00_axi_araddr(araddr[0]), .s00_axi_arlen(arlen[0]),
        .s00_axi_arsize(arsize[0]), .s00_axi_arburst(arburst[0]), .s00_axi_arlock(arlock[0]),
        .s00_axi_arcache(arcache[0]), .s00_axi_arprot(arprot[0]), .s00_axi_arqos(arqos[0]),
        .s00_axi_arvalid(arvalid[0]), .s00_axi_arready(arready[0]),
        .s00_axi_rdata(rdata[0]), .s00_axi_rresp(rresp[0]), .s00_axi_rlast(rlast[0]),
        .s00_axi_rvalid(rvalid[0]), .s00_axi_rready(rready[0]), .s00_axi_rid(rid[0]),
        .s01_axi_awid(awid[1]), .s01_axi_awaddr(awaddr[1]), .s01_axi_awlen(awlen[1]),
        .s01_axi_awsize(awsize[1]), .s01_axi_awburst(awburst[1]), .s01_axi_awlock(awlock[1]),
        .s01_axi_awcache(awcache[1]), .s01_axi_awprot(awprot[1]), .s01_axi_awqos(awqos[1]),
        .s01_axi_awvalid(awvalid[1]), .s01_axi_awready(awready[1]),
        .s01_axi_wdata(wdata[1]), .s01_axi_wstrb(wstrb[1]), .s01_axi_wlast(wlast[1]),
        .s01_axi_wvalid(wvalid[1]), .s01_axi_wready(wready[1]),
        .s01_axi_bresp(bresp[1]), .s01_axi_bvalid(bvalid[1]), .s01_axi_bready(bready[1]),
        .s01_axi_bid(bid[1]),
        .s01_axi_arid(arid[1]), .s01_axi_araddr(araddr[1]), .s01_axi_arlen(arlen[1]),
        .s01_axi_arsize(arsize[1]), .s01_axi_arburst(arburst[1]), .s01_axi_arlock(arlock[1]),
        .s01_axi_arcache(arcache[1]), .s01_axi_arprot(arprot[1]), .s01_axi_arqos(arqos[1]),
        .s01_axi_arvalid(arvalid[1]), .s01_axi_arready(arready[1]),
        .s01_axi_rdata(rdata[1]), .s01_axi_rresp(rresp[1]), .s01_axi_rlast(rlast[1]),
        .s01_axi_rvalid(rvalid[1]), .s01_axi_rready(rready[1]), .s01_axi_rid(rid[1]),
        .s02_axi_awid(awid[2]), .s02_axi_awaddr(awaddr[2]), .s02_axi_awlen(awlen[2]),
        .s02_axi_awsize(awsize[2]), .s02_axi_awburst(awburst[2]), .s02_axi_awlock(awlock[2]),
        .s02_axi_awcache(awcache[2]), .s02_axi_awprot(awprot[2]), .s02_axi_awqos(awqos[2]),
        .s02_axi_awvalid(awvalid[2]), .s02_axi_awready(awready[2]),
        .s02_axi_wdata(wdata[2]), .s02_axi_wstrb(wstrb[2]), .s02_axi_wlast(wlast[2]),
        .s02_axi_wvalid(wvalid[2]), .s02_axi_wready(wready[2]),
        .s02_axi_bresp(bresp[2]), .s02_axi_bvalid(bvalid[2]), .s02_axi_bready(bready[2]),
        .s02_axi_bid(bid[2]),
        .s02_axi_arid(arid[2]), .s02_axi_araddr(araddr[2]), .s02_axi_arlen(arlen[2]),
        .s02_axi_arsize(arsize[2]), .s02_axi_arburst(arburst[2]), .s02_axi_arlock(arlock[2]),
        .s02_axi_arcache(arcache[2]), .s02_axi_arprot(arprot[2]), .s02_axi_arqos(arqos[2]),
        .s02_axi_arvalid(arvalid[2]), .s02_axi_arready(arready[2]),
        .s02_axi_rdata(rdata[2]), .s02_axi_rresp(rresp[2]), .s02_axi_rlast(rlast[2]),
        .s02_axi_rvalid(rvalid[2]), .s02_axi_rready(rready[2]), .s02_axi_rid(rid[2]),
        .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst), .m_axi_awlock(m_awlock),
        .m_axi_awcache(m_awcache), .m_axi_awprot(m_awprot), .m_axi_awqos(m_awqos),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_bid(m_bid),
        .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst), .m_axi_arlock(m_arlock),
        .m_axi_arcache(m_arcache), .m_axi_arprot(m_arprot), .m_axi_arqos(m_arqos),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast),
        .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready), .m_axi_rid(m_rid));

    //=========================================================================
    // 简化 MIG 从机: awready/arready 常 1; 每接受一笔 AW 后延迟 bdly 拍回 B,
    //   **bid/rid 恒给 4'h0**(这正是坑 #23 的陷阱: 按 ID 路由必错)
    //=========================================================================
    // 单笔在飞模型: 仲裁器保证每方向同一时刻至多一个未完成事务
    reg [3:0] bdly_r = 0;
    reg [3:0] rdly_r = 0;

    initial begin
        m_awready = 1; m_wready = 1; m_arready = 1;
        m_bvalid = 0; m_bresp = 0; m_bid = 4'h0;
        m_rvalid = 0; m_rlast = 0; m_rresp = 0; m_rdata = 0; m_rid = 4'h0;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            bdly_r <= 0; m_bvalid <= 0;
            rdly_r <= 0; m_rvalid <= 0; m_rlast <= 0;
        end else begin
            // ---- 写响应: AW 握手 -> 3 拍后 B(bid 恒 4'h0 = 陷阱) ----
            if (m_bvalid && m_bready) m_bvalid <= 0;
            if (m_awvalid && m_awready && bdly_r == 0 && !m_bvalid) bdly_r <= 3;
            else if (bdly_r > 0) begin
                bdly_r <= bdly_r - 1;
                if (bdly_r == 1) m_bvalid <= 1;
            end
            // ---- 读响应: AR 握手 -> 3 拍后单拍 R ----
            if (m_rvalid && m_rready) begin m_rvalid <= 0; m_rlast <= 0; end
            if (m_arvalid && m_arready && rdly_r == 0 && !m_rvalid) rdly_r <= 3;
            else if (rdly_r > 0) begin
                rdly_r <= rdly_r - 1;
                if (rdly_r == 1) begin m_rvalid <= 1; m_rlast <= 1; end
            end
        end
    end

    //=========================================================================
    // 三主激励 + 计数
    //=========================================================================
    integer aw_cnt [0:2];    // 各主发出的 AW 笔数
    integer b_cnt  [0:2];    // 各主收到的 B 笔数
    integer ar_cnt [0:2];
    integer r_cnt  [0:2];
    integer errs = 0;
    integer i, k;

    always @(posedge clk) begin
        for (k = 0; k < 3; k = k + 1) begin
            if (awready[k] && awvalid[k]) aw_cnt[k] <= aw_cnt[k] + 1;
            if (bvalid[k] && bready[k])   b_cnt[k]  <= b_cnt[k]  + 1;
            if (arready[k] && arvalid[k]) ar_cnt[k] <= ar_cnt[k] + 1;
            if (rvalid[k] && rready[k])   r_cnt[k]  <= r_cnt[k]  + 1;
        end
    end

    // 单笔写事务(单拍数据) / 单笔读事务(单拍数据), 带随机间隔
    task automatic one_wr(input integer m);
        begin
            wstrb[m] = {64{1'b1}}; wdata[m] = {512{1'b0}};
            awvalid[m] = 1;                       // AR 阶段: 先 AW 握手
            while (!awready[m]) @(posedge clk);
            @(posedge clk); awvalid[m] = 0;
            wvalid[m] = 1; wlast[m] = 1;          // W 阶段(wready 仅授权后有)
            while (!wready[m]) @(posedge clk);
            @(posedge clk); wvalid[m] = 0; wlast[m] = 0;
            bready[m] = 1;
            while (!bvalid[m]) @(posedge clk);
            @(posedge clk); bready[m] = 0;
            repeat (i % 4) @(posedge clk);
        end
    endtask

    task automatic one_rd(input integer m);
        begin
            arvalid[m] = 1; arlen[m] = 0;
            while (!arready[m]) @(posedge clk);
            @(posedge clk); arvalid[m] = 0;
            rready[m] = 1;
            while (!rvalid[m]) @(posedge clk);
            @(posedge clk); rready[m] = 0;
            repeat (i % 3) @(posedge clk);
        end
    endtask

    initial begin
        for (k = 0; k < 3; k = k + 1) begin
            aw_cnt[k] = 0; b_cnt[k] = 0; ar_cnt[k] = 0; r_cnt[k] = 0;
            awid[k] = 4'h0;   // ★ 三主同 ID —— 路由必须靠 grant 而非 ID
            arid[k] = 4'h0;
            awaddr[k] = 32'h0010_0000 + k*32'h0010_0000;
            araddr[k] = 32'h0010_0000 + k*32'h0010_0000;
            awlen[k] = 0; arlen[k] = 0; awsize[k] = 3'd6; arsize[k] = 3'd6;
            awburst[k] = 2'd1; arburst[k] = 2'd1; awlock[k] = 0; arlock[k] = 0;
            awcache[k] = 0; arcache[k] = 0; awprot[k] = 0; arprot[k] = 0;
            awqos[k] = 0; arqos[k] = 0;
            awvalid[k] = 0; wvalid[k] = 0; wlast[k] = 0; bready[k] = 0;
            arvalid[k] = 0; rready[k] = 0;
            wdata[k] = 0; wstrb[k] = 0;
        end
        repeat (10) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);

        // ---- T1/T2: 三主并发写 K=12 笔 —— 轮转公平 + 响应各归各主 ----
        for (i = 0; i < 12; i = i + 1) begin
            fork
                one_wr(0);
                one_wr(1);
                one_wr(2);
            join
        end
        $display("[T1] 三主并发写 12 笔: 授权 S00=%0d S01=%0d S02=%0d (max-min<=1)",
                 aw_cnt[0], aw_cnt[1], aw_cnt[2]);
        if (aw_cnt[0] != 12 || aw_cnt[1] != 12 || aw_cnt[2] != 12) begin
            $display("  [FAIL] 有主被饿死 (期望各 12)"); errs = errs + 1;
        end
        $display("[T2] 写响应路由(三主 awid 全同): 收到 B  S00=%0d S01=%0d S02=%0d",
                 b_cnt[0], b_cnt[1], b_cnt[2]);
        for (k = 0; k < 3; k = k + 1) begin
            if (b_cnt[k] != aw_cnt[k]) begin
                $display("  [FAIL] S0%0d B=%0d != AW=%0d (响应路由错)", k, b_cnt[k], aw_cnt[k]);
                errs = errs + 1;
            end
        end

        // ---- T3/T4: 三主并发读 —— 同上，且与写并行 ----
        for (i = 0; i < 10; i = i + 1) begin
            fork
                one_rd(0);
                one_rd(1);
                one_rd(2);
            join
        end
        $display("[T3] 读响应路由(三主 arid 全同): 收到 R  S00=%0d S01=%0d S02=%0d",
                 r_cnt[0], r_cnt[1], r_cnt[2]);
        for (k = 0; k < 3; k = k + 1) begin
            if (r_cnt[k] != ar_cnt[k]) begin
                $display("  [FAIL] S0%0d R=%0d != AR=%0d (响应路由错)", k, r_cnt[k], ar_cnt[k]);
                errs = errs + 1;
            end
        end

        $display("==== ARB3_TB: %0d errors ====", errs);
        if (errs == 0) $display("ARB3_TB: PASS"); else $display("ARB3_TB: FAIL");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("ARB3_TB: FAIL (timeout)");
        $finish;
    end
endmodule
