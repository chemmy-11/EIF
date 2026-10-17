# R2 构建轮次与失败诊断（b31b_r2_2026-10-17 归档）

状态：**构建未收口（NO_BITSTREAM）** —— 所有轮次均被时序门限（WNS≥0 & WHS≥0）拒收，按构建纪律不写位流、**不覆盖在库产物**（本目录中 `aurora_mem_bridge_r1_in_service_c8cd3a32.bit` 是 R1 在库位流，仅作参照，不是 R2 产物）。

## 1. 轮次表（`build_v5_sweep.tcl` + `build_v5_sweep2.tcl`；时钟 mmcm_clkout0 = ui_clk 300MHz）

| 轮 | place 指令 | 后布 WNS | 最终 WNS / WHS | 结论 |
|---|---|---|---|---|
| 1 | ExtraTimingOpt | -0.198 | **-0.098 / +0.004** | 门限拒 |
| 2 | Default | — | — | `Opt 31-306` MIG 缝合瞬态（坑账本已知，不判设计） |
| 3 | AggressiveExplore | — | — | `[Common 17-69] Placer could not place all instances`（拥塞） |
| 4 | WLDrivenBlockPlacement | -0.251 | -0.225 / +0.004 | 门限拒 |
| 5 | ExtraPostPlacementOpt | -0.200 | **-0.175 / +0.004** | 门限拒 |

综合（`build_r2_synth.log`）：**0 errors / 0 critical warnings**（743 warnings）；`pre_impl_debug.dcp` + ILA 四核（含 R2 新探针）OK。⇒ 失败发生在 place/route 时序收敛，不在综合/功能。

## 2. 失败诊断（`rpt2_ExtraPostPlacementOpt.worst.rpt`，30 条最差路径）

- **25/30 条**：源 = `u_mem/u_wr_bytes/wr_gray_s2_reg[3]/C`（user→ui 字节 FIFO 的**同步化写指针**）→ 目的 = `u_mem/u_bridge/g_wr_dma.wd_data_r_reg[*]/CE`（R2 新写引擎 512b 数据寄存器的**逐字节 lane 使能**）。
  - 数据路径 3.238ns（logic 1.405 / **route 1.833 = 56.6%**，8 级逻辑含 CARRY8×3）；slack -0.175ns。
  - 机制：`wf_empty`（gray 比较，3 个 CARRY8）→ `wd_fill` → 64:1 lane 译码 → 512 个 CE 负载。新增 S2MM 通道后布线拥塞，使这条**已有形态的锥**（R1 旧 W FSM 同构）越界。
- **5/30 条**：`u_mem2/u_wr_bytes/...` → `u_mem2/u_bridge/g_wr_hw.w_data_r_reg[*]/D`（**桥② 旧写 FSM，R1 既有同族路径**，未被 R2 改动）⇒ 设计整体在该族路径上余量本就 <0.2ns。

## 3. 建议修复（下次开工第一步，不需要重新论证设计）

**主修：新写引擎字节捕获加 1 级流水**（`axi4_master_bridge.v` 的 `g_wr_dma` 分支）：
- `wf_rd_en` 仍由 `!wf_empty`（轻负载：FIFO 读指针 CE）控制；
- 新增 `byte_q`/`byte_valid_q` 一拍：本周期 `byte_q<=wf_data; byte_valid_q<=1`，下周期用**寄存器** `byte_valid_q` + `wd_bi` 写 `wd_data_r[wd_bi*8+:8]` / `wd_keep_r[wd_bi]`；
- 效果：长度 8 级的 gray→compare→decode 锥从 512 CE 的路径上移走（只剩 1 个 FF 到 CE），吞吐仍 1 byte/cycle（流水不降速）。
- **不动** `HAS_DMA=0` 分支（坑 #55）；但注意 5/30 的桥② 旧 FSM 同族路径也在边缘——主修后若仍差 0.0x，再评估"对两分支同构加流水"（需 W4 回归 + 等价性论证）或靠 place 指令/方差收敛。

**备选**：
1. 裁 ILA3 低价值探针（`dbg_mem2_stall/len`、`dbg_mem_wslot/rslot` 等 ~48b，保留 S6/S10 硬判所需 wm/wr/rd/ost）后重综合再掷（+7min 综合）；
2. 追加 place 指令取方差：`ExtraPostPlacementOpt`（已试 -0.175）、`ExtraTimingOpt`（-0.098 最好）、`SSI_SpreadLogic_high`、`AltSpreadLogic_high`、二次重掷；注意本轮 `AggressiveExplore` 布局失败、`Default` MIG 瞬态；
3. 单掷 `build_debug.tcl`（R1 曾用该配方出 +0.004）。

## 4. 复现命令

```powershell
# 综合 + ILA（会重写 pre_impl_debug.dcp）
& 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat' -mode batch -source D:\FPGA\prj\project_11\scripts\build_synth_only.tcl -notrace
# 扩展扫描（失败也落 dcp+报告；stdout 必须文件重定向——坑 #58）
cmd /c ""D:\Xilinx\Vivado\2023.1\bin\vivado.bat" -mode batch -source D:\FPGA\prj\project_11\scripts\build_v5_sweep2.tcl -notrace > D:\FPGA\prj\project_11\out\r2_sweep2_console.log 2>&1"
```

> 本文件为证据归档；记录正文：`C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`（docs 镜像见 `D:\FPGA\docs\调试记录\`）。
