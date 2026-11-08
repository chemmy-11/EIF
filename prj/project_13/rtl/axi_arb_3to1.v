//=============================================================================
// axi_arb_3to1.v — 三主一从 AXI4 仲裁器（prj11 B3-1，ui_clk 同域，纯 RTL）
//-----------------------------------------------------------------------------
// 由来: B3-1 要把桥②(EGRESS 读)换成 AXI DMA MM2S，而 MIG 只有**一个** AXI4
//   从机口 —— DMA 的 M_AXI 必须与桥①(S00)、桥②(S01) 共享该口，故本件在
//   axi_arb_2to1 基础上扩到 3 主。2to1 原件保持不动（W4 联合 TB 继续测它）。
//
// 纪律(照抄 2to1, 含 W4 修复教训):
//   - **响应路由按内部 grant 锁存器，绝不按 bid/rid**（坑 #23 的根因: 三主若
//     ID 相同或相同来源，按 ID 路由会把响应送错主 → 板上死锁）
//   - 事务级轮转: AW/AR 各自独立授权并锁定到事务结束(B / RLAST)
//   - 读写两方向并行授权（MIG 支持读写并发）
//   - 每主任意时刻至多一个未完成写事务 + 一个未完成读事务（上游保证）
//
// S02 = 预留给 AXI DMA MM2S（B3-1 接入前悬空: awvalid/arvalid 接 0，
//   wlast/wdata/rready 相应悬空 —— 见顶层）。
//=============================================================================
`timescale 1ns / 1ps

module axi_arb_3to1 (
    input  wire         clk,
    input  wire         rst_n,

    // ================= S00 (桥① / INGRESS 写) =================
    input  wire [3:0]   s00_axi_awid,   input  wire [31:0] s00_axi_awaddr,
    input  wire [7:0]   s00_axi_awlen,  input  wire [2:0]  s00_axi_awsize,
    input  wire [1:0]   s00_axi_awburst,input  wire        s00_axi_awlock,
    input  wire [3:0]   s00_axi_awcache,input  wire [2:0]  s00_axi_awprot,
    input  wire [3:0]   s00_axi_awqos,  input  wire        s00_axi_awvalid,
    output wire         s00_axi_awready,
    input  wire [511:0] s00_axi_wdata,  input  wire [63:0] s00_axi_wstrb,
    input  wire         s00_axi_wlast,  input  wire        s00_axi_wvalid,
    output wire         s00_axi_wready,
    output wire [1:0]   s00_axi_bresp,  output wire        s00_axi_bvalid,
    input  wire         s00_axi_bready, output wire [3:0]  s00_axi_bid,
    input  wire [3:0]   s00_axi_arid,   input  wire [31:0] s00_axi_araddr,
    input  wire [7:0]   s00_axi_arlen,  input  wire [2:0]  s00_axi_arsize,
    input  wire [1:0]   s00_axi_arburst,input  wire        s00_axi_arlock,
    input  wire [3:0]   s00_axi_arcache,input  wire [2:0]  s00_axi_arprot,
    input  wire [3:0]   s00_axi_arqos,  input  wire        s00_axi_arvalid,
    output wire         s00_axi_arready,
    output wire [511:0] s00_axi_rdata,  output wire [1:0]  s00_axi_rresp,
    output wire         s00_axi_rlast,  output wire        s00_axi_rvalid,
    input  wire         s00_axi_rready, output wire [3:0]  s00_axi_rid,

    // ================= S01 (桥② / EGRESS 读) =================
    input  wire [3:0]   s01_axi_awid,   input  wire [31:0] s01_axi_awaddr,
    input  wire [7:0]   s01_axi_awlen,  input  wire [2:0]  s01_axi_awsize,
    input  wire [1:0]   s01_axi_awburst,input  wire        s01_axi_awlock,
    input  wire [3:0]   s01_axi_awcache,input  wire [2:0]  s01_axi_awprot,
    input  wire [3:0]   s01_axi_awqos,  input  wire        s01_axi_awvalid,
    output wire         s01_axi_awready,
    input  wire [511:0] s01_axi_wdata,  input  wire [63:0] s01_axi_wstrb,
    input  wire         s01_axi_wlast,  input  wire        s01_axi_wvalid,
    output wire         s01_axi_wready,
    output wire [1:0]   s01_axi_bresp,  output wire        s01_axi_bvalid,
    input  wire         s01_axi_bready, output wire [3:0]  s01_axi_bid,
    input  wire [3:0]   s01_axi_arid,   input  wire [31:0] s01_axi_araddr,
    input  wire [7:0]   s01_axi_arlen,  input  wire [2:0]  s01_axi_arsize,
    input  wire [1:0]   s01_axi_arburst,input  wire        s01_axi_arlock,
    input  wire [3:0]   s01_axi_arcache,input  wire [2:0]  s01_axi_arprot,
    input  wire [3:0]   s01_axi_arqos,  input  wire        s01_axi_arvalid,
    output wire         s01_axi_arready,
    output wire [511:0] s01_axi_rdata,  output wire [1:0]  s01_axi_rresp,
    output wire         s01_axi_rlast,  output wire        s01_axi_rvalid,
    input  wire         s01_axi_rready, output wire [3:0]  s01_axi_rid,

    // ================= S02 (AXI DMA MM2S, B3-1) =================
    input  wire [3:0]   s02_axi_awid,   input  wire [31:0] s02_axi_awaddr,
    input  wire [7:0]   s02_axi_awlen,  input  wire [2:0]  s02_axi_awsize,
    input  wire [1:0]   s02_axi_awburst,input  wire        s02_axi_awlock,
    input  wire [3:0]   s02_axi_awcache,input  wire [2:0]  s02_axi_awprot,
    input  wire [3:0]   s02_axi_awqos,  input  wire        s02_axi_awvalid,
    output wire         s02_axi_awready,
    input  wire [511:0] s02_axi_wdata,  input  wire [63:0] s02_axi_wstrb,
    input  wire         s02_axi_wlast,  input  wire        s02_axi_wvalid,
    output wire         s02_axi_wready,
    output wire [1:0]   s02_axi_bresp,  output wire        s02_axi_bvalid,
    input  wire         s02_axi_bready, output wire [3:0]  s02_axi_bid,
    input  wire [3:0]   s02_axi_arid,   input  wire [31:0] s02_axi_araddr,
    input  wire [7:0]   s02_axi_arlen,  input  wire [2:0]  s02_axi_arsize,
    input  wire [1:0]   s02_axi_arburst,input  wire        s02_axi_arlock,
    input  wire [3:0]   s02_axi_arcache,input  wire [2:0]  s02_axi_arprot,
    input  wire [3:0]   s02_axi_arqos,  input  wire        s02_axi_arvalid,
    output wire         s02_axi_arready,
    output wire [511:0] s02_axi_rdata,  output wire [1:0]  s02_axi_rresp,
    output wire         s02_axi_rlast,  output wire        s02_axi_rvalid,
    input  wire         s02_axi_rready, output wire [3:0]  s02_axi_rid,

    // ================= M: MIG =================
    output wire [3:0]   m_axi_awid,     output wire [31:0] m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,    output wire [2:0]  m_axi_awsize,
    output wire [1:0]   m_axi_awburst,  output wire        m_axi_awlock,
    output wire [3:0]   m_axi_awcache,  output wire [2:0]  m_axi_awprot,
    output wire [3:0]   m_axi_awqos,    output wire        m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [511:0] m_axi_wdata,    output wire [63:0] m_axi_wstrb,
    output wire         m_axi_wlast,    output wire        m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [1:0]   m_axi_bresp,    input  wire        m_axi_bvalid,
    output wire         m_axi_bready,   input  wire [3:0]  m_axi_bid,
    output wire [3:0]   m_axi_arid,     output wire [31:0] m_axi_araddr,
    output wire [7:0]   m_axi_arlen,    output wire [2:0]  m_axi_arsize,
    output wire [1:0]   m_axi_arburst,  output wire        m_axi_arlock,
    output wire [3:0]   m_axi_arcache,  output wire [2:0]  m_axi_arprot,
    output wire [3:0]   m_axi_arqos,    output wire        m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [511:0] m_axi_rdata,    input  wire [1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,    input  wire        m_axi_rvalid,
    output wire         m_axi_rready,   input  wire [3:0]  m_axi_rid
);

    //=========================================================================
    // 写方向
    //=========================================================================
    reg [1:0] wgrant;   // 0=S00 1=S01 2=S02
    reg [1:0] wlast;    // 上次授权（轮转起点）
    reg       wbusy;
    wire [2:0] wreq = {s02_axi_awvalid, s01_axi_awvalid, s00_axi_awvalid};
    wire       wany = |wreq;

    // 轮转: 从 wlast 的下一主开始找第一个请求者
    reg [1:0] wpick;
    always @* begin
        case (wlast)
            2'd0: wpick = wreq[1] ? 2'd1 : (wreq[2] ? 2'd2 : 2'd0);
            2'd1: wpick = wreq[2] ? 2'd2 : (wreq[0] ? 2'd0 : 2'd1);
            default: wpick = wreq[0] ? 2'd0 : (wreq[1] ? 2'd1 : 2'd2);
        endcase
    end
    wire [1:0] wsel = wbusy ? wgrant : wpick;

    assign s00_axi_awready = ~wbusy & s00_axi_awvalid & (wsel == 2'd0) & m_axi_awready;
    assign s01_axi_awready = ~wbusy & s01_axi_awvalid & (wsel == 2'd1) & m_axi_awready;
    assign s02_axi_awready = ~wbusy & s02_axi_awvalid & (wsel == 2'd2) & m_axi_awready;

    assign m_axi_awvalid = ~wbusy & (wsel == 2'd0 ? s00_axi_awvalid :
                                     wsel == 2'd1 ? s01_axi_awvalid : s02_axi_awvalid);
    assign m_axi_awid    = wsel == 2'd0 ? s00_axi_awid :
                           wsel == 2'd1 ? s01_axi_awid : s02_axi_awid;
    assign m_axi_awaddr  = wsel == 2'd0 ? s00_axi_awaddr :
                           wsel == 2'd1 ? s01_axi_awaddr : s02_axi_awaddr;
    assign m_axi_awlen   = wsel == 2'd0 ? s00_axi_awlen :
                           wsel == 2'd1 ? s01_axi_awlen : s02_axi_awlen;
    assign m_axi_awsize  = wsel == 2'd0 ? s00_axi_awsize :
                           wsel == 2'd1 ? s01_axi_awsize : s02_axi_awsize;
    assign m_axi_awburst = wsel == 2'd0 ? s00_axi_awburst :
                           wsel == 2'd1 ? s01_axi_awburst : s02_axi_awburst;
    assign m_axi_awlock  = wsel == 2'd0 ? s00_axi_awlock :
                           wsel == 2'd1 ? s01_axi_awlock : s02_axi_awlock;
    assign m_axi_awcache = wsel == 2'd0 ? s00_axi_awcache :
                           wsel == 2'd1 ? s01_axi_awcache : s02_axi_awcache;
    assign m_axi_awprot  = wsel == 2'd0 ? s00_axi_awprot :
                           wsel == 2'd1 ? s01_axi_awprot : s02_axi_awprot;
    assign m_axi_awqos   = wsel == 2'd0 ? s00_axi_awqos :
                           wsel == 2'd1 ? s01_axi_awqos : s02_axi_awqos;

    assign m_axi_wvalid = wgrant == 2'd0 ? s00_axi_wvalid :
                          wgrant == 2'd1 ? s01_axi_wvalid : s02_axi_wvalid;
    assign m_axi_wdata  = wgrant == 2'd0 ? s00_axi_wdata :
                          wgrant == 2'd1 ? s01_axi_wdata : s02_axi_wdata;
    assign m_axi_wstrb  = wgrant == 2'd0 ? s00_axi_wstrb :
                          wgrant == 2'd1 ? s01_axi_wstrb : s02_axi_wstrb;
    assign m_axi_wlast  = wgrant == 2'd0 ? s00_axi_wlast :
                          wgrant == 2'd1 ? s01_axi_wlast : s02_axi_wlast;
    assign s00_axi_wready = (wgrant == 2'd0) & wbusy & m_axi_wready;
    assign s01_axi_wready = (wgrant == 2'd1) & wbusy & m_axi_wready;
    assign s02_axi_wready = (wgrant == 2'd2) & wbusy & m_axi_wready;

    // 写响应: 按 grant 锁存路由（坑 #23: 不依赖 bid）
    wire b_to_s01 = wbusy & (wgrant == 2'd1);
    wire b_to_s02 = wbusy & (wgrant == 2'd2);
    wire b_to_s00 = wbusy & (wgrant == 2'd0);
    assign s00_axi_bvalid = m_axi_bvalid & b_to_s00;
    assign s01_axi_bvalid = m_axi_bvalid & b_to_s01;
    assign s02_axi_bvalid = m_axi_bvalid & b_to_s02;
    assign s00_axi_bresp = m_axi_bresp;  assign s00_axi_bid = m_axi_bid;
    assign s01_axi_bresp = m_axi_bresp;  assign s01_axi_bid = m_axi_bid;
    assign s02_axi_bresp = m_axi_bresp;  assign s02_axi_bid = m_axi_bid;
    assign m_axi_bready  = b_to_s00 ? s00_axi_bready :
                           b_to_s01 ? s01_axi_bready : s02_axi_bready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wgrant <= 2'd0; wbusy <= 1'b0; wlast <= 2'd2;   // 复位后 S00 先
        end else begin
            if (!wbusy) begin
                if (m_axi_awvalid && m_axi_awready) begin
                    wbusy  <= 1'b1;
                    wgrant <= wsel;
                    wlast  <= wsel;
                end
            end else if (m_axi_bvalid && m_axi_bready) begin
                wbusy <= 1'b0;
            end
        end
    end

    //=========================================================================
    // 读方向
    //=========================================================================
    reg [1:0] rgrant;
    reg [1:0] rlast;
    reg       rbusy;
    wire [2:0] rreq = {s02_axi_arvalid, s01_axi_arvalid, s00_axi_arvalid};

    reg [1:0] rpick;
    always @* begin
        case (rlast)
            2'd0: rpick = rreq[1] ? 2'd1 : (rreq[2] ? 2'd2 : 2'd0);
            2'd1: rpick = rreq[2] ? 2'd2 : (rreq[0] ? 2'd0 : 2'd1);
            default: rpick = rreq[0] ? 2'd0 : (rreq[1] ? 2'd1 : 2'd2);
        endcase
    end
    wire [1:0] rsel = rbusy ? rgrant : rpick;

    assign s00_axi_arready = ~rbusy & s00_axi_arvalid & (rsel == 2'd0) & m_axi_arready;
    assign s01_axi_arready = ~rbusy & s01_axi_arvalid & (rsel == 2'd1) & m_axi_arready;
    assign s02_axi_arready = ~rbusy & s02_axi_arvalid & (rsel == 2'd2) & m_axi_arready;

    assign m_axi_arvalid = ~rbusy & (rsel == 2'd0 ? s00_axi_arvalid :
                                     rsel == 2'd1 ? s01_axi_arvalid : s02_axi_arvalid);
    assign m_axi_arid    = rsel == 2'd0 ? s00_axi_arid :
                           rsel == 2'd1 ? s01_axi_arid : s02_axi_arid;
    assign m_axi_araddr  = rsel == 2'd0 ? s00_axi_araddr :
                           rsel == 2'd1 ? s01_axi_araddr : s02_axi_araddr;
    assign m_axi_arlen   = rsel == 2'd0 ? s00_axi_arlen :
                           rsel == 2'd1 ? s01_axi_arlen : s02_axi_arlen;
    assign m_axi_arsize  = rsel == 2'd0 ? s00_axi_arsize :
                           rsel == 2'd1 ? s01_axi_arsize : s02_axi_arsize;
    assign m_axi_arburst = rsel == 2'd0 ? s00_axi_arburst :
                           rsel == 2'd1 ? s01_axi_arburst : s02_axi_arburst;
    assign m_axi_arlock  = rsel == 2'd0 ? s00_axi_arlock :
                           rsel == 2'd1 ? s01_axi_arlock : s02_axi_arlock;
    assign m_axi_arcache = rsel == 2'd0 ? s00_axi_arcache :
                           rsel == 2'd1 ? s01_axi_arcache : s02_axi_arcache;
    assign m_axi_arprot  = rsel == 2'd0 ? s00_axi_arprot :
                           rsel == 2'd1 ? s01_axi_arprot : s02_axi_arprot;
    assign m_axi_arqos   = rsel == 2'd0 ? s00_axi_arqos :
                           rsel == 2'd1 ? s01_axi_arqos : s02_axi_arqos;

    wire r_to_s00 = rbusy & (rgrant == 2'd0);
    wire r_to_s01 = rbusy & (rgrant == 2'd1);
    wire r_to_s02 = rbusy & (rgrant == 2'd2);
    assign s00_axi_rvalid = m_axi_rvalid & r_to_s00;
    assign s01_axi_rvalid = m_axi_rvalid & r_to_s01;
    assign s02_axi_rvalid = m_axi_rvalid & r_to_s02;
    assign s00_axi_rdata = m_axi_rdata;  assign s00_axi_rresp = m_axi_rresp;
    assign s00_axi_rlast = m_axi_rlast;  assign s00_axi_rid   = m_axi_rid;
    assign s01_axi_rdata = m_axi_rdata;  assign s01_axi_rresp = m_axi_rresp;
    assign s01_axi_rlast = m_axi_rlast;  assign s01_axi_rid   = m_axi_rid;
    assign s02_axi_rdata = m_axi_rdata;  assign s02_axi_rresp = m_axi_rresp;
    assign s02_axi_rlast = m_axi_rlast;  assign s02_axi_rid   = m_axi_rid;
    assign m_axi_rready  = r_to_s00 ? s00_axi_rready :
                           r_to_s01 ? s01_axi_rready : s02_axi_rready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rgrant <= 2'd0; rbusy <= 1'b0; rlast <= 2'd2;
        end else begin
            if (!rbusy) begin
                if (m_axi_arvalid && m_axi_arready) begin
                    rbusy  <= 1'b1;
                    rgrant <= rsel;
                    rlast  <= rsel;
                end
            end else if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
                rbusy <= 1'b0;
            end
        end
    end

endmodule
