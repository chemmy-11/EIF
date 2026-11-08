# M1 · prj13 · P2 透明 IPv4 转发 RTL 接口契约（v0.2）

- **日期**：2026-11-08
- **状态**：v0.2 契约（离线实现依据）。**不含集成、不含上板**；RTL 代码见 `prj/project_13/rtl/p2/`，TB 见 `prj/project_13/sim/p2/`。
- **上游依据**：
  - 交付仓 issue #10「[A组] P2 契约改为 IPv4 packet 转发（v0.2）」正文与 3 条评论（尤其「接受域 = 1500，1538 仅缓冲深度」的建议）
  - `GSnFPipe-FPGA-PP: docs/protocol_v1.md` §2.2（地址与 MAC）/ §2.5（A 侧转发模型与 local_steer 判决表）/ §3.1（尺寸预算：A 内部帧上限 1500 B、帧缓冲 1538 B）
  - `prj13_P2开工手册_2026-11-08.md` §3 P0-1 验收清单
- **替代关系**：本文取代 `docs/M1_prj12_P2透明转发候选设计_2026-10-24.md`（v0.1，UDP payload relay + 重建 ETH/IP/UDP）作为实现依据；v0.1 只作迁移参考（迁移清单见 §8）。

---

## 1. 一句话契约

**PC1 → 板 A →（Aurora）→ 板 B → PC2 的 IPv4 包转发：去掉 14 B 以太网头，Aurora 上搬 IP 包原样字节，出光纤时只补一条新以太网头（dst=对端 PC MAC、src=本板 MAC、0x0800）。IP 包内 20..1500 B 一个字节都不改**（src/dst IP、端口、TTL、IP/UDP checksum、DSCP、options、分片字段全保留）。

只转发 `dst == PEER_IP` 的 IPv4；`BOARD_IP` 走本地栈；ARP **只在本地终结，绝不跨板**；其余一律 DROP 并各自计数。

---

## 2. 为什么这样切模块

| 关注点 | 归属 | 理由 |
|---|---|---|
| 以太网帧边界、`total_len` 裁剪 padding、IP 头结构/checksum 校验 | `ipv4_packet_extract` | 都是**字节级**判断，必须在搬字节时同步做，不能等整帧收完再补 |
| 「这个包该去哪」（MAC/ARP/广播/组播/BOARD/PEER/其它） | `local_steer` | **策略层**，纯组合，输入是解析出的元数据；同一份判决表将来也给代理 ARP 用 |
| 出光纤后重建 14 B 头 + 补零到 60 B | `eth_rewrap` | 与 extract 严格对称，只加头不改包 |

三个模块**都不含跨时钟域逻辑**：extract 在 `eth_rxc` 域、rewrap 在 Aurora `user_clk` 域，各自的 `clk` 由上级接；中间那级 CDC 走既有 mem1/mem2 + pack/unpack（复用 prj11 已验证件）。

---

## 3. 公共约定（两模块共用的字节流与编码）

### 3.1 字节流握手（1 byte/beat）

| 信号 | 方向 | 含义 |
|---|---|---|
| `valid` / `ready` | — | `valid && ready` 才算传输一拍 |
| `data[7:0]` | — | 一个字节（网络序，帧内顺序发送） |
| `sop` | — | 该拍是**帧首字节**（以太网帧 = 目的 MAC 第 1 字节；IP 包 = version/IHL） |
| `eop` | — | 该拍是**帧尾字节** |

- **不含**前导码/SFD、**不含** FCS（由 MAC 层负责）。
- 背压安全是硬要求：`ready` 拉低时不得丢字节、不得重复、不得乱序。
- 丢帧/非法帧必须**把该帧字节全部消费到 eop**（只吞不吐），否则下一帧错位。

### 3.2 drop reason 统一编码（4 bit，extract 与 steer 共用）

| 值 | 名称 | 计入计数器的条件 |
|---|---|---|
| 0 | `DROP_NONE` | 不计数（表示「reason 由上游沿给出」或「不是 drop」） |
| 1 | `DROP_VLAN` | EtherType ∈ {0x8100, 0x88A8}（v0.2 不做 VLAN） |
| 2 | `DROP_IPV6` | EtherType = 0x86DD |
| 3 | `DROP_ETHERTYPE` | 其它非 IPv4 EtherType（ARP 0x0806 也走此路，但 ARP 的 LOCAL 记账在 `local_steer`，**不计 drop**） |
| 4 | `DROP_BROADCAST` | IPv4 广播（`255.255.255.255`、`0.0.0.0/8`）或以太网广播且 IP dst 非本板 |
| 5 | `DROP_MULTICAST` | IPv4 `224.0.0.0/4` 或以太网组播（目的 MAC 首字节 bit0=1） |
| 6 | `DROP_UNKNOWN_DST` | IPv4 dst 既不是 `BOARD_IP` 也不是 `PEER_IP`（**防乒乓红线**） |
| 7 | `DROP_OVERSIZE` | `total_len > 1500` |
| 8 | `DROP_BAD_CSUM` | IP 头 checksum ones'-complement 累加 ≠ 0xFFFF |
| 9 | `DROP_TRUNCATED` | 帧长不足（<14+20）、IHL 非法、或可用字节 < 14+`total_len` |
| 10 | `DROP_MAC` | 以太网 dst 既非 `BOARD_MAC` 也非广播/组播（非混杂模式） |

> **接受域（接受范围）裁决**：`total_len ≤ 1500` 为接受域，`1538` 只是帧缓冲深度（issue #10 2026-10-27 评论的建议值，本契约按此实现）。1500 < `total_len` ≤ 1538 的包**一律 DROP_OVERSIZE**，不留灰色地带。

---

## 4. `ipv4_packet_extract`

```verilog
module ipv4_packet_extract #(
    parameter [15:0] MAX_IP_LEN = 16'd1500,
    parameter [47:0] BOARD_MAC  = 48'h02_00_00_00_0A_01
)(
    input  clk, input rst_n,
    input  s_valid, output s_ready, input [7:0] s_data, input s_sop, input s_eop,
    output m_valid, input  m_ready, output [7:0] m_data, output m_sop, output m_eop,
    output [31:0] m_ip_src, output [31:0] m_ip_dst,
    output [15:0] m_total_len, output [15:0] m_ip_id, output [15:0] m_csum,
    output [7:0]  m_proto, output [7:0] m_ttl, output [7:0] m_tos,
    output [3:0]  m_ihl, output [2:0] m_ip_flags, output [12:0] m_frag_off,
    output        m_is_fragment,
    output        o_frame_pulse, output o_parse_pulse,
    output        o_drop_pulse, output [3:0] o_drop_reason
);
```

### 4.1 结构检查顺序（命中即 DROP，一帧只产生一个 reason）

| # | 条件 | reason |
|---|---|---|
| 1 | 帧长 < 14+20 | `DROP_TRUNCATED` |
| 2 | EtherType ∈ {0x8100,0x88A8} | `DROP_VLAN` |
| 3 | EtherType = 0x86DD | `DROP_IPV6` |
| 4 | EtherType ≠ 0x0800 | `DROP_ETHERTYPE` |
| 5 | version≠4 或 IHL<5 或 IHL*4>total_len | `DROP_TRUNCATED` |
| 6 | total_len > `MAX_IP_LEN` | `DROP_OVERSIZE` |
| 7 | 可用帧长 < 14+total_len | `DROP_TRUNCATED` |
| 8 | IP 头 checksum 累加 ≠ 0xFFFF | `DROP_BAD_CSUM` |
| 9 | eth_dst 非 `BOARD_MAC` 且非广播/组播 | `DROP_MAC` |

通过后：输出**恰好 `total_len` 字节**（从以太网第 14 字节起，剥掉以太网 padding），元数据在 `m_sop` 握手一拍起有效、保持到 `m_eop`。

### 4.2 元数据字段（供 `local_steer` 与将来 upper layer 使用）

`m_ip_src/m_ip_dst`（大端装配）、`m_total_len`、`m_ip_id`、`m_csum`（收到的原值）、`m_proto`、`m_ttl`、`m_tos`、`m_ihl`、`m_ip_flags[2:0]`（bit1=MF，bit2=DF）、`m_frag_off[12:0]`、`m_is_fragment = MF | (frag_off≠0)`。

---

## 5. `eth_rewrap`

```verilog
module eth_rewrap #(
    parameter [47:0] SRC_MAC = 48'h02_00_00_00_0A_01,  // BOARD_MAC
    parameter [47:0] DST_MAC = 48'h00_00_00_00_00_00,  // PEER_MAC（对端 PC 的 MAC）
    parameter [15:0] MIN_FRAME_LEN = 16'd60
)(
    input  clk, input rst_n,
    input  s_valid, output s_ready, input [7:0] s_data, input s_sop, input s_eop,
    input  [15:0] i_pkt_len,
    output m_valid, input m_ready, output [7:0] m_data, output m_sop, output m_eop,
    output [15:0] m_frame_len, output o_len_err
);
```

输出帧 = `dst_mac(6) + src_mac(6) + 0x0800(2) + IP 包原样 + 0 填充`，`i_pkt_len` 在 `s_sop` 握手拍给出；`14+i_pkt_len < MIN_FRAME_LEN` 时补 `0x00` 到 60 B（不含 FCS 的最小以太网帧）。`o_len_err` 在 `i_pkt_len` 与实际字节数不符时脉冲（仍按实际字节输出，不吞帧）。

**方向说明（易错）**：板 A 的 `eth_rewrap` 用的 `DST_MAC` 是**对端 PC2 的 MAC**，不是板 A 自己的 MAC —— 包是从板 A 的网口发给 PC2 的。

---

## 6. `local_steer`

### 6.1 组合判决部分

```verilog
input  [47:0] i_eth_dst; input [15:0] i_eth_type; input [31:0] i_ip_dst;
input  [15:0] i_ip_total_len; input i_ip_hdr_ok; input [15:0] i_frame_len;
output [2:0]  o_decision;      // 0=DROP 1=LOCAL 2=RELAY 3=ARP
output [3:0]  o_drop_reason;
```

**判决优先级（自上而下，命中即停）**

| 序 | 条件 | 判决 | 说明 |
|---|---|---|---|
| 1 | `i_eth_type == 0x0806` | `ARP` | 任何 opcode 都交本地 ARP；`PROXY_ARP_EN=1` 且 target==PEER_IP 时用 `BOARD_MAC` 代理应答；**永远不 RELAY** |
| 2 | 以太网广播 且 非 ARP | `i_ip_dst==BOARD_IP` ? LOCAL : `DROP_BROADCAST` | 广播绝不跨板 |
| 3 | 以太网组播 | `DROP_MULTICAST` | |
| 4 | `i_eth_dst ≠ BOARD_MAC` 且非广播/组播 | `DROP_MAC` | 非混杂模式 |
| 5 | `i_ip_hdr_ok == 0` | `DROP` + `DROP_NONE` | reason 由上游（extract）沿给出 |
| 6 | `i_ip_dst == 255.255.255.255` 或 `i_ip_dst[31:24]==0` | `DROP_BROADCAST` | |
| 7 | `i_ip_dst[31:28] == 0xE` | `DROP_MULTICAST` | `224.0.0.0/4` |
| 8 | `i_ip_dst == BOARD_IP` | `LOCAL` | 本地 IP 栈（ping/管理） |
| 9 | `i_ip_dst == PEER_IP` | `RELAY` | 唯一允许跨板的目的 IP |
| 10 | 其它 | `DROP_UNKNOWN_DST` | **防乒乓红线**：不允许「非本板 IP 都转发」 |

> 反馈环注意：`o_decision` 只依赖**头字段**，不依赖 extract 的输出流，也不回灌 extract 的元数据，因此「metadata → 判决 → 是否转发」是纯前馈，无组合环。

### 6.2 计数器组（32 bit 粘滞、`clk` 域、`rst_n` 清零）

脉冲输入：`i_frame_pulse`、`i_relay_pulse`、`i_local_pulse`、`i_arp_pulse`、`i_drop_pulse + i_drop_reason[3:0]`。

| 输出 | 含义 | 手册/契约对应 |
|---|---|---|
| `o_cnt_rx_frames` | 收到以太网帧总数 | §6.7 `rx_frames` |
| `o_cnt_relay` | 转发出去的 IP 包数 | `rx_relay` |
| `o_cnt_local` | 交本地 IP 栈的包数 | `rx_local_ip` |
| `o_cnt_arp` | 本地终结的 ARP 帧数 | `rx_arp_local` |
| `o_cnt_drop_vlan` … `o_cnt_drop_mac` | 10 类 drop（见 §3.2 表 1–10） | `rx_drop_*` |

链路侧计数器（`aurora_channel_up` / `hard_err` / `soft_err` / `tx_frames` / `rx_frames` 对端）**不属于本轮三个模块**：它们挂在 Aurora 域，属 V4 集成时的顶层计数块（§7.2）。

---

## 7. 集成点（V4 上板阶段才做，本轮不动）

### 7.1 现状（读码依据）

- 以太网 RX 字节流：`gmii_rxd[7:0] + gmii_rx_dv`（`eth_rxc` 域，`rgmii_rx_fix2` 输出）；官方栈的 `arp_rx/icmp_rx/udp_rx` **并行嗅探**这条流（`rtl/aurora_mem_bridge.v:106-107`）。
- 本地栈 TX 入帧泵：`stack_txd/stack_tx_en`（`eth_ctrl` 输出 → 泵A，`aurora_mem_bridge.v:108-109`）。
- PC 侧 TX：帧泵B `rgmii_txd_i/rgmii_tx_en_i` → W5 命令注入 mux → `gmii_to_rgmii`（`aurora_mem_bridge.v:130-133`）。
- 旧回显：`assign des_mac = src_mac; assign des_ip = src_ip;`（`aurora_mem_bridge.v:163-164`）—— P2 必须**关闭**这条，否则转发与回显并存会出现重复帧/乒乓。

### 7.2 要改的三处（不在本轮）

| # | 位置 | 改动 | 风险 |
|---|---|---|---|
| 1 | `gmii_rxd/gmii_rx_dv` 出口 | 接 `ipv4_packet_extract` + `local_steer`；RELAY 帧写 mem1，LOCAL 帧维持给官方栈 | 与官方栈并存（嗅探型），不能抢走本地栈需要的帧 |
| 2 | `stack_txd/stack_tx_en` 之前 | 加「本地栈帧 / relay 帧」优先级 mux，relay 不占用 UDP 命令通道 | 与 W5 命令通道仲裁冲突（`cmd_takeover` 空闲拍注入法） |
| 3 | 帧泵B 出口 | 接 `eth_rewrap`（`dst=PEER_MAC`） | 与栈自发 ARP/ICMP 应答共用 RGMII TX，需优先级 mux；`<60 B` 补零 |
| 4 | **本地栈应答出板路径（本轮新发现，必做）** | 让 `dst=BOARD_IP` 的 LOCAL 帧从**本板 GE2** 出去，而不是走 Aurora | 见 §7.3：当前所有栈 TX 字节只进 `u_pump_fwd`，本地应答根本回不到本板 PC |

### 7.3 本地栈应答出板路径缺失（2026-11-08 读码确认，L2）

**事实链**（`rtl/aurora_mem_bridge.v`，逐行可核）：

- `:676-677` `u_eth_ctrl` 的 `.gmii_tx_en/.gmii_txd` 直接连 `stack_tx_en/stack_txd`；
- `:823-829` `u_pump_fwd` 的 `.wr_data/.wr_en` 就是 `stack_txd/stack_tx_en` → 栈的所有 TX 字节都写进 Aurora 前向帧泵；
- `:163-164` `assign des_mac = src_mac; assign des_ip = src_ip;` 是 P1 的"回显/自反"语义，P2 必须关掉；
- 结论：**当前位流根本没有"本地栈帧出本板 GE2"的通路**。P1 期间 PC1 能收不到板卡 ARP 应答（所以必须配静态 ARP）、ping 板卡不通，都是这条的必然结果 —— 不是配置问题。

**对 P2 的影响**：契约 §2.5 的 `dst==BOARD_IP → LOCAL`（`protocol_v1.md:133`）只完成"判决"，**不自动等于"ping 得通"**。V4 集成必须新增一条「LOCAL 帧 → 本板 RGMII TX mux」的通路（可复用 W5 命令通道的末级注入法，`rgmii_txd_i → rgmii_txd_o` 那级 mux），否则 P2 的「`BOARD_IP` 走本地栈」在板上不可观测，与「P1 跨板 ping 不通、P2 才通」的判据冲突。

**本轮状态**：仅记录 + 判据口径，**不改 RTL**（P0-1 明确禁止动 `aurora_mem_bridge.v` 接线）。

---

## 8. 与 v0.1 候选设计的迁移清单

| v0.1 | v0.2 | 动作 |
|---|---|---|
| `udp_payload_extract.v` | `ipv4_packet_extract.v` | 吃整帧、按 `total_len` 裁剪、不解析 UDP |
| `relay_tx.v`（重建 ETH/IP/UDP，UDP csum=0） | `eth_rewrap.v` | 只加 14 B 头，不重建 IP/UDP、不写 checksum |
| `local_steer.v`（UDP 端口分类） | `local_steer.v`（IP dst 分类） | 判决改 BOARD/PEER/其它 + ARP 本地 |
| `p2_candidate/sim/*` 三个 TB | `sim/p2/tb_p2_pipeline.v` | **旧 v0.1 的 PASS 不再作为 v0.2 证据**（issue #10 明确） |

---

## 9. 验收映射（P0-1 → TB 用例）

| 手册验收项 | TB 用例 |
|---|---|
| 正常转发逐字节相同（1472 B） | `normal_1472` |
| 9 类 DROP 各自计数 | `drop_vlan` / `drop_ipv6` / `drop_ethertype` / `drop_broadcast` / `drop_multicast` / `drop_unknown_dst` / `drop_oversize` / `drop_bad_csum` / `drop_truncated` |
| ARP 不跨板 | `arp_local`（广播 ARP request → `o_decision==3`、无 rewrap 输出） |
| 无乒乓 | `no_pingpong`（8.8.8.8 ×3 → 全 DROP、输出 0 帧） |
| <60 B 补零 | `pad_26`（26 B IP 包 → 60 B 帧、尾部全 0） |
| 分片透传 | `frag_passthrough`（MF=1 + offset≠0 逐字节相同、不重组） |
| （补充）背压不丢字节 | `backpressure` |
| （补充）checksum 边界 | `csum_edge`（0xFFFF / 0x0000 边界） |

---

## 10. 待确认（列出，不自拍板）

1. **地址方案**：本契约参数默认值取 `protocol_v1.md` §2.2 的 `192.168.50.x` + `02:00:00:00:0A:01/0B:01`；开工手册 §8 建议 `10.10.0.1/.2` + 板卡管理 `.11/.12`。两处不一致，需项目负责人裁决后同步三处（protocol_v1.md / RTL 参数 / PC 脚本默认值）。
2. **可靠性归属**：「FPGA 只透传，ARQ/SACK/RTO 在 PC 侧」需 B 组书面确认；若要求 FPGA 重传，P2 范围与排期都要重排。
3. **坏 IP header checksum**：本契约按 issue #10 契约 **DROP 并计数**；若 B 组依赖端到端校验希望照转，需改一行判决并重跑 TB（成本很低，但要先定）。
4. **分片**：本轮透传不重组，需 B 组确认分片粒度 ≤ MTU（1500），否则出现「单个分片合法但整包超 1500」的场景不受本契约保护。

---

## 11. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-08 | v0.2 首版：按 issue #10 + protocol_v1 §2.2/§2.5/§3.1 定义三模块接口、drop 编码、判决优先级、计数器清单、验收映射、集成点与 4 项待确认 |
| 2026-11-08 20:40 | **地址裁决**：项目负责人定 `10.10.0.x`（开工手册 §8），RTL 参数与 PC 脚本默认全部切换；`protocol_v1.md` §2.2 留成品阶段同步 |
| 2026-11-08 21:10 | v0.3：新增 §12 顶层集成（已落地）与 §13 已知限制（含集成级 TB 实测数） |

---

# 12. 顶层集成（2026-11-08 落地，v0.3）

> 本节把 §7 的"集成点"从计划变成事实。改动集中在 `rtl/aurora_mem_bridge.v` 的 4 处 +
> 两个新文件；Aurora / DDR / 内存桥 / 软核控制面主体一字未动。

## 12.1 新增文件（集成层，不属于三个单元件）

| 文件 | 作用 |
|---|---|
| `rtl/p2/p2_frame_buf.v` | 单时钟、2 bank（各 2 KB）、**整帧粒度**弹性缓冲 + 侧带（每帧 eth_dst/eth_type 跟帧走）。银行满/超容量时**整帧丢弃**并计数，绝不留半帧 |
| `rtl/p2/p2_relay_top.v` | 集成封装：以太侧 `rx→buf→extract→steer→relay 门控`；Aurora 侧 `unpack→buf→rewrap→mem2 写` |

## 12.2 为什么必须有 `p2_frame_buf`（这是集成里最容易被漏掉的一环）

链路两侧的**生产者都不支持反压**：

- 以太网 MAC 侧 `gmii_rxd/gmii_rx_dv` 按线速到达，不能暂停；
- Aurora 解包侧 `axis_word_unpack.out_valid` **没有 ready 口**（`rtl/axis_word_unpack.v:163-193`：帧内零空拍、帧间恰好 1 拍 gap）。

而三个单元件是 valid/ready 字节流（extract 整帧收完再发、rewrap 先吐 14 B 头）。直连必在**帧中间**丢字节 → 残帧上电路，比丢整帧恶劣得多。`p2_frame_buf` 就是那道"要么整帧、要么整帧丢"的闸门。

**侧带随帧走**（`o_rd_eth_dst/o_rd_eth_type`）：判决要 eth_dst/eth_type，而这两个字段只在帧首 14 B。若在缓冲外面旁路嗅探，第二帧的帧首会在第一帧还在读侧时覆盖嗅探寄存器 —— 背靠背帧就误判（集成 TB 的 `I09` 专门钉这条）。

## 12.3 `aurora_mem_bridge.v` 的四处改动

| # | 位置 | 改动 |
|---|---|---|
| 1 | 参数区 | `BOARD_MAC=02:00:00:00:0A:01`、`BOARD_IP=10.10.0.11`、新增 `PEER_MAC/PEER_IP/PC_IP`（板 B 只换参数） |
| 2 | `u_pump_fwd.wr_data/wr_en` | `stack_txd/stack_tx_en` → `p2_relay_txd/p2_relay_tx_en`（**转发流**） |
| 3 | `u_mem2.wr_data/wr_en` | `unpack_data/unpack_en` → `p2_lan_txd/p2_lan_tx_en`（**已重加 14 B 头的完整以太帧**） |
| 4 | RGMII TX 末级 mux | 新增 `stack_takeover`（本地栈应答局域网直出），优先级 `cmd > stack > relay` |

**关键语义变化（★必读）**：栈 TX 不再进 Aurora。P1 的"跨板回声"结构上消失（不再有 `des_mac=src_mac` 的回声帧跨板），本地应答（ARP/ICMP/管理 UDP）因此真的能回到本板 PC —— 这就是 §7.3 记的缺口被补上的方式。`des_mac = src_mac` 保留，因为对**本地**应答它恰好是正确的以太网目的地址。

## 12.4 回程为什么把 `eth_rewrap` 放在**内存桥②之前**

`eth_rewrap` 吐 14 B 头时 `s_ready=0`；帧泵B 读侧没有反压口。放在泵B **之后**每帧必丢 14 字节。放在桥② **之前**，泵B 拿到的已经是完整以太帧，与 P1 回程路径逐位同构（P1 泵B 也是原样吐桥② 内容）。

`i_pkt_len` 在本集成里**钉 0**：它只用于算 `tot_len`，而 `tot_len` 只影响"是否补零到 60 B"与结尾判据。钉 0 ⇒ `tot_len=60` ⇒ IP 包 <46 B 补零到 60（正确）、≥46 B 到真实 eop 就结束（正确）。线上字节完全正确，只有它自己报的 `m_frame_len/o_len_err` 无意义（不接、不判）。

---

# 13. 验证矩阵与已知限制（截至 2026-11-08 21:10）

## 13.1 已验证（离线，判据分级按 AGENTS §6a）

| 层 | 判据 | 结果 | 证据 |
|---|---|---|---|
| 单元 | 三件套 23 例 | **PASS 23/0** | `sim/p2/` runner；`out/evidence_2026-11-08_p2_sim/handbook_3tb/` |
| 单元 | 帧缓冲 5 例（含超容量整帧丢弃） | **PASS 5/0** | 同上 `framebuf_*` |
| 集成 | relay_top 9 例（含 ARP/背靠背/满帧/侧带） | **PASS 9/0** | 同上 `relay_*`、`relay_verdict.log` |
| 集成 | **I04** 3×142 B 背靠背 | `relayed=3 dropped=0` | 同上 |
| 集成 | **I10** 3×1472 B 满帧背靠背 | `relayed=3 dropped=0` | 同上 |
| 综合 | `synth_design` 2023.1 | **0 Error / 0 Critical Warning**，2:48 墙钟，Checksum `a31ff1a4`，5 个 ILA 核插入 | `out/synth13_p2b.log`（`SYNTH_OK`/`SYNTH_DCP_OK`） |

## 13.2 已知限制（写进候选位流说明，V4 上板前必须知道）

1. **吞吐上限未触到（未被证伪，也未证明够用）**：`2-bank 整帧缓冲 + 暂存转发`，实测 **3 帧 × 1472 B 满帧背靠背 3/3 无丢**（I10）。**不外推**成"任意连发安全" —— >3 连发、或帧长刚好卡 bank 边界的情形未测；需要时加 `5–8 帧` 用例钉。丢帧语义是**整帧丢并计数**（`st_rx_drop`），不会残帧。
2. **`stack_takeover` 抢帧风险**：本地栈应答与回程帧同一拍起帧时，被抢占那一帧会坏（与 W5 命令注入同类，已在 `aurora_mem_bridge.v` 的该段注释登记）。表现是 PC 侧该帧丢失/校验错，**不会静默通过**。
3. **非法 IPv4 帧仍会透传**：Aurora 侧收到的帧若首字节 `version!=4`，`st_aur_bad_v4` 计数但仍会加头送出，由 PC 侧 IP 层丢弃。Aurora 是点对点带 CRC 链路，正常不会出现；作为已知边界登记。
4. **P2 计数器本候选未挂 ILA**：11 个 drop 计数器 + relay/local/arp 在 RTL 里已实现，但**没有 mark_debug 探针**（为保 B1 那点时序余量）。V4 上板前必须补一路探针（预计 32–48 bit），会需要重掷 place directive。
5. **没有板级验证**：本候选位流**未经任何上板判据**；V4 的全部验收项（逐字节不变、DROP 计数、ARP 不跨板、无乒乓）都待板。
6. **地址双方案共存**：`protocol`（192.168.50.x）仅作历史保留；`protocol_v1.md` §2.2 仍是旧值，留成品阶段同步。


