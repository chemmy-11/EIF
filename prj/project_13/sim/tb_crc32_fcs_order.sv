//=============================================================================
// tb_crc32_fcs_order.sv (v2) — 确定 crc32_d8 的正确 FCS 取字节公式
//-----------------------------------------------------------------------------
// v1 结论：crc32_d8 的内部 crc_data 是标准 FCS 的 **位反转**：
//   bitrev32(crc_data) == 标准线上 FCS
//   验证：输入 "123456789" → bitrev32(0x9B63D02C) = 0x340BC6D9 = ~0xCBF43926 ✓
//
// v2 目的：验证候选公式
//   CAND-A: b_k = reverse_bits( crc_data[(31-8k) : (24-8k)] )   （无取反）
//   是否对多组数据都成立 → 决定 eth_rewrap 的 FCS 输出写法
//=============================================================================
`timescale 1ns / 1ps

module tb_crc32_fcs_order;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    reg  [7:0]  data = 8'h00;
    reg         crc_en = 1'b0;
    reg         crc_clr = 1'b0;
    wire [31:0] crc_data;
    wire [31:0] crc_next;

    always #5 clk = ~clk;

    crc32_d8 u_crc32_d8 (
        .clk(clk), .rst_n(rst_n), .data(data),
        .crc_en(crc_en), .crc_clr(crc_clr),
        .crc_data(crc_data), .crc_next(crc_next)
    );

    // 软件参考 CRC-32/ISO-HDLC
    function automatic logic [31:0] ref_crc(input logic [31:0] c, input logic [7:0] b);
        logic [31:0] x; x = c ^ {24'b0, b};
        for (int i = 0; i < 8; i++) x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
        return x;
    endfunction

    function automatic logic [7:0] rev8(input logic [7:0] b);
        logic [7:0] r;
        for (int i = 0; i < 8; i++) r[i] = b[7-i];
        return r;
    endfunction

    int pass_cnt = 0, fail_cnt = 0;

    // 一组测试向量：[0] 是长度，其余是字节
    task automatic run_case(input string name, input byte unsigned vec[$]);
        logic [31:0] c;
        logic [31:0] wire_fcs;      // 标准：~CRC
        logic [7:0]  exp_b[4];
        logic [7:0]  got_b[4];

        // 参考
        c = 32'hFFFFFFFF;
        foreach (vec[i]) c = ref_crc(c, vec[i]);
        wire_fcs = ~c;
        exp_b[0] = wire_fcs[7:0];
        exp_b[1] = wire_fcs[15:8];
        exp_b[2] = wire_fcs[23:16];
        exp_b[3] = wire_fcs[31:24];

        // 复位 + 喂数
        crc_clr = 1'b1; @(posedge clk); @(negedge clk); crc_clr = 1'b0;
        rst_n = 1'b1;
        foreach (vec[i]) begin
            data = vec[i]; crc_en = 1'b1;
            @(posedge clk); @(negedge clk);
            crc_en = 1'b0;
        end
        @(posedge clk); @(negedge clk);

        // CAND-A: 无取反，按字节位反转，高字节在前
        got_b[0] = rev8(crc_data[31:24]);
        got_b[1] = rev8(crc_data[23:16]);
        got_b[2] = rev8(crc_data[15:8]);
        got_b[3] = rev8(crc_data[7:0]);

        $display("[%s] n=%0d  crc_data=0x%08x", name, vec.size(), crc_data);
        $display("   EXP = %02x %02x %02x %02x", exp_b[0], exp_b[1], exp_b[2], exp_b[3]);
        $display("   GOT = %02x %02x %02x %02x", got_b[0], got_b[1], got_b[2], got_b[3]);

        if (got_b[0] === exp_b[0] && got_b[1] === exp_b[1] &&
            got_b[2] === exp_b[2] && got_b[3] === exp_b[3]) begin
            $display("   CAND-A: PASS");
            pass_cnt++;
        end else begin
            $display("   CAND-A: FAIL");
            fail_cnt++;
        end
        $display("");
    endtask

    initial begin
        byte unsigned v1[$], v2[$], v3[$], v4[$];
        v1 = '{8'h31,8'h32,8'h33,8'h34,8'h35,8'h36,8'h37,8'h38,8'h39};   // "123456789"
        v2 = '{8'h00};                                                    // 单字节 0
        v3 = '{8'hFF,8'hFF,8'hFF,8'hFF};                                  // 全 FF
        v4 = '{8'h02,8'h00,8'h00,8'h00,8'h0B,8'h01,8'h08,8'h3C,8'h03,8'hA0,
               8'h26,8'h96,8'h08,8'h00,8'h45,8'h00,8'h00,8'h80};          // 类以太帧头片段

        rst_n = 1'b0;
        repeat (3) @(posedge clk);

        run_case("123456789", v1);
        run_case("single00",  v2);
        run_case("ffffffff",  v3);
        run_case("ethhdr18",  v4);

        $display("-----------------------------------------");
        if (fail_cnt == 0) $display("TEST_PASS  (pass=%0d fail=%0d)", pass_cnt, fail_cnt);
        else               $display("TEST_FAIL  (pass=%0d fail=%0d)", pass_cnt, fail_cnt);
        $finish;
    end

    initial begin #200000; $display("TEST_FAIL: WATCHDOG"); $finish; end

endmodule
