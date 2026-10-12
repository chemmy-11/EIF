//=============================================================================
// sink_tb.sv — dma_sink 单元仿真（prj11 B3-1a, 2026-10-12）
//-----------------------------------------------------------------------------
// 判据:
//   K1 单拍帧 64B   -> q0 = {1, 64}, q1 = 载荷首 32b, q2 done=1/tlast=1
//   K2 两拍帧 84B   -> q0 = {2, 84} (尾拍 keep=20)
//   K3 连续两帧     -> done_cnt 递增, 第二帧 q0/q1 各自正确
//   K4 无 TLAST     -> done 不增, busy 恒 1; 恢复帧正常 (TLAST=帧边界)
// 输出经 user 域 2FF 镜像, 采样前留镜像稳定窗。
//=============================================================================
`timescale 1ns/1ps

module sink_tb;
    reg clk = 0, rst_n = 0;
    reg clk_user = 0, rst_user_n = 0;
    always #1.665 clk = ~clk;           // 300 MHz
    always #3.3  clk_user = ~clk_user;  // 151.5 MHz

    reg  [511:0] tdata = 0;
    reg  [63:0]  tkeep = 0;
    reg          tlast = 0, tvalid = 0;
    wire         tready;
    wire [31:0]  q0, q1, q2;

    dma_sink dut (
        .clk(clk), .rst_n(rst_n), .clk_user(clk_user), .rst_user_n(rst_user_n),
        .s_tdata(tdata), .s_tkeep(tkeep), .s_tlast(tlast), .s_tvalid(tvalid),
        .s_tready(tready),
        .q0(q0), .q1(q1), .q2(q2));

    int errs = 0;

    task automatic beat(input int nkeep, input [31:0] word0, input bit last);
        int i;
        begin
            @(negedge clk);
            tdata = 512'd0; tkeep = 64'd0;
            tdata[31:0] = word0;
            for (i = 0; i < nkeep; i = i + 1) tkeep[i] = 1'b1;
            tlast  = last;
            tvalid = 1'b1;
            @(negedge clk);
            tvalid = 1'b0; tlast = 1'b0;
        end
    endtask

    task automatic settle;      // 2FF 镜像稳定 (两域各数拍)
        int k;
        begin
            for (k = 0; k < 40; k++) @(posedge clk);
        end
    endtask

    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1; rst_user_n = 1;
        repeat (10) @(posedge clk);

        // ---- K1: 单拍 64B ----
        beat(64, 32'h1122_3344, 1'b1);
        settle();
        $display("[K1] q0=%08x q1=%08x q2=%08x", q0, q1, q2);
        if (q0 !== 32'h0001_0040) begin $display("[FAIL] K1 q0"); errs++; end
        if (q1 !== 32'h1122_3344) begin $display("[FAIL] K1 q1"); errs++; end
        if (q2[31:24] !== 8'd1 || q2[23] !== 1'b1) begin $display("[FAIL] K1 q2 (done/tlast)"); errs++; end

        // ---- K2: 两拍 84B (64+20) ----
        beat(64, 32'hA000_0000, 1'b0);
        beat(20, 32'hA000_0040, 1'b1);
        settle();
        $display("[K2] q0=%08x q1=%08x q2=%08x", q0, q1, q2);
        if (q0 !== 32'h0002_0054) begin $display("[FAIL] K2 q0 (want 0002_0054)"); errs++; end
        if (q1 !== 32'hA000_0000) begin $display("[FAIL] K2 q1"); errs++; end
        if (q2[31:24] !== 8'd2) begin $display("[FAIL] K2 done_cnt"); errs++; end

        // ---- K4: 无 TLAST 半帧 -> busy 恒 1; 恢复帧 ----
        beat(64, 32'hDEAD_0000, 1'b0);
        repeat (100) @(posedge clk);
        if (q2[31:24] !== 8'd2) begin $display("[FAIL] K4 半帧 done 递增"); errs++; end
        // 恢复: 补一拍带 TLAST (与半帧合计算一轮, done+1)
        beat(64, 32'hDEAD_0040, 1'b1);
        settle();
        if (q2[31:24] !== 8'd3) begin
            $display("[FAIL] K4 恢复 done=%d (want 3)", q2[31:24]); errs++;
        end
        $display("[K4] 恢复后 q0=%08x q2=%08x", q0, q2);

        $display("==== SINK_TB: %0d errors ====", errs);
        if (errs == 0) $display("SINK_TB: PASS"); else $display("SINK_TB: FAIL");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("SINK_TB: FAIL (timeout)");
        $finish;
    end
endmodule
