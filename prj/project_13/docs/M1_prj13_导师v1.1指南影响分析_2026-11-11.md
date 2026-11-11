# M1 · prj13 · 导师 v1.1 指南对 prj13 的影响分析（2026-11-11）

- **输入**：`C:\Users\ljh\Desktop\GSnFPipe_A组_FPGA实验执行与验收指南_v1.1.md`（26,822 B，版本日期 2026-11-10）。
- **性质**：影响分析（文档对照 + 本仓源码直读），**不是上板结论**。
- **依据等级**：本文除明确标注外均为 **L1**（对照分析）。每条事实给出 `文件:行`；凡"未测/未证"一律写明，不写成已通过。
- **上位**：`AGENTS.md` §二 两轴采信规则（工程事实以本仓实测为准，工具语义以 AMD 官方文档为准）。

---

## 0. 结论摘要（对 prj13 的 7 条影响）

| # | 影响 | 对 prj13 的动作 | 状态 |
|---|---|---|---|
| 1 | P2 从"候选"升级为 A2 交付主体（v1.1 §5.1） | 出流 + 登记 + 能力文件三件套 | 出流进行中 |
| 2 | 业务口口径 = **GE2**（v1.1 §1.3），prj13 引脚本就是 GE2 | 仅 XDC 注释是旧称 `GE1`，登记待办，**不改约束** | 已核对 |
| 3 | 能力必须写成 `fpga_capabilities.yaml`（v1.1 §5.4） | 新增该文件；`bitstream_sha256` 出流后填，`max_*` 无板记 `TO_MEASURE` | 待出流 |
| 4 | 验收报告新增 `A2_P2_udp_compatibility_report.md`（v1.1 §10） | 档 2 的 S0–S7 是其证据骨架；当前**无板 → BLOCKED** | 阻塞 |
| 5 | J0 协议冻结要求固定测试向量（DATA/ACK/ERROR，v1.1 §5.3） | 现有 TB 未按协议类型构造，属**新增用例** | 未做 |
| 6 | 双向路径需要**板 B 参数集位流**（PEER_MAC=PC1 网卡） | 板 B 位流未构建；B 参数口径需先订正 | 未做 |
| 7 | A5 的 HOLD/RELEASE/SET_WINDOW 不计入本轮 P2 | prj13 当前只有 FORWARD_NOW 语义 | 边界明确 |

---

## 1. 定位变化：prj13 变成 B 组接入的唯一实现载体

v1.1 §0.1 把 P2 写成：

> `P2 IPv4/UDP 透明转发 | project_13 已启动 | 不能直接当成已可运行通用 TCP/IP 的网桥`

v1.1 §5.1 说明原因：B 组 PyTorch 需要把完整 Tensor 拆成**正常 UDP 应用报文**直接发到对端 PC 并收回 ACK/gradient，P1 的"终止 + 回显"语义不兼容。

⇒ 对 prj13：P2 不再是"候选位流"，而是 **A2 的交付主体**；其证据链（位流指纹、时序守门、档 2 判据、能力文件）必须按 v1.1 §10 的 `PASS / FAIL / BLOCKED / NOT_TESTED` 四态书写。

---

## 2. 端口口径：v1.1 说 GE2 —— prj13 引脚本来就是 GE2

**事实（磁盘直读）**：

- prj13 XDC 的 eth 引脚：`rtl` 侧端口 `eth_rxc/eth_rxd/eth_txd/...`，约束在
  `prj/project_13/xdc/aurora_mem_bridge.xdc:40-49`（AC31/Y33/W33/W34/V33/AC32/Y32/AE32/Y31/AF32…）。
- 该引脚组 = 官方 `KU_IO.xdc` 的 `#GE2` 段，2026-11-06 板上实测定案：
  `prj/project_12/docs/M1_prj12_两板硬件清点_2026-11-06.md:26-27`
  > 工程 XDC 的 eth 引脚 = 官方 `KU_IO.xdc` 的 `#GE2` 段（AC31/Y33/W33/W34/V33/AC32/Y32/AE32/Y31/AF32/AF30/AG30/AA33）。文档旧称"GE1"是误称；插 GE1 时 PC 网卡一直 `Disconnected`，换 GE2 立即 Up / 1 Gbps。

**唯一不一致**：`prj/project_13/xdc/aurora_mem_bridge.xdc:39` 的注释仍写
`## ---- RGMII GE1 (YT8531 PHY, 全部 LVCMOS18) ----`。

**处置建议**：**本轮不改**。改注释会改变 XDC 文件哈希，使"位流 ↔ 约束"哈希对账需要重跑综合；把它登记为待办，在下次必然要重综合的改动里一并订正（注释级，不动任何 `set_property`）。

---

## 3. 能力边界（可直接填进 `fpga_capabilities.yaml`）

| 能力项 | prj13 现值 | 证据 |
|---|---|---|
| 转发对象 | 仅 IPv4（EtherType `0x0800`，version=4），**不解析 TCP/UDP** | `docs/M1_prj13_P2_RTL接口契约_v0.2_2026-11-08.md:88-102` |
| 转发判决 | 仅 `ip_dst == PEER_IP` 的单播 → RELAY；`BOARD_IP` → 本地栈；ARP 本地终结不跨板 | 同上 §6、`rtl/p2/local_steer.v` |
| 接受域 | `total_len ≤ 1500`；1500 < len ≤ 1538 一律 `DROP_OVERSIZE` | 契约 `:64` |
| 帧缓冲 | **2 bank × 2048 B**，整帧粒度，超容量整帧丢并计数 | `rtl/p2/p2_frame_buf.v:36`、契约 `:263` |
| DROP 分类（10 类） | VLAN / IPv6 / 非 IPv4 EtherType / 广播 / 组播 / 未知 dst / 超长 / 坏 IP csum / 截断 / MAC 不符 | 契约 `:50-62` |
| 分片 | **不重组**：MF/offset 只作为元数据，IP 包逐字节转发 | 契约 `:106`（`m_is_fragment`）、`:313` |
| 地址（板 A 参数集） | `BOARD_IP=10.10.0.11`、`PEER_IP=10.10.0.2`、`PC_IP=10.10.0.1`、`BOARD_MAC=02:00:00:00:0A:01`、`PEER_MAC=A8:2B:DD:76:DF:A2` | `rtl/aurora_mem_bridge.v:100-102`；地址表 `docs/M1_P2地址与ARP方案_v0.2_2026-11-08.md:33-38` |
| TCP / iperf3 | **不支持**（不解析传输层，也无 TCP 端点） | 与 v1.1 §5.2 `:202` 口径一致 |
| 吞吐 | **未测**；>3 帧背靠背未证 | 契约 `:311`（I10：3×1472 B 背靠背 3/3） |
| 错误计数可观测性 | 11 个 DROP 计数器**无 ILA 探针** | 契约 `:314` |
| 控制模式 | 仅 `FORWARD_NOW` 语义（无 HOLD/RELEASE/SET_WINDOW） | 契约 §6，本仓无对应命令 |

> ⚠ 与 v1.1 §8.2 的冲突：指南写"当前只有 **256×4 KiB 帧槽**（按已知旧工程记录）"，本仓实测实现是 **2×2048 B**（`p2_frame_buf.v:36`）。**能力文件必须写实测值**，不能抄旧记录；两者差异登记为与导师口径的待澄清项（见 §7）。

---

## 4. 验收映射：v1.1 §10 的三个件由 prj13 产出

| v1.1 要求的件 | prj13 现状 | 缺什么 |
|---|---|---|
| `A2_P2_udp_compatibility_report.md` | 档 2 执行单已把判据拆成 S0–S7（`docs/M1_prj13_P2上板验证执行单_2026-11-10.md:143-154`） | **无板 → 全部 BLOCKED**；未执行任何一条 |
| `fpga_capabilities.yaml` | 字段值已可从源码读出（本文 §3），`bitstream_sha256` 待本次出流 | 出流后填哈希；`max_*` 四项需实测 |
| `bitstreams/INDEX.md` | 登记格式见 `docs/M1_prj13_P2候选位流登记_2026-11-08.md:8-19` | 本次重建位流的**成品阶段**才进交付仓；本阶段只进 EIF |
| J0 固定测试向量（DATA/ACK/ERROR） | 现有 `sim/p2/` 覆盖单元 23 例 + 集成 9 例，但**未按协议类型构造** | 新增 3 个用例（可离线，不需板） |

---

## 5. 与 v1.1 A0 / A1 / A5 的依赖关系

1. **A0（板 B 随机配置丢失）**：是双板 V4 的前置；与 prj13 无代码耦合，但决定 prj13 能否拿到双板证据。
2. **A0-补充（FIFO 复位补丁实板验证）**：prj13 的 fork 已带 B1 补丁（`prj/project_13/README.md:11`：xsim PASS、位流 `E9BE2B14`、**未上板**）。v1.1 §3.1 `:143` 明确"目前报告只证实构建，不证实已上板恢复" ⇒ **该补丁的实板证据与 prj13 的 V4 证据是两件事，不能互相替代**。
3. **A1（10 MiB / 多轮 / 同时双向）**：不属于 prj13 的交付，但 prj13 的 **2-bank 容量 + >3 帧背靠背未证**直接决定 10 MiB 连续是否可行。建议：离线 TB 补 `5–8` 帧背靠背用例（不需要板），把容量边界先钉住。
4. **A5（HOLD/RELEASE/SET_WINDOW）**：prj13 当前没有这些命令；按 v1.1 §8.3 属**新开发**，不计入本轮 P2 验收。

---

## 6. 对当前出流任务的影响

- **不改 RTL**：v1.1 的要求都能由现有 P2 实现回答（能力边界 + 判据），所以本轮仍按原配方重建位流（`build_impl.tcl` 默认配方，见 `scripts/build_impl.tcl:31-36`）。
- **出流后立刻可回填的字段**：`bitstream_sha256`、`firmware_sha256`（沿用 `prj12/out/j3_soft_r2_BA3C0220.elf`，61,296 B）、时序（WNS/WHS）。
- **仍需板的字段**：`max_udp_payload_bytes`、`max_inflight_segments`、`max_safe_rate_mbps`、`buffer_full_behavior`、S0–S7。
- **口径纪律**：v1.1 §10 `:409` 要求 `PASS/FAIL/BLOCKED/NOT_TESTED`；无板时档 2 记 **BLOCKED（缺板）**，不写 FAIL（判据未取得 ≠ 判据失败，AGENTS §6a 硬规则 3）。

---

## 7. 风险与待澄清（需与导师 / B 组对齐）

1. **可靠路径**（v1.1 §5.3）：业务 DATA 与 ACK 都必须走同一 FPGA 路径。prj13 只转发 `dst == PEER_IP` 的 IPv4；若 B 组 ACK 从管理口/串口回，判据无效。
2. **能力数字不能外推**：`max_*` 四项没有板上实测前只能写 `TO_MEASURE`；本仓只有 I10 的 3 帧背靠背（`契约:311`），不能外推成吞吐或任意连发安全。
3. **帧槽容量口径冲突**（§3 备注）：256×4 KiB（指南）vs 2×2048 B（本仓实测）—— 需导师确认指南引用的是哪一版工程。
4. **板 B 参数集**：v1.1 §5 的双向路径需要板 B 位流。参数集必须给 `PEER_MAC = PC1 网卡 MAC = 08:3C:03:A0:26:96`（`docs/M1_P2地址与ARP方案_v0.2_2026-11-08.md:35`）；而 `out/twin_config_13.json` 的 B 块 `peer_mac` 写的是 `02:00:00:00:0A:01`（板 A MAC），**口径不同**，在生成 B 位流前必须订正并复核（L1，待确认该字段是否被脚本当真）。
5. **XDC 注释旧称**：`xdc/aurora_mem_bridge.xdc:39` 写 `GE1`，与 v1.1 §1.3 的 `GE2` 冲突；实测定案（prj12 清点）是 GE2。注释待办，不改约束。
6. **P2 计数器无 ILA**（契约 `:314`）：v1.1 §5.4 的 `buffer_full_behavior` 与"各类 DROP 分别计数"当前抓不到；补探针要重出位流（预计 32–48 bit，需重掷 place directive）。

---

## 8. 本轮动作（无板）

- [x] 官方知识库核对构建方法（UG904 / UG892，见 §9）。
- [x] 能力边界与验收映射（本文 §3/§4）。
- [x] 离线判据自检：`twin_recv.py` 负向对照 N1 PASS / N2 FAIL / N3 FAIL / N4 FAIL（`D:\fpga\.tmp\dryrun-20261111\`）。
- [ ] 出流（run#3 进行中）→ 登记位流/ltx 指纹、填 `twin_config_13.json` 的 `expect_bit_sha256`。
- [ ] 档 2 S0–S7：**BLOCKED（无板）**。
- [ ] J0 固定测试向量三用例（离线可做）。

---

## 9. 官方依据（本轮构建方法）

- UG904：`NoTimingRelaxation` = "Prevents the router from relaxing timing to complete routing. If the router has difficulty meeting timing, it runs longer…" —— 解释了 route 段 3 h 量级的长耗时，属"用编译时间换布线质量"的官方口径。
  <https://docs.amd.com/r/2023.2-English/ug904-vivado-implementation/Using-Directives>
- UG892（含 2023.1）：checkpoint 捕获 netlist + constraints + implementation 结果，可"run the design through the remainder of the flow using Tcl commands"，但不能加新源 —— 支撑本轮"place 后写 checkpoint"的分段做法。
  <https://docs.amd.com/r/2025.2-English/ug892-vivado-design-flows-overview/Using-Design-Checkpoints>
- UG1387：明确推荐"trying place_design using multiple directives and saving the checkpoints for each… select the place_design checkpoint with the best timing" —— 与 prj13 的换 directive 重掷策略同源。
  <https://docs.amd.com/r/2025.2-English/ug1387-acap-hardware-ip-platform-dev-methodology/Analyzing-a-Design-at-Different-Stages-Using-Checkpoints>

> 版本说明：上列 URL 的 `family` 字段为 `All`，`version` 覆盖 2023.1（UG904 块 version=2023.2, 2024.1, 2023.1），与本机 Vivado 2023.1 对齐；未使用 2026.1 独占行为。

---

## 10. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-11 | 首版：对照导师 v1.1 指南，给出 prj13 的 7 条影响、能力边界表、验收映射、风险与待澄清 |
