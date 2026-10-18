// r2_lite_pipe_wr_tb.sv -- 写通道"背靠背写"复核：AXI4 允许写响应未返回前主端继续发 AW/W。
// 判据：2 次写 → 2 个 B；若 AW/W 握手数 > B 数 → 有握手被吞（互连将永等 B → 后续读被阻塞/楔死）。
`timescale 1ns/1ps
module r2_lite_pipe_wr_tb;
    reg aclk = 0, clk_user = 0;
    always #5.0 aclk = ~aclk;
    always #3.3 clk_user = ~clk_user;
    reg aresetn = 0, rst_user_n = 0;

    reg  [31:0] awaddr = 0; reg awvalid = 0; wire awready;
    reg  [31:0] wdata = 0;  reg wvalid = 0;  wire wready;
    wire [1:0] bresp; wire bvalid; reg bready = 1;
    reg  [31:0] araddr = 0; reg arvalid = 0; wire arready;
    wire [31:0] rdata; wire [1:0] rresp; wire rvalid; reg rready = 1;

    wire cfg_rd_engine, cfg_mode, rd_req_pulse, cfg_wr_pulse, cfg_wr_go, cfg_wr_ack;
    wire [7:0] cfg_rd_slot;
    wire [15:0] lite_engine_cnt, lite_exec_cnt, lite_rd_trig_cnt;
    wire [15:0] u_wr_frame = 16'h1111, u_rd_frame = 16'h2222, u_buf_drop = 16'h3333;

    axi_lite_regs dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .clk_user(clk_user), .rst_user_n(rst_user_n),
        .u_wr_frame(u_wr_frame), .u_rd_frame(u_rd_frame), .u_buf_drop(u_buf_drop),
        .lat_w(16'h4444), .lat_r(16'h5555),
        .dma_q0(32'h66666666), .dma_q1(32'h77777777), .dma_q2(32'h88888888),
        .ctl_owner(1'b1),
        .cfg_rd_engine(cfg_rd_engine),
        .dma_req(32'h0), .dma_arl(32'h0), .dbg_emit(32'h0),
        .lite_engine_cnt(lite_engine_cnt),
        .cfg_mode(cfg_mode), .cfg_rd_slot(cfg_rd_slot),
        .rd_req_pulse(rd_req_pulse), .cfg_wr_pulse(cfg_wr_pulse),
        .lite_exec_cnt(lite_exec_cnt), .lite_rd_trig_cnt(lite_rd_trig_cnt),
        .dma_wr_req(32'hDEADBEEF), .dma_wr_dbg(32'hCAFE_F00D),
        .cfg_wr_go(cfg_wr_go), .cfg_wr_ack(cfg_wr_ack)
    );

    integer aw_hs = 0, w_hs = 0, b_hs = 0, i;
    reg [1:0] lwst_d = 2'd0;
    always @(posedge aclk) begin
        if (aresetn) begin
            if (dut.lwst !== lwst_d) begin
                $display("[LWST] t=%0t lwst=%0d aw_pending=%b w_pending=%b a_req=%b a_ack_s=%b bvalid=%b awready=%b wready=%b",
                         $time, dut.lwst, dut.aw_pending, dut.w_pending, dut.a_req, dut.a_ack_s, dut.s_axi_bvalid, awready, wready);
                lwst_d <= dut.lwst;
            end
            if (awvalid && awready) aw_hs <= aw_hs + 1;
            if (wvalid && wready)   w_hs  <= w_hs + 1;
            if (bvalid && bready) begin
                b_hs <= b_hs + 1;
                $display("[BHS] t=%0t b_hs=%0d lwst=%0d", $time, b_hs + 1, dut.lwst);
            end
        end
    end

    task automatic write_pair(input [31:0] a1, input [31:0] d1, input [31:0] a2, input [31:0] d2);
        integer n;
        begin
            // 发第 1 笔
            @(negedge aclk); awaddr = a1; awvalid = 1; wdata = d1; wvalid = 1;
            n = 0;
            while (!(awvalid && awready) && n < 500) begin @(posedge aclk); n = n + 1; end
            // 不等 B，立即发第 2 笔（AXI4 允许）
            @(negedge aclk); awaddr = a2; awvalid = 1; wdata = d2; wvalid = 1;
            n = 0;
            while (n < 500) begin
                if (awvalid && awready) begin awvalid <= 1'b0; end
                if (wvalid && wready)   begin wvalid <= 1'b0; end
                @(posedge aclk); n = n + 1;
                if (!awvalid && !wvalid) n = 500;
            end
            @(negedge aclk); awvalid = 0; wvalid = 0;
            repeat (200) @(posedge aclk);
            $display("[PAIR] AW_HS=%0d W_HS=%0d B_HS=%0d (expect 2/2/2)", aw_hs, w_hs, b_hs);
        end
    endtask

    initial begin
        repeat (30) @(posedge aclk);
        aresetn = 1; rst_user_n = 1;
        repeat (30) @(posedge aclk);
        $display("=== pipelined writes: 0x00 then 0x0C (SET_MODE, SET_ENGINE) ===");
        write_pair(32'h00, 32'h01, 32'h0C, 32'h01);
        if (b_hs == 2 && aw_hs == 2 && w_hs == 2)
            $display("=== R2 LITE_PIPE_WR_TB: PASS (2 writes -> 2 B) ===");
        else
            $display("=== R2 LITE_PIPE_WR_TB: FAIL (handshake swallowed: AW/W=%0d/%0d B=%0d) ===", aw_hs, w_hs, b_hs);
        $finish;
    end
endmodule
