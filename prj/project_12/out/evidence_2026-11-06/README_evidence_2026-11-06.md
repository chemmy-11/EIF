# prj12 · P1 上板证据包（2026-11-06）

> 本目录是 **2026-11-06 P1 双板上板联调**的 PC1 侧证据。PC2 侧证据在 `out/evidence_2026-11-06_pc2/`（PC2 本机）。
> 判据口径：`docs/M1_prj12_P1双板上板执行单_2026-10-24.md` §3–§4（已按本日实测修订）；协作记录 EIF issue #1。
> 位流指纹 **`C856BA83`**（SHA256 `C856BA83781FE85CCDCB684B6CD3C60873AA43E92F89AD30000B5954E5667401`），ELF `BA3C0220`。

## 1. 结论速览

| 项 | 状态 | 证据 |
|---|---|---|
| P1-02 链路（板 A） | ✅ PASS：`ch_up=1 / link_ok=1 同相 / lane_up=1 / gt_pll_lock=1 / aurora_rst=0 / hard,soft=0` | `ila/ila6_A_sfp_connected_1550.csv`、`ila6_A_recheck_1603.csv` |
| P1-02 链路 10 min 稳定（板 A） | ✅ PASS：两次抓取 `ch_up` 均为 1，`ch_up_evt/hard_err_cnt/soft_err_cnt` 不增长 | `ila/ila6_A_marker_1717.csv`、`ila/ila6_A_10min_1727.csv`、`judge/judge_ila6_A_10min_1727.csv.txt` |
| P1-02 链路（板 B） | ✅ PASS（PC2 证据）：17:08 重烧后 `ch_up=1/lane_up=1/rst=0`，10 min 复抓字节级不变 | PC2 `out/evidence_2026-11-06_pc2/ila6_B_1709.csv` |
| P1-03 数据面 A→B（本地链路） | ✅ PASS：发 5 帧 → `pfwd_wr=5 / mem_wr_frm=5 / mem_rd_frm=5 / pk_frames=5` | `ila/ila6_A_marker_1717.csv`、`ila/ila3_A_marker_1717.csv` |
| **P1-03 数据面 A→B（端到端）** | ✅ **PASS（官方判据）**：PC2 抓到 **20/20 帧**，`run_id=0x1`、`unique=20`、`dup=0`、`fill` 全 ok；仓库版 `twin_recv.py` @ `003284d` 判 `twin_recv: PASS` | PC2 `out/pc2_round4.pcap`（sha256 `a5aaf1f3…d563e3`，56 帧）；判据全文 `pc2_issue/comment_6682320881_20261106_180558.txt` |
| **P1-04 数据面 B→A** | ✅ **逻辑闭环**：B 侧 ILA `pk_frames=20`（20 帧打包进 Aurora TX）；A 侧 ILA6 `up_frames=20`、`prev_wr=20`，ILA3 `mem2_wm/wr_frm/rd_frm=20/20/20`（PC1 pcap 判据见下条） | B：`comment_6682341507_20261106_180708.txt`；A：`ila/ila6_A_after_b2a1.csv`、`ila/ila3_A_after_b2a1.csv` |
| **P1-04 数据面 B→A（PC1 pcap 判据）** | ✅ **PASS**：PC1 抓到 **20/20 帧**，`run_id=0x2`、`unique=20`、`dup=0`、`len=100`、`fill` 全 ok、跨度 0.39 s | `pcap/pc1_b2a_final.pcap`（sha256 `FCA2E71F…4B3A`，26,872 B，108 帧）+ `pcap/pc1_b2a_final.log` |
| P1-05 断电恢复 | ⏳ 未做（板 B 存在无规律复位风险，先稳定供电） | — |
| P1-06 证据归档 | ⏳ 本目录（A 侧已收，B 侧待 PC2 汇总） | — |

## 2. 关键发现（本日实测，已写进执行单）

1. **网口是 GE2，不是 GE1**：工程 XDC 的 eth 引脚 = 官方 `KU_IO.xdc` 的 `#GE2` 段；板 A 插 GE1 时 PC 网卡一直 `Disconnected`（两端重插无效），换 GE2 立即 Up / 1 Gbps。
2. **P1 数据路必须 BitElf + 串口 `d`（DMA 写模式），两个方向都要两端如此**：
   - 只烧位流：`pfwd_wr` 涨、`mem_wr_frm/mem_rd_frm/pk_frames` 恒 0（帧只进泵）；
   - 烧 BitElf + `d`：`pfwd_wr=mem_wr_frm=mem_rd_frm=pk_frames=5`；
   - A→B 时板 B 也要（B 的接收侧同样过 `frame_mem_if` 写通路）：17:42 实测 A 的 `pk_frames` +20、B 的 `dbg_up_frames` +20，但 B 的 `dbg_prev_wr` 不动。
3. **pack 级卡死处置**（本日两次踩到）：对端板重烧/断电导致 Aurora 闪断后，A 侧可能出现 `mem_wr_frm/mem_rd_frm` 正常涨而 `pk_frames` 停滞；发 `d` 无效，**整板 BitElf 重烧** 才能恢复。
4. **位流是否加载只看 `get_hw_ilas` 数**（P1=4 / flash 旧位流=0）；`CONFIG_STATUS=0x509079FC` 在两种状态下相同，不能作判据。
5. **`twin_recv.py` 端口方向假阴性**（已修，commit `669d61e`）：板卡回声是 `sport=1234 / dport=PC 临时端口`，旧版只认 `dport==1234`；新增 `--port-direction {any,sport,dport}` 默认 `any`。
6. **回声帧 `eth.dst = ff:ff:ff:ff:ff:ff`（广播）**：板 B 的 ARP 表无 PC2 IP，跨板回声退化成广播；判据只看 `src=板卡 MAC` + TWIN payload，不看 `dst_mac`。
7. **板卡身份**：两台机器的 JTAG 都报 `210512180081`（克隆 EEPROM 或同批烧写）⇒ 单机禁 `-Board Both`，以物理标签 A/PC1、B/PC2 区分。
8. **抓包时段纪律**：分块抓包（每块 15 s + 判据耗时）块间有空档，20 帧 0.4 s 的突发落在空档就会漏抓（18:05:45 的 B→A 首轮就是这么漏的：A 侧计数 `up_frames/prew_wr` 都 +20，PC1 pcap 却是空）。**收尾判据必须用单次连续抓包**（`pc/npcap_capture.py --seconds 300`）。

## 3. 环境与工具

| 项 | PC1 | PC2 |
|---|---|---|
| 板卡 | 板 A（GE2 ↔ 本机） | 板 B（GE2 ↔ 本机） |
| JTAG | `210512180081`（Digilent JTAG-HS1） | `210512180081`（同值，见发现 7） |
| 串口 | CH340 `VID_1A86&PID_7523` → **COM6** 9600 8N1 | CH340 → **COM4** |
| 网卡 | Realtek `08-3C-03-A0-26-96` → `192.168.1.102/24` | Realtek `A8-2B-DD-76-DF-A2` → `192.168.1.102/24` |
| 抓包 | Npcap 运行时 + `pc/npcap_capture.py`（ctypes，无需 dumpcap/管理员） | 同（PC2 自写 `npcap_capture.py`） |
| 烧录 | `out/twin_burn.ps1 -Board A -Mode BitElf -Run`（xsct 通道） | `out/twin_burn.ps1 -Board B -Mode BitElf -Run` |

## 4. 文件索引

- `burn_A_bitelf_last.console.log`：板 A 最后一次 BitElf 烧录（`BURN_BIT_OK` / `BURN_OK` + `BURN_ELF_DONE`）
- `ila/ila6_A_*.csv`：板 A 的 ILA6（链路 + 计数器）各时刻抓取
- `ila/ila3_A_*.csv`：板 A 的 ILA3（`calib` + `mem/mem2` 写读计数 + S2MM 状态）
- `serial/serial_A_U_*.txt`：串口 `U` 寄存器快照（含 `mode=`、`wreq/wdbg/s2sr`）
- `pcap/pc1_*.pcap`：PC1 侧抓包（含 A→B 本地自测、B→A 抓包）
- `pcap/pc1_captest.log`：Npcap 抓包工具自检（14 帧/10 s）
- `judge/judge_*.txt`：`judge_ila6.py` 对关键 CSV 的判据输出
- `pcap/selftest_bcast_1730.pcap`：`twin_recv.py` 新判据自测（广播 dst + `sport=1234/dport=49355`）

> 大件（ILA CSV、pcap）留在本目录不提交 git；判据文本与说明随文档提交。
> PC2 侧证据（`pc2_round4.pcap`、`ila6_B_1709.csv`、`burn_B_1708.console.log`、`npcap_capture.py`）由 PC2 归档到其 `out/evidence_2026-11-06_pc2/`。

## 5. 待办（P1 收口前必须闭环）

- [ ] B→A 数据面 20 帧 PASS（PC1 抓包 + PC2 发 `run_id=0x2`）
- [ ] 板 B 供电/USB 稳定性（无规律复位 = 每轮都要重烧两块板；这是当前唯一系统性风险）
- [ ] P1-05 断电恢复：两板断电 10 s → 重烧 BitElf + `d` → 30 s 内 `channel_up=1`、计数清零不增长
- [ ] 硬件清点表回填（`docs/M1_prj12_两板硬件清点_2026-11-06.md`）
- [ ] PC2 侧用修好的 `twin_recv.py` 重跑 `pc2_round4.pcap` 出官方 PASS 文本
