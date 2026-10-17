# 收口文档最终文本（可直接整段粘贴）

- **版本**：2026-10-17 21:42 定稿（对应修复版位流 `c8cd3a32`、S0–S8 全 PASS、四判据全过）。
- **用途**：Lead 落盘 vault/docs 时**逐段复制**；本文件只给"最终文本"，不再含过程说明。
- **纪律**：docs 镜像**必须脱敏**（用户名→`***`，人名→`前辈`），**不得**把 vault 原文直接覆盖进 `docs/`；本次 vault 与 docs 的 3 份目标文件当前逐字节相同（`记录 D4024C79`/`工作清单 C8FFFE60`/`agent A924316F`），同步时先改 vault 再**重写** docs 副本并复检敏感串。
- **J3 最终口径**：**带 `--dma`**（脚本已修 `warm_probe=(not args.dma)`；`j3_fourchains.ps1` 已改 `--dma`；`retire_s0_s8.ps1` 内 S8b 的"不带 --dma"是旧文案，Lead 同步改文字）。

---

## 1. `D:\FPGA\AGENTS.md`

### 1.1 §十 路线 B 状态长句（L214 末尾追加，接在原文最后一句后）

> `→ **10-17 晚 R1 读侧收口完成（[L4] 定案）**：修复版退役位流 **`c8cd3a32`**（SHA256 `c8cd3a32…76ba80`，9,746,300 B；构建 `SWEEP_ExtraTimingOpt: WNS=0.004 WHS=0.004`/`V5_SWEEP_OK`/DRC 0 Errors；RTL blob `7fe880e`；探针 `352a5f28…`；xsa `c9b52dd7…`）+ ELF `2961b585` 上 **S0–S8 全 PASS、四判据全过**：`S2b` 不发 `'d'` ping 0/1（位流身份=退役版）；`S3` req.bit24=1/mode=1；`S4` 单帧 ping 1/1 + NIC ReceivedBytes +74 + `WM_WR/WM_RD` 各 +1；`S5` ping 4/4 + Bytes +296 + 各 +4；`S6` emit 字段正确 + 线上 4/4；`S7` 桥级 ILA 桥② `dbg_mem2_rd_frm` 777→781（+4）、`ost` 恒 0（旧位流同口径为读 0/ost 19→23）；`S8b` J3 四链（带 `--dma`）M/A/B 全 PASS（`[M] inv=30417 miss=0`、`[A] inv=30171 miss=[5100]`=恰帧#100、`[B] inv=30417`）；`S8c` 发射流与绿参考掩码后 **ndiff_after_mask=0（ISOMORPHIC=YES）**；`S8d` 四档零回归 PASS（20/20·12/12·12/12·300/300）。**根因 [L4]**：8afa168 在共享模块 `axi4_master_bridge.v` 内无条件删硬件读 FSM，误伤 `HAS_DMA=0` 桥②（无 DMA shim）⇒ 读 FSM 永泊 R_DRET + 读数据口无源 ⇒ 泵B 无输入、出向帧不上线；修复 = 读 FSM 按 `HAS_DMA` 参数化（`HAS_DMA=1` DMA-only 不变 / `HAS_DMA=0` 恢复 R_AR/R_R/R_UNPACK/R_FIN）+ `shim_frame_done` tie-0 + W2/W4 TB 显式 `.HAS_DMA(0)`。**另定案独立软件侧 [L4]**：J3 判据脚本 `j3_soft_verify.py` 的 DMA 预热帧缺陷（SEQ 窗预热帧占 1 槽 ⇒ `wr+255` 级联）已修 `warm_probe=(not args.dma)` 并复验 PASS，与 RTL/位流无关。**下一步 = R2（B3-2 桥①写侧换层 S2MM）**。详见记录 §三之二十 与 `prj/project_11/out/evidence_2026-10-17/R1_evidence_index.md`。`

### 1.2 §十 未决项（L215）——④⑥ 两行整行替换

> `④ ~~退役位流数据面未通~~ **已闭合（10-17 晚，[L4]）**：修复版 `c8cd3a32` 上 S0–S8 全 PASS + 四判据全过（S7 桥② 读帧 +4/ost 恒 0 为直接闭合证据）；旧位流 `0ecb8438` 的"桥② 写 +4/读 0/ost 19→23"是其缺陷直证。`
>
> `⑥ ~~归因未定~~ **已定案（10-17 晚，[L4]）**：根因 = 共享模块退役误伤 `HAS_DMA=0` 桥② 读 FSM（非"归档位流不对应 RTL"、非网表差异；H2/H4 候选排除）。另：J3 判据脚本缺陷（DMA 预热帧占槽）作为**独立 [L4]** 一并修复复验。`

其余 ①②③⑤ 项原文保留。

### 1.3 §九 坑账本新增 #55 / #56（接在 #54 之后）

> `| 55 | **共享模块的"退役/删除"必须按实例作用域做——无条件删实例级读 FSM 会让 HAS_DMA=0 的实例死锁/无源** | 2026-10-17 实证（prj11 R1）：8afa168 在 `axi4_master_bridge.v`（u_mem/u_mem2 **两实例共用**）里把 R_PRE 的 `else if (dma_engine)` 改成无条件 DMA 并删 R_AR/R_R/R_UNPACK/R_FIN ⇒ `HAS_DMA=0` 的桥②（u_mem2，无 DMA shim）读 FSM 永泊 R_DRET（`shim_frame_done` 无驱动恒 0）+ 读数据口无源（`brf_wr_en` 无人置位）⇒ 泵B 无输入、出向帧不上线。ILA 前后对照：旧位流桥② 写帧 +4/读帧恒 0/ost 19→23；修复位流 读帧 +4/ost 恒 0。**修法 = 读 FSM 按 `HAS_DMA` 参数化门控（HAS_DMA=1 DMA-only / HAS_DMA=0 恢复硬件读）+ `shim_frame_done` tie-0**；修复版 `c8cd3a32` S0–S8/四判据全过。**纪律 = 删逻辑前枚举全部实例与参数化差异；结构差异用参数（HAS_DMA）守卫、不用运行态位（dma_engine）**。详见记录 §三之二十 §2/§3/§9-②③。 |`
>
> `| 56 | **判据工具自身也是被测件：J3 预热帧在 DMA 模式槽泄漏 ⇒ `wr+255` 级联假 FAIL；失败不得重试** | 2026-10-17 实证（prj11 R1）：绿位流 `--dma` 下 J3 四链连续三次 `[M] wr+255`（写少 1 帧）→ 读阶段不启动 → 槽满级联 FAIL；根因 = `scripts/j3_soft_verify.py` 的 `run_round()` 在 SEQOK 后无条件发 1 个预热帧，DMA 模式下该帧读请求永泊 `R_DRET` 占 1 槽（软核正停在 `round_command` 等 GO、驻留服务不在跑），写阶段第 256 帧槽满被拒；桥模式由硬件读引擎自动退休故 PASS。**修法 = `warm_probe=(not args.dma)`（--dma 跳过预热帧）**，复验 `green_dma_j3_run5_warmfix.log` PASS；修复版位流上 S8b（带 `--dma`）M/A/B 全 PASS。附纪律：J3 必须**新烧录后**跑；跑前 `'S'`+只读检查 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍（清槽）；**`wr+255`/收帧停摆不得重试**（级联假 FAIL + 可能半楔死需重烧）；轮末 `R_ENGINE=0`/`R_MODE=RND` ⇒ 后续 ping 判据重发 `'d'`/`'S'`。另：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ **NIC 主判据用 `ReceivedBytes`**（单帧 74B / 4 帧 296B），`ReceivedUnicast` 恒 0 不可用。详见记录 §三之二十 §4.2/§9-⑧⑨。 |`

---

## 2. `C:\Users\***\Desktop\毕设\操作文档\阶段三_prj11_路线B剩余工作清单_2026-10-16.md`

### 2.1 §一 总览 · R1 行（L21）整行替换

> `| **R1** | **读侧收尾：退役桥②读引擎** | **ping/ARP ✓ + 四档逐字节 ✓ + J3/J3′ + 负向 A/B**（DMA 为唯一读出路径） | ~~驻留服务改非阻塞版 → 重跑判据~~ | ✅ **已收口（10-17 晚，[L4]）**：① 驻留静默根因定案修复（§三之十九）；② 退役位流在**有效序列**下桥① 读出正常（`WM_WR/WM_RD` +4）；③ ILA 定位根因 = 8afa168 共享模块退役误伤 `HAS_DMA=0` 桥② 读 FSM（写 +4/读恒 0/ost 19→23）；④ 修复 = 读 FSM 按 `HAS_DMA` 参数化（工作树 4 M 文件）；⑤ **修复版位流 `c8cd3a32`（WNS/WHS +0.004）上 S0–S8 全 PASS、四判据全过**：S2b 身份判据、S4 单帧端到端、S5 ping 4/4+Bytes+296、S6 emit 正确、S7 桥② 读帧 +4/ost 恒 0、S8b J3 四链（`--dma`）全 PASS、S8c 发射流 ISOMORPHIC、S8d 四档 PASS。另定案独立软件侧 [L4]：J3 脚本 DMA 预热帧缺陷已修复复验（详见记录 §三之二十）。**下一步 R2（B3-2 写侧 S2MM）** |`

### 2.2 §二之七 后新增 **§二之八**（整段插入）

> ```markdown
> ### 二之八、10-17 晚：R1 读侧收口完成（[L4] 定案）——根因、修复、S0–S8 与四判据（记录 §三之二十）
>
> **结论**：修复版退役位流 **`c8cd3a32`**（SHA256 `c8cd3a32…76ba80`，9,746,300 B；WNS/WHS **+0.004**；RTL blob `7fe880e`；探针 `352a5f28…`）上 **S0–S8 全 PASS、四判据全过**；「DMA 为唯一读出路径」在退役位流上成立。原始日志全部在 `out/evidence_2026-10-17/`（索引 `R1_evidence_index.md`）。
>
> - **有效判据（旧位流 `3aa600aa`）**：`'d'`→ping×4 中途不跑 M/A/B ⇒ `WM_WR/WM_RD` 各 11→15（+4）、`emit`={len=86,slot 10→14,byte0=0x55}、`arl` slot 10→14；但 ping 0/4、NIC delta=0 ⇒ 桥① 读侧/发射字段正常，故障在"桥① 发射口之后"（`clean_engine1_ping_204321.log`）。
> - **根因（[L4]）**：`8afa168` 在**两桥共用**的 `rtl/axi4_master_bridge.v` 里无条件删硬件读 FSM（R_AR/R_R/R_UNPACK/R_FIN）并让 R_PRE 无条件进 R_DRET；`u_mem2` 是 `HAS_DMA(0)`、无 DMA shim ⇒ `shim_frame_done` 无驱动（恒 0）+ `brf_wr_en` 无人置位 ⇒ 读 FSM 永久停泊、读数据口无源 ⇒ 泵B 无输入、出向帧不上线。
> - **板级前后对照（S7，[L4]）**：旧位流 `0ecb8438` 桥② 写帧 19→23、**读帧恒 0**、ost 19→23；修复位流 `c8cd3a32` 桥② 写帧 777→781、**读帧 777→781（+4）**、ost 恒 0；桥① 同轮 +4/+4、ost 0（`ilacap_counters_summary.txt` / `ilacap_rdfix_counters_summary.txt`）。
> - **修复（工作树 4 个 M 文件，未提交）**：① 读 FSM 按 `HAS_DMA` 参数化（`HAS_DMA=1` DMA-only 不变 / `HAS_DMA=0` 恢复硬件读）+ `shim_frame_done` tie-0；② W2/W4 TB 显式 `.HAS_DMA(0)`；③ `scripts/j3_soft_verify.py`：`run_round(..., warm_probe=True)`，`--dma` 时跳过预热帧（独立 [L4]，见下）。
> - **S0–S8（`s0s8_20261017_213020.log`，`S0S8_RESULT: PASS`，exit 0）**：S0 PASS（WNS/WHS +0.004/成功标记/bit8=c8cd3a32/elf8=2961b585）；S1 PASS（绿 `708f15a4`+`2961b585` ping 3/3、'L' 应答、邻居 Permanent）；S2a PASS（M 轮 1 帧未完成=非身份判据）；**S2b PASS（不发 'd' ping 0/1、NIC delta=0 ⇒ 位流身份=退役版）**；S3 PASS（req.bit24=1&mode=1、bit25=0、slot=2 len=86）；S3b PASS（wmwr==wmrd&sticky=0 两拍）；**S4 PASS（单帧 ping 1/1、NIC ReceivedBytes +74、WM_WR+1/WM_RD+1）**；**S5 PASS（ping 4/4、Bytes +296、WM_WR+4/WM_RD+4）**；**S6 PASS（emit 正确+线上 4/4）**；S7 由 Lead 补跑 PASS；**S8b PASS（J3 四链带 `--dma`：`[M] inv=30417 miss=0` / `[A] inv=30171 miss=[5100]`=恰帧#100 / `[B] inv=30417`；`[B2-SOFT-VERIFY] PASS`）**；**S8c PASS（`rdcap2_rdfix.csv` 1526B/前导 OK；vs 绿 `rdcap2_green.csv` 掩 dst(8–13)+IP-ID(26–27)+csum(32–33)+FCS 后 `ndiff_after_mask=0` ISOMORPHIC=YES）**；**S8d PASS（四档 20/20·12/12·12/12·300/300；`DDR_VERIFY: PASS`）**。
> - **J3 判据脚本缺陷（独立 [L4]，与 RTL/位流无关）**：绿位流 `--dma` 下 J3 连续 FAIL（`[M] wr+255` → 读阶段不启动 → 级联）根因 = `j3_soft_verify.py` 在 SEQ 窗无条件发预热帧、DMA 模式下占 1 槽；桥模式由硬件读引擎自动退休故 PASS。修复 `warm_probe=(not args.dma)`，复验 `green_dma_j3_run5_warmfix.log` PASS；修复版位流 S8b 亦 PASS。**最终 J3 口径 = 带 `--dma`**（`j3_fourchains.ps1` 已改；`retire_s0_s8.ps1` 的 S8b 旧文案"不带 --dma"待同步）。纪律：J3 必须新烧录后跑、`wr+255`/收帧停摆不重试、J3 后 ping 需重发 `'d'`/`'S'`。
> - **NIC 判据口径**：静态 ARP ⇒ 板自发帧 dst=广播 ⇒ `ReceivedUnicast` 恒 0；主判据 = **`ReceivedBytes`**（单帧 ≥74、4 帧 ≥296）。旧"Unicast delta"表述作废。
> - **对旧结论的更正（补记引用，原文不动）**：补四 的"两侧 wmwr/wmrd 1/1→4/4 逐项相同"表与 `s2_s6_204148.log` 不符（该轮 S5 无效）；`rtl_audit_204519.md` 的"u_mem2 未被退役影响"判断错误；§补二 的"归档位流不对应 RTL/网表差异"候选（H2/H4）已排除。
> - **运维修正**：`out/aurora_mem_bridge.bit` 现为修复版 `c8cd3a32`（下次构建会变）⇒ 一律用归档绝对路径 + 先核 hash；退役位流每次上电先发一次 `'d'`（翻转语义，需 `'U'` 双确认 mode+bit24，不要盲发两次）。
> ```

### 2.3 §二之七 表后"过程纪律"前追加一行

> `> **10-17 晚补充**：本表 S4 的 `manual_round.py COM5 1` 口径已废弃——S4 改为 `ping -n 1` 单帧（NIC ReceivedBytes ≥74 + `WM` 前后差分）；S7 主判据改为桥② ILA 计数（`dbg_mem2_rd_frm` 前进/`ost` 回落）；发射流同构须掩 dst(8–13)+IP-ID+csum+FCS。最终执行以 `out/retire_s0_s8.ps1` + `out/S0S8_DESIGN.md` 为准。`

---

## 3. `C:\Users\***\Desktop\毕设\agent.md`

### 3.1 「当前状态」大 bullet（L116）末尾追加

> `……**10-17 晚 R1 读侧收口完成（[L4]）**：修复版位流 `c8cd3a32`（WNS/WHS +0.004）+ ELF `2961b585` 上 **S0–S8 全 PASS、四判据全过**（S4 单帧 1/1+Bytes+74；S5 ping 4/4+Bytes+296+WM 各 +4；S7 桥② 读帧 777→781/ost 恒 0；S8b J3 四链带 `--dma` 全 PASS；S8c 发射流 vs 绿参考掩码后 ndiff=0；S8d 四档 PASS）。根因 [L4] = 8afa168 共享模块退役误伤 `HAS_DMA=0` 桥② 读 FSM；修复 = 读 FSM 按 `HAS_DMA` 参数化。另：J3 判据脚本 DMA 预热帧缺陷已修复复验（独立 [L4]）。**下一步 R2（B3-2 写侧 S2MM）**。详见记录 §三之二十。`

### 3.2 「★ 10-17 日场结论」节末（L165 后）追加

> ```markdown
> ### ★ 10-17 晚场结论：R1 读侧收口完成（[L4]）——修复版位流 S0–S8 + 四判据全过
>
> - **配置**：修复版退役位流 **`c8cd3a32`**（SHA256 `c8cd3a32…76ba80`，9,746,300 B；构建 WNS/WHS **+0.004**、`V5_SWEEP_OK`、DRC 0 Errors；RTL blob `7fe880e`；探针 `352a5f28…`；xsa `c9b52dd7…`）+ ELF `2961b585`。
> - **S0–S8（`s0s8_20261017_213020.log`，`S0S8_RESULT: PASS`）**：S0 PASS；S1 绿基线 PASS；S2a/S2b PASS（**不发 'd' ping 0/1 ⇒ 位流身份=退役版**）；S3 PASS（req.bit24=1/mode=1）；S3b PASS；**S4 PASS（ping 1/1、NIC ReceivedBytes+74、WM_WR/WM_RD +1）**；**S5 PASS（ping 4/4、Bytes+296、各 +4）**；**S6 PASS（emit 正确+线上 4/4）**；S7 PASS（桥② `dbg_mem2_rd_frm` 777→781、ost 恒 0；旧位流同口径读 0/ost 19→23）；**S8b PASS（J3 四链带 `--dma`：M inv=30417/miss=0、A inv=30171/miss=[5100]=恰帧#100、B inv=30417）**；**S8c PASS（发射流与绿参考掩码后 ndiff_after_mask=0 ISOMORPHIC=YES）**；**S8d PASS（四档 20/20·12/12·12/12·300/300、DDR_VERIFY PASS）**。
> - **根因 [L4]**：8afa168 在**两桥共用**的 `axi4_master_bridge.v` 内无条件删硬件读 FSM，误伤 `HAS_DMA=0` 桥②（无 DMA shim）⇒ 读 FSM 永泊 R_DRET + 读数据口无源 ⇒ 泵B 无输入、出向帧不上线。**修复** = 读 FSM 按 `HAS_DMA` 参数化 + `shim_frame_done` tie-0 + W2/W4 TB 显式 `.HAS_DMA(0)`。
> - **独立软件侧 [L4]**：J3 判据脚本 `j3_soft_verify.py` 的 DMA 预热帧缺陷（SEQ 窗预热帧占 1 槽 ⇒ `wr+255` 级联）已修 `warm_probe=(not args.dma)` 并复验 PASS；**最终 J3 口径 = 带 `--dma`**。
> - **NIC 口径**：静态 ARP ⇒ 板自发帧广播 dst ⇒ 主判据 = `ReceivedBytes`（单帧 ≥74、4 帧 ≥296），`ReceivedUnicast` 恒 0。
> - **下一步**：R2（B3-2 桥①写侧换层 S2MM，DMA 描述符驱动写槽，判据 = 四档 + 10MB 100%+SHA + 双桥计数对账）。
> ```

### 3.3 运维口径两行更正（L160/L161 一带）

- `'d'` 句：`**退役位流每次上电必须先发一次 `'d'` 才有桥① 读出路径**（`'d'` 是翻转：`'U'` 回读 mode+req.bit24 双确认，最多翻转 3 次；不要盲发两次——第二下关掉 DMA 驻留服务）。`
- 烧录纪律：`烧录一律**绝对路径 + 先 Get-FileHash**，不引用默认名产物；`out/aurora_mem_bridge.bit` 现为修复版 `c8cd3a32`（下次构建会变），归档在 `out/archive/b31b_rdfix_2026-10-17/`。`
- S0–S8 行补充：`**S7 判别观测 = 桥② ILA 计数**（`dbg_mem2_rd_frm` 前进/`ost` 回落）；**NIC 主判据 = ReceivedBytes**；J3 带 `--dma` 且必须新烧录后跑、失败不重试。`

---

## 4. `D:\FPGA\docs\` 镜像（脱敏同步清单）

**脱敏规则**：用户名/本机路径中的用户名 → `***`（如 `C:\Users\***\`）；人名 → `前辈`；`[[wiki 双链]]` 按仓库惯例保留；**禁止**把 vault 原文直接 `copy` 覆盖 docs（先逐段复制到 docs 再脱敏，最后 `Select-String -Pattern '***|C:\\Users\\[^\\*]'` 复检 0 命中）。

| docs 目标文件 | 来源（vault） | 操作 | 当前状态（快照） |
|---|---|---|---|
| `D:\FPGA\docs\调试记录\阶段三_prj11_B3-1三主仲裁器与DMA读路径设计_2026-10-12.md` | `毕设\调试记录\` 同名 | 插入 `record_section_final.md` 正文（删其顶部元信息）；回填文末「§三、当前状态（末版快照）」L1008/L1009/L1010；在 §三之十九之补四 末尾加一行补四更正注 | 与 vault 逐字节相同（`D4024C79`，1012 行，L1002/L1003 为插入点） |
| `D:\FPGA\docs\操作文档\阶段三_prj11_路线B剩余工作清单_2026-10-16.md` | `毕设\操作文档\` 同名 | 按 §2.1 替换 R1 行；§二之七 后加一行；新增 §二之八（§2.2） | 与 vault 相同（`C8FFFE60`，107 行） |
| `D:\FPGA\docs\agent.md` | `毕设\agent.md` | 按 §3.1/§3.2/§3.3 同步 | 与 vault 相同（`A924316F`，165 行） |
| `D:\FPGA\docs\README.md` | — | **不新增 `.md` 文件 ⇒ 索引表与"当前 N 个"计数不变，无需改**；只跑 CI 第 6 项确认一致 | 二级标题取自一级标题，正文追加不影响索引行 |
| `D:\FPGA\docs\` 其它 | — | **无**（`out/evidence_*` 属工程内证据，不迁 docs；`S0S8_DESIGN.md` 留在 `prj/project_11/out/`） | — |

---

## 5. 落盘后自检

```powershell
# 1) 代码/工具侧：4 个 M 文件 + 新归档目录
git -C D:\FPGA status --short
git -C D:\FPGA hash-object prj/project_11/rtl/axi4_master_bridge.v      # 7fe880e…
git -C D:\FPGA hash-object prj/project_11/scripts/j3_soft_verify.py     # 59a2d7e…

# 2) 文档侧 CI（第 1/2/6 项重点）
& "C:\Users\***\AppData\Local\Python\pythoncore-3.14-64\python.exe" D:\FPGA\scripts\ci_check.py

# 3) docs 镜像脱敏复检（新增内容 0 命中）
Select-String -Path 'D:\FPGA\docs\调试记录\阶段三_prj11_B3-1三主仲裁器与DMA读路径设计_2026-10-12.md','D:\FPGA\docs\操作文档\阶段三_prj11_路线B剩余工作清单_2026-10-16.md','D:\FPGA\docs\agent.md' -Pattern '***|C:\\Users\\[^\\]'

# 4) 记录 PENDING 清零检查（只允许"未发生"类）
Select-String -Path 'C:\Users\***\Desktop\毕设\调试记录\阶段三_prj11_B3-1三主仲裁器与DMA读路径设计_2026-10-12.md' -Pattern 'PENDING'
```

**提交范围（建议）**：代码 `rtl/axi4_master_bridge.v` + `sim/mem_bridge_tb.sv` + `sim/w4_joint_tb.sv` + `scripts/j3_soft_verify.py`；新归档 `out/archive/b31b_rdfix_2026-10-17/`（其 `.bit/.ltx/.xsa/.log` 被 `.gitignore` 忽略，`SHA256.txt`/RTL 快照/`j3_soft_verify_rdfix.py` 可入库）；证据 `out/evidence_2026-10-17/*.md` 与可提交 `.csv`；文档 vault 3 份 + `AGENTS.md` + `docs/` 3 份镜像。
