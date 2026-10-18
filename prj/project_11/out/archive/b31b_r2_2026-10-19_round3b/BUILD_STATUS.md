# R2 round3b 构建状态（b31b_r2_2026-10-19_round3b 归档）

状态：**构建成功（PASS）** —— `V5_SWEEP2_OK`，`SWEEP2_ExtraTimingOpt: WNS=+0.004 / WHS=+0.004`（首掷即过，无需重掷）。**板卡按用户要求已断电，本轮未做板验**。

## 1. 产物（关键 hash）

| 产物 | 文件（本目录） | SHA256 前 8 / 大小 |
|---|---|---|
| 位流 | `aurora_mem_bridge_r2_02F7153A.bit` | **`02F7153A`** / 9,996,016 B |
| 探针 | `probes_r2_02F7153A.ltx` | **`0B2CC2F5`** / 84,582 B（**3 核**：ILA0/ILA3/ILA5） |
| XSA | `mb_ctrl_r2.xsa` | `95E1D156` / 2,623,406 B |
| 诊断固件 ELF | `j3_soft_r2_16D06BD3.elf`（f8cf4022 基线 + `'W'` DMA 状态 + LMB 快照 + GO 后 1ms + 10ms 慢轮询） | **`16D06BD3`** / 53,800 B |

## 2. round3b 改动集（相对 round2f）

- **`rtl/axi_lite_regs.v` = lite fix2 `d5d16d46`**（AW/W ready 单拍 + bvalid 未消费不接新写 + 写事务关闭前不接受 AR；仿真：背靠背 2 写 2/2/2 PASS）
- `rtl/aurora_mem_bridge.v` = `6150212e`（仅新增 6 行 mark_debug alias：`dbg_pfwd_data[7:0]`/`dbg_pfwd_en`/`dbg_s2mm_tdata64`/`dbg_s2mm_tkeep8`/`dbg_s2mm_tlast_w`，无逻辑改动）
- bridge `c92c20c7` / fmi `96d5b136` 不变
- **探针**：ILA0 probe0 **101b**（92b 旧位序 + `dbg_pfwd_data[7:0]` + `dbg_pfwd_en`）、probe1 9b；ILA3 probe0 152b（**深度 2048→1024**）；**新增 `u_ila_5@ui_clk`** 5 probe=64/8/1/1/1（`dbg_s2mm_tdata64`/`dbg_s2mm_tkeep8`/`dbg_s2mm_tvalid`/`dbg_s2mm_tready`/`dbg_s2mm_tlast_w`，深度 1024）
- **注意**：Vivado 2023.1 `C_DATA_DEPTH` 合法值最小 1024 ⇒ ILA5 不能降到 512（首次尝试因此失败 4 次综合）；实际只降了 ILA3。

## 3. 构建过程

- 综合：`build_synth_only.tcl`，0 errors / 0 critical warnings（603 warnings）；`ILA5_PROBES: tdata64=64 tkeep8=8 + tvalid/tready/tlast`；期间遇 Vivado 安装盘 transient（ddr4 IP `Failed to deliver file(s)`），重试包装第 4 次通过（坑 #61）。
- 实现：`build_v5_sweep2.tcl` 首掷 `ExtraTimingOpt` 即过：后布 **WNS=+0.012 / TNS=0.000 / WHS=+0.004** → 尾判 **WNS=+0.004 / WHS=+0.004**。
- 报告：`rpt2_ExtraTimingOpt.{timing_summary,util,worst}.rpt`（本轮成功轮）；失败轮 ExtraPostPlacementOpt 报告一并留档供诊断。

## 4. 板验准备（板已断电；下次上电按此执行）

1. 烧本目录 `aurora_mem_bridge_r2_02F7153A.bit` + ELF `j3_soft_r2_16D06BD3.elf`（绝对路径 + 先 Get-FileHash）。
2. 串口 9600：`'U'`（基线）→ `'d'` → **`'W'`**（期望：`s2cr` RS=1、`s2sr=0`、`s2len=0`）→ ping 1 → **`'W'`**（关键：期望 `s2len=0x56=86`、`s2sr=0x1002`=Idle+IOC、无 int/slv/dec 错误）→ ping 4 → `'W'`。
3. 若 `s2len=86` 且无错误：写侧洗清 → 用 `out/evidence_2026-10-18/tools/r2_ila5_capture.tcl` 首拍触发（`tvalid&&tready&&!tlast`）抓 S2MM 写流：期望 beat0 `tdata[63:0]=0xD555555555555555`、`tkeep=0xFF`；beat1 `tkeep=0x003F_FFFF`、`tlast=1`。之后转查 MM2S→shim→eth TX（PC 收帧）。
4. 若 `s2len!=86` 或出现错误位：按 PG021 `S2MM_DMASR` 错误位定位（包长/内存写），并对照 `out/ip_sim_r2/REPORT.md` 的官方 IP 期望值。

## 5. 官方工具定位回顾（本轮之前的结论，见 `out/evidence_2026-10-18/R2_official_tool_diagnosis_20261018.md`）

- 官方 axi_dma IP 仿真（`out/ip_sim_r2/`，`TEST_PASS`）：S2MM 字节映射 1:1、86B 只写 86B、完成后 `S2MM_LENGTH=86`、`S2MM_DMASR=0x1002` ⇒ **IP 语义不是故障源**。
- round2f 板端：`'d'` 后 S2MM 已启动（`s2sr=0`），但首次 ping 后**写服务前**即发生 M01 lite_regs 读楔死（LMB 快照 `WA_CNT=0`、UART 静默）⇒ round3b 的 lite fix2 是继续观测的前提。
