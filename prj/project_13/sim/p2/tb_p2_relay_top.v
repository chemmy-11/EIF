//=============================================================================
// tb_p2_relay_top.v  --  prj13 P2 集成层 TB（p2_relay_top v2）
//-----------------------------------------------------------------------------
// 被测件：rtl/p2/p2_relay_top.v（v2）+ 其内部 p2_frame_buf(v2) / 三件套
// 双时钟：eth_clk 125 MHz(8 ns) 与 aur_clk 200 MHz(5 ns) —— 故意不同频，
//         跨域接错（比如把 eth 域信号接进 aur 域）会立刻表现为帧错位/计数不对。
//
// 用例（Lead 指定，全部逐字节断言，不是只数长度）：
//   I01 relay_1472            1472 B IP(dst=PEER_IP) → relay 字节逐字节相同、=1472、st_relay=1
//                             另断言 relay_en 的上升/下降**精确落在 IP 包首/尾字节**
//   I02 local_swallowed       dst=BOARD_IP → relay 零字节、st_local=1、st_relay 不变
//   I03 arp_no_cross          广播 ARP → relay 零字节、st_arp=1、st_drop_ethertype=0
//   I04 back_to_back          3 帧（帧间仅 1 拍空档）→ **守恒判据**：
//                             relayed + st_rx_drop == 3，且已转出的帧逐字节正确
//                             （2-bank 整帧缓冲 + 暂存转发 ⇒ 满速背靠背有吞吐上限，
//                               实测 relayed 可能 < 3，属已文档化的已知限制）
//   I10 long_back_to_back     3 × **1472 B 满帧**背靠背（帧间 1 拍）→ 同上守恒判据；
//                             这是"2-bank + 暂存转发"吞吐上限真正会顶到的地方
//                             （I04 的 142 B 短帧压不到上限），打 [INFO] I10 实测值
//   I06 rewrap_aur_1472       aur 1472 B IP → lan = 14 B 头 + 原包逐字节，总长 1486
//   I07 rewrap_aur_26_pad     aur 26 B IP → lan 60 B，第 40..59 字节全 0
//   I08 counters_clean        两域计数器逐一比对
//   I09 sideband_follows_frame 背靠背「广播 ARP」+「BOARD_MAC/0x0800/PEER_IP」
//                             → 第 2 帧必须被正确转发（旧旁路嗅探器会把它判成 ARP）
//
// 判据行：P2_RELAY_TB: PASS=<n> FAIL=<m>
// 编码：纯 Verilog-2001（无 logic/always_ff/interface/包）。
//=============================================================================
`timescale 1ns / 1ps

module tb_p2_relay_top;

    //=========================================================================
    // 参数（板 A：handbook §8 的 10.10.0.x）
    //=========================================================================
    localparam [47:0] BOARD_MAC   = 48'h02_00_00_00_0A_01;
    localparam [47:0] PEER_MAC    = 48'hAA_BB_CC_DD_EE_02;   // 板 A 对端 PC2 实际 MAC
    localparam [47:0] PC1_MAC     = 48'hAA_BB_CC_DD_EE_01;
    localparam [47:0] BCAST_MAC   = 48'hFFFF_FFFF_FFFF;

    localparam [31:0] BOARD_IP    = {8'd10, 8'd10, 8'd0, 8'd11};
    localparam [31:0] PEER_IP     = {8'd10, 8'd10, 8'd0, 8'd2};
    localparam [31:0] PC1_IP      = {8'd10, 8'd10, 8'd0, 8'd1};

    //=========================================================================
    // 双时钟 / 复位
    //=========================================================================
    reg eth_clk, aur_clk;
    reg eth_rst_n, aur_rst_n;
    initial eth_clk = 1'b0;
    initial aur_clk = 1'b0;
    always #4 eth_clk = ~eth_clk;     // 125 MHz
    always #2.5 aur_clk = ~aur_clk;   // 200 MHz

    //=========================================================================
    // DUT: p2_relay_top
    //=========================================================================
    reg  [7:0] rx_data;
    reg        rx_dv;
    wire [7:0] relay_data;
    wire       relay_en;

    wire [31:0] st_rx_frames, st_rx_drop, st_relay, st_local, st_arp;
    wire [31:0] st_drop_vlan, st_drop_ipv6, st_drop_ethertype;
    wire [31:0] st_drop_broadcast, st_drop_multicast, st_drop_unknown_dst;
    wire [31:0] st_drop_oversize, st_drop_bad_csum, st_drop_truncated, st_drop_mac;

    reg  [7:0] aur_data;
    reg        aur_en;
    wire [7:0] lan_data;
    wire       lan_en;

    wire [31:0] st_aur_frames, st_aur_drop, st_lan_frames, st_aur_bad_v4;

    p2_relay_top #(
        .BOARD_MAC    (BOARD_MAC),
        .PEER_MAC     (PEER_MAC),
        .BOARD_IP     (BOARD_IP),
        .PEER_IP      (PEER_IP),
        .PC_IP        (PC1_IP),
        .PROXY_ARP_EN (1'b0)
    ) dut (
        .eth_clk   (eth_clk),
        .eth_rst_n (eth_rst_n),
        .rx_data   (rx_data),
        .rx_dv     (rx_dv),
        .relay_data(relay_data),
        .relay_en  (relay_en),
        .st_rx_frames        (st_rx_frames),
        .st_rx_drop          (st_rx_drop),
        .st_relay            (st_relay),
        .st_local            (st_local),
        .st_arp              (st_arp),
        .st_drop_vlan        (st_drop_vlan),
        .st_drop_ipv6        (st_drop_ipv6),
        .st_drop_ethertype   (st_drop_ethertype),
        .st_drop_broadcast   (st_drop_broadcast),
        .st_drop_multicast   (st_drop_multicast),
        .st_drop_unknown_dst (st_drop_unknown_dst),
        .st_drop_oversize    (st_drop_oversize),
        .st_drop_bad_csum    (st_drop_bad_csum),
        .st_drop_truncated   (st_drop_truncated),
        .st_drop_mac         (st_drop_mac),
        .aur_clk   (aur_clk),
        .aur_rst_n (aur_rst_n),
        .aur_data  (aur_data),
        .aur_en    (aur_en),
        .lan_data  (lan_data),
        .lan_en    (lan_en),
        .st_aur_frames (st_aur_frames),
        .st_aur_drop   (st_aur_drop),
        .st_lan_frames (st_lan_frames),
        .st_aur_bad_v4 (st_aur_bad_v4)
    );

    //=========================================================================
    // 工作缓冲 / 期望
    //=========================================================================
    reg [7:0] wb [0:4095];          // rx 用：0..13 是以太头，14.. 是 IP 包
                                    // aur 用：0.. 就是 IP 包本体
    reg [7:0] exp_lan [0:4095];
    integer   exp_lan_len;

    //=========================================================================
    // relay 侧捕获（eth 域）：en 的上升/下降 = 帧边界
    //=========================================================================
    reg [7:0] rc [0:8191];
    integer   r_total;              // 累计高电平拍数（含所有帧）
    integer   r_len;                // 当前帧已捕获字节
    integer   r_frames;             // 完成的帧数
    integer   r_frame_len [0:31];   // 每帧长度
    reg       r_in_frame;

    always @(posedge eth_clk) begin
        if (relay_en === 1'b1) begin
            if (!r_in_frame) r_in_frame = 1'b1;
            rc[r_total] = relay_data;
            r_total     = r_total + 1;
            r_len       = r_len + 1;
        end else begin
            if (r_in_frame) begin
                r_in_frame            = 1'b0;
                r_frame_len[r_frames] = r_len;
                r_frames              = r_frames + 1;
                r_len                 = 0;
            end
        end
    end

    //=========================================================================
    // lan 侧捕获（aur 域）：en 的上升/下降 = 帧边界
    //=========================================================================
    reg [7:0] lc [0:8191];
    integer   l_total;
    integer   l_len;
    integer   l_frames;
    integer   l_frame_len [0:31];
    reg       l_in_frame;

    always @(posedge aur_clk) begin
        if (lan_en === 1'b1) begin
            if (!l_in_frame) l_in_frame = 1'b1;
            lc[l_total] = lan_data;
            l_total     = l_total + 1;
            l_len       = l_len + 1;
        end else begin
            if (l_in_frame) begin
                l_in_frame            = 1'b0;
                l_frame_len[l_frames] = l_len;
                l_frames              = l_frames + 1;
                l_len                 = 0;
            end
        end
    end

    //=========================================================================
    // 参考模型
    //=========================================================================
    integer m_rx, m_relay, m_local, m_arp, m_rxdrop;
    integer m_dvlan, m_dipv6, m_detype, m_dbcast, m_dmcast, m_dunk;
    integer m_dover, m_dcsum, m_dtrunc, m_dmac;
    integer m_aurf, m_aurd, m_lanf, m_badv4;

    integer pass_cnt, fail_cnt;
    reg     chk_fail;

    //=========================================================================
    // 工具 task
    //=========================================================================
    task req;
        input            cond;
        input [8*72-1:0] what;
        begin
            if (!cond) begin
                chk_fail = 1'b1;
                $display("  [DET] %0s", what);
            end
        end
    endtask

    task end_case;
        input [8*72-1:0] nm;
        begin
            if (chk_fail) begin
                fail_cnt = fail_cnt + 1;
                $display("[FAIL] %0s", nm);
            end else begin
                pass_cnt = pass_cnt + 1;
                $display("[PASS] %0s", nm);
            end
            chk_fail = 1'b0;
        end
    endtask

    task wait_eth;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(negedge eth_clk);
        end
    endtask

    task wait_aur;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(negedge aur_clk);
        end
    endtask

    //---------------------------------------------------------------------
    // IP 头构造（放在 wb 的 base 偏移处）+ ones'-complement 校验和
    //---------------------------------------------------------------------
    task ip_csum_at;
        input integer base;
        input [3:0]   ihl;
        integer n, k;
        reg [31:0] s;
        reg [15:0] f;
        begin
            wb[base + 10] = 8'h00;
            wb[base + 11] = 8'h00;
            n = ihl * 2;
            s = 32'd0;
            for (k = 0; k < n; k = k + 1) begin
                s = s + {16'd0, wb[base + 2*k], wb[base + 2*k + 1]};
            end
            while (s[31:16] != 16'd0) begin
                s = {16'd0, s[15:0]} + {16'd0, s[31:16]};
            end
            f = ~s[15:0];
            wb[base + 10] = f[15:8];
            wb[base + 11] = f[7:0];
        end
    endtask

    task ip_hdr_at;
        input integer base;
        input [3:0]   ihl;
        input [15:0]  tot_len;
        input [7:0]   proto;
        input [7:0]   ttl;
        input [7:0]   tos;
        input [2:0]   flags;
        input [12:0]  frag_off;
        input [31:0]  src_ip;
        input [31:0]  dst_ip;
        input [15:0]  ip_id;
        integer k;
        begin
            wb[base + 0]  = {4'h4, ihl};
            wb[base + 1]  = tos;
            wb[base + 2]  = tot_len[15:8];
            wb[base + 3]  = tot_len[7:0];
            wb[base + 4]  = ip_id[15:8];
            wb[base + 5]  = ip_id[7:0];
            wb[base + 6]  = {flags, frag_off[12:8]};
            wb[base + 7]  = frag_off[7:0];
            wb[base + 8]  = ttl;
            wb[base + 9]  = proto;
            wb[base + 10] = 8'h00;
            wb[base + 11] = 8'h00;
            wb[base + 12] = src_ip[31:24];
            wb[base + 13] = src_ip[23:16];
            wb[base + 14] = src_ip[15:8];
            wb[base + 15] = src_ip[7:0];
            wb[base + 16] = dst_ip[31:24];
            wb[base + 17] = dst_ip[23:16];
            wb[base + 18] = dst_ip[15:8];
            wb[base + 19] = dst_ip[7:0];
            for (k = base + 20; k < (base + ihl*4); k = k + 1) wb[k] = 8'h01;
            ip_csum_at(base, ihl);
        end
    endtask

    task eth_hdr_at;
        input [47:0] dmac;
        input [47:0] smac;
        input [15:0] etype;
        begin
            wb[0] = dmac[47:40]; wb[1] = dmac[39:32]; wb[2] = dmac[31:24];
            wb[3] = dmac[23:16]; wb[4] = dmac[15:8];  wb[5] = dmac[7:0];
            wb[6] = smac[47:40]; wb[7] = smac[39:32]; wb[8] = smac[31:24];
            wb[9] = smac[23:16]; wb[10] = smac[15:8]; wb[11] = smac[7:0];
            wb[12] = etype[15:8]; wb[13] = etype[7:0];
        end
    endtask

    //---------------------------------------------------------------------
    // 驱动：以太侧（rx_dv 的上升/下降界定一帧）
    //   gap_after=1 时在帧尾后插 1 拍空档（背靠背最紧形态）
    //---------------------------------------------------------------------
    task rx_frame;
        input integer len;
        input integer gap_after;
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                @(negedge eth_clk);
                rx_dv   = 1'b1;
                rx_data = wb[i];
            end
            if (gap_after != 0) begin
                @(negedge eth_clk);
                rx_dv   = 1'b0;
                rx_data = 8'd0;
            end
        end
    endtask

    // 清掉帧尾（结束一串背靠背）
    task rx_idle;
        input integer n;
        integer i;
        begin
            @(negedge eth_clk);
            rx_dv   = 1'b0;
            rx_data = 8'd0;
            for (i = 1; i < n; i = i + 1) @(negedge eth_clk);
        end
    endtask

    // 驱动：Aurora 侧（aur_en 的上升/下降界定一帧）
    task aur_frame;
        input integer len;
        input integer gap_after;
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                @(negedge aur_clk);
                aur_en   = 1'b1;
                aur_data = wb[i];
            end
            if (gap_after != 0) begin
                @(negedge aur_clk);
                aur_en   = 1'b0;
                aur_data = 8'd0;
            end
        end
    endtask

    task aur_idle;
        input integer n;
        integer i;
        begin
            @(negedge aur_clk);
            aur_en   = 1'b0;
            aur_data = 8'd0;
            for (i = 1; i < n; i = i + 1) @(negedge aur_clk);
        end
    endtask

    //---------------------------------------------------------------------
    // 期望 lan 帧：14 B 头(dst=PEER_MAC, src=BOARD_MAC, 0x0800) + IP + 补零
    //---------------------------------------------------------------------
    task build_exp_lan;
        input integer total_len;       // IP 包字节数（wb[0..total_len-1]）
        integer i, plen;
        begin
            exp_lan[0] = PEER_MAC[47:40]; exp_lan[1] = PEER_MAC[39:32];
            exp_lan[2] = PEER_MAC[31:24]; exp_lan[3] = PEER_MAC[23:16];
            exp_lan[4] = PEER_MAC[15:8];  exp_lan[5] = PEER_MAC[7:0];
            exp_lan[6] = BOARD_MAC[47:40]; exp_lan[7] = BOARD_MAC[39:32];
            exp_lan[8] = BOARD_MAC[31:24]; exp_lan[9] = BOARD_MAC[23:16];
            exp_lan[10] = BOARD_MAC[15:8]; exp_lan[11] = BOARD_MAC[7:0];
            exp_lan[12] = 8'h08;
            exp_lan[13] = 8'h00;
            for (i = 0; i < total_len; i = i + 1) exp_lan[14 + i] = wb[i];
            plen = 14 + total_len;
            if (plen < 60) begin
                for (i = plen; i < 60; i = i + 1) exp_lan[i] = 8'h00;
                exp_lan_len = 60;
            end else begin
                exp_lan_len = plen;
            end
        end
    endtask

    //---------------------------------------------------------------------
    // 比对 task
    //---------------------------------------------------------------------
    function integer r_off;
        input integer n;
        integer i;
        begin
            r_off = 0;
            for (i = 0; i < n; i = i + 1) r_off = r_off + r_frame_len[i];
        end
    endfunction

    function integer l_off;
        input integer n;
        integer i;
        begin
            l_off = 0;
            for (i = 0; i < n; i = i + 1) l_off = l_off + l_frame_len[i];
        end
    endfunction

    task chk_relay_bytes;
        input integer n_expect;        // 第 n 帧（0 起）
        input integer off;             // 期望字节在 wb 里的起点
        input integer len;
        integer i, ok;
        begin
            ok = 1'b1;
            if (r_frame_len[n_expect] != len) begin
                ok = 1'b0;
                $display("  [DET] relay frame%0d len=%0d exp=%0d", n_expect, r_frame_len[n_expect], len);
            end
            // 该帧在 rc[] 里的起点 = 前几帧长度之和
            for (i = 0; i < len; i = i + 1) begin
                if (rc[r_off(n_expect) + i] !== wb[off + i]) begin
                    if (ok) $display("  [DET] relay byte[%0d]=%02h exp=%02h", i, rc[r_off(n_expect)+i], wb[off+i]);
                    ok = 1'b0;
                end
            end
            req(ok, "relay frame byte-identical");
        end
    endtask

    task chk_lan_frame;
        input integer n_expect;
        integer i, ok;
        begin
            ok = 1'b1;
            if (l_frame_len[n_expect] != exp_lan_len) begin
                ok = 1'b0;
                $display("  [DET] lan frame%0d len=%0d exp=%0d", n_expect, l_frame_len[n_expect], exp_lan_len);
            end
            for (i = 0; i < exp_lan_len; i = i + 1) begin
                if (lc[l_off(n_expect) + i] !== exp_lan[i]) begin
                    if (ok) $display("  [DET] lan byte[%0d]=%02h exp=%02h", i, lc[l_off(n_expect)+i], exp_lan[i]);
                    ok = 1'b0;
                end
            end
            req(ok, "lan frame byte-identical");
        end
    endtask

    task chk_cnts;
        begin
            req(st_rx_frames        == m_rx,     "st_rx_frames");
            req(st_rx_drop          == m_rxdrop, "st_rx_drop");
            req(st_relay            == m_relay,  "st_relay");
            req(st_local            == m_local,  "st_local");
            req(st_arp              == m_arp,    "st_arp");
            req(st_drop_vlan        == m_dvlan,  "st_drop_vlan");
            req(st_drop_ipv6        == m_dipv6,  "st_drop_ipv6");
            req(st_drop_ethertype   == m_detype, "st_drop_ethertype");
            req(st_drop_broadcast   == m_dbcast, "st_drop_broadcast");
            req(st_drop_multicast   == m_dmcast, "st_drop_multicast");
            req(st_drop_unknown_dst == m_dunk,   "st_drop_unknown_dst");
            req(st_drop_oversize    == m_dover,  "st_drop_oversize");
            req(st_drop_bad_csum    == m_dcsum,  "st_drop_bad_csum");
            req(st_drop_truncated   == m_dtrunc, "st_drop_truncated");
            req(st_drop_mac         == m_dmac,   "st_drop_mac");
            req(st_aur_frames       == m_aurf,   "st_aur_frames");
            req(st_aur_drop         == m_aurd,   "st_aur_drop");
            req(st_lan_frames       == m_lanf,   "st_lan_frames");
            req(st_aur_bad_v4       == m_badv4,  "st_aur_bad_v4");
        end
    endtask

    //=========================================================================
    // 主流程
    //=========================================================================
    integer i, t;
    integer base_r, base_l;
    integer n_rel, d_obs, d_drop0, ok4, j;
    // I04 专用：把 3 帧的期望内容各存一份（背靠背连发时 wb 会被下一帧覆盖）
    reg [7:0] seq3 [0:1023];
    // I10 专用：3 × 1486 B 的期望内容存档（3*1486 = 4458）
    reg [7:0] seq10 [0:8191];

    initial begin
        //---------------------------------------------------------------------
        // 初始化
        //---------------------------------------------------------------------
        eth_rst_n = 1'b0; aur_rst_n = 1'b0;
        rx_dv = 1'b0; rx_data = 8'd0;
        aur_en = 1'b0; aur_data = 8'd0;
        r_total = 0; r_len = 0; r_frames = 0; r_in_frame = 1'b0;
        l_total = 0; l_len = 0; l_frames = 0; l_in_frame = 1'b0;
        pass_cnt = 0; fail_cnt = 0; chk_fail = 1'b0;
        m_rx=0; m_relay=0; m_local=0; m_arp=0; m_rxdrop=0;
        m_dvlan=0; m_dipv6=0; m_detype=0; m_dbcast=0; m_dmcast=0; m_dunk=0;
        m_dover=0; m_dcsum=0; m_dtrunc=0; m_dmac=0;
        m_aurf=0; m_aurd=0; m_lanf=0; m_badv4=0;
        for (i = 0; i < 32; i = i + 1) begin
            r_frame_len[i] = 0; l_frame_len[i] = 0;
        end

        $display("==============================================================");
        $display(" p2_relay_top integration TB (v2, eth 125 MHz / aur 200 MHz)");
        $display("==============================================================");

        repeat (8) @(negedge eth_clk);
        repeat (8) @(negedge aur_clk);
        eth_rst_n = 1'b1;
        aur_rst_n = 1'b1;
        repeat (6) @(negedge eth_clk);

        //=====================================================================
        // I01 正常转发 1472 B（eth 侧）
        //=====================================================================
        eth_hdr_at(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr_at(14, 4'd5, 16'd1472, 8'd17, 8'd64, 8'd0, 3'b010, 13'd0,
                  PC1_IP, PEER_IP, 16'h0101);
        for (i = 34; i < 14 + 1472; i = i + 1) wb[i] = (i * 7 + 3);
        base_r = r_frames;

        rx_frame(14 + 1472, 1);
        wait_eth(12 * (14 + 1472) + 2000);

        req(r_frames == base_r + 1, "I01 exactly one relay frame");
        chk_relay_bytes(base_r, 14, 1472);
        req(r_frame_len[base_r] == 1472, "I01 relay byte count == 1472 (IP packet only)");
        m_rx = m_rx + 1; m_relay = m_relay + 1;
        chk_cnts;
        end_case("I01_relay_1472");

        //=====================================================================
        // I02 LOCAL 被吞掉（零字节外泄）
        //=====================================================================
        eth_hdr_at(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr_at(14, 4'd5, 16'd60, 8'd1, 8'd64, 8'd0, 3'b000, 13'd0,
                  PC1_IP, BOARD_IP, 16'h0102);
        for (i = 34; i < 14 + 60; i = i + 1) wb[i] = 8'hC5;
        base_r = r_frames;
        t = r_total;

        rx_frame(14 + 60, 1);
        wait_eth(12 * (14 + 60) + 2000);

        req(r_frames == base_r, "I02 LOCAL produced NO relay frame");
        req(r_total == t,       "I02 LOCAL produced ZERO relay bytes");
        m_rx = m_rx + 1; m_local = m_local + 1;
        chk_cnts;
        end_case("I02_local_swallowed");

        //=====================================================================
        // I03 广播 ARP 不跨板
        //=====================================================================
        eth_hdr_at(BCAST_MAC, PC1_MAC, 16'h0806);
        wb[14]=8'h00; wb[15]=8'h01; wb[16]=8'h08; wb[17]=8'h00;
        wb[18]=8'h06; wb[19]=8'h04; wb[20]=8'h00; wb[21]=8'h01;
        wb[22]=PC1_MAC[47:40]; wb[23]=PC1_MAC[39:32]; wb[24]=PC1_MAC[31:24];
        wb[25]=PC1_MAC[23:16]; wb[26]=PC1_MAC[15:8];  wb[27]=PC1_MAC[7:0];
        wb[28]=PC1_IP[31:24]; wb[29]=PC1_IP[23:16]; wb[30]=PC1_IP[15:8]; wb[31]=PC1_IP[7:0];
        wb[32]=8'h00; wb[33]=8'h00; wb[34]=8'h00; wb[35]=8'h00; wb[36]=8'h00; wb[37]=8'h00;
        wb[38]=PEER_IP[31:24]; wb[39]=PEER_IP[23:16]; wb[40]=PEER_IP[15:8]; wb[41]=PEER_IP[7:0];
        base_r = r_frames;
        t = r_total;

        rx_frame(42, 1);
        wait_eth(12 * 42 + 2000);

        req(r_frames == base_r, "I03 ARP produced NO relay frame");
        req(r_total == t,       "I03 ARP produced ZERO relay bytes");
        req(st_drop_ethertype == m_detype, "I03 ARP must NOT count as drop_ethertype");
        m_rx = m_rx + 1; m_arp = m_arp + 1;
        chk_cnts;
        end_case("I03_arp_no_cross");

        //=====================================================================
        // I04 背靠背 3 帧（帧间仅 1 拍空档）
        //   判据（2026-11-08 Lead 裁决）：2-bank 整帧缓冲 + extract 暂存转发
        //   ⇒ 满速背靠背有**固有吞吐上限**，所以不要求 3/3，而要求：
        //     ① 守恒：relayed + st_rx_drop == 3（每帧要么整帧转出、要么整帧被丢）
        //     ② 已转出的帧**逐字节正确**（不许半帧/错字节）
        //     ③ 把实测值打进日志（3/2/1 都可 PASS）
        //   注：缓冲的丢帧永远是"最新那帧"（FIFO 语义），所以已转出的必然是
        //       前 n_rel 帧，可以和 seq3 按顺序逐帧比对。
        //=====================================================================
        base_r  = r_frames;
        d_drop0 = st_rx_drop;
        for (t = 0; t < 3; t = t + 1) begin
            eth_hdr_at(BOARD_MAC, PC1_MAC, 16'h0800);
            ip_hdr_at(14, 4'd5, 16'd128, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
                      PC1_IP, PEER_IP, 16'h0200 + t);
            for (i = 34; i < 14 + 128; i = i + 1) wb[i] = (i + t * 3) & 8'hFF;
            for (i = 0; i < 14 + 128; i = i + 1) seq3[t*142 + i] = wb[i];
            rx_frame(14 + 128, 1);      // 每帧后仅 1 拍空档
        end
        wait_eth(16 * (14 + 128) + 3000);

        n_rel = r_frames - base_r;
        d_obs = st_rx_drop - d_drop0;
        $display("  [INFO] I04: relayed=%0d dropped=%0d (throughput-limited, documented)", n_rel, d_obs);
        req((n_rel + d_obs) == 3, "I04 conservation: relayed + buffer-dropped == 3");
        for (j = 0; j < n_rel; j = j + 1) begin
            ok4 = 1'b1;
            if (r_frame_len[base_r + j] != 128) begin
                ok4 = 1'b0;
                $display("  [DET] I04 frame%0d len=%0d exp=128", j, r_frame_len[base_r + j]);
            end
            for (i = 0; i < 128; i = i + 1) begin
                if (rc[r_off(base_r + j) + i] !== seq3[j*142 + 14 + i]) begin
                    if (ok4) $display("  [DET] I04 frame%0d byte[%0d]=%02h exp=%02h",
                                      j, i, rc[r_off(base_r + j) + i], seq3[j*142 + 14 + i]);
                    ok4 = 1'b0;
                end
            end
            req(ok4, "I04 relayed frame byte-identical");
        end
        m_rx     = m_rx + (3 - d_obs);
        m_relay  = m_relay + n_rel;
        m_rxdrop = m_rxdrop + d_obs;
        chk_cnts;
        end_case("I04_back_to_back_3");

        //=====================================================================
        // I10 满帧背靠背：3 × 1472 B IP（帧长 1486），帧间仅 1 拍空档
        //   这是"2-bank 整帧缓冲 + extract 暂存转发"吞吐上限**真正会顶到**的位置：
        //   I04 用的是 142 B 短帧，短帧下 extract 的 S_SEND 时长(128) < 帧长(142)，
        //   写侧反而比读侧慢，所以压不到上限；满帧 1472 vs 1486 才是压力点。
        //   判据与 I04 相同（Lead 裁决）：守恒 relayed + st_rx_drop == 3，
        //   且已转出的帧**逐字节正确**（3 帧内容各不相同，丢/串都能分辨）。
        //=====================================================================
        base_r  = r_frames;
        d_drop0 = st_rx_drop;
        for (t = 0; t < 3; t = t + 1) begin
            eth_hdr_at(BOARD_MAC, PC1_MAC, 16'h0800);
            ip_hdr_at(14, 4'd5, 16'd1472, 8'd17, 8'd64, 8'd0, 3'b010, 13'd0,
                      PC1_IP, PEER_IP, 16'h1000 + t);
            for (i = 34; i < 14 + 1472; i = i + 1) wb[i] = (i * 7 + t * 29) & 8'hFF;
            for (i = 0; i < 14 + 1472; i = i + 1) seq10[t*1486 + i] = wb[i];
            rx_frame(14 + 1472, 1);     // 每帧后仅 1 拍空档
        end
        wait_eth(30 * 1486 + 6000);

        n_rel = r_frames - base_r;
        d_obs = st_rx_drop - d_drop0;
        $display("  [INFO] I10: relayed=%0d dropped=%0d", n_rel, d_obs);
        req((n_rel + d_obs) == 3, "I10 conservation: relayed + buffer-dropped == 3");
        for (j = 0; j < n_rel; j = j + 1) begin
            ok4 = 1'b1;
            if (r_frame_len[base_r + j] != 1472) begin
                ok4 = 1'b0;
                $display("  [DET] I10 frame%0d len=%0d exp=1472", j, r_frame_len[base_r + j]);
            end
            for (i = 0; i < 1472; i = i + 1) begin
                if (rc[r_off(base_r + j) + i] !== seq10[j*1486 + 14 + i]) begin
                    if (ok4) $display("  [DET] I10 frame%0d byte[%0d]=%02h exp=%02h",
                                      j, i, rc[r_off(base_r + j) + i], seq10[j*1486 + 14 + i]);
                    ok4 = 1'b0;
                end
            end
            req(ok4, "I10 relayed full frame byte-identical");
        end
        m_rx     = m_rx + (3 - d_obs);
        m_relay  = m_relay + n_rel;
        m_rxdrop = m_rxdrop + d_obs;
        chk_cnts;
        end_case("I10_long_back_to_back");

        //=====================================================================
        // I06 aur 侧 1472 B
        //=====================================================================
        ip_hdr_at(0, 4'd5, 16'd1472, 8'd17, 8'd64, 8'd0, 3'b010, 13'd0,
                  PC1_IP, PEER_IP, 16'h0601);
        for (i = 20; i < 1472; i = i + 1) wb[i] = (i * 9 + 5);
        build_exp_lan(1472);
        base_l = l_frames;

        aur_frame(1472, 1);
        wait_aur(8 * 1472 + 800);

        req(l_frames == base_l + 1, "I06 exactly one lan frame");
        chk_lan_frame(base_l);
        req(l_frame_len[base_l] == 1486, "I06 lan total len == 1486");
        m_aurf = m_aurf + 1; m_lanf = m_lanf + 1;
        chk_cnts;
        end_case("I06_rewrap_aur_1472");

        //=====================================================================
        // I07 aur 侧 26 B -> 补零到 60
        //=====================================================================
        ip_hdr_at(0, 4'd5, 16'd26, 8'd253, 8'd64, 8'd0, 3'b000, 13'd0,
                  PC1_IP, PEER_IP, 16'h0602);
        for (i = 20; i < 26; i = i + 1) wb[i] = 8'hA0 + (i - 20);
        build_exp_lan(26);
        base_l = l_frames;

        aur_frame(26, 1);
        wait_aur(8 * 60 + 600);

        req(l_frames == base_l + 1, "I07 exactly one lan frame");
        chk_lan_frame(base_l);
        req(l_frame_len[base_l] == 60, "I07 lan total len == 60");
        m_aurf = m_aurf + 1; m_lanf = m_lanf + 1;
        chk_cnts;
        end_case("I07_rewrap_aur_26_pad");

        //=====================================================================
        // I09 侧带跟帧走：背靠背「广播 ARP」+「BOARD_MAC/0x0800/PEER_IP」
        //     旧旁路嗅探器会把第 2 帧判成 ARP（不转发）
        //=====================================================================
        // 第 1 帧：广播 ARP
        eth_hdr_at(BCAST_MAC, PC1_MAC, 16'h0806);
        wb[14]=8'h00; wb[15]=8'h01; wb[16]=8'h08; wb[17]=8'h00;
        wb[18]=8'h06; wb[19]=8'h04; wb[20]=8'h00; wb[21]=8'h01;
        wb[22]=PC1_MAC[47:40]; wb[23]=PC1_MAC[39:32]; wb[24]=PC1_MAC[31:24];
        wb[25]=PC1_MAC[23:16]; wb[26]=PC1_MAC[15:8];  wb[27]=PC1_MAC[7:0];
        wb[28]=PC1_IP[31:24]; wb[29]=PC1_IP[23:16]; wb[30]=PC1_IP[15:8]; wb[31]=PC1_IP[7:0];
        wb[32]=8'h00; wb[33]=8'h00; wb[34]=8'h00; wb[35]=8'h00; wb[36]=8'h00; wb[37]=8'h00;
        wb[38]=PEER_IP[31:24]; wb[39]=PEER_IP[23:16]; wb[40]=PEER_IP[15:8]; wb[41]=PEER_IP[7:0];
        rx_frame(42, 1);              // 1 拍空档，紧接第 2 帧

        // 第 2 帧：BOARD_MAC + 0x0800 + dst=PEER_IP（期望 RELAY）
        eth_hdr_at(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr_at(14, 4'd5, 16'd74, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
                  PC1_IP, PEER_IP, 16'h0902);
        for (i = 34; i < 14 + 74; i = i + 1) wb[i] = (i * 13 + 1);
        base_r = r_frames;

        rx_frame(14 + 74, 1);
        wait_eth(16 * (14 + 74) + 3000);

        req(r_frames == base_r + 1, "I09 2nd frame relayed (sideband not polluted by 1st)");
        chk_relay_bytes(base_r, 14, 74);
        req(st_arp == m_arp + 1, "I09 st_arp == 1 (first frame counted as ARP)");
        m_rx = m_rx + 2; m_arp = m_arp + 1; m_relay = m_relay + 1;
        chk_cnts;
        end_case("I09_sideband_follows_frame");

        //=====================================================================
        // I08 计数器总对账
        //=====================================================================
        wait_eth(200);
        wait_aur(200);
        chk_cnts;
        req(st_drop_vlan == 0,  "I08 no vlan drops ever");
        req(st_drop_ipv6 == 0,  "I08 no ipv6 drops ever");
        req(st_aur_bad_v4 == 0, "I08 aur frames all IPv4");
        end_case("I08_counters_clean");

        $display("--------------------------------------------------------------");
        $display("P2_RELAY_TB: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0) $display("P2_RELAY_TB: RESULT=FAIL");
        else               $display("P2_RELAY_TB: RESULT=PASS");
        $display("--------------------------------------------------------------");
        $finish;
    end

endmodule
