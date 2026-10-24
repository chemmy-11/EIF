//=============================================================================
// shim_drop_tb.sv — dma_rd_shim_v2 前导丢弃判据（prj11 B3-1b）
//-----------------------------------------------------------------------------
// 背景: DMA 读窗口起点比帧首早 DROP_BYTES 字节(板上定案=8: 槽存完整 ETH 帧,
//   "50" 是 42B 帧头 + 8 的早期误读)。本 TB 用 DROP=50 跑参数健壮性 —— 故意
//   取 >64 的值, 让丢弃跨拍边界; 集成配置 DROP=8 由 bridge_dma_tb P2 覆盖。
//   把「50 字节前导 + 帧」的 512b 流喂进去, 输出必须是**纯帧字节**(前导全丢),
//   且每帧恰 1 个 frame_done (v3: 描述符由桥侧发射, 本 TB 只管字节+脉冲)。
//
// 判据:
//   D1 200B 帧 + 50B 前导 (合计 250B = 3 全拍 + 58B 尾拍) -> 字节流 == 帧, 输出恰 200B
//   D2 512B 帧 + 50B 前导 (合计 562B = 8 全拍 + 50B 尾拍) -> 字节流 == 帧, 输出恰 512B
//   D3   1B 帧 + 50B 前导 (合计  51B = 1 拍, keep=51)     -> 字节流 == 帧, 输出恰 1B
//   D4 64B 帧 + 50B 前导 (合计 114B = 1 全拍 + 50B 尾拍)  -> 边界: 前导恰在首拍内
//   期望字节流由 TB 独立生成比对; 前导填充 0xEE 且与帧字节内容不同, 漏丢必被抓。
//=============================================================================
`timescale 1ns/1ps

module shim_drop_tb;

    localparam integer DROP = 50;

    reg clk = 0, rst_n = 0;
    always #3.33 clk = ~clk;              // 300 MHz

    reg  [511:0] tdata = 0;
    reg  [63:0]  tkeep = 0;
    reg          tlast = 0, tvalid = 0;
    wire         tready;

    wire        rf_wr_en;
    wire [7:0]  rf_wr_data;
    wire        frame_done;
    reg  [7:0]  tag_slot = 0;
    reg         tag_valid = 0;

    reg [15:0] frame_len = 0;      // v3: 桥侧参考输入, shim 不再使用
    dma_rd_shim_v2 #(.DROP_BYTES(DROP)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(tdata), .s_tkeep(tkeep), .s_tlast(tlast), .s_tvalid(tvalid),
        .s_tready(tready),
        .rf_wr_en(rf_wr_en), .rf_wr_data(rf_wr_data),
        .frame_done(frame_done),
        .frame_len(frame_len), .tag_slot(tag_slot), .tag_valid(tag_valid)
    );

    int errs = 0;
    int got_bytes = 0;

    reg [7:0]  cap [0:8191];
    int        done_n = 0;

    always @(posedge clk) begin
        if (rf_wr_en) begin
            cap[got_bytes] <= rf_wr_data;
            got_bytes <= got_bytes + 1;
        end
        if (frame_done)
            done_n <= done_n + 1;
    end

    // 连续字节流缓冲: [0,DROP) 前导 0xEE; [DROP,DROP+n) 帧 = base+i
    reg [7:0]  stream [0:8191];
    task automatic mk_stream(input int n, input byte base);
        begin
            for (int i = 0; i < DROP; i = i + 1) stream[i] = 8'hEE;
            for (int i = 0; i < n; i = i + 1)  stream[DROP + i] = base + i[7:0];
        end
    endtask

    // 把一个连续字节流按 64B/拍打成 512b AXI4-Stream
    task automatic emit(input int total);
        int nb, k, i;
        begin
            nb = (total + 63) / 64;
            for (k = 0; k < nb; k = k + 1) begin
                @(negedge clk);
                tdata = 512'd0; tkeep = 64'd0;
                for (i = 0; i < 64; i = i + 1) begin
                    if ((k*64 + i) < total) begin
                        tdata[i*8 +: 8] = stream[k*64 + i];
                        tkeep[i] = 1'b1;
                    end
                end
                tlast  = ((k+1)*64 >= total);
                tvalid = 1'b1;
                while (tready !== 1'b1) @(negedge clk);   // 坑 #37: negedge 确认 tready
                @(posedge clk);
                @(negedge clk);
                tvalid = 1'b0; tlast = 1'b0;
            end
        end
    endtask

    // 一帧: n 字节(帧), 前导 DROP, 校验输出 = 帧, frame_done 恰 1 个
    task automatic case_drop(input int n, input byte base, input byte slot, input string tag);
        int b0, dn0, g0;
        begin
            b0 = got_bytes;
            mk_stream(n, base);
            tag_slot = slot; tag_valid = 1;
            frame_len = n[15:0];
            emit(DROP + n);
            @(negedge clk); tag_valid = 0;
            dn0 = done_n; g0 = 0;
            while ((done_n == dn0) && (g0 < 8000)) begin
                @(posedge clk); g0 = g0 + 1;
            end
            repeat (2) @(posedge clk);
            // 字节流 = 帧(前导必须全部丢弃)
            for (int i = 0; i < n; i = i + 1) begin
                if (cap[b0 + i] !== base + i[7:0]) begin
                    $display("[FAIL] %s byte#%d got %02x want %02x",
                             tag, i, cap[b0 + i], base + i[7:0]);
                    errs = errs + 1;
                end
            end
            if ((got_bytes - b0) != n) begin
                $display("[FAIL] %s 输出字节数=%0d want %0d (前导未全丢?)",
                         tag, got_bytes - b0, n);
                errs = errs + 1;
            end
            if (done_n == dn0) begin
                $display("[FAIL] %s 无 frame_done", tag); errs = errs + 1;
            end
            if (errs == 0) $display("[%s] %0dB 帧 + %0dB 前导 -> 纯帧 %0dB ✓", tag, n, DROP, n);
        end
    endtask

    initial begin
        repeat (10) @(posedge clk); rst_n = 1;
        repeat (5) @(posedge clk);

        case_drop(200, 8'h10, 8'h2A, "D1");
        case_drop(512, 8'h40, 8'h2B, "D2");
        case_drop(1,   8'h70, 8'h2C, "D3");
        case_drop(64,  8'h90, 8'h2D, "D4");

        $display("==== SHIM_DROP_TB: %0d errors ====", errs);
        if (errs == 0) $display("SHIM_DROP_TB: PASS"); else $display("SHIM_DROP_TB: FAIL");
        $finish;
    end

    initial begin
        #3_000_000;
        $display("SHIM_DROP_TB: FAIL (timeout)");
        $finish;
    end
endmodule
