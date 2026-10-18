# R2 round2c 构建与产物（b31b_r2_2026-10-18 归档）

状态：**位流已出，时序门限通过** —— `ExtraTimingOpt` 后布 WNS +0.042 → phys_opt 后 **WNS +0.004 / WHS +0.004**，DRC **0 Errors / 22 Warnings**，`V5_SWEEP2_OK`。板验进行中（用户上电后 S0–S11）。

## 1. 修复链（每步均经独立 TB 绿灯后才进构建）

| 步 | 改动 | 结果 |
|---|---|---|
| 2.0 | 失败轮诊断（10-17 夜）：30/30 最差路径 = `u_wr_bytes/wr_gray_s2`→gray2bin→level==0/比较→`g_wr_dma.wd_data_r[*]/CE` | 25/30 族 + 5/30 桥② 旧 FSM 同族 |
| 2.1 | **字节捕获 1 级流水**（`byte_q`/`byte_valid_q`，`wd_fetch` 与消费同拍流水；吞吐 1B/cycle） | 首版 `740ab153` 被审计 TB 抓 A16：满拍保持拍重复 fetch 覆盖跨拍预取 ⇒ 每非末拍丢 1 字节；修法 `&& !wd_beat_full` → `06e6bd72`；TB PASS+2 负向 FAIL |
| 2.2 | **`WD_ARM` 拆拍**：WAITGO 完成条件（`wf_level>=wd_len`，12b/3×CARRY8）不再同拍清 512 位数据/keep 寄存器；新增 `WD_ARM=3'd7` 用状态译码清零（HALT 保持=6；每帧 +1 拍） | `f43267db`；TB PASS+2 负向 FAIL（审计 §13） |
| 2.3 | **ILA 裁剪**：ILA1/ILA2 整核移除；ILA0 probe0 374→92、probe1 9；ILA3 184→152（裁 bresp/wslot/rslot） | 综合 0 err/0 CW（1 条 aurora 既有 CW）；审计 §12 复核 |

## 2. 构建轮次（`build_v5_sweep2.tcl`；ui_clk 300MHz；门限 WNS≥0 & WHS≥0）

| 轮 | RTL / ILA | 指令 | 后布 WNS | 尾判 WNS / WHS | 结论 |
|---|---|---|---|---|---|
| 2a | 06e6bd72 / 未裁 | ExtraTimingOpt | −0.147 | −0.135 / +0.004 | 门限拒 |
| 2b | 06e6bd72 / 裁剪 | ExtraTimingOpt | −0.156 | −0.127 / +0.003 | 门限拒 |
| **2c** | **f43267db / 裁剪** | **ExtraTimingOpt** | **+0.042** | **+0.004 / +0.004** | **✅ 过门限、写位流** |

`rpt2_ExtraTimingOpt.timing_summary.rpt`：All user specified timing constraints are met. `write_bitstream completed successfully`。

## 3. 产物（`SHA256.txt` 为权威清单）

- bit `aurora_mem_bridge_r2_28921C6B.bit`（= `aurora_mem_bridge_r2.bit`），10,266,180 B，SHA256 `28921C6B38BE92447950B8C81405F278945529BB007E94461EC2CEEF0D324627`
- ltx `probes_r2_28921C6B.ltx`（= `probes_r2.ltx`），64,593 B，SHA256 `4AC2554667F94BC3E052E0A652FF2DE322E2CE51FEE2B47399A108DF9E6B7C33`；审计 ltx 实物核对：仅 `u_ila_0/u_ila_3` 两核、宽度 92/9/152、末 5bit=`state[2:0]/tvalid/tready`、裁剪项缺席
- xsa `mb_ctrl_r2.xsa`，2,606,995 B，SHA256 `16A4F01F51AF9665B4C79686812FEAA353C3CF8C27C8BC3C47DA1EC7D28EC59E`
- ELF `j3_soft_r2_1bc8088d.elf`，50,896 B，SHA256 `1BC8088DC48D42BBF40AEC76FDFB69B96CE9B187CFAF6DBD022E285B921BD42A`
- RTL 快照 blob：`f43267db82b84305cfeb519adcfa76f79443f6b3`（bridge，round2c）/ `96d5b136` / `1885225f` / `421df59c`

## 4. 复现命令

```powershell
# 综合 + ILA（含瞬态自动重试, 坑 #61）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\r2_synth_retry.ps1
# place/route 扫描（失败也落 dcp+报告; stdout 必须文件重定向, 坑 #58）
cmd /c ""D:\Xilinx\Vivado\2023.1\bin\vivado.bat" -mode batch -source D:\FPGA\prj\project_11\scripts\build_v5_sweep2.tcl -notrace > D:\FPGA\prj\project_11\out\r2_sweep2_console.log 2>&1"
# 烧写（板验）
xsct D:\FPGA\prj\project_11\out\jb31b_burn_pair.tcl <归档bit绝对路径> <归档ELF绝对路径>
```

## 5. 板验注意

`dbg_s2mm_state` **7=ARM 正常瞬态（忽略）、6=HALT 才 fail-stop**；`dbg_wr_fault` 全程应 0；S10 的 `bresp/wslot/rslot`=INFO/判据未取得（本轮裁掉）；ILA1/2 已移除 ⇒ 无 eth/B 域交叉观测。
