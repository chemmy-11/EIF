//=============================================================================
// tb_eth_rewrap_fcs.sv — eth_rewrap 完整出帧字节级回归（2026-11-20 D1 修复）
//-----------------------------------------------------------------------------
// 裁决要求（EIF #13 16:26）：
//   "先回归，后启动 B 构建"；覆盖 前导/SFD → MAC/EtherType/IP/填充 → FCS；
//   "从首拍至 FCS 连续有效"；"CRC 只覆盖 MAC 头、IP 和填充"；
//   "按独立 CRC 参考逐字节比对"；GMII 有效宽度 72 / 154 / 1526。
//
// 三个用例：
//   CASE1 100B UDP   : i_pkt_len=128 → 8 + 142 + 4 = 154
//   CASE2 短帧填充   : i_pkt_len=40  → 8 + 60  + 4 = 72
//   CASE3 1500B IPv4 : i_pkt_len=1500→ 8 + 1514+ 4 = 1526
//
// 判据：帧长、前导 7x55+D5、以太头、IP 载荷 1:1 原样、FCS 与独立参考逐字节一致
//       → 打印 TEST_PASS / TEST_FAIL
//=============================================================================
`timescale 1ns / 1ps

module tb_eth_rewrap_fcs;

    localparam [47:0] TB_DST_MAC = 48'hA8_2B_DD_76_DF_A2;   // PC2 数据 NIC（裁决指定）
    localparam [47:0] TB_SRC_MAC = 48'h02_00_00_00_0A_01;   // 板 A

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    always #5 clk = ~clk;

    //---- DUT 接口 ----
    reg         s_valid = 1'b0;
    wire        s_ready;
    reg  [7:0]  s_data = 8'h00;
    reg         s_sop = 1'b0;
    reg         s_eop = 1'b0;
    reg  [15:0] i_pkt_len = 16'd0;

    wire        m_valid;
    reg         m_ready = 1'b1;
    wire [7:0]  m_data;
    wire        m_sop, m_eop;
    wire [15:0] m_frame_len;
    wire        o_len_err;

    eth_rewrap #(
        .SRC_MAC       (TB_SRC_MAC),
        .DST_MAC       (TB_DST_MAC),
        .MIN_FRAME_LEN (16'd60)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sop(s_sop), .s_eop(s_eop), .i_pkt_len(i_pkt_len),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_data),
        .m_sop(m_sop), .m_eop(m_eop),
        .m_frame_len(m_frame_len), .o_len_err(o_len_err)
    );

    //---- 采集输出帧 ----
    byte unsigned cap[$];
    always @(posedge clk) begin
        if (m_valid && m_ready) cap.push_back(m_data);
    end

    //---- 独立 CRC 参考（CRC-32/ISO-HDLC）----
    function automatic logic [31:0] ref_crc(input logic [31:0] c, input logic [7:0] b);
        logic [31:0] x; x = c ^ {24'b0, b};
        for (int i = 0; i < 8; i++) x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
        return x;
    endfunction

    int pass_cnt = 0, fail_cnt = 0;

    //---- 发一个 IP 包 ----
    task automatic send_pkt(input int plen, input byte unsigned pay[$]);
        // 等 DUT 空闲
        while (!s_ready) @(posedge clk);
        for (int i = 0; i < plen; i++) begin
            @(negedge clk);
            s_valid   = 1'b1;
            s_data    = (i < pay.size()) ? pay[i] : 8'hA5;   // 未指定字节用 A5
            s_sop     = (i == 0);
            s_eop     = (i == plen-1);
            i_pkt_len = plen[15:0];
            @(posedge clk);
            while (!s_ready) @(posedge clk);
        end
        @(negedge clk);
        s_valid = 1'b0; s_sop = 1'b0; s_eop = 1'b0;
    endtask

    //---- 一个完整用例 ----
    task automatic run_case(input string name, input int plen, input int exp_len);
        byte unsigned pay[$];
        logic [31:0] crc;
        int errs;
        int tot_data;

        cap.delete();
        // 载荷：可预测序列
        for (int i = 0; i < plen; i++) pay.push_back(8'(i * 7 + 8'h10));

        send_pkt(plen, pay);
        // 等帧发完
        repeat (40) @(posedge clk);

        $display("---- %s : i_pkt_len=%0d  expect_total=%0d  got=%0d  m_frame_len=%0d",
                 name, plen, exp_len, cap.size(), m_frame_len);

        errs = 0;
        if (cap.size() != exp_len) begin
            $display("   FAIL: 帧长 %0d != %0d", cap.size(), exp_len); errs++;
        end
        // tot_data = exp_len - 8 - 4
        tot_data = exp_len - 12;

        // 前导码 7x55 + D5
        for (int i = 0; i < 7; i++)
            if (cap[i] !== 8'h55) begin $display("   FAIL: 前导[%0d]=%02x != 55", i, cap[i]); errs++; end
        if (cap[7] !== 8'hD5) begin $display("   FAIL: SFD=%02x != D5", cap[7]); errs++; end

        // 以太头
        for (int i = 0; i < 6; i++)
            if (cap[8+i] !== TB_DST_MAC[47-8*i -: 8]) begin
                $display("   FAIL: dst_mac[%0d]=%02x != %02x", i, cap[8+i], TB_DST_MAC[47-8*i -: 8]); errs++; end
        for (int i = 0; i < 6; i++)
            if (cap[14+i] !== TB_SRC_MAC[47-8*i -: 8]) begin
                $display("   FAIL: src_mac[%0d]=%02x != %02x", i, cap[14+i], TB_SRC_MAC[47-8*i -: 8]); errs++; end
        if (cap[20] !== 8'h08 || cap[21] !== 8'h00) begin
            $display("   FAIL: ethertype=%02x%02x != 0800", cap[20], cap[21]); errs++; end

        // IP 载荷 1:1 原样 + 填充为 0
        for (int i = 0; i < tot_data - 14; i++) begin
            byte unsigned exp_b;
            exp_b = (i < plen) ? pay[i] : 8'h00;
            if (cap[22+i] !== exp_b) begin
                if (errs < 8) $display("   FAIL: payload[%0d]=%02x != %02x", i, cap[22+i], exp_b);
                errs++; end
        end

        // FCS：CRC 只覆盖 MAC 头 + IP + 填充 = cap[8 .. exp_len-5]
        crc = 32'hFFFFFFFF;
        for (int i = 8; i <= exp_len-5; i++) crc = ref_crc(crc, cap[i]);
        crc = ~crc;
        if (cap[exp_len-4] !== crc[7:0]   || cap[exp_len-3] !== crc[15:8] ||
            cap[exp_len-2] !== crc[23:16] || cap[exp_len-1] !== crc[31:24]) begin
            $display("   FAIL: FCS got %02x %02x %02x %02x  expect %02x %02x %02x %02x",
                     cap[exp_len-4], cap[exp_len-3], cap[exp_len-2], cap[exp_len-1],
                     crc[7:0], crc[15:8], crc[23:16], crc[31:24]);
            errs++;
        end

        if (errs == 0) begin
            $display("   PASS (%0d 字节逐字节核对)", exp_len);
            pass_cnt++;
        end else begin
            $display("   FAIL (%0d 处不符)", errs);
            fail_cnt++;
        end
        $display("");
    endtask

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        run_case("CASE1 100B UDP",   128, 154);
        run_case("CASE2 短帧填充",    40,  72);
        run_case("CASE3 1500B IPv4", 1500, 1526);
        // 连续帧：紧接着再发一帧，验证状态机复位正常
        run_case("CASE4 连续帧①",   128, 154);
        run_case("CASE5 连续帧②",   128, 154);

        $display("=========================================");
        if (fail_cnt == 0) $display("TEST_PASS  (pass=%0d fail=%0d)", pass_cnt, fail_cnt);
        else               $display("TEST_FAIL  (pass=%0d fail=%0d)", pass_cnt, fail_cnt);
        $finish;
    end

    initial begin #2000000; $display("TEST_FAIL: WATCHDOG"); $finish; end

endmodule
