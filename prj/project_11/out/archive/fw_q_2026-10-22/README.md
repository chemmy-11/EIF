# fw_q_2026-10-22 — 串口 Q 汇总行演示固件（B6D3F7B1）

## 是什么

在 round3d 验收固件 `BA3C0220` 的同一份源码（`main.c`）上，只加两条 UART 命令：

| 命令 | 回包（示例） | 说明 |
|---|---|---|
| `Q` | `[Q] mode=DMA wr=769 rd=768 drop=0 s2sr=00000000 H=0 I=0 E=0 fault=0 P=0 last=0/118` | 一行汇总：模式 / 桥①计数 / S2MM 状态解码 / 写引擎 fault+pending / 末帧槽长 |
| `?` | `[?] U W I Q L X S d M A B E D F P G C J K` | 命令速查 |

- **只读**：不改任何寄存器状态、不进数据路径。
- **位流不变**：仍用 round3d 的 `aurora_mem_bridge_r2_F6012BA0.bit`；本目录只有 ELF。
- 正式 S0–S11 / 哈希证据仍必须烧 `BA3C0220`（本固件仅供演示/调试串口观感）。

## 产物

| 文件 | SHA256 前 8 | 大小 | 说明 |
|---|---|---|---|
| `j3_soft_r2_B6D3F7B1.elf` | `B6D3F7B1` | 63,208 B | 演示固件 |
| `main.c` | 见 `SHA256.txt` | 53,927 B | 对应源码（与 `sw/src_j3/main.c` 同） |
| `fw_q_build.log` | 见 `SHA256.txt` | 226 B | Vitis `rebuild_j3.tcl` 构建日志 |
| `fw_q_burn3.log` | 见 `SHA256.txt` | 964 B | 最终一次配对烧写日志（`PAIR_BURNED`） |
| `fw_q_fourtier.log` | 见 `SHA256.txt` | 1,456 B | 四档 UDP 全量 PASS |
| `fw_q_j3_M.log` / `_A.log` / `_B.log` | 见 `SHA256.txt` | 各 ~800 B | 官方分轮流程 J3 PASS |
| `fw_q_serial_final.log` | 见 `SHA256.txt` | 261 B | `Q` / `?` / `I` / `S` 原始回包（repr） |
| `fw_q_j3_M.json` | 见 `SHA256.txt` | 360 B | M 轮判据 JSON |

位流（不在本目录）：
`..\b31b_r2_2026-10-19_round3d\aurora_mem_bridge_r2_F6012BA0.bit`（`F6012BA0`）。

## 本轮板上验证（2026-10-22，COM7，9600 8N1）

| 项 | 结果 | 日志 |
|---|---|---|
| UDP 四档逐字节 | **PASS**：20/20、12/12、12/12、300/300 | `fw_q_fourtier.log` |
| J3 四链（重烧后分轮 M / A / B） | **PASS ×3**（A 恰缺 1 帧=预期） | `fw_q_j3_M/A/B.log` |
| `Q` / `?` | 回包见左表示例 | `fw_q_serial_final.log` |

> 说明：一次性 `--rounds MAB` 连跑时 `B` 曾报“收帧停摆 @1/256”，与 round3d 历史 run2 同类（复现指南 §11.2：J3 对起始态敏感）。按官方分轮流程重烧后 M/A/B 全 PASS；不是本次 `Q` 改动引入。

## 烧写

```powershell
Set-Location D:\FPGA
$arc = "D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d"
$fw  = "D:\FPGA\prj\project_11\out\archive\fw_q_2026-10-22"
cmd /c "`"D:\Xilinx\Vitis\2023.1\bin\xsct.bat`" D:\FPGA\prj\project_11\out\jb31b_burn_pair.tcl `"$arc\aurora_mem_bridge_r2_F6012BA0.bit`" `"$fw\j3_soft_r2_B6D3F7B1.elf`""
# 期望尾行： PAIR_BURNED
```

烧完按复现指南 §3 先发一次 `'d'`，再发 `Q`。

## 边界

- 9600 波特率下一行 `Q` 约 85 ms；**只在空闲/档间发**，流量中打印会阻塞服务循环、表现为丢帧（不是计数器坏了）。
- `Q` 只汇总桥①（`wm_wr/wm_rd/drop`）与 DMA 状态；桥② `mem2` 计数与双桥全量对账仍在 ILA，串口打不出。
- 逐字节判定 / 10MB SHA256 仍需主机侧脚本（板卡读不到 DDR 帧内容）。
