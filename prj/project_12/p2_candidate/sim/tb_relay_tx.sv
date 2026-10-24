`timescale 1ns/1ps
// =============================================================================
// tb_relay_tx.sv — prj12 P2 候选件② 单元 TB（relay_tx）
// 判据:
//   T1 长度 0/1/26/100/1496：42B 头部逐字节 + payload 逐字节一致
//   T2 IP 头自校验：20B 头按 16bit 累加 = 0xFFFF
//   T3 长度字段：IP total_len = 28+len，UDP len = 8+len
//   T4 1497 超限：err_oversize=1 且**不产生任何输出字节**
//   T5 背压：m_ready 周期性拉低，输出仍逐字节一致（证明没有丢拍）
// 结束: 打印 P2_RELAY_TB: PASS/FAIL
// =============================================================================
module tb_relay_tx;

  localparam [47:0] SRC_MAC  = 48'h00_11_22_33_44_55;
  localparam [31:0] SRC_IP   = {8'd192, 8'd168, 8'd1, 8'd10};
  localparam [15:0] SRC_PORT = 16'd1234;
  localparam [47:0] DST_MAC  = 48'hAA_BB_CC_DD_EE_FF;
  localparam [31:0] DST_IP   = {8'd192, 8'd168, 8'd1, 8'd102};
  localparam [15:0] DST_PORT = 16'd1234;

  reg clk = 0;
  always #4 clk = ~clk;          // 125 MHz
  reg rst_n = 0;

  reg  [47:0] dst_mac  = DST_MAC;
  reg  [31:0] dst_ip   = DST_IP;
  reg  [15:0] dst_port = DST_PORT;
  reg         start    = 0;
  reg  [15:0] plen     = 0;

  reg  [7:0]  p_data  = 0;
  reg         p_valid = 0;
  reg         p_last  = 0;
  wire        p_ready;

  wire [7:0]  m_data;
  wire        m_valid;
  wire        m_last;
  reg         m_ready = 1;

  wire busy, done, err_oversize, err_short;

  relay_tx dut (
    .clk(clk), .rst_n(rst_n),
    .dst_mac(dst_mac), .dst_ip(dst_ip), .dst_port(dst_port),
    .start(start), .payload_len(plen),
    .p_data(p_data), .p_valid(p_valid), .p_last(p_last), .p_ready(p_ready),
    .m_data(m_data), .m_valid(m_valid), .m_last(m_last), .m_ready(m_ready),
    .busy(busy), .done(done), .err_oversize(err_oversize), .err_short(err_short)
  );

  integer errs = 0;
  integer ncap = 0;
  reg [7:0] cap [0:4095];
  integer cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (m_valid && m_ready && ncap < 4096) begin
      cap[ncap] = m_data;
      ncap = ncap + 1;
    end
  end

  // ---- 参考模型 ----
  function [15:0] ip_cksum(input [15:0] tot_len);
    reg [31:0] s;
    begin
      s = 32'h0000_4500 + {16'h0000, tot_len} + 32'h0000_0000
        + 32'h0000_4000 + 32'h0000_4011
        + {16'h0000, SRC_IP[31:16]} + {16'h0000, SRC_IP[15:0]}
        + {16'h0000, DST_IP[31:16]} + {16'h0000, DST_IP[15:0]};
      s = (s & 32'h0000_FFFF) + (s >> 16);
      s = (s & 32'h0000_FFFF) + (s >> 16);
      ip_cksum = ~s[15:0];
    end
  endfunction

  reg [7:0] exp [0:4095];

  task automatic build_expected(input [15:0] len);
    reg [15:0] total_len, udp_len, ck;
    integer i;
    begin
      total_len = 16'd28 + len;
      udp_len   = 16'd8 + len;
      ck        = ip_cksum(total_len);
      exp[0]=DST_MAC[47:40];  exp[1]=DST_MAC[39:32]; exp[2]=DST_MAC[31:24];
      exp[3]=DST_MAC[23:16];  exp[4]=DST_MAC[15:8];  exp[5]=DST_MAC[7:0];
      exp[6]=SRC_MAC[47:40];  exp[7]=SRC_MAC[39:32]; exp[8]=SRC_MAC[31:24];
      exp[9]=SRC_MAC[23:16];  exp[10]=SRC_MAC[15:8]; exp[11]=SRC_MAC[7:0];
      exp[12]=8'h08; exp[13]=8'h00;
      exp[14]=8'h45; exp[15]=8'h00;
      exp[16]=total_len[15:8]; exp[17]=total_len[7:0];
      exp[18]=8'h00; exp[19]=8'h00;
      exp[20]=8'h40; exp[21]=8'h00;
      exp[22]=8'd64; exp[23]=8'd17;
      exp[24]=ck[15:8]; exp[25]=ck[7:0];
      exp[26]=SRC_IP[31:24]; exp[27]=SRC_IP[23:16]; exp[28]=SRC_IP[15:8]; exp[29]=SRC_IP[7:0];
      exp[30]=DST_IP[31:24]; exp[31]=DST_IP[23:16]; exp[32]=DST_IP[15:8]; exp[33]=DST_IP[7:0];
      exp[34]=SRC_PORT[15:8]; exp[35]=SRC_PORT[7:0];
      exp[36]=DST_PORT[15:8]; exp[37]=DST_PORT[7:0];
      exp[38]=udp_len[15:8]; exp[39]=udp_len[7:0];
      exp[40]=8'h00; exp[41]=8'h00;
      for (i = 0; i < len; i = i + 1) exp[42+i] = (i * 7 + 3) & 8'hFF;
    end
  endtask

  // ---- 驱动一帧 ----
  task automatic run_frame(input [15:0] len, input integer slow_ready);
    integer i;
    integer guard;
    begin
      build_expected(len);
      ncap   = 0;
      @(negedge clk);
      plen  = len;
      start = 1;
      @(negedge clk);
      start = 0;
      // 载荷：等 p_ready 再进
      for (i = 0; i < len; i = i + 1) begin
        guard = 0;
        while (!p_ready && guard < 200) begin @(negedge clk); guard = guard + 1; end
        p_data  = (i * 7 + 3) & 8'hFF;
        p_valid = 1;
        p_last  = (i == len - 1);
        @(negedge clk);
      end
      p_valid = 0;
      p_last  = 0;
      // m_ready 背压开关
      if (slow_ready) begin
        while (!done) begin
          @(negedge clk);
          m_ready = (cyc % 5) != 0;
        end
        m_ready = 1;
      end else begin
        guard = 0;
        while (!done && guard < 20000) begin @(negedge clk); guard = guard + 1; end
      end
      @(negedge clk);
      @(negedge clk);
      // 比对
      if (ncap !== 42 + len) begin
        $display("  [FAIL] len=%0d: captured %0d bytes, expect %0d", len, ncap, 42 + len);
        errs = errs + 1;
      end else begin
        for (i = 0; i < 42 + len; i = i + 1) begin
          if (cap[i] !== exp[i]) begin
            $display("  [FAIL] len=%0d: byte[%0d]=%02x expect %02x", len, i, cap[i], exp[i]);
            errs = errs + 1;
            i = 42 + len;
          end
        end
      end
    end
  endtask

  // IP 头自校验：把捕获到的 20B 头按 16bit 累加（含校验和字段）应为 0xFFFF
  task automatic check_ip_cksum(input [15:0] len);
    reg [31:0] s;
    integer i;
    begin
      s = 0;
      for (i = 0; i < 20; i = i + 2) s = s + {cap[14+i], cap[15+i]};
      s = (s & 32'hFFFF) + (s >> 16);
      s = (s & 32'hFFFF) + (s >> 16);
      if (s[15:0] !== 16'hFFFF) begin
        $display("  [FAIL] len=%0d: IP checksum sum=%04x (expect FFFF)", len, s[15:0]);
        errs = errs + 1;
      end
    end
  endtask

  initial begin
    $display("=== tb_relay_tx ===");
    repeat (5) @(negedge clk);
    rst_n = 1;
    repeat (2) @(negedge clk);

    run_frame(16'd0,    0); check_ip_cksum(16'd0);
    run_frame(16'd1,    0); check_ip_cksum(16'd1);
    run_frame(16'd26,   0); check_ip_cksum(16'd26);
    run_frame(16'd100,  0); check_ip_cksum(16'd100);
    run_frame(16'd1496, 0); check_ip_cksum(16'd1496);
    run_frame(16'd100,  1);             // 背压

    // 超限：不发
    ncap = 0;
    @(negedge clk); plen = 16'd1497; start = 1;
    @(negedge clk); start = 0;
    repeat (60) @(negedge clk);
    if (!err_oversize) begin $display("  [FAIL] 1497: err_oversize not set"); errs = errs + 1; end
    if (ncap != 0)     begin $display("  [FAIL] 1497: emitted %0d bytes", ncap); errs = errs + 1; end
    if (err_short)     begin $display("  [FAIL] 1497: err_short set unexpectedly"); errs = errs + 1; end

    if (errs == 0) $display("P2_RELAY_TB: PASS");
    else           $display("P2_RELAY_TB: FAIL (%0d errors)", errs);
    $finish;
  end

  initial begin
    #2000000;
    $display("P2_RELAY_TB: FAIL (timeout)");
    $finish;
  end
endmodule
