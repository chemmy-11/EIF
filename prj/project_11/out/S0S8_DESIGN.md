# S0–S8 判据设计说明（prj11 路线 B 读侧收口 · 退役位流 rdfix · 2026-10-17）

> 配套脚本：`out\retire_s0_s8.ps1`（S0–S8 一键）、`out\j3_fourchains.ps1`（J3 四链封装）。
> 本文回答四件事：每一步**能区分什么**、**判据未取得怎么标注**、**为什么顺序不能换**、
> 以及旧脚本 `retire_s2_s6.ps1` 两处已证实失效的**证据行号**。所有"今天实测"结论均给出原始日志/源码行号，
> 不把相容假说写成判定（等级口径同 `evidence_2026-10-17\rtl_audit_204519.md` §0）。

---

## 0. 一句话口径

**退役位流上唯一的读出路径是 DMA 描述符（engine=1，由软核驻留服务驱动）；bridg① 硬件读引擎已退役，
桥② 的硬件读引擎必须保留。** 所以上板判据的全部有效性都建立在两个前置不变量上：

1. **测 ping/emit 之前板上必须处于 engine=1 + SEQ，且中间不能跑任何 M/A/B 轮**；
2. **`'d'` 是翻转命令，每次都必须用 `'U'` 回读确认 `mode=1` 且 `req.bit24=1`**（不允许"发一次就当 DMA"）；
3. **J3 只在不带 `--dma` 的前提下跑 M/A/B**，且跑前板卡必须是新烧录干净状态或满足
   `'S'` + `wmwr==wmrd` 且 `req.bit25=0` 连续两拍；任一轮失败就停（不重试），
   `wr+255`/收帧停摆 ⇒ 判据未取得 + 板卡需重烧（依据 §1.7；`green_bridge_j3_run1.log` vs
   `green_engine1_j3_dma.log`）。

---

## 1. 环境与仪器口径（先记死）

### 1.1 烧写与工件

- 烧写命令：`xsct D:/FPGA/prj/project_11/out/jb31b_burn_pair.tcl <bit> <elf>`（绝对路径、先核 SHA256）。
  脚本实现见 `jb31b_burn_pair.tcl`（`fpga` → `dow` → `con`，成功打印 `PAIR_BURNED`）。
- **必须用归档绝对路径**：构建会把 `out\aurora_mem_bridge.bit` 覆盖掉。`retire_s0_s8.ps1` 在 `-Run` 下
  若 `-Bit` 落在 `out\archive\` 之外会**拒绝烧写**（`-AllowNonArchive` 可显式放行），并对
  `out\aurora_mem_bridge.bit` 直接判 FAIL。本次 rdfix 产物归档目标：
  `out\archive\b31b_rdfix_2026-10-17\`（实际 hash 由 Lead 归档时确定；脚本只打印 hash8，
  可加 `-ExpectBitHash8/-ExpectElfHash8` 钉死）。
- S0 期望的成功标记：`V5_SWEEP_OK`（回滚扫描构建，见 `scripts/build_v5_sweep.tcl:37`）
  或 `W5_BUILD_OK`/`DBG_BUILD_DONE`（单次构建，见 `scripts/build_debug.tcl:303-306`）；
  失败标记：`V5_SWEEP_ALL_FAIL`/`W5_BUILD_TIMING_FAIL`；门限值 `WNS_GATE/WHS_GATE`
  或 `SWEEP_<directive>: WNS=.. WHS=..`（例：`b31b_retire_flag_2026-10-17\build_retire_sweep3.log:6046,6130`）。

### 1.2 `'d'` 是翻转命令（不是"置 DMA"）

`sw/src_j3/main.c:436-447`：

```
else if (c == 'd') {
    g_dma_mode = !g_dma_mode;                       // 436-439：取反
    R_ENGINE = g_dma_mode ? 1u : 0u;                // 443：引擎位跟随
    if (g_dma_mode) R_MODE = MODE_SEQ;              // 444：切 DMA 时顺带置 SEQ
    ... "[B2] DMAMODE now=DMA|bridge"               // 445-446
}
```

⇒ 板上已是 DMA 时再发 `'d'` 会**翻回 bridge**，整轮 ping 无效（今天已实测踩中）。
`retire_s0_s8.ps1` 的 `Set-EngineMode` 统一走：`'U'` 回读 `mode` + `req.bit24` →
不匹配才发 `'d'` → 再回读；最多翻转 3 次；**最后必须同时满足 `mode=1` 且 `req.bit24=1`** 才继续。
`j3_fourchains.ps1` 用同一实现（两模式切换前都做双重确认）。

### 1.3 静态 ARP 邻居及其副作用（会直接影响 S8 判据）

- PC 侧永久静态邻居：`192.168.1.10 → 00-11-22-33-44-55`（Permanent）。这是今天让退役路径
  "首次可取值"的手段（文档 §二之六）：PC 不再发 ARP，ping 直接单播到板 MAC。
- **副作用（已由 ILA 发射字节流证实）**：板端 ARP 学不到 PC MAC ⇒ 板**自发帧的 dst MAC 会写成
  `ff:ff:ff:ff:ff:ff`（广播）**。`evidence_2026-10-17\rdcap2_cmp_retired.log:11-13` 抓到
  `dst=ff:ff:ff:ff:ff:ff ... BCAST`，而同文件 `:18` 的位置差异 `8..13` 就是 dst MAC；
  `:29-30` 显示 `--mask-volatile`（只掩 IP-ID/校验和/FCS）后仍有 6 处差异（即 dst MAC）⇒ **必须连
  8-13 一起掩**。
- ⇒ **S8 发射流同构判据的掩码固定为**：`8-13`（dst MAC）+ `26-27`（IPv4 ID）+ `32-33`（IP 头校验和）
  + `-4..-1`（FCS）。掩掉后应与归档绿参考 `archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv` 逐字节同构。
  不掩会假红（strict ndiff=14）。
- ⇒ **UDP 回显**在广播 dst 下是否被 PC 接收需要显式核对：若"S5 ping 通、S8a UDP 回显 0/1"，先查
  广播 dst / PC 收包过滤因素，**不要急于判数据面坏**（脚本 S8a 把它做成信息项 + WARN，不硬判失败）。
- **NIC 计数口径（必须，2026-10-17 21:0x 修正）**：板自发帧 dst MAC 是广播 ⇒ 回包计入
  `ReceivedBytes`（以及可能 `ReceivedBroadcastPackets`），**`ReceivedUnicast` 恒 0**。
  今天绿位流 engine=1 实测：`green_engine1_ping.log` 里 ping **4/4**（4 条 `Reply ... TTL=128`），
  同机 NIC 读数 `ReceivedUnicast delta = 0`、**`ReceivedBytes delta = +296` = 4×74B**（ICMP 回包帧
  14+20+8+32=74B）⇒ S4/S5 的 NIC 主判据必须改成 `ReceivedBytes`（单帧 ≥74、4 帧 ≥296），
  `ReceivedBroadcastPackets` 作辅助打印；**禁止**再用 `ReceivedUnicast >= 1/4`（会假 FAIL）。
  理由与发射流掩码（dst MAC 8–13）完全一致。

### 1.4 `'U'` 探针解析口径

`sw/src_j3/main.c:448-472` 打印 9 行；每行**首值是上一地址残值**，只用第 2..6 个值（脚本实现：
丢首值、其余要求相等、不等取最后一值并 WARN）。寄存器语义：

| 行 | 寄存器 | 解码（32 位） |
|---|---|---|
| `req` | `+0x34` `ro_dma_req` | `bit25`=sticky 待服务请求；`bit24`=engine(1=DMA)；`slot=[23:16]`；`len=[15:0]`（`frame_mem_if.v:78,502`） |
| `emit` | `+0x3C` `ro_dbg_emit` | `len=[31:16]`；`slot=[15:8]`；`byte0=[7:0]`（`frame_mem_if.v:507-524`） |
| `wmwr` | `+0x08` | `[15:0]` = `u_wr_frame`（桥① 写侧收帧数，高 16 位为 0） |
| `wmrd` | `+0x0C` | `[15:0]` = `u_rd_frame`（桥① 读出帧数，高 16 位为 0） |
| `mode` | 软件 | `g_dma_mode`（**不是** `cfg_mode`！`main.c:470-471`） |

`emit` 的字节流口径（ILA probe1 抓的就是它）：**8B 前导(0x55×7+0xD5) + 以太网帧 + 4B FCS**
⇒ `len = 帧长 + 12`；首字节恒为 `0x55`。实测：ping 32B 载荷 ⇒ `0x56`=86（`clean_engine1_ping_204321.log`
step4 `emit=0560e55`：len 86 slot 14 byte0 0x55）；manual_round 64B 载荷 ⇒ `0x76`=118
（`s2_s6_204148.log` S3 `emit=0760155`：len 118 slot 1）。

### 1.5 计数器语义与"读出路径启动"的硬证据

- `WM_WR` 记的是**写入桥① 的帧数**。栈 TX（`eth_ctrl` 的 ARP/ICMP/UDP 应答，见
  `aurora_mem_bridge.v:517-636`）→ 泵A（`:754-767`）→ 桥① 写侧（`:772-818`）。
- `WM_RD` 记的是**桥① 读出帧数**（`frame_mem_if.v` 读 FSM 的 `u_rd_frame_cnt`），读出流 →
  `axis_word_pack` → Aurora TX（`aurora_mem_bridge.v:1159-1171`）。
- ⇒ **ping×4 期间 `WM_WR` 与 `WM_RD` 各 +4 = "应答帧被写入、且桥① 真的读出来了"**；这是区分
  "读侧没启动"与"读出来了但没上线"的关键。今天 `clean_engine1_ping_204321.log` 就是后者：
  engine=1+SEQ、不跑轮次、ping 0/4，但 `wmwr/wmrd 11→15`（各 +4）⇒ 第一跳通过、第二跳断。

### 1.6 为什么 ping 前不能跑任何 M/A/B 轮（顺序不变量）

1. `round_command` 段1 把 `R_MODE = MODE_RND` 且**轮末不恢复**（`main.c:358`，注释 `380-381`）；
2. 轮末把 `R_ENGINE` **写回 0**（`main.c:375-379`，`g_dma_mode=1` 时）；
3. RND 下顶层**不再自动发读请求**（`aurora_mem_bridge.v:322-327`：RND 分支只认命令通道脉冲），
   engine=0 时退役 RTL 又没有硬件读出路径 ⇒ **读侧零启动**。

已证实的反例（旧脚本 S2→S4→S5 那轮，`evidence_2026-10-17\s2_s6_204148.log`）：
S6 `req=0x00010076`（bit24=0）、`WM_WR=7` 而 `WM_RD=2`（+0），ping 0/4、NIC delta=0。
该轮 S5 是**无效实验**，不是"判据通过"——审计解码见 `rtl_audit_204519.md:377-388`。

### 1.7 J3 四链的执行口径（2026-10-17 21:0x 实测修正：**不带 `--dma`**）

- **不带 `--dma` 跑 M/A/B**。今天同一绿位流 `708f15a4` + ELF `2961b585`、新烧录干净状态对照：
  - 不带 `--dma`：`green_bridge_j3_run1.log` → **PASS**（`[M] wr+256 rd+256 inv=32132 miss=0`；
    `[A] wr+256 rd+255 miss=[5356]`=恰帧#100，符合负向设计；`[B] wr+256 rd+256`；
    `[B2-SOFT-VERIFY] PASS`）。
  - 带 `--dma`：`green_engine1_j3_dma.log` / `run2.log` / `run3_nowarmup.log` → **连续三次 FAIL**，
    均为 `[M] wr+255`（写阶段丢 1 帧）→ 读阶段不启动 → 槽满 → 后续全 FAIL；还可能把板卡留在
    "256 槽未读 + 读 FSM 泊 `R_DRET`"的半楔死状态（需重烧恢复）。
  - 旁证：`green_fresh_manual_round_256.log`（新烧绿、**不发 `'d'`**）`manual_round.py COM5 256`
    → `[B2] DONE t=M wr+256 rd+256 stall=0` + `echo=256/256`。
  - 机制今天未定（`[L3]` 事实、`[L1]` 归因）⇒ 操作上**禁止**在 J3 前手工发 `'d'`；`'d'` 只决定
    空闲期驻留服务，给 ping 等判据用。
- **J3 前置**：板卡必须是新烧录的干净状态，或至少满足 `发 'S'` → 轮询 `'U'` 直到
  `wmwr == wmrd` 且 `req.bit25(sticky)=0` **连续两拍**（只读检查，不发 `'d'`）。
  不满足 ⇒ 判「判据未取得 + 板卡需重烧」，**不跑**（残留"已写未读"帧占槽会让 M 轮 `wr+255`）。
- **失败纪律**：任一轮 FAIL 就**不再跑后续轮**（不自动重试；重试会级联假 FAIL 并可能楔死板卡）。
  `wr+255` / `收帧停摆` ⇒ 判「判据未取得 + 板卡需重烧」。`j3_fourchains.ps1` 用逐轮独立调用
  `j3_soft_verify.py --rounds M/A/B` 来让 M 失败立即止损（不改原件；其内部对该轮仍有 ≤3 次尝试，
  属既有脚本行为）。
- **引擎由谁切**：M/A/B 轮内固件自己把 `R_ENGINE` 置 1 并逐笔服务 DMA（以 `g_dma_mode=1` 为前提，
  `sw/src_j3/main.c:352-356`）；绿位流 `g_dma_mode=0` 时走桥① 硬件读路径（`green_bridge_j3_run1.log`
  即此形态，故不带 `--dma` 也能 PASS）。退役位流只有 DMA 读出路径，故在 S0–S8 流程里由 S3 先
  `Set-EngineMode(DMA)` 再进 S8。轮末固件把 `R_ENGINE` 写回 0、`R_MODE` 停在 RND；J3 跑完只读状态，
  需要 ping/emit 时再单独 `Set-EngineMode DMA`（`j3_fourchains.ps1` 不在 J3 后自动发 `'d'`）。
- **为什么 J3 不再跑"桥模式"分支**：退役改动只作用于 `HAS_DMA=1` 的桥①
  （`axi4_master_bridge.v:694-704` 一律泊 `R_DRET` 等 DMA shim；`705-717` 的硬件读 FSM 只给
  `HAS_DMA=0` 的桥②）⇒ 退役位流 engine=0 时**没有任何读出路径**，跑"桥模式"必然失败
  （预期行为、不是回归）。新版只做"不带 `--dma` 的一次 M/A/B"，`-Bitstream` 只影响前置提示与期望。

---

## 2. 逐步设计（能区分什么 / 判据 / 判据未取得怎么标）

> 统一退出语义：`PASS` / `FAIL`（有效负结果）/ `NOT_OBTAINED`（判据未取得=实验无效）/ `SKIP`（可选或占位）。
> **FAIL 与 NOT_OBTAINED 都使脚本退出码非 0**，并在末尾打印 `S0S8_RESULT: FAIL <step>`（NOT_OBTAINED
> 时带 `(判据未取得)` 后缀）——绝不让"无效实验"冒充"通过"。

| 步 | 动作 | 判据 | 能区分什么 | 判据未取得时 |
|---|---|---|---|---|
| **S0** | 离线：位流/ELF SHA256 + 构建日志门限 | 日志含 `WNS_GATE/WHS_GATE`（或 `SWEEP_*: WNS/WHS`）且 WNS≥0、WHS≥0，且成功标记在、失败标记不在；hash8 打印（可 `-Expect*Hash8` 钉死） | 位流是否真出得来（时序门限）；工件身份（归档对） | 无 `-BuildLog` ⇒ `SKIP` 并标注（非失败）；日志存在但解析不到门限 ⇒ `NOT_OBTAINED` |
| **S1**（可选） | 烧绿 `708f15a4`+`c13a54f5` → ping 3 + `'L'` + 邻居 | ping 3/3；`[B2] LAT w=.. r=..` 应答；邻居 `Permanent` 且 MAC 正确 | 板/线/PC 侧没变（之后 S2 烧退役对 = 唯一变量） | 未给 `-GreenBit/-GreenElf` ⇒ `SKIP`；烧后无 boot/无 `'L'` ⇒ `FAIL`（环境前提崩了，后续结论降级参考） |
| **S2a** | 烧新退役对，**先不发 `'d'`**，`manual_round.py COM5 1` | 必须**失败**：`WAITWR-FAIL`/`STALL`、无 `[B2] DONE`、`echo=0` | "1 帧凑不齐一轮"（NSLOTS 编译期 256，`main.c:68,270-282`）⇒ 只能证明 M 轮没完成，**不能单独证明位流身份**（见 §5 加严） | `SEQOK/READY` 都没收到 ⇒ `NOT_OBTAINED`（串口/固件问题）；出现 `DONE` ⇒ `FAIL` |
| **S2b**（本次加严，`-SkipS2IdentityPing` 可关） | `engine=0` 确认 → 发 `'S'` → ping −n 1，**全程不发 `'d'`** | 必须 **0 回包 + NIC `ReceivedBytes` delta=0** | **真正的位流身份原位判据**：绿 RTL 在 engine=0 时桥① 硬件读引擎在线 ⇒ 会回包；退役 RTL 无读出路径 ⇒ 不回包（`axi4_master_bridge.v:694-717`） | engine=0 无法确认 ⇒ `NOT_OBTAINED`；有回包 ⇒ `FAIL`（烧错/烧旧/engine 位已 1） |
| **S3** | `Set-EngineMode(DMA)` → `'S'` → `'U'` 整段回读 | `mode=1` 且 `req.bit24=1`（断言）；同时记录 `bit25/slot/len` | 补上"engine 位当场回读"证据；`'U'` 原始行整段落盘 | `'U'` 无应答/解析失败/bit24=0 ⇒ `FAIL`（并给出 Set-EngineMode 的翻转轨迹） |
| **S3b**（本次加严） | 静默窗：轮询 `'U'` 直到 `wmwr==wmrd` 且 `bit25=0` 连续两拍 | 清掉 S2a/S2b 留下的"已写未读"帧 | 让 S4/S5 的差分基线干净；持续不排空 = 读出侧停摆（与 H4/H6 同形） | 10 次轮询仍不静 ⇒ `FAIL`（后面 S4/S5 自动降级 `NOT_OBTAINED`） |
| **S4** | U 前 → `ping -n 1 -w 1500` → U 后 | ping 1/1、NIC **`ReceivedBytes` delta≥74**（1×74B ICMP 回包）、`WM_WR+1`、`WM_RD+1` | 单帧端到端（消掉多帧/时序变量）；失败形态可切分：`WR+0`=请求未达栈/未生成应答；`WR+1/RD+0`=读出未启动；`WR+1/RD+1` 但线上 0/1=断在 bridge① 读出之后 | 前置（mode/bit24）不满足、NIC 不可用、或 S3b 静默窗未建立 ⇒ `NOT_OBTAINED`；计数一致但线上 0/1 ⇒ `FAIL`（有效负结果） |
| **S5** | U 前 → `ping -n 4 -w 900` → U 后；打印 ping 统计 | **`WM_WR +4` 且 `WM_RD +4`**（硬断言）+ ping 4/4 + NIC **`ReceivedBytes` delta≥296**（4×74B） | 唯一"到没到线上"的真值；`WM_RD+0` 直接排除"线上问题"，把断点锁在读出侧 | S3b 基线不干净 ⇒ `NOT_OBTAINED`；计数在但回包 0/4 ⇒ `FAIL`（断点在 bridge① 读出之后）；`WR+4/RD+0` ⇒ `FAIL`（读出侧零启动） |
| **S6** | 读 `'U'` 的 emit/req/wm | emit：`len∈{86,74}`、`byte0=0x55`、`slot` = 最近 4 写槽（严格期望 `(wmwr_last-1)&0xFF`，差槽仅 WARN） | 分叉：**WM_RD 未推进**⇒无发射可判（`NOT_OBTAINED`）；**emit 空/字段错**⇒断在「shim→bridge①读出端口」；**emit 正确但线上 0/4**⇒断在「bridge① 读出之后」（`pack→Aurora TX→环回→RX→桥②读侧→泵B→mux→PHY`） | WM_RD+0 或 S5 基线不干净 ⇒ `NOT_OBTAINED`；`emit=0`/字段错/emit 正确但线上 0 ⇒ `FAIL` |
| **S7** | ILA 命令占位（Lead 执行） | 桥② 计数：`dbg_mem2_wr_frm/ost` 增长而 `dbg_mem2_rd_frm==0` ⇒ 断在桥② 读侧；`rd_frm` 增长而泵B 无活动 ⇒ 泵B；两者都有 ⇒ mux/PHY/PC | 字节级/计数级定位第二跳 | 永远 `SKIP`（占位；不跑 Vivado/JTAG） |
| **S8a** | UDP 单帧回显（`jb31b_rdcap2_send.py --no-uart`） | 回显 1/1 且逐字节一致；0/1 只 WARN（广播 dst 环境因素） | 数据面往返（含双跳）的旁证 | 解析不到 ⇒ NOTE；不计入失败 |
| **S8b** | 调 `j3_fourchains.ps1 -Bitstream retired`：**不带 `--dma`** 逐轮跑 M/A/B（**nslots 默认 256**）；跑前发 `'S'` + `'U'` 检查 `wmwr==wmrd` 且 `bit25=0` 连续两拍（只读，不发 `'d'`）；任一轮失败即停 | M/A/B 三轮各自 `[B2-SOFT-VERIFY] PASS`（硬要求）；`wr+255`/收帧停摆 ⇒ 判据未取得 + 板卡需重烧 | 功能面收口；读出链路零回归（引擎由固件轮内决定，绿=桥/DMA 皆可，退役=DMA 唯一路径） | 前置槽表不干净 ⇒ `NOT_OBTAINED`（板卡需重烧）；任一轮 `wr+255`/停摆 ⇒ `NOT_OBTAINED`；其他失败 ⇒ `FAIL`；缺 wrapper ⇒ `NOT_OBTAINED` |
| **S8c** | 发射流同构（可选 `-EmitCsv`） | `rdcap2_cmp.py` 掩码 `8-13,26-27,32-33,-4..-1` 后 `ISOMORPHIC=YES` 且 1526B、前导 `55*7+D5` | 第一跳发射字节流与归档绿参考同构（排除"字节被改"级差异） | 未给 CSV ⇒ `SKIP`（打印可复制命令）；cmp 失败 ⇒ `FAIL`（先排除 dst MAC 广播） |
| **S8d** | 四档零回归命令占位 | `udp_verify_ddr.py` 尾部 `DDR_VERIFY: PASS`（四档：链路/基础/槽深/稳定） | 数据穿 DDR 往返逐字节（B4 口径） | 占位（Lead 决定何时跑 green/retired） |
| **收尾** | 重新 `Set-EngineMode(DMA)` | `mode=1` 且 `req.bit24=1` | M/A/B 轮末 `R_ENGINE=0`（`main.c:375-379`），后续任何测量前必须重新确认 | 恢复失败 ⇒ `FAIL` |

---

## 3. 顺序为什么不能换（依赖图）

```
S0(离线门限/身份) ──► S1(绿基线, 可选) ──► S2(烧退役对, 不发 d; 身份)
                                              │
                                              ▼
                              S3(Set-EngineMode DMA + 'U' bit24 断言)
                                              │
                                              ▼
                              S3b(静默窗: 清 S2 残留待读帧)
                                              │
                    ┌─────────────────────────┴───────────────┐
                    ▼                                         ▼
              S4(单帧) ──► S5(ping×4, WM_WR/WM_RD 各 +4) ──► S6(emit 分叉)
                                                              │
                                                              ▼
                                                    S7(ILA 占位, 由 Lead)
                                                              │
                                                              ▼
                              S8(J3 四链两模式 + 发射流/四档 + 收尾重切 DMA)
```

- **S2 必须在 S3 之前**：S2 的身份判据前提是"还没发 `'d'`、engine=0"；一旦切了 DMA 就不再是原位身份判据。
- **S3/S3b 必须在 S4/S5 之前**：S2a/S2b 各留下"已写未读"帧；且 `'d'` 之前 `R_MODE` 可能停在 RND。
  S3 的 `'S'` + S3b 静默窗把基线与引擎状态都归位，S4/S5 的差分才是干净窗口。
- **S4/S5/S6 必须在 S8 之前**：S8 要跑 M/A/B 轮，而轮末会留 `R_ENGINE=0`/`R_MODE=RND`（`main.c:358/375-379`）；
  J3 本身不带 `--dma`（§1.7），跑完只读状态、不自动切 DMA；需要继续 ping/emit 判据时再单独
  `Set-EngineMode DMA`。S8 前若槽表不干净会直接判据未取得（板卡需重烧）。
- **S5 与 S6 不可拆**：S6 的分叉输入就是 S5 的 `WM_RD` delta 与 NIC delta；只有 S5 的 `WM_RD+4`
  成立时，"emit 正确但线上 0/4"才等于"断点在 bridge① 读出之后"。
- **S0 必须在一切之前**：时序门限不过的位流按纪律不得上板（`build_debug.tcl:292-306` 的 W5 门限纪律）。

---

## 4. 旧脚本 `retire_s2_s6.ps1` 两处已证实失效（证据行号）

### 失效①：S4 跑 M 轮后，S5 ping 是在 engine=0 + RND 下跑的（无效实验）

- 旧脚本 `out\retire_s2_s6.ps1:48`：
  `RunCapture "S4 single-frame WITH d (expect wr+1 rd+1, echo=1)" { ... py $mr $Port 1 }`
  —— `$mr = manual_round.py`，即实打实跑了一轮 `'M'`。
- 固件在轮末做两件事：`R_MODE` 停在 RND（`sw/src_j3/main.c:358`，轮末不恢复的注释在 `380-381`）；
  `R_ENGINE` 被**写回 0**（`sw/src_j3/main.c:375-379`，`g_dma_mode=1` 时打印
  `[B2] DMAMODE engine=bridge`）。
- 后果：轮后的 `'U'` 回读 `req.bit24=0`、`WM_RD` 冻结，之后的 S5 ping 没有任何读出路径。
  原始证据（S2–S6 那轮）：`evidence_2026-10-17\s2_s6_204148.log` 的 S6 段
  `[B2] U req: ... 00010076`、`[B2] U wmrd: ... 00000002`、`[B2] U wmwr: ... 00000007`
  （解码见 `rtl_audit_204519.md:383-385`：`bit24=0`、`WM_WR 2→7`、`WM_RD 2→2`）。
- 新脚本的对策：ping 前**不跑任何 M/A/B**；S4 改 `ping -n 1`；S3 前 `Set-EngineMode` 双重确认；
  S8 之后强制重新切回 DMA 并重验 bit24。

### 失效②：`manual_round.py COM5 1` 的"单帧"对 `'M'` 轮永远不成立

- 旧脚本 `out\retire_s2_s6.ps1:44` 与 `:48` 都用 `py $mr $Port 1` 做"单帧"。
- 板端 `NSLOTS` 是编译期 256（`sw/src_j3/main.c:68`）；`run_round` 先等 `WM_WR` 增加 **NSLOTS=256**
  （`main.c:270-282`：`WRWAIT t=.. want+256`；不足即 `WAITWR-FAIL` 并 return 1），之后才进入读阶段。
  `manual_round.py` 只发 1 帧（`out\manual_round.py:51-55` 按 argv 发 NSL 帧）⇒ **必然 `WAITWR-FAIL`**，
  与位流/引擎无关。
- 实测：`evidence_2026-10-17\s2_s6_204148.log` 两处 `[B2] WAITWR-FAIL t=M got+1`（S2 与 S4）、`echo=0`。
- 新脚本的对策：S2a 把"1 帧必然失败"当作**负向前置**（不是通过）；S4 的"单帧"改用
  `ping -n 1`（ICMP 应答帧恰好 1 帧写 +1 帧读），并同时核 NIC delta 与 WM 差分。

### 附：旧脚本其它已修的口径问题

- 旧 `:46` S3 直接发 `'d'` 后读 `'U'`，未校验 `mode`；若板已是 DMA 则 `'d'` 会翻回 bridge（§1.2）。
- 旧 `:50-57` 用 `Get-NetIPAddress 192.168.1.102` 找网卡后可接受；但未做 S3b 静默窗，
  无法保证 ping 前没有待读残留帧。

---

## 5. 本次已实现的判据修正（相对 2026-10-16 §二之七 原表）

1. **Set-EngineMode（替代"直接发 `'d'`"）**：`'U'` 回读 `mode`+`req.bit24` 双重确认，最多翻转 3 次；
   `j3_fourchains.ps1` 两模式切换前同样确认。证据：`main.c:436-447`；实测踩坑：今天 20:4x 的无效轮。
2. **S2b 位流身份 ping（新增）**：原表 S2 的 `manual_round 1` 必然失败（失效②），不具身份判别力；
   "不发 `'d'` 的 ping"才是绿/退役的真判别（绿 engine=0 有硬件读出路径：`axi4_master_bridge.v:694-717`；
   绿 ELF `c13a54f5` 在 10-16 已有 ping 3/3 记录，见文档 §二之三表）。
3. **S3b 静默窗（新增）**：S2a/S2b 必然留下"已写未读"帧；`'d'` 后驻留服务会把它们读出
   （实测 `s2_s6_204148.log` S3 时 `WM_WR==WM_RD==2`）。不做静默窗，S4/S5 的 deltas 会被残留帧污染。
4. **S4 三态判定**：前置/仪器不满足 ⇒ `NOT_OBTAINED`（判据未取得）；计数一致但线上 0/1 ⇒ `FAIL`
   （有效负结果）。两者都退出码非 0，但日志措辞不同，避免"无效实验"被读成"通过"或"缺陷"。
5. **S6 的 `dbg_emit` 语义修正**：原表把 emit 当"发射口"判据；实际 emit 在**桥①**（`frame_mem_if.v:507-524`
   + `aurora_mem_bridge.v:719/817`），只覆盖「桥①读出 → pack → Aurora TX」**第一跳**；上线路径是
   **Aurora TX → 光纤环回 → Aurora RX → 桥②(`u_mem2`) 硬件读 → 泵B → 末级 mux → PHY**
   （审计 `rtl_audit_204519.md:155-199`）。⇒ "emit 正确但线上 0"的断点**不是**原表写的
   "发射口→线上"，而是**bridge① 读出之后的整段两跳路径**，必须用 S7 的桥② 计数继续二分。
   旧位流（`0ecb8438`）的 ILA 实测正是该形态：`dbg_mem2_wr_frm/ost 19→23` 而 `dbg_mem2_rd_frm 恒 0`
   （`evidence_2026-10-17\ilacap_counters_summary.txt`）⇒ 桥② 读侧死（RTL 修复后 rdfix 应改变这一形态）。
6. **emit len 口径**：字节流含 8B 前导 + 4B FCS ⇒ `len=帧长+12`；ping 32B 期望 86，同时容忍 74
   （若未来探针改为不捕前导/FCS 口径）并在日志标注。
7. **S8 发射流掩码**：必须掩 `8-13`(dst MAC，静态 ARP 环境=广播) + `26-27`(IPv4 ID) + `32-33`(IP cksum)
   + 末 4B(FCS)；`--mask-volatile` 不含 dst MAC，不够（`rdcap2_cmp_retired.log:29-30`）。
8. **S8 收尾只读状态**：M/A/B 轮末 engine→0、R_MODE=RND（`main.c:358/375-379`）；J3 之后**不自动发 `'d'`**
   （避免预序列翻转窗口干扰），只打印状态；需要继续 ping/emit 判据时再单独 `Set-EngineMode DMA` 并重验 bit24。
9. **S0 工件纪律**：拒绝烧非归档/易被构建覆盖的位流；可 `-ExpectBitHash8/-ExpectElfHash8` 钉死身份。
10. **J3 执行口径（21:0x 实测修正）**：**不带 `--dma`** 跑 M/A/B，每轮独立调用（M 失败即止损）；
    跑前 `'S'` + 只读检查 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍；**失败不自动重试**，
    `wr+255`/收帧停摆 ⇒ 判「判据未取得 + 板卡需重烧」。依据：`green_bridge_j3_run1.log`（不带 --dma PASS）
    vs `green_engine1_j3_dma.log`/`run2`/`run3_nowarmup`（带 --dma 连续 FAIL wr+255）；
    旁证 `green_fresh_manual_round_256.log`（不发 `'d'`，`manual_round 256` PASS）。
11. **NIC 主判据 = `ReceivedBytes`**（21:0x 修正）：板自发帧 dst MAC 是广播 ⇒ `ReceivedUnicast` 恒 0。
    绿位流实测 ping 4/4 时 `Unicast delta=0`、`Bytes delta=+296`（4×74B）。S4 要求 `Bytes ≥74`、
    S5 要求 `Bytes ≥296`，`ReceivedBroadcastPackets` 仅辅助打印。用 Unicast 会假 FAIL。
12. **退役位流的 J3 前置特别说明**：退役 RTL 只有 DMA 读出路径，而轮内切 DMA 以 `g_dma_mode=1`
    为前提（`main.c:352-356`）。所以 S0–S8 流程中 S3 已把板切到 DMA，S8 直接跑不带 `--dma` 的
    M/A/B 即可；若单独在新烧录的退役板上跑 `j3_fourchains.ps1`，脚本会打印 mode 提示，
    若 M 轮失败按「判据未取得 + 板卡需重烧」处理。

### 仍建议 Lead 决定/后续做


### 三条实证依据速查（2026-10-17 21:0x 口径更正，脚本已按此实现）

1. **为什么 NIC 要用 `ReceivedBytes`（而不是 `ReceivedUnicast`）**
   - 现象：绿位流 engine=1 ping **4/4**；`ReceivedUnicast delta=0`，**`ReceivedBytes delta=+296`**（4×74B）。
   - 机制：静态 ARP ⇒ 板端学不到 PC MAC ⇒ 板自发帧 dst MAC=`ff:ff:ff:ff:ff:ff`（广播）⇒ 不进 Unicast 计数。
   - 依据：`evidence_2026-10-17\green_engine1_ping.log`（4 条 `Reply ... TTL=128`）+ 同机 NIC 读数；
     与 `rdcap2_cmp_retired.log` 的 dst MAC 差异（位置 8-13）互相印证。
   - 脚本：S4 要求 `Bytes ≥74`、S5 要求 `Bytes ≥296`；`ReceivedBroadcastPackets` 仅辅助打印。
2. **为什么 J3 不带 `--dma`（以及为什么退役位流不跑桥模式）**
   - 事实（同一绿位流+ELF、新烧录干净状态）：不带 `--dma` → `green_bridge_j3_run1.log` **PASS**
     （`[M] wr+256 rd+256 inv=32132 miss=0` / `[A] rd+255 miss=[5356]` / `[B] PASS`）；
     带 `--dma` → `green_engine1_j3_dma.log` / `run2.log` / `run3_nowarmup.log` **连续三次 FAIL**，
     首轮均 `[M] wr+255`（写丢 1 帧）→ 读阶段不启动 → 槽满级联。
   - 旁证：`green_fresh_manual_round_256.log`（新烧绿、不发 `'d'`）→ `DONE wr+256 rd+256 stall=0` + `echo=256/256`。
   - 行为：`j3_fourchains.ps1` 逐轮调 `j3_soft_verify.py --rounds M/A/B`（不带 `--dma`）；任一轮失败即停、
     不自动重试；`wr+255`/收帧停摆 ⇒ 判据未取得 + 板卡需重烧。J3 前不发 `'d'`。
   - 为什么退役位流"桥模式"不跑：退役改动只作用于 `HAS_DMA=1` 的桥①
     （`axi4_master_bridge.v:694-704` 一律泊 `R_DRET` 等 DMA shim；`705-717` 的硬件读 FSM 只给
     `HAS_DMA=0` 的桥②）⇒ engine=0 时退役位流**没有读出路径**，跑桥模式必然失败（预期行为、不是回归）。
3. **为什么 J3 前必须清槽（前置：`'S'` + 只读检查 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍）**
   - 现象：带 `--dma` 那几轮首轮 `[M] wr+255`（256 帧只收到 255），读阶段未启动，随后 A/B 全 `wr+0` 连锁。
   - 机制/现场归因：`--dma` 的预序列（'S'/'I'/'d'，含多次翻转）留下 1 个"已写未读"帧占槽，
     写侧少收 1 帧（`green_engine1_j3_dma.log:9`；`[L1]` 归因，`[L3]` 现象）。
   - 做法：前置 `'S'` + 轮询 `'U'` 到 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍（只读、不发 `'d'`）；
     清槽后 `green_dma_predrain_uart.log` 为 `wmwr=4 wmrd=4`、`req=0x01000000`（bit25=0）。



- **新 ELF 给 `'U'` 加桥② 计数器**（`mem2_wm/mem2_rd_frame/mem2_outstanding`、`pump_rev_wr/rd`、
  `link_ok`、`cmd_takeover`）——只重建 ELF、不重建位流，就能把 S6 的"bridge① 之后"再细分成
  `Aurora 环回 / 桥② 读侧 / 泵B / mux/PHY` 四段（审计 §5 H3 建议 4）。
- **四档零回归在静态 ARP 环境下的 UDP 回显归属**需单独确认（板自发帧 dst 广播），别把它当"数据面坏"。
- 若 rdfix 修复生效，建议 S5 再加一轮 ping×4 复跑，排除一次性/状态相关故障。

---

## 6. 运行方式与日志

```powershell
# 1) 默认 dry-run（不碰板；打印完整计划 + 离线 S0 核验）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\retire_s0_s8.ps1 `
    -Bit <archived.bit> -Elf <archived.elf> -BuildLog <build.log>

# 2) 真执行（会烧板/串口/ping）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\retire_s0_s8.ps1 -Run `
    -Bit D:\FPGA\prj\project_11\out\archive\b31b_rdfix_2026-10-17\<rdfix>.bit `
    -Elf D:\FPGA\prj\project_11\out\archive\b31b_rdfix_2026-10-17\<rdfix>.elf `
    -BuildLog <rdfix build log> -GreenBit D:\FPGA\prj\project_11\out\archive\b31b_v5rtl_2026-10-16\aurora_mem_bridge.bit `
    -GreenElf D:\FPGA\prj\project_11\out\archive\b31b_v5rtl_2026-10-16\j3_soft_v5rtl.elf

# 3) 只跑 J3 四链（默认 nslots=256；不带 --dma，逐轮 M/A/B）
#    J3 前置: 'S' + 只读检查 wmwr==wmrd & req.bit25=0 连续两拍（不发 'd'）
#    失败纪律: 任一轮失败即停、不重试；wr+255/收帧停摆 ⇒ 判据未取得 + 板卡需重烧
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_11\out\j3_fourchains.ps1 -Run -Bitstream retired
```

- 日志：`out\evidence_2026-10-17\s0s8_<yyyyMMdd_HHmmss>.log`（UTF-8，含所有原始输出与 `[JUDGE]/[PLAN]/[NOTE]` 行）；
  `j3_fourchains.ps1` 逐轮 tee 到 `j3_m_<ts>.log` / `j3_a_<ts>.log` / `j3_b_<ts>.log`，
  另有 `j3_fourchains_<ts>.log` 汇总控制台行。
- dry-run 保证：**不烧写、不开串口、不发 ping**；只做 SHA256/邻居/NIC/路径等只读检查，并照写日志。
- 两个 `.ps1` 均为 **UTF-8 BOM**（PS 5.1 读无 BOM 中文脚本会假语法错），已用
  `[System.Management.Automation.Language.Parser]::ParseFile` 在 PowerShell 5.1 下验证 0 语法错误。

---

## 7. 附录 A：今天原始日志的解码样例（用于核对脚本解析）

1. `evidence_2026-10-17\clean_engine1_ping_204321.log`（旧退役 `3aa600aa` + ELF `2961b585`；
   'd' 后 engine=1、SEQ、不跑轮次）：
   - U 前 `wmwr=11 wmrd=11`；ping 0/4；U 后 `wmwr=15 wmrd=15` ⇒ **+4/+4（写出+读出都发生）**；
   - `emit=0x00560e55` ⇒ len=86 slot=14 byte0=0x55；NIC delta=0 ⇒ **断点在 bridge① 读出之后**。
2. `evidence_2026-10-17\s2_s6_204148.log`（旧脚本 S2–S6 轮）：
   - S3 `req=0x01010076` ⇒ bit24=1、bit25=0、slot=1、len=0x76=118（S2 那 1 帧）；
   - S6 `req=0x00010076` ⇒ bit24=0；`WM_WR=7`、`WM_RD=2` ⇒ 读出侧零启动 ⇒ **S5 ping 无效**。
3. `evidence_2026-10-17\ilacap_counters_summary.txt`（旧退役 `0ecb8438` + ping×4 ILA）：
   - 桥①：`dbg_mem_wr_frm 19→23`、`dbg_mem_rd_frm 19→23`（第一跳正常）；
   - 桥②：`dbg_mem2_wr_frm 19→23`、`dbg_mem2_ost 19→23`、`dbg_mem2_rd_frm 0→0` ⇒ **桥② 读侧死**；
   - 与 RTL 修复注释 `axi4_master_bridge.v:694-717`（HAS_DMA=0 实例必须保留硬件读引擎）同源。
4. `evidence_2026-10-17\rdcap2_cmp_retired.log`：发射流与绿参考 strict ndiff=14（8-13 dst MAC、
   26-27 IP ID、32-33 cksum、末 4B FCS）；`--mask-volatile` 后仍 6 处（dst MAC）⇒ 掩码必须加 8-13。
5. `evidence_2026-10-17\green_engine1_ping.log`（绿位流 engine=1）：ping **4/4**（4 条
   `Reply ... TTL=128`）；同机 NIC 读数 `ReceivedUnicast delta=0`、**`ReceivedBytes delta=+296`**
   （4×74B ICMP 回包）⇒ **NIC 主判据只能用 `ReceivedBytes`**（用 Unicast 会假 FAIL）。
6. `evidence_2026-10-17\green_bridge_j3_run1.log`（绿位流 + ELF `2961b585`，**不带 `--dma`**、新烧录）：
   **PASS** —— `[M] wr+256 rd+256 inv=32132 miss=0`、`[A] wr+256 rd+255 miss=[5356]`（恰帧#100）、
   `[B] wr+256 rd+256`、`[B2-SOFT-VERIFY] PASS` ⇒ J3 判据的正型。
7. `evidence_2026-10-17\green_engine1_j3_dma.log` / `green_engine1_j3_dma_run2.log` /
   `green_engine1_j3_dma_run3_nowarmup.log`（同配置，**带 `--dma`**）：连续三次 FAIL，
   首轮均 `[M] wr+255`（写阶段丢 1 帧）→ 读阶段不启动 → 槽满 → 后续全 FAIL ⇒ **J3 禁止带 `--dma`**
   （且重试会级联假 FAIL / 可能楔死板卡）。
8. `evidence_2026-10-17\green_fresh_manual_round_256.log`（新烧绿、**不发 `'d'`**）：
   `manual_round.py COM5 256` → `[B2] DONE t=M wr+256 rd+256 stall=0` + `echo=256/256` ⇒ 轮内引擎
   自洽（旁证不带 `--dma` 的 M/B 正型）。
9. `evidence_2026-10-17\green_dma_predrain_uart.log`：前置 `'S'`+回读后 `wmwr=4 wmrd=4`、
   `req=0x01000000`（bit24=1、**bit25=0**）⇒ 槽表干净、可起跑。

## 8. 附录 B：关键行号索引

| 事实 | 证据位置 |
|---|---|
| `'d'` 翻转 / R_ENGINE / R_MODE=SEQ | `sw/src_j3/main.c:436-447` |
| 轮末 `R_ENGINE=0` | `sw/src_j3/main.c:375-379` |
| 轮起 `R_MODE=RND`（不恢复） | `sw/src_j3/main.c:358`（注释 380-381） |
| `NSLOTS=256` / `WAITWR-FAIL` | `sw/src_j3/main.c:68,270-282` |
| 逆序读 / `STALL` | `sw/src_j3/main.c:288-307` |
| `'U'` 探针字段顺序 | `sw/src_j3/main.c:448-472` |
| `req` 布局 {sticky,engine,slot,len} | `rtl/frame_mem_if.v:78,502` |
| `emit` 布局 {len,slot,byte0} | `rtl/frame_mem_if.v:507-524` |
| 桥① 写=栈 TX、读→pack→Aurora TX | `rtl/aurora_mem_bridge.v:754-818,1159-1171` |
| Aurora RX→unpack→桥②→泵B→mux | `rtl/aurora_mem_bridge.v:1176-1206,1223-1226` |
| 退役只作用于 HAS_DMA=1；桥② 保留硬件读引擎 | `rtl/axi4_master_bridge.v:694-717,720-729` |
| RND 下不自动发读 | `rtl/aurora_mem_bridge.v:322-327` |
| 旧脚本 S2/S4 的 `manual_round 1` | `out/retire_s2_s6.ps1:44,48` |
| 旧脚本 S3 直接发 `'d'` | `out/retire_s2_s6.ps1:46` |
| `dbg_emit` 只覆盖第一跳 / 第二跳路径 | `out/evidence_2026-10-17/rtl_audit_204519.md:28-30,155-199`（§4.3 在 `:183-199`） |
| H1（RND+engine=0 导致读侧零启动） | `out/evidence_2026-10-17/rtl_audit_204519.md:220-255` |
| 原始日志解码表 | `out/evidence_2026-10-17/rtl_audit_204519.md:377-388` |
| 四档零回归脚本 | `D:\FPGA\prj\project_10\prj_loop\scripts\udp_verify_ddr.py`（判据尾部 `DDR_VERIFY:`） |
| J3 四链脚本（--nslots 默认 256；`--dma` 禁用） | `scripts/j3_soft_verify.py:543,548-550`（`--dma` 开关见 `:548`） |
| NIC 判据口径（ReceivedBytes） | `evidence_2026-10-17/green_engine1_ping.log`（4/4）+ 21:0x 同机 NIC 读数（Unicast 0 / Bytes +296） |
| J3 不带 --dma 的正型/反型 | `green_bridge_j3_run1.log`（PASS）vs `green_engine1_j3_dma.log`/`run2`/`run3_nowarmup`（FAIL wr+255） |
| J3 前置槽表检查 | `green_dma_predrain_uart.log`（wmwr=wmrd=4、bit25=0）；`green_fresh_manual_round_256.log`（DONE wr+256 rd+256 stall=0） |
| 退役位流桥模式无读出路径 | `rtl/axi4_master_bridge.v:694-717`（HAS_DMA=1 只走 DMA；HAS_DMA=0 保留 HW 读） |

---

## 附：最终口径与实测结果（2026-10-17 21:32 上板复验后定稿）

**1) J3 最终口径 = 带 `--dma`（取代本文 §1.7/§5-10 的"不带 --dma"临时口径）**
- 原因：`j3_soft_verify.py` 的 `run_round()` 在 SEQ 窗无条件发 1 个预热帧；DMA 模式（g_dma_mode=1、R_ENGINE=1）下该帧写入后读请求永泊 R_DRET（此刻无驻留服务），占住 1 槽 ⇒ 写阶段第 256 帧槽满被拒 ⇒ 板端 `WAITWR-FAIL got+255` 级联 FAIL。桥模式由硬件读引擎自动退休故不留残槽。
- 修复：`run_round(..., warm_probe=True)`；`--dma` 时跳过预热帧。复验（绿位流 `708f15a4`+ELF `2961b585`，新烧录）：`[B2-SOFT-VERIFY] PASS`（`green_dma_j3_run5_warmfix.log`）。
- `j3_fourchains.ps1` 与 `retire_s0_s8.ps1` 的 S8b 已统一为 **带 `--dma`**；`wr+255`/收帧停摆一律判「判据未取得 + 需重烧」，不自动重试。

**2) 修复版位流 `c8cd3a32` 的 S0–S8 实测（`s0s8_20261017_213020.log`，`S0S8_RESULT: PASS`）**

| 步 | 结果 |
|---|---|
| S0 | PASS（WNS/WHS +0.004、`V5_SWEEP_OK`、bit `c8cd3a32` / ELF `2961b585`）|
| S1 | PASS（绿 `708f15a4`+`2961b585`：ping 3/3、`'L'` 应答、邻居 Permanent）|
| S2a/S2b | PASS（M 轮 1 帧未完成=非身份判据；**不发 'd' 时 ping 0/1、NIC delta=0 ⇒ 身份=退役版**）|
| S3/S3b | PASS（`req.bit24=1`&mode=1；静默窗 wmwr==wmrd & sticky=0）|
| S4 | PASS（ping 1/1、NIC ReceivedBytes +74、WM_WR+1/WM_RD+1）|
| S5 | PASS（ping 4/4、NIC +296、WM_WR+4/WM_RD+4）|
| S6 | PASS（emit 正确 + 线上 4/4）|
| S7 | ILA 直证：桥② `wr_frm/rd_frm` 777→781/777→781、`ost` 恒 0（旧位流同测 rd 恒 0、ost 只增）|
| S8b | PASS：J3 `--dma` M/A/B 全 PASS（`[M] wr+256 rd+256 inv=30417`；`[A] rd+255 miss=[#100]`；`[B] wr+256 rd+256`）|
| S8c | PASS：发射流 1526B、前导开头、与绿参考掩码后 ndiff=0 |
| S8d | PASS：四档零回归（20/20 · 12/12 · 12/12 · 300/300）|

**3) 四条验收判据在退役位流 `c8cd3a32` 上的取值**：ping/ARP ✓ · 四档逐字节零回归 ✓ · J3/J3′+负向 A/B ✓ · 发射流与桥式（绿参考）逐字节同构 ✓。