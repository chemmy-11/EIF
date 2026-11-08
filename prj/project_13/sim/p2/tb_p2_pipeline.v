//=============================================================================
// tb_p2_pipeline.v  --  prj13 P2 (v0.2 contract) pipeline self-checking TB
//-----------------------------------------------------------------------------
// 链路（与 P2 集成形态一致）：
//
//   frame -> [ipv4_packet_extract] --m_*--> glue --> [eth_rewrap] --> frame out
//                    |                        ^
//                    | o_*_pulse              | 组合判决
//                    +--> [local_steer] <-----+（metadata + TB 抓的以太网头）
//                              |
//                              +--> 计数器组（32 bit 粘滞）
//
// glue（TB 承担，模拟顶层要在 P2 里做的那段接线）：
//   - 从输入流抓 eth_dst / eth_type（MAC 侧视角，合法可观测）
//   - 判决拍（extract 的 o_frame_pulse）用 extract 的 IP 元数据 + 抓到的
//     eth_dst/eth_type 驱动 local_steer，并把 i_ip_hdr_ok 置成本帧是否通过
//     结构检查
//   - 只有 decision==RELAY 才把 m_* 接到 eth_rewrap；LOCAL/ARP/DROP 一律吞掉
//     （DROP 的字节仍被消费，避免上游卡死）
//   - 计数器事件：extract 自己的 drop 用 extract 的 reason；local_steer 判决
//     出来的 DROP/LOCAL/ARP/RELAY 分别在流尾/帧尾/判决拍打一拍脉冲
//
// 用例（手册 P0-1 验收）：
//   C01 normal_relay_1472      1472 B IP 包（真 IP+UDP checksum）逐字节透传
//   C02 tiny_pad_26            26 B IP 包 -> 补零到 60 B
//   C03 drop_vlan              0x8100
//   C04 drop_ipv6              0x86DD
//   C05 drop_ethertype         0x1234
//   C06 drop_broadcast         以太网广播 + IP 非本板
//   C07 drop_multicast         以太网组播（ip_dst=PEER_IP 也被 MAC 层先丢）
//   C08 drop_unknown_dst       8.8.8.8（防乒乓核心）
//   C09 drop_oversize          total_len=1501
//   C10 drop_bad_csum          IP 头 checksum 错
//   C11 drop_truncated         帧长 < 14+total_len（半包不得外泄）
//   C12 drop_mac               eth_dst 非本板（第 10 类 reason）
//   C13 arp_local              广播 ARP request -> ARP/LOCAL，不跨板
//   C14 no_pingpong            连续 3 帧 8.8.8.8 全 DROP，输出 0 字节
//   C15 fragment_passthru      MF=1 + frag_off=1480，逐字节透传，无重组
//   C16 backpressure_lfsr      m_ready LFSR 随机，1472 B 仍逐字节正确
//   C17 csum_boundary_0000     checksum 字段 = 0x0000 边界（合法，必须透传）
//   C18 csum_boundary_ffff     checksum 字段 = 0xFFFF 边界（非法，必须丢弃）
//   C19 local_to_board_ip      dst=BOARD_IP -> LOCAL(1)，本地栈收，零输出
//   C20 local_bcast_to_board_ip 以太网广播 + ip_dst=BOARD_IP -> LOCAL(1)
//   C21 global_counters_clean  全局计数器/输出字节数/len_err 收尾
//
// 输出：每例 [PASS]/[FAIL] 行，末尾 "P2_TB: PASS=<n> FAIL=<m>"
// 编码：纯 Verilog-2001（无 logic/always_ff/interface/包），单时钟域。
//=============================================================================
`timescale 1ns / 1ps

module tb_p2_pipeline;

    //=========================================================================
    // 参数（板 A 形态；板 B 见各 RTL 参数注释）
    //=========================================================================
    localparam [47:0] BOARD_MAC   = 48'h02_00_00_00_0A_01;
    localparam [47:0] PEER_PC_MAC = 48'hAA_BB_CC_DD_EE_02;   // 板 A 对端 PC2 实际 MAC
    localparam [47:0] PC1_MAC     = 48'hAA_BB_CC_DD_EE_01;   // 板 A 直连 PC1 实际 MAC
    localparam [47:0] OTHER_MAC   = 48'h02_00_00_00_0A_99;
    localparam [47:0] BCAST_MAC   = 48'hFFFF_FFFF_FFFF;
    localparam [47:0] MCAST_MAC   = 48'h01_00_5E_00_00_01;

    localparam [31:0] BOARD_IP    = {8'd192, 8'd168, 8'd50, 8'd11};
    localparam [31:0] PEER_IP     = {8'd192, 8'd168, 8'd50, 8'd2};
    localparam [31:0] PC1_IP      = {8'd192, 8'd168, 8'd50, 8'd1};
    localparam [31:0] UNKNOWN_IP  = {8'd8, 8'd8, 8'd8, 8'd8};

    localparam [15:0] MIN_FRAME   = 16'd60;

    //=========================================================================
    // 时钟 / 复位
    //=========================================================================
    reg clk;
    reg rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;     // 100 MHz

    //=========================================================================
    // DUT 0: ipv4_packet_extract
    //=========================================================================
    wire        ex_s_valid;
    wire        ex_s_ready;
    wire [7:0]  ex_s_data;
    wire        ex_s_sop;
    wire        ex_s_eop;

    wire        ex_m_valid;
    wire        ex_m_ready;
    wire [7:0]  ex_m_data;
    wire        ex_m_sop;
    wire        ex_m_eop;

    wire [31:0] ex_m_ip_src;
    wire [31:0] ex_m_ip_dst;
    wire [15:0] ex_m_total_len;
    wire [15:0] ex_m_ip_id;
    wire [15:0] ex_m_csum;
    wire [7:0]  ex_m_proto;
    wire [7:0]  ex_m_ttl;
    wire [7:0]  ex_m_tos;
    wire [3:0]  ex_m_ihl;
    wire [2:0]  ex_m_ip_flags;
    wire [12:0] ex_m_frag_off;
    wire        ex_m_is_fragment;

    wire        ex_frame_pulse;
    wire        ex_parse_pulse;
    wire        ex_drop_pulse;
    wire [3:0]  ex_drop_reason;

    ipv4_packet_extract #(
        .MAX_IP_LEN (16'd1500),
        .BOARD_MAC  (BOARD_MAC)
    ) u_ext (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_valid       (ex_s_valid),
        .s_ready       (ex_s_ready),
        .s_data        (ex_s_data),
        .s_sop         (ex_s_sop),
        .s_eop         (ex_s_eop),
        .m_valid       (ex_m_valid),
        .m_ready       (ex_m_ready),
        .m_data        (ex_m_data),
        .m_sop         (ex_m_sop),
        .m_eop         (ex_m_eop),
        .m_ip_src      (ex_m_ip_src),
        .m_ip_dst      (ex_m_ip_dst),
        .m_total_len   (ex_m_total_len),
        .m_ip_id       (ex_m_ip_id),
        .m_csum        (ex_m_csum),
        .m_proto       (ex_m_proto),
        .m_ttl         (ex_m_ttl),
        .m_tos         (ex_m_tos),
        .m_ihl         (ex_m_ihl),
        .m_ip_flags    (ex_m_ip_flags),
        .m_frag_off    (ex_m_frag_off),
        .m_is_fragment (ex_m_is_fragment),
        .o_frame_pulse (ex_frame_pulse),
        .o_parse_pulse (ex_parse_pulse),
        .o_drop_pulse  (ex_drop_pulse),
        .o_drop_reason (ex_drop_reason)
    );

    //=========================================================================
    // DUT 1: eth_rewrap
    //=========================================================================
    wire        rw_s_valid;
    wire        rw_s_ready;
    wire [7:0]  rw_s_data;
    wire        rw_s_sop;
    wire        rw_s_eop;
    wire [15:0] rw_pkt_len;

    wire        rw_m_valid;
    wire        rw_m_ready;
    wire [7:0]  rw_m_data;
    wire        rw_m_sop;
    wire        rw_m_eop;
    wire [15:0] rw_frame_len;
    wire        rw_len_err;
    integer     rw_len_err_cnt;

    eth_rewrap #(
        .SRC_MAC       (BOARD_MAC),
        .DST_MAC       (PEER_PC_MAC),
        .MIN_FRAME_LEN (MIN_FRAME)
    ) u_rw (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_valid     (rw_s_valid),
        .s_ready     (rw_s_ready),
        .s_data      (rw_s_data),
        .s_sop       (rw_s_sop),
        .s_eop       (rw_s_eop),
        .i_pkt_len   (rw_pkt_len),
        .m_valid     (rw_m_valid),
        .m_ready     (rw_m_ready),
        .m_data      (rw_m_data),
        .m_sop       (rw_m_sop),
        .m_eop       (rw_m_eop),
        .m_frame_len (rw_frame_len),
        .o_len_err   (rw_len_err)
    );

    //=========================================================================
    // DUT 2: local_steer（组合判决 + 计数器组）
    //=========================================================================
    reg  [47:0] cap_eth_dst;
    reg  [47:0] cap_eth_src;
    reg  [15:0] cap_eth_type;
    reg         st_hdr_ok;
    reg  [15:0] st_frame_len;

    wire [2:0]  steer_dec;
    wire [3:0]  steer_reason;

    reg         ev_frame;
    reg         ev_relay;
    reg         ev_local;
    reg         ev_arp;
    reg         ev_drop;
    reg  [3:0]  ev_drop_reason;

    wire [31:0] cnt_rx, cnt_relay, cnt_local, cnt_arp;
    wire [31:0] cnt_dvlan, cnt_dipv6, cnt_detype, cnt_dbcast, cnt_dmcast;
    wire [31:0] cnt_dunk, cnt_dover, cnt_dcsum, cnt_dtrunc, cnt_dmac;

    local_steer #(
        .BOARD_MAC    (BOARD_MAC),
        .BOARD_IP     (BOARD_IP),
        .PEER_IP      (PEER_IP),
        .PC_IP        (PC1_IP),
        .PROXY_ARP_EN (1'b0)
    ) u_steer (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_eth_dst        (cap_eth_dst),
        .i_eth_type       (cap_eth_type),
        .i_ip_dst         (ex_m_ip_dst),
        .i_ip_total_len   (ex_m_total_len),
        .i_ip_hdr_ok      (st_hdr_ok),
        .i_frame_len      (st_frame_len),
        .o_decision       (steer_dec),
        .o_drop_reason    (steer_reason),
        .i_frame_pulse    (ev_frame),
        .i_relay_pulse    (ev_relay),
        .i_local_pulse    (ev_local),
        .i_arp_pulse      (ev_arp),
        .i_drop_pulse     (ev_drop),
        .i_drop_reason    (ev_drop_reason),
        .o_cnt_rx_frames       (cnt_rx),
        .o_cnt_relay           (cnt_relay),
        .o_cnt_local           (cnt_local),
        .o_cnt_arp             (cnt_arp),
        .o_cnt_drop_vlan       (cnt_dvlan),
        .o_cnt_drop_ipv6       (cnt_dipv6),
        .o_cnt_drop_ethertype  (cnt_detype),
        .o_cnt_drop_broadcast  (cnt_dbcast),
        .o_cnt_drop_multicast  (cnt_dmcast),
        .o_cnt_drop_unknown_dst(cnt_dunk),
        .o_cnt_drop_oversize   (cnt_dover),
        .o_cnt_drop_bad_csum   (cnt_dcsum),
        .o_cnt_drop_truncated  (cnt_dtrunc),
        .o_cnt_drop_mac        (cnt_dmac)
    );

    //=========================================================================
    // glue: extract m_* -> eth_rewrap，只有 RELAY 才放行
    //=========================================================================
    wire pipe_relay = (steer_dec == 3'd2);

    assign rw_s_valid = ex_m_valid & pipe_relay;
    assign rw_s_data  = ex_m_data;
    assign rw_s_sop   = ex_m_sop;
    assign rw_s_eop   = ex_m_eop;
    assign rw_pkt_len = ex_m_total_len;
    // 非 RELAY（LOCAL/DROP/ARP）时把字节吞掉，保证 extract 不会卡在 S_SEND
    assign ex_m_ready = pipe_relay ? rw_s_ready : 1'b1;

    //=========================================================================
    // 输入驱动（1 B/beat，等 s_ready）
    //=========================================================================
    reg [7:0] frm [0:2047];
    integer   frm_len;
    reg       drv_active;
    integer   drv_idx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) drv_idx <= 0;
        else if (drv_active && ex_s_valid && ex_s_ready) drv_idx <= drv_idx + 1;
    end

    assign ex_s_valid = drv_active;
    assign ex_s_sop   = drv_active && (drv_idx == 0);
    assign ex_s_eop   = drv_active && (drv_idx == (frm_len - 1));
    assign ex_s_data  = frm[drv_idx];

    //=========================================================================
    // 输出背压发生器（LFSR）
    //=========================================================================
    reg  [1:0]  ready_mode;      // 0=常 ready 1=LFSR
    reg         o_ready;
    reg  [15:0] lfsr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lfsr <= 16'hACE1;
        else        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    always @(negedge clk) begin
        if (ready_mode == 2'd1) o_ready = lfsr[1] | lfsr[4] | lfsr[7];   // 约 7/8 ready
        else                    o_ready = 1'b1;
    end

    assign rw_m_ready = o_ready;

    //=========================================================================
    // 输出捕获（帧数 + 总字节数 + 逐字节）
    //=========================================================================
    reg [7:0] cap_out [0:2047];
    integer   cap_len;
    integer   out_frames;
    integer   out_bytes;        // 输出**总字节数**：DROP 帧必须一个字节都不外泄
    integer   last_out_len;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_len        <= 0;
            out_frames     <= 0;
            out_bytes      <= 0;
            last_out_len   <= 0;
            rw_len_err_cnt <= 0;
        end else begin
            if (rw_len_err) rw_len_err_cnt <= rw_len_err_cnt + 1;
            if (rw_m_valid && rw_m_ready) begin
                out_bytes <= out_bytes + 1;
                if (rw_m_sop) begin
                    cap_len  <= 1;
                    cap_out[0] <= rw_m_data;
                end else begin
                    cap_out[cap_len] <= rw_m_data;
                    cap_len <= cap_len + 1;
                end
                if (rw_m_eop) begin
                    out_frames   <= out_frames + 1;
                    last_out_len <= cap_len + 1;
                end
            end
        end
    end

    //=========================================================================
    // glue 的时序部分：抓头 / 判决 / 事件脉冲
    //=========================================================================
    reg [2:0]  meta_dec;
    reg [3:0]  meta_reason;
    reg [3:0]  last_drop_reason;
    reg        frame_had_stream;
    reg        frame_had_drop;
    reg        arp_seen;
    reg        saw_is_fragment;

    reg [31:0] meta_ip_src, meta_ip_dst;
    reg [15:0] meta_total_len, meta_ip_id, meta_csum;
    reg [7:0]  meta_proto, meta_ttl, meta_tos;
    reg [3:0]  meta_ihl;
    reg [2:0]  meta_flags;
    reg [12:0] meta_frag_off;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_eth_dst  <= 48'd0;
            cap_eth_src  <= 48'd0;
            cap_eth_type <= 16'd0;
            st_hdr_ok    <= 1'b0;
            st_frame_len <= 16'd0;
            ev_frame     <= 1'b0;
            ev_relay     <= 1'b0;
            ev_local     <= 1'b0;
            ev_arp       <= 1'b0;
            ev_drop      <= 1'b0;
            ev_drop_reason <= 4'd0;
            meta_dec     <= 3'd0;
            meta_reason  <= 4'd0;
            last_drop_reason <= 4'd0;
            frame_had_stream <= 1'b0;
            frame_had_drop   <= 1'b0;
            arp_seen         <= 1'b0;
            saw_is_fragment  <= 1'b0;
            meta_ip_src      <= 32'd0;
            meta_ip_dst      <= 32'd0;
            meta_total_len   <= 16'd0;
            meta_ip_id       <= 16'd0;
            meta_csum        <= 16'd0;
            meta_proto       <= 8'd0;
            meta_ttl         <= 8'd0;
            meta_tos         <= 8'd0;
            meta_ihl         <= 4'd0;
            meta_flags       <= 3'd0;
            meta_frag_off    <= 13'd0;
        end else begin
            // 事件脉冲默认撤掉（每拍重新打）
            ev_frame  <= 1'b0;
            ev_relay  <= 1'b0;
            ev_local  <= 1'b0;
            ev_arp    <= 1'b0;
            ev_drop   <= 1'b0;

            // ---- MAC 侧抓以太网头 ----
            if (ex_s_valid && ex_s_ready) begin
                if (drv_idx <= 5) begin
                    cap_eth_dst <= {cap_eth_dst[39:0], ex_s_data};
                end
                if ((drv_idx >= 6) && (drv_idx <= 11)) begin
                    cap_eth_src <= {cap_eth_src[39:0], ex_s_data};
                end
                if (drv_idx == 12) cap_eth_type[15:8] <= ex_s_data;
                if (drv_idx == 13) cap_eth_type[7:0]  <= ex_s_data;
            end

            // ---- 判决拍（extract 的 o_frame_pulse，S_VRD）----
            if (ex_frame_pulse) begin
                ev_frame         <= 1'b1;
                st_frame_len     <= drv_idx;
                meta_dec         <= steer_dec;
                meta_reason      <= steer_reason;
                frame_had_stream <= 1'b0;
                frame_had_drop   <= 1'b0;
                arp_seen         <= 1'b0;
                saw_is_fragment  <= 1'b0;

                if (ex_drop_pulse) begin
                    // extract 结构检查直接丢弃：reason 由 extract 给出
                    st_hdr_ok        <= 1'b0;
                    ev_drop          <= 1'b1;
                    ev_drop_reason   <= ex_drop_reason;
                    last_drop_reason <= ex_drop_reason;
                    frame_had_drop   <= 1'b1;
                end else begin
                    // 通过结构检查（或 ARP：ARP 无输出，记 ARP 计数）
                    st_hdr_ok <= (cap_eth_type == 16'h0800);
                    if (cap_eth_type == 16'h0806) begin
                        ev_arp   <= 1'b1;
                        arp_seen <= 1'b1;
                    end
                end
            end

            // ---- 流首（m_sop 握手）：锁元数据/判决 ----
            if (ex_m_valid && ex_m_ready && ex_m_sop) begin
                frame_had_stream <= 1'b1;
                meta_dec         <= steer_dec;
                meta_reason      <= steer_reason;
                meta_ip_src      <= ex_m_ip_src;
                meta_ip_dst      <= ex_m_ip_dst;
                meta_total_len   <= ex_m_total_len;
                meta_ip_id       <= ex_m_ip_id;
                meta_csum        <= ex_m_csum;
                meta_proto       <= ex_m_proto;
                meta_ttl         <= ex_m_ttl;
                meta_tos         <= ex_m_tos;
                meta_ihl         <= ex_m_ihl;
                meta_flags       <= ex_m_ip_flags;
                meta_frag_off    <= ex_m_frag_off;
                saw_is_fragment  <= ex_m_is_fragment;
            end

            // ---- 流尾（m_eop 握手）：LOCAL / STEER-DROP 在这里计数 ----
            if (ex_m_valid && ex_m_ready && ex_m_eop) begin
                if (steer_dec == 3'd1) begin
                    ev_local <= 1'b1;
                end else if (steer_dec == 3'd0) begin
                    ev_drop          <= 1'b1;
                    ev_drop_reason   <= steer_reason;
                    last_drop_reason <= steer_reason;
                    frame_had_drop   <= 1'b1;
                end
            end

            // ---- rewrap 输出帧尾：RELAY 计数 ----
            if (rw_m_valid && rw_m_ready && rw_m_eop) begin
                ev_relay <= 1'b1;
            end
        end
    end

    //=========================================================================
    // 期望值 / 参考模型
    //=========================================================================
    reg [7:0] exp_frame [0:2047];
    integer   exp_frame_len;

    reg [31:0] exp_ip_src, exp_ip_dst;
    reg [15:0] exp_total_len, exp_ip_id, exp_csum;
    reg [7:0]  exp_proto, exp_ttl, exp_tos;
    reg [3:0]  exp_ihl;
    reg [2:0]  exp_flags;
    reg [12:0] exp_frag_off;
    reg        exp_is_frag;

    integer m_rx, m_relay, m_local, m_arp;
    integer m_dvlan, m_dipv6, m_detype, m_dbcast, m_dmcast;
    integer m_dunk, m_dover, m_dcsum, m_dtrunc, m_dmac;
    integer m_out;
    integer m_out_bytes;

    integer pass_cnt, fail_cnt;
    reg     chk_fail;

    reg [31:0] acc32;
    reg [15:0] acc16;
    reg [15:0] csum_field;

    //-------------------------------------------------------------------------
    // 帧构造
    //-------------------------------------------------------------------------
    task set_eth;
        input [47:0] dmac;
        input [47:0] smac;
        input [15:0] etype;
        begin
            frm[0]  = dmac[47:40]; frm[1]  = dmac[39:32]; frm[2]  = dmac[31:24];
            frm[3]  = dmac[23:16]; frm[4]  = dmac[15:8];  frm[5]  = dmac[7:0];
            frm[6]  = smac[47:40]; frm[7]  = smac[39:32]; frm[8]  = smac[31:24];
            frm[9]  = smac[23:16]; frm[10] = smac[15:8];  frm[11] = smac[7:0];
            frm[12] = etype[15:8]; frm[13] = etype[7:0];
        end
    endtask

    // IP 头 ones'-complement 校验和（checksum 字段先清零再累加，取反写回）
    task ip_csum;
        input [3:0] ihl;
        integer n, k;
        reg [31:0] s;
        reg [15:0] f;
        begin
            frm[24] = 8'h00;
            frm[25] = 8'h00;
            n = ihl * 2;
            s = 32'd0;
            for (k = 0; k < n; k = k + 1) begin
                s = s + {16'd0, frm[14 + 2*k], frm[15 + 2*k]};
            end
            while (s[31:16] != 16'd0) begin
                s = {16'd0, s[15:0]} + {16'd0, s[31:16]};
            end
            f = ~s[15:0];
            frm[24] = f[15:8];
            frm[25] = f[7:0];
        end
    endtask

    // 折叠整个 IP 头（含 checksum 字段）：合法应得 0xFFFF
    task ip_csum_check;
        input [3:0] ihl;
        integer n, k;
        reg [31:0] s;
        begin
            n = ihl * 2;
            s = 32'd0;
            for (k = 0; k < n; k = k + 1) begin
                s = s + {16'd0, frm[14 + 2*k], frm[15 + 2*k]};
            end
            while (s[31:16] != 16'd0) begin
                s = {16'd0, s[15:0]} + {16'd0, s[31:16]};
            end
            acc16 = s[15:0];
        end
    endtask

    task ip_hdr;
        input [3:0]  ihl;
        input [15:0] tot_len;
        input [7:0]  proto;
        input [7:0]  ttl;
        input [7:0]  tos;
        input [2:0]  flags;
        input [12:0] frag_off;
        input [31:0] src_ip;
        input [31:0] dst_ip;
        input [15:0] ip_id;
        integer k;
        begin
            frm[14] = {4'h4, ihl};
            frm[15] = tos;
            frm[16] = tot_len[15:8];
            frm[17] = tot_len[7:0];
            frm[18] = ip_id[15:8];
            frm[19] = ip_id[7:0];
            frm[20] = {flags, frag_off[12:8]};
            frm[21] = frag_off[7:0];
            frm[22] = ttl;
            frm[23] = proto;
            frm[24] = 8'h00;
            frm[25] = 8'h00;
            frm[26] = src_ip[31:24];
            frm[27] = src_ip[23:16];
            frm[28] = src_ip[15:8];
            frm[29] = src_ip[7:0];
            frm[30] = dst_ip[31:24];
            frm[31] = dst_ip[23:16];
            frm[32] = dst_ip[15:8];
            frm[33] = dst_ip[7:0];
            for (k = 34; k < (14 + ihl*4); k = k + 1) frm[k] = 8'h01;   // 选项区 NOP
            ip_csum(ihl);
            // 记录本帧期望元数据
            exp_ip_src    = src_ip;
            exp_ip_dst    = dst_ip;
            exp_total_len = tot_len;
            exp_ip_id     = ip_id;
            exp_ihl       = ihl;
            exp_flags     = flags;
            exp_frag_off  = frag_off;
            exp_proto     = proto;
            exp_ttl       = ttl;
            exp_tos       = tos;
            exp_is_frag   = flags[0] | (frag_off != 13'd0);
            exp_csum      = {frm[24], frm[25]};
        end
    endtask

    // 把 frm[base..base+len-1] 当 16-bit 大端字累加进 acc32（奇数尾补 0）
    task sum_frm;
        input integer base;
        input integer len;
        integer k;
        reg [15:0] w;
        begin
            k = 0;
            while (k < len) begin
                w[15:8] = frm[base + k];
                if ((k + 1) < len) w[7:0] = frm[base + k + 1];
                else               w[7:0] = 8'h00;
                acc32 = acc32 + {16'd0, w};
                k = k + 2;
            end
        end
    endtask

    task fold_acc;
        begin
            while (acc32[31:16] != 16'd0) begin
                acc32 = {16'd0, acc32[15:0]} + {16'd0, acc32[31:16]};
            end
            acc16 = acc32[15:0];
        end
    endtask

    // UDP 校验和（含伪头）；hdr_off = UDP 头绝对偏移
    task udp_csum;
        input integer hdr_off;
        input [15:0]  udp_len;
        input [31:0]  src_ip;
        input [31:0]  dst_ip;
        begin
            // 伪头放 1640..1651（帧最大 1515 B，不冲突）
            frm[1640] = src_ip[31:24]; frm[1641] = src_ip[23:16];
            frm[1642] = src_ip[15:8];  frm[1643] = src_ip[7:0];
            frm[1644] = dst_ip[31:24]; frm[1645] = dst_ip[23:16];
            frm[1646] = dst_ip[15:8];  frm[1647] = dst_ip[7:0];
            frm[1648] = 8'h00;
            frm[1649] = 8'd17;
            frm[1650] = udp_len[15:8];
            frm[1651] = udp_len[7:0];
            frm[hdr_off + 6] = 8'h00;
            frm[hdr_off + 7] = 8'h00;
            acc32 = 32'd0;
            sum_frm(1640, 12);
            sum_frm(hdr_off, 8);
            sum_frm(hdr_off + 8, udp_len - 8);
            fold_acc;
            acc16 = ~acc16;                            // 反码和取反 = checksum
            if (acc16 == 16'h0000) acc16 = 16'hFFFF;   // RFC768：算得 0 时发 0xFFFF
            frm[hdr_off + 6] = acc16[15:8];
            frm[hdr_off + 7] = acc16[7:0];
        end
    endtask

    // 暴力搜索 ip_id，使 IP 头 checksum **字段值** 恰好等于 want
    // （固定其余字段时 S_rest = A + id 是双射，每个 want 恰好一个解）
    task csum_search;
        input [15:0] want;
        integer id, k, n;
        reg [31:0] s;
        reg [15:0] f;
        reg found;
        begin
            n = (frm[14] & 8'h0F) * 2;
            found = 0;
            id = 0;
            while ((id < 65536) && (found == 0)) begin
                frm[18] = id[15:8];
                frm[19] = id[7:0];
                frm[24] = 8'h00;
                frm[25] = 8'h00;
                s = 32'd0;
                for (k = 0; k < n; k = k + 1) begin
                    s = s + {16'd0, frm[14 + 2*k], frm[15 + 2*k]};
                end
                while (s[31:16] != 16'd0) begin
                    s = {16'd0, s[15:0]} + {16'd0, s[31:16]};
                end
                f = ~s[15:0];
                if (f == want) found = 1'b1;
                else           id = id + 1;
            end
            if (found == 0) $display("  [DET] csum_search: no id for want=%04h", want);
            csum_field = {frm[24], frm[25]};
            // 元数据期望同步（id / checksum 都变了）
            exp_ip_id = {frm[18], frm[19]};
            exp_csum  = {frm[24], frm[25]};
        end
    endtask

    // 期望输出帧（rewrap 形态）
    task build_expected;
        input integer total_len;
        integer i, plen;
        begin
            exp_frame[0]  = PEER_PC_MAC[47:40]; exp_frame[1]  = PEER_PC_MAC[39:32];
            exp_frame[2]  = PEER_PC_MAC[31:24]; exp_frame[3]  = PEER_PC_MAC[23:16];
            exp_frame[4]  = PEER_PC_MAC[15:8];  exp_frame[5]  = PEER_PC_MAC[7:0];
            exp_frame[6]  = BOARD_MAC[47:40];   exp_frame[7]  = BOARD_MAC[39:32];
            exp_frame[8]  = BOARD_MAC[31:24];   exp_frame[9]  = BOARD_MAC[23:16];
            exp_frame[10] = BOARD_MAC[15:8];    exp_frame[11] = BOARD_MAC[7:0];
            exp_frame[12] = 8'h08;
            exp_frame[13] = 8'h00;
            for (i = 0; i < total_len; i = i + 1) exp_frame[14 + i] = frm[14 + i];
            plen = 14 + total_len;
            if (plen < MIN_FRAME) begin
                for (i = plen; i < MIN_FRAME; i = i + 1) exp_frame[i] = 8'h00;
                exp_frame_len = MIN_FRAME;
            end else begin
                exp_frame_len = plen;
            end
        end
    endtask

    //=========================================================================
    // 检查工具
    //=========================================================================
    task req;
        input            cond;
        input [8*64-1:0] what;
        begin
            if (!cond) begin
                chk_fail = 1'b1;
                $display("  [DET] %0s", what);
            end
        end
    endtask

    task chk_cnts;
        begin
            req(cnt_rx      == m_rx,      "cnt_rx_frames");
            req(cnt_relay   == m_relay,   "cnt_relay");
            req(cnt_local   == m_local,   "cnt_local");
            req(cnt_arp     == m_arp,     "cnt_arp");
            req(cnt_dvlan   == m_dvlan,   "cnt_drop_vlan");
            req(cnt_dipv6   == m_dipv6,   "cnt_drop_ipv6");
            req(cnt_detype  == m_detype,  "cnt_drop_ethertype");
            req(cnt_dbcast  == m_dbcast,  "cnt_drop_broadcast");
            req(cnt_dmcast  == m_dmcast,  "cnt_drop_multicast");
            req(cnt_dunk    == m_dunk,    "cnt_drop_unknown_dst");
            req(cnt_dover   == m_dover,   "cnt_drop_oversize");
            req(cnt_dcsum   == m_dcsum,   "cnt_drop_bad_csum");
            req(cnt_dtrunc  == m_dtrunc,  "cnt_drop_truncated");
            req(cnt_dmac    == m_dmac,    "cnt_drop_mac");
            // 关键：DROP 帧必须**一个字节都不外泄**（不是"没有完整帧"就够了）
            req(out_bytes   == m_out_bytes, "rewrap output BYTE count (no leak on drop)");
            req(out_frames  == m_out,       "rewrap output FRAME count");
        end
    endtask

    task chk_bytes;
        integer i;
        reg bad;
        begin
            bad = 1'b0;
            if (cap_len != exp_frame_len) begin
                bad = 1'b1;
                $display("  [DET] frame_len=%0d exp=%0d", cap_len, exp_frame_len);
            end
            for (i = 0; i < exp_frame_len; i = i + 1) begin
                if (cap_out[i] !== exp_frame[i]) begin
                    if (!bad) $display("  [DET] byte[%0d]=%02h exp=%02h", i, cap_out[i], exp_frame[i]);
                    bad = 1'b1;
                end
            end
            req(!bad, "frame byte-compare");
        end
    endtask

    task chk_meta;
        begin
            req(meta_ihl       == exp_ihl,       "meta m_ihl");
            req(meta_total_len == exp_total_len, "meta m_total_len");
            req(meta_ip_id     == exp_ip_id,     "meta m_ip_id");
            req(meta_csum      == exp_csum,      "meta m_csum");
            req(meta_proto     == exp_proto,     "meta m_proto");
            req(meta_ttl       == exp_ttl,       "meta m_ttl");
            req(meta_tos       == exp_tos,       "meta m_tos");
            req(meta_ip_src    == exp_ip_src,    "meta m_ip_src");
            req(meta_ip_dst    == exp_ip_dst,    "meta m_ip_dst");
            req(meta_flags     == exp_flags,     "meta m_ip_flags");
            req(meta_frag_off  == exp_frag_off,  "meta m_frag_off");
            req(saw_is_fragment == exp_is_frag,  "meta m_is_fragment");
        end
    endtask

    task end_case;
        input [8*64-1:0] nm;
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

    // 通用收尾：计数器 + 判决 + 元数据 + 字节
    task chk_all;
        input [8*64-1:0] nm;
        input [2:0]      e_dec;
        input [3:0]      e_reason;
        input            had_stream;
        input            has_out;
        begin
            chk_cnts;
            if (had_stream) begin
                req(meta_dec == e_dec, "steer decision (RELAY=2/LOCAL=1/DROP=0/ARP=3)");
                if (e_dec == 3'd0) req(meta_reason == e_reason, "steer drop reason");
                chk_meta;
            end else if (!arp_seen) begin
                req(last_drop_reason == e_reason, "extract drop reason");
            end
            if (has_out) chk_bytes;
            end_case(nm);
        end
    endtask

    //=========================================================================
    // 主流程
    //=========================================================================
    integer i, k;
    integer base_out, base_bytes;

    task do_reset;
        begin
            rst_n      = 1'b0;
            drv_active = 1'b0;
            drv_idx    = 0;
            ready_mode = 2'd0;
            o_ready    = 1'b1;
            repeat (8) @(negedge clk);
            rst_n = 1'b1;
            repeat (6) @(negedge clk);
        end
    endtask

    task run_frame;
        begin
            @(negedge clk);
            drv_idx    = 0;
            drv_active = 1'b1;
            while (drv_idx < frm_len) @(negedge clk);
            @(negedge clk);
            drv_active = 1'b0;
        end
    endtask

    task drain;
        integer n;
        begin
            n = 12 * frm_len + 600;
            repeat (n) @(negedge clk);
        end
    endtask

    initial begin
        //---------------------------------------------------------------------
        // 初始化
        //---------------------------------------------------------------------
        rst_n        = 1'b0;
        drv_active   = 1'b0;
        drv_idx      = 0;
        ready_mode   = 2'd0;
        o_ready      = 1'b1;
        frm_len      = 0;
        cap_len      = 0;
        out_frames   = 0;
        out_bytes    = 0;
        last_out_len = 0;
        pass_cnt     = 0;
        fail_cnt     = 0;
        chk_fail     = 1'b0;
        m_rx = 0; m_relay = 0; m_local = 0; m_arp = 0;
        m_dvlan = 0; m_dipv6 = 0; m_detype = 0; m_dbcast = 0; m_dmcast = 0;
        m_dunk = 0; m_dover = 0; m_dcsum = 0; m_dtrunc = 0; m_dmac = 0;
        m_out = 0;
        m_out_bytes = 0;
        acc32 = 32'd0;
        acc16 = 16'd0;
        csum_field = 16'd0;
        exp_frame_len = 0;

        $display("==============================================================");
        $display(" prj13 P2 v0.2 pipeline TB  (extract -> steer -> rewrap)");
        $display("==============================================================");

        do_reset;

        //=====================================================================
        // C01 正常转发：1472 B IP 包（真 IP + UDP checksum）
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd1472, 8'd17, 8'd64, 8'd0, 3'b010, 13'd0,
               PC1_IP, PEER_IP, 16'h1234);
        // UDP: sport 1234, dport 47001, len 1452
        frm[34] = 8'h04; frm[35] = 8'hD2;
        frm[36] = 8'hB7; frm[37] = 8'h99;
        frm[38] = 8'h05; frm[39] = 8'hAC;
        frm[40] = 8'h00; frm[41] = 8'h00;
        for (i = 42; i < 14 + 1472; i = i + 1) frm[i] = (i * 7 + 3);
        udp_csum(34, 16'd1452, PC1_IP, PEER_IP);

        ip_csum_check(4'd5);
        req(acc16 == 16'hFFFF, "C01 IP checksum well-formed");
        // UDP 校验和自校验（UDP 段 + 伪头 折叠应 = 0xFFFF）
        acc32 = 32'd0;
        sum_frm(34, 1452);
        sum_frm(1640, 12);
        fold_acc;
        req(acc16 == 16'hFFFF, "C01 UDP checksum well-formed");

        frm_len = 14 + 1472;
        build_expected(1472);
        m_rx = m_rx + 1; m_relay = m_relay + 1; m_out = m_out + 1;
        m_out_bytes = m_out_bytes + exp_frame_len;
        run_frame;
        drain;
        chk_all("C01_normal_relay_1472", 3'd2, 4'd0, 1'b1, 1'b1);
        req(rw_len_err_cnt == 0, "C01 no len_err");

        //=====================================================================
        // C02 <60 B 补零：26 B IP 包 -> 60 B 帧
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd26, 8'd253, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h0002);
        for (i = 34; i < 14 + 26; i = i + 1) frm[i] = 8'hA0 + (i - 34);
        frm_len = 14 + 26;
        build_expected(26);
        m_rx = m_rx + 1; m_relay = m_relay + 1; m_out = m_out + 1;
        m_out_bytes = m_out_bytes + exp_frame_len;
        run_frame;
        drain;
        chk_all("C02_tiny_pad_26_to_60", 3'd2, 4'd0, 1'b1, 1'b1);
        req(cap_len == 60, "C02 output frame len == 60");
        req(rw_len_err_cnt == 0, "C02 no len_err");

        //=====================================================================
        // C03 DROP_VLAN (0x8100)
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h8100);
        frm[14] = 8'h00; frm[15] = 8'h64; frm[16] = 8'h08; frm[17] = 8'h00;
        for (i = 18; i < 60; i = i + 1) frm[i] = 8'h11;
        frm_len = 60;
        m_rx = m_rx + 1; m_dvlan = m_dvlan + 1;
        run_frame;
        drain;
        chk_all("C03_drop_vlan", 3'd0, 4'd1, 1'b0, 1'b0);
        req(arp_seen == 1'b0, "C03 not ARP");

        //=====================================================================
        // C04 DROP_IPV6 (0x86DD)
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h86DD);
        frm[14] = 8'h60;
        for (i = 15; i < 62; i = i + 1) frm[i] = 8'h22;
        frm_len = 62;
        m_rx = m_rx + 1; m_dipv6 = m_dipv6 + 1;
        run_frame;
        drain;
        chk_all("C04_drop_ipv6", 3'd0, 4'd2, 1'b0, 1'b0);
        req(arp_seen == 1'b0, "C04 not ARP");

        //=====================================================================
        // C05 DROP_ETHERTYPE (0x1234)
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h1234);
        for (i = 14; i < 60; i = i + 1) frm[i] = 8'h33;
        frm_len = 60;
        m_rx = m_rx + 1; m_detype = m_detype + 1;
        run_frame;
        drain;
        chk_all("C05_drop_ethertype", 3'd0, 4'd3, 1'b0, 1'b0);
        req(arp_seen == 1'b0, "C05 not ARP");

        //=====================================================================
        // C06 DROP_BROADCAST（以太网广播 + IP 非本板）
        //=====================================================================
        set_eth(BCAST_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd60, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, {8'd192, 8'd168, 8'd50, 8'd99}, 16'h0006);
        for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'h44;
        frm_len = 14 + 60;
        m_rx = m_rx + 1; m_dbcast = m_dbcast + 1;
        run_frame;
        drain;
        chk_all("C06_drop_broadcast", 3'd0, 4'd4, 1'b1, 1'b0);
        req(meta_reason == 4'd4, "C06 reason DROP_BROADCAST");

        //=====================================================================
        // C07 DROP_MULTICAST（以太网组播；ip_dst 即便是 PEER_IP 也先被 MAC 层丢）
        //=====================================================================
        set_eth(MCAST_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd60, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h0007);
        for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'h55;
        frm_len = 14 + 60;
        m_rx = m_rx + 1; m_dmcast = m_dmcast + 1;
        run_frame;
        drain;
        chk_all("C07_drop_multicast", 3'd0, 4'd5, 1'b1, 1'b0);
        req(meta_reason == 4'd5, "C07 reason DROP_MULTICAST");

        //=====================================================================
        // C08 DROP_UNKNOWN_DST (8.8.8.8) —— 防乒乓红线
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd60, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, UNKNOWN_IP, 16'h0008);
        for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'h66;
        frm_len = 14 + 60;
        m_rx = m_rx + 1; m_dunk = m_dunk + 1;
        run_frame;
        drain;
        chk_all("C08_drop_unknown_dst", 3'd0, 4'd6, 1'b1, 1'b0);
        req(meta_reason == 4'd6, "C08 reason DROP_UNKNOWN_DST");

        //=====================================================================
        // C09 DROP_OVERSIZE (total_len = 1501)
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd1501, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h0009);
        for (i = 34; i < 14 + 1501; i = i + 1) frm[i] = (i & 8'hFF);
        frm_len = 14 + 1501;
        m_rx = m_rx + 1; m_dover = m_dover + 1;
        run_frame;
        drain;
        chk_all("C09_drop_oversize_1501", 3'd0, 4'd7, 1'b0, 1'b0);
        req(arp_seen == 1'b0, "C09 not ARP");

        //=====================================================================
        // C10 DROP_BAD_CSUM（改动 TTL 制造校验和错）
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd60, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h000A);
        for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'h77;
        frm[22] = frm[22] ^ 8'h01;                 // TTL 翻一位 -> 校验和错
        ip_csum_check(4'd5);
        req((acc16 != 16'hFFFF) && (acc16 != 16'h0000), "C10 corrupt vector really invalid");
        frm_len = 14 + 60;
        m_rx = m_rx + 1; m_dcsum = m_dcsum + 1;
        run_frame;
        drain;
        chk_all("C10_drop_bad_csum", 3'd0, 4'd8, 1'b0, 1'b0);
        req(arp_seen == 1'b0, "C10 not ARP");

        //=====================================================================
        // C11 DROP_TRUNCATED（帧长 60 < 14+total_len=114）
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd100, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h000B);
        for (i = 34; i < 60; i = i + 1) frm[i] = 8'h88;
        frm_len = 60;
        m_rx = m_rx + 1; m_dtrunc = m_dtrunc + 1;
        run_frame;
        drain;
        chk_all("C11_drop_truncated", 3'd0, 4'd9, 1'b0, 1'b0);
        req(arp_seen == 1'b0, "C11 not ARP");

        //=====================================================================
        // C12 DROP_MAC（eth_dst 非本板、非广播/组播）
        //=====================================================================
        set_eth(OTHER_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd60, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h000C);
        for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'h99;
        frm_len = 14 + 60;
        m_rx = m_rx + 1; m_dmac = m_dmac + 1;
        run_frame;
        drain;
        chk_all("C12_drop_mac", 3'd0, 4'd10, 1'b0, 1'b0);
        req(arp_seen == 1'b0, "C12 not ARP");

        //=====================================================================
        // C13 ARP 不跨板：广播 ARP request -> ARP/LOCAL，rewrap 无输出
        //=====================================================================
        set_eth(BCAST_MAC, PC1_MAC, 16'h0806);
        frm[14] = 8'h00; frm[15] = 8'h01;          // htype = 1
        frm[16] = 8'h08; frm[17] = 8'h00;          // ptype = 0x0800
        frm[18] = 8'h06;                            // hlen
        frm[19] = 8'h04;                            // plen
        frm[20] = 8'h00; frm[21] = 8'h01;           // opcode = request
        frm[22] = PC1_MAC[47:40]; frm[23] = PC1_MAC[39:32];
        frm[24] = PC1_MAC[31:24]; frm[25] = PC1_MAC[23:16];
        frm[26] = PC1_MAC[15:8];  frm[27] = PC1_MAC[7:0];
        frm[28] = PC1_IP[31:24];  frm[29] = PC1_IP[23:16];
        frm[30] = PC1_IP[15:8];   frm[31] = PC1_IP[7:0];
        frm[32] = 8'h00; frm[33] = 8'h00; frm[34] = 8'h00;
        frm[35] = 8'h00; frm[36] = 8'h00; frm[37] = 8'h00;
        frm[38] = PEER_IP[31:24]; frm[39] = PEER_IP[23:16];
        frm[40] = PEER_IP[15:8];  frm[41] = PEER_IP[7:0];
        frm_len = 42;
        m_rx = m_rx + 1; m_arp = m_arp + 1;
        run_frame;
        drain;
        chk_cnts;
        req(arp_seen == 1'b1, "C13 ARP event seen");
        req(meta_dec == 3'd3, "C13 decision == ARP(3)");
        req(meta_reason == 4'd0, "C13 ARP reason NONE");
        end_case("C13_arp_local_no_cross");

        //=====================================================================
        // C14 无乒乓：连续 3 帧 8.8.8.8 全 DROP，输出 0 字节
        //=====================================================================
        base_out   = out_frames;
        base_bytes = out_bytes;
        for (k = 0; k < 3; k = k + 1) begin
            set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
            ip_hdr(4'd5, 16'd60, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
                   PC1_IP, UNKNOWN_IP, 16'h0010 + k);
            for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'hA5;
            frm_len = 14 + 60;
            m_rx = m_rx + 1; m_dunk = m_dunk + 1;
            run_frame;
            drain;
            req(meta_dec == 3'd0, "C14 decision DROP");
            req(meta_reason == 4'd6, "C14 reason DROP_UNKNOWN_DST");
        end
        chk_cnts;
        req(out_frames == base_out, "C14 no ping-pong: zero output frames");
        req(out_bytes == base_bytes, "C14 no ping-pong: zero output bytes");
        end_case("C14_no_pingpong_x3");

        //=====================================================================
        // C15 分片透传：MF=1 + frag_off=1480，无重组
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd1480, 8'd17, 8'd63, 8'd0, 3'b001, 13'd1480,
               PC1_IP, PEER_IP, 16'h0015);
        for (i = 34; i < 14 + 1480; i = i + 1) frm[i] = (i * 5 + 1);
        frm_len = 14 + 1480;
        build_expected(1480);
        m_rx = m_rx + 1; m_relay = m_relay + 1; m_out = m_out + 1;
        m_out_bytes = m_out_bytes + exp_frame_len;
        run_frame;
        drain;
        chk_all("C15_fragment_passthru", 3'd2, 4'd0, 1'b1, 1'b1);
        req(saw_is_fragment == 1'b1, "C15 m_is_fragment == 1");
        req(meta_frag_off == 13'd1480, "C15 frag_off preserved");

        //=====================================================================
        // C16 背压：m_ready 用 LFSR 随机，1472 B 仍逐字节正确
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd1472, 8'd17, 8'd64, 8'd0, 3'b010, 13'd0,
               PC1_IP, PEER_IP, 16'h0016);
        frm[34] = 8'h04; frm[35] = 8'hD2;
        frm[36] = 8'hB7; frm[37] = 8'h99;
        frm[38] = 8'h05; frm[39] = 8'hAC;
        frm[40] = 8'h00; frm[41] = 8'h00;
        for (i = 42; i < 14 + 1472; i = i + 1) frm[i] = (i * 11 + 7);
        udp_csum(34, 16'd1452, PC1_IP, PEER_IP);
        frm_len = 14 + 1472;
        build_expected(1472);
        ready_mode = 2'd1;                 // 打随机 backpressure
        m_rx = m_rx + 1; m_relay = m_relay + 1; m_out = m_out + 1;
        m_out_bytes = m_out_bytes + exp_frame_len;
        run_frame;
        drain;
        ready_mode = 2'd0;
        repeat (20) @(negedge clk);
        chk_all("C16_backpressure_lfsr", 3'd2, 4'd0, 1'b1, 1'b1);
        req(rw_len_err_cnt == 0, "C16 no len_err");

        //=====================================================================
        // C17 checksum 边界 A：checksum 字段 = 0x0000（反码"零"端点）
        //   命中条件：其余字段折叠和 = 0xFFFF。合法头必须被接受并透传。
        //   这条也覆盖"把 0x0000 误当未计算/未校验"的实现缺陷。
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd48, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h0000);
        for (i = 34; i < 14 + 48; i = i + 1) frm[i] = 8'hC1;
        csum_search(16'h0000);
        req(csum_field == 16'h0000, "C17 checksum field == 0x0000");
        ip_csum_check(4'd5);
        req(acc16 == 16'hFFFF, "C17 folded total == 0xFFFF");
        frm_len = 14 + 48;
        build_expected(48);
        m_rx = m_rx + 1; m_relay = m_relay + 1; m_out = m_out + 1;
        m_out_bytes = m_out_bytes + exp_frame_len;
        run_frame;
        drain;
        chk_all("C17_csum_boundary_0000", 3'd2, 4'd0, 1'b1, 1'b1);

        //=====================================================================
        // C18 checksum 边界 B：checksum 字段 = 0xFFFF（另一端）
        //   注意：**合法** IPv4 头不可能出现 checksum 字段 = 0xFFFF ——
        //   那要求"其余字段之和"恰好 = 0x0000，而 version/ihl 字节恒为 0x45，
        //   反码折叠对非零和只在 0xFFFF 表示零（证明见 sim/p2/README.md）。
        //   所以这一端只能作为"必须被拒"的边界向量：字段被强行改成 0xFFFF 后
        //   折叠总和不再等于 0xFFFF，必须 DROP_BAD_CSUM。
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd48, 8'd17, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, PEER_IP, 16'h00FF);
        for (i = 34; i < 14 + 48; i = i + 1) frm[i] = 8'hC2;
        ip_csum(4'd5);
        req({frm[24], frm[25]} != 16'hFFFF, "C18 base vector not already 0xFFFF");
        frm[24] = 8'hFF;
        frm[25] = 8'hFF;
        ip_csum_check(4'd5);
        req((acc16 != 16'hFFFF) && (acc16 != 16'h0000),
            "C18 vector with field=0xFFFF is really invalid");
        frm_len = 14 + 48;
        m_rx = m_rx + 1; m_dcsum = m_dcsum + 1;
        run_frame;
        drain;
        chk_all("C18_csum_boundary_ffff", 3'd0, 4'd8, 1'b0, 1'b0);

        //=====================================================================
        // C19 LOCAL：dst=BOARD_IP 走本地栈（不跨板、不上 Aurora）
        //   覆盖判决表第 7 条 LOCAL 分支 + cnt_local 计数（否则该断言是空跑）
        //=====================================================================
        set_eth(BOARD_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd60, 8'd1, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, BOARD_IP, 16'h0019);
        for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'hDD;
        frm_len = 14 + 60;
        m_rx = m_rx + 1; m_local = m_local + 1;
        run_frame;
        drain;
        chk_all("C19_local_to_board_ip", 3'd1, 4'd0, 1'b1, 1'b0);
        req(meta_reason == 4'd0, "C19 LOCAL reason NONE");

        //=====================================================================
        // C20 LOCAL（广播 + 本板 IP）：判决表第 2 条的 LOCAL 那一支
        //   "以太网广播但 ip_dst==BOARD_IP" 必须本地收下，不能当广播丢掉
        //=====================================================================
        set_eth(BCAST_MAC, PC1_MAC, 16'h0800);
        ip_hdr(4'd5, 16'd60, 8'd1, 8'd64, 8'd0, 3'b000, 13'd0,
               PC1_IP, BOARD_IP, 16'h001A);
        for (i = 34; i < 14 + 60; i = i + 1) frm[i] = 8'hDE;
        frm_len = 14 + 60;
        m_rx = m_rx + 1; m_local = m_local + 1;
        run_frame;
        drain;
        chk_all("C20_local_bcast_to_board_ip", 3'd1, 4'd0, 1'b1, 1'b0);
        req(meta_reason == 4'd0, "C20 LOCAL(bcast+BOARD_IP) reason NONE");

        //=====================================================================
        // 收尾
        //=====================================================================
        repeat (50) @(negedge clk);
        chk_cnts;
        req(rw_len_err_cnt == 0, "global: eth_rewrap o_len_err never asserted");
        req(m_local == 2, "global: LOCAL path really exercised (cnt_local==2)");
        end_case("C21_global_counters_clean");

        $display("--------------------------------------------------------------");
        $display("P2_TB: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        $display("--------------------------------------------------------------");
        if (fail_cnt != 0) $display("P2_TB: RESULT=FAIL");
        else               $display("P2_TB: RESULT=PASS");
        $finish;
    end

endmodule
