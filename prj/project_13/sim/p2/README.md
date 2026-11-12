# prj13 · P2 透明 IPv4 转发 —— RTL 三件套 + 一键 xsim

> 契约：issue #10 / `protocol_v1.md` §2.2 / §2.5 / §3.1（**v0.2 语义**）
> 状态：**单元级 xsim 全 PASS（21/21，exit 0）**，2026-11-08；未上板。
> 证据：`../../out/evidence_2026-11-08_p2_sim/`
> 历史：`docs/M1_prj12_P2透明转发候选设计_2026-10-24.md` 是 v0.1 的 UDP-payload 方案，
> **只作迁移参考**，与 v0.2（整 IPv4 包逐字节透传）语义已不同，不要照它实现。

---

## 1. 模块清单

| 文件 | 模块 | 作用 | 参数默认值（板 A） |
|---|---|---|---|
| `rtl/p2/ipv4_packet_extract.v` | `ipv4_packet_extract` | 以太网帧 → IPv4 包（剥 14 B 头与 padding），9 类结构检查 + 元数据 + 事件脉冲 | `MAX_IP_LEN=1500`、`BOARD_MAC=48'h02_00_00_00_0A_01` |
| `rtl/p2/eth_rewrap.v` | `eth_rewrap` | IPv4 包 → 以太网帧：只加/换 14 B 头 + 1:1 透传 + <60 B 补零 | `SRC_MAC=…0A_01`、`DST_MAC=0`（顶层填对端 PC MAC）、`MIN_FRAME_LEN=60` |
| `rtl/p2/local_steer.v` | `local_steer` | 组合判决 DROP/LOCAL/RELAY/ARP（§2.5 全表）+ 32 bit 粘滞计数器组 | `BOARD_IP=10.10.0.11`、`PEER_IP=10.10.0.2`、`PC_IP=10.10.0.1`、`PROXY_ARP_EN=0` |
| `rtl/p2/p2_frame_buf.v` | `p2_frame_buf` | **集成层（Lead 所有，本组只读）**：单时钟 2 bank 整帧弹性缓冲，bank 忙则整帧丢弃并计数；v2 增 `o_rd_eth_dst/o_rd_eth_type` 侧带跟帧走 | `AW=11`（2048 B/bank） |
| `rtl/p2/p2_relay_top.v` | `p2_relay_top` | **集成层（Lead 所有，本组只读）**：三件套接成两条单向通路（eth→relay、aur→lan）+ 两域计数器 | `BOARD_IP=10.10.0.11` 等（见 §2.4） |
| `sim/p2/tb_p2_pipeline.v` | `tb_p2_pipeline` | 单元 TB：三件套串起来（含 glue 与参考计数器模型），23 例 | — |
| `sim/p2/tb_p2_relay_top.v` | `tb_p2_relay_top` | 集成 TB：`p2_relay_top` 双时钟（eth 125 / aur 200 MHz），8 例（I01–I09） | — |
| `sim/p2/tb_p2_frame_buf.v` | `tb_p2_frame_buf` | 单元 TB：`p2_frame_buf` 整帧丢弃 + v2 侧带，4 例（FB01–FB04） | — |
| `sim/p2/run_p2_sim.ps1` | — | 一键跑**三个** TB（各自 xvlog→xelab→xsim），汇总 `P2_SIM: PASS (unit/relay/framebuf)` | — |

板 B 差异（只改参数，不改代码）：`BOARD_MAC=48'h02_00_00_00_0B_01`、`BOARD_IP=.12`、
`PEER_IP=.1`、`PC_IP=.2`、`DST_MAC` 填 PC2 实际 MAC。

编码纪律：全部 **Verilog-2001**（无 `logic`/`always_ff`/`interface`/package），
单时钟域，端口固定 `input clk, input rst_n`（异步低有效复位）。

---

## 2. 接口摘要

公共字节流握手：`valid/ready/data[7:0]/sop/eop`，1 byte/beat，`valid&&ready` 才算传输，
不含前导/FCS。统一 drop reason（4 bit，三件套共用）：

```
0 NONE  1 VLAN  2 IPV6  3 ETHERTYPE  4 BROADCAST  5 MULTICAST
6 UNKNOWN_DST  7 OVERSIZE  8 BAD_CSUM  9 TRUNCATED  10 MAC
```

### 2.1 `ipv4_packet_extract`

输入整以太网帧，输出**只有 IPv4 包**（长度严格 = `total_len`），元数据 `m_ip_src/m_ip_dst/
m_total_len/m_ip_id/m_csum/m_proto/m_ttl/m_tos/m_ihl/m_ip_flags/m_frag_off/m_is_fragment`
从 `m_sop` 被接受到 `m_eop` 有效。事件：`o_frame_pulse`（每帧 1 拍，判决拍）、
`o_parse_pulse`（`m_eop` 握手拍）、`o_drop_pulse`+`o_drop_reason`。

检查顺序（命中即丢，**仍把整帧消费到 eop**）：

1. 帧长 < 34 → TRUNCATED
2. `eth_type ∈ {0x8100, 0x88A8}` → VLAN
3. `eth_type == 0x86DD` → IPV6
4. `eth_type != 0x0800` → ETHERTYPE（**ARP 0x0806 走本条但不计 drop**：ARP 的 LOCAL 记账归 `local_steer`）
5. `version!=4 || ihl<5 || ihl*4>total_len` → TRUNCATED
6. `total_len > MAX_IP_LEN` → OVERSIZE
7. 帧长 < 14+`total_len` → TRUNCATED
8. IP 头 ones'-complement 累加 != 0xFFFF → BAD_CSUM
9. `eth_dst` 既非 `BOARD_MAC` 也非广播/组播 → MAC

### 2.2 `eth_rewrap`

`[14 B 新头: DST_MAC | SRC_MAC | 0x0800]` + IP 包 1:1 原样（**不改任何字节**）+
不足 `MIN_FRAME_LEN` 补 `0x00`。`m_frame_len = 14 + max(i_pkt_len, MIN_FRAME_LEN-14)`。
`o_len_err`：`i_pkt_len` 与实际收到的字节数不符时脉冲。14 B 头期间 `s_ready=0`（上游被反压
14 拍），之后 `s_ready = m_ready` 直通。

### 2.3 `local_steer`

判决表（顺序即优先级）：

| # | 条件 | 判决 |
|---|---|---|
| 1 | `eth_type==0x0806` | ARP(3)（任何 ARP 永不 RELAY） |
| 2 | eth_dst 广播（非 ARP）：`ip_dst==BOARD_IP` | LOCAL / 否则 DROP+BROADCAST |
| 3 | eth_dst 组播 | DROP+MULTICAST |
| 4 | `eth_dst != BOARD_MAC` 且非广播/组播 | DROP+MAC |
| 5 | `i_ip_hdr_ok==0` | DROP+NONE（reason 由上游沿给出） |
| 6 | `ip_dst==255.255.255.255` 或 `0.0.0.0/8` | DROP+BROADCAST |
| 6b | `ip_dst[31:28]==4'hE` | DROP+MULTICAST |
| 7 | `ip_dst==BOARD_IP` / `==PEER_IP` | LOCAL / RELAY |
| 8 | 其它（含 8.8.8.8） | DROP+UNKNOWN_DST ← **防乒乓红线** |

计数器：`rx_frames/relay/local/arp` + 10 个 `drop_*`，全部 32 bit 粘滞、`rst_n` 清零；
`i_drop_pulse` + `i_drop_reason` 解码，`DROP_NONE` 不加任何 drop 计数。

---

## 3. 用例表

### 3.1 单元 TB `tb_p2_pipeline.v`（23 条：三件套串起来，含 TB glue）

| # | 用例 | 覆盖的验收集 | 断言要点 |
|---|---|---|---|
| C01 | `normal_relay_1472` | 正常转发逐字节相同 | 1472 B IP 包（**真 IP + 真 UDP checksum**，两者都自校验折叠=0xFFFF）；输出 1486 B，`0x0800`，dst/src MAC 正确，IP 段逐字节相同 |
| C02 | `tiny_pad_26_to_60` | <60 B 补零 | 26 B 包 → 帧长 60，前 40 B 原样、后 20 B 全 0 |
| C03 | `drop_vlan` | VLAN | 无输出、reason=1、`cnt_drop_vlan+1` |
| C04 | `drop_ipv6` | IPv6 | reason=2 |
| C05 | `drop_ethertype` | 非 IP（0x1234） | reason=3 |
| C06 | `drop_broadcast` | 广播 | reason=4（以太网广播 + IP 非本板） |
| C07 | `drop_multicast` | 组播 | reason=5（`ip_dst=PEER_IP` 也被 MAC 层先丢，证明优先级） |
| C08 | `drop_unknown_dst` | 未知 dst 8.8.8.8 | reason=6 |
| C09 | `drop_oversize` | 超长 | `total_len=1501`，帧给满 1515 B，reason=7 |
| C10 | `drop_bad_csum` | 坏 IP 头 checksum | 翻 TTL 一位，先自证"确实非法"，reason=8 |
| C11 | `drop_truncated` | 帧截断 | `total_len=100` / 帧 60 B，reason=9，**零字节外泄** |
| C12 | `drop_mac` | 非本板 MAC（第 10 类） | reason=10 |
| C13 | `arp_local_no_cross` | ARP 不跨板 | `decision==3`、`cnt_arp+1`、`cnt_drop_ethertype` **不动**、rewrap 零输出 |
| C14 | `no_pingpong_x3` | 无乒乓 | 连发 3 帧 8.8.8.8 → 全 DROP_UNKNOWN_DST，输出帧数=0 **且字节数=0** |
| C15 | `fragment_passthru` | 分片透传 | MF=1 + frag_off=1480，逐字节相同，`m_is_fragment=1`，无重组 |
| C16 | `backpressure_lfsr` | 背压不丢字节 | `m_ready` 由 16 bit LFSR 随机拉低，1472 B 仍逐字节正确 |
| C17 | `csum_boundary_0000` | checksum 边界 A | 字段=0x0000（其余字段折叠和=0xFFFF）→ 必须**接受**并透传 |
| C18 | `csum_boundary_ffff` | checksum 边界 B | 字段=0xFFFF → 必须**丢弃**（reason=8），见 §6.3 |
| C19 | `local_to_board_ip` | LOCAL 分支 | `ip_dst=BOARD_IP`（单播到本板 MAC）→ `decision==1`、`cnt_local+1`、零输出 |
| C20 | `local_bcast_to_board_ip` | LOCAL 分支（广播+本板 IP） | 以太网广播但 `ip_dst==BOARD_IP` → LOCAL（不能被当广播丢掉），`cnt_local+1` |
| C22 | `old_protocol_addr_now_drop` | 旧地址不再生效 | `ip_dst=192.168.50.11`（protocol_v1 §2.2 旧板 A IP）→ `DROP_UNKNOWN_DST`、**不得被判 LOCAL**。防"两套地址混用"时静默转发 |
| C23 | `default_params_handbook_addr` | **RTL 默认参数自检** | 用一份**不带 `#()` 覆盖**的 `local_steer` 实例直接验默认值：`BOARD_IP==10.10.0.11`→LOCAL、`PEER_IP==10.10.0.2`→RELAY、旧 `192.168.50.11/.2`→DROP、`10.0.10.11`（字节序反写）→DROP |
| C21 | `global_counters_clean` | 全局收尾 | 23 帧后 14 个计数器/输出字节数/`o_len_err` 全对，并断言 `cnt_local==2`（防 LOCAL 分支空跑） |

> C23 是补一个**真覆盖洞**才加的：`u_steer` 是带参数覆盖例化的，RTL 里的**默认值在仿真里根本没被用到**——
> 只测 `u_steer` 的话，"默认值写错/字节序写反"永远查不出来（变异 MA 实测就是这么漏过去的）。

**每例都做的三件事**：(1) 14 个计数器逐一对参考模型；(2) 判决/元数据逐字段比对；
(3) rewrap 输出**帧数 + 总字节数 + 逐字节**比对。第 (3) 条的"总字节数"是关键——
它把"没有完整帧"升级成"一个字节都没漏"，否则切通实现的半包泄漏查不出来。

### 3.2 集成 TB `tb_p2_relay_top.v`（13 条，双时钟 eth 125 MHz / aur 200 MHz）

被测件 `p2_relay_top`（v2）+ 内部 `p2_frame_buf` + 三件套。两域时钟**故意不同频**，
跨域接错会立刻表现为帧错位/计数不对。

| # | 用例 | 断言要点 |
|---|---|---|
| I01 | `relay_1472` | 1472 B IP（dst=PEER_IP）从 `rx_data/rx_dv` 进 → `relay_data/relay_en` **逐字节相同**、字节数=1472、**恰好 1 帧**、`st_relay=1`。帧边界即字节边界（en 上升/下降落在 IP 包首/尾），错一个字节计数/内容就对不上 |
| I02 | `local_swallowed` | dst=BOARD_IP → relay **零帧零字节**、`st_local=1`、`st_relay` 不变 |
| I03 | `arp_no_cross` | 广播 ARP(0x0806) → relay 零字节、`st_arp=1`、`st_drop_ethertype` **不动**（ARP 不算 ethertype 丢弃） |
| I04 | `back_to_back_3` | 3 帧连发（帧间仅 1 拍空档，142 B 短帧）→ **守恒判据** `relayed + st_rx_drop == 3` + 已转出的帧逐字节正确；打 `[INFO] I04: relayed/dropped` |
| I10 | `long_back_to_back` | 3 × **1472 B 满帧**背靠背（帧长 1486，帧间 1 拍）→ 同守恒判据 + 逐字节正确；打 `[INFO] I10: relayed/dropped`。这是"2-bank + 暂存转发"吞吐上限真正会顶到的位置（I04 的短帧压不到） |
| I11 | `fcs_tail` | MAC 未剥 FCS：帧尾多 4 B + `rx_dv` 连续 → relay **仍严格 = `total_len`(128)**、逐字节正确、FCS 不得计入 IP 包；`o_wr_frame_cnt` 只 +1 |
| I13 | `runt_then_good` | 12 B 碎片 → 1 拍空档 → 正常帧：碎片计 `DROP_TRUNCATED`，正常帧照常逐字节转出（残留状态不卡死后面） |
| I14 | `preamble_sfd` | ★**2026-11-12 板上缺陷回归**：`7×0x55 + 0xD5` 与 MAC 头**同一 `rx_dv` burst**（150 B 连续）→ relay 仍 = 128 B IP 包；`o_wr_frame_cnt` +1（前导从未进缓冲） |
| I15 | `preamble_two_frames` | 连续两帧都带前导（帧间 1 拍）→ 两帧都逐字节正确、`o_wr_frame_cnt` +2（对齐器帧尾不死锁） |
| I06 | `rewrap_aur_1472` | `aur_data/aur_en` 送 1472 B IP → `lan` = `PEER_MAC/BOARD_MAC/0x0800` + 原包逐字节，总长 1486 |
| I07 | `rewrap_aur_26_pad` | 26 B IP → `lan` 60 B，第 40..59 字节全 0 |
| I08 | `counters_clean` | 两域 19 个计数器逐一比对（含 `st_rx_frames/st_rx_drop/st_drop_*` 不被误加、`st_aur_bad_v4=0`） |
| I09 | `sideband_follows_frame` | **背靠背**「广播 ARP」+「BOARD_MAC/0x0800/dst=PEER_IP」→ 第 2 帧必须被正确转发、`st_arp=1`、`st_relay=1`。旧旁路嗅探器会把第 2 帧判成 ARP（这就是 v2 侧带 bug 的最小复现） |

### 3.3 帧缓冲 TB `tb_p2_frame_buf.v`（4 条）

| # | 用例 | 断言要点 |
|---|---|---|
| FB01 | `two_frames_buffered` | 写 2 帧而读侧不消费 → `o_wr_frame_cnt=2`、`o_wr_drop_cnt=0`、两 bank 都忙 |
| FB02 | `third_frame_whole_drop` | 再来第 3 帧 → `o_wr_drop_cnt=1`、`o_wr_frame_cnt` 仍为 2（**没存半帧**） |
| FB03 | `read_two_frames_bytewise` | 放开读侧 → 只读出 2 帧、两帧**逐字节正确**（证明丢的是整帧） |
| FB04 | `sideband_follows_frame` | 两帧 MAC/EtherType 不同 → 读侧侧带各自正确（v2 `o_rd_eth_dst/o_rd_eth_type` 跟帧走） |

---

## 4. 怎么跑

```powershell
# 一键跑全部三个 TB（推荐）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_13\sim\p2\run_p2_sim.ps1

# 只跑某一个（unit | framebuf | relay）
...\run_p2_sim.ps1 -Only relay

# 带清理 / 换 Vivado 版本
...\run_p2_sim.ps1 -Clean
...\run_p2_sim.ps1 -VivadoBin D:\Xilinx\Vivado\2023.1\bin
```

三个 TB 各自独立 `xvlog → xelab → xsim`（每个 TB 前都删 `xsim.dir`，坑 #48），
判据行分别是 `P2_TB:` / `P2_FRAMEBUF_TB:` / `P2_RELAY_TB:`，汇总一行：
`P2_SIM: PASS (unit=<n> relay=<m> framebuf=<k>)`，任一 FAIL 则退出码非 0。

脚本行为（PS 5.1 兼容，**纯 ASCII**，中文只在本 README 里）：

1. 串行检查：`Get-Process` 发现 `vivado/xsim/xvlog/xelab` 任一在跑就直接拒跑（exit 4），
   不跟别人抢（本机 Vivado 全局串行）；`-AllowConcurrent` 可跳过。
2. 路径 ASCII 守卫：脚本目录/rtl 目录/Vivado bin/TEMP 有非 ASCII 字符就拒跑（exit 3）。
3. `TEMP=TMP=D:\FPGA\.tmp`；**每次**先删 `xsim.dir`（坑 #48：中断的 xvlog 会写坏共享 work 库）。
4. `xvlog`（不加 `-sv`）→ `xelab -debug typical … -s p2_sim` → `xsim p2_sim -runall`，
   输出全部落文件再 `Select-String`（不管道直取）。
5. 抓 `P2_TB: PASS=<n> FAIL=<m>`：解析不到 → exit 20；`FAIL!=0` → exit 1；
   `PASS<21` → exit 23；全 PASS → **exit 0**。
6. 额外把 elaboration 的 `not connected / remains unconnected` 当阻塞错误（exit 12）——
   本机验证过一次"忘了接 clk/rst_n"就是这样被抓到的。

退出码：`0` 全 PASS / `1` TB FAIL / `4` 有别的 Vivado 在跑 / `10` xvlog 失败 /
`11` xelab 失败 / `12` 端口未接 / `20` 无判据行 / `22` xsim 非 0 / `23` 用例数不足。

---

## 5. 本次实跑命令与结果

```powershell
PS> powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_13\sim\p2\run_p2_sim.ps1 -Clean
serial check: no vivado/xsim/xvlog/xelab running
TEMP/TMP   : D:\FPGA\.tmp

=== unit : tb_p2_pipeline ===        xvlog 0 / xelab 0 / xsim 0
  P2_TB: PASS=23 FAIL=0
=== framebuf : tb_p2_frame_buf ===   xvlog 0 / xelab 0 / xsim 0
  P2_FRAMEBUF_TB: PASS=5 FAIL=0
=== relay : tb_p2_relay_top ===      xvlog 0 / xelab 0 / xsim 0
  [INFO] I04: relayed=3 dropped=0 (throughput-limited, documented)
  P2_RELAY_TB: PASS=8 FAIL=0

=== RTL under test (SHA256) ===
  ipv4_packet_extract.v    CEBDAB5E0C849BF6632E93D0C63542A44F01401078DB4B40F23AEA1A767860B4  (17640 B)
  eth_rewrap.v             0C19024593342197285E02021114F678E721A6BD714CC7B8604DC1DFECC7DC32  (10165 B)
  local_steer.v            7CC36DC45911F289051045C9A580FA4DB7CEE63F362749F86BD223CE9105F0A9  (10168 B)
  p2_frame_buf.v           77FC6E622D98B33555A3715FE8AF542EEE714F6780113F4B79DD17BE15800153  (9641 B)
  p2_relay_top.v           17D303F518DE6694A6FC596E4FA2A68EB6552AD33273739E54688D139C85AD83  (12296 B)

P2_SIM: PASS (unit=23 relay=8 framebuf=5)
```

- 全套墙钟 **20 s**（3 TB × xvlog/xelab/xsim）；9 份日志 **零 WARNING / 零 ERROR / 零 `[DET]`**
- 仿真结束时刻：unit `1,080,950 ns` / framebuf `42,810 ns` / relay `375,080 ns`
- `I04` 实测 **`relayed=3 dropped=0`**（守恒 `3+0==3`）：先前"第 3 帧会丢"的预判被实测推翻
  （短帧下 extract 的 `S_SEND`=128 < 帧长 142，写侧反而更慢，压不到上限）
- 每次运行自动重写 `RTL_SHA256.txt`（5 个 RTL 的内容哈希）：**测的是哪版 RTL 可自证**，
  位流候选登记直接抄，不信 mtime
- 归档：`../../out/evidence_2026-11-08_p2_sim/handbook_3tb/`（runner stdout + 9 份原始日志 + 3 份判据抽取）
- `I10`（3 × 1472 B **满帧**背靠背）**已实跑**：`P2_RELAY_TB: PASS=9 FAIL=0`（exit 0，7.3 s，
  `$finish` 815,405 ns），实测 **`[INFO] I10: relayed=3 dropped=0`** —— 满帧 3 连发也全部转出
  （守恒 3+0==3）。**边界**：这只是一个数据点（3 帧满帧背靠背 n/3），**不可外推**成"任意连发安全"；
  上限要去 >3 连发或"帧长卡 bank 边界"的用例里找。
- 注意 `-Only relay` 时汇总行是 `P2_SIM: PASS (unit=0 relay=9 framebuf=0)`，`unit/framebuf=0`
  表示**本次未跑**；完整登记值应为 **unit=23 / framebuf=5 / relay=9**

---

## 6. 设计要点与取舍（评审请看这里）

### 6.1 为什么 `ipv4_packet_extract` 是 store-and-forward，不是切通

契约要求被 DROP 的帧**不产生任何输出字节**，而 `eth_rewrap` 没有 abort 口——一旦漏出
半包，PC 侧就会看到 runt/残帧。检查 1/7（帧长相关）只有到 `eop` 才知道结果，所以任何
"边收边发"的切通实现都无法保证零输出。故本模块把帧存进 `BUF_DEPTH` 字节缓冲区
（默认 `14+1500` 上取整到 64 = 1536 B），判决通过后再流出。

- 收益：坏帧零泄漏（C11 + 变异测试 M4 就是验证这条）。
- 代价：单帧 50% 占空（收一段、发一段），1 Gbps 线上行速率上限约 500 Mbps。
  要恢复线速可在上层做双缓冲乒乓，或给下游加 abort 口后改切通——属集成阶段的事。
- TB 里这条被 `out_bytes`（总字节数）断言钉住，不是"看起来没输出"。

### 6.2 事件脉冲的时序契约（顶层集成必须知道）

`o_frame_pulse` / `o_drop_pulse` / `o_drop_reason` 是**组合**的，在 `S_VRD` 那**一拍**高，
它**先于**第一个输出字节（`S_SEND` 从下一拍开始）。所以顶层要用这一拍锁存判决结果/
drop reason，到 `S_SEND` 首拍时已经稳定。若把脉冲寄存到 `S_SEND` 同拍，上层就没有建立时间了
（本 TB 的 glue 正是这样用的，可作参考）。

`o_parse_pulse` = `(state==S_SEND) && m_eop && m_ready`，即 `m_eop` 握手拍，可直接当
"本包已成功转发"的记账脉冲。

### 6.3 checksum 边界：0xFFFF 那一端为什么是"必须被拒"

任务书要求 `checksum 结果 0xFFFF / 0x0000 两种边界各 1 例`。实测/证明：

- `checksum 字段 = 0x0000` ⇔ "其余字段的折叠和 = 0xFFFF"——**可达**，且合法头必须被接受。
  天真实现若把 0x0000 当"未计算/不校验"就会漏检，故 C17 专门钉它。
- `checksum 字段 = 0xFFFF` ⇔ "其余字段的折叠和 = 0x0000"。而 IPv4 头首字节
  `version/ihl = 0x45` 恒非零；反码折叠对**非零**原和只在 `0xFFFF` 处表示零
  （`k*0xFFFF → 0xFFFF`，`0xFFFF+m → 0x0001+m`，只有原和恰为 0 才折出 `0x0000`）。
  所以**合法** IPv4 头不可能出现 0xFFFF 这个字段值——这个端点只能作为"必须被拒"的
  非法向量存在。C18 就是强改字段为 0xFFFF 后断言 `reason=BAD_CSUM` 且向量确实非法
  （TB 自查折叠和既不是 0xFFFF 也不是 0x0000，避免测试向量本身退化）。
- RTL 侧 `csum_ok` 同时接受折叠结果 `0xFFFF` 与 `0x0000`（反码里两者都是"零"），
  这是按标准写的，不是宽松。

### 6.4 其它已知边界

- `local_steer` 的 `PROXY_ARP_EN` 与 `PC_IP` 本版**对判决无影响**：代理 ARP 应答件
  不在本轮范围；参数先按契约占位（板 A/B 两套值写在参数注释里）。
- `eth_rewrap` 在输入比 `i_pkt_len` 长时会以输入实际 `eop` 结束并拉 `o_len_err`；
  比 `i_pkt_len` 短时补零到 `m_frame_len` 后结束并拉 `o_len_err`。TB 断言全程 `o_len_err=0`。
- 未做 IP options 的专门用例（`ip_hdr` 支持 `ihl>5`，选项区填 NOP；checksum 覆盖整头）。
- 未做"背靠背无间隙"专门用例，但驱动端 `run_frame` 不等空闲就连发下一帧，
  C14 连发 3 帧即为该形态。

---

## 7. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-08 | 首版：三件套 RTL（v0.2 契约）+ 21 例自检 TB + 一键脚本；xsim 21/21 PASS；4 组变异测试验证断言有牙。LOCAL 分支（C19/C20）在本轮自查"cnt_local 全程为 0 = 断言空跑"后补上 |
| 2026-11-08（二） | 地址方案切 **handbook §8 的 10.10.0.x**；加 C22（旧 192.168.50.11 → DROP_UNKNOWN_DST）、C23（用**不带参数覆盖**的实例验 RTL 默认值 + 字节序）；unit 23 例 |
| 2026-11-08（三） | 新增集成层两个 TB：`tb_p2_relay_top`（9 例，双时钟）+ `tb_p2_frame_buf`（5 例）；runner 改表驱动跑 3 个 TB 并**自动打印 5 个 RTL 的 SHA256**；I04 改成守恒判据，新增 I10（满帧背靠背）；实测 unit 23 / framebuf 5 / relay 9（I10 实测 3/3、0 丢） |
| 2026-11-12 | 板上实测抓到真因：`gmii_rxd` 帧含 7 B 前导 + 1 B SFD，裸喂缓冲导致侧带 `eth_dst=55…` → DROP_MAC → `pfwd_wr≡0`。Lead 在 `p2_relay_top` 加自适应前导对齐器后，本组新增 **I11（FCS 尾）/ I13（碎片→正常帧）/ I14（前导+SFD，连续 burst 形态）/ I15（两帧都带前导）**；`I01` 无前导向量保留作"自适应不误伤"回归；撤销 I12（帧内 dv 空洞非病根）。实测 **unit 23 / framebuf 5 / relay 13**，exit 0，35.3 s |

### 本轮踩到的坑（写下来免得重犯）

| 坑 | 现象 | 正确做法 |
|---|---|---|
| `buf` 是 Verilog 保留字 | `xvlog`: `syntax error near 'buf'` / `Verilog 2000 keyword 'buf' used in incorrect context` | 数组名别用 `buf`（本次改 `pkt_buf`） |
| wire 先用后声明 | `xvlog`: `identifier 'v_drop_now' is used before its declaration` | 组合辅助信号先声明/先赋值，`assign` 放到判决逻辑之后 |
| 端口漏接 | xelab WARNING `port 'clk' is not connected`（不报错、仿真照样跑，但计数器全死） | 脚本把 `not connected` 当阻塞错误（exit 12） |
| `local_steer` 漏写 `clk/rst_n` | 计数器组没有时钟 | 公共约定要求所有模块端口固定带 `clk/rst_n` |
| xvlog 自己的日志叫 `xvlog.log` | 重定向到同名文件 → `CRITICAL WARNING [Common 17-183] Failed to open handle xvlog.log` | 重定向到 `*_console.txt`，别跟工具的日志同名 |
| **用 PowerShell 改含中文的源码** | `Set-Content -Encoding ASCII` 把中文注释全变 `?`、还吞了换行 → 只能整文件重写 | 改源码**只用** `edit`/`write` 工具，别用 PS 文本 I/O（PS 5.1 读无 BOM UTF-8 会按 GBK 解） |
