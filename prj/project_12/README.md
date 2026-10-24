# project_12 · prj12 双板互联 P1（离线就绪）

> 由 `prj/project_11` fork（2026-10-24，prj11 已收工冻结：位流 `F6012BA0` + ELF `BA3C0220`）。
> 本工程**只做两件事**：① 把 `link_ok` 从"双核"改成"单核"（跨板后 B 笼无光纤）；② 把 P1 的位流/脚本/观测/文档做到"板一到就能上板"。
> 板卡不在场：本目录不含任何上板结论。

## 0. P1 位流（已离线构建，2026-10-24）

| 项 | 值 |
|---|---|
| 位流指纹 | **`C856BA83`**（`out/aurora_mem_bridge.bit`，10,302,552 B） |
| SHA256 | `C856BA83781FE85CCDCB684B6CD3C60873AA43E92F89AD30000B5954E5667401` |
| 时序 | WNS **+0.032 ns** / WHS **+0.004 ns** / WPWS +0.022（门限 PASS，0 failing endpoints） |
| 实现阶段 CW | **0** |
| ILA | 4 核（`u_ila_0/3/5/6`），`scripts/probes.ltx` |
| 配套 ELF | `out/j3_soft_r2_BA3C0220.elf`（沿用 prj11 验收固件） |
| 详细对比 | [构建报告_P1位流_2026-10-24.md](docs/构建报告_P1位流_2026-10-24.md) |

## 1. 与 prj11 的差异（全部可复核）

| 类别 | 文件 | 改动 |
|---|---|---|
| RTL | `rtl/aurora_mem_bridge.v` | `link_ok = channel_up & channel_up_b` → `link_ok = channel_up`（保留 B 核）；新增 3 个纯观测别名 `dbg_link_ok/dbg_aurora_rst/dbg_gt_pll_lock` |
| 构建 | `scripts/build_synth_only.tcl` | 路径改 prj12；**新增 u_ila_6**（单核链路健康 119b @ user_clk，`P12_SKIP_ILA6=1` 可关）；OOC 残留 run 复位 + ddr4 产物缺失才重建（带重试）+ 综合 jobs 4 |
| 构建 | `scripts/create_project.tcl` / `create_bd_b.tcl` | 仅路径/工程名（BD 功能零差异） |
| 新增 | `scripts/build_impl.tcl` | 从 `pre_impl_debug.dcp` 实现+出流（沿用 round3d 配方），WNS/WHS 门限不过不写位流 |
| 新增 | `scripts/run_vivado_batch.ps1` / `build_p1.cmd` | 本机可用的 Vivado 批处理启动器（子进程+文件重定向；可脱离会话） |

其余 82 个源码文件与 prj11 **逐字节一致**，见 `fork_manifest_12.json`（90 文件：82 identical / 4 modified / 4 prj12-only）。

## 2. 目录

```
project_12/
├── rtl/ xdc/ sim/ sw/         # fork 自 prj11 的源码树（sw 只带 src/src_j3 与 Vitis 脚本）
├── scripts/                   # Tcl 四件套 + 启动器 + 观测/烧录脚本
├── out/                       # 构建产物（gitignore）：bit/ltx/log/报告/mock pcap
├── docs/                      # P1 观测清单 / P2 候选设计（本工程级）
├── p2_candidate/              # P2 候选 RTL + 单元 TB（**不在** Vivado 工程 fileset 里）
├── pc/                        # PC 侧脚本（发送/抓包判据/静态 ARP/pcap 造帧）
└── fork_manifest_12.json      # 逐文件 SHA256 对照 prj11
```

## 3. 怎么重建（幂等；先确认没有其它 vivado 进程）

```powershell
# 1) 建工程（约 2 分钟；从 prj9/prj10 只读 import IP）
vivado -mode batch -source D:\FPGA\prj\project_12\scripts\create_project.tcl -notrace

# 2) 综合 + ILA 插入 → scripts\pre_impl_debug.dcp
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_vivado_batch.ps1 `
    -Source D:\FPGA\prj\project_12\scripts\build_synth_only.tcl -Tag synth -Wait `
    -EnvList "R3C_SKIP_ILA4=1;R3C_LITE_ILA5=1"

# 3) 实现 + 位流（WNS/WHS 门限不过不写流）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_vivado_batch.ps1 `
    -Source D:\FPGA\prj\project_12\scripts\build_impl.tcl -Tag impl -Wait `
    -EnvList "P12_PLACE_DIRECTIVE=ExtraTimingOpt"

# 或一条链跑完（含时序回退重掷）：scripts\build_p1.cmd
```

**构建开关**：`P12_SKIP_ILA6=1`（去掉单核链路 ILA）、`P12_SYNTH_JOBS=N`（默认 4；本机 16GB 内存，8 会崩）、
`P12_PLACE_DIRECTIVE=ExtraTimingOpt|ExtraPostPlacementOpt`、`P12_SKIP_XSA=1`。

## 4. 上板用（板卡归位后）

| 脚本 | 用途 |
|---|---|
| `out\twin_burn.ps1` | 两板烧录（默认 dry-run；`-Run` 才烧；按 JTAG 线缆序号选板） |
| `out\twin_link_test.ps1` | P1-01～P1-06 执行单骨架（`-Step 1 -Run` 只做 preflight） |
| `scripts\ila_capture.tcl` | 抓 u_ila_6 快照/触发到 CSV |
| `pc\twin_send.py` / `pc\twin_recv.py` | PC1 发 / PC2 抓包判据（可离线喂 pcap） |
| `pc\static_arp.ps1` | 静态 ARP 绑定（绕过 ARP 解析） |
| `pc\make_test_pcap.py` | 造正/负向 pcap，离线证明判据脚本不是橡皮图章 |

## 5. 本阶段明确不做

- ❌ 把 P2 候选件并入 P1 位流（`p2_candidate/` 只做设计与单元验证）；
- ❌ 删 B 核 / 改 XDC（P1 最小改动；B 核清理留 P2）；
- ❌ 改 prj10/prj11（只读引用）；❌ 仓库改名/重组。
