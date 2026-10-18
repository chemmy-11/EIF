# R2 板验场次记录（2026-10-18 16:27–17:0x，初场，未收口）

状态：**板验未通过（R2 端到端未建立）**；已定位并修复 1 个固件阻塞缺陷，另有 1 个新发现的 AXI 总线楔死问题未定位（写在 §5）。

## 1. 硬件与工件（已核实）
- 板上电后 JTAG 可见 `xcku060`；PHY link **Up 1Gbps**（FPGA 配置后 link 才起，正常）；CH340 COM5 @ **9600**（BD `C_BAUDRATE {9600}`，与 `uart_probe.py` 默认一致）。
- 烧写：`jb31b_burn_pair.tcl` 归档 bit `28921C6B` + ELF（先 `1bc8088d`，后板验候选 `1e3a42db`），均 `PAIR_BURNED`。
- 初次 115200 探测无响应是**波特率错**（非板故障），9600 后 `'U'` 正常。

## 2. S0/S1/S3（判据工具结果）
- S0 **PASS**（WNS/WHS/DRC/hash）。
- S1 **PASS**（只读记录完成）。
- S3 **PASS**（`'d'` 后 mode=1 & req.bit24=1；s2sr Halted 清除）。

## 3. 发现的固件阻塞缺陷（已修，[L2]）
- 首场 S2–S5 全 NOT_OBTAINED/FAIL 的根因之一：`serve_write_once()` 里 `dread()` 只读 2 次；在**紧循环交替读不同地址**（0x44/0x40）时 Lite 读滞后 >1 笔 → 固件**从不认为有 pending 请求**（板上用 JTAG 读全局变量证实 `pending_seen=0 / arm_cnt=0`；改 3 读后 `pending_seen=1 / arm_cnt=1 / WRREQ=0x80010056` 正确）。
- 修法：`dread()` 改 3 读（快速路径）；慢速路径 `rd_reg()` 不变（哑写+busy_ms）。板验候选 ELF `1e3a42db`（50,944 B，build 自 `sw/src_j3/main.c`）。

## 4. 修复后的板级观测（[L2]）
- 写引擎可被服务：板上 `'I'` 计数 `wr=6 rd=3`，ILA `dbg_mem_wm=5 / rd_frm=5`（说明 S2MM **commit 与 MM2S 读出都发生**）；`WR_DBG.last_commit_len=0x56=86` 出现。
- 但 **PC 侧收不到任何帧**：`ping 0/4`，NIC `ReceivedBytes` delta=0（连广播帧也没有）。

## 5. 未定位问题：AXI 总线楔死（新，[L1]）
- 现象：高频率调用 `serve_any()`（~143kHz，每圈多次 Lite 读）后，MicroBlaze **挂死在 `dread()` 的 volatile load**（PC 逐指令定位在 `lwi`），UART 完全静默；`rst -processor` 后仍无法恢复（PL 侧事务已楔死），只能重配 FPGA。
- 用"当前 AXI 访问"全局标记定位：挂死时 `g_dbg_addr=0x44A00034`（lite_regs DMA_REQ 读）、`g_dbg_code=0x1111`（dread）。
- **临时缓解**：idle 服务循环加 `busy_ms(1)` 限速（~1kHz）后，多次实验可保持总线存活且计数推进；但**非确定性**（另一次实验仍在 ping 后楔死）⇒ 不是单纯速率问题，疑 lite_regs 读写邮箱在"写命令(SET_WRGO)后紧接读"场景下的握手竞争，待 RTL 级定位（建议 ILA 触发式抓 lite_regs AXI 读/写通道 + 逐周期握手；需重综合加探针）。
- 另有独立待查项：`ping` 无回包但 `rd_frm` 增长 ⇒ 读出侧在动、ETH TX/线上无帧，需 eth 域观测（本 bitstream 已裁 ILA1/ILA2，属裁剪代价）。

## 6. 证据
- 工具日志：`out/evidence_2026-10-18/R2_20261018_16*.log`（首场/次场 S0–S7）、`R2_manual_r2diag1.log`、`R2_manual_rd3test.log`、`R2_manual_fwfix1.log`。
- ILA 快照/差分 CSV：`R2_ila_flood1/2_*`、`R2_ila_fwfix_state_*`、`R2_ila_s4emit_*`。
- JTAG 寄存器/固件全局读数：`r2_jtag_diag*.log`、`r2_mark_diag.log`、`r2_stack_diag.log`。
- 固件构建：`r2_fwdbg*_build.log`、`r2_fwfix_build.log`、`r2_clean2_build.log`。

## 7. 下一步（建议顺序）
1. **RTL/综合侧加触发式 ILA 探针**：lite_regs 的 S_AXI AR/R/B/W 通道若干 + lite_regs 用户域 `r_req/r_ack/d_req/d_ack` + 桥 `wdst/wpending/dma_wr_go`，触发条件 `!s_axi_rvalid && arvalid` 悬挂/`r_ack stuck`；重综合后复现楔死并抓波形。
2. 在楔死前做**最小操作序列**（仅 'U' / 仅 'd' / 'd'+1 ping / 'd'+2 ping）确定触发点。
3. 待 AXI 楔死修复后，再解决 TX 无帧问题（保留 ILA1 eth 域探针或新增 TX 路径探针）。
4. 以上完成后再跑 S0–S11 全序列。
