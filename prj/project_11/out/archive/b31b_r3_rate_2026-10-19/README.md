# b31b_r3_rate_2026-10-19 — 路线 B R3 速率量化 + R4 收口证据

本目录为 **2026-10-19 路线 B 收尾轮**（R3 速率量化 + R4 文档/可观测性收口）的证据归档。
位流/ELF 沿用上一轮验收对：`b31b_r2_2026-10-19_round3d/`（bit `F6012BA0` / ltx `2F8AF498` / xsa `216839F4` / ELF `BA3C0220`）。

## 关键结论

- 1466B 帧：**可持续 2000 fps 零丢失**（≈23.5 Mbps 单向）；**临界 ≈2500 fps**（400µs 档丢 0.085%）；
  **服务能力上限 ≈2560 fps ≈ 390 µs/帧**（多个丢包档反推中位数）。
- 归因 A/B：perf2（去每帧 MM2S 整引擎复位）/ perf3（去写服务 `busy_ms(1)` 固定等待）对上限改善 ≤±0.4%（噪声）
  ⇒ 瓶颈 = **每帧两轮软核-桥-DMA 服务往返本身**（结构性），非单点延时；进一步提速需 SG/批处理（新设计，不在路线 B 范围）。
- 与路线 A 对照：82.67k fps（≈969 Mbps） vs 路线 B ≈2.0–2.5k fps —— 差 33–40×，来自每帧 ~390µs 软核介入。
- D2（坑 #39 三读撤除）= 放弃（收益 <2%、风险不成比例）。

## 实验固件（未采纳）

| 变体 | 改动 | ELF hash8 | 处置 |
|---|---|---|---|
| perf1 | 基线（验收固件：`s2mm_rearm` + 全速服务） | `BA3C0220` | ✅ 采纳（官方对） |
| perf2 | 读服务去掉每帧 MM2S 整引擎复位 | `ED908502` | 实验后回退 |
| perf3 | 写服务去掉 GO 后 `busy_ms(1)` 固定等待，改等 S2MM IOC | `47B9EB18` | 实验后回退 |

复现：对归档 `b31b_r2_2026-10-19_round3d/main_fix1.c` 之后版本（记录 §二十二口径）应用 `r3_patch_perf{2,3}.py` 并 `make`。
板卡最终状态：round3d + perf1 + `'d'`（mode=1）；四档与 10MB+SHA 已复验 PASS。

## 文件

- `R3_RATE_RESULTS.md`：R3 汇总报告（档位表/膝点/A-B/对照/D2）
- `R3_thru_*.json/.log`：各变体测量原始输出（perf1 矩阵/膝点/perf2/perf3）
- `R3_tier_pace*.log`：单档 storm 原始输出（注意：同名档位后跑会覆盖前跑，主结论以 console/json 为准）
- `R3_final_fourtier.log` / `R2_mb10_20261019_172807.log` / `R3_final_burn_official.log`：官方对复验
- `W6_prj11_可观测性清单.md`：R4-2 自动生成清单
- `ARCHIVE_INDEX_prj11.md`：R4-3 跨轮归档索引（32 轮/584 文件/0 缺失）
- `复现_prj11_指南_2026-10-19.md`：R4-1 复现指南（同时入 vault `复现/` 与 docs 镜像）
- `r3_thru.py` / `r3_analyze.py` / `r3_patch_perf2.py` / `r3_patch_perf3.py`：测量/分析与固件实验脚本
- `w6_inventory_prj11.py` / `archive_index_prj11.py` / `backfill_archive_sha.py`：R4 工具
