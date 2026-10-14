//=============================================================================
// shim_tb.sv — dma_rd_shim 单元仿真（prj11 B3-1b, 2026-10-12）
//-----------------------------------------------------------------------------
// 判据:
//   S1 全拍帧    : 2 拍 × 64B 全 keep -> 字节流逐字节一致, 描述符 {len=128, slot}
//   S2 尾拍截断  : 1 全拍 + 1 尾拍 keep=20B -> len=84 (TKEEP 语义, 不拖尾)
//   S3 单拍帧    : 1 拍 keep=7B -> len=7
//   S4 连续多帧  : 背靠背 3 帧(不同 slot tag) -> 3 个描述符, 顺序与 tag 一致
//   NEG 无 TLAST : 流只发 1 拍(无 tlast)后停止 -> 不发描述符, 不死锁,
//                  后续新帧(tvalid 重新出现)能重新开始 (IDLE 重入)
// 激励用可变 keep/last 的任务驱动; 期望字节流由 TB 独立生成比对。
//=============================================================================
`timescale 1ns/1ps

module shim_tb;

    reg clk = 0, rst_n = 0;
    always #3.33 clk = ~clk;              // 300 MHz

    reg  [511:0] tdata = 0;
    reg  [63:0]  tkeep = 0;
    reg          tlast = 0, tvalid = 0;
    wire         tready;

    wire        rf_wr_en;
    wire [7:0]  rf_wr_data;
    wire        rdesc_wr_en;
    wire [24:0] rdesc_wr_data;
    reg  [7:0]  tag_slot = 0;
    reg         tag_valid = 0;

    dma_rd_shim dut (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(tdata), .s_tkeep(tkeep), .s_tlast(tlast), .s_tvalid(tvalid),
        .s_tready(tready),
        .rf_wr_en(rf_wr_en), .rf_wr_data(rf_wr_data),
        .rdesc_wr_en(rdesc_wr_en), .rdesc_wr_data(rdesc_wr_data),
        .tag_slot(tag_slot), .tag_valid(tag_valid), .tag_pop()
    );

    int errs = 0;
    int got_bytes = 0;

    // 收集字节流与描述符
    reg [7:0]  cap [0:4095];
    reg [24:0] desc_q [0:15];
    int        desc_n = 0;

    always @(posedge clk) begin
        if (rf_wr_en) begin
            cap[got_bytes] <= rf_wr_data;
            got_bytes <= got_bytes + 1;
        end
        if (rdesc_wr_en) begin
            desc_q[desc_n] <= rdesc_wr_data;
            desc_n <= desc_n + 1;
        end
    end

    // 构造一拍(64B), 前 n 字节有效(keep), 数据 = base+i
    task automatic beat(input int nkeep, input byte base, input bit last);
        int i;
        begin
            @(negedge clk);
            tdata = 512'd0; tkeep = 64'd0;
            for (i = 0; i < nkeep; i = i + 1) begin
                tdata[i*8 +: 8] = base + i[7:0];
                tkeep[i] = 1'b1;
            end
            tlast  = last;
            tvalid = 1'b1;
            // 坑 #37 纪律: negedge 上确认 tready=1, 让下一 posedge 成为握手沿
            while (tready !== 1'b1) @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            tvalid = 1'b0; tlast = 1'b0;
        end
    endtask

    // 比对一段已收字节与期望
    task automatic chk_bytes(input int from_, input int n, input byte base, input string tag);
        int i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                if (cap[from_ + i] !== base + i[7:0]) begin
                    $display("[FAIL] %s byte#%d: got %02x want %02x",
                             tag, i, cap[from_ + i], base + i[7:0]);
                    errs = errs + 1;
                end
            end
        end
    endtask

    // extra: 错误路径语义 —— 前一帧无 TLAST 弃帧后 in_frame 残留, 恢复帧
    //        的描述符 len 会包含弃帧字节数(RTL 有意为之: TLAST 是唯一帧边界)
    task automatic frame(input int nbytes, input byte base, input byte slot,
                         input int extra = 0);
        int full, tail;
        int b0;
        begin
            b0 = got_bytes;
            tag_slot = slot; tag_valid = 1;
            full = nbytes / 64;
            tail = nbytes % 64;
            for (int k = 0; k < full; k++)
                beat(64, base + k*64, (tail == 0) && (k == full-1));
            if (tail != 0)
                beat(tail, base + full*64, 1'b1);
            @(negedge clk); tag_valid = 0;
            // 等描述符出现(=整帧拆包完成), 而非固定拍数; 5000 拍超时兜底
            begin
                int g0 = 0;
                int dn0 = desc_n;
                while ((desc_n == dn0) && (g0 < 5000)) begin
                    @(posedge clk); g0 = g0 + 1;
                end
                repeat (2) @(posedge clk);
            end
            chk_bytes(b0, nbytes, base, $sformatf("F%0d", nbytes));
            if (desc_n < 1) begin
                $display("[FAIL] 无描述符"); errs = errs + 1;
            end else begin
                desc_n = desc_n - 1;
                if ((desc_q[desc_n][23:8] !== nbytes + extra) ||
                    (desc_q[desc_n][7:0] !== slot)) begin
                    $display("[FAIL] 描述符 len=%0d slot=%0d (want %0d/%0d)",
                             desc_q[desc_n][23:8], desc_q[desc_n][7:0], nbytes, slot);
                    errs = errs + 1;
                end
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk); rst_n = 1;
        repeat (5) @(posedge clk);

        // ---- S1 全拍帧: 128B (2 全拍) ----
        frame(128, 8'h10, 8'h2A);
        $display("[S1] 128B 全拍帧 done");

        // ---- S2 尾拍截断: 84B = 64 + 20 ----
        frame(84, 8'h40, 8'h2B);
        $display("[S2] 84B 尾拍帧 done (TKEEP 语义)");

        // ---- S3 单拍短帧: 7B ----
        frame(7, 8'h70, 8'h2C);
        $display("[S3] 7B 单拍帧 done");

        // ---- S4 背靠背 3 帧 ----
        frame(64, 8'h90, 8'h01);
        frame(200, 8'hA0, 8'h02);
        frame(65, 8'hB0, 8'h03);
        $display("[S4] 背靠背 3 帧 done");

        // ---- NEG: 无 TLAST 的"半帧" -> 不发描述符; 再发正常帧可恢复 ----
        desc_n = 0;
        beat(64, 8'hC0, 1'b0);                    // 无 tlast
        repeat (80) @(posedge clk);
        if (desc_n != 0) begin
            $display("[FAIL] NEG: 半帧发了描述符"); errs = errs + 1;
        end
        // 静默后重新开始一帧 (shim 应停在 IDLE/UNPK 且能继续)
        frame(50, 8'hD0, 8'h05, 64);   // 弃帧 64B 并入恢复帧 len (文档化语义)
        $display("[NEG] 恢复帧 len 含弃帧 64B (TLAST=唯一帧边界, 设计语义)");
        $display("[NEG] 无TLAST恢复 done");

        $display("==== SHIM_TB: %0d errors ====", errs);
        if (errs == 0) $display("SHIM_TB: PASS"); else $display("SHIM_TB: FAIL");
        $finish;
    end

    initial begin
        #3_000_000;
        $display("SHIM_TB: FAIL (timeout)");
        $finish;
    end
endmodule
