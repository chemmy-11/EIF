# prj13 P2 · PC 侧脚本（双板 / 双 IP / 静态 ARP / 发帧基准）

> 板卡不在场也能跑：`static_arp.ps1 -DryRun`、`twin_send.py --dry-run`、`twin_recv.py --dry-run`
> 三个脚本都做过「无板 + 无网卡绑定」的参数自检（不落配置、不发包、不抓包）。
> 现场判据/流程见 `../scripts/p1_selfcheck.ps1`（P0-3）与 `../out/twin_link_test.ps1`。

## 0. 先钉死两件事（**地址方案待项目负责人裁决**）

两套候选并存，脚本用 `-Scheme` / `--scheme` 切换，**默认 `protocol`**；裁决后只需保留一套默认值。

| 项 | `protocol`（protocol_v1.md §2.2，默认） | `handbook`（开工手册 §8 建议） |
|---|---|---|
| PC1 | `192.168.50.1/24` | `10.10.0.1/24` |
| PC2 | `192.168.50.2/24` | `10.10.0.2/24` |
| 板 A（管理） | `192.168.50.11/24`，MAC `02:00:00:00:0A:01` | `10.10.0.11/24`，MAC 同上 |
| 板 B（管理） | `192.168.50.12/24`，MAC `02:00:00:00:0B:01` | `10.10.0.12/24`，MAC 同上 |
| 板 A `BOARD_IP`/`PEER_IP` | `.50.11` / `.50.2`（PC2） | `10.10.0.11` / `10.10.0.2` |
| 板 B `BOARD_IP`/`PEER_IP` | `.50.12` / `.50.1`（PC1） | `10.10.0.12` / `10.10.0.1` |

第三套 `p1` 只用于**当前位流**（P1 实跑值，RTL 硬编码 `rtl/aurora_mem_bridge.v:98-101`）：
板 `192.168.1.10` / `00:11:22:33:44:55`，两 PC 同为 `192.168.1.102`。
**换了 P2 位流就必须停用 `p1`**，否则地址全错。

板卡参数完整表 + 待裁决明细见 `../docs/M1_P2地址与ARP方案_v0.2_2026-11-08.md`。

| 项 | 板 A / PC1 | 板 B / PC2 |
|---|---|---|
| 数据网口 | **GE2**（GE1 一直 Disconnected，手册 §5） | **GE2** |
| PC 网卡 MAC | `08-3C-03-A0-26-96`（`以太网`） | `A8-2B-DD-76-DF-A2` |

## 1. 静态 ARP（**必须**，不是可选）

**为什么必须**：P1 里板卡的 ARP/ICMP/UDP 应答全部汇成 `stack_txd` 进泵A → Aurora
（`rtl/eth_ctrl.v:163-177`、`rtl/aurora_mem_bridge.v:657`/`:808`），**ARP 应答也跨光去了对端板**，
所以 PC 永远收不到 ARP 应答，`sendto()` 在 OS 层就失败。P2 数据面仍是「PC 静态 ARP」主方案
（`PROXY_ARP_EN=0`），默认不改。

```powershell
# 演练（任何机器都能跑，只打印将执行的 netsh 命令，不改系统配置）
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair B -DryRun -Scheme handbook

# 真绑（管理员；PC1 用 pair A，PC2 用 pair B；-IfAlias 必须是 Get-NetAdapter 的 Name 原样）
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -IfAlias "以太网"
# 校验：邻居表应出现 <板卡IP> -> 02-00-00-00-0a-01 / Permanent
Get-NetNeighbor -IPAddress 192.168.50.11 | Format-Table InterfaceAlias,IPAddress,LinkLayerAddress,State
# 解除
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -Remove -IfAlias "以太网"
# 只查看当前状态
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -List -IfAlias "以太网"
```

每条绑定写 **两个表项**（都是「→ 本板 MAC」的代理 ARP 形态，protocol_v1.md §2.3）：

| 表项 | PC1（pair A） | PC2（pair B） |
|---|---|---|
| 本板管理 IP → 本板 MAC | `192.168.50.11 → 02-00-00-00-0a-01` | `192.168.50.12 → 02-00-00-00-0b-01` |
| 对端 PC IP → 本板 MAC | `192.168.50.2 → 02-00-00-00-0a-01` | `192.168.50.1 → 02-00-00-00-0b-01` |

第二个表项是 P2 的关键：**PC1 发给 `192.168.50.2` 的帧，以太网目的 MAC 必须是板 A 的 MAC**，
A 才会收下并转发；否则走 ARP 广播、板卡应答又跨光，帧根本发不出去。

> 手工等价命令（不想用脚本时）：
> `netsh interface ipv4 add neighbors "以太网" 192.168.50.11 02-00-00-00-0a-01`

## 2. 发送：`twin_send.py`

payload 自带结构：`"TWIN"|seq(2)|count(2)|run_id(4)|fill(...)`，对端逐字节校验（`fill[i]=(seq+12+i)&0xFF`）。

```powershell
# 只看计划 + 42 B 以太网/IP/UDP 头摘要（不发包；默认 = 板A 形态）
py pc\twin_send.py --dry-run
# 只看计划：B 端 / 1200 B / run_id 0x2（PC2→PC1 方向）
py pc\twin_send.py --dry-run --pair B --len 1200 --run-id 0x2
# 当前位流（P1）发一帧：必须显式切 p1 方案
py pc\twin_send.py --dry-run --scheme p1 --src-mac 08-3C-03-A0-26-96
py pc\twin_send.py --scheme p1 --dst-port 1234 --count 20 --len 100 --run-id 0x1 --interval-ms 20
# 10 MiB 批量（interval 必须 0，否则 7124 帧 × 20 ms = 142 s）
py pc\twin_send.py --count 7124 --len 1472 --interval-ms 0 --run-id 0x10
```

参数全都有默认值（默认板A 形态），`--dst-mac/--src-mac/--iface` 只用于**帧头摘要与留证**：
真发仍是普通 UDP socket，源 MAC/源 IP 由内核路由决定（`--src-ip` 给了才会 `bind()`）。

## 3. 发帧能力基准：`--bench`

```powershell
# 无板：本机 socket 路径开销（构造 + sendto，loopback 收口）
py pc\twin_send.py --bench --bench-out out\evidence_2026-11-08_p0_addr\bench_no_board.txt
# 只测构造（连 socket 都不开）
py pc\twin_send.py --bench --bench-target none
# 上板后：真打板卡（这才是 L2/L3 证据）
py pc\twin_send.py --bench --bench-target board --dst-ip 192.168.50.11 --bench-count 20000
```

输出「帧长 vs 帧率 vs 实际 Mbps」markdown 表 + 10 MiB（1472 B × 7124 帧）乐观/保守耗时估计。
**无板一律标 L1**（AGENTS §6a），上板后必须用 `--bench-target board` 重测覆盖。
结论归档在 `../docs/M1_PC侧发帧能力基准_2026-11-08.md`。

## 4. 抓包 + 判据：`twin_recv.py`

```powershell
# 现场抓（dumpcap 来自 Wireshark；filter 只收板卡发出的帧）
dumpcap -D
dumpcap -i 3 -f "ether src 00:11:22:33:44:55" -a duration:30 -w pc2.pcap
# 解析（P2：多值 MAC / 多值目的 IP / 硬判单播）
py pc\twin_recv.py --from-pcap pc2.pcap --scheme protocol --pair B `
    --expect-dst-ip 192.168.50.2 --expect-dst-ip 192.168.50.1 --no-bcast `
    --port 1234 --expect-count 20 --expect-len 100 --expect-run-id 0x1
# 或者一条命令（内部调 dumpcap）
py pc\twin_recv.py --live --iface "以太网" --seconds 30 --out pc2.pcap --expect-count 20
# 只做参数校验（无板/无网卡/无 pcap 都能过）
py pc\twin_recv.py --dry-run --scheme protocol --pair B --no-bcast
```

判据口径（P1 → P2 的变化）：

| 项 | P1（已废止） | P2（新口径） |
|---|---|---|
| `eth.dst` | 广播 `ff:ff:ff:ff:ff:ff` 属预期，**不判** | 必须**单播** = 本端 PC MAC（`--no-bcast` 硬判） |
| 板卡判定 | `src` = `00:11:22:33:44:55` | `src` ∈ 本板 MAC（`--board-mac` 可多次 / `--scheme --pair`） |
| IP 目的 | 不分（两 PC 同 `.102`） | `--expect-dst-ip` 多值（本端 PC IP / 对端 PC IP） |
| 端口方向 | `--port-direction any`（默认保留） | 同左（板卡回声是 `sport=1234 / dport=PC 临时端口`） |

`matched=0` 时先看新加的 `other breakdown`：`other-src-mac` 涨 ⇒ MAC/方案不对；
`dst-ip-miss` 涨 ⇒ 地址方案选错（`protocol` vs `p1`）；`port-miss` 涨 ⇒ 端口判据不对。

## 5. 常见错误

| 现象 | 原因 | 处理 |
|---|---|---|
| `sendto` 直接失败 / `WSAEHOSTUNREACH` | 没绑静态 ARP（板卡 ARP 应答跨光） | 先 `static_arp.ps1 -Apply`，再 `Get-NetNeighbor` 确认 `Permanent` |
| 抓包看不到 GE 口流量 | 网线插了 **GE1** | 必须 **GE2**（GE1 一直 Disconnected，手册 §5） |
| 两 PC 互发不通、地址冲突 | PC1/PC2 都用 `.102`（P1 遗留） | 改成 `.50.1` / `.50.2`（或 `10.10.0.1/.2`），且**两端不同 IP** |
| 帧根本出不去 / 板卡不回 | 目的 MAC 用了广播（P1 回声口径） | P2 目的 MAC = 本板 MAC；`twin_recv --no-bcast` 会直接判 FAIL |
| `--dst-ip` 对但 `matched=0` | 方案不匹配（拿 `p1` 位流打 `.50.x`，或反之） | 位流版本 ↔ `-Scheme/--scheme` 必须一致；`p1` = 当前位流 |
| 判据 `FAIL: duplicate seq` | 真重复，或两端都发了同一 run_id | 换 `--run-id`（PC1 用 `0x1`、PC2 用 `0x2`）；确属预期才 `--allow-dup` |
| 10 MiB 跑了 2 分钟 | 忘了 `--interval-ms 0` | 批量/基准一律 `--interval-ms 0` |
| `WARN: N frame(s) carry 802.1Q VLAN tag` | 上游/网卡加了标签 | 板卡不发光 VLAN（P2 契约 DROP VLAN）；查网卡「优先级和 VLAN」设置 |
| `--len > 1472` 被 WARN | 超过 1500 MTU | 业务上限 1472 B payload（+8 UDP +20 IP = 1500 IP 包，以太网帧 1514 B，不 jumbo） |
| `static_arp` 报 `adapter not found` | `-IfAlias` 与 `Get-NetAdapter` 的 Name 不一致（可能中英混排） | 先 `Get-NetAdapter` 抄 Name 原样；`-DryRun` 不会因此失败 |

## 6. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-08 | prj13 P2（P0-2/P0-4）：双板/双 IP + `-Scheme`（protocol/handbook/p1）；`static_arp.ps1` 改 netsh + `-BoardPcPair A\|B`；`twin_send.py` 全参数 + 帧头摘要 + `--bench`；`twin_recv.py` 多值判据 + `--no-bcast`；新增常见错误表 |
| 2026-10-29 | （prj12 继承）payload 结构加固、VLAN/FCS 解析、`--port-direction any` |
