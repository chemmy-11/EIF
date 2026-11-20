// =============================================================================
// tb_link_loss_monitor.sv — link_loss_monitor 回归（13 用例）
//
// 溯源：原型见 C:/Users/15266/AppData/Local/Temp/fifo_b1_decision_20261120/
//       tb_link_monitor.sv（2026-11-20，xsim.log: RESULT: PASS 13）。
//       本文件为落库版本，仅把 DUT 实例名 link_monitor → link_loss_monitor。
//
// 跑法（ASCII 工作目录）:
//   xvlog D:/Xilinx/Vivado/2023.1/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv \
//         <rtl>/link_loss_monitor.v sim/tb_link_loss_monitor.sv \
//         D:/Xilinx/Vivado/2023.1/data/verilog/src/glbl.v
//   xelab -debug typical tb glbl -s link_loss_monitor_sim
//   xsim link_loss_monitor_sim -runall
//   期望末尾: RESULT: PASS 13
//
// 覆盖：无光启动 / 未校准 / 首个合格 up / 1 个 user 周期脉冲 5 个相位 /
//       user 时钟掉线期间 / 恢复后跨重连 / 重复掉线 /
//       UI 时钟暂停期间捕获、恢复后锁存 / UI 复位后清零并重新 armed
// =============================================================================
module tb;
    timeunit 1ns;
    timeprecision 1ps;
    logic ui_clk = 0, user_clk = 0, user_clock_en = 1, ui_clock_en = 1;
    logic ui_rst_n = 0, calib = 0, aurora_rst = 1;
    wire armed, lost, down;
    integer n, passed = 0;
    always #5 if (ui_clock_en) ui_clk = ~ui_clk;
    always #2 if (user_clock_en) user_clk = ~user_clk;
    link_loss_monitor dut(ui_clk, ui_rst_n, calib, aurora_rst, armed, lost, down);

    task check(input bit goal, input string name);
        if (!goal) $fatal(1, "FAIL %s", name);
        $display("PASS %s", name);
        passed++;
    endtask

    task restart_unlinked;
        @(negedge ui_clk);
        ui_rst_n = 0;
        calib = 0;
        aurora_rst = 1;
        repeat (10) @(negedge ui_clk);
        ui_rst_n = 1;
        calib = 1;
        repeat (10) @(negedge ui_clk);
    endtask

    task link_up;
        @(negedge ui_clk);
        aurora_rst = 0;
        repeat (10) @(negedge ui_clk);
    endtask

    initial begin
        #150;
        restart_unlinked();
        check(!armed && !lost && down, "dark start");
        aurora_rst = 0;
        calib = 0;
        repeat (10) @(negedge ui_clk);
        check(!armed && !lost && !down, "uncalibrated link");
        calib = 1;
        link_up();
        check(armed && !lost && !down, "first qualified up");

        for (n = 1; n <= 5; n++) begin
            restart_unlinked();
            link_up();
            #(n);
            aurora_rst = 1;
            #4;
            aurora_rst = 0;
            repeat (10) @(negedge ui_clk);
            check(armed && lost && !down, $sformatf("one-user-period pulse phase=%0d", n));
        end

        restart_unlinked();
        link_up();
        @(negedge user_clk);
        aurora_rst = 1;
        user_clock_en = 0;
        repeat (4) @(negedge ui_clk);
        check(armed && lost && down, "user clock stopped during down");
        aurora_rst = 0;
        repeat (10) @(negedge ui_clk);
        check(armed && lost && !down, "sticky across recovery");
        aurora_rst = 1;
        repeat (10) @(negedge ui_clk);
        aurora_rst = 0;
        repeat (10) @(negedge ui_clk);
        check(armed && lost && !down, "repeat flap");

        restart_unlinked();
        link_up();
        @(negedge ui_clk);
        ui_clock_en = 0;
        #1; aurora_rst = 1;
        #4; aurora_rst = 0;
        #30; ui_clock_en = 1;
        repeat (10) @(negedge ui_clk);
        check(armed && lost && !down, "capture while UI clock paused, latch after resume");
        restart_unlinked();
        link_up();
        check(armed && !lost && !down, "cleared and rearmed after UI reset");
        $display("RESULT: PASS %0d", passed);
        $finish;
    end
endmodule
