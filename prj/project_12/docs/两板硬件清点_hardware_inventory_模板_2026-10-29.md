# prj12 · 两板硬件清点（hardware_inventory）

> 用途：P1 联调当天逐项**实测**登记，作为证据包的一部分（对应草案 P0-10 的"两板逐项实测栏"）。
> 纪律：**只填实测值，不猜**；测不到就写 `未测`，空着比编好；填完与 `out/twin_config.json` 保持一致。
> 用法：复制本文件为 `hardware_inventory_2026-10-29.md`（或当天日期）再填。

---

## 1. 板卡与链路

| 项 | 板 A（左，接 PC1） | 板 B（右，接 PC2） |
|---|---|---|
| 板号/位置标签（照片编号） |  |  |
| 板卡序列号（丝印） |  |  |
| 器件 PN / 速度等级 | xcku060-ffva1156-2-i | xcku060-ffva1156-2-i |
| JTAG 线缆序列号（`get_hw_targets` 名字里） |  |  |
| JTAG hw_server | localhost:3121 |  |
| 串口 COM / 波特率 | COM? / 9600 8N1 | COM? / 9600 8N1 |
| GE1 对端 PC（网卡名 / IP） |  |  |
| SFPA 模块型号 / SN |  |  |
| SFPB 模块是否插（P1 空挂） |  |  |
| 光纤类型 / 长度 | LC duplex 单模/多模 ? m | 同 |
| 光模块速率档（RS0=RS1=1） | 已由 RTL 固定 | 已由 RTL 固定 |
| 参考时钟来源 | 板载 156.25 MHz | 板载 156.25 MHz |
| 电源型号 / 电压实测 |  |  |
| 上电时刻 |  |  |

## 2. 软件/位流

| 项 | 值 |
|---|---|
| 位流文件 / 指纹 | `out/aurora_mem_bridge.bit` / **C856BA83** |
| 位流 SHA256 | `C856BA83781FE85CCDCB684B6CD3C60873AA43E92F89AD30000B5954E5667401` |
| ILA 定义 | `scripts/probes.ltx`（与位流成对，勿单换） |
| ELF（可选，串口控制台） | `out/j3_soft_r2_BA3C0220.elf` / `BA3C0220` |
| 烧录时刻 / 通道 |  |
| `End of startup status` | 高（HIGH） |

## 3. 实测判据记录（每项带时刻）

| 判据 | 板 A | 板 B | 时刻 | 证据文件 |
|---|---|---|---|---|
| `channel_up` = 1 |  |  |  | ILA csv |
| `link_ok` 与 `channel_up` 同相 |  |  |  | ILA csv |
| `lane_up` = 1 |  |  |  | ILA csv |
| `gt_pll_lock` = 1 |  |  |  | ILA csv |
| `aurora_rst` = 0（链路起来后） |  |  |  | ILA csv |
| `hard_err`/`soft_err` 计数 10 min 不增长 |  |  |  | ILA csv ×2 |
| T23 LED 常亮 |  |  |  | 照片 |
| PC1→PC2 方向：发出 N / 抓到 M | PC1 发 20 | PC2 抓 ? |  | pcap + twin_recv 输出 |
| PC2→PC1 方向：发出 N / 抓到 M | PC1 抓 ? | PC2 发 20 |  | pcap + twin_recv 输出 |
| 断电重启后恢复（30 s 内 `channel_up`=1） |  |  |  | ILA csv |

## 4. 现场异常与处理（原样记录，别只写结论）

| 时刻 | 现象 | 判别依据 | 处理 | 结果 |
|---|---|---|---|---|
|  |  |  |  |  |

## 5. 对齐检查（填完自查）

- [ ] `twin_config.json` 的 `jtag_serial` / `cable_serial` / `com` / `pc_nic` 与实际一致（`pc_nic` = `Get-NetAdapter` 的 `Name` 列，**可能本地化**）；
- [ ] 两台 PC 都绑了静态 ARP（`192.168.1.10 → 00-11-22-33-44-55`，State=Permanent）；
- [ ] 两板 GE1 **直连**各自 PC，**未进同一交换机**（两板同 MAC/IP）；
- [ ] 位流与 `probes.ltx` 同批；ILA CSV 文件名带板号；
- [ ] 照片不少于 4 张：两板板号、SFP 模块与光纤接线、上电状态 LED、PC2 抓包屏（可选）。
