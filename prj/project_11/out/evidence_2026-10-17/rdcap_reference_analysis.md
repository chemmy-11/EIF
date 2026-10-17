# 发射字节流取证复刻 · 归档参考解析 + 新工具 + 触发方案评估

> 日期 2026-10-17 · 离线准备单（**未运行** xsct / vivado / 串口 / ping，**未触碰硬件**、未 commit）
> 目标：在**退役位流**上复刻 10-16 的「一整帧发射字节流」取证，与归档的绿流参考逐字节比对。
> 下文所有数字均由 `out\jb31b_rdcap2_cmp.py` 现算，命令随文给出，可原地复跑。

---

## 0. 结论先行

1. **归档参考两条流都是 1526 字节、都以 8B 前导 `55 55 55 55 55 55 55 D5` 开头、都无气泡（1526 个 `mem_rden=1` 采样连续）。**
   注意：`b31b_v5rtl_2026-10-16\` 里的 **e.csv 已经是新口径**（带前导）。任务书里说的「e.csv 是旧口径帧+FCS+8B 垃圾」是 **`b31b_v5probe_2026-10-16\jb31b_rdcap_e.csv`（10-16 13:41）**，两份文件不同，见 §1.5。
2. **bridge 流与 e 流严格逐字节相比差 6 个字节：偏移 27（IPv4 ID 低字节）、33（IPv4 头校验和低字节）、1522–1525（FCS）。**
   这 6 个字节对**任何**两次发射都必然不同（板上协议栈每发一帧把 IPv4 ID +1，校验和与 FCS 随之变），
   掩掉 `IP-ID(26-27) + IP 头校验和(32-33) + 末 4B FCS` 后 **差异 0 ⇒ 逐字节同构**。
   ⇒ **判据必须带 `--mask-volatile`**，否则「退役流 vs 绿参考」每次都会被这 6 个字节判红。
3. 退役位流上「`dbg_mem_rden eq 1'b1` 触发 + 武装后 500 ms 内发目标帧」**仍然成立，但前提是武装前发射侧已空**
   ——退役固件是**驻留服务**模式（`while(!urx_poll()) serve_dma_once()`），武装后只要有任何一帧被读出，触发就落在**那一帧**上。
   建议：武装前 warm+排空并**用 `'I'` 计数器证明 `wr==rd` 且两拍不变**（新 `jb31b_rdcap2_warm.py` 已实现），窗口压到 ≤500 ms，捕获后先查头 8B。
4. 6 个新脚本全部落在 `out\`，`.py` 全部 `py -m py_compile` 通过；`.tcl` 纯 ASCII、无行尾 `#`、括号引号平衡（静态检查 PASS）；`.bat` 纯 ASCII + CRLF。

---

## 1. 归档参考两流解析（任务 1）

### 1.1 复跑命令

```powershell
py D:\FPGA\prj\project_11\out\jb31b_rdcap2_cmp.py `
   D:\FPGA\prj\project_11\out\archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_bridge.csv `
   D:\FPGA\prj\project_11\out\archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv `
   --expect-prefix 55*7+D5 --expect-len 1526 --mask-volatile
# 退出码 0 = 掩码后同构；1 = 有差异；2 = 解析失败
```

（这两份 CSV 与 `out\jb31b_rdcap_bridge.csv` / `out\jb31b_rdcap_e.csv` **逐字节相同**，
SHA256 分别 `CF808E5194779C43…` / `057C66B8DB589837…`，可任取其一。）

### 1.2 两条流的基本量

| 项 | bridge 流 | e 流（engine=1 参考） |
|---|---|---|
| 文件 | `out\archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_bridge.csv` | `out\archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv` |
| CSV 采样行 | 2048 | 2048 |
| `mem_rden=1` 采样 | 1526（连续，run=1526 后接 522 个 0） | 1526（同） |
| **重建字节数** | **1526** | **1526** |
| 解析坏行 | 0 | 0 |
| 8B 前导 `55×7,D5` | **YES** | **YES** |
| 数据列 / 使能列 / 进制 | `mem_rd_data[7:0]` / `dbg_mem_rden` / HEX | 同 |

前 32 字节：

```
bridge: 55 55 55 55 55 55 55 d5 08 3c 03 a0 26 96 00 11 22 33 44 55 08 00 45 00 05 dc 01 5a 40 00 40 11
e     : 55 55 55 55 55 55 55 d5 08 3c 03 a0 26 96 00 11 22 33 44 55 08 00 45 00 05 dc 01 5d 40 00 40 11
```

末 16 字节：

```
bridge: b4 b5 b6 b7 b8 b9 ba bb bc bd be bf 00 b4 b8 03
e     : b4 b5 b6 b7 b8 b9 ba bb bc bd be bf 34 8b 2f 62
```

### 1.3 首差异与差异明细

**首差异位置 = 27（0 基）；严格逐字节差异 6 处：**

| 偏移 | 字段 | bridge | e | 为什么必然不同 |
|---|---|---|---|---|
| 27 | IPv4 ID 低字节 | `5a` | `5d` | 板上协议栈每发一帧自增（`0x015a→0x015d` = 3 帧，正好对上期间 2 帧暖机 + 1 帧目标） |
| 33 | IPv4 头校验和低字节 | `f6` | `f3` | 随 ID 变 |
| 1522–1525 | 以太网 FCS | `00 b4 b8 03` | `34 8b 2f 62` | 随整帧内容变 |

差异上下文（偏移 19–34）：

```
bridge: 55 08 00 45 00 05 dc 01 5a 40 00 40 11 af f6 c0
e     : 55 08 00 45 00 05 dc 01 5d 40 00 40 11 af f3 c0
                    └总长┘ └ID┘ └flags┘ TTL P └csum┘ └src IP...
```

**同构判断：**
* 严格口径：`1526` 中 `6` 字节不同 ⇒ **非同构**（1/254 的字节）；
* 掩掉 `26-27`（IP-ID）、`32-33`（IP 头校验和）、`-4..-1`（FCS）：**差异 0 ⇒ 同构 = YES**。
  `--mask-volatile` 就是这三个区间，**不掩 TTL/协议/长度/端口/payload**。

### 1.4 帧布局（由字节流反解，两条流一致）

| 偏移 | 长度 | 内容 | 实测值 |
|---|---|---|---|
| 0–7 | 8 | 以太网前导 + SFD | `55 55 55 55 55 55 55 D5` |
| 8–13 | 6 | 目的 MAC（PC） | `08 3c 03 a0 26 96` |
| 14–19 | 6 | 源 MAC（板） | `00 11 22 33 44 55` |
| 20–21 | 2 | EtherType | `08 00`（IPv4） |
| 22–41 | 20 | IPv4 头 | `45 00 05 dc 01 5a 40 00 40 11 af f6 c0 a8 01 0a c0 a8 01 66`（总长 1500、DF、TTL 64、UDP、`192.168.1.10`→`192.168.1.102`） |
| 42–49 | 8 | UDP 头 | `04 d2 04 d2 05 c8 00 00`（1234→1234、长度 1480、校验和 0） |
| 50–1521 | 1472 | 自描述载荷 | `00 01 02 …`（`byte[i] = i & 0xFF`，偏移 50+0x55 处确实读到 `55`） |
| 1522–1525 | 4 | FCS | 随帧变 |

⇒ **1526 = 8 前导 + 14 以太 + 20 IP + 8 UDP + 1472 载荷 + 4 FCS**，与 `--expect-len 1526` 一致。
同一份 CSV 里 1526 个使能采样**连续无气泡**，之后 522 个采样为 0 ⇒ 一次触发正好装下一帧，缓冲（2048）里没有第二帧的位置。

### 1.5 「旧口径」到底在哪份文件里（重要澄清）

| 捕获（`jb31b_rdcap_e.csv`） | 时间 | 头 8B | 末 4B | 口径 |
|---|---|---|---|---|
| `b31b_v5probe_2026-10-16\` | 10-16 13:41 | `08 3c 03 a0 26 96 00 11`（帧首，**无前导**） | `ff ff ff ff`（尾部共 8 个 `FF`） | **旧**：`[帧 1518][8B 0xFF 垃圾]` |
| `b31b_v5fix_2026-10-16\` | 10-16 15:33 | `55 55 55 55 55 55 55 d5` | `f6 99 b8 9b`（FCS） | 新：`[8B 前导][帧 1518]` |
| `b31b_v5rtl_2026-10-16\` | 10-16 16:20 | `55 55 55 55 55 55 55 d5` | `34 8b 2f 62`（FCS） | 新 |

证明：`old[0:1518]` 与 `new[8:1526]` 只差 **7 个字节**，位置 `[18,19]`（帧内 IP-ID）、`[24,25]`（帧内 IP 校验和）、`[1514,1515,1517]`（帧内 FCS）
⇒ 旧流 = 新流**去掉 8B 前导 + 尾部补 8B 0xFF**，其余逐字节相同。口径翻转点在 10-16 13:41→15:33 之间（v5 的 SA/LEN–DROP_BYTES 配对修复）。

### 1.6 对本次复刻的判据含义

* 参考 = `b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv`（engine=1、新口径、1526B）；
* 退役流判据 = **1526 字节 + 头 8B `55×7,D5` + 掩掉 IP-ID/IP 校验和/FCS 后逐字节相同**；
* 若退役流出现「无前导」或「尾部多 8B」，那是**真缺陷**，不是口径问题（旧口径的 8B 垃圾已由 v5 修复）。

---

## 2. 新脚本清单与用法（任务 2）

全部新增，未改动任何既有文件。`.tcl` **纯 ASCII、注释一律独立成行**（Vivado 按 GBK 读 tcl；行尾 `#` 非法，坑 #19）。

| 文件（绝对路径） | 一行用法 |
|---|---|
| `D:\FPGA\prj\project_11\out\jb31b_rdcap2.tcl` | `call "%VIVADO%" -mode batch -source jb31b_rdcap2.tcl -notrace`（读 `RDCAP_*` 环境变量） |
| `D:\FPGA\prj\project_11\out\jb31b_rdcap2.bat` | `jb31b_rdcap2.bat`（一键：warm → vivado 抓取 → cmp，`RDCAP_SEND_MODE=retired` 默认） |
| `D:\FPGA\prj\project_11\out\jb31b_rdcap2_send.bat` | 由 tcl 在武装窗口内 `exec`（快路径，**不发 'd'**） |
| `D:\FPGA\prj\project_11\out\jb31b_rdcap2_send.py` | `py ... --mode retired [--send-d]`，发 1472B 自描述帧，打印 `MODE=… echo=… match=…` |
| `D:\FPGA\prj\project_11\out\jb31b_rdcap2_warm.py` | `py ... --send-d --drain 2 --quiet-wait 6`，切 DMA + ping + 暖机 + 排空 + `wr==rd` 静默判据 |
| `D:\FPGA\prj\project_11\out\jb31b_rdcap2_cmp.py` | `py ... A.csv B.csv --expect-prefix 55*7+D5 --expect-len 1526 --mask-volatile` |

### 2.1 `jb31b_rdcap2.tcl` 参数（环境变量）

| 变量 | 默认 | 含义 |
|---|---|---|
| `RDCAP_LTX` | `…\archive\b31b_retire_flag_2026-10-17\probes_0ecb8438.ltx` | 探针文件（与 v5-RTL 的 `probes.ltx` **逐字节相同**，SHA256 `352A5F28…C3A11A2`，均 194528 B） |
| `RDCAP_OUT` | `<脚本目录>\jb31b_rdcap2_capture.csv` | 输出 CSV |
| `RDCAP_SEND_CMD` | `<脚本目录>\jb31b_rdcap2_send.bat` | 武装后 `exec` 的发送器 |
| `RDCAP_TRIG_DATA` | 空 | 可选，如 `55`；把 `mem_rd_data==0x55` AND 进触发（见 §3.4-R5） |
| `RDCAP_PRE_MS` | 500 | 武装→发送的间隔 |
| `RDCAP_WAIT_S` | 60 | `wait_on_hw_ila` 超时 |
| `RDCAP_MODE` | `unlabeled` | 只用于日志标签 |

tcl 会打印：实际设备名、候选 ILA 与其 `mem_rd_data*` 命中数、**最终选中的 ILA 名 + 全部 probe 名/位宽**、
`DATA_DEPTH`、`TRIGGER_POSITION`、触发探针与读回值、`RDCAP2_ARMED`、发送结果、`wait_on_hw_ila` 的 catch 结果、
CSV 路径、**CSV 行数/采样数/第 3 行原文**，最后 `RDCAP2_DONE`。
探针找不到时会先 dump 所有 ILA 的所有 probe 名再报错（避免"探针名口径"猜谜）。

### 2.2 两段式串联（照抄 10-16 的模式）

```
jb31b_rdcap2.bat
  ├─[1] py jb31b_rdcap2_warm.py --send-d …        # 串口 'd'/'U' + ping + 暖机 + 排空 + wr==rd
  ├─[2] vivado.bat -mode batch -source jb31b_rdcap2.tcl
  │        tcl: 武装 → after 500 → exec jb31b_rdcap2_send.bat
  │        bat: 清 PYTHONHOME/PYTHONPATH（Vivado 会污染）→ 全路径 python → send.py --mode …
  │        tcl: wait_on_hw_ila(catch) → upload → write CSV
  └─[3] py jb31b_rdcap2_cmp.py <归档 e.csv> <新 CSV> --expect-prefix 55*7+D5 --expect-len 1526 --mask-volatile
```

* 为什么用 bat 夹一层：Vivado 进程里 `PYTHONHOME` 指向自带 python，直接 `exec python` 会崩；bat 里清空并写全路径解释器（坑 #45：Git Bash 的 `python` 是坏壳）。
* 为什么窗口内不发 `'d'`：`'d'` 是**翻转**语义 + 要发 `'U'` 确认（~1 s），会拉长「武装→目标帧」窗口。

### 2.3 完整手工顺序（推荐按这个跑）

```powershell
# 0) 前提（人工）：烧退役位流 + 下 ELF，串口出现 "[B2-SOFT] WAITCMD (M/A/B/S/I/L/D/E/U)"；
#    JTAG 插好、hw_server 可连。注意 ltx 用 probes_0ecb8438.ltx（与 v5-RTL 的完全相同）。
# 1) 上电后先切 DMA 引擎并验证（'d' 是翻转，脚本用 'U' 读回兜底，幂等）
py D:\FPGA\prj\project_11\out\jb31b_rdcap2_warm.py --send-d --require-dma
#    期望：D_MODE=dma ；结尾 WARM_QUIET=YES wr=… rd=…
# 2) 武装 + 窗口内发帧 + 抓 CSV（一条命令）
D:\FPGA\prj\project_11\out\jb31b_rdcap2.bat
#    产物：out\evidence_2026-10-17\rdcap2_retired.csv
#          out\evidence_2026-10-17\rdcap2_send_<mode>_<ts>.log（回显前 32B hexdump）
#          out\evidence_2026-10-17\rdcap2_retired_vivado.log（tcl 的 RDCAP2_* 全部打印）
#          out\evidence_2026-10-17\rdcap2_cmp_retired.log
# 3) 若第 1 步已做过，第 2 步的 warm 会再发一次 'U'（只是读状态，不会翻转）
```

`jb31b_rdcap2_send.py` 的关键输出（可直接 grep）：

```
MODE=retired echo=1 match=YES
ECHO_LEN=1472 ECHO_HEAD32=00 01 02 03 …
D_MODE=dma              # 只有带 --send-d 时出现
EVIDENCE=D:\FPGA\prj\project_11\out\evidence_2026-10-17\rdcap2_send_retired_<ts>.log
```

`jb31b_rdcap2_cmp.py` 退出码：**0** 同构 / **1** 有差异 / **2** 解析失败（可直接当 `if` 判据）。
除长度与首差异外，还会打印一条 `SIG:` 帧签名（目的/源 MAC、EtherType、IP 协议），
抓错帧时一眼能看出来（例如 `ethertype=ARP NOT_THE_TARGET` 或 `dst=ff:ff:ff:ff:ff:ff BCAST`）。

---

## 3. 触发方案评估（任务 3）

### 3.1 仪器事实

* `u_ila_0`，`C_DATA_DEPTH 2048`，`probe1 = {dbg_mem_rden, mem_rd_data[7:0]}`（9 位，`scripts\build_debug.tcl:139-148`）。
* `dbg_mem_rden = mem_rd_en`（`rtl\aurora_mem_bridge.v:1310`），即 `frame_mem_if` 读口 → `u_pack` 的**逐字节发射使能**（`:1157-1162`）。
  两种读引擎（桥硬件 / DMA+shim）都从同一个读口出字节，所以这条探针**与引擎无关**。
* 10-16 归档实测：`en=1` 是**连续 1526 拍**（一帧），之后 522 拍为 0 ⇒ 触发落在**第一个发射字节**、每次抓取正好一帧。
* 触发是**电平比较**（`TRIGGER_COMPARE_VALUE eq1'b1`），不是边沿；触发位置 0 ⇒ 抓到的第 0 个采样就是第一个 `en=1` 字节。

### 3.2 warm → arm → send 为什么能保证「武装后第一次发射就是目标帧」

1. **读请求产生的规则**（`rtl\aurora_mem_bridge.v:322-326`）：
   * `SEQ`（`cfg_mode_eff=0`）：`mem_rd_req <= (outstanding != 0) && !rd_busy && !mem_rd_req`
     —— **只要内存里还有没读完的帧，就立刻再发一笔读请求**（自持重装）；
   * `RND`（`cfg_mode_eff=1`）：只由 `cmd_rd_req_pulse | lite_rd_req_pulse` 单拍触发（显式命令才读）。
2. `warm` 在**武装之前**把 ping（ARP/ICMP 应答）和 2 帧暖机全部发完，并排空回显 —— 于是武装那一刻 `outstanding == 0`，
   `mem_rd_req` 不会再自装，`dbg_mem_rden` 恒 0，触发处于「等第一个 1」的状态。
3. 武装后 500 ms 内发目标帧 ⇒ 该帧落槽 → `outstanding != 0` → 首笔读请求 → 第一个 `en=1` 采样即**前导第 1 字节 0x55** → 触发。
4. 因为 1526 拍一帧不中断、缓冲 2048，触发后不会混入第二帧。

### 3.3 退役位流的额外风险：会不会抓住「别的帧」？—— **会，而且是这套方案唯一的真实风险**

退役位流的固件是**驻留服务**模式（`sw\src_j3\main.c:407-414`）：

```c
for (;;) {
    while (!urx_poll()) { if (g_dma_mode) serve_dma_once(); }   /* 空闲即服务桥 FSM 的 {slot,len} 读请求 */
```

`'d'` 把 `g_dma_mode=1`、`R_ENGINE=1`，并且**顺带把 `R_MODE` 设成 `MODE_SEQ`**（`:436-447`）⇒ 回到 §3.2 的 SEQ 自装规则。
于是**武装之后**只要有任何一帧被写进槽（被谁写进来都算），软核就会把它读出去发射，触发随即落在那一帧上。
具体有四条路径会让「第一帧」不是目标帧：

| # | 路径 | 现象（CSV 头会是什么） |
|---|---|---|
| a | 暖机帧还没读完（排空窗口不够长 / DMA 服务慢） | 抓到暖机帧的**中段**（头部不是 `55 55 … D5`，或前 8B 是帧内的某处） |
| b | PC 的 ARP 表过期，板子在回显前先发 **ARP 请求** | 头 8B 仍是前导，但目的 MAC = `ff:ff:ff:ff:ff:ff`、EtherType = `0806` |
| c | 武装→发送窗口里来了任何**别的入向帧**（广播/其它主机/交换机泛洪） | 前导 + 别的帧；`SIG:` 行会指认 |
| d | 软核把 `'d'`/`'U'` 的回显处理与帧服务交错（窗口内做串口往返） | 窗口被拉长 → 命中 b/c 的概率上升 |

**结论：驻留服务本身不会凭空产生发射**（`serve_dma_once` 先读 `+0x34`，无 sticky 就返回，无副作用），
**但它是"任何入向帧都会被立刻发射"的放大器**——在 SEQ 模式下，武装后板子不再"静默等命令"，而是"来一帧发一帧"。
所以顺序必须是 **先 warm/排空并证明空，再武装，再（≤500 ms 内）发目标帧**，而不是"先武装再慢慢准备"。

### 3.4 建议（按优先级；前 3 条已写进脚本）

* **R1（已实现）武装前用软核自己的计数器证明发射侧已空**：发 `'I'` 读回 `wr/rd/drop`，
  要求 `wr == rd` 且连续两拍**都不变**才算 `WARM_QUIET=YES`（`jb31b_rdcap2_warm.py`）。
  比"睡 2 秒"可靠：`wr==rd` 是「写进槽的帧都已读出」的充分观测，而 SEQ 自装规则意味着 `outstanding==0` ⇒ 不会自发发射。
* **R2（已实现）窗口 ≤500 ms，且窗口内零 ARP/ICMP/串口往返**：`RDCAP_PRE_MS=500`，发送 bat 里**不发 `'d'`**；
  ping 只在 warm 阶段发一次（保证板子已学到 PC 的 MAC，避免 §3.3-b）。若网络里有其它主机，考虑把 `RDCAP_PRE_MS` 压到 200。
* **R3（已实现）`'d'` 放在武装之前，且必须验证**：`'d'` 是翻转；`jb31b_rdcap2_warm.py --send-d` 用 `'U'` 回读 `mode=` 判定，
  只有读到 0 才补一次 `'d'`（幂等）。外层 bat 带 `--require-dma`：只要引擎**没有**被确认为 DMA（读到 `mode=0`，
  或 `'U'` 完全无应答）就退出码 3，`jb31b_rdcap2.bat` **在武装前中止**（避免白抓）。
  绿位流上用旧 ELF（没有 `'U'` 命令）时去掉 `--require-dma` 即可，脚本会打 `WARM_D_NOTE` 并继续。
* **R4（已实现）捕获后先查头部再认账**：`cmp --expect-prefix 55*7+D5 --expect-len 1526`；
  头不对 ⇒ 直接判「抓错帧/抓断帧」，重抓，不要拿去和参考比对。
* **R5（可选，默认关闭）`RDCAP_TRIG_DATA=55` 把 `mem_rd_data==0x55` AND 进触发**：
  好处：即使有排队帧，也只在**某个前导字节**上触发，头对齐有保证；
  **坏处（重要）**：这条判据对"发射流没有前导"这个正是要测的缺陷**是盲的**——若真无前导，触发会一直等到载荷里出现 `0x55`（偏移 50+0x55=135）或干脆不触发。
  ⇒ **主判据仍用 `en eq 1`（缺陷无关）**，`TRIG_DATA` 只作为"怀疑队列没排空"时的对照实验（两次抓取对照，一次 en-only、一次 55 限定）。
* **R6（若要彻底消除路径 a/b/c）换 RND + 单次显式读**：把 `R_MODE` 切到 `MODE_RND`（`+0x00` 写 1），
  此时 `mem_rd_req` 只由单拍命令触发（`:325`）。于是可以「武装 → 发目标帧（只写槽、不发射，`dbg_mem_rden` 保持 0）→ 再发一次单槽读命令」，
  目标帧的发射时刻由命令决定，窗口内任何杂帧都**只写不读**、不会抢触发。
  **但离线无法验证**：现固件没有"读单槽"的独立命令（`'M'/'A'/'B'` 是整轮 256 槽的序列，`round_command` 会先写 `R_SLOT=255` 起跑），
  UDP 命令通道的 `READ_SLOT` 是否还能在退役位流上生效也需板上确认（owner 是"最近写者胜"）。⇒ 作为**备选方案**，不建议首轮就用。

### 3.5 一句话回答

> 退役位流是**驻留服务 + SEQ 自装**，"武装后先抓到别的帧"确实可能：**只要武装时还有未读完的帧，或窗口内来任何一帧**。
> 用「warm 排空 + `wr==rd` 证明空 → 武装 → ≤500 ms 内发目标帧 → 捕获后验头 8B」这条链，能把该风险压到"仅剩外部杂帧"，
> 并且失败时**可识别、可重抓**（`cmp` 会直接报头不对/`SIG:` 是 ARP）。

---

## 4. 自查结果（任务 4）

| 检查 | 结果 |
|---|---|
| `py -m py_compile jb31b_rdcap2_cmp.py / send.py / warm.py` | **全部退出码 0** |
| `jb31b_rdcap2.tcl` 纯 ASCII（Vivado 按 GBK 读） | **PASS**（0 个非 ASCII 字节，183 行） |
| `jb31b_rdcap2.tcl` 引号/花括号/方括号闭合、**行尾 `#` 注释** | **PASS**（brace/bracket 深度均 0、无未闭合引号、行尾注释 0 处） |
| `.bat` 纯 ASCII + CRLF（cmd 读批处理的真实读法） | **PASS**（两个 bat 均 0 非 ASCII、全 CRLF） |
| `cmp` 退出码语义 | 实测：掩码后同构 → **0**；严格差异 → **1**；文件缺失/解析失败 → **2** |
| `send.py` 报文/匹配/落盘逻辑 | 本机回环自测（127.0.0.1 UDP echo，**不碰硬件**）：`echo=1 match=YES`，证据文件字段完整 |
| `warm.py` 帧路径/参数 | 本机回环自测：`WARM_FRAMES_SENT=2 WARM_ECHO=2`，`--no-uart` 时 `WARM_QUIET=UNKNOWN`、退出码 0 |
| `'d'` 幂等切换逻辑（假串口单测） | 已是 DMA → 不发 `'d'`；读到 `mode=0` → 发 1 次 `'d'` 后确认 DMA；`'U'` 无应答 → `state=None`（只发 1 次 `'d'`）；始终 bridge → 发满 3 次后仍报 `0`（warm 退出码 3 ⇒ 武装前中止） |

未做（明确不做）：未执行任何 Vivado/tclsh/xsct 命令、未开串口、未 ping、未烧板、未 commit。

---

## 5. 需要你在硬件上确认的点

1. **退役位流是否真的"必须先 `'d'`"**：上电后先跑 `py jb31b_rdcap2_warm.py --send-d --require-dma`，看 `D_MODE=dma`；
   若退出码 3 且读到 `mode=unknown`，说明 `'U'` 命令不在该 ELF 里（`j3_soft_n7_2961b585.elf` 应按 `sw\src_j3\main.c` 编入 `U`）——
   此时改用"只看 `'d'` 的回显行 `DMAMODE now=DMA`"判据，或去掉 `--require-dma` 继续（但要自己确认引擎）。
2. **退役流的发射流是否仍是 1526B + 8B 前导**（预测：是，因为 v5 之后 SA/LEN 与 DROP_BYTES 已配对；若否，`cmp` 会直接给出长度与首差异）。
3. **`wait_on_hw_ila -timeout` 在 2023.1 是否被接受**：tcl 里是 `catch` 包裹；若报错只打印 `RDCAP2_WAIT_NOTE` 并继续 upload。
   若日志里出现该 NOTE 且 CSV 异常，请回贴 `rdcap2_*_vivado.log`。
4. **`exec <bat>` 在本机 Vivado 批处理里是否照旧可用**（10-16 实证可用；本脚本沿用同一写法）。
5. **探针对象名**：tcl 先打印 `RDCAP2_PROBE:` 全表。若发现 probe 名是 `probe0/probe1` 而不是网络名，`mem_rd_data*` / `dbg_mem_rden` 的匹配会失败并 dump 全表 —— 届时按 dump 出来的真名改两处 `string match` 即可（本机无 Vivado 可验，不能提前钉死）。
6. **COM 口号 / 板卡 IP**：脚本默认 `COM5`、`192.168.1.102→192.168.1.10:1234`（与 10-16、`out\uart_probe.py` 一致）；变了就加 `--com/--src-ip/--dst-ip`。
7. **首轮建议先抓一次"绿位流对照"**（可选）：用同一套脚本在绿位流上抓 `--mode green`，确认新链路能复现归档的 1526B/前导，
   再去抓退役流 —— 这样任何异常都能二分到"工具链"还是"退役位流"。

---

## 附：本次生成的产物清单

| 路径 | 作用 |
|---|---|
| `out\jb31b_rdcap2.tcl` | Vivado batch 抓取（参数化 ltx/输出/触发数据，打印 ILA+probe+触发+行数，`RDCAP2_DONE` 收尾） |
| `out\jb31b_rdcap2.bat` | 一键编排：warm → vivado → cmp（ASCII/CRLF） |
| `out\jb31b_rdcap2_send.bat` | 武装窗口内的发送器（tcl 通过 `exec` 调用） |
| `out\jb31b_rdcap2_send.py` | 发 1472B 自描述帧 + 可选幂等 `'d'` + 回显判定 + 证据落盘 |
| `out\jb31b_rdcap2_warm.py` | 武装前 warm/排空/`wr==rd` 静默判据 + 幂等切 DMA |
| `out\jb31b_rdcap2_cmp.py` | CSV→字节流、双流比对、掩码、退出码 0/1/2 |
| `out\evidence_2026-10-17\rdcap_reference_analysis.md` | 本文件 |
