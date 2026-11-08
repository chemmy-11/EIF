//=============================================================================
// tb_p2_frame_buf.v  --  prj13 P2 集成层单元 TB：p2_frame_buf（v2）
//-----------------------------------------------------------------------------
// 测什么（Lead 指定的 I05 + v2 侧带）：
//   FB01  写侧连写 2 帧而读侧**不消费** -> 两个 bank 占满，o_wr_frame_cnt=2
//   FB02  再来第 3 帧 -> **整帧丢弃**：o_wr_drop_cnt=1，且不产生半个可读帧
//   FB03  放开读侧 -> 读出的帧数仍是 2、两帧内容逐字节正确（丢的是整帧，不是半帧）
//   FB04  v2 侧带 o_rd_eth_dst/o_rd_eth_type 必须**跟帧走**：
//         两帧不同 MAC/EtherType，读侧各自取到自己的（不是最后一帧的）
//
// 判据行：P2_FRAMEBUF_TB: PASS=<n> FAIL=<m>
// 编码：纯 Verilog-2001，单时钟，异步低有效复位。
//=============================================================================
`timescale 1ns / 1ps

module tb_p2_frame_buf;

    localparam integer AW = 11;              // bank 深度 2048 B（与集成件一致）
    localparam integer BD = (1 << AW);

    //=========================================================================
    // 时钟 / 复位
    //=========================================================================
    reg clk;
    reg rst_n;
    initial clk = 1'b0;
    always #5 clk = ~clk;                    // 100 MHz

    //=========================================================================
    // DUT
    //=========================================================================
    reg  [7:0]  wr_data;
    reg         wr_en;
    wire [15:0] wr_frame_cnt;
    wire [15:0] wr_drop_cnt;
    wire [7:0]  rd_data;
    wire        rd_valid;
    wire        rd_sop;
    wire        rd_eop;
    reg         rd_ready;
    wire [15:0] rd_frame_cnt;
    wire [47:0] rd_eth_dst;
    wire [15:0] rd_eth_type;
    wire [1:0]  bank_busy;

    p2_frame_buf #(.AW(AW)) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .wr_data        (wr_data),
        .wr_en          (wr_en),
        .o_wr_frame_cnt (wr_frame_cnt),
        .o_wr_drop_cnt  (wr_drop_cnt),
        .rd_data        (rd_data),
        .rd_valid       (rd_valid),
        .rd_sop         (rd_sop),
        .rd_eop         (rd_eop),
        .rd_ready       (rd_ready),
        .o_rd_frame_cnt (rd_frame_cnt),
        .o_rd_eth_dst   (rd_eth_dst),
        .o_rd_eth_type  (rd_eth_type),
        .o_bank_busy    (bank_busy)
    );

    //=========================================================================
    // 期望帧 / 捕获
    //=========================================================================
    reg [7:0] frm_a [0:2047];
    reg [7:0] frm_b [0:2047];
    reg [7:0] frm_c [0:2047];
    reg [7:0] frm_d [0:4095];        // 超 bank 容量帧（FB05，2100 B > 2048）
    reg [7:0] frm_e [0:2047];        // FB05 之后紧跟的正常帧
    integer   len_a, len_b, len_c, len_d, len_e;

    reg [7:0] cap [0:8191];
    integer   total_cap;
    integer   nfr;
    integer   fr_start [0:15];
    integer   fr_end   [0:15];
    reg [47:0] fr_dst  [0:15];
    reg [15:0] fr_typ  [0:15];

    integer pass_cnt, fail_cnt;
    reg     chk_fail;

    always @(posedge clk) begin
        if (rd_valid && rd_ready) begin
            if (rd_sop) begin
                fr_start[nfr] = total_cap;
                fr_dst[nfr]   = rd_eth_dst;
                fr_typ[nfr]   = rd_eth_type;
            end
            cap[total_cap] = rd_data;
            total_cap      = total_cap + 1;
            if (rd_eop) begin
                fr_end[nfr] = total_cap;
                nfr         = nfr + 1;
            end
        end
    end

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

    //=========================================================================
    // 驱动
    //=========================================================================
    task do_reset;
        begin
            rst_n    = 1'b0;
            wr_en    = 1'b0;
            wr_data  = 8'd0;
            rd_ready = 1'b0;
            repeat (8) @(negedge clk);
            rst_n = 1'b1;
            repeat (4) @(negedge clk);
        end
    endtask

    // 写一帧：wr_en 高 len 拍，前后各留低电平（en 的上升/下降界定帧）
    task wr_frame;
        input integer which;      // 0=a 1=b 2=c 3=d(超长) 4=e
        input integer len;
        integer i;
        begin
            for (i = 0; i < len; i = i + 1) begin
                @(negedge clk);
                wr_en   = 1'b1;
                if (which == 0)      wr_data = frm_a[i];
                else if (which == 1) wr_data = frm_b[i];
                else if (which == 2) wr_data = frm_c[i];
                else if (which == 3) wr_data = frm_d[i];
                else                 wr_data = frm_e[i];
            end
            @(negedge clk);
            wr_en   = 1'b0;
            wr_data = 8'd0;
        end
    endtask

    task wait_clk;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(negedge clk);
        end
    endtask

    //=========================================================================
    // 主流程
    //=========================================================================
    integer i, ok;
    integer base, base_cap, base_fr, d_drop0;

    initial begin
        rst_n = 1'b0; wr_en = 1'b0; wr_data = 8'd0; rd_ready = 1'b0;
        total_cap = 0; nfr = 0; pass_cnt = 0; fail_cnt = 0; chk_fail = 1'b0;
        for (i = 0; i < 16; i = i + 1) begin fr_start[i]=0; fr_end[i]=0; fr_dst[i]=0; fr_typ[i]=0; end

        $display("==============================================================");
        $display(" p2_frame_buf unit TB (v2: whole-frame drop + per-frame sideband)");
        $display("==============================================================");

        //---------------------------------------------------------------------
        // 构造 3 帧：A/B 各自不同的 MAC 与 EtherType（考侧带跟帧走）
        //---------------------------------------------------------------------
        len_a = 100;
        for (i = 0; i < len_a; i = i + 1) frm_a[i] = (i * 3 + 1);
        // 以太头：dst = 02:00:00:00:0A_AA, type = 0x0800
        frm_a[0]=8'h02; frm_a[1]=8'h00; frm_a[2]=8'h00;
        frm_a[3]=8'h00; frm_a[4]=8'h0A; frm_a[5]=8'hAA;
        frm_a[12]=8'h08; frm_a[13]=8'h00;

        len_b = 60;
        for (i = 0; i < len_b; i = i + 1) frm_b[i] = (i * 5 + 2);
        frm_b[0]=8'h02; frm_b[1]=8'h00; frm_b[2]=8'h00;
        frm_b[3]=8'h00; frm_b[4]=8'h0B; frm_b[5]=8'hBB;
        frm_b[12]=8'h08; frm_b[13]=8'h06;

        len_c = 50;
        for (i = 0; i < len_c; i = i + 1) frm_c[i] = (i * 7 + 3);

        // FB05 用：2100 B（> 2^AW = 2048，触发 wr_toobig 整帧丢弃）
        len_d = 2100;
        for (i = 0; i < len_d; i = i + 1) frm_d[i] = (i * 11 + 5);
        frm_d[0]=8'h02; frm_d[1]=8'h00; frm_d[2]=8'h00;
        frm_d[3]=8'h00; frm_d[4]=8'h0C; frm_d[5]=8'hCC;
        frm_d[12]=8'h08; frm_d[13]=8'h00;

        // FB05 用：超长帧之后的正常帧（100 B，dst/type 与前面都不同）
        len_e = 100;
        for (i = 0; i < len_e; i = i + 1) frm_e[i] = (i * 13 + 7);
        frm_e[0]=8'h02; frm_e[1]=8'h00; frm_e[2]=8'h00;
        frm_e[3]=8'h00; frm_e[4]=8'h0D; frm_e[5]=8'hDD;
        frm_e[12]=8'h08; frm_e[13]=8'h00;

        do_reset;

        //=====================================================================
        // FB01：写 A、B 两帧，读侧不消费 -> 两 bank 占满
        //=====================================================================
        wr_frame(0, len_a);
        wait_clk(2);
        wr_frame(1, len_b);
        wait_clk(4);
        req(wr_frame_cnt == 16'd2, "FB01 o_wr_frame_cnt == 2");
        req(wr_drop_cnt  == 16'd0, "FB01 no drop yet");
        req(bank_busy == 2'b11,    "FB01 both banks busy");
        end_case("FB01_two_frames_buffered");

        //=====================================================================
        // FB02：第 3 帧 -> 整帧丢弃（不放半帧进 bank）
        //=====================================================================
        wr_frame(2, len_c);
        wait_clk(4);
        req(wr_drop_cnt == 16'd1, "FB02 o_wr_drop_cnt == 1 (whole frame dropped)");
        req(wr_frame_cnt == 16'd2, "FB02 o_wr_frame_cnt still 2 (no half frame stored)");
        req((rd_frame_cnt == 16'd0) || (rd_frame_cnt <= 16'd1), "FB02 no extra readable frame");
        end_case("FB02_third_frame_whole_drop");

        //=====================================================================
        // FB03：放开读侧 -> 只有 A、B 两帧，且逐字节正确
        //=====================================================================
        rd_ready = 1'b1;
        wait_clk(4 * (len_a + len_b) + 200);
        req(nfr == 2, "FB03 exactly 2 frames readable");
        req(rd_frame_cnt == 16'd2, "FB03 o_rd_frame_cnt == 2");
        req(wr_drop_cnt == 16'd1, "FB03 drop count unchanged");

        ok = 1'b1;
        if ((fr_end[0] - fr_start[0]) != len_a) begin
            ok = 1'b0;
            $display("  [DET] frame0 len=%0d exp=%0d", fr_end[0]-fr_start[0], len_a);
        end
        for (i = 0; i < len_a; i = i + 1) begin
            if (cap[fr_start[0]+i] !== frm_a[i]) begin
                if (ok) $display("  [DET] A byte[%0d]=%02h exp=%02h", i, cap[fr_start[0]+i], frm_a[i]);
                ok = 1'b0;
            end
        end
        req(ok, "FB03 frame A byte-identical");

        ok = 1'b1;
        if ((fr_end[1] - fr_start[1]) != len_b) begin
            ok = 1'b0;
            $display("  [DET] frame1 len=%0d exp=%0d", fr_end[1]-fr_start[1], len_b);
        end
        for (i = 0; i < len_b; i = i + 1) begin
            if (cap[fr_start[1]+i] !== frm_b[i]) begin
                if (ok) $display("  [DET] B byte[%0d]=%02h exp=%02h", i, cap[fr_start[1]+i], frm_b[i]);
                ok = 1'b0;
            end
        end
        req(ok, "FB03 frame B byte-identical");
        end_case("FB03_read_two_frames_bytewise");

        //=====================================================================
        // FB04：v2 侧带跟帧走（两帧 MAC/EtherType 不同，各取各的）
        //=====================================================================
        req(fr_dst[0] == 48'h02_00_00_00_0A_AA, "FB04 frame A sideband eth_dst");
        req(fr_typ[0] == 16'h0800,              "FB04 frame A sideband eth_type");
        req(fr_dst[1] == 48'h02_00_00_00_0B_BB, "FB04 frame B sideband eth_dst (not overwritten)");
        req(fr_typ[1] == 16'h0806,              "FB04 frame B sideband eth_type (not overwritten)");
        end_case("FB04_sideband_follows_frame");

        //=====================================================================
        // FB05：超 bank 容量（2100 B > 2048）-> 整帧丢弃，绝不发布被截断的半帧
        //   再紧跟一帧正常帧 -> 必须能读出且逐字节正确（证明 bank 没被脏占）
        //   （这条钉的是 2026-11-08 修掉的 ovf 缺陷：原来 wr_cnt 被冻在 2047，
        //     帧尾照样发布 => 读侧会拿到 2047 B 的**截断帧**）
        //=====================================================================
        rd_ready    = 1'b1;                  // 读侧随时可读：真发布了截断帧必被抓到
        wait_clk(4);
        base_cap    = total_cap;
        base_fr     = nfr;
        d_drop0     = wr_drop_cnt;

        wr_frame(3, len_d);                  // 2100 B
        wait_clk(400);

        req(wr_drop_cnt  == d_drop0 + 16'd1, "FB05 o_wr_drop_cnt +1 (whole frame dropped)");
        req(wr_frame_cnt == 16'd2,           "FB05 o_wr_frame_cnt unchanged (nothing published)");
        req(nfr          == base_fr,         "FB05 read side saw ZERO new frames");
        req(total_cap    == base_cap,        "FB05 read side saw ZERO new bytes (no truncated frame)");

        // 紧跟一帧正常帧：bank 必须还能用
        wr_frame(4, len_e);
        wait_clk(4 * len_e + 200);

        req(wr_frame_cnt == 16'd3,     "FB05 next normal frame accepted (o_wr_frame_cnt == 3)");
        req(wr_drop_cnt  == d_drop0 + 16'd1, "FB05 drop count unchanged by the normal frame");
        req(nfr          == base_fr + 1, "FB05 next normal frame readable");
        ok = 1'b1;
        if ((fr_end[nfr-1] - fr_start[nfr-1]) != len_e) begin
            ok = 1'b0;
            $display("  [DET] FB05 frame len=%0d exp=%0d", fr_end[nfr-1]-fr_start[nfr-1], len_e);
        end
        for (i = 0; i < len_e; i = i + 1) begin
            if (cap[fr_start[nfr-1]+i] !== frm_e[i]) begin
                if (ok) $display("  [DET] FB05 byte[%0d]=%02h exp=%02h", i, cap[fr_start[nfr-1]+i], frm_e[i]);
                ok = 1'b0;
            end
        end
        req(ok, "FB05 post-oversize frame byte-identical");
        req(fr_dst[nfr-1] == 48'h02_00_00_00_0D_DD, "FB05 post-oversize sideband eth_dst");
        end_case("FB05_oversize_whole_drop");

        $display("--------------------------------------------------------------");
        $display("P2_FRAMEBUF_TB: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0) $display("P2_FRAMEBUF_TB: RESULT=FAIL");
        else               $display("P2_FRAMEBUF_TB: RESULT=PASS");
        $display("--------------------------------------------------------------");
        $finish;
    end

endmodule
