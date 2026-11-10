# 板 B 稳定性验证报告（空载 60 min + 负载 60 min）

- 日期：2026-11-10
- 执行：PC1 本机（以太网 `08-3C-03-A0-26-96`，ifIndex 7，`192.168.1.102/24`）
- 被测：**板 B**（JTAG 线缆 `210512180081`，CH340 **COM7**，DNA `0x0000000040020001011829680590e285`）
- 工程/位流：**prj11 单板回环** `aurora_mem_bridge` `F6012BA0`
  - bit `D:\FPGA\prj\project_12\out\baseline_F6012BA0.bit` 9,288,496 B
    SHA256 `f6012ba0ff8f9d7f3bcd9ac848a97f1c5e1b6dd7016dad5bebe93755e73c54c4`
  - elf `D:\FPGA\prj\project_12\out\j3_soft_r2_BA3C0220.elf` 61,296 B
    SHA256 `ba3c02209720b59d9f0fbc4083c2ab80b16efc9a148448b9dcfbcda001bb3559`
  - ltx `...\b31b_r2_2026-10-19_round3d\probes_r2_F6012BA0.ltx` 82,040 B
    SHA256 `2f8af49895396ebd33d08389ede1bc2158dba83d2398b1b8a4ae350b34baf686`
- 网口：**丝印 GE1**（= 板卡手册表 43.5.1 的 GE1 = 官方 `KU_IO.xdc` 的 `#GE2` 段；本板无 GE2 丝印）

## 1. 结论（限定范围内的）

**在"当前位置 / 当前供电链 / 当前负载强度"下，板 B 连续 3 h 05 min 未发生配置丢失（复位），其中
空载 60 min 与负载 60 min 均有 30 s 粒度全采样，零复位、零掉链、零 USB 掉线、零持续丢帧。**

不得据此宣称"板 B 稳定"：**未做热对照**（用户 2026-11-10 决定不做，理由：板卡当前不在笔记本出风口，
位置非变量），且**负载强度仅约 1.17 Mbps**（见 §5 局限），不构成 GE1 带宽压力测试。

## 2. 两相判据数据

### 2.1 空载相（15:17:14 → 16:17:41）

| 观测 | 样本 | 结果 |
|---|---|---|
| ILA 存活（主判据） | 119 | `ILAS=3 DONE=1` × 119 / `ILAS=0` 0 / `RESET_DETECTED` 0 / `POLL_ERR` 0 |
| PC 侧巡逻 | 113 | 掉链 0 / ping 失败 0 / CH340 掉 0 / JTAG 掉 0 |
| 结束标记 | — | `MONITOR_DONE elapsed=3627 resets=0 errors=0`；`PC_MON_DONE elapsed=3528 linkdown=0 pingfail=0 usbgone=0` |

### 2.2 负载相（17:17:49 → 18:18:25）

| 观测 | 样本 | 结果 |
|---|---|---|
| ILA 存活 | 119 | `ILAS=3 DONE=1` × 119 / `ILAS=0` 0 / `RESET_DETECTED` 0 / `POLL_ERR` 0 |
| PC 侧巡逻 | 115 | 掉链 0 / ping 失败 0 / CH340 掉 0 / JTAG 掉 0 |
| 负载 | 119 个采样行 + 1 行 `LOAD_DONE` | `LOAD_DONE elapsed=3600.0 SENT=3,599,897 ECHO=3,599,893 ECHO_RATIO=100.00% SENT_RATE=1000.0` |
| 结束标记 | — | `MONITOR_DONE elapsed=3630 resets=0 errors=0` |

采样完整性：两相均为 30 s 粒度（实测间隔 min 30 s / max 31 s / avg 30.4 s），各覆盖 3600 s。

## 3. 复位账（从烧录到收尾，3 h 05 min 41 s）

| 区段 | 时长 | 观测方式 | 结论 |
|---|---|---|---|
| 15:12:44 烧录完成 → 15:17:14 | 4.5 min | 无 | 由 15:17 首个采样 `ILAS=3` 覆盖 |
| 15:17:14 → 16:17:41 空载相 | 60 min | 30 s 全采样 | 零复位 |
| 16:17:41 → 17:17:22 空窗 | 59.7 min | 端点检查 | `CHECK_DONE 1 / CHECK_ILAS 3 / CHECK_DNA` 同前 ⇒ 未复位 |
| 17:17:55 → 18:18:25 负载相 | 60 min | 30 s 全采样 | 零复位 |

**为什么 30 s 粒度足以判定复位**：复位是**锁存态**——板子掉配置后回落出厂 QSPI 镜像，
该镜像 `ILA=0` 且**不驱动 PHY**（2026-11-10 15:04 实测：`DONE=1`、`ILA=0`、网口 `Disconnected`）。
配置不会自己恢复，因此任何一次采样都必然看到，不存在"两次采样之间复位又恢复"。

## 4. 关键现场结论（本次新得，与既有文档冲突处已标注）

1. **丝印只有 GE0/GE1，没有 GE2**。三个名字指同一组球号：
   丝印 GE1 = 手册表 43.5.1 的 GE1 = 官方 `KU_IO.xdc` 的 `#GE2` 段
   （AC31/Y33/W33/W34/V33/AC32/Y32/AE32/Y31/AF32/AF30/AG30 + `eth_rst_n` AA33）。
   丝印 GE0 = `KU_IO.xdc` 的 `#GE1` 段（AD30…），本项目从未使用。
2. **出厂 QSPI 镜像不驱动本板 PHY** ⇒ 与 `汇报_双板互联进展与板B稳定性问题_2026-11-09.md:67`
   所述"出厂设计也驱动 GE2，网口 Up 是假象"**不成立**。本板上复位 ⇒ 网口必掉线，
   这是一条比文档 L2 假象更可靠的复位交叉观测。
3. **`ping` 不通不等于网口问题**：`main.c:611-616` 的 serve 循环只在 `g_dma_mode` 下跑，
   出向帧（含栈自发 ARP/ICMP/命令应答）的读回依赖它。实测：发 `d` 前 ping 3/3 丢、发 `d` 后
   ping 3/3 通，唯一变量是 `d`（固件回显 `[B2] DMAMODE now=DMA`）。
4. **prj11 的 `.ltx` 没有 `channel_up` / `hard_err` 探针**（3 核 36 probe 全是 `dbg_mem_*` /
   `dbg_s2mm_*`），故 09 日汇报 §3.5 里那两条判据在 prj11 上取不到数，本报告改用
   "ILA 核数 + DONE 位 + 链路 + USB" 组合判据替代。

## 5. 局限（不得越过）

- **未做热对照**（用户决定）。本结论只在"当前不在出风口"的位置条件下成立。
- **负载强度低**：1000 fps × 100 B payload，线上每帧约 146 B ⇒ **≈1.17 Mbps**，
  相对 GE1（≈950 Mbps）仅约 0.12%。本相验证的是"持续帧流/帧率维度"，
  **不是带宽压力**；不能据此称"满线速稳定"。
- 空载/负载相之间与前后各有约 1 h 与 5 min 无采样区段，只能由端点检查证明未复位。
- 本测试与 M1 剩余 5 项判据（多尺寸、10 MiB 连续、双向 5 轮、重启复测、错误可报告口径）无关。

## 6. 与 2026-11-06 记录对比

| 项 | 11-06（PC2 侧） | 11-10（本次） |
|---|---|---|
| 复位次数 | 单日 10 次 | **0 次** |
| 复位间隔 | 2–38 min，无周期 | — |
| 最长稳定 | 38 min | **185 min**（含两相全采样 120 min） |
| 位流/固件 | 同一套软核/DMA 路径 | `F6012BA0` + `BA3C0220` |

差异变量（位置、供电链、接线、负载）**未逐项复现**，因此不能把"0 次"归因为"板子自身变好"，
也不能排除 11-06 是环境/接触类问题。

## 7. 证据清单

全部位于 `D:\FPGA\prj\project_11\out\evidence_2026-11-10_boardB_stability\`，
校验见 `SHA256SUMS.txt`。关键文件：

| 文件 | 内容 |
|---|---|
| `burn_B_bitelf_20261110.console.log` | `BURN_OK`，exit=0，15.2 s，cable 210512180081 |
| `serial_d_probe_20261110.log` | `[B2] DMAMODE now=DMA` |
| `udp_loopback_3x100_20261110.log` | `sent=3 echo=3`（光纤环回闭环验证） |
| `ila_poll_3600s.log` / `pc_side_3600s.log` | 空载相 119 / 113 样本 |
| `ila_poll_load_3600s.log` / `pc_side_load_3600s.log` / `load_soak_3600s.log` | 负载相 119 / 115 / 120 行 |
| `ila_check_before_load.log` | 空窗端点检查（DONE/DNA/ILAS） |
| `ila_poll_monitor.tcl` / `ila_poll_load.tcl` / `ila_check_once.tcl` | ILA 轮询与一次性检查脚本（Tcl 8.5.14 语法检查 PASS） |
| `pc_side_monitor.ps1` / `serial_probe.py` / `load_soak.py` | PC 侧巡逻 / 串口探针 / 持续负载 |
