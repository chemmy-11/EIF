# R2 离线回归 TB 补丁说明（Lead 授权：只加 tie，不改用例语义）

> 背景：R2 改了共享模块端口/写路径契约，三个 R1 回归 TB 需最小端口补齐才能编译。
> 除 `bridge_dma_tb` 的"最小 S2MM 服务模型"外，其余均为纯 tie；补丁全部为 `sim/*.sv`，不改 `rtl/`、不改用例断言。

## 1. mem_bridge_tb.v / w4_joint_tb.sv（HAS_DMA=0）：纯端口 tie

`frame_mem_if` 实例追加 12 根 B3-2 端口 tie：`dma_wr_go/ack=0`、`s2mm_introut=0`、`dma_wr_t*` 输出悬空、`dma_wr_tready=0`、`ro_dma_wr_*`/`ro_stat_wr_timeout`/`ro_dbg_wr_state` 悬空。HAS_DMA=0 分支内部本就钉常量，显式 tie 只防 X 推理。**用例语义 0 改动。**

## 2. bridge_dma_tb.sv（直例化 axi4_master_bridge，HAS_DMA=1）：tie + 最小 S2MM 服务模型

**为什么"只加 tie"不够（对 Lead 指令的订正）**：该 TB 原语义 = "写 n 帧后 `stat_wm` 递增、再按槽读回逐字节比对"，其写提交原由 AXI 写 + B 响应完成。R2 后 HAS_DMA=1 的写路径改为 WD_* S2MM：若仅把 `dma_wr_go=0/s2mm_introut=0` 钉住，每帧会在 WAITGO 等满 24 位看门狗（≈56ms 仿真）后被丢弃、`stat_wm` 恒不增 ⇒ 用例必然 FAIL 且仿真极慢。

故在**不改读路径、不改断言**的前提下补一个 ~45 行行为级服务模型（位于 TB 内）：检测 `{pending,toggle}` 变化 → 清 IOC → 3 拍后翻 `dma_wr_go` → 按 TKEEP 把 512b 流写进 TB 的 `ddr[]`（与读侧 18-bit 掩码口径一致）→ TLAST 后 2 拍拉 `s2mm_introut`（桥在此 commit）→ 再落 0 回 IDLE。

R2 写路径的正式判据在独立 TB `r2_wr_tb.sv`；本补丁只恢复该回归的"写后可读"语义。

## 3. 逐文件 diff（`git diff`，相对 HEAD）

### `mem_bridge_tb.sv`

```diff
diff --git a/prj/project_11/sim/mem_bridge_tb.sv b/prj/project_11/sim/mem_bridge_tb.sv
index f6984c3..6fbd044 100644
--- a/prj/project_11/sim/mem_bridge_tb.sv
+++ b/prj/project_11/sim/mem_bridge_tb.sv
@@ -133,7 +133,12 @@ module mem_bridge_tb #(
         // B3-1b: DMA engine ports tied off (bridge-engine regression path)
         .dma_engine(1'b0), .dma_s_tdata(512'd0), .dma_s_tkeep(64'd0),
         .dma_s_tlast(1'b0), .dma_s_tvalid(1'b0), .dma_s_tready(),
-        .ro_dma_req());
+        .ro_dma_req(),
+        // R2（B3-2）最小端口补齐：只加 tie，不改用例语义（HAS_DMA=0 分支内部已钉常量）
+        .dma_wr_go(1'b0), .dma_wr_ack(1'b0), .s2mm_introut(1'b0),
+        .dma_wr_tdata(), .dma_wr_tkeep(), .dma_wr_tlast(), .dma_wr_tvalid(),
+        .dma_wr_tready(1'b0),
+        .ro_dma_wr_req(), .ro_dma_wr_dbg(), .ro_stat_wr_timeout(), .ro_dbg_wr_state());
 
     axi4_ram_model #(.MEM_BYTES(1<<20), .AR_LAT(AR_LAT_T), .W_RESP_DLY(W_DLY_T),
                      .STALL_EN(STALL_EN_T)) u_ram (

```

### `w4_joint_tb.sv`

```diff
diff --git a/prj/project_11/sim/w4_joint_tb.sv b/prj/project_11/sim/w4_joint_tb.sv
index 42d2365..7b28a7c 100644
--- a/prj/project_11/sim/w4_joint_tb.sv
+++ b/prj/project_11/sim/w4_joint_tb.sv
@@ -174,7 +174,12 @@ module w4_joint_tb #(
         // B3-1b: DMA engine ports tied off (bridge-engine regression path)
         .dma_engine(1'b0), .dma_s_tdata(512'd0), .dma_s_tkeep(64'd0),
         .dma_s_tlast(1'b0), .dma_s_tvalid(1'b0), .dma_s_tready(),
-        .ro_dma_req());
+        .ro_dma_req(),
+        // R2（B3-2）最小端口补齐：只加 tie，不改用例语义（HAS_DMA=0 分支内部已钉常量）
+        .dma_wr_go(1'b0), .dma_wr_ack(1'b0), .s2mm_introut(1'b0),
+        .dma_wr_tdata(), .dma_wr_tkeep(), .dma_wr_tlast(), .dma_wr_tvalid(),
+        .dma_wr_tready(1'b0),
+        .ro_dma_wr_req(), .ro_dma_wr_dbg(), .ro_stat_wr_timeout(), .ro_dbg_wr_state());
 
     frame_mem_if #(.SLOT_BASE(32'h0020_0000), .MAX_LEN(16'd1538), .HAS_DMA(0)) u_memB (
         .user_clk(user_clk), .user_rst_n(user_rst_n),
@@ -208,7 +213,12 @@ module w4_joint_tb #(
         // B3-1b: DMA engine ports tied off (bridge-engine regression path)
         .dma_engine(1'b0), .dma_s_tdata(512'd0), .dma_s_tkeep(64'd0),
         .dma_s_tlast(1'b0), .dma_s_tvalid(1'b0), .dma_s_tready(),
-        .ro_dma_req());
+        .ro_dma_req(),
+        // R2（B3-2）最小端口补齐：只加 tie，不改用例语义（HAS_DMA=0 分支内部已钉常量）
+        .dma_wr_go(1'b0), .dma_wr_ack(1'b0), .s2mm_introut(1'b0),
+        .dma_wr_tdata(), .dma_wr_tkeep(), .dma_wr_tlast(), .dma_wr_tvalid(),
+        .dma_wr_tready(1'b0),
+        .ro_dma_wr_req(), .ro_dma_wr_dbg(), .ro_stat_wr_timeout(), .ro_dbg_wr_state());
 
     generate
         if (DEFECT_ROUTING) begin : g_defect

```

### `bridge_dma_tb.sv`

```diff
diff --git a/prj/project_11/sim/bridge_dma_tb.sv b/prj/project_11/sim/bridge_dma_tb.sv
index 6919f1a..2c8f1d8 100644
--- a/prj/project_11/sim/bridge_dma_tb.sv
+++ b/prj/project_11/sim/bridge_dma_tb.sv
@@ -68,6 +68,27 @@ module bridge_dma_tb;
     wire [7:0]  dma_req_slot;
     wire [15:0] dma_req_len;
 
+    // ---- R2（B3-2）补丁：写路径已换 S2MM，原用例靠 "AXI 写 + B 响应" 提交；
+    //      本 TB 只补一个最小 S2MM 行为模型（软核协议 + 流->ddr），用例语义不变：
+    //      "写 n 帧后 stat_wm 递增、可按槽读回"。读路径部分零改动。
+    wire        dma_wr_req_toggle, dma_wr_req_pending;
+    wire [7:0]  dma_wr_req_slot;
+    wire [15:0] dma_wr_req_len;
+    wire [511:0] dma_wr_tdata;
+    wire [63:0]  dma_wr_tkeep;
+    wire        dma_wr_tlast, dma_wr_tvalid;
+    wire [15:0] stat_wr_timeout;
+    wire        dbg_wr_fault;
+    wire [7:0]  dbg_wr_last_slot;
+    wire [15:0] dbg_wr_last_len;
+    wire [2:0]  dbg_wr_state;
+    reg         dma_wr_go = 1'b0, s2mm_introut = 1'b0, dma_wr_tready = 1'b0;
+    reg         wr_model_last_tg = 1'b0;
+    reg  [1:0]  wr_model_st = 2'd0;
+    reg  [2:0]  wr_model_cnt = 3'd0;
+    reg  [7:0]  wr_model_slot = 8'd0;
+    reg  [15:0] wr_model_off = 16'd0;
+
     // ---- 简化 FIFO: TB 用数组 + 指针模拟 async_fifo 行为 (同钟单域) ----
     // 写字节 FIFO
     reg [7:0] wf_mem [0:4095];
@@ -142,7 +163,17 @@ module bridge_dma_tb;
         .dma_s_tdata(dma_s_tdata), .dma_s_tkeep(dma_s_tkeep),
         .dma_s_tlast(dma_s_tlast), .dma_s_tvalid(dma_s_tvalid),
         .dma_s_tready(dma_s_tready),
-        .dma_req_new(dma_req_new), .dma_req_slot(dma_req_slot), .dma_req_len(dma_req_len)
+        .dma_req_new(dma_req_new), .dma_req_slot(dma_req_slot), .dma_req_len(dma_req_len),
+        // R2（B3-2）最小端口补齐 + 写引擎服务模型（tie 仅为接口；服务模型见下方）
+        .dma_wr_go(dma_wr_go), .dma_wr_ack(1'b0), .s2mm_introut(s2mm_introut),
+        .m_axis_s2mm_tdata(dma_wr_tdata), .m_axis_s2mm_tkeep(dma_wr_tkeep),
+        .m_axis_s2mm_tlast(dma_wr_tlast), .m_axis_s2mm_tvalid(dma_wr_tvalid),
+        .m_axis_s2mm_tready(dma_wr_tready),
+        .dma_wr_req_toggle(dma_wr_req_toggle), .dma_wr_req_pending(dma_wr_req_pending),
+        .dma_wr_req_slot(dma_wr_req_slot), .dma_wr_req_len(dma_wr_req_len),
+        .stat_wr_timeout(stat_wr_timeout), .dbg_wr_fault(dbg_wr_fault),
+        .dbg_wr_last_slot(dbg_wr_last_slot), .dbg_wr_last_len(dbg_wr_last_len),
+        .dbg_wr_state(dbg_wr_state)
     );
 
     // B 通道: bvalid 保持到 bready 握手完成 (AXI 合法行为)
@@ -167,6 +198,64 @@ module bridge_dma_tb;
         end
     end
 
+    // ---- R2（B3-2）最小 S2MM 写引擎服务模型（行为级；只补写提交协议） ----
+    //   IDLE: 见到 {pending,toggle 变化} -> 清 IOC -> 3 拍后翻 GO
+    //   STREAM: 按 TKEEP 把 512b 流写进 ddr（与 read 侧 18bit 掩码口径一致）
+    //   DONE: 2 拍后拉 s2mm_introut 1（桥此时 commit），再落 0 回 IDLE
+    localparam [1:0] WM_IDLE = 2'd0, WM_GO = 2'd1, WM_STREAM = 2'd2, WM_DONE = 2'd3;
+    always @(posedge clk) begin
+        if (!rst_n) begin
+            wr_model_st <= WM_IDLE; wr_model_cnt <= 3'd0; wr_model_last_tg <= 1'b0;
+            wr_model_slot <= 8'd0; wr_model_off <= 16'd0;
+            dma_wr_go <= 1'b0; s2mm_introut <= 1'b0; dma_wr_tready <= 1'b0;
+        end else begin
+            case (wr_model_st)
+            WM_IDLE: begin
+                if (dma_wr_req_pending && (dma_wr_req_toggle !== wr_model_last_tg)) begin
+                    wr_model_last_tg <= dma_wr_req_toggle;
+                    wr_model_slot    <= dma_wr_req_slot;
+                    wr_model_off     <= 16'd0;
+                    s2mm_introut     <= 1'b0;          // 清 IOC
+                    wr_model_cnt     <= 3'd0;
+                    wr_model_st      <= WM_GO;
+                end
+            end
+            WM_GO: begin
+                wr_model_cnt <= wr_model_cnt + 3'd1;
+                if (wr_model_cnt == 3'd3) begin
+                    dma_wr_go      <= ~dma_wr_go;      // 软核已编程 -> 翻 GO
+                    dma_wr_tready  <= 1'b1;
+                    wr_model_st    <= WM_STREAM;
+                end
+            end
+            WM_STREAM: begin
+                if (dma_wr_tvalid && dma_wr_tready) begin
+                    for (int k = 0; k < 64; k++) begin
+                        if (dma_wr_tkeep[k])
+                            ddr[(SLOT_BASE + wr_model_slot*4096 + wr_model_off + k) & 18'h3FFFF]
+                                <= dma_wr_tdata[k*8 +: 8];
+                    end
+                    wr_model_off <= wr_model_off + 16'd64;
+                    if (dma_wr_tlast) begin
+                        dma_wr_tready <= 1'b0;
+                        wr_model_cnt  <= 3'd0;
+                        wr_model_st   <= WM_DONE;
+                    end
+                end
+            end
+            WM_DONE: begin
+                wr_model_cnt <= wr_model_cnt + 3'd1;
+                if (wr_model_cnt == 3'd1) s2mm_introut <= 1'b1;   // 完成中断
+                if (wr_model_cnt == 3'd5) begin
+                    s2mm_introut <= 1'b0;
+                    wr_model_st  <= WM_IDLE;
+                end
+            end
+            default: wr_model_st <= WM_IDLE;
+            endcase
+        end
+    end
+
     // ---- AXI 读从机: engine=0 时桥硬件读走这里 ----
     reg [31:0] ar_addr_q;
     reg [7:0]  r_beat_q;

```
