`timescale 1ns/1ps
// =============================================================================
// tb_local_steer.sv — prj12 P2 候选件③ 单元 TB（分流判决表）
// 判据: 8 类输入 -> cls/is_local/is_relay/is_drop 全表一致
//   1 ARP                      -> LOCAL_ARP
//   2 IPv4 ICMP                -> LOCAL_ICMP
//   3 UDP 到本板 1235          -> LOCAL_CMD
//   4 UDP 到任意地址 1234      -> RELAY
//   5 UDP 到本板其它端口       -> LOCAL_STACK
//   6 UDP 到其它地址其它端口   -> DROP
//   7 IPv4 其它协议(TCP=6)     -> DROP
//   8 非 IPv4/ARP (0x88B5)     -> DROP
// 结束: 打印 P2_STEER_TB: PASS/FAIL
// =============================================================================
module tb_local_steer;

  localparam [31:0] BOARD_IP = {8'd192, 8'd168, 8'd1, 8'd10};
  localparam [2:0]  CLS_DROP = 3'd0, CLS_ARP = 3'd1, CLS_ICMP = 3'd2,
                    CLS_CMD = 3'd3, CLS_STACK = 3'd4, CLS_RELAY = 3'd5;

  reg  [15:0] eth_type = 0;
  reg  [7:0]  ip_proto = 0;
  reg  [31:0] dst_ip   = 0;
  reg  [15:0] dst_port = 0;

  wire [2:0] cls;
  wire       is_local, is_relay, is_drop;

  local_steer dut (
    .eth_type(eth_type), .ip_proto(ip_proto),
    .dst_ip(dst_ip), .dst_port(dst_port),
    .cls(cls), .is_local(is_local), .is_relay(is_relay), .is_drop(is_drop)
  );

  integer errs = 0;

  task automatic check(input [15:0] et, input [7:0] proto, input [31:0] dip,
                       input [15:0] dport, input [2:0] exp_cls);
    begin
      eth_type = et; ip_proto = proto; dst_ip = dip; dst_port = dport;
      #1;
      if (cls !== exp_cls) begin
        $display("  [FAIL] et=%04x proto=%0d dip=%08x dport=%0d -> cls=%0d expect %0d",
                 et, proto, dip, dport, cls, exp_cls);
        errs = errs + 1;
      end
      if (is_local !== (exp_cls == CLS_ARP || exp_cls == CLS_ICMP ||
                        exp_cls == CLS_CMD || exp_cls == CLS_STACK)) begin
        $display("  [FAIL] is_local mismatch at cls=%0d", exp_cls); errs = errs + 1;
      end
      if (is_relay !== (exp_cls == CLS_RELAY)) begin
        $display("  [FAIL] is_relay mismatch at cls=%0d", exp_cls); errs = errs + 1;
      end
      if (is_drop !== (exp_cls == CLS_DROP)) begin
        $display("  [FAIL] is_drop mismatch at cls=%0d", exp_cls); errs = errs + 1;
      end
    end
  endtask

  initial begin
    $display("=== tb_local_steer ===");
    check(16'h0806, 8'd0,  32'h0000_0000, 16'd0,    CLS_ARP);
    check(16'h0800, 8'd1,  32'hC0A8_010A, 16'd0,    CLS_ICMP);
    check(16'h0800, 8'd17, 32'hC0A8_010A, 16'd1235, CLS_CMD);
    check(16'h0800, 8'd17, 32'hC0A8_0166, 16'd1234, CLS_RELAY);   // 目的不是本板也转发
    check(16'h0800, 8'd17, 32'hC0A8_010A, 16'd9999, CLS_STACK);
    check(16'h0800, 8'd17, 32'hC0A8_0166, 16'd9999, CLS_DROP);
    check(16'h0800, 8'd6,  32'hC0A8_010A, 16'd80,   CLS_DROP);
    check(16'h88B5, 8'd0,  32'h0000_0000, 16'd0,    CLS_DROP);

    if (errs == 0) $display("P2_STEER_TB: PASS");
    else           $display("P2_STEER_TB: FAIL (%0d errors)", errs);
    $finish;
  end
endmodule
