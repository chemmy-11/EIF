// =============================================================================
// link_loss_monitor.v — 链路丢失粘滞告警（决策 C 的观测单元）
//
// 用途：把「本板上电并成功建链之后，发生过一次数据面链路复位」这件事变成
//       一个可通过 JTAG 读到的粘滞位。原来 ch_up_evt_cnt 由 aurora_rst 清零，
//       闪断证据被自己抹掉（aurora_mem_bridge.v:1457-1467），运维无法判定
//       是否需要整板重烧。
//
// 语义（与决策文档 §4.1 一致）:
//   · link_armed_ui        首次合格建链（calib=1 且链路已起）后置 1，UI 复位清零
//   · link_lost_sticky_ui  已 armed 之后出现 link_down 即置 1，**只有 ui_rst_n 能清**
//                          （掉电 / PL 重配置 / MIG UI 复位）；不提供软件清旗
//   · link_down_ui         aurora_rst | ~ui_rst_n 经异步置位、UI 域展宽后的电平
//
// 为什么这样取：
//   1) 源复位用 xpm_cdc_async_rst（异步断言 / 同步释放），异步断言保留窄脉冲、
//      不被 UI 时钟漏采；DEST_SYNC_FF=4 让释放经四级 UI 拍。
//   2) 展宽后的电平再过两级 ASYNC_REG（初值 2'b11），粘滞采样不直接用异步输出。
//   3) 两级都初值为「down」⇒ 上电早期显示为未就绪而不是误报。
//
// 溯源：本模块是 2026-11-20 离线原型的逐行移植（原型模块名 link_monitor，
//       位于 C:/Users/15266/AppData/Local/Temp/fifo_b1_decision_20261120/
//       tb_link_monitor.sv，xsim 日志 RESULT: PASS 13）。此处仅改名为
//       link_loss_monitor 以对齐决策文档 §4.1，逻辑未改。
//       回归：sim/tb_link_loss_monitor.sv（13 用例）。
//
// 时钟域：ui_clk（MIG 用户时钟，自由运行，不随 Aurora 链路掉线而停）
// 依赖：XPM_CDC 库（xpm_cdc_async_rst）
// =============================================================================
module link_loss_monitor (
    input  wire ui_clk,
    input  wire ui_rst_n,
    input  wire calib,                 // init_calib_complete（ui_clk 域）
    input  wire aurora_rst,            // = ~sys_rst_n | ~link_ok（user 域电平）
    output reg  link_armed_ui,
    output reg  link_lost_sticky_ui,
    output wire link_down_ui
);

    wire                     link_down_stretched_ui;
    (* ASYNC_REG = "TRUE" *) reg [1:0] down_sync_ui;

    initial begin
        link_armed_ui       = 1'b0;
        link_lost_sticky_ui = 1'b0;
        down_sync_ui        = 2'b11;   // 上电初值 = down（未就绪），避免误报
    end

    // 异步断言（窄脉冲也留得住）/ 同步释放（经 4 级 UI 拍展宽）
    xpm_cdc_async_rst #(
        .DEST_SYNC_FF   (4),
        .INIT_SYNC_FF   (1),
        .RST_ACTIVE_HIGH(1)
    ) u_capture (
        .src_arst  (aurora_rst | ~ui_rst_n),
        .dest_clk  (ui_clk),
        .dest_arst (link_down_stretched_ui)
    );

    // 再打两拍，粘滞采样只用同步后的电平
    always @(posedge ui_clk) begin
        down_sync_ui <= {down_sync_ui[0], link_down_stretched_ui};
    end
    assign link_down_ui = down_sync_ui[1];

    // armed / sticky：只用 ui_rst_n 清零（无软件清旗、无重连清旗）
    always @(posedge ui_clk) begin
        if (!ui_rst_n) begin
            link_armed_ui       <= 1'b0;
            link_lost_sticky_ui <= 1'b0;
        end else begin
            if (calib && !link_down_ui)
                link_armed_ui <= 1'b1;
            if (link_armed_ui && link_down_ui)
                link_lost_sticky_ui <= 1'b1;
        end
    end

endmodule
