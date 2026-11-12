# project_13 — prj12 P2 透明 IPv4 转发（v0.2 契约）起点

## 这是什么

- **来源**：2026-11-08 从 `prj12`（`D:\FPGA\prj\project_12`）fork 的**源码骨架**（不含任何构建产物）。
- **目的**：承接交付仓 issue #10 的 **P2 契约 v0.2——IPv4 packet 透明转发**：
  - 只换 14 B 以太网头（dst=PEER_MAC, src=BOARD_MAC, `0x0800`），**IP 包逐字节不变**（源/目的 IP、端口、TTL、IP/UDP checksum、DSCP、options、分片字段全保留）；
  - 只转发 `dst=PEER_IP` 的 IPv4；`BOARD_IP` 走本地栈；其它 dst / VLAN / IPv6 / 广播 / 组播 / 超长 / 坏 IP header checksum / 截断帧 → **DROP + 各自计数**；
  - ARP 只在本地终结、**不跨板**；静态 ARP 为主；
  - 关闭旧的回显路径（`des_mac=src_mac`），防 A↔B 乒乓环。
- **包含 B1 修复**：本 fork 的 `rtl/frame_mem_if.v` + `rtl/aurora_mem_bridge.v` 已含 **B1 复位配对补丁**（`ui_link_rst_n = ui_rst_n & ~aurora_rst_ui`，接到 `u_mem`/`u_mem2` 的 FIFO ui 侧复位）。该补丁 **xsim 已 PASS、位流已构建（`E9BE2B14`）、尚未上板验证**——详见 `prj/project_12/out/evidence_2026-11-07_dma_stall/BUILD_B1_2026-11-07.md`。

## 与 prj12 的差异（截至 fork 时点）

- **源码零差异**（rtl/xdc/sim/sw/docs/pc 全量复制；脚本里的 `project_12` 路径已改为 `project_13`，`create_project` 工程名改为 `prj13`）；
- 未复制：`vivado/`（383 MB 工程目录，按需重建）、`scripts/*.dcp/*.ltx/*.bit`、`out/`（证据与产物）；
- `p2_candidate/` 只保留历史 `result.txt`（旧 v0.1 候选的 TB 产物已清，源码树里本就没有对应 RTL）。

## 构建流程（与本机 PC1 一致）

```powershell
cd D:\FPGA\prj\project_13
# 1) 建工程（IP 从 prj9/prj10 只读 import：aurora×3、async_fifo、ddr4_0）
$env:TEMP='D:\FPGA\.tmp'; $env:TMP='D:\FPGA\.tmp'
vivado -mode batch -source scripts\create_project.tcl -notrace
# 2) 综合（约 5 min）
vivado -mode batch -source scripts\build_synth_only.tcl -notrace
# 3) 实现 + 位流（约 30–40 min；自带 WNS>=0 && WHS>=0 守门，否则不写位流）
vivado -mode batch -source scripts\build_impl.tcl -notrace
```

产物：`out/aurora_mem_bridge.bit` + `scripts/probes.ltx`（**成对**）+ `out/rpt_impl_timing_summary.rpt`。
> 注意：产物文件名沿用 `aurora_mem_bridge`（顶层实体名不变）。**prj13 的位流与 prj12 不通用**，烧录时必须与同次构建的 `probes.ltx` 配对；建议出片后立刻改名为 `aurora_mem_bridge_p2_<指纹>.bit` 并在交付仓 `fpga/bitstreams/INDEX.md` 登记。

## 验收判据（P2，交付仓 #10）

1. TB 断言：relay 输出的 IPv4 包与输入**逐字节相同**（除新加的 14 B 头）；
2. DROP 计数器各自递增：VLAN / IPv6 / 非 IP EtherType / 广播 / 组播 / 未知 dst / 超长 / 坏 IP header checksum / 帧截断；
3. ARP 不跨板；无 A↔B 乒乓环；本地回显与转发不共存；
4. 计数器清单落地（`rx_frames`…`aurora_channel_up`/`hard_err`/`soft_err`）；
5. 上板：PC1→A→B→PC2 单向 `ping`/UDP 与反向，IP 包内容不变，丢包 0（**板 B 稳定性 / B1 验证通过后**）。

## 状态

- [x] 骨架 fork（源码 + 脚本路径改写 + README + fork manifest）
- [x] P2 RTL：`rtl/p2/{ipv4_packet_extract,eth_rewrap,local_steer}.v`（v0.2）+ 单板环路 TB（`sim/p2/`，**xsim 21/21 PASS**，含 4 组变异测试；2026-11-08）
- [x] P0/P1 离线工程化（2026-11-08）：地址/ARP 方案、`p1_selfcheck.ps1` + `p1_judge.py`（mock 25/25）、PC 侧发帧基准、B1 回归 `sim/regress.ps1`（12/12）、`stall_watchdog.ps1`、QSPI 方案、吞吐批量方案
- [x] P2 顶层集成（2026-11-08）：`rtl/p2/p2_frame_buf.v` + `rtl/p2/p2_relay_top.v`；泵A 写侧 ← 转发流；桥② 写侧 ← 已重加 14 B 头的完整帧；**本地栈应答改走本板 GE2**（P1 跨板回声结构上消失）
- [x] 首次构建 P2 候选位流 **`CFA98553`**（11,459,804 B，WNS **+0.015** / WHS **+0.004**、0 失败端点；位流/ltx 成对；登记 `docs/M1_prj13_P2候选位流登记_2026-11-08.md`）
- [ ] 板 B 版位流（同源码换参数：`BOARD_IP=.12 / BOARD_MAC=0B:01 / PEER_IP=.1 / PC_IP=.2`）
- [ ] P2 计数器挂 ILA（本候选为保时序余量未加，V4 前必做）
- [ ] 上板验收（需板）

### 2026-11-08 离线产出索引（证据在磁盘、不入库；见 `.gitignore`）

| 主题 | 文档 | 一键入口 |
|---|---|---|
| **上板操作单（11-12 下午场）** | `docs/M1_prj13_P2上板操作单_2026-11-12.md`（板 A + 单 PC 两档 + v1.1 能力项采集） | 照单执行 |
| **上板验证（判据全表）** | `docs/M1_prj13_P2上板验证执行单_2026-11-10.md`（单板两档 + 双板 V3/V4 + 六点差分链 + 分诊） | `out/twin_config_13.json` → `prj12/out/twin_burn.ps1 -Root . -Config out/twin_config_13.json` |
| P2 环境勘误与档 2 前置 | `docs/M1_prj13_P2上板环境勘误与档2前置_2026-11-10.md`（junction / 安装盘瞬时读 / COM5 / 免管理员注入） | — |
| 导师 v1.1 指南影响分析 | `docs/M1_prj13_导师v1.1指南影响分析_2026-11-11.md`（7 条影响 + 能力边界 + 验收映射） | — |
| P2 RTL 接口契约 | `docs/M1_prj13_P2_RTL接口契约_v0.2_2026-11-08.md` | `sim/p2/run_p2_sim.ps1` |
| P2 候选位流登记 | `docs/M1_prj13_P2候选位流登记_2026-11-08.md`（§0 活跃候选：两片等价） | `out/b_p2_CFA98553/` |
| P2 位流重建登记 | `docs/M1_prj13_P2位流重建登记_2026-11-12.md`（`F16FCE70`，组员机重建，档 2 BLOCKED） | `out/b_p2_F16FCE70/` |
| 地址与 ARP | `docs/M1_P2地址与ARP方案_v0.2_2026-11-08.md` | `pc/static_arp.ps1 -DryRun` |
| M1 判据 | `docs/M1_多尺寸与10MiB判据_2026-11-08.md` | `scripts/p1_selfcheck.ps1 -DryRun` |
| PC 发帧基准 | `docs/M1_PC侧发帧能力基准_2026-11-08.md` | `pc/twin_send.py --bench` |
| B1 回归 | `docs/P1_B1回归套件_2026-11-08.md` | `sim/regress.ps1 -Scenario all` |
| QSPI 固化 | `docs/P1_QSPI固化方案_2026-11-08.md` | `scripts/qspi_program.ps1 -DryRun` |
| 吞吐批量 | `docs/M1_吞吐批量路径方案_2026-11-08.md` | —（本轮不实现） |

## 纪律

- **prj12 只收 P1/B1 修复**；P2 新功能一律进 prj13；共性 bug 修复用同一 patch 文件两边 apply；
- 不把 B1 当"已验证"对外引用，直到 `VERIFY_ON_BOARD.md` 的核心判据通过；
- 位流/ltx 必须成对，版本哈希登记到交付仓 `fpga/bitstreams/INDEX.md`；
- **出片后立刻建 `prj13/out/twin_config.json`**（否则 `p1_selfcheck` 会回落到 prj12 的 P1 基线对，M1 复现正确但会误以为烧了 prj13 新位流）。
