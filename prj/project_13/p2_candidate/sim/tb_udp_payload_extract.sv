`timescale 1ns/1ps
// =============================================================================
// tb_udp_payload_extract.sv — prj12 P2 候选件① 单元 TB
// 判据:
//   T1 正常 100B：payload 逐字节一致 + m_len=100 + 无错误标志
//   T2 零长（udp_len=8）：err_zero=1, m_len=0
//   T3 超长（udp_len=8+1497）：err_oversize=1
//   T4 长度不符（声明 108，实发 90）：err_len_mismatch=1
//   T5 头部截断（只发 3B 就 last）：err_trunc=1
//   T6 背压：m_ready 周期拉低，payload 仍逐字节一致
// 结束: 打印 P2_EXTRACT_TB: PASS/FAIL
// =============================================================================
module tb_udp_payload_extract;

  reg clk = 0;
  always #4 clk = ~clk;         // 125 MHz
  reg rst_n = 0;

  reg  [7:0] s_data  = 0;
  reg        s_valid = 0;
  reg        s_sop   = 0;
  reg        s_last  = 0;
  wire       s_ready;

  wire [7:0] m_data;
  wire       m_valid, m_last;
  reg        m_ready = 1;

  wire [15:0] m_len;
  wire        m_len_valid;
  wire        err_zero, err_oversize, err_len_mismatch, err_trunc;

  udp_payload_extract dut (
    .clk(clk), .rst_n(rst_n),
    .s_data(s_data), .s_valid(s_valid), .s_sop(s_sop), .s_last(s_last), .s_ready(s_ready),
    .m_data(m_data), .m_valid(m_valid), .m_last(m_last), .m_ready(m_ready),
    .m_len(m_len), .m_len_valid(m_len_valid),
    .err_zero(err_zero), .err_oversize(err_oversize),
    .err_len_mismatch(err_len_mismatch), .err_trunc(err_trunc)
  );

  integer errs = 0;
  integer ncap = 0;
  integer saw_len = 0;          // m_len_valid 脉冲是否真的看到（否则判据不可信）
  reg [7:0] cap [0:4095];
  integer cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (m_valid && m_ready && ncap < 4096) begin
      cap[ncap] = m_data;
      ncap = ncap + 1;
    end
    if (m_len_valid) saw_len <= 1;
  end

  // 发一帧 UDP 段：hdr_bytes（<=8，模拟头截断）+ 声明长度 + 实发 payload 字节数
  // ★2026-10-24 修: last 必须落在**整帧最后一个字节**上（零 payload 时就是第 8 个
  //   头字节），否则 DUT 会在 ST_PAY 里等一个永远不来的载荷（首版 TB 就是这么挂的）。
  task automatic send_udp(input integer hdr_bytes, input [15:0] udp_len_decl,
                          input integer n_payload, input integer slow_ready);
    integer i, guard, total, idx;
    reg [7:0] b;
    reg is_last_byte;
    begin
      ncap = 0;
      saw_len = 0;
      total = hdr_bytes + n_payload;
      for (i = 0; i < hdr_bytes; i = i + 1) begin
        case (i)
          0: b = 8'h04; 1: b = 8'hd2;               // sport 1234
          2: b = 8'h04; 3: b = 8'hd2;               // dport 1234
          4: b = udp_len_decl[15:8];
          5: b = udp_len_decl[7:0];
          default: b = 8'h00;                       // cksum
        endcase
        idx = i + 1;
        is_last_byte = (idx == total);
        guard = 0;
        while (!s_ready && guard < 200) begin @(negedge clk); guard = guard + 1; end
        s_data = b; s_valid = 1; s_sop = (i == 0); s_last = is_last_byte;
        @(negedge clk);
      end
      for (i = 0; i < n_payload; i = i + 1) begin
        idx = hdr_bytes + i + 1;
        is_last_byte = (idx == total);
        guard = 0;
        while (!s_ready && guard < 200) begin
          @(negedge clk); guard = guard + 1;
          if (slow_ready) m_ready = (cyc % 4) != 0; else m_ready = 1;
        end
        s_data = (i * 5 + 1) & 8'hFF; s_valid = 1; s_sop = 0; s_last = is_last_byte;
        @(negedge clk);
        if (slow_ready) m_ready = (cyc % 4) != 0;
      end
      s_valid = 0; s_sop = 0; s_last = 0; m_ready = 1;
      // 等 m_len_valid（1 拍脉冲）
      guard = 0;
      while (!m_len_valid && guard < 4000) begin @(negedge clk); guard = guard + 1; end
      @(negedge clk);
      if (!saw_len && !m_len_valid) begin
        $display("  [FAIL] m_len_valid pulse never seen (timeout)");
        errs = errs + 1;
      end
    end
  endtask

  task automatic expect_flags(input [15:0] len, input exp_zero, input exp_over,
                              input exp_mismatch, input exp_trunc, input [15:0] exp_len);
    begin
      if (ncap !== len) begin
        $display("  [FAIL] captured %0d, expect %0d", ncap, len);
        errs = errs + 1;
      end
      if (m_len !== exp_len) begin
        $display("  [FAIL] m_len=%0d expect %0d", m_len, exp_len);
        errs = errs + 1;
      end
      if (err_zero !== exp_zero)         begin $display("  [FAIL] err_zero=%b expect %b", err_zero, exp_zero); errs = errs + 1; end
      if (err_oversize !== exp_over)     begin $display("  [FAIL] err_oversize=%b expect %b", err_oversize, exp_over); errs = errs + 1; end
      if (err_len_mismatch !== exp_mismatch) begin $display("  [FAIL] err_len_mismatch=%b expect %b", err_len_mismatch, exp_mismatch); errs = errs + 1; end
      if (err_trunc !== exp_trunc)       begin $display("  [FAIL] err_trunc=%b expect %b", err_trunc, exp_trunc); errs = errs + 1; end
    end
  endtask

  integer i;
  initial begin
    $display("=== tb_udp_payload_extract ===");
    repeat (5) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);

    // T1 正常 100B
    send_udp(8, 16'd108, 100, 0);
    expect_flags(100, 0, 0, 0, 0, 16'd100);
    for (i = 0; i < ncap; i = i + 1)
      if (cap[i] !== ((i * 5 + 1) & 8'hFF)) begin
        $display("  [FAIL] T1 payload[%0d]=%02x", i, cap[i]); errs = errs + 1; i = ncap;
      end

    // T2 零长
    send_udp(8, 16'd8, 0, 0);
    expect_flags(0, 1, 0, 0, 0, 16'd0);

    // T3 超长（1497 payload）
    send_udp(8, 16'd1505, 10, 0);
    expect_flags(10, 0, 1, 1, 0, 16'd10);   // 声明 1505 实发 10 => 同时 length mismatch

    // T4 长度不符：声明 108，实发 90
    send_udp(8, 16'd108, 90, 0);
    expect_flags(90, 0, 0, 1, 0, 16'd90);

    // T5 头截断：只发 3B
    send_udp(3, 16'd0, 0, 0);
    expect_flags(0, 0, 0, 0, 1, 16'd0);

    // T6 背压 100B
    send_udp(8, 16'd108, 100, 1);
    expect_flags(100, 0, 0, 0, 0, 16'd100);

    if (errs == 0) $display("P2_EXTRACT_TB: PASS");
    else           $display("P2_EXTRACT_TB: FAIL (%0d errors)", errs);
    $finish;
  end

  initial begin
    #2000000;
    $display("P2_EXTRACT_TB: FAIL (timeout)");
    $finish;
  end
endmodule
