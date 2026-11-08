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
| `rtl/p2/local_steer.v` | `local_steer` | 组合判决 DROP/LOCAL/RELAY/ARP（§2.5 全表）+ 32 bit 粘滞计数器组 | `BOARD_MAC/IP`、`PEER_IP`、`PC_IP`、`PROXY_ARP_EN=0` |
| `sim/p2/tb_p2_pipeline.v` | `tb_p2_pipeline` | 三段串起来的自检 TB（含 glue 与参考计数器模型） | — |
| `sim/p2/run_p2_sim.ps1` | — | 一键 xvlog→xelab→xsim，抓 `P2_TB: PASS=` 判据 | — |

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

## 3. 用例表（`tb_p2_pipeline.v`，21 条）

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
| C21 | `global_counters_clean` | 全局收尾 | 21 帧后 14 个计数器/输出字节数/`o_len_err` 全对，并断言 `cnt_local==2`（防 LOCAL 分支空跑） |

**每例都做的三件事**：(1) 14 个计数器逐一对参考模型；(2) 判决/元数据逐字段比对；
(3) rewrap 输出**帧数 + 总字节数 + 逐字节**比对。第 (3) 条的"总字节数"是关键——
它把"没有完整帧"升级成"一个字节都没漏"，否则切通实现的半包泄漏查不出来。

---

## 4. 怎么跑

```powershell
# 一键（推荐）
powershell -NoProfile -ExecutionPolicy Bypass -File D:\FPGA\prj\project_13\sim\p2\run_p2_sim.ps1

# 带清理 / 换 Vivado 版本
...\run_p2_sim.ps1 -Clean
...\run_p2_sim.ps1 -VivadoBin D:\Xilinx\Vivado\2023.1\bin
```

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
xvlog exit = 0
xelab exit = 0
xsim exit = 0
[PASS] C01_normal_relay_1472
...
[PASS] C21_global_counters_clean
P2_TB: PASS=21 FAIL=0
P2_SIM: PASS (PASS=21 FAIL=0)
```

- 仿真结束：`$finish called at time : 1065250 ns`
- 墙钟 6.5 s（三步合计）；xvlog/xelab/xsim **零 WARNING**
- 原始日志：`p2_xsim_console.txt`、`run_p2_sim.log`、`xsim.log`（同目录）
- 归档：`../../out/evidence_2026-11-08_p2_sim/`（含 `SHA256SUMS.txt` 与 4 份变异测试日志）

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

### 本轮踩到的坑（写下来免得重犯）

| 坑 | 现象 | 正确做法 |
|---|---|---|
| `buf` 是 Verilog 保留字 | `xvlog`: `syntax error near 'buf'` / `Verilog 2000 keyword 'buf' used in incorrect context` | 数组名别用 `buf`（本次改 `pkt_buf`） |
| wire 先用后声明 | `xvlog`: `identifier 'v_drop_now' is used before its declaration` | 组合辅助信号先声明/先赋值，`assign` 放到判决逻辑之后 |
| 端口漏接 | xelab WARNING `port 'clk' is not connected`（不报错、仿真照样跑，但计数器全死） | 脚本把 `not connected` 当阻塞错误（exit 12） |
| `local_steer` 漏写 `clk/rst_n` | 计数器组没有时钟 | 公共约定要求所有模块端口固定带 `clk/rst_n` |
| xvlog 自己的日志叫 `xvlog.log` | 重定向到同名文件 → `CRITICAL WARNING [Common 17-183] Failed to open handle xvlog.log` | 重定向到 `*_console.txt`，别跟工具的日志同名 |
| **用 PowerShell 改含中文的源码** | `Set-Content -Encoding ASCII` 把中文注释全变 `?`、还吞了换行 → 只能整文件重写 | 改源码**只用** `edit`/`write` 工具，别用 PS 文本 I/O（PS 5.1 读无 BOM UTF-8 会按 GBK 解） |
