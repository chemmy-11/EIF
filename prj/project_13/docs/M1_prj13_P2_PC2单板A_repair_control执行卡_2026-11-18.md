# M1 · prj13 · PC2 单板 A_repair_control 执行卡（2026-11-18）

> **范围**：物理板 B（PC2）加载**A 参数**修复后位流，做**隔离单板**档 1/档 2。
> **不是**正式板 B 镜像，**不是**双板 V4；不得把本卡结果当正式 B 角色或 V4 验收。
> 依据：EIF #2（前置已关闭）、EIF #9 D1–D10、`docs/M1_prj12_prj13_下一轮操作口径_2026-11-17.md`、`M1_prj13_P2位流重建登记_2026-11-18.md`。
> 板级判据转出到交付仓 **#10（A2/P2）** 跟踪。

---

## 0. 本卡使用的件（必须与哈希一致）

| 件 | 路径（仓库根相对） | SHA256 / 字节 |
|---|---|---|
| 位流（A 参数） | `prj/project_13/out/b_p2_A_3a8b6300_b30c3903/aurora_mem_bridge_p2_3a8b6300.bit` | `3a8b630045fd3d20c12dec18b33484bfc512b971fec42934f60b1b2152a284dd` / 11,497,656 B |
| ILA（成对） | `prj/project_13/out/b_p2_A_3a8b6300_b30c3903/probes_p2_b30c3903.ltx` | `b30c3903272bc7517b7db1ab9960751e73a67d0b0d761d0900184f5fe80dc525` / 134,915 B |
| 烧录配置（PC2 单板 A profile） | `prj/project_13/out/twin_config_13_A_3a8b6300_pc2.json` | `c8860f6c97b4512b9b2e1090746b821b82430e493eae181c7ff491fd6f231d31` |
| ELF（沿用） | `prj/project_12/out/j3_soft_r2_BA3C0220.elf` | `ba3c02209720b59d9f0fbc4083c2ab80b16efc9a148448b9dcfbcda001bb3559` / 61,296 B |

- **禁止**：`CFA98553`/`F16FCE70`（修复前，作废）；PC2 自己的 `337E929B` 与 PC1 `3A8B6300` **不得混用配置**（两者同源不同片；本卡固定用 `3A8B6300`）。
- **READY=false 提示**：本片尚未完成离线终检（bitgen DRC 22 条普通警告、`no_input_delay=8/no_output_delay=10` 待逐项复核）。若现场要求 READY 才烧，先按 `M1_prj13_P2位流重建登记_2026-11-18.md` §6/§7 复核；未复核则记 `BLOCKED`，不要把“构建通过”当“可上板”。

---

## 1. 现场身份与前置

- PC2 数据 NIC：`以太网`（index/名称以 `Get-NetAdapter` 为准），MAC **A8-2B-DD-76-DF-A2**；当前 IP 可能为 `192.168.1.102/24`，本卡需临时加 `10.10.0.1/24`。
- 串口：CH340 **COM5**（以设备管理器实测为准；不要照抄 COM6）。
- JTAG：`210512180081`，`list_targets` 只应看到一条；**禁止 `-Board Both`**。
- 档 1 **不接光纤**；档 2 由用户接 **SFPA TX→RX** 自环跳线。
- 档 1 的 `ping`/ARP 走 OS 栈，**需要管理员**；无管理员时只能做原始 ARP/ICMP 旁证，档 1 判据记 `BLOCKED`，不得改判 PASS。

---

## 2. 档 1：无光本地通路（先做，最便宜）

### 2.1 网络 profile（管理员）

```powershell
Get-NetAdapter | ? Name -eq '以太网' | ft Status,LinkSpeed,MacAddress
New-NetIPAddress -InterfaceAlias '以太网' -IPAddress 10.10.0.1 -PrefixLength 24
Remove-NetNeighbor -InterfaceAlias '以太网' -IPAddress 10.10.0.11 -ErrorAction SilentlyContinue
New-NetNeighbor -InterfaceAlias '以太网' -IPAddress 10.10.0.11 -LinkLayerAddress 02-00-00-00-0A-01 -State Permanent
Get-NetIPAddress -InterfaceAlias '以太网' -AddressFamily IPv4
Get-NetNeighbor -InterfaceAlias '以太网' -IPAddress 10.10.0.11
```

### 2.2 烧录 + DMA

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File prj/project_12/out/twin_burn.ps1 `
  -Board B -Mode BitElf -Run `
  -Root D:\FPGA\prj\project_13 `
  -Config D:\FPGA\prj\project_13\out\twin_config_13_A_3a8b6300_pc2.json `
  -Cable 210512180081
# 期望：BURN_OK / BURN_ELF_DONE；bit hash 不符会拒烧
powershell -NoProfile -ExecutionPolicy Bypass -File prj/project_13/scripts/serial_dma_mode.ps1 -Com COM5
# 期望：now=DMA（d 是翻转，只看最后一条 banner）
```

### 2.3 判据

| 项 | 通过标准 | 证据 |
|---|---|---|
| ping 20 | `ping 10.10.0.11 -n 20` → 20/20，0 丢失，<1 ms | ping 原始输出/抓包 |
| ARP | 学到 `02-00-00-00-0A-01`（Permanent/Reachable） | `arp -a`/`Get-NetNeighbor` |
| 反向 | `ping 10.10.0.2 -n 3` → 3/3 超时（无光纤） | 原始输出 |
| 身份 | `list_targets` 只有 `210512180081`；DMA banner now=DMA | 串口日志 |

- 档 1 只证明“本地栈出板”通，**不证明转发**；不要用档 1 替代档 2。
- 失败先查网口/权限/地址/ARP/`stack_takeover`；环境不满足记 `BLOCKED`，不怪 RTL。

---

## 3. 档 2：SFPA 自环（转发通路）

用户接好 **SFPA TX→RX** 后执行；**不要接双板光纤**。

### 3.1 链路 S0

```powershell
$env:TEMP='D:\FPGA\.tmp'; $env:TMP='D:\FPGA\.tmp'
$ltx='prj/project_13/out/b_p2_A_3a8b6300_b30c3903/probes_p2_b30c3903.ltx'
vivado -mode batch -source prj/project_13/scripts/ila_capture_any.tcl `
  -tclargs localhost:3121 210512180081 prj/project_13/out/pc2_s0_link.csv $ltx dbg_pk_frames none
```

判据：`ch_up=1 lane_up=1 gt_pll_lock=1 link_ok=1 aurora_rst=0 hard/soft=0`；`ch_up_evt=0`。

### 3.2 S1：单帧转发 + 六点计数

```powershell
py prj/project_13/pc/p2_rawsend.py --iface <PC2 Npcap GUID> --dst-ip 10.10.0.2 --count 1 --len 100 --run-id 0x11
# 或管理员下 py prj/project_13/pc/twin_send.py --dst-ip 10.10.0.2 --count 1 --len 100 --run-id 0x11
```

抓 `npcap_capture.py --seconds 30`；发帧前后各抓 ILA6/ILA3 快照；八计数应各 +1：
`pfwd_wr → mem_wr_frm → mem_rd_frm → pk_frames → up_frames → mem2_wr_frm → mem2_rd_frm → prev_wr`。

### 3.3 S2/S3/S5/S6

| 项 | 判据 |
|---|---|
| S2 | 完整 IP 逐字节不变，仅换以太头；无重复 |
| S3 | `--len 12`：IP 40、Ethernet 54，补 6 B 0 到 60（无 FCS）；末尾 20 B 全 0 |
| S5 | `dst=10.10.0.11` 不跨自环，`pfwd_wr` 不涨；本地应答正常 |
| S6 | `dst=8.8.8.8` ×3 不转发，`pfwd_wr` 不涨；应有对应 DROP 计数（**当前无 DROP ILA，只能记 NOT_OBSERVABLE，不能写 PASS**） |

### 3.4 失败分诊

- `pfwd_wr=0`：查发送 MAC/IP、preamble/SFD、extract/steer；
- 有 `pfwd_wr` 但 `mem_wr_frm/pk_frames` 不动：查整帧缓冲/DMA/commit；
- 有 `pk` 但 `up_frames` 不动：查链路/流；
- `up_frames` 有但 `mem2/prev` 或 pcap 短：查 mem2/pack/长度；
- 两次受控单帧仍无边界证据：关窗口回离线，不接第二块板放大变量。

---

## 4. 证据与回报

- 目录：`prj/project_13/out/evidence_20261118_pc2_single_A/`（或 `pc2/...`），失败只增不覆盖。
- 必带：bit/ltx/ELF/config 全 SHA、cable/COM/NIC、地址 profile、命令、ILA CSV、pcap、判据文本、`SHA256SUMS.txt`。
- 回报格式：
  `TEAM-REPORT prj13-G4-<run> | PASS/FAIL/BLOCKED/NOT_TESTED | machine=PC2 physical_board=B parameter=A_repair_control | inputs=<hashes> | measured=<counts/len/dup/direction> | evidence=<path/SHA> | next=<...>`
- 未测写 `NOT_TESTED`，环境缺失写 `BLOCKED`，观测违例写 `FAIL`；不把“没触发/没探针”当通过。

## 5. 边界

- 本卡只做 PC2 单板档 1/档 2；**双板 V4、板 B 正式位流、DROP 观测、A3** 都不在本卡范围。
- 单板结果不能替代 prj12 或双板验收；正式 B 参数位流必须另行五参数构建、登记，不能改 JSON 凑版。
- 旧位流/旧配置（`twin_config_13.json` 的 CFA98553）禁止使用。
