//=============================================================================
// p2_relay_top.v — prj13 P2 v0.2 顶层集成封装（两个时钟域各自闭合，无新增 CDC）
//-----------------------------------------------------------------------------
// 职责：把三个已过单元仿真的 P2 单元件，按真实链路拓扑接成两条单向通路，
//   并把"生产者无反压"的两处（以太网 MAC 接收 / Aurora 解包）加上整帧粒度弹性
//   缓冲（p2_frame_buf），使二者之间不会出现半帧上电路。
//
// 两条通路（每块板同一份源码，A/B 只换参数）：
//
//   ① 转发：PC ─GE2─► gmii_rx ─► [p2_frame_buf] ─► ipv4_packet_extract
//              ─► local_steer 判决 == RELAY ? ─► IP 字节流 relay_data/relay_en
//              ─► 帧泵A 写侧 ─► 内存桥① ─► pack ─► Aurora TX ─► 光纤
//      （判决 != RELAY 的包在本地被**完整吞掉**，不产生输出字节）
//
//   ② 回程：光纤 ─► Aurora RX ─► unpack_data/unpack_en ─► [p2_frame_buf]
//              ─► eth_rewrap（只加 14 B 头，IP 包原样）─► lan_data/lan_en
//              ─► 内存桥② 写侧 ─► 帧泵B ─► RGMII TX ─► PC
//
// 为什么回程的 rewrap 放在**内存桥②之前**而不是帧泵B 之后：
//   eth_rewrap 在吐 14 B 头时 s_ready=0；帧泵B 的读侧没有反压口。放在泵B 之后
//   每次都要丢 14 字节。放在桥② 之前，帧泵B 拿到的已经是**完整以太帧**，
//   与 P1 的回程路径逐位同构（P1 的泵B 也是原样吐桥② 内容）。
//
// i_pkt_len 的接法（刻意 tie 0，见 eth_rewrap 语义）：
//   eth_rewrap 只用 i_pkt_len 算 tot_len；tot_len 只影响"是否补零到 60 B"与
//   结尾判据。把 i_pkt_len 钉 0 => tot_len=MIN_FRAME_LEN=60，于是
//     · IP 包 <46 B → 补零到 60 B（正确）
//     · IP 包 >=46 B → 到真实 eop 就结束、不补零（正确）
//   即线上字节完全正确；仅它自己报的 m_frame_len/o_len_err 在本集成里无意义
//   （因此不接、不判）。这样回程不需要"先收 4 B 头再算长度"的前置缓冲。
//
// 编码：Verilog-2001，两个时钟域各自单域逻辑，跨域只经过已有内存桥/帧泵。
//=============================================================================
`timescale 1ns / 1ps

module p2_relay_top #(
    parameter [47:0] BOARD_MAC = 48'h02_00_00_00_0A_01,   // 板 A；板 B 0B:01
    parameter [47:0] PEER_MAC  = 48'h00_00_00_00_00_00,   // ★对端 PC 的 MAC（跨板方向用）
parameter [47:0] PC_MAC    = 48'h00_00_00_00_00_00,   // ★2026-11-20 D1 修复：本板直连 PC 的网卡 MAC（出口 dst）
    parameter [31:0] BOARD_IP  = {8'd10,8'd10,8'd0,8'd11},// 板 A；板 B .12
    parameter [31:0] PEER_IP   = {8'd10,8'd10,8'd0,8'd2}, // 板 A 的对端 PC2；板 B .1
    parameter [31:0] PC_IP     = {8'd10,8'd10,8'd0,8'd1}, // 本板直连 PC；板 B .2
    parameter        PROXY_ARP_EN = 1'b0
)(
    //=====================================================================
    // 以太网域（gmii_rx_clk / eth_rxc，与 eth_ctrl/泵A 写侧同域）
    //=====================================================================
    input  wire        eth_clk,
    input  wire        eth_rst_n,
    // MAC 接收：字节 + dv（不反压，按线速到达）
    input  wire [7:0]  rx_data,
    input  wire        rx_dv,
    // 转发出口 → 帧泵A 写侧（en 的上升/下降界定一帧）
    output wire [7:0]  relay_data,
    output wire        relay_en,
    // 以太网域统计
    output wire [31:0] st_rx_frames,  st_rx_drop,   st_relay,  st_local, st_arp,
    output wire [31:0] st_drop_vlan,  st_drop_ipv6, st_drop_ethertype,
    output wire [31:0] st_drop_broadcast, st_drop_multicast, st_drop_unknown_dst,
    output wire [31:0] st_drop_oversize,  st_drop_bad_csum,  st_drop_truncated,
    output wire [31:0] st_drop_mac,
    //=====================================================================
    // Aurora / user 域（user_clk）
    //=====================================================================
    input  wire        aur_clk,
    input  wire        aur_rst_n,
    // 解包输出（IP 字节流，不反压）
    input  wire [7:0]  aur_data,
    input  wire        aur_en,
    // 回程出口 → 内存桥② 写侧（完整以太帧，en 的上升/下降界定一帧）
    output wire [7:0]  lan_data,
    output wire        lan_en,
    // Aurora 域统计
    output wire [31:0] st_aur_frames, st_aur_drop, st_lan_frames, st_aur_bad_v4,
    //=====================================================================
    // ★B2 入口缓冲暂停诊断（2026-11-27；全部 eth_clk / gmii_rx_clk 域）
    //---------------------------------------------------------------------
    // 为什么**不**用提取器 m_ready 做暂停：m_valid 是"状态机停在 S_SEND"的组合
    //   输出，拉低 m_ready 只让字节原地停住，下游仍按保持的 valid/EOP 逐拍消费
    //   ⇒ 重复转发/重复计数（EIF #18 明确列为陷阱）。
    // 本实现的暂停点选在**入口 RAM 与提取器之间**，两个信号同时门控：
    //   · u_rxbuf.rd_ready <- ext_s_ready & ~pause  （RAM 不推进，帧留在 bank）
    //   · u_ext.s_valid    <- rxbf_vld    & ~pause  （提取器看不到新字节）
    // 只停消费、不停生产：上游 al_dv 照常写入，两个 bank 先后占满，第三帧在写侧
    //   被整帧拒收并计入 o_wr_drop_cnt（p2_frame_buf 既有语义，不改）。
    // 默认 pause=0 时两路门控恒等透传，与生产版本逐位等价。
    //=====================================================================
    input  wire        dbg_pause_req,     // 暂停请求（异步，VIO 输出探针）
    output wire        dbg_pause,         // 同步+边沿锁存后的暂停态（0 = 生产语义）
    output wire [1:0]  dbg_bank_busy,     // 入口 RAM 两槽占用 {bank1,bank0}
    output wire        dbg_rx_sop_pulse,  // 入口帧边界：帧首字节（写侧 al_dv 上升）
    output wire        dbg_rx_eop_pulse,  // 入口帧边界：帧尾字节（写侧 al_dv 下降）
    output wire        dbg_rx_drop_pulse, // 入口整帧拒收脉冲（o_wr_drop_cnt 变化，1 拍）
    output wire        dbg_rxbf_vld,      // 入口 RAM 读侧 valid（原始）
    output wire        dbg_buf_rd_ready,  // 门控后送 RAM 的 rd_ready
    output wire        dbg_ext_s_ready    // 提取器原始 s_ready（未门控）
);

    //=====================================================================
    // ① 以太网域：整帧缓冲 → 提取 → 判决 → 转发出口
    //=====================================================================
    //=====================================================================
    // 前导码 / SFD 对齐（★2026-11-12 板上实测缺陷修复）
    //---------------------------------------------------------------------
    // 板上 `gmii_rxd/gmii_rx_dv` 的帧**从 7 B 前导码(0x55) + 1 B SFD(0xD5) 开始**，
    // 而不是从目的 MAC 开始 —— 官方栈自己就是靠跳这 8 B 工作的：
    //   rtl/udp/udp_rx.v:161 `if((gmii_rx_dv==1 && gmii_rxd==8'h55)) skip_en<=1`，
    //   :167 `if((cnt<6) && (gmii_rxd!=8'h55))`（校验 7 个 0x55），:169 `cnt==6` 后进 SFD。
    // 集成时把裸 `gmii_rxd` 直接喂给 p2_frame_buf ⇒ 侧带 eth_dst 变成 `55 55 55 55 55 55`、
    // eth_type 取到源 MAC 字节 ⇒ local_steer 判 DROP_MAC ⇒ relay_en 永不高 ⇒ 泵A 写侧
    // 计数恒 0（2026-11-12 板 A 单板那轮的实测现象，六点差分八点全 0）。
    //
    // 修法：**自适应**跳前导 —— 首字节是 0x55 才当前导处理（后面必须仍是 0x55，
    // 假前导概率极低），否则原样透传。这样既修板上形态，也不破坏"无前导"的仿真向量。
    // 修复后 `u_rxbuf` 收到的帧从**目的 MAC 第 1 字节**开始，与单元件契约一致。
    //=====================================================================
    localparam [1:0] PA_IDLE = 2'd0,   // 等帧首
                     PA_PRE  = 2'd1,   // 已见 0x55，数前导
                     PA_PASS = 2'd2;   // 透传（MAC 头起）
    reg [1:0] pa_st;
    reg [3:0] pa_cnt;                  // 已确认的 0x55 个数
    reg       al_dv;                   // 对齐后字节流 valid
    reg [7:0] al_data;

    always @(posedge eth_clk or negedge eth_rst_n) begin
        if (!eth_rst_n) begin
            pa_st <= PA_IDLE; pa_cnt <= 4'd0; al_dv <= 1'b0; al_data <= 8'd0;
        end else begin
            al_dv <= 1'b0;                         // 默认只高 1 拍
            case (pa_st)
                PA_IDLE: if (rx_dv) begin
                    if (rx_data == 8'h55) begin    // 疑似前导
                        pa_st <= PA_PRE; pa_cnt <= 4'd1;
                    end else begin                 // 无前导形态：从本字节开始透传
                        al_dv <= 1'b1; al_data <= rx_data; pa_st <= PA_PASS;
                    end
                end
                PA_PRE: if (!rx_dv) begin
                    pa_st <= PA_IDLE; pa_cnt <= 4'd0;   // 帧过短/假前导：丢弃
                end else if (rx_data == 8'h55) begin
                    if (pa_cnt == 4'd7) pa_st <= PA_PASS;  // 防御：>7 个 0x55
                    else                pa_cnt <= pa_cnt + 1'b1;
                end else begin
                    // 非 0x55 ⇒ 这就是 SFD(0xD5)：**丢掉本字节**，下一字节起才是 MAC 头
                    pa_st <= PA_PASS;
                end
                PA_PASS: if (rx_dv) begin
                    al_dv <= 1'b1; al_data <= rx_data;
                end else begin
                    pa_st <= PA_IDLE; pa_cnt <= 4'd0;   // 帧尾，准备下一帧
                end
                default: pa_st <= PA_IDLE;
            endcase
        end
    end

    //---------------------------------------------------------------------
    // ★B2 暂停控制：异步请求 -> 2FF 同步（异步复位清 0）-> 稳态后上升沿置位 /
    //   请求撤低清除。
    //   为什么还要 pause_mask：复位会把同步器本身清 0，若请求此时仍为高，
    //   同步后天然产生一次 0->1 的"假上升沿"，会把刚复位的设计又停住。
    //   pause_mask 在复位释放后屏蔽前 15 拍，只有**稳态之后**的真实上升沿才置位
    //   => 语义确定：复位后一律恢复默认（解除），要再暂停必须重新 0->1。
    //---------------------------------------------------------------------
    reg  [3:0] pause_mask;
    reg pause_s1, pause_s2, pause_s2_d;
    reg pause_q;
    always @(posedge eth_clk or negedge eth_rst_n) begin
        if (!eth_rst_n) begin
            pause_mask <= 4'd0;
            pause_s1 <= 1'b0; pause_s2 <= 1'b0; pause_s2_d <= 1'b0; pause_q <= 1'b0;
        end else begin
            if (!(&pause_mask)) pause_mask <= pause_mask + 4'd1;
            pause_s1   <= dbg_pause_req;
            pause_s2   <= pause_s1;
            pause_s2_d <= pause_s2;
            if (!pause_s2)                           pause_q <= 1'b0;  // 请求撤低 => 解除
            else if (!pause_s2_d && (&pause_mask))    pause_q <= 1'b1;  // 稳态上升沿 => 暂停
        end
    end
    wire pause = pause_q;
    assign dbg_pause = pause;

    // 入口帧边界（写侧 al_dv 的上升/下降沿，恰好 1 拍）
    reg al_dv_d;
    always @(posedge eth_clk or negedge eth_rst_n) begin
        if (!eth_rst_n) al_dv_d <= 1'b0;
        else            al_dv_d <= al_dv;
    end
    assign dbg_rx_sop_pulse =  al_dv & ~al_dv_d;
    assign dbg_rx_eop_pulse = ~al_dv &  al_dv_d;

    wire [7:0]  rxbf_data;
    wire        rxbf_vld, rxbf_sop, rxbf_eop, rxbf_rdy;
    wire [15:0] rxbf_wr_cnt, rxbf_drop_cnt, rxbf_rd_cnt;
    wire [1:0]  rxbf_busy;
    wire [47:0] rxbf_eth_dst;
    wire [15:0] rxbf_eth_type;

    p2_frame_buf #(.AW(11)) u_rxbuf (
        .clk            (eth_clk),
        .rst_n          (eth_rst_n),
        .wr_data        (al_data),
        .wr_en          (al_dv),
        .o_wr_frame_cnt (rxbf_wr_cnt),
        .o_wr_drop_cnt  (rxbf_drop_cnt),
        .rd_data        (rxbf_data),
        .rd_valid       (rxbf_vld),
        .rd_sop         (rxbf_sop),
        .rd_eop         (rxbf_eop),
        .rd_ready       (rxbf_rdy),
        .o_rd_frame_cnt (rxbf_rd_cnt),
        .o_rd_eth_dst   (rxbf_eth_dst),
        .o_rd_eth_type  (rxbf_eth_type),
        .o_bank_busy    (rxbf_busy)
    );

    // 一帧在缓冲侧完成（判决/ARP 计数的事件边界；不受上游丢帧影响）
    wire rx_frm_done = rxbf_vld & rxbf_rdy & rxbf_eop;

    // ★B2：入口 RAM 与提取器之间的暂停门控（见端口注释）
    //   ext_s_ready 是提取器的真实反压（S_VRD/S_SEND 期间为 0）；
    //   暂停时把它和 s_valid 一起压 0，RAM 与提取器**同拍**停住，字节原地保持。
    wire ext_s_ready;
    assign rxbf_rdy         = ext_s_ready & ~pause;
    assign dbg_buf_rd_ready = rxbf_rdy;
    assign dbg_ext_s_ready  = ext_s_ready;
    assign dbg_rxbf_vld     = rxbf_vld;
    assign dbg_bank_busy    = rxbf_busy;

    // 入口整帧拒收脉冲：p2_frame_buf 只在帧尾把 o_wr_drop_cnt +1，故计数变化即事件
    reg [15:0] rxbf_drop_d;
    always @(posedge eth_clk or negedge eth_rst_n) begin
        if (!eth_rst_n) rxbf_drop_d <= 16'd0;
        else            rxbf_drop_d <= rxbf_drop_cnt;
    end
    assign dbg_rx_drop_pulse = (rxbf_drop_cnt != rxbf_drop_d);

    // 提取器输出（IP 字节流 + 元数据）
    wire [7:0]  ex_data;
    wire        ex_vld, ex_rdy, ex_sop, ex_eop;
    wire [31:0] ex_ip_src, ex_ip_dst;
    wire [15:0] ex_totlen, ex_ip_id, ex_csum;
    wire [7:0]  ex_proto, ex_ttl, ex_tos;
    wire [3:0]  ex_ihl;
    wire [2:0]  ex_flags;
    wire [12:0] ex_frag_off;
    wire        ex_is_frag;
    wire        ex_frame_pulse, ex_parse_pulse, ex_drop_pulse;
    wire [3:0]  ex_drop_reason;

    ipv4_packet_extract #(
        .MAX_IP_LEN (16'd1500),
        .BOARD_MAC  (BOARD_MAC)
    ) u_ext (
        .clk           (eth_clk),
        .rst_n         (eth_rst_n),
        .s_valid       (rxbf_vld & ~pause),
        .s_ready       (ext_s_ready),
        .s_data        (rxbf_data),
        .s_sop         (rxbf_sop),
        .s_eop         (rxbf_eop),
        .m_valid       (ex_vld),
        .m_ready       (1'b1),          // 下游恒收：非 RELAY 的字节在这里被吞掉
        .m_data        (ex_data),
        .m_sop         (ex_sop),
        .m_eop         (ex_eop),
        .m_ip_src      (ex_ip_src),
        .m_ip_dst      (ex_ip_dst),
        .m_total_len   (ex_totlen),
        .m_ip_id       (ex_ip_id),
        .m_csum        (ex_csum),
        .m_proto       (ex_proto),
        .m_ttl         (ex_ttl),
        .m_tos         (ex_tos),
        .m_ihl         (ex_ihl),
        .m_ip_flags    (ex_flags),
        .m_frag_off    (ex_frag_off),
        .m_is_fragment (ex_is_frag),
        .o_frame_pulse (ex_frame_pulse),
        .o_parse_pulse (ex_parse_pulse),
        .o_drop_pulse  (ex_drop_pulse),
        .o_drop_reason (ex_drop_reason)
    );

    // ---- 判决（组合；RELAY 才输出）----
    //   eth_dst/eth_type 来自**缓冲的侧带**（跟帧走，不会被下一帧覆盖）
    wire [2:0] dec;
    wire [3:0] dec_reason;

    local_steer #(
        .BOARD_MAC    (BOARD_MAC),
        .BOARD_IP     (BOARD_IP),
        .PEER_IP      (PEER_IP),
        .PC_IP        (PC_IP),
        .PROXY_ARP_EN (PROXY_ARP_EN)
    ) u_steer (
        .clk             (eth_clk),
        .rst_n           (eth_rst_n),
        .i_eth_dst       (rxbf_eth_dst),
        .i_eth_type      (rxbf_eth_type),
        .i_ip_dst        (ex_ip_dst),
        .i_ip_total_len  (ex_totlen),
        .i_ip_hdr_ok     (ex_vld),        // 提取器只在结构合法时出字节
        .i_frame_len     (16'd0),          // 预留口：local_steer 当前不用帧长（判决只吃
                                           // eth_dst/eth_type/ip_dst/ip_hdr_ok）。★若将来
                                           // 在 local_steer 里加长度相关检查，必须接真实
                                           // 帧长（p2_frame_buf 需新增 o_rd_len），不能沿用 0。
        .o_decision      (dec),
        .o_drop_reason   (dec_reason),
        .i_frame_pulse   (rx_frm_done),
        .i_relay_pulse   (ex_vld & ex_eop & (dec == 3'd2)),
        .i_local_pulse   (ex_vld & ex_eop & (dec == 3'd1)),
        .i_arp_pulse     (rx_frm_done & (rxbf_eth_type == 16'h0806)),
        .i_drop_pulse    (ex_drop_pulse),
        .i_drop_reason   (ex_drop_reason),
        .o_cnt_rx_frames (st_rx_frames),
        .o_cnt_relay     (st_relay),
        .o_cnt_local     (st_local),
        .o_cnt_arp       (st_arp),
        .o_cnt_drop_vlan        (st_drop_vlan),
        .o_cnt_drop_ipv6        (st_drop_ipv6),
        .o_cnt_drop_ethertype   (st_drop_ethertype),
        .o_cnt_drop_broadcast   (st_drop_broadcast),
        .o_cnt_drop_multicast   (st_drop_multicast),
        .o_cnt_drop_unknown_dst (st_drop_unknown_dst),
        .o_cnt_drop_oversize    (st_drop_oversize),
        .o_cnt_drop_bad_csum    (st_drop_bad_csum),
        .o_cnt_drop_truncated   (st_drop_truncated),
        .o_cnt_drop_mac         (st_drop_mac)
    );

    // 转发出口：只有 RELAY 的包出字节；其余被 m_ready=1 吞掉（零泄漏语义由
    // 单元件保证，这里只做门控）
    assign relay_data = ex_data;
    assign relay_en   = ex_vld & (dec == 3'd2);

    // 缓冲丢弃计数（整帧丢，不是半帧）
    assign st_rx_drop = {16'd0, rxbf_drop_cnt};

    //=====================================================================
    // ② Aurora 域：整帧缓冲 → 重加以太网头 → 内存桥② 写侧
    //=====================================================================
    wire [7:0]  abf_data;
    wire        abf_vld, abf_sop, abf_eop, abf_rdy;
    wire [15:0] abf_wr_cnt, abf_drop_cnt, abf_rd_cnt;
    wire [1:0]  abf_busy;

    p2_frame_buf #(.AW(11)) u_aurbuf (
        .clk            (aur_clk),
        .rst_n          (aur_rst_n),
        .wr_data        (aur_data),
        .wr_en          (aur_en),
        .o_wr_frame_cnt (abf_wr_cnt),
        .o_wr_drop_cnt  (abf_drop_cnt),
        .rd_data        (abf_data),
        .rd_valid       (abf_vld),
        .rd_sop         (abf_sop),
        .rd_eop         (abf_eop),
        .rd_ready       (abf_rdy),
        .o_rd_frame_cnt (abf_rd_cnt),
        .o_rd_eth_dst   (),                 // 回程不需要判决，侧带不接
        .o_rd_eth_type  (),
        .o_bank_busy    (abf_busy)
    );

    wire [7:0]  wp_data;
    wire        wp_vld, wp_sop, wp_eop, wp_len_err;
    wire [15:0] wp_frame_len;
    reg  [31:0] bad_v4_cnt;

    always @(posedge aur_clk or negedge aur_rst_n) begin
        if (!aur_rst_n) bad_v4_cnt <= 32'd0;
        else if (abf_vld & abf_rdy & abf_sop & (abf_data[7:4] != 4'h4))
            bad_v4_cnt <= bad_v4_cnt + 32'd1;
    end

    eth_rewrap #(
        .SRC_MAC       (BOARD_MAC),
        .DST_MAC       (PC_MAC),   // ★2026-11-20 D1 修复：出口帧发给本板直连 PC，用 PC_MAC（原为 PEER_MAC，接反）
        .MIN_FRAME_LEN (16'd60)
    ) u_rewrap (
        .clk         (aur_clk),
        .rst_n       (aur_rst_n),
        .s_valid     (abf_vld),
        .s_ready     (abf_rdy),
        .s_data      (abf_data),
        .s_sop       (abf_sop),
        .s_eop       (abf_eop),
        .i_pkt_len   (16'd0),           // 见文件头：MIN_FRAME_LEN 决定补零
        .m_valid     (wp_vld),
        .m_ready     (1'b1),            // 桥② 写侧无反压（满则整帧拒收+计数）
        .m_data      (wp_data),
        .m_sop       (wp_sop),
        .m_eop       (wp_eop),
        .m_frame_len (wp_frame_len),
        .o_len_err   (wp_len_err)
    );

    assign lan_data = wp_data;
    assign lan_en   = wp_vld;

    assign st_aur_frames = {16'd0, abf_wr_cnt};
    assign st_aur_drop   = {16'd0, abf_drop_cnt};
    assign st_lan_frames = {16'd0, abf_rd_cnt};
    assign st_aur_bad_v4 = bad_v4_cnt;

endmodule
