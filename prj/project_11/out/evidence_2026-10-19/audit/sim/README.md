# audit/sim —— 本轮 D（隔离单元仿真）未执行说明

状态：**SKIPPED（有意跳过，非失败）**。原因与后续计划如下。

## 1. 为什么本轮不做

1. **Lead 的 round3c 综合/实现正在本机运行**（12:08–12:2x，vivado 多进程 + 8 job 综合）：
   任务约束「xsim 类工具短时运行且不得与 Lead 的综合/实现并发冲突——若 Lead 构建在跑，等待或只做静态分析」。
2. 本轮的审计判据**不依赖新仿真**：lite fix2 的协议行为已由上一轮（2026-10-18）四份 xsim 日志直证
   （`out/evidence_2026-10-18/R2_sim_lite_proto_frozen_{r,w}.log`、`R2_sim_lite_proto_fix_{r,w}.log`：
   冻结版 1AR→5R/1AW+W→5B；fix2 版 1AR→1R、1AW+W→1B、背靠背 2 写 2/2/2 PASS）。
3. 本轮静态审计**没有发现新的"确定性缺陷"需要仿真先复现**：C 项的 round3d 候选补丁是"防御性结构修复"
   （邮箱超时/SLVERR/sticky/ASYNC_REG/4 个补盲检测位），其正确性必须用**新 TB** 验证——但那是 round3d
   合入前的动作，不是本轮审计的产出；现在跑只会占用与 Lead 构建竞争的 CPU。

## 2. round3d 合入前必须补的仿真（清单，供 Lead/下一轮执行）

工作目录建议：`prj/project_11/sim/r3d_tmp/`（不要写 `out/evidence_.../audit/sim/` 之外的地方）；
跑前必须 `rmdir /s /q xsim.dir`（坑 #48）；xvlog 非零退出必须当硬失败（坑 #32）。

1. 复用既有 TB（回归 fix2 语义不被 round3d 补丁破坏）：
   - `sim/r2_tmp/r2_lite_proto_tb.sv`：单读/单写/背靠背双读 → 1 AR→1 R、1 AW+W→1 B、双读数据各自正确、
     `mbox_fault == 0` 全程。
   - `sim/r2_tmp/r2_lite_write_proto_tb.sv`：背靠背两写 AW/W/B = 2/2/2。
   - `sim/r2_tmp/r2_lite_pipe_wr_tb.sv`：B 未消费前不接受新写。
2. 新增超时 TB（对应 `round3d_candidate.patch` A2–A5）：
   - T1 读超时：发起读后把 `rst_user_n` 拉 0 并保持 → ≤4097 aclk 内 `rvalid=1,rresp=2'b10`，
     `mbox_fault[0]=1`，`+0x50` 读回 bit0=1；释放 `rst_user_n` 后下一笔读 OKAY。
   - T2 写超时：发起写后拉低 `rst_user_n` → `bvalid=1,bresp=2'b10`、`mbox_fault[1]=1`；恢复后下一笔写 OKAY。
   - T3 负向对照：1e5 笔随机正常读写 → `mbox_fault` 恒 0、无 SLVERR（防"超时误触发/判据恒真"）。
   - T4 `LR_DACK` 卡死：强制 `d_req` 不撤 → 41µs 后强制回 IDLE、sticky=1、后续事务正常。
3. 综合侧：改 RTL 后先 `sim/mini_synth_check.tcl` 单模块 OOC 综合（坑 #27），再工程级综合；
   检查 0 条 `MDRV-1`（多驱动，坑 #25；round3d patch 的 `mbox_fault/mbox_clr_tog` 已按单驱动块写，
   但必须工具复核）。

## 3. 本轮已完成的"静态替代证据"

- lite fix2 协议行为：上一轮 4 份 xsim 日志（见上）。
- BD 端口 `dbg_l_bus` 引出：BD regen 日志 + 生成 wrapper 逐行核对（`R3C_probe_review.md` §2.2）。
- mark_debug/net 名风险：本机综合日志实证（`R3C_probe_review.md` §2.5，第 1 次 round3c 构建失败点）。
- 固件/PG021 语义：`out/ip_sim_r2/REPORT.md`（官方 axi_dma IP 仿真 TEST_PASS，S2MM 字节映射/长度/状态）。

*本文件由 rtl-auditor 产出；D 项为有意跳过，非"判据未取得"，也不是"通路正常"的证据。*
