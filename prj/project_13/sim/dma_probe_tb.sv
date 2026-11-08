//=============================================================================
// dma_probe_tb.sv -- prj11 B3-1b: axi_dma MM2S 真实字节映射裁决台 (xsim)
//-----------------------------------------------------------------------------
// 背景: 板场次实测 DMA 流首 4 字节 = 内存[SA-50..SA-47] (三帧独立验证)。
//   候选模型在 j=0..49 一致, 仅每拍尾 14 字节分歧; 板上 sink 只见首拍低 32
//   位 -> 无法区分。本台实例化同配置 IP 的 sim 网表, 打印:
//     1) IP 实际发出的 AR (addr/len/size)   <- 地址是否被改写
//     2) M_AXIS 首拍完整 64 字节             <- 拍内是否旋转
//   判据(第一拍):
//     首拍 == mem[SA..SA+63]        -> 线性 (板上差异在别处)
//     首拍 == mem[SA-50..SA+13]     -> 线性 -50 (SA 预补偿即可)
//     首拍 == rot14(mem[SA-64..SA-1])-> 拍内旋转 (需去旋转)
//
// 内存从机只实现读通道 (AR/R), 数据用地址函数直接生成 (无需 RAM 数组):
//     byte(addr) = addr & 0xFF      (地址指纹, 便于肉眼比对)
//   AXI 语义: AR 落在块内时从机返回"含该地址的整块", 主设备弃前导字节。
//   本台按"块对齐地址 = AR addr 向下取 64B"返回, 与 MIG 行为一致。
//=============================================================================
`timescale 1ns/1ps

module dma_probe_tb;

    // ---------------- clocks ----------------
    reg lite_clk = 1'b0;
    reg mm2s_clk = 1'b0;
    always #5.0     lite_clk = ~lite_clk;      // 100 MHz
    always #1.6667  mm2s_clk = ~mm2s_clk;      // 300 MHz

    reg rstn = 1'b0;

    // ---------------- AXI4-Lite master ----------------
    reg  [9:0]  s_awaddr  = 10'd0;
    reg         s_awvalid = 1'b0;
    wire        s_awready;
    reg  [31:0] s_wdata   = 32'd0;
    reg         s_wvalid  = 1'b0;
    wire        s_wready;
    wire [1:0]  s_bresp;
    wire        s_bvalid;
    reg         s_bready  = 1'b0;
    reg  [9:0]  s_araddr  = 10'd0;
    reg         s_arvalid = 1'b0;
    wire        s_arready;
    wire [31:0] s_rdata;
    wire [1:0]  s_rresp;
    wire        s_rvalid;
    reg         s_rready  = 1'b0;

    // ---------------- M_AXI_MM2S (DMA is master) ----------------
    wire [31:0]  m_araddr;
    wire [7:0]   m_arlen;
    wire [2:0]   m_arsize;
    wire [1:0]   m_arburst;
    wire [2:0]   m_arprot;
    wire [3:0]   m_arcache;
    wire         m_arvalid;
    reg          m_arready = 1'b0;
    reg  [511:0] m_rdata   = 512'd0;
    reg  [1:0]   m_rresp   = 2'b00;
    reg          m_rlast   = 1'b0;
    reg          m_rvalid  = 1'b0;
    wire         m_rready;

    // ---------------- M_AXIS_MM2S ----------------
    wire [511:0] axis_tdata;
    wire [63:0]  axis_tkeep;
    wire         axis_tvalid;
    wire         axis_tlast;
    reg          axis_tready = 1'b1;

    wire         mm2s_prmry_reset_out_n;
    wire         mm2s_introut;
    wire [31:0]  axi_dma_tstvec;

    // ---------------- DUT ----------------
    mb_ctrl_axi_dma_0_0 dut (
        .s_axi_lite_aclk  (lite_clk),
        .m_axi_mm2s_aclk  (mm2s_clk),
        .axi_resetn       (rstn),
        .s_axi_lite_awvalid(s_awvalid), .s_axi_lite_awready(s_awready),
        .s_axi_lite_awaddr (s_awaddr),
        .s_axi_lite_wvalid (s_wvalid),  .s_axi_lite_wready (s_wready),
        .s_axi_lite_wdata  (s_wdata),
        .s_axi_lite_bresp  (s_bresp),   .s_axi_lite_bvalid (s_bvalid),
        .s_axi_lite_bready (s_bready),
        .s_axi_lite_arvalid(s_arvalid), .s_axi_lite_arready(s_arready),
        .s_axi_lite_araddr (s_araddr),
        .s_axi_lite_rvalid (s_rvalid),  .s_axi_lite_rready (s_rready),
        .s_axi_lite_rdata  (s_rdata),   .s_axi_lite_rresp  (s_rresp),
        .m_axi_mm2s_araddr (m_araddr),
        .m_axi_mm2s_arlen  (m_arlen),
        .m_axi_mm2s_arsize (m_arsize),
        .m_axi_mm2s_arburst(m_arburst),
        .m_axi_mm2s_arprot (m_arprot),
        .m_axi_mm2s_arcache(m_arcache),
        .m_axi_mm2s_arvalid(m_arvalid),
        .m_axi_mm2s_arready(m_arready),
        .m_axi_mm2s_rdata  (m_rdata),
        .m_axi_mm2s_rresp  (m_rresp),
        .m_axi_mm2s_rlast  (m_rlast),
        .m_axi_mm2s_rvalid (m_rvalid),
        .m_axi_mm2s_rready (m_rready),
        .mm2s_prmry_reset_out_n(mm2s_prmry_reset_out_n),
        .m_axis_mm2s_tdata (axis_tdata),
        .m_axis_mm2s_tkeep (axis_tkeep),
        .m_axis_mm2s_tvalid(axis_tvalid),
        .m_axis_mm2s_tready(axis_tready),
        .m_axis_mm2s_tlast (axis_tlast),
        .mm2s_introut      (mm2s_introut),
        .axi_dma_tstvec    (axi_dma_tstvec)
    );

    //=========================================================================
    // AXI4 read slave (读通道 only)
    //=========================================================================
    localparam RD_IDLE = 2'd0, RD_BEAT = 2'd1, RD_END = 2'd2;
    reg [1:0]  rd_st = RD_IDLE;
    reg [31:0] araddr_q;
    reg [7:0]  arlen_q, beat_q;
    integer    kk;

    always @(posedge mm2s_clk or negedge rstn) begin
        if (!rstn) begin
            m_arready <= 1'b1; m_rvalid <= 1'b0; m_rlast <= 1'b0;
            m_rdata <= 512'd0; rd_st <= RD_IDLE;
            araddr_q <= 32'd0; arlen_q <= 8'd0; beat_q <= 8'd0;
        end else begin
            case (rd_st)
            RD_IDLE: begin
                m_arready <= 1'b1; m_rvalid <= 1'b0; m_rlast <= 1'b0;
                if (m_arvalid && m_arready) begin
                    araddr_q <= m_araddr;
                    arlen_q  <= m_arlen;
                    beat_q   <= 8'd0;
                    m_arready<= 1'b0;
                    rd_st    <= RD_BEAT;
                    $display("[%0t] AR addr=%08x len=%0d size=%0d burst=%0d",
                             $time, m_araddr, m_arlen, m_arsize, m_arburst);
                end
            end
            RD_BEAT: begin
                for (kk = 0; kk < 64; kk = kk + 1)
                    m_rdata[kk*8 +: 8] <= ((araddr_q & ~32'h3F) + beat_q*32'd64 + kk) & 32'hFF;
                m_rvalid <= 1'b1;
                m_rlast  <= (beat_q == arlen_q);
                rd_st    <= RD_END;
            end
            RD_END: begin
                if (m_rvalid && m_rready) begin
                    m_rvalid <= 1'b0; m_rlast <= 1'b0;
                    if (beat_q == arlen_q) rd_st <= RD_IDLE;
                    else begin beat_q <= beat_q + 8'd1; rd_st <= RD_BEAT; end
                end
            end
            default: rd_st <= RD_IDLE;
            endcase
        end
    end

    //=========================================================================
    // M_AXIS 抓取 (打印首拍 64 字节 + 后续拍前 8 字节)
    //=========================================================================
    integer nb;
    always @(posedge mm2s_clk) begin
        if (rstn && axis_tvalid && axis_tready) begin
            if (nb == 0) begin
                $write("[%0t] AXIS beat0 tk=%016x tl=%b data=", $time, axis_tkeep, axis_tlast);
                for (kk = 0; kk < 64; kk = kk + 1)
                    $write("%02x", axis_tdata[kk*8 +: 8]);
                $write("\n");
            end else begin
                $display("[%0t] AXIS beat%0d tk=%016x tl=%b b0..7=%02x %02x %02x %02x %02x %02x %02x %02x",
                         $time, nb, axis_tkeep, axis_tlast,
                         axis_tdata[7:0],  axis_tdata[15:8],  axis_tdata[23:16], axis_tdata[31:24],
                         axis_tdata[39:32],axis_tdata[47:40],axis_tdata[55:48],axis_tdata[63:56]);
            end
            nb <= nb + 1;
        end
    end

    //=========================================================================
    // AXI4-Lite 任务
    //=========================================================================
    task lite_write(input [9:0] a, input [31:0] d);
        begin
            @(posedge lite_clk);
            s_awaddr <= a; s_awvalid <= 1'b1;
            s_wdata  <= d; s_wvalid  <= 1'b1; s_bready <= 1'b1;
            while (!(s_awready && s_wready)) @(posedge lite_clk);
            s_awvalid <= 1'b0; s_wvalid <= 1'b0;
            while (!s_bvalid) @(posedge lite_clk);
            @(posedge lite_clk);
            s_bready <= 1'b0;
        end
    endtask

    task lite_read(input [9:0] a, output [31:0] d);
        begin
            @(posedge lite_clk);
            s_araddr <= a; s_arvalid <= 1'b1; s_rready <= 1'b1;
            while (!s_arready) @(posedge lite_clk);
            @(posedge lite_clk);
            s_arvalid <= 1'b0;
            while (!s_rvalid) @(posedge lite_clk);
            d = s_rdata;
            @(posedge lite_clk);
            s_rready <= 1'b0;
        end
    endtask

    //=========================================================================
    // 一次 MM2S 传输
    //=========================================================================
    reg [31:0] sr_q;
    task dma_run(input [31:0] sa, input [31:0] len);
        integer guard;
        begin
            nb = 0;
            $display("---- MM2S: SA=%08x LEN=%0d ----", sa, len);
            lite_write(10'h000, 32'h0000_0004);          // reset
            lite_read (10'h004, sr_q);
            lite_write(10'h000, 32'h0000_0001);          // RS
            lite_write(10'h018, sa);                     // MM2S_SA
            lite_write(10'h028, len);                    // MM2S_LENGTH -> 启动
            guard = 0;
            sr_q = 32'h0;
            while (!(sr_q[1]) && guard < 4000) begin     // 等 Idle
                lite_read(10'h004, sr_q);
                guard = guard + 1;
            end
            $display("[%0t] DMASR=%08x idle=%b ioc=%b errbits=%b", $time, sr_q, sr_q[1], sr_q[12], sr_q[6:4]);
            repeat (60) @(posedge mm2s_clk);
        end
    endtask

    //=========================================================================
    initial begin
        nb = 0;
        repeat (10) @(posedge lite_clk);
        rstn = 1'b1;
        repeat (20) @(posedge lite_clk);

        dma_run(32'h0010_0040, 32'd64);    // 板场次同款: 64B 对齐, 单拍
        dma_run(32'h0010_0100, 32'd128);   // 64B 对齐, 两拍
        dma_run(32'h0010_0024, 32'd64);    // 非 64B 对齐 (观察 IP 行为)

        $display("PROBE_DONE");
        $finish;
    end

endmodule
