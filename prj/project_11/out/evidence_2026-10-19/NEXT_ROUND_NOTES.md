# NEXT-ROUND NOTES (2026-10-19 14:2x) — R2 round3c continuation

## 正在跑的后台作业

- job id: `pwsh-0bbc242e288d41a6`（`D:\FPGA\prj\project_11\out\r3c2_sweep_one_retry.ps1`）
  = round3c-lite（3 核，ILA4 已跳过）**ExtraTimingOpt 单掷实现重跑**。
- 日志：`out/r3c2_one.log` / `out/r3c2_one_console.log`（旧尝试见 `out/r3c2_sweep2*`、attempt1 存档目录）。
- 成功标志：console 出现 `V5_SWEEP1_OK: directive=ExtraTimingOpt wns=<>=0> whs=<>=0> bit=...`，
  产物 `out/aurora_mem_bridge.bit`（~9.99MB，新时间戳）、`scripts/probes.ltx`（3 核，84KB 级别）、`out/mb_ctrl.xsa`。
- 失败标志：`V5_SWEEP1_ALL_FAIL`。失败时保存日志并考虑：ILA5 probe5 再减位（去 ack_ui/intr_ui？）/ 或 ILA3 深度（已 1024 最小）/ 或换 place directive / 参考 attempt1 的 -0.029 与 300MHz `u_mem/u_wr_bytes` 路径族。

## 位流成功后立即做

1. 运行 `py out/r2_archive_round3c.py success` → 生成 `out/archive/b31b_r2_2026-10-19_round3c/SHA256.txt` 与 hash 命名副本；回填 `BUILD_STATUS.md §4`。
2. `out/evidence_2026-10-19/tools/r3c_pin.md §1` 回填（可发 script-tools 做）；核对 ltx 3 核/宽度（ILA0 110、ILA3 152、ILA5 82）。
3. 板验（板当前处于 round2f pair 楔死态，直接重烧即可；电源未断，无需用户操作）：
   - 烧 `out/archive/...round3c/aurora_mem_bridge_r2_<h8>.bit` + `j3_soft_r2_DB88C9D0_jk.elf`（绝对路径 + Get-FileHash；xsct `jb31b_burn_pair.tcl`）。
   - 串口：`py out/uart_probe.py --cmd U --wait 2 --drain 0.1 --raw` → `d` → `W`（期望 s2cr=00011003/s2sr=0/s2len=0/m2sr=1）。
   - ILA：`out/evidence_2026-10-19/tools/r3c_cap.tcl`，env：
     `R2_LTX=<归档ltx>`、`R2_OUT_DIR=out/evidence_2026-10-19`、`R2_TAG=r3cA`、
     `R2_STIM_CMD='ping -n 1 -w 900 192.168.1.10'`、`R2_TRIG_ILA5="<probe5名>=eq7'b0011001"`、
     `R3C_EXPECT_ILA_COUNT=3`、`R2_WAIT_MIN=1`；
     vivado batch 从 `D:\FPGA`（ASCII CWD）启动，日志重定向。
     若 probe5 名/宽不匹配（LTX 先看 `R3C_PROBE_MAP`），退 Run B：`R2_TRIG_ILA5="dbg_s2mm_tvalid=eq1'b1"`。
   - 楔死后：`r3c_cap.tcl` 再来一次 `R2_SNAPSHOT_ONLY=1`；`xsct tools/r3c_diag.tcl`；串口补测 U/W；保存一切。
   - 判读：`py tools/r3c_ila_analyze.py --dir out/evidence_2026-10-19 --pattern "R3C_r3cA*.csv"`，看 `R3C_ILA5_HYPOTHESIS`。
4. 判读结论 → 记录 §十八 补记 + 决定 round3d（audit/round3d_candidate.patch：邮箱看门狗/SLVERR/sticky/ASYNC_REG/拆分触发探针；或按 go_ui 结果修 GO 链）。

## 板端已知状态（本轮实测）

- round3b `02F7153A` + 诊断固件：'d' 后 ping 1 → UART 全静默；g_step=11；WA_S2CR=WA_S2SR=WA_S2LEN=WA_WREQ=WA_WDBG=0x80010056（跨 M01/M02 读回冻结 [L2]）；PC 0x738（uputc TX_FULL 轮询）。
- P/G/J/K 固件实验：无真实帧请求时 LENGTH/GO/跨从机写序均不楔死；帧到达不服务读路正常 ⇒ 楔死需"真实帧请求+服务使桥真进 STREAM"（[L1] K1）。
- round2f 原配（bit 8A8FE378 + ELF b614a2dc）**同样复现 ping 后静默** ⇒ "fix2 回归"无证据（[L1]）。
- 集成工具均已彩排可用：`r3c_diag.tcl`、`r3c_cap.tcl`（3 核 LTX 上 PRE/POST 正常）。

## 待办/坑

- 中文 CWD 下 implement_debug_core 子进程必失败（本轮实测）→ 所有构建脚本首行 `Set-Location D:\FPGA`。
- `.ps1` 改后必须复验 BOM（239,187,191）+ ParseFile（本轮 script-tools 实测 edit 会剥 BOM）。
- 证据缺口：P/J/K 为会话内转录（见 `out/evidence_2026-10-19/R3C_serial_PJK_rehearsal.log.md`）；如需更硬证据可再跑一遍并落原始串口 log。
