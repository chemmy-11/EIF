# GPP2/v1 线格式（J0 冻结）

> **状态：线格式 FROZEN v1.0（2026-11-16）**。
> 决策：J0 以 **GPP2/v1** 为准，A 组基于此适配，不再要求 B 组移植到原 `protocol_v1`（GSP1）。
> 冻结范围：**线格式 + META/ACK 语义 + 固定向量集**。未冻结项见 §7。
> A 侧承载（透明 IPv4/UDP 转发）不改 RTL；实机承载验证随 **A2/P2** 上板完成。
> 原 `docs/protocol_v1.md`（GSP1，40 B 头）**降为参考实现/历史**，不作为 J1/J2 线格式。

## 1. 决策与影响

| 项 | 结论 |
|---|---|
| 线格式 | **GPP2/v1**（52 B 固定头 + JSON META + 逐片 ACK） |
| A 侧 | P2 透明转发 IPv4/UDP，**不解析 GPP2 载荷**；只要求应用 datagram ≤1200 B、IP 包 ≤1228 B、端口/ARP/MTU 按 §6 |
| B 侧 | 现有 GPP2 实现/测试/向量**不用返工**；J0 后按本文件补 labels 约定与会话/重启说明（不改线格式） |
| 原 protocol_v1 | 保留 `docs/protocol_v1.md` 与 `pp/transport/` 实现作为**参考/mock 后端**，不再作为 J1/J2 的正式线格式 |
| 改名 | 导师文档里的 `protocol_vNext` = 本文件的 J0 标签；落地文件为 `protocol_v2_GPP2.md`（内容载体） |

## 2. 固定头（52 B，网络字节序 big-endian）

`struct` 格式：`!4sBBBB16sIIIIIII`，`calcsize() == 52`。

| 偏移 | 字段 | 宽度 | 说明 |
|---|---|---|---|
| 0 | `magic` | 4 B | 固定 `b"GPP2"` |
| 4 | `version` | 1 B | `1` |
| 5 | `kind` | 1 B | `1=META`、`2=DATA`、`3=ACK`、`4=ERROR` |
| 6 | `direction` | 1 B | `1=FWD`（activation）、`2=BWD`（gradient） |
| 7 | `flags` | 1 B | v1 固定 `0`；非 0 拒绝 |
| 8 | `run_id` | 16 B | ASCII，NUL 右填充，有效长度 1..16，不允许内嵌 NUL |
| 24 | `step_id` | 4 B | uint32 |
| 28 | `microbatch_id` | 4 B | uint32 |
| 32 | `transfer_id` | 4 B | uint32；一次 Tensor 传输唯一 |
| 36 | `segment_index` | 4 B | DATA 为 0..count−1；**META 及其 ACK 固定 `0xFFFFFFFF`** |
| 40 | `segment_count` | 4 B | DATA 片数（空张量允许 0） |
| 44 | `payload_len` | 4 B | 后续 payload 字节数，≤1148 |
| 48 | `crc32` | 4 B | `zlib.crc32(header 前 48 B + payload)`，IEEE 反射 |

- 应用层 UDP datagram = 一个 GPP2 消息，总长 ≤ **1200 B**；数据片 ≤ **1148 B**。
- Tensor 字节固定 **little-endian**；`byte_order` 只能是 `"little"`。
- 单个 Tensor 硬上限 **8 MiB（8,388,608 B）**；超限发送端拒绝。
- Tensor 分片数 = `ceil(nbytes / 1148)`（空张量 1 片、payload 为空）。

## 3. META 语义

META 的 payload 是 UTF-8 JSON（紧凑格式）：

```json
{"dtype":"float32","shape":[2,16,16,16],"byte_order":"little","nbytes":32768,"sha256":"…64 hex…"}
```

- `dtype`：`float32 / float64 / int32 / int64 / uint8`；
- `nbytes = prod(shape) × dtype_size`，且 ≤ 8 MiB；
- `sha256`：**整个 Tensor 原始字节**的 SHA256；
- 接收端：先回 META ACK（`segment_index=0xFFFFFFFF`），再收 DATA；整张量重组后校验 SHA256，不符发 ERROR。

## 4. DATA / ACK / ERROR 语义

- **DATA**：`segment_index 0..count−1`，CRC 错则丢弃且**不回 ACK**；重复片去重；乱序按 index 重组。
- **ACK**：逐片 ACK，`segment_index` = 被确认的片号（`0..count−1`），或 `0xFFFFFFFF` 表示 META ACK；ACK 本身无 payload。
- 发送端：META → 等 META ACK → DATA（默认窗口 8）→ 每片 ACK；RTO 250 ms、重试上限 12（B 组实现默认，可配）；`send` 返回仅表示“全部片被接收端 ACK”。
- **ERROR**：payload 为 UTF-8 文本；用于整张量 SHA 不符、非法 META 等；v1 不定义机读错误码（见 §7）。
- **labels 约定（冻结的语义约定，不改线格式）**：labels 作为**独立 transfer**发送，`dtype=int64`、`shape=[batch]`；与 activation 的配对按 `(run_id, step_id, microbatch_id)` + 同一 Step 内“先 activation、后 labels”的发送顺序确定；接收端必须按此校验，不得把 int64 张量当 activation 消费。若未来需要显式 kind 位，升 v1.1。
- **会话/重启**：v1 无 HELLO/session。A 侧不缓存、不重排、不跨复位保证顺序；B 侧靠 `transfer_id` + RTO 重传识别旧包/缺失。板卡复位/进程重启后使用新的 `transfer_id`，旧包按 CRC/五元组自然丢弃。

## 5. A 侧承载契约（P2，透明转发）

- A 只转发 **IPv4 dst = PEER_IP** 的包；只换以太网头（dst=对端 PC MAC，src=本板 MAC，type=0x0800），**不改 IP 内任何字节**（TTL/checksum/DSCP/分片均不动）。
- 一个 UDP datagram（含 52 B 头 + 数据）≤1200 B ⇒ IP 包 ≤ **1228 B**，在 MTU 1500 内；**禁止 jumbo / VLAN / IPv6**。
- 业务 UDP 端口固定 **47001**（两端一致，可配）；PC 侧静态 ARP 指向本板 MAC（见 `docs/protocol_v1.md` §2.3 的地址示例，拓扑与 ARP 规则沿用）。
- **ACK 必须走同一 FPGA 路径反向返回**，不允许管理口旁路。
- A 侧不解析 GPP2，因此协议字段/ACK 策略变化不影响 RTL；A 侧只需保证**不丢包、不改包、不乱序**（Aurora FIFO 深度/速率能力见 `config/fpga_capabilities.example.yaml`，A2/A3 后回填）。
- 板卡复位/链路闪断：A 侧不保证跨复位的有序性；恢复后由 B 侧 ARQ 续传（`reset_recovery_log.csv` 记录恢复时间）。

## 6. 地址、端口与配置

| 项 | 值 |
|---|---|
| 业务口 | 丝印 **GE1**（本板无 GE2） |
| PC1 / PC2 IP | 现场配置，同一子网（模板 `192.168.50.1/.2`） |
| 板 A / 板 B IP | 本地管理地址（模板 `192.168.50.11/.12`） |
| 业务 UDP 端口 | **47001**（两端一致；防火墙放行入站） |
| MTU | 1500，不做 jumbo |
| ARP | PC 侧静态 ARP：对端 IP → 本板 MAC |
| 协议 | GPP2/v1（本文件） |

## 7. 冻结范围与未冻结项

**已冻结**：头部布局/字节序/CRC/META JSON 字段/逐片 ACK/META ACK/labels 约定/8 MiB 上限/1200 B datagram。

**未冻结（不阻塞线格式）**：
1. A 侧实机承载（1228 B IP 包经 P2 双向、丢包/速率上限）——待 A2/A3；
2. `network_config.yaml` / `fpga_capabilities.yaml` 的实测数值——待 A2/A3；
3. 机读 ERROR 码表（v1 只有文本）；
4. API 方法名与语义（`send_activation/recv_activation/...`）——B 组交付，A 侧只读；
5. labels 的显式 kind 位（如需，升 v1.1）。

> J0 正式签收 = 本文件线格式冻结 + 向量通过 + A 侧能力/网络回填 + 双方签字；当前前两项完成，后两项待 A2/A3。

## 8. 向量与验证

- 向量目录：`results/raw/20261116_bgroup_j0_handoff_v1/test_vectors/`（B 组交付原样，10 用例，`manifest.json` 带路径级 SHA256）。
- A 侧独立实现：`pp/transport/gpp2_codec.py`；验证脚本：`scripts/verify_gpp2_vectors.py`。
- 验证结果（2026-11-16）：**10/10 用例、380 个报文**全部通过；逐包 CRC、逐包 decode→encode **字节一致**、按 index 重组后整张量 SHA256 = META = `expected_payload.bin`；与 B 组 `b2_packet_codec.py` **逐包双向比对一致**；`pytest tests/test_gpp2_codec.py` **37 passed**。
- 详细报告：`docs/J0_GPP2_线格式冻结验证报告_2026-11-16.md`。

## 9. 变更控制

- 任何字段/字节序/CRC/上限变化 ⇒ 升 **v1.x**，更新本文件 + 向量 + `docs/接口变更记录.md`，并重跑验证脚本。
- B 组实现为准；A 侧 codec 为独立校验实现，不引入与 B 组不同的语义。
- 历史 `results/raw/` 不回改；旧 GSP1 文档保留供追溯。
