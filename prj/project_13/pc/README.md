# prj13 P2 · PC 侧脚本（双板 / 双 IP / 静态 ARP / 发帧基准）

> **默认地址方案 = `handbook`（`10.10.0.x`）**：项目负责人 2026-11-08 20:40 裁决。
> `protocol`（`192.168.50.x`）降级为历史方案；`p1`（`192.168.1.0/24`）只用于**现役 P1 基线位流**。
> 三个脚本每次运行都打印 `scheme=` 与 `BITSTREAM:` 两行 —— **位流版本必须和 scheme 配对**，
> 配错不会报错，只会静默丢包（见 §0.2）。

> 板卡不在场也能跑：`static_arp.ps1 -DryRun`、`twin_send.py --dry-run`、`twin_recv.py --dry-run`
> 三个脚本都做过「无板 + 无网卡绑定」的参数自检（不落配置、不发包、不抓包）。

## 0. 先钉死两件事

### 0.1 地址方案（已裁决）

| 项 | `handbook`（**默认**，已裁决） | `protocol`（历史） | `p1`（现役 P1 位流） |
|---|---|---|---|
| PC1 | `10.10.0.1/24` | `192.168.50.1/24` | `192.168.1.102/24` |
| PC2 | `10.10.0.2/24` | `192.168.50.2/24` | `192.168.1.102/24`（同 IP，P1 遗留） |
| 板 A | `10.10.0.11/24`，MAC `02:00:00:00:0A:01` | `192.168.50.11/24`，同 MAC | `192.168.1.10`，MAC `00:11:22:33:44:55` |
| 板 B | `10.10.0.12/24`，MAC `02:00:00:00:0B:01` | `192.168.50.12/24`，同 MAC | 同 A（P1 两板同值） |
| 用在哪 | **P2 位流** | P2 位流（若按旧契约文档构建） | **只对现役 P1 位流** |

完整地址表、板卡参数表、影响面清单见 `../docs/M1_P2地址与ARP方案_v0.2_2026-11-08.md`。

| 项 | 板 A / PC1 | 板 B / PC2 |
|---|---|---|
| 数据网口 | **GE2**（GE1 一直 Disconnected，手册 §5） | **GE2** |
| PC 网卡 MAC | `08-3C-03-A0-26-96`（`以太网`） | `A8-2B-DD-76-DF-A2` |

### 0.2 位流防呆（新增，最容易踩）

| 板上位流 | 脚本 scheme | 结果 |
|---|---|---|
| P1 基线（RTL 硬编码 `192.168.1.10`） | `handbook`（**默认**） | `sendto` 成功、板卡静默丢弃 → 看起来像"链路故障" |
| P2 新位流（`10.10.0.11/.12`） | `p1` | 发到 `192.168.1.10`，无人应答 |
| 任意 | scheme 与位流一致 | 正常 |

所以：**P1 位流必须显式 `-Scheme p1` / `--scheme p1`**；三个脚本的 `BITSTREAM:` 行会说明当前 scheme 需要哪种位流。

## 1. 静态 ARP（**必须**，不是可选）

**为什么必须**：P1 里板卡的 ARP/ICMP/UDP 应答全部汇成 `stack_txd` 进泵A → Aurora
（`rtl/eth_ctrl.v:159-180` → `rtl/aurora_mem_bridge.v:676-677` → `:825-838`），**ARP 应答也跨光去了对端板**，
所以 PC 永远收不到 ARP 应答，`sendto()` 在 OS 层就失败。P2 数据面仍是「PC 静态 ARP」主方案
（`PROXY_ARP_EN=0`），默认不改。

```powershell
# 演练（任何机器都能跑，只打印将执行的 netsh 命令，不改系统配置）；不给 -Scheme 就是 handbook
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair B -DryRun

# 真绑（管理员；PC1 用 pair A，PC2 用 pair B；-IfAlias 必须是 Get-NetAdapter 的 Name 原样）
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -IfAlias "以太网"
# 校验：邻居表应出现 10.10.0.11 -> 02-00-00-00-0a-01 / Permanent
Get-NetNeighbor -IPAddress 10.10.0.11 | Format-Table InterfaceAlias,IPAddress,LinkLayerAddress,State
# 解除 / 只查看
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -Remove -IfAlias "以太网"
powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -List -IfAlias "以太网"
# 其他方案：-Scheme protocol（历史 .50.x） / -Scheme p1（现役 P1 位流）
```

每条绑定写 **两个表项**（都是「→ 本板 MAC」的代理 ARP 形态，protocol_v1.md §2.3）：

| 表项 | PC1（pair A） | PC2（pair B） |
|---|---|---|
| 本板管理 IP → 本板 MAC | `10.10.0.11 → 02-00-00-00-0a-01` | `10.10.0.12 → 02-00-00-00-0b-01` |
| 对端 PC IP → 本板 MAC | `10.10.0.2 → 02-00-00-00-0a-01` | `10.10.0.1 → 02-00-00-00-0b-01` |

第二个表项是 P2 的关键：**PC1 发给 `10.10.0.2` 的帧，以太网目的 MAC 必须是板 A 的 MAC**，
A 才会收下并转发；否则走 ARP 广播、板卡应答又跨光，帧根本发不出去。

> 手工等价命令：`netsh interface ipv4 add neighbors "以太网" 10.10.0.11 02-00-00-00-0a-01`

## 2. 发送：`twin_send.py`

payload 自带结构：`"TWIN"|seq(2)|count(2)|run_id(4)|fill(...)`，对端逐字节校验（`fill[i]=(seq+12+i)&0xFF`）。

```powershell
# 只看计划 + 42 B 以太网/IP/UDP 头摘要（不发包；默认 = handbook 板A 形态 10.10.0.11）
py pc\twin_send.py --dry-run
# PC2 侧（板 B / 1200 B / run_id 0x2）
py pc\twin_send.py --dry-run --pair B --len 1200 --run-id 0x2
# 现役 P1 位流：必须显式切 p1
py pc\twin_send.py --dry-run --scheme p1 --src-mac 08-3C-03-A0-26-96
py pc\twin_send.py --scheme p1 --dst-ip 192.168.1.10 --dst-port 1234 --count 20 --len 100 --run-id 0x1
# P2 跨板业务（PC1 -> PC2）
py pc\twin_send.py --dst-ip 10.10.0.2 --dst-port 47001 --count 20 --len 100 --interval-ms 20
# 10 MiB 批量（interval 必须 0，否则 7124 帧 × 20 ms = 142 s）
py pc\twin_send.py --dst-ip 10.10.0.2 --count 7124 --len 1472 --interval-ms 0 --run-id 0x10
```

参数全都有默认值，`--dst-mac/--src-mac/--iface` 只用于**帧头摘要与留证**：
真发仍是普通 UDP socket，源 MAC/源 IP 由内核路由决定（`--src-ip` 给了才会 `bind()`）。

## 3. 发帧能力基准：`--bench`

```powershell
# 无板：本机 socket 路径开销（构造 + sendto，loopback 收口）
py pc\twin_send.py --bench --bench-out out\evidence_2026-11-08_p0_addr\bench_no_board.txt
# 只测构造（连 socket 都不开）
py pc\twin_send.py --bench --bench-target none
# 上板后：真打板卡（这才是 L2/L3 证据）
py pc\twin_send.py --bench --bench-target board --dst-ip 10.10.0.11 --bench-count 20000
```

输出「帧长 vs 帧率 vs 实际 Mbps」markdown 表 + 10 MiB（1472 B × 7124 帧）乐观/保守耗时估计。
**无板一律标 L1**（AGENTS §6a），上板后必须用 `--bench-target board` 重测覆盖。
**注意**：bench 数字只与帧长和主机 socket 开销有关，**与地址方案无关**，所以 2026-11-08 20:40
地址裁决后未重测（`bench_no_board.txt` 复用，证据包 `run_evidence.ps1` 默认也复用，`-RegenBench` 才重测）。

## 4. 抓包 + 判据：`twin_recv.py`

```powershell
# 现场抓（dumpcap 来自 Wireshark；filter 只收板卡发出的帧）
dumpcap -D
dumpcap -i 3 -f "ether src 02:00:00:00:0a:01" -a duration:30 -w pc2.pcap
# 解析（P2 默认 handbook：多值目的 IP + 硬判单播）
py pc\twin_recv.py --from-pcap pc2.pcap --pair B `
    --expect-dst-ip 10.10.0.2 --expect-dst-ip 10.10.0.1 --no-bcast `
    --port 47001 --expect-count 20 --expect-len 100 --expect-run-id 0x1
# 判 P1 抓包：必须显式 --scheme p1（否则默认只认 02:00:... 的板卡 MAC，会 matched=0）
py pc\twin_recv.py --from-pcap p1.pcap --scheme p1 --board-mac 00:11:22:33:44:55 --port 1234 --expect-count 20
# 或者一条命令（内部调 dumpcap）
py pc\twin_recv.py --live --iface "以太网" --seconds 30 --out pc2.pcap --expect-count 20
# 只做参数校验（无板/无网卡/无 pcap 都能过）
py pc\twin_recv.py --dry-run --pair B --expect-dst-ip 10.10.0.2 --no-bcast
```

判据口径（P1 → P2 的变化）：

| 项 | P1（已废止） | P2（新口径） |
|---|---|---|
| `eth.dst` | 广播 `ff:ff:ff:ff:ff:ff` 属预期，**不判** | 必须**单播** = 本端 PC MAC（`--no-bcast` 硬判） |
| 板卡判定 | `src` = `00:11:22:33:44:55` | `src` ∈ 本板 MAC（默认按 `--scheme` 取；`--board-mac` 可多次覆盖） |
| IP 目的 | 不分（两 PC 同 `.102`） | `--expect-dst-ip` 多值（本端 PC IP / 对端 PC IP） |
| 端口方向 | `--port-direction any`（默认保留） | 同左（板卡回声是 `sport=1234 / dport=PC 临时端口`；P2 业务 47001） |

`matched=0` 时先看 `other breakdown`：`other-src-mac` 涨 ⇒ MAC/方案不对（P1 位流？→ `--scheme p1`）；
`dst-ip-miss` 涨 ⇒ 地址方案选错；`port-miss` 涨 ⇒ 端口判据不对。

## 5. 常见错误

| 现象 | 原因 | 处理 |
|---|---|---|
| 默认 `handbook` 打现役 P1 位流：发包成功但板卡不回 | 位流 RTL 硬编码 `192.168.1.10` | 显式 `-Scheme p1` / `--scheme p1`；看脚本的 `BITSTREAM:` 行 |
| `sendto` 直接失败 / `WSAEHOSTUNREACH` | 没绑静态 ARP（板卡 ARP 应答跨光） | 先 `static_arp.ps1 -Apply`，再 `Get-NetNeighbor` 确认 `Permanent` |
| 抓包看不到 GE 口流量 | 网线插了 **GE1** | 必须 **GE2**（GE1 一直 Disconnected，手册 §5） |
| 两 PC 互发不通、地址冲突 | PC1/PC2 都用 `.102`（P1 遗留） | 改 `10.10.0.1` / `10.10.0.2`（或历史 `192.168.50.1/.2`），且**两端不同 IP** |
| 帧根本出不去 / 板卡不回 | 目的 MAC 用了广播（P1 回声口径） | P2 目的 MAC = 本板 MAC；`twin_recv --no-bcast` 会直接判 FAIL |
| 判 P1 抓包 `matched=0` | 默认 scheme 已是 `handbook`（只认 `02:00:...`） | 加 `--scheme p1`（或 `--board-mac 00:11:22:33:44:55`） |
| 判据 `FAIL: duplicate seq` | 真重复，或两端都发了同一 run_id | 换 `--run-id`（PC1 用 `0x1`、PC2 用 `0x2`）；确属预期才 `--allow-dup` |
| 10 MiB 跑了 2 分钟 | 忘了 `--interval-ms 0` | 批量/基准一律 `--interval-ms 0` |
| `WARN: N frame(s) carry 802.1Q VLAN tag` | 上游/网卡加了标签 | 板卡不发光 VLAN（P2 契约 DROP VLAN）；查网卡「优先级和 VLAN」设置 |
| `--len > 1472` 被 WARN | 超过 1500 MTU | 业务上限 1472 B payload（+8 UDP +20 IP = 1500 IP 包，帧 1514 B，不 jumbo） |
| `static_arp` 报 `adapter not found` | `-IfAlias` 与 `Get-NetAdapter` 的 Name 不一致（本机是中文 `以太网`） | 先 `Get-NetAdapter` 抄 Name 原样；`-DryRun` 不会因此失败 |

## 6. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-08 20:40 后 | 默认 scheme 全部切换为 **`handbook`（`10.10.0.x`，项目负责人裁决）**；`protocol` 降为历史；`p1` 明确为「现役 P1 位流专用」；三脚本新增 `BITSTREAM:` 位流防呆行；README 增加 §0.2 防呆表与判 P1 需 `--scheme p1` 的坑 |
| 2026-11-08 | prj13 P2（P0-2/P0-4）：双板/双 IP + `-Scheme`（protocol/handbook/p1）；`static_arp.ps1` 改 netsh + `-BoardPcPair A\|B`；`twin_send.py` 全参数 + 帧头摘要 + `--bench`；`twin_recv.py` 多值判据 + `--no-bcast`；新增常见错误表 |
| 2026-10-29 | （prj12 继承）payload 结构加固、VLAN/FCS 解析、`--port-direction any` |
