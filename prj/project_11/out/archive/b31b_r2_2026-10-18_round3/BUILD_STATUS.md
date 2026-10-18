# R2 round3 构建状态（b31b_r2_2026-10-18_round3 归档）

状态：**构建未收口（NO_BITSTREAM）** —— 本轮新增 lite_regs fix2 + 写流/写入口探针后，place/route **最好 WNS=-0.002ns / WHS=+0.004**（差 0.002ns 过门限），其余指令更差。按构建纪律不写位流、不覆盖在库产物（在库 R1 `c8cd3a32` 仍在 `out/` 与旧归档）。板卡本轮末按用户要求已断电，**未做本轮板验**。

## 1. round3 改动集（四文件冻结）
| 文件 | blob | 说明 |
|---|---|---|
| `rtl/axi4_master_bridge.v` | `c92c20c7` | fix2（WAITGO 首拍互斥 + 满槽判据注册化）|
| `rtl/frame_mem_if.v` | `96d5b136` | 同 round2f |
| `rtl/aurora_mem_bridge.v` | `6150212e` | +6 行 mark_debug alias（pfwd_data/en、s2mm tdata64/tkeep8/tlast，无逻辑改动）|
| `rtl/axi_lite_regs.v` | `d5d16d46` | fix2（AW/W ready 单拍 + B 串行化 + 写关前不接受 AR）|

固件候选：`f8cf4022` 基础上加 **GO 后 1ms 间隔** → ELF **`b614a2dc`**（50,944 B，本归档）。

## 2. 探针（round3 新增，供下轮板验写流取证）
- `u_ila_5 @ui_clk`：5 probe（`dbg_s2mm_tdata64[63:0]` / `dbg_s2mm_tkeep8[7:0]` / `dbg_s2mm_tvalid` / `dbg_s2mm_tready` / `dbg_s2mm_tlast_w`），深度 1024。
- ILA0 probe0 92→101b：追加 `dbg_pfwd_data[7:0]`、`dbg_pfwd_en`（写入口字节）。
- 期望 ltx：3 核（u_ila_0/u_ila_3/u_ila_5），ILA0=101+9、ILA3=152、ILA5=64/8/1/1/1。
- 采集脚本：`out/evidence_2026-10-18/tools/r2_ila5_capture.tcl`（首拍触发 `tvalid&&tready&&!tlast`）。

## 3. 构建轮次（`build_v5_sweep2.tcl`；ui_clk 300MHz；门限 WNS≥0 & WHS≥0）
| 尝试 | place 指令 | 后布 WNS | 尾判 WNS/WHS | 结论 |
|---|---|---|---|---|
| 1 | ExtraTimingOpt | -0.023（中间）→ 后布 **-0.002** | **-0.002 / +0.004** | 门限差 0.002 拒 |
| 2 | ExtraPostPlacementOpt | **-0.037** | （phys_opt 中被人为停止） | 预判拒；扫描停止 |
| 3+ | WLDriven/Explore/AltSpread | 未跑（用户要求构建后收尾，板已断电） | — | 中止 |

综合：round3 `r2j_synth` = **0 errors / 0 critical warnings**（603 warnings）；ILA5 probe 挂接成功（`ILA5_PROBES: tdata64=64 tkeep8=8 + tvalid/tready/tlast`）；lite/top 变更已进网表（module-ref OOC 已 reset）。

## 4. 下轮构建建议（差 0.002ns，优先低风险手段）
1. **ILA5 深度 1024→512**（300MHz BRAM/布线余量；不影响触发/判据）；
2. **ILA3 深度 2048→1024**；
3. 重掷 `ExtraTimingOpt`/`ExtraPostPlacementOpt` 取方差（round2f 同配方曾 +0.004）；
4. 最后才考虑裁剪判据探针（mem/mem2 计数器必须保留，S6/S10 需要）。

## 5. 板验状态（未执行）
用户于 22:3x 明确"板子已断电，此轮构建之后先收尾结束此轮任务" ⇒ 本轮未上板。下轮开场建议：
1) 烧 round2f 成功位流 `8A8FE378`（可复现 AXI 楔死规避 + 写/读数据面推进）或等 round3b 位流；
2) 用 `r2_ila5_capture.tcl` 首拍触发抓 S2MM 写流：期望 beat0 `tdata[63:0]=0xD555555555555555`、`tkeep=0xFF`；beat1 `tkeep` 低 22 lane、`tlast=1`；
3) 对照 ILA0 `dbg_pfwd_data` 写入口字节（判"写入口/写引擎/上游"分层）；
4) PC 侧 `r2_tx_probe.ps1 -Run` 三分类 + **R1 绿位流对照**（已证环境正常，R1 在 'd' 后 ping 4/4）。
