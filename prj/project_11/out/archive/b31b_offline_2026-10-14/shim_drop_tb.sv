//=============================================================================
// shim_drop_tb.sv — dma_rd_shim 前导丢弃判据（prj11 B3-1b）
//-----------------------------------------------------------------------------
// 背景: 板上实证 DMA 读窗口起点比帧首早 50 字节(见 dma_rd_shim.v 头部证据)。
//   集成配置 = 对齐读 SA=SLOT_BASE, LEN=帧长+DROP_BYTES, shim DROP_BYTES=50。
//   本 TB 用 DROP_BYTES=50 的实例, 直接验证:
//     把「50 字节前导 + 帧」的 512b 流喂进去, 输出必须是**纯帧字节**(前导全丢),
//     且描述符 len = 帧长(不是帧长+50)。
//
// 判据:
//   D1 200B 帧 + 50B 前导 (合计 250B = 3 全拍 + 58B 尾拍) -> 字节流 == 帧, len=200
//   D2 512B 帧 + 50B 前导 (合计 562B = 8 全拍 + 50B 尾拍) -> 字节流 == 帧, len=512
//   D3   1B 帧 + 50B 前导 (合计  51B = 1 拍, keep=51)     -> 字节流 == 帧, len=1
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
    wire        rdesc_wr_en;
    wire [24:0] rdesc_wr_data;
    reg  [7:0]  tag_slot = 0;
    reg         tag_valid = 0;

    dma_rd_shim #(.DROP_BYTES(DROP)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(tdata), .s_tkeep(tkeep), .s_tlast(tlast), .s_tvalid(tvalid),
        .s_tready(tready),
        .rf_wr_en(rf_wr_en), .rf_wr_data(rf_wr_data),
        .rdesc_wr_en(rdesc_wr_en), .rdesc_wr_data(rdesc_wr_data),
        .tag_slot(tag_slot), .tag_valid(tag_valid), .tag_pop()
    );

    int errs = 0;
    int got_bytes = 0;

    reg [7:0]  cap [0:8191];
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

    // 一帧: n 字节(帧), 前导 DROP, 校验输出 = 帧, 描述符 len=n
    task automatic case_drop(input int n, input byte base, input byte slot, input string tag);
        int b0, dn0, g0;
        begin
            b0 = got_bytes;
            mk_stream(n, base);
            tag_slot = slot; tag_valid = 1;
            emit(DROP + n);
            @(negedge clk); tag_valid = 0;
            dn0 = desc_n; g0 = 0;
            while ((desc_n == dn0) && (g0 < 8000)) begin
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
            if (desc_n < 1) begin
                $display("[FAIL] %s 无描述符", tag); errs = errs + 1;
            end else begin
                desc_n = desc_n - 1;
                if (desc_q[desc_n][23:8] !== n || desc_q[desc_n][7:0] !== slot) begin
                    $display("[FAIL] %s 描述符 len=%0d slot=%0d (want %0d/%0d)",
                             tag, desc_q[desc_n][23:8], desc_q[desc_n][7:0], n, slot);
                    errs = errs + 1;
                end
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
