---
title: prj13 P2 地址与静态 ARP 方案 v0.3（双板 / 双端 PC；10.10.0.x 已裁决）
version: v0.3
date: 2026-11-08
decision: 地址方案 = handbook（10.10.0.x），项目负责人裁决 2026-11-08 20:40
scope: P0-2 交付物；纯离线（未上板、未启 Vivado/xsim）
related:
  - D:\GSnFPipe-FPGA-PP\docs\protocol_v1.md §2.2/2.3/2.4/2.5（转发契约；地址表待成品阶段同步）
  - C:\Users\15266\Desktop\毕设\操作文档\prj13_P2开工手册_2026-11-08.md §3 P0-2、§5、§8
  - D:\FPGA\prj\project_13\pc\README.md（脚本用法）、pc\static_arp.ps1、pc\twin_send.py、pc\twin_recv.py
  - D:\FPGA\prj\project_13\out\evidence_2026-11-08_p0_addr\（dry-run 全文证据 + SHA256SUMS）
---

# 0. 一页速览

| 项 | 结论 | 依据 |
|---|---|---|
| **地址方案（已裁决）** | **`handbook` = `10.10.0.x`**：PC1 `10.10.0.1` / PC2 `10.10.0.2` / 板 A `10.10.0.11` / 板 B `10.10.0.12`；MAC `02:00:00:00:0A:01` / `02:00:00:00:0B:01` | **项目负责人裁决 2026-11-08 20:40**；原建议见 `prj13_P2开工手册_2026-11-08.md:128` |
| `protocol`（`192.168.50.x`） | **降级为历史方案**，脚本仍可选；`protocol_v1.md §2.2` **本阶段不改**，留到成品阶段同步 | 裁决第 2 条（只有成品才进交付仓） |
| 双端 PC 地址 | **PC1 / PC2 必须不同 IP**（旧「两端同为 `.102`」口径作废） | 开工手册 §3 P0-2 第 54 行；protocol_v1.md:105 |
| 两块板地址 | 板 A / 板 B **不同 IP + 不同 MAC**（旧「两板同为 `.10` / `00:11:22:33:44:55`」口径作废） | 开工手册 §3 P0-2 第 54 行；protocol_v1.md:59-60、:66-67 |
| 回声帧 dst=广播 | **作废**；P2 要求单播 dst=本端 PC MAC | 开工手册 §5 第 101 行（旧口径）；protocol_v1.md:124（新口径 `dst=PC2_MAC`） |
| 静态 ARP | 仍然**必须**（`PROXY_ARP_EN=0`，纯静态），每端绑 **2 条**表项 | protocol_v1.md:76-83、:72 |
| **位流防呆** | `handbook`/`protocol` 需 **P2 位流**；现役 P1 位流只认 `192.168.1.10`，混用会**静默丢包** → 三个脚本每次运行都打印 `scheme=` + `BITSTREAM:` 提示 | 见 §4.1；RTL 硬编码 `rtl/aurora_mem_bridge.v:98-101` |
| P1 跨板 ping | **预期不通**（P1 是「终止 + 回显」语义，应答跨光去了对端板） | 见 §5；现象证据：prj12 `pc/README.md:13-14`、`:18-20`（P1 实测） |
| P2 跨板 ping | **才通**（`dst=PEER_IP` → RELAY，IP 包逐字节不变） | protocol_v1.md:118、:133-139 |
| 脚本 dry-run（无板/无网卡） | 23 步 23 PASS（含 5 步「应 FAIL 就 FAIL」反向判据） | `out/evidence_2026-11-08_p0_addr/`（`run_evidence.ps1` + `e_*.txt` + `SHA256SUMS.txt`） |

# 1. 地址表

## 1.1 已裁决主方案：`handbook`（`10.10.0.x`）

| 节点 | IP | MAC | 说明 |
|---|---|---|---|
| PC1（板 A 侧） | `10.10.0.1/24` | `08-3C-03-A0-26-96`（网卡名 `以太网`，现场 `Get-NetAdapter` 读取） | Stage1 |
| PC2（板 B 侧） | `10.10.0.2/24` | `A8-2B-DD-76-DF-A2`（现场读取） | Stage2 |
| 板 A | `10.10.0.11/24` | `02:00:00:00:0A:01` | 本地管理；数据面代理 PC2 |
| 板 B | `10.10.0.12/24` | `02:00:00:00:0B:01` | 本地管理；数据面代理 PC1 |

- IP 取自裁决：`prj13_P2开工手册_2026-11-08.md:128`（「PC1 `10.10.0.1` / PC2 `10.10.0.2` / 板卡管理 `10.10.0.11/.12`」）。
- MAC 由裁决第 1 条明确「MAC 仍 `02:00:00:00:0A:01/0B:01`」→ 与 `protocol_v1.md:59-60` 一致；**MAC 属板卡身份，与网段裁决无关**。
- PC 网卡 MAC 来自现场：`08-3C-03-A0-26-96` 见开工手册 §2 第 39 行（与 `prj12/out/twin_config.json:24` 一致）；PC2 的 `A8-2B-DD-76-DF-A2` 见 §2 第 40 行。
- `02:` 开头 = locally administered（U1 位=1），不当厂商 OUI 用；两板**必须不同 MAC**，否则两端 PC 无法区分回包来自哪块板。

## 1.2 历史方案：`protocol`（`192.168.50.x`，可选、非默认）

| 节点 | IP | MAC |
|---|---|---|
| PC1 | `192.168.50.1/24`（`protocol_v1.md:57`） | 同上 |
| PC2 | `192.168.50.2/24`（`:58`） | 同上 |
| 板 A | `192.168.50.11/24`（`:59`、`:66-67`） | `02:00:00:00:0A:01` |
| 板 B | `192.168.50.12/24`（`:60`、`:66-67`） | `02:00:00:00:0B:01` |

**保留理由**：交付仓 `protocol_v1.md §2.2` 现在仍是这套值；本阶段不动交付仓（裁决第 2 条），
脚本保留 `-Scheme protocol` 以便「按现有契约文档」复现，成品阶段同步后即可删除或改成同一套。

## 1.3 现役位流实际值：`p1`（**只用于 P1 基线位流**）

| 参数 | 值 | 证据 |
|---|---|---|
| `BOARD_MAC` | `00:11:22:33:44:55` | `rtl/aurora_mem_bridge.v:98` |
| `BOARD_IP` | `192.168.1.10` | `rtl/aurora_mem_bridge.v:99` |
| `DES_MAC` | `ff:ff:ff:ff:ff:ff`（广播） | `rtl/aurora_mem_bridge.v:100` |
| `DES_IP` | `192.168.1.102`（PC 侧） | `rtl/aurora_mem_bridge.v:101` |
| PC1 / PC2 | 都是 `192.168.1.102` | 开工手册 §2 第 39-40 行；`prj12/out/twin_config.json:21-24`、`:36` |

三个脚本的 `p1` 方案就是这一组值：**P1 基线位流在板上时用 `p1`，P2 位流在板上时用 `handbook`（默认）**。
选错不会报错，只会静默不通 —— 所以 §4.1 的防呆提示是硬性输出。

## 1.4 板卡参数表（`BOARD_IP`/`PEER_IP`/`BOARD_MAC`/`PEER_MAC`/`PC_IP`/`PC_MAC`）

定义先对齐（protocol_v1.md:66-70 + :76-83）：

| 参数 | 含义 | 谁用 |
|---|---|---|
| `BOARD_IP` | **本板**管理 IP。IPv4 `dst==BOARD_IP` → 交本地栈（ping/管理），不转发 | 本板 `local_steer` |
| `BOARD_MAC` | **本板** MAC。只收 `dst==BOARD_MAC` 的帧（非混杂）；转发时作 `src` | 本板 RX 过滤 / TX 重封装 |
| `PEER_IP` | **对端 PC** 的 IP（不是对端板的 IP）。`dst==PEER_IP` → RELAY | 本板 `local_steer`（**防环红线**，protocol_v1.md:139） |
| `PEER_MAC` | **对端 PC** 的 MAC。本板把放行帧重封装成 `dst=PEER_MAC` 时用 | 本板 TX 重封装（`eth_rewrap`） |
| `PC_IP` | **本端 PC**（直连本板的那台）的 IP | 本板 ARP/本地栈判断 |
| `PC_MAC` | **本端 PC** 的 MAC，本板发往本端 PC 时的 `dst` | 本板本地栈 TX |

> ⚠ 术语陷阱：`PEER_IP` 是「对端 **PC** 的 IP」，不是「对端板的管理 IP」。板 B 的管理 IP `.12` **永远不该**出现在板的转发判据里。

| 参数 | 板 A（`handbook`，**已裁决**） | 板 B（`handbook`，**已裁决**） | 板 A（`protocol`，历史） | 板 B（`protocol`，历史） |
|---|---|---|---|---|
| `BOARD_IP` | **`10.10.0.11`** | **`10.10.0.12`** | `192.168.50.11` | `192.168.50.12` |
| `BOARD_MAC` | `02:00:00:00:0A:01` | `02:00:00:00:0B:01` | 同左 | 同左 |
| `PEER_IP` | **`10.10.0.2`**（PC2） | **`10.10.0.1`**（PC1） | `192.168.50.2`（PC2） | `192.168.50.1`（PC1） |
| `PEER_MAC` | PC2 网卡 MAC | PC1 网卡 MAC | 同左 | 同左 |
| `PC_IP` | **`10.10.0.1`**（PC1） | **`10.10.0.2`**（PC2） | `192.168.50.1` | `192.168.50.2` |
| `PC_MAC` | `08-3C-03-A0-26-96` | `A8-2B-DD-76-DF-A2` | 同左 | 同左 |
| `RELAY_EN` | 1 | 1 | 1 | 1 |
| `PROXY_ARP_EN` | 0（纯静态 ARP） | 0 | 0 | 0 |

（`RELAY_EN`/`PROXY_ARP_EN` 取值来自 `protocol_v1.md:71-72`。）

# 2. 新口径：明确作废的三条旧口径

| # | 旧口径（P1 实测形态） | 出处 | 新口径（已裁决） | 为什么必须换 |
|---|---|---|---|---|
| 1 | 两端 PC 同为 `192.168.1.102` | 开工手册 §2 第 39-40 行（「PC2 也是 `.102`（M2 前必须改）」） | PC1 `10.10.0.1` / PC2 `10.10.0.2` | 同 IP 时 `dst==PEER_IP` 与本机 IP 重合，转发判据无法区分「发给对端」与「发给本机」，M2 跨板业务直接冲突（开工手册 §3 第 54 行） |
| 2 | 两块板同为 `192.168.1.10` / MAC `00:11:22:33:44:55` | `rtl/aurora_mem_bridge.v:98-99`（同一份位流烧两块板） | 板 A `10.10.0.11` / `02:00:00:00:0A:01`；板 B `10.10.0.12` / `02:00:00:00:0B:01` | 两板同 MAC 时 PC 无法区分回包来自本板还是对端板；P2 重封装要写 `src=BOARD_MAC`，必须两个不同值（protocol_v1.md:124） |
| 3 | 回声帧 `eth.dst = ff:ff:ff:ff:ff:ff`（板卡 ARP 表空 → 退化成广播） | 开工手册 §5 第 101 行；2026-11-06 实测 | P2 转发帧 `dst = PEER_MAC`（单播）；本地栈帧 `dst = PC_MAC` | 广播会让同链路所有设备都收到并上送协议栈；`twin_recv.py --no-bcast` 现在把广播目的直接判 FAIL |

**P1 的广播回声是 P1 的必然产物，不是 bug**：`DES_MAC=ff:ff:ff:ff:ff:ff`（`rtl/aurora_mem_bridge.v:100`）
+ 板卡 ARP 表里没有对端 PC 的 IP，所以只能广播。P2 之所以能写单播，是因为 PC 侧静态 ARP
把「对端 PC IP → 本板 MAC」钉死，板卡才知道该把帧交给哪一个 MAC（protocol_v1.md:76-81）。

# 3. 静态 ARP（已裁决方案，两边各一套，可直接照抄）

## 3.1 为什么必须（不是可选）

板卡侧 ARP/ICMP/UDP 的应答字节都汇到 `eth_ctrl` 的 `gmii_txd`（协议选择器 `rtl/eth_ctrl.v:159-180`），
该输出即 `stack_txd`（`rtl/aurora_mem_bridge.v:676-677`），再进「帧泵 A」写入 Aurora
（`rtl/aurora_mem_bridge.v:825-838`）。也就是说 **连 ARP 应答都会跨光到对端板**，
发起方 PC 永远等不到应答 → Windows 邻居解析失败 → `sendto()` 在 OS 层报错。
把表项钉成 `Permanent` 后，发送侧完全不依赖 ARP 应答。

P2 数据面仍是「PC 静态 ARP」主方案（`PROXY_ARP_EN=0`，protocol_v1.md:72、:83），所以 **P2 依然必须绑**。

> 行号勘误：`prj12/pc/README.md:18-19` 引的是 `rtl/eth_ctrl.v:163-177` 与 `aurora_mem_bridge.v:657`/`:808`。
> 逐行核对后：`eth_ctrl.v:163-177` 落在协议选择器内部（近似可接受），但
> `aurora_mem_bridge.v:657` 其实是 `icmp_tx_done` 端口、`:808` 是 `cfg_wr_go` 端口，**与「进泵A」无关**。
> 本文用核对后的行号：`eth_ctrl.v:159-180` → `aurora_mem_bridge.v:676-677` → `:825-838`。结论不变。

## 3.2 脚本（推荐；默认即已裁决方案）

```powershell
# PC1（板 A 侧）：演练 -> 真绑（不给 -Scheme 就是 handbook/10.10.0.x）
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -IfAlias "以太网"
# PC2（板 B 侧）
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair B -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair B -Apply -IfAlias "<PC2 网卡 Name>"
# 其他方案（历史/现役位流）
#   ... -Scheme protocol      # 192.168.50.x（历史）
#   ... -Scheme p1            # 192.168.1.x（只对现役 P1 位流）
# 解除 / 只查看
#   ... -Apply -Remove
#   ... -List
```

也可以完全手工给参数（不依赖预设）：

```powershell
... -LocalIp 10.10.0.1 -PeerIp 10.10.0.2 -BoardIp 10.10.0.11 `
    -BoardMac 02:00:00:00:0A:01 -PeerMac 02:00:00:00:0B:01 -IfAlias "以太网" -DryRun
```

## 3.3 手工等价命令（`handbook`，逐字可抄）

**PC1**：

```powershell
netsh interface ipv4 delete neighbors "以太网" 10.10.0.11
netsh interface ipv4 add    neighbors "以太网" 10.10.0.11 02-00-00-00-0a-01
netsh interface ipv4 delete neighbors "以太网" 10.10.0.2
netsh interface ipv4 add    neighbors "以太网" 10.10.0.2  02-00-00-00-0a-01
```

**PC2**：

```powershell
netsh interface ipv4 delete neighbors "<PC2 网卡>" 10.10.0.12
netsh interface ipv4 add    neighbors "<PC2 网卡>" 10.10.0.12 02-00-00-00-0b-01
netsh interface ipv4 delete neighbors "<PC2 网卡>" 10.10.0.1
netsh interface ipv4 add    neighbors "<PC2 网卡>" 10.10.0.1  02-00-00-00-0b-01
```

`protocol`（历史）把 IP 换成 `192.168.50.11/.12` 与 `192.168.50.2/.1`，MAC 不变。
`p1`（现役位流）：`192.168.1.10 → 00-11-22-33-44-55`（对端 PC 表项跳过：两 PC 同 `.102`）。

## 3.4 校验

```powershell
Get-NetNeighbor -IPAddress 10.10.0.11 | Format-Table InterfaceAlias,IPAddress,LinkLayerAddress,State
# 期望：LinkLayerAddress = 02-00-00-00-0A-01，State = Permanent
arp -a | Select-String "10.10.0"      # 交叉核对
```

本机现存 P1 表项实测（`static_arp.ps1 -Scheme p1 -DryRun` 的 `current` 行）：
`192.168.1.10 -> 00-11-22-33-44-55 state=Permanent` —— 脚本读的是真表，证据 `out/evidence_2026-11-08_p0_addr/e_static_arp_A_p1.txt`。

## 3.5 每条表项为什么是「→ 本板 MAC」

| 表项 | PC1 | PC2 | 作用 |
|---|---|---|---|
| 本板管理 IP → 本板 MAC | `10.10.0.11 → 02-00-00-00-0a-01` | `10.10.0.12 → 02-00-00-00-0b-01` | ping/管理本板不需要 ARP 应答 |
| 对端 PC IP → 本板 MAC | `10.10.0.2 → 02-00-00-00-0a-01` | `10.10.0.1 → 02-00-00-00-0b-01` | **P2 转发命脉**：去往对端 PC 的帧必须以本板 MAC 为目的，本板才收（板卡只收 `dst==BOARD_MAC`，protocol_v1.md:116） |

两条表项指向同一个 MAC 是**正常的代理 ARP 形态**（protocol_v1.md:81 原文）。

# 4. 地址方案变更影响面清单（裁决后必须同步的地方）

## 4.1 位流防呆（最重要，先看这条）

裁决把默认地址换成 `10.10.0.x`，但 **现役 P1 位流在 RTL 里硬编码 `192.168.1.10`**
（`rtl/aurora_mem_bridge.v:98-101`）。两边不匹配时**没有任何报错**，只有「帧发出去了但没人回」。

因此三个脚本每次运行都强制打印两行：

| 脚本 | 输出行（原文） |
|---|---|
| `static_arp.ps1` | `scheme   : handbook` + `BITSTREAM: handbook requires a P2 bitstream -- the RTL address params must be the adjudicated 10.10.0.x ...` + `Against a P1 bitstream (192.168.1.10) these entries silently drop frames.` |
| `twin_send.py` | `scheme   : handbook / pair A` + `BITSTREAM: requires a P2 bitstream -- RTL BOARD_IP must be 10.10.0.11/.12 ...` |
| `twin_recv.py` | `scheme   : handbook` + `BITSTREAM: requires a P2 bitstream (RTL BOARD_IP 10.10.0.11/.12); a P1 bitstream only ever emits 00:11:22:33:44:55 -> use --scheme p1 for P1 captures` |

配错时的表现（防呆要防的就是这个）：

| 位流在板上 | 脚本 scheme | 结果 |
|---|---|---|
| P1 基线（`192.168.1.10`） | `handbook`（默认！） | `sendto` 成功、板卡静默丢弃、PC2 抓不到帧 → **看起来像"脚本没问题但链路不通"** |
| P2 新位流（`10.10.0.11/.12`） | `p1` | 同上（发到 `192.168.1.10`，无人应答） |
| 任意 | `--scheme` 与位流一致 | 正常 |

**结论：上板第一件事是确认「位流版本 ↔ `--scheme`」配对**；P1 位流必须显式 `-Scheme p1` / `--scheme p1`。

## 4.2 影响面清单

| # | 对象 | 现状 | 裁决后要求 | 归属/状态 |
|---|---|---|---|---|
| 1 | **RTL 参数（地址相关 3 个）**：`BOARD_IP` / `DES_IP`(→`PEER_IP`) / `DES_MAC`(→`PEER_MAC`) | `192.168.1.10` / `192.168.1.102` / `ff:ff:ff:ff:ff:ff`（`aurora_mem_bridge.v:99-101`） | 板 A `BOARD_IP=10.10.0.11`、`PEER_IP=10.10.0.2`、`PEER_MAC=PC2 网卡 MAC`；板 B 对称（`.12` / `.1` / PC1 网卡 MAC） | **P0-1 / P2 顶层集成**（本任务不碰 `rtl/`） |
| 2 | RTL 参数（MAC，**非地址裁决范围**，但 P2 同样必须改） | `BOARD_MAC=00:11:22:33:44:55`（`aurora_mem_bridge.v:98`） | 板 A `02:00:00:00:0A:01`、板 B `02:00:00:00:0B:01` | 同上；这条来自 v0.2 契约（protocol_v1.md:66-67），与 20:40 网段裁决无关 |
| 3 | **PC 脚本 3 个默认值** | `static_arp.ps1 -Scheme`、`twin_send.py --scheme`、`twin_recv.py --scheme` 默认原为 `protocol` | **全部改为 `handbook`**（本次已完成）；`protocol`/`p1` 仍可选 | **本任务（已完成）** |
| 4 | `protocol_v1.md §2.2`（交付仓 `D:\GSnFPipe-FPGA-PP\docs\`） | `192.168.50.x` + `02:00:00:00:0A:01/0B:01` | **本阶段不改**；成品阶段把 §2.2 地址表同步成 `10.10.0.x` | **成品阶段**（裁决第 2 条：只有成品才进交付仓） |
| 5 | `prj12/out/twin_config.json` | `board_ip=192.168.1.10`、`pc_ip=192.168.1.102`（`:21-24`、`:33-36`） | **不动 prj12 基线**；prj13 需要自己的配置（建议 `prj13/out/twin_config_13.json`，`board_ip=10.10.0.11/.12`） | 构建/自检负责人（P0-3） |
| 6 | 位流登记（交付仓 `fpga/bitstreams/INDEX.md`） | P1 位流 `c856ba83…7401` + B1 `b1_E9BE2B14` | 新位流改名 `aurora_mem_bridge_p2_<指纹>.bit`，**登记行里必须写清该位流的地址参数族（`10.10.0.x`）**，避免与 P1 的 `192.168.1.0/24` 混烧 | 构建负责人（Lead） |
| 7 | 上板操作手册/执行单里的示例命令 | 多为 `192.168.1.10` / `.102` | 用 P1 位流时保留；用 P2 位流时改成 `10.10.0.11` / `10.10.0.1`，并在命令旁注明 `--scheme` | 文档维护（后续） |

**不需要改**：`PROXY_ARP_EN`（仍 0）、业务端口（仍按 47001 传参、脚本默认 1234 保 P1 回归）、
MTU/子网掩码/防火墙规则（`/24` 与 `1500` 不变，只有第三个八位组从 `.1` 变 `.10`）。

# 5. P1 跨板 ping 预期不通、P2 才通

## 5.1 结论表

| 源 → 目的 | P1（现役位流） | P2（v0.2 契约，已裁决地址） | 原因 |
|---|---|---|---|
| PC1 `ping` 板 A `BOARD_IP`（`10.10.0.11` / P1 的 `192.168.1.10`） | **不通** | **通**（本地栈） | P1：echo reply 汇入 `stack_txd` → 泵 A → 跨光到板 B；PC1 收不到。P2：`dst==BOARD_IP → LOCAL`（protocol_v1.md:133） |
| PC1 `ping` PC2 `PEER_IP`（`10.10.0.2`） | **不通** | **通** | P1：`DES_IP` 是「回显目的」而非转发；且应答跨光（`aurora_mem_bridge.v:101`）。P2：`dst==PEER_IP → RELAY`，B 侧重封装 `dst=PC2_MAC`（protocol_v1.md:118、:124） |
| PC2 `ping` PC1 `PEER_IP`（`10.10.0.1`） | **不通** | **通** | 对称 |
| PC1 `ping` 板 B 管理 IP（`10.10.0.12`） | 不通 | **不通（预期 DROP，计数）** | 只转发 `PEER_IP` 是防环红线（protocol_v1.md:139） |
| 任意 PC `ping` `8.8.8.8` | 不通 | 不通（DROP 计数） | 同上 |

## 5.2 为什么 P1 必然不通（机制链，逐行可查）

1. 板卡只回显/应答，**不转发**：P1 的 `DES_IP = 192.168.1.102`（`rtl/aurora_mem_bridge.v:101`）是「回声帧的 IP 目的」，不是「转发目标」。P1 语义 = 终止 + 回显。
2. 应答字节的去向：`eth_ctrl` 的 `protocol_sw` 把 ARP/UDP/ICMP 的 TX 字节复用到 `gmii_txd`（`rtl/eth_ctrl.v:159-180`）→ `stack_txd`（`aurora_mem_bridge.v:676-677`）→ 泵 A（`:825-838`）→ Aurora → 对端板 → 对端 PC 网口。
3. 因此发起方 PC 拿不到 ARP 应答，也拿不到 ICMP echo reply；`sendto()` 在 OS 层失败，`ping` 超时。

证据等级（AGENTS §6a）：
- 「PC1 收不到回包 / 回声帧在对端 PC 网口可见」= **L3**（2026-11-06 板上实测，归档 `prj12/out/evidence_2026-11-06/`，`prj12/pc/README.md:13-14`、`:18-20` 记载）。
- 「ping 必然不通」= **L2**（由上条实测 + RTL 静态连线共同得出，本轮**未**单独取 ping 失败抓包）→ 所以写「预期不通」，不写「已证不通」。

## 5.3 P2 为什么才通（以及一个必须先修的 RTL 前提）

```text
PC1 --(dst MAC=板A, IP dst=PC2=10.10.0.2)--> A
  A: dst==BOARD_MAC? 是 -> IPv4 dst==PEER_IP -> 去以太网头, IP 包逐字节原样送 Aurora
光纤: 一个 IPv4 packet = 一个内部帧
B: Aurora RX -> 加以太网头 (dst=PC2_MAC, src=BOARD_B_MAC, type=0x0800) -> PC2
PC2 回包 -> B -> (dst==PEER_IP=PC1 10.10.0.1) -> RELAY -> A -> 重封装 dst=PC1_MAC -> PC1
```

关键点：**跨板 ARP 一次都不需要**。PC1 已把「PC2 的 IP」静态绑到板 A 的 MAC 上，
所以发往 PC2 IP 的帧天然被板 A 收下；回程同理。这就是 P2「才通」的全部原因。

> **RTL 硬前提（还没满足，务必转 P0-1）**：契约里 `dst==BOARD_IP → LOCAL`（protocol_v1.md:133），
> 但当前连线上 `eth_ctrl` 的所有 TX 字节都走 `stack_txd → 泵 A → Aurora`（`aurora_mem_bridge.v:676-677`、`:825-838`）。
> **若 P2 位流不把本地栈应答改成「直接出本板 GE2」，PC1 `ping` 板 A 自己的 `BOARD_IP` 在 P2 依然不通**，
> 与 §5.1 的预期冲突。属 `rtl/` 改动，不在本任务写权限内 —— 见 §7 待办。

## 5.4 上板后的补证动作（等口令）

```powershell
# 1) 静态 ARP 已绑（§3.4 校验 Permanent）
# 2) P1 位流（现役）用 p1 方案，记录现象而不是"通过"
py pc\twin_send.py --scheme p1 --dst-ip 192.168.1.10 --dst-port 1234 --count 3 --len 100
ping -n 4 192.168.1.10          # 期望：100% 丢失（L2 假设的反证点）
# 3) P2 新位流：默认 handbook 即可
py pc\twin_send.py --dst-ip 10.10.0.2 --dst-port 47001 --count 20 --len 100 --interval-ms 20
py pc\twin_recv.py --from-pcap out\rx_b.pcap --pair B --expect-dst-ip 10.10.0.2 --no-bcast `
    --expect-count 20 --expect-len 100
ping -n 4 10.10.0.2             # P2 期望：4/4 通过
```

# 6. 裁决记录与其余待确认

## 6.1 已裁决（2026-11-08 20:40，项目负责人）

| # | 项 | 裁决 | 影响 |
|---|---|---|---|
| 1 | 地址方案 | **`handbook` `10.10.0.x`** 取代 `protocol_v1.md §2.2` 的 `192.168.50.x` 作为默认；`protocol` 方案保留但不再是默认 | 三个脚本默认值已改；§4.2 清单 |
| 2 | 交付仓 | **只有成品才进交付仓** → 本阶段**不改** `D:\GSnFPipe-FPGA-PP\docs\protocol_v1.md`，所有落文进 `D:\FPGA\prj\project_13\` | §4.2 第 4 条 |
| 3 | Vivado | Lead 正在做 P2 顶层集成 + 综合/实现/位流，**本任务不跑任何 Vivado/xsim** | 本文件全部离线 |

历史对照（供成品阶段同步时核对）：

| 项 | 历史 `protocol_v1.md §2.2` | 已裁决 |
|---|---|---|
| PC1 / PC2 | `192.168.50.1` / `192.168.50.2` | `10.10.0.1` / `10.10.0.2` |
| 板 A / 板 B | `192.168.50.11` / `192.168.50.12` | `10.10.0.11` / `10.10.0.12` |
| 板 MAC | `02:00:00:00:0A:01` / `02:00:00:00:0B:01` | **不变** |
| 子网/前缀 | `/24` | **不变** |
| 业务 UDP 端口 | 47001（`protocol_v1.md:107`） | **不变**（脚本 `--dst-port` 默认仍 1234 以保 P1 回归，P2 业务显式传 47001） |

## 6.2 其余待确认（不影响本阶段脚本）

| # | 待确认 | 现状/建议 | 需要谁 |
|---|---|---|---|
| 1 | 板卡管理是否需要独立网段 | 当前管理+业务同 `10.10.0.0/24` | 项目负责人 + B 组 |
| 2 | 业务 UDP 端口 47001 是否最终值 | 契约写 47001，P1 工具链一直 1234 | 项目负责人 + B 组 |
| 3 | 代理 ARP 是否启用（`PROXY_ARP_EN`） | v0.2 默认 0（纯静态 ARP） | 项目负责人 |
| 4 | **本地栈应答出板路径**（§5.3 风险） | 现在应答进泵 A，不改则 P2 的 `BOARD_IP` ping 仍不通 | P0-1 RTL 负责人 |
| 5 | prj13 版 `twin_config_13.json` 由谁生成 | 建议 P0-3 自检脚本生成，含 `board_ip=10.10.0.11/.12` | P0-3 |
| 6 | 10 MiB 批量帧数：手册写 7125，精确值 7124 | `ceil(10485760/1472)=7124`；7125 也覆盖（多 1 帧） | P0-3 判据负责人 |

# 7. 脚本侧兼容与验收证据

## 7.1 参数对照（默认已切到已裁决方案）

| 脚本 | 关键参数 | 默认值 | 说明 |
|---|---|---|---|
| `pc/static_arp.ps1` | `-BoardPcPair A\|B`、`-Scheme handbook\|protocol\|p1`、`-LocalIp/-PeerIp/-BoardIp/-BoardMac/-PeerMac/-IfAlias`、`-DryRun`、`-Apply`、`-Remove`、`-List` | **`-Scheme handbook`**，`-IfAlias Ethernet`，不加 `-Apply` 即 dry-run | 纯 ASCII、PS 5.1 兼容；无网卡时 dry-run 仍 PASS；每次打印 `scheme=` + `BITSTREAM:` |
| `pc/twin_send.py` | `--scheme/--pair/--dst-ip/--dst-port/--src-ip/--dst-mac/--src-mac/--iface/--len/--count/--run-id/--interval-ms/--dry-run/--bench` | **`--scheme handbook`**、`--pair A`、`--len 100`、`--count 20`、`--run-id 0x1`、`--interval-ms 20`、`--dst-port 1234` | `--dst-mac/--src-mac/--iface` 只用于**帧头摘要与留证**；真发仍是 UDP socket（`--src-ip` 才 bind） |
| `pc/twin_recv.py` | `--scheme handbook\|protocol\|p1`、`--pair`、`--board-mac`（可多次）、`--expect-dst-ip`（可多次）、`--expect-dst-mac`（可多次）、`--no-bcast`、`--port-direction` | **`--scheme handbook`**（板卡 MAC 判据取该方案两块板）；`--port-direction any` | **判 P1 抓包必须显式 `--scheme p1`**（否则默认只认 `02:00:00:00:0A:01/0B:01`，P1 帧会 `matched=0`） |

## 7.2 实跑证据（全离线；23 步 23 PASS）

运行入口：`out/evidence_2026-11-08_p0_addr/run_evidence.ps1`（纯 ASCII，可重复执行）。
每步完整 stdout/stderr 落 `e_<step>.txt`，逐条带 `### CMD` / `### ACTUAL EXIT` / `### STEP VERDICT`。
`e_source_hashes.txt` 记录产生这些 transcript 的脚本 SHA256；`SHA256SUMS.txt` 覆盖目录内全部文件。

反向判据（证明判据不是橡皮图章）：

| 步骤 | 期望 | 实际 | 证据文件 |
|---|---|---|---|
| `static_arp_bad_mac`（`-BoardMac ZZ:11`） | exit 1 | 1 | `e_static_arp_bad_mac.txt` |
| `static_arp_no_params`（无参 dry-run） | exit 1 | 1 | `e_static_arp_no_params.txt` |
| `twin_send_bad_mac`（`--dst-mac ZZ:..`） | exit 1 | 1 | `e_twin_send_bad_mac.txt` |
| `twin_recv_p2_nobcast_fail`（广播帧 + `--no-bcast`） | exit 1 | 1 | `e_twin_recv_p2_nobcast_fail.txt` |
| `twin_recv_p2_multivalue_miss`（P1 mock 撞 P2 判据） | exit 1 | 1 | `e_twin_recv_p2_multivalue_miss.txt` |

默认 scheme 实测输出（节选，`e_static_arp_A_default_handbook.txt`）：

```text
### CMD: powershell ... -File ...\pc\static_arp.ps1 -BoardPcPair A -DryRun
scheme   : handbook
note     : scheme=handbook is the ADJUDICATED plan (project owner decision 2026-11-08 20:40);
BITSTREAM: handbook requires a P2 bitstream -- the RTL address params must be the
           adjudicated 10.10.0.x (BOARD_IP 10.10.0.11/.12, PEER_IP 10.10.0.2/.1).
board ip : 10.10.0.11
board mac: 02-00-00-00-0a-01
CMD[2] : netsh interface ipv4 add neighbors "Ethernet" 10.10.0.11 02-00-00-00-0a-01
CMD[4] : netsh interface ipv4 add neighbors "Ethernet" 10.10.0.2 02-00-00-00-0a-01
STATIC_ARP_RESULT: DRY_RUN_OK
### ACTUAL EXIT: 0
```

# 8. 剩余风险

| # | 风险 | 影响 | 缓解 |
|---|---|---|---|
| 1 | **默认已切 handbook，但位流可能还是 P1** | 静默丢包，最像"链路故障" | 三个脚本每次打印 `BITSTREAM:`；上板第一步核对位流版本（§4.1） |
| 2 | RTL 仍硬编码 P1 地址（`aurora_mem_bridge.v:98-101`） | 不换位流时新地址完全不生效 | §4.2 第 1/2 条交 P0-1；位流登记必须写地址族 |
| 3 | 本地栈应答仍进泵 A（§5.3） | P2 的 `BOARD_IP` ping 仍不通 | §6.2 第 4 条，交 P0-1 |
| 4 | 现场网卡名可能是中文（本机 `以太网`） | 照抄 `Ethernet` 会找不到网卡 | `-IfAlias` 用 `Get-NetAdapter` 的 Name 原样；找不到时脚本列候选，dry-run 仍 PASS |
| 5 | `twin_recv.py` 默认只认 `02:00:...` | 判 P1 抓包时 `matched=0`（易误判为链路坏） | 判 P1 必须 `--scheme p1`；`other-src-mac` 计数会立刻暴露 |

# 9. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-08 20:40 后 | **v0.3**：按项目负责人裁决把 `handbook`（`10.10.0.x`）升为默认主方案（裁决来源 2026-11-08 20:40）；`protocol` 降级为历史方案（`protocol_v1.md §2.2` 留待成品阶段同步）；新增 §4「地址方案变更影响面清单」（RTL 参数 3+1、pc 脚本 3 默认值、交付仓文档、twin_config/位流登记）；新增 §4.1 位流防呆表；证据矩阵重跑为 23 步 |
| 2026-11-08 | v0.2 首版：完整地址表（protocol/handbook/p1 三套）、板卡参数表、作废三条旧口径、静态 ARP 双套命令、P1/P2 ping 预期与机制链、地址方案不一致并列待裁决、P2 RTL 本地栈出板风险 |
