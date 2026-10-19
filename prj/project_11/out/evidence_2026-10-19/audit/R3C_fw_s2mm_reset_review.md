# R2 S2MM 周期性 Halted / 50% 丢帧：固件级根因修复独立复核

- 产出：rtl-auditor（只读复核，未改 rtl/scripts/sw；未碰板） 日期：2026-10-19
- 被复核修复：`s2mm_rearm()`（固件级，无 RTL/位流改动），验收位流 `9852016C` / 固件 `BA3C0220(perf1)` / 位流作者记录 `out/evidence_2026-10-19/R3C_board_session_20261019.md`
- 等级：L4 定案 / L3 板证 / L2 对照+代码或同版本实物 / L1 相容假说（AGENTS §6a）

## Q1 官方口径：任一通道 Reset 是否复位整个 AXI DMA？

**准确，未检索到例外（async / SG / direct-register 模式均无版本或模式豁免）[L2 官方文档]。**

- PG021 `S2MM_DMACR` bit2 原文：
  > "Soft reset for resetting the AXI DMA core. … **Setting either MM2S_DMACR.Reset = 1 or S2MM_DMACR. Reset = 1 resets the entire AXI DMA engine.** After completion of a soft reset, all registers and bits are in the Reset State."
  URL: https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_DMACR-S2MM-DMA-Control-Register-Offset-30h
  返回块核对：`family` 含 Kintex UltraScale+（本器件 `xcku060-ffva1156-2-i` 属该族）；`version: All`；本工程落点 **Vivado 2023.1 / axi_dma 7.1 / 直通（direct register，C_INCLUDE_SG=0）/ ASYNC 时钟模式**（BD regen 日志原文："Clocks connected to AXI DMA are not same. Configuring AXI DMA in ASYNC mode"）。
- `MM2S_DMACR` bit2 同句（双通道对称说明）：https://docs.amd.com/r/en-US/pg021_axi_dma/MM2S_DMACR-MM2S-DMA-Control-Register-Offset-00h
- 旧版数据手册同句（排除"新版本才这样"）：DS781/DS852（axi_dma v4.00a）"S2MM_DMACR Reset = 1 resets the entire AXI DMA engine"：https://docs.amd.com/v/u/en-US/axi_dma_ds781
- 例外核查：
  - **ASYNC 模式**只是时钟方案（双时钟 CDC），文档未给 reset 作用域的豁免；异步只增加复位传播延迟 ⇒ 软件必须 poll `DMASR.Halted` 而不是假设立即完成（修复代码正是 poll，正确）。
  - **Scatter/Gather 模式**：reset 仍复位整个引擎，仅"flush 描述符队列"语义；本工程非 SG 模式，无此差异。
  - **Direct Register 模式**的联动后果有官方另一条直证：`S2MM_DMASR` 页原文 "For Direct Register Mode, **writing to the LENGTH register has no effect on DMA operations**"（Halted=1 时）。URL: https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_DMASR-S2MM-DMA-Status-Register-Offset-34h
  ⇒ "MM2S 复位 → S2MM Halted → 下一帧 LENGTH 写无效 → 不启动传输" 链条 [L2 官方]。
- 唯一补充：reset 是 **graceful**（"pending commands/transfers are flushed or completed; AXI4-Stream outs terminated early, if necessary with associated TLAST"），不是瞬时清零，故代码用 Halted 轮询而非固定延迟是对的。

## Q2 `s2mm_rearm()` 时序与残余风险

代码（`sw/j3_soft/src/main.c:343-351`）：写 `S2MM_DMACR=IOC_IrqEn|RS` → poll `Halted==0` → `S2MM_DMASR=IOC(W1C)`；调用点：`serve_dma_once()` 末尾（读服务后，:303）与 `serve_write_once()` 每次编程前（:394，且在 SA/LENGTH 写之前）。[L2 代码]

**判定：时序顺序正确，不改变桥 commit 语义；残余窗口小，均为"丢帧/走 fault 恢复"而非"提交错数据"。**

- 正确性 1：RS 写后 poll Halted==0 符合 PG021（"halted bit deasserts to 0 when the DMA engine begins operations"）；先 rearm 再写 `S2MM_LENGTH` 正是"Halted=1 时 LENGTH 无效"的必要序。
- 正确性 2：**不碰 `g_wr_last_toggle`** 是对的——rearm 不是"新请求 arm"，若改 toggle 会让 `serve_write_once` 的 `tog==g_wr_last_toggle` 判定失步（重复/漏 arm）。[L2 代码]
- 桥 commit 语义：桥 `WD_WAITDONE` 以 `s2mm_introut` **电平**（ui 域 2FF）为提交条件；`s2mm_rearm` 的 W1C 会拉低 introut。理论上存在"完成→桥采样前被清"的偷取窗口，但：
  - W1：读服务 MM2S 复位可能打断**在飞的 S2MM 写传输**。固件单线程序列 = `LENGTH→GO→busy_ms(1)→返回`；`busy_ms(1)` 实测 ≈0.15ms（坑 #51），而 86B–1538B 帧的 S2MM 写仅 ~µs 级 ⇒ 读服务最早在 150µs 后才到，余量 ~30–50×。若极端情况下发生：PG021 的 reset 是 graceful、stream 提前 TLAST 终止；桥收不到 introut ⇒ WAITDONE 56ms 超时 ⇒ WD_HALT→fault 恢复；该槽**不会被 commit/置满**（桥只在 introut 时 commit）⇒ **数据完整性不受损，最坏是该帧丢弃 + 一次恢复**。[L1 低]
  - W2：`s2mm_rearm()` 的 W1C 与桥采样竞争的窗口 ≈ 数个 ui 周期（<50ns），而固件动作最早在 GO 后 150µs ⇒ 实际概率极低；本轮 7022 帧 10MB 实测 0 丢/0 错亦未观测。**建议（可选加固）**：`s2mm_rearm()` 里的 W1C 在两处调用点其实是冗余的（读服务前的 MM2S 全引擎 reset 已把 IOC 清 0；写服务前 caller 已先写 `S2MM_DMASR=IOC`）——**删掉该 W1C 可完全消除该理论窗口**，且无功能影响。[L0 建议→需回归]
  - W3：写 `S2MM_DMACR` RS=1 时若通道已在跑（RS=1→1）为 no-op，不破坏在飞传输（PG021）。新一轮请求只有在上一帧 commit 后才会出现（桥 FSM 语义），故 rearm 与在飞写传输重叠只可能来自 W1。
- 另一处未改：fault 恢复 `s2mm_channel_init()` 仍走"全引擎 reset + 重新 RS + 清 IOC + `g_wr_last_toggle=0xFFFFFFFF` + 翻 ACK"，属异常出口，合理。
- 建议保留 `busy_ms(1)`（不要为提速删到 0），直到 round3d 给 lite/桥加超时兜底；若将来去 `busy_ms(1)`，W1 余量归零，需同时改"仅在 S2MM 无 pending 时 reset MM2S"或改用 RS=1 不带 reset 的读路径。

## Q3 为什么旧位流是"读回冻结+UART 静默"而不是 50% 丢帧？BD 全量 regen 修复了什么？

**结论 [L2 强推断，机制板级直证待 ILA4]：round2f/round3/round3b 的位流里 `axi_lite_regs` 一直是 10-17 的旧网表（IP cache 陈旧），fix1/fix2 从未进过任何位流；BD 全量 regen 只是"迫使 module-ref 重新综合"的开关，不是 BD 逻辑变了。**

证据链（全部只读归档/工程产物）：

1. **旧 IP cache 条目 `1f8570ac5fbdb536`**（`vivado/prj11.cache/ip/2023.1/1/f/1f8570ac5fbdb536/`）所有文件 mtime = **2026-10-17 22:22:03**（BD 首建时间；`mb_ctrl_axi_lite_regs_0_0_8` 目录 10-17 22:15）；`stats.txt`: `NumberHits:19`、`Timestamp: Sun Oct 18 16:10:59 UTC 2026` = **本地 10-19 00:10:59**，恰为 round3b 构建时刻
   ⇒ round3b（以及 round2f/round3，日志同路径）复用 10-17 的 DCP。
2. **旧构建日志逐代读同一陈旧 DCP**：`build_r2_synth.log` 里 `Reading design checkpoint '.../mb_ctrl_axi_lite_regs_0_0_9/mb_ctrl_axi_lite_regs_0_0.dcp'`：round2f L1673 / round3 L1237 / round3b L1232（同一 `_9` 目录）。
   而 `axi_lite_regs.v` 在 10-18 有两次功能修改（fix1 `c8c8a0b` 10-18 17:09；fix2 `c541f16` 10-18 21:14）——**均在 cache 生成之后，但 cache 未失效**。
3. **BD regen 后变新实例**：`mb_ctrl_axi_lite_regs_0_0_10`（旧 `_9`）；新 build 日志（`out/r3c3_synth.log:1616`、`out/r3c2_synth.log:1615`）读 `..._10/...dcp`。新 IP cache 条目 **`f74c8b84ebe500a4`** 创建于 **2026-10-19 12:05:50**（`stats.txt` 最后命中 15:53:46=r3d 综合），DCP 107719 B / sim_netlist 147774 B，vs 旧 93605 B / 123327 B。
4. **为什么旧 key 不随 RTL 变**：新旧 cache 的 `.xci` 仅 `IPCACHEID`/`IPCACHESYNTHCRC` 等运行时字段不同（3fdf9d25 → 08aea834）；`stub.v` 差异仅是新接口多 `dbg_o[35:0]`（旧 stub 日期 10-17，新 10-19）。⇒ module-ref IP 的 cache key 跟 **接口/生成输入**走，**不追踪内部 RTL 编辑**；`reset_run`/`MODULE_REF_RESET` 只重置 run，不清 IP cache，故"每轮都 reset 了 run 却仍用旧网表"（坑 #35 在 IP-cache 层的变体）。
5. **功能等价对照**：`BUILD_STATUS.md:4` 明确 round3c 位流"**功能 RTL 与 round3b 等价，仅新增纯观测 dbg_o/BD 端口/GO 链 mark_debug**"。若旧网表=新网表，行为不应改变；实际楔死消失 ⇒ 唯一实质变量就是"lite 网表新旧"。
6. **旧网表的已知缺陷**：10-18 独立审计单元仿真实测（`out/evidence_2026-10-18/R2_sim_lite_proto_frozen_{r,w}.log`）：旧版单读 `1 AR→5 R`、单写 `1 AW+W→5 B`（AXI4-Lite 协议违例，互连读写跟踪失步 ⇒ 读滞后/楔死，坑 #39/#36 家族）。即旧 cache 网表 = **含该缺陷的版本**。

⇒ 现象差异解释：**旧网表**上，Lite 总线协议违例在"GO 写 + S2MM 开始搬数"这类流量形态下会让互连读/写跟踪失步 → 表现为**读回冻结（同值 0x80010056）/UART 静默/CPU 自旋**（整条服务面死亡）；**真正 fix2 进网表后**总线协议正确，楔死消失，才暴露出唯一的确定性逻辑 bug——MM2S reset 连带 S2MM Halted → **严格隔帧丢（50%）**。两者不是同一故障的两种表现，而是"先修好总线（regen 副作用）→ 后暴露逻辑 bug（固件修复）"的串联。
- 等级：陈旧网表链条 **[L2]**（时间戳/命中数/日志路径/接口 CRC 全链闭合）；"陈旧网表 ⇒ 冻结现象"映射 **[L1]**（缺 round3b 时刻的 lite 总线直证；建议 round3d 若补 ILA4/或离线重放旧网表 TB 可升 L3）。
- **新坑建议（AGENTS §九候选 #68）**：BD module reference 的 OOC/IP-cache **不随 RTL 源文件内容失效**；`reset_run` 不够。判别法：build 日志里 `Reading design checkpoint .../mb_ctrl_*_<N>/...dcp` 的 `<N>` 目录 mtime 应晚于 RTL mtime；或查 `prj11.cache/ip/.../stats.txt` 的 Timestamp/NumberHits；修法 = 改 module-ref RTL 后 **BD regen（或删除对应 cache 条目 / `config_ip_cache -disable_cache`）** 再综合。

## 复核结论（一句话）

Q1 官方口径准确且无模式/版本豁免 [L2]；Q2 修复顺序正确、不改变桥 commit 语义，残余仅"极端时序下丢一帧+恢复/理论 IOC 偷取窗口"，建议删冗余 W1C 并保留 `busy_ms(1)` [L1 低]；Q3 旧位流的"冻结/静默"是 **lite_regs 旧 IP-cache 网表（fix 未生效）** 导致，BD regen 通过换 module-ref 实例/接口迫使真综合，从而让 fix2 首次进流 [L2 强推断]。

*本文件为只读复核；未修改任何设计/脚本/固件。*
