---
title: prj13 P2 地址与静态 ARP 方案 v0.2（双板 / 双端 PC）
version: v0.2
date: 2026-11-08
scope: P0-2 交付物；纯离线（未上板、未启 Vivado）
related:
  - D:\GSnFPipe-FPGA-PP\docs\protocol_v1.md §2.2/2.3/2.4/2.5（地址与转发契约）
  - C:\Users\15266\Desktop\毕设\操作文档\prj13_P2开工手册_2026-11-08.md §3 P0-2、§5、§8
  - D:\FPGA\prj\project_13\pc\README.md（脚本用法）、pc\static_arp.ps1、pc\twin_send.py、pc\twin_recv.py
  - D:\FPGA\prj\project_13\out\evidence_2026-11-08_p0_addr\（dry-run 全文证据 + SHA256SUMS）
---

# 0. 一页速览

| 项 | 结论 | 依据 |
|---|---|---|
| 双端 PC 地址 | **PC1 / PC2 必须不同 IP**（旧「两端同为 `.102`」口径作废） | 开工手册 §3 P0-2 第 54 行；protocol_v1.md:105（同子网但不同地址） |
| 两块板地址 | 板 A / 板 B **不同 IP + 不同 MAC**（旧「两板同为 `.10` / `00:11:22:33:44:55`」口径作废） | 开工手册 §3 P0-2 第 54 行；protocol_v1.md:59-60、:66-67 |
| 回声帧 dst=广播 | **作废**；P2 要求单播 dst=本端 PC MAC | 开工手册 §5 第 101 行（旧口径）；protocol_v1.md:124（新口径 `dst=PC2_MAC`） |
| 静态 ARP | 仍然**必须**（P2 默认 `PROXY_ARP_EN=0`），每端绑 **2 条**表项 | protocol_v1.md:76-83、:72 |
| P1 跨板 ping | **预期不通**（P1 是「终止 + 回显」语义，应答跨光去了对端板） | 见 §5；现象证据：prj12 `pc/README.md:18-20`（P1 实测） |
| P2 跨板 ping | **才通**（`dst=PEER_IP` → RELAY，IP 包逐字节不变） | protocol_v1.md:118、:133-139 |
| 地址方案（`.50.x` vs `10.10.0.x`） | **未裁决**，两套并列在 §6；脚本用 `-Scheme/--scheme` 兼容两套 | 本文件 §6（**需项目负责人裁决**） |
| 脚本 dry-run（无板/无网卡） | 22 步全 PASS（含 5 步「应 FAIL 就 FAIL」反向判据） | `out/evidence_2026-11-08_p0_addr/`（`run_evidence.ps1` + `e_*.txt` + `SHA256SUMS.txt`） |

# 1. 地址表（完整）

## 1.1 两套候选方案（并列，未裁决）

| 节点 | `protocol`（protocol_v1.md §2.2，**脚本默认**） | `handbook`（开工手册 §8 建议） | MAC（两套共用） |
|---|---|---|---|
| PC1（板 A 侧） | `192.168.50.1/24` | `10.10.0.1/24` | `08-3C-03-A0-26-96`（`以太网`，现场 `Get-NetAdapter` 读取） |
| PC2（板 B 侧） | `192.168.50.2/24` | `10.10.0.2/24` | `A8-2B-DD-76-DF-A2`（现场读取） |
| 板 A（本地管理） | `192.168.50.11/24` | `10.10.0.11/24` | `02:00:00:00:0A:01` |
| 板 B（本地管理） | `192.168.50.12/24` | `10.10.0.12/24` | `02:00:00:00:0B:01` |

- `protocol` 的 IP/MAC 逐字取自 `protocol_v1.md:57-60`（节点表）与 `:66-67`（`BOARD_IP`/`BOARD_MAC`）。
- `handbook` 只给了 IP（`prj13_P2开工手册_2026-11-08.md:128`：「PC1 `10.10.0.1` / PC2 `10.10.0.2` / 板卡管理 `10.10.0.11/.12`」），
  **MAC 沿用 protocol_v1 的板卡 MAC**（MAC 属于板卡身份，不是网段属性）。这条是**推断，需裁决时一并确认**。
- PC 网卡 MAC 来自现场：`08-3C-03-A0-26-96` 见开工手册 §2 第 39 行（与 `prj12/out/twin_config.json:24` 一致）；
  PC2 的 `A8-2B-DD-76-DF-A2` 见 §2 第 40 行。**PC MAC 由现场读取，不写进 RTL 默认值以外的任何固定假设**。

## 1.2 当前位流的实际值（P1，**与上面两套都不同**）

| 参数 | 值 | 证据 |
|---|---|---|
| `BOARD_MAC` | `00:11:22:33:44:55` | `rtl/aurora_mem_bridge.v:98` |
| `BOARD_IP` | `192.168.1.10` | `rtl/aurora_mem_bridge.v:99` |
| `DES_MAC` | `ff:ff:ff:ff:ff:ff`（广播） | `rtl/aurora_mem_bridge.v:100` |
| `DES_IP` | `192.168.1.102`（PC 侧） | `rtl/aurora_mem_bridge.v:101` |
| PC1 / PC2 | 都是 `192.168.1.102` | 开工手册 §2 第 39-40 行；`prj12/out/twin_config.json:21-24`、`:36` |

**脚本里对应 `-Scheme p1` / `--scheme p1`**：只用于打**当前位流**，用来保住 P1 回归能力（`p1_selfcheck` 等）。
换了 P2 位流必须停用 p1，否则地址全错 —— 这是最容易踩的一条。

## 1.3 板卡参数表（`BOARD_IP`/`PEER_IP`/`BOARD_MAC`/`PEER_MAC`/`PC_IP`/`PC_MAC`）

定义先对齐（protocol_v1.md:66-70 + :76-83）：

| 参数 | 含义 | 谁用 |
|---|---|---|
| `BOARD_IP` | **本板**管理 IP。IPv4 `dst==BOARD_IP` → 交本地栈（ping/管理），不转发 | 本板 `local_steer` |
| `BOARD_MAC` | **本板** MAC。只收 `dst==BOARD_MAC` 的帧（非混杂）；转发时作 `src` | 本板 RX 过滤 / TX 重封装 |
| `PEER_IP` | **对端 PC** 的 IP（不是对端板的 IP）。`dst==PEER_IP` → RELAY | 本板 `local_steer`（**防环红线**，protocol_v1.md:139） |
| `PEER_MAC` | **对端 PC** 的 MAC。本板把放行帧重封装成 `dst=PEER_MAC` 时用 | 本板 TX 重封装（`eth_rewrap`） |
| `PC_IP` | **本端 PC**（直连本板的那台）的 IP，用于 ARP/本地栈判断与文档对齐 | 本板 ARP/本地栈 |
| `PC_MAC` | **本端 PC** 的 MAC，本板发往本端 PC 时的 `dst` | 本板本地栈 TX |

> ⚠ 术语陷阱：`PEER_IP` 是「对端 **PC** 的 IP」，不是「对端板的管理 IP」。板 B 的管理 IP `.12` **永远不该**出现在板的转发判据里。

| 参数 | 板 A（`protocol`） | 板 B（`protocol`） | 板 A（`handbook`） | 板 B（`handbook`） |
|---|---|---|---|---|
| `BOARD_IP` | `192.168.50.11` | `192.168.50.12` | `10.10.0.11` | `10.10.0.12` |
| `BOARD_MAC` | `02:00:00:00:0A:01` | `02:00:00:00:0B:01` | 同左 | 同左 |
| `PEER_IP` | `192.168.50.2`（PC2） | `192.168.50.1`（PC1） | `10.10.0.2`（PC2） | `10.10.0.1`（PC1） |
| `PEER_MAC` | PC2 网卡 MAC | PC1 网卡 MAC | 同左 | 同左 |
| `PC_IP` | `192.168.50.1`（PC1） | `192.168.50.2`（PC2） | `10.10.0.1` | `10.10.0.2` |
| `PC_MAC` | `08-3C-03-A0-26-96` | `A8-2B-DD-76-DF-A2` | 同左 | 同左 |
| `RELAY_EN` | 1 | 1 | 1 | 1 |
| `PROXY_ARP_EN` | 0（v0.2 先静态 ARP） | 0 | 0 | 0 |

（`RELAY_EN`/`PROXY_ARP_EN` 的取值来自 `protocol_v1.md:71-72`。MAC 用 `02:` 开头的本地管理地址：
`02:...` 的 U1 位 = 1 = locally administered，不会被当成厂商 OUI，P2 两板必须**不同 MAC**才能让两端 PC 分别对上板。）

# 2. 新口径：明确作废的三条旧口径

| # | 旧口径（P1 实测形态） | 出处 | 新口径（v0.2） | 为什么必须换 |
|---|---|---|---|---|
| 1 | 两端 PC 同为 `192.168.1.102` | 开工手册 §2 第 39-40 行（「PC2 也是 `.102`（M2 前必须改）」） | PC1 `192.168.50.1` / PC2 `192.168.50.2`（或 `10.10.0.1/.2`） | 同 IP 时 `dst==PEER_IP` 与本机 IP 重合，转发判据无法区分「发给对端」与「发给本机」，M2 跨板业务直接冲突（开工手册 §3 第 54 行） |
| 2 | 两块板同为 `192.168.1.10` / MAC `00:11:22:33:44:55` | `rtl/aurora_mem_bridge.v:98-99`（同一份位流烧两块板） | 板 A `.11` / `02:00:00:00:0A:01`；板 B `.12` / `02:00:00:00:0B:01` | 两块板同 MAC 时 PC 无法区分「回包来自本板还是对端板」；P2 重封装要写 `src=BOARD_MAC`，两端必须是两个不同值（protocol_v1.md:124「`src=BOARD_B_MAC`」） |
| 3 | 回声帧 `eth.dst = ff:ff:ff:ff:ff:ff`（板卡 ARP 表空 → 退化成广播） | 开工手册 §5 第 101 行；2026-11-06 实测 | P2 转发帧 `dst = PEER_MAC`（单播）；本地栈帧 `dst = PC_MAC` | 广播会让同链路上所有设备都收到并上送协议栈；`twin_recv.py` 的 `--no-bcast` 现在会把广播目的直接判 FAIL |

**P1 的广播回声是 P1 的必然产物，不是 bug**：`DES_MAC=ff:ff:ff:ff:ff:ff`（`rtl/aurora_mem_bridge.v:100`）
+ 板卡 ARP 表里没有对端 PC 的 IP，所以只能广播。P2 之所以能写单播，是因为 PC 侧静态 ARP
把「对端 PC IP → 本板 MAC」钉死，板卡才知道该把帧交给哪一个 MAC（protocol_v1.md:76-81）。

# 3. 静态 ARP（两边各一套，可直接照抄）

## 3.1 为什么必须（不是可选）

P1 实测机制：板卡侧 ARP/ICMP/UDP 的应答字节都汇到 `eth_ctrl` 的 `gmii_txd`
（协议选择器：`rtl/eth_ctrl.v:159-180`），该输出即 `stack_txd`
（`rtl/aurora_mem_bridge.v:676-677`），再进「帧泵 A」写入 Aurora
（`rtl/aurora_mem_bridge.v:825-838`）。也就是说 **连 ARP 应答都会跨光到对端板**，
发起方 PC 永远等不到应答 → Windows 邻居解析失败 → `sendto()` 在 OS 层就报错。
把表项钉成 `Permanent` 后，发送侧完全不依赖 ARP 应答，变量减少到一个。

P2 数据面仍是「PC 静态 ARP」主方案，`PROXY_ARP_EN=0`（protocol_v1.md:72、:83），
所以 **P2 依然必须绑**；代理 ARP 只是可选增量。

> 行号勘误：`prj12/pc/README.md:18-19` 引的是 `rtl/eth_ctrl.v:163-177` 与 `rtl/aurora_mem_bridge.v:657`/`:808`。
> 本次逐行核对：`eth_ctrl.v:163-177` 落在协议选择器内部（可接受的近似），但
> `aurora_mem_bridge.v:657` 其实是 `icmp_tx_done` 端口、`:808` 是 `cfg_wr_go` 端口，**与「进泵A」无关**。
> 本文改用核对后的行号：`eth_ctrl.v:159-180`（协议选择器）→ `aurora_mem_bridge.v:676-677`（`stack_txd`/`stack_tx_en`）→
> `:825-838`（`frame_fifo_pump u_pump_fwd` 写侧）。结论不变（应答确实跨光），但引用更准。

## 3.2 脚本（推荐）

```powershell
# PC1（板 A 侧）：演练 -> 真绑
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -IfAlias "以太网"
# PC2（板 B 侧）
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair B -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair B -Apply -IfAlias "<PC2 网卡 Name>"
# 另一套地址方案：加 -Scheme handbook（默认 protocol）
# 当前 P1 位流：加 -Scheme p1
# 解除 / 只查看
#   ... -Apply -Remove
#   ... -List
```

`-BoardPcPair` 只决定「本端是谁」，`-Scheme` 决定「用哪张地址表」，两者正交。也可以完全手工给参数：

```powershell
... -LocalIp 192.168.50.1 -PeerIp 192.168.50.2 -BoardIp 192.168.50.11 `
    -BoardMac 02:00:00:00:0A:01 -PeerMac 02:00:00:00:0B:01 -IfAlias "以太网" -DryRun
```

## 3.3 手工等价命令（不想用脚本时，逐字可抄）

`protocol` 方案 —— **PC1**：

```powershell
netsh interface ipv4 delete neighbors "以太网" 192.168.50.11
netsh interface ipv4 add    neighbors "以太网" 192.168.50.11 02-00-00-00-0a-01
netsh interface ipv4 delete neighbors "以太网" 192.168.50.2
netsh interface ipv4 add    neighbors "以太网" 192.168.50.2  02-00-00-00-0a-01
```

`protocol` 方案 —— **PC2**：

```powershell
netsh interface ipv4 delete neighbors "<PC2 网卡>" 192.168.50.12
netsh interface ipv4 add    neighbors "<PC2 网卡>" 192.168.50.12 02-00-00-00-0b-01
netsh interface ipv4 delete neighbors "<PC2 网卡>" 192.168.50.1
netsh interface ipv4 add    neighbors "<PC2 网卡>" 192.168.50.1  02-00-00-00-0b-01
```

`handbook` 方案只需把 IP 换成 `10.10.0.11/.12`（板）与 `10.10.0.1/.2`（对端 PC），MAC 不变。
`p1` 方案（当前位流）：删/加 `192.168.1.10 00-11-22-33-44-55`（对端 PC 表项跳过，两 PC 同 `.102`）。

## 3.4 校验

```powershell
Get-NetNeighbor -IPAddress 192.168.50.11 | Format-Table InterfaceAlias,IPAddress,LinkLayerAddress,State
# 期望：LinkLayerAddress = 02-00-00-00-0A-01，State = Permanent
arp -a | Select-String "192.168.50"      # 交叉核对
```

本机现存 P1 表项实测（`static_arp.ps1 -Scheme p1 -DryRun` 的 `current` 行）：
`192.168.1.10  ->  00-11-22-33-44-55 state=Permanent` —— 说明脚本读的正是真表，
证据 `out/evidence_2026-11-08_p0_addr/e_static_arp_A_p1.txt`。

## 3.5 每条表项为什么是「→ 本板 MAC」

| 表项 | PC1 | PC2 | 作用 |
|---|---|---|---|
| 本板管理 IP → 本板 MAC | `192.168.50.11 → 02-00-00-00-0a-01` | `192.168.50.12 → 02-00-00-00-0b-01` | ping/管理本板不需要 ARP 应答 |
| 对端 PC IP → 本板 MAC | `192.168.50.2 → 02-00-00-00-0a-01` | `192.168.50.1 → 02-00-00-00-0b-01` | **P2 转发命脉**：去往对端 PC 的帧必须以本板 MAC 为目的，本板才收；板卡只收 `dst==BOARD_MAC`（protocol_v1.md:116） |

两条表项指向同一个 MAC 是**正常的代理 ARP 形态**（protocol_v1.md:81 原文）。

# 4. 上线前后必须一起改的东西（非本任务写权范围）

| # | 项 | 现状 | P2 要求 | 归属 |
|---|---|---|---|---|
| 1 | RTL `BOARD_MAC`/`BOARD_IP`/`DES_MAC`/`DES_IP` | `00:11:22:33:44:55` / `192.168.1.10` / `ff:..` / `192.168.1.102`（`rtl/aurora_mem_bridge.v:98-101`） | 两板各自 `BOARD_MAC`/`BOARD_IP`，`PEER_IP`/`PEER_MAC` 由参数化传入 | P0-1 RTL（本任务不改 `rtl/`） |
| 2 | 本地栈应答不再进泵 A | 现在 `eth_ctrl.gmii_txd → stack_txd → u_pump_fwd`（`aurora_mem_bridge.v:676-677`、`:825-838`） | `dst==BOARD_IP` 的应答必须**直接出本板 GE2**，不能跨光 | P0-1 RTL（见 §5.3 风险） |
| 3 | 板卡管理 IP 是否需要独立网段 | 与业务同网段 | 开工手册 §8 提到「或保留 `192.168.1.10` 管理、业务另开网段」 | **待裁决** |

# 5. P1 跨板 ping 预期不通、P2 才通

## 5.1 结论表

| 源 → 目的 | P1（当前位流） | P2（v0.2 契约） | 原因 |
|---|---|---|---|
| PC1 `ping` 板 A `BOARD_IP` | **不通** | **通**（本地栈） | P1：echo reply 汇入 `stack_txd` → 泵 A → 跨光到板 B；PC1 收不到。P2：`dst==BOARD_IP → LOCAL`（protocol_v1.md:133） |
| PC1 `ping` PC2 `PEER_IP` | **不通** | **通** | P1：`DES_IP` 是「回显目的」而非转发；且应答跨光（`aurora_mem_bridge.v:101`）。P2：`dst==PEER_IP → RELAY`，B 侧重封装 `dst=PC2_MAC`（protocol_v1.md:118、:124） |
| PC2 `ping` PC1 `PEER_IP` | **不通** | **通** | 对称 |
| PC1 `ping` 板 B 管理 IP | 不通 | **不通（预期 DROP，计数）** | 只转发 `PEER_IP` 是防环红线（protocol_v1.md:139）：「非本板 IP 都转发」会 A→B→A 乒乓成环 |
| 任意 PC `ping` `8.8.8.8` | 不通 | 不通（DROP 计数） | 同上；`dst` 不属于 `{BOARD_IP, PEER_IP}` |

## 5.2 为什么 P1 必然不通（机制链，逐行可查）

1. 板卡只回显/应答，**不转发**：P1 的 `DES_IP = 192.168.1.102`（`rtl/aurora_mem_bridge.v:101`）
   是「回声帧的 IP 目的」，不是「转发目标」。P1 语义 = 任一方向收到的帧被 `frame_mem_if` 收进内存，
   再由另一块板放出 —— 也就是「终止 + 回显」。
2. 应答字节的去向：`eth_ctrl` 的 `protocol_sw` 把 ARP/UDP/ICMP 的 TX 字节复用到 `gmii_txd`
   （`rtl/eth_ctrl.v:159-180`），该线即 `stack_txd`（`rtl/aurora_mem_bridge.v:676-677`），
   进泵 A（`rtl/aurora_mem_bridge.v:825-838`）→ Aurora → 对端板 → 对端 PC 的网口。
3. 因此：**发起方 PC 拿不到 ARP 应答，也拿不到 ICMP echo reply**。
   `sendto()` 会在 OS 层就失败；`ping` 一定超时。

证据等级（AGENTS §6a）：
- 「PC1 收不到回包 / 回声帧在对端 PC 网口可见」= **L3**（2026-11-06 板上实测，归档 `prj12/out/evidence_2026-11-06/`，`prj12/pc/README.md:13-14`、`:18-20` 记载）。
- 「ping 必然不通」= **L2**（由上条实测 + 上条 RTL 静态连线共同得出，本轮**未**单独取得 ping 失败抓包）。
  → 所以本文写「预期不通」，不写「已证不通」。上板后请按 §5.4 补一条 ping 的 pcap 作为 RTL 级证据。

## 5.3 P2 为什么才通（以及一个必须先修的 RTL 前提）

P2 的转发是**真正的中转**（protocol_v1.md:112-125）：

```text
PC1 --(dst MAC=板A, IP dst=PC2)--> A
  A: dst==BOARD_MAC? 是 -> IPv4 dst==PEER_IP -> 去以太网头, IP 包逐字节原样送 Aurora
光纤: 一个 IPv4 packet = 一个内部帧
B: Aurora RX -> 加以太网头 (dst=PC2_MAC, src=BOARD_B_MAC, type=0x0800) -> PC2
PC2 回包 -> B -> (dst==PEER_IP=PC1) -> RELAY -> A -> 重封装 dst=PC1_MAC -> PC1
```

关键点：**跨板 ARP 一次都不需要**。PC1 已经把「PC2 的 IP」静态绑到板 A 的 MAC 上，
所以发往 `PC2 IP` 的帧天然被板 A 收下；回程同理。这就是 P2「才通」的全部原因。

> **RTL 硬前提（现在还没满足，务必转给 P0-1）**：契约里 `dst==BOARD_IP → LOCAL`（protocol_v1.md:133）。
> 但当前连线上 `eth_ctrl` 的所有 TX 字节都走 `stack_txd → 泵 A → Aurora`
> （`aurora_mem_bridge.v:676-677`、`:825-838`）。**如果 P2 位流不把本地栈应答改成「直接出本板 GE2」，
> 那么 PC1 `ping` 板 A 自己的 `BOARD_IP` 在 P2 依然不通**，与本文 §5.1 的预期冲突。
> 这条属于 `rtl/` 改动，不在本任务写权限内 —— 已列入 §6 待办。

## 5.4 上板后的补证动作（等口令）

```powershell
# 1) 静态 ARP 已绑（§3.4 校验 Permanent）
# 2) P1 位流上的期望（作为对照，记录现象而不是"通过"）
ping -n 4 192.168.1.10      # 期望：100% 丢失（L2 假设的反证点就是这里）
# 3) P2 位流上（两侧同时抓 180 s 连续包，见手册 §5 坑表）
py pc\twin_send.py --scheme protocol --pair A --dst-ip 192.168.50.2 --dst-port 47001 --count 20 --len 100 --interval-ms 20
py pc\twin_recv.py --from-pcap out\rx_b.pcap --scheme protocol --pair B `
    --expect-dst-ip 192.168.50.2 --no-bcast --expect-count 20 --expect-len 100
ping -n 4 192.168.50.2      # P2 期望：4/4 通过
```

# 6. 待确认项（**需项目负责人裁决，本文件不自行拍板**）

## 6.1 地址方案：两处文档不一致

| 项 | protocol_v1.md §2.2（交付仓契约） | 开工手册 §8 建议 | 冲突点 |
|---|---|---|---|
| PC1 | `192.168.50.1/24`（`protocol_v1.md:57`） | `10.10.0.1`（`prj13_P2开工手册_2026-11-08.md:128`） | 网段不同 |
| PC2 | `192.168.50.2/24`（`:58`） | `10.10.0.2`（`:128`） | 网段不同 |
| 板 A | `192.168.50.11/24` + `02:00:00:00:0A:01`（`:59`、`:66-67`） | `10.10.0.11`（`:128`），MAC 未给 | 网段不同；handbook 缺 MAC |
| 板 B | `192.168.50.12/24` + `02:00:00:00:0B:01`（`:60`、`:66-67`） | `10.10.0.12`（`:128`），MAC 未给 | 同上 |
| 业务 UDP 端口 | `47001`（`:107`） | 未提 | 需与 B 组确认 |
| 是否与 P1 的 `192.168.1.0/24` 共存 | 未提 | `:128` 提到「或保留 `192.168.1.10` 管理、业务另开网段」 | 是否双网段/双网口未定 |

**裁决选项**（任一被选中后，脚本只需改一行默认值）：

- 选项 1 = `protocol`（`.50.x`）：与已冻结的 v0.2 契约一致，交付仓文档不用改。
- 选项 2 = `handbook`（`10.10.0.x`）：避开 `192.168.x`（现场 Wi-Fi/办公网常占 `.1`/`.50.x`），但需同步改 `protocol_v1.md §2.2`。
- 选项 3 = 双网段（管理 `192.168.1.0/24` 保留 + 业务 `10.10.0.0/24`）：改动最大，需要两块板各留两个管理入口。

脚本侧已兼容：`static_arp.ps1 -Scheme`、`twin_send.py --scheme`、`twin_recv.py --scheme`，
可选值 `protocol`（默认）/`handbook`/`p1`。**默认值不等于裁决**（见 §0 与 README）。

## 6.2 其余待确认

| # | 待确认 | 现状/建议 | 需要谁 |
|---|---|---|---|
| 1 | `handbook` 方案的板卡 MAC 是否就用 `02:00:00:00:0A:01/0B:01` | 本文件按「MAC 属于板卡身份」沿用 protocol_v1 | 项目负责人 |
| 2 | 板卡是否继续用「管理+业务同网段」，还是管理另开网段 | 手册 §8 提了选项，未定 | 项目负责人 + B 组 |
| 3 | 业务 UDP 端口 47001 是否最终值（P1 工具链一直用 1234） | 脚本 `--dst-port` 默认 1234 以保 P1 回归，P2 业务按 47001 传参 | 项目负责人 + B 组 |
| 4 | 代理 ARP 是否启用（`PROXY_ARP_EN`） | v0.2 默认 0（纯静态 ARP） | 项目负责人 |
| 5 | 两板 MAC 必须不同 —— 是否接受 `02:` 本地管理地址段 | 本文件建议全部用 `02:` 开头（U1=1，locally administered） | 项目负责人 |
| 6 | **本地栈应答出板路径**（§5.3 风险）是否由 P0-1 改 | 现在应答进泵 A，不改则 P2 的 `BOARD_IP` ping 仍不通 | P0-1 RTL 负责人 |
| 7 | 10 MiB 批量帧数：手册写 7125，精确值 7124 | `ceil(10485760/1472)=7124`（7124×1472=10,486,528 ≥ 10,485,760）；7125 也覆盖，多 1 帧 | P0-3 判据负责人 |

# 7. 脚本侧兼容与验收证据

## 7.1 参数对照

| 脚本 | 关键参数 | 默认值 | 说明 |
|---|---|---|---|
| `pc/static_arp.ps1` | `-BoardPcPair A\|B`、`-Scheme`、`-LocalIp/-PeerIp/-BoardIp/-BoardMac/-PeerMac/-IfAlias`、`-DryRun`、`-Apply`、`-Remove`、`-List` | `-Scheme protocol`，`-IfAlias Ethernet`，不加 `-Apply` 即 dry-run | 纯 ASCII、PS 5.1 兼容；无网卡时 dry-run 仍 PASS |
| `pc/twin_send.py` | `--scheme/--pair/--dst-ip/--dst-port/--src-ip/--dst-mac/--src-mac/--iface/--len/--count/--run-id/--interval-ms/--dry-run/--bench` | `protocol/pair A`、`--len 100`、`--count 20`、`--run-id 0x1`、`--interval-ms 20`、`--dst-port 1234` | `--dst-mac/--src-mac/--iface` 只用于**帧头摘要与留证**；真发仍是 UDP socket（源 MAC/IP 由内核决定，`--src-ip` 才 bind） |
| `pc/twin_recv.py` | `--board-mac`（可多次）、`--expect-dst-ip`（可多次）、`--expect-dst-mac`（可多次）、`--no-bcast`、`--port-direction`、`--scheme/--pair` | `--port-direction any`；不给 `--board-mac` 时默认匹配**全部已知板卡 MAC** | P1 广播口径仍可判（不加 `--no-bcast`），P2 单播口径用 `--no-bcast` 硬判 |

## 7.2 实跑证据（全离线；22 步 22 PASS）

运行入口：`out/evidence_2026-11-08_p0_addr/run_evidence.ps1`（纯 ASCII，可重复执行）。
每个步骤的完整 stdout/stderr 落 `e_<step>.txt`，逐条带 `### CMD` / `### ACTUAL EXIT` / `### STEP VERDICT`。
校验和：`out/evidence_2026-11-08_p0_addr/SHA256SUMS.txt`（SHA256SUMS 覆盖 30 个文件 = 22 份 `e_*.txt` + `e_source_hashes.txt` + 3 份 bench 输出 + 2 个 mock pcap + `README.md` + `run_evidence.ps1`）。

摘要（runner 结尾原文）：

```text
STEPS: 22  FAILED: 0
SHA256SUMS.txt: 30 file(s)
EVIDENCE_RESULT: PASS
```

其中「应 FAIL 就 FAIL」的反向判据（证明判据不是橡皮图章）：

| 步骤 | 期望 | 实际 | 证据文件 |
|---|---|---|---|
| `static_arp_bad_mac`（`-BoardMac ZZ:11`） | exit 1 | 1 | `e_static_arp_bad_mac.txt` |
| `static_arp_no_params`（无参 dry-run） | exit 1 | 1 | `e_static_arp_no_params.txt` |
| `twin_send_bad_mac`（`--dst-mac ZZ:..`） | exit 1 | 1 | `e_twin_send_bad_mac.txt` |
| `twin_recv_p2_nobcast_fail`（广播帧 + `--no-bcast`） | exit 1 | 1 | `e_twin_recv_p2_nobcast_fail.txt` |
| `twin_recv_p2_multivalue_miss`（P1 mock 撞 P2 MAC 判据） | exit 1 | 1 | `e_twin_recv_p2_multivalue_miss.txt` |

关键输出行（照抄，含命令）：

```text
### CMD: powershell -NoProfile -ExecutionPolicy Bypass -File ...\pc\static_arp.ps1 -BoardPcPair A -DryRun
board ip : 192.168.50.11
board mac: 02-00-00-00-0a-01
peer ip  : 192.168.50.2  -> board mac (proxy-ARP form, ...)
CMD[1] : netsh interface ipv4 delete neighbors "Ethernet" 192.168.50.11
CMD[2] : netsh interface ipv4 add neighbors "Ethernet" 192.168.50.11 02-00-00-00-0a-01
CMD[3] : netsh interface ipv4 delete neighbors "Ethernet" 192.168.50.2
CMD[4] : netsh interface ipv4 add neighbors "Ethernet" 192.168.50.2 02-00-00-00-0a-01
STATIC_ARP_RESULT: DRY_RUN_OK
### ACTUAL EXIT: 0
```

```text
### CMD: py ...\pc\twin_send.py --dry-run
scheme   : protocol / pair A
dst      : 192.168.50.11:1234/udp
  ip       : ver=4 ihl=5 total_len=128 id=0x0000 (kernel chooses) flags=0x4000 = DF, ... proto=17/UDP csum=0x5510
  udp      : sport=40000 (placeholder) dport=1234 len=108 csum=0x0000 = 'not computed' in the plan; ...
DRY_RUN: nothing sent. Drop --dry-run to transmit.
### ACTUAL EXIT: 0
```

```text
### CMD: py ...\pc\twin_recv.py --from-pcap ...\mock_bcast.pcap --no-bcast --expect-count 5
FAIL: 5/5 matched frame(s) have broadcast/multicast eth.dst -- P2 requires unicast dst (the P1 broadcast echo shape is RETIRED)
twin_recv: FAIL
### ACTUAL EXIT: 1
```

# 8. 剩余风险

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| 1 | 地址方案未裁决，默认 `protocol` | 现场可能全错网段 | 脚本一行改默认值；`-Scheme/--scheme` 已就位；README §0 显式标注 |
| 2 | RTL 仍硬编码 P1 地址（`aurora_mem_bridge.v:98-101`） | 不换位流时新地址完全不生效 | 位流版本 ↔ `--scheme` 必须配对；换 P2 位流前先跑 `-Scheme protocol -DryRun` 自检 |
| 3 | 本地栈应答仍进泵 A（§5.3） | P2 的 `BOARD_IP` ping 仍不通 | 已列 §6.2 第 6 条，交 P0-1 |
| 4 | 现场网卡名可能是中文（本机 `以太网`） | 照抄文档里的 `Ethernet` 会找不到网卡 | `-IfAlias` 用 `Get-NetAdapter` 的 Name 原样；找不到时脚本会列候选 |
| 5 | `p1` 方案两 PC 同 IP | 若误用 p1 打 P2 位流，静默错址 | 脚本 banner 每次打印 `scheme`；p1 会打 NOTE 并跳过自身 IP 绑定 |

# 9. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-08 | v0.2 首版：完整地址表（protocol/handbook/p1 三套）、板卡参数表、作废三条旧口径、静态 ARP 双套命令、P1/P2 ping 预期与机制链、6.1 地址方案不一致并列待裁决、P2 RTL 本地栈出板风险、22 步 dry-run 证据 |
