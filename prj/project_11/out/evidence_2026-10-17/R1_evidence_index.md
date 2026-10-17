# R1 证据索引（2026-10-17 · prj11 路线 B 读侧收口）

- **用途**：2026-10-17 R1 收口的**唯一证据台账**——每一条结论/判据指向哪个原始文件、SHA256 指纹、依据等级。
- **生成**：2026-10-17 21:44（Asia/Shanghai，**最终版**：21:30–21:35 修复版位流 `c8cd3a32` 的 S0–S8、S7 ILA、S8c/S8d 与 J3 复验全部落盘），文档与证据管理员（Agent Team 成员 `docs-evidence`）。**结论：[L4] 定案（S0–S8 + 四判据全过）**。
- **写权限边界**：本目录（`prj/project_11/out/evidence_2026-10-17/`）是本人**唯一**写入区；未改 vault/docs/仓库文件、未 commit、未碰硬件（未跑 xsct/vivado/串口/ping）。
- **目录是活目录**：Lead 在 20:43–21:22 间持续追加产物（修复版构建、绿基线复跑、J3 诊断/修复验证、S0–S8 工具迭代）。表中 hash 为**快照时刻实测值**；晚于快照的新文件见 §7 PENDING，收口时补录（同一文件被覆盖后 hash 会变，以 §2 的"轮次留痕"为准）。
- **Hash 口径**：`Get-FileHash -Algorithm SHA256`，表中列**前 8 位**（按任务要求）；关键产物在 §3/§5 给**完整 64 位**。复算命令见 §9。

**依据等级（AGENTS.md §6a）**：[L4] 定案 · [L3] 板证实 · [L2] 对照成立 · [L1] 相容假说（只能写"假设"栏）。另设三类**非结论**标注：
`无效留痕`（实验无效/判据未取得，只保留过程）、`过程留痕`（抓取/工具过程，不直接支撑结论）、`离线准备`（工具/分析准备，非板上证据）。

---

## 1. 今日结论 → 证据映射（先看这张）

| # | 判据 / 结论 | 支撑证据（本目录） | 等级 | 取值状态 |
|---|---|---|---|---|
| **C1** | 退役位流上「DMA 为唯一读出路径」的桥① 读侧**是通的**：`'d'`→engine=1 后 ping×4，`WM_WR`/`WM_RD` 各 **11→15（+4）**，`emit` len=86/slot 10→14/首字节 0x55，`arl` slot 10→14 | `clean_engine1_ping_204321.log`；`r1cap_uart_pre3.log` / `r1cap_uart_post3.log`；`ilacap_pre_ui.csv`→`ilacap_post_ui.csv`（桥① `dbg_mem_rd_frm` 19→23、`ost`=0） | **[L3]** | **已取值** |
| **C2** | 桥① 发射口之后（Aurora→桥②）之前：**桥① 发射字节流字节级正确**（1526B、`55×7+D5` 前导、1526 拍无气泡；与归档绿参考仅差 dst MAC/IP-ID/IP 校验和/FCS）；且**同环境绿参考 `rdcap2_green.csv` vs 旧退役 `rdcap2_retired.csv`，掩 dst(8–13)+IP-ID(26–27)+IP cksum(32–33)+FCS 后逐字节相同（ndiff_after_mask=0，Lead 实测）** | `rdcap2_retired.csv` + `rdcap2_cmp_retired.log`（20:54 场次）；对照 `rdcap2_green.csv`（20:57 同环境绿参考）；绿 vs 退役同掩码比对结果（对比日志待归档，见 §7） | **[L3]** | **已取值**（判据口径须带 dst 掩码，见 §6-②） |
| **C3** | **根因：桥②（u_mem2，HAS_DMA=0）读 FSM 被 8afa168 的共享模块退役误伤 ⇒ 读路径死**（泵B 无输入 ⇒ 出向帧不上线） | `ilacap_pre/post_user.csv` + `ilacap_pre/post_ui.csv` + `ilacap_counters_summary.txt`：桥② `dbg_mem2_wr_frm` 19→23、**`dbg_mem2_rd_frm` 0→0**、`dbg_mem2_ost` 19→23；user 域 `dbg_mem2_u_rd`=0；叠加代码级（工作树 diff + `git show 8afa168`） | **[L3]** | **已取值**（修复复验 PENDING → 见 C6） |
| **C4** | 旧 `retire_s2_s6.ps1` 序列（S4 跑 M 轮 → S5 ping）是**无效实验**：绿/退役都会 0/N；两处机理 = M 轮末把 `R_ENGINE` 写回 0 + `R_MODE` 停在 RND | `s2_s6_201701.log`、`s2_s6_204148.log`；脚本 `out\retire_s2_s6.ps1`；固件 `sw/src_j3/main.c:358/375-379/443-444` | **[L3]** | **已定（作废留痕）** |
| **C5** | 记录 §三之十九之补四 的表（"两侧 `wmwr/wmrd` 1/1→4/4 逐项相同"）**与归档原始日志矛盾**：`s2_s6_204148.log` 实为 `WM_WR 2→7`、`WM_RD 2→2`（读侧零启动） | `s2_s6_204148.log`；`rtl_audit_204519.md` §5 H1/§8 解码表 | **事实 [L3] / 归因 [L2]** | **已定，需在记录正文更正** |
| **C6** | **修复后四判据全过（R1 收口）**：修复版 `c8cd3a32` 上 S0–S8 全 PASS；四判据（ping/ARP、四档逐字节、J3/J3′、负向 A/B）全部取值通过 | `s0s8_20261017_213020.log`（`S0S8_RESULT: PASS`）+ S7 `ilacap_rdfix_counters_summary.txt` + S8b `j3_fourchains_20261017_213200.log` + S8c `rdcap2_cmp_green_rdfix.log` + S8d `rdfix_4tier.log` | **[L4]** | **已取值（PASS）** |
| **C7** | 绿位流同机对照（今日同一 `'d'` 协议）：ping **4/4**（**NIC 实测 `ReceivedUnicast delta=0`、`ReceivedBytes delta=+296`=4×74B** ⇒ 板自发帧 dst 是广播、只进 Bytes）；四档零回归 **PASS**（20/20·12/12·12/12·300/300）；同环境绿发射字节流 1526B、`dbg_mem_rden=1` 连续 1526 拍、绿侧桥② 有读（`dbg_mem2_u_rd=11`） | `green_engine1_ping.log`、`green_engine1_uart_pre.log`（req bit24=1）、`green_engine1_4tier.log`、`rdcap2_green.csv`、`rdcap2_green_vivado.log`；NIC 口径与 +296 读数记于 `out\S0S8_DESIGN.md` §1.3/§5 | **[L3]** | **已取值**（作为 C2/C3 的对照；NIC 主判据=ReceivedBytes，见 C10） |
| **C7b** | **绿位流 `--dma` 模式 J3 四链三次 FAIL → 根因 [L4] = 判据工具 `scripts/j3_soft_verify.py` 自身缺陷**（`run_round()` 在 SEQ 窗无条件发 1 个预热帧；DMA 模式下该帧读请求永泊 `R_DRET` 占 1 槽 ⇒ 写阶段第 256 帧槽满被拒 ⇒ `wr+255` → 读阶段不启动 → 级联 FAIL；桥模式由硬件读引擎自动退休故 PASS）。**修复**：`run_round(..., warm_probe=True)`，`--dma` 时跳过（`warm_probe=(not args.dma)`，+15/−4）；**修复复验 [L4]：`green_dma_j3_run5_warmfix.log` PASS**（`[M] wr+256 rd+256 inv=32385 miss=0` / `[A] wr+256 rd+255 inv=32131 miss=[5356]`（恰帧#100 负向设计） / `[B] wr+256 rd+256` / `[B2-SOFT-VERIFY] PASS`） | 失败留痕：`green_engine1_j3_dma.log`、`run2`、`run3_nowarmup`、`green_dma_idle_j3_run1.log`；修复复验：`green_dma_j3_run5_warmfix.log`；桥模式对照 PASS：`green_bridge_j3_run1.log`；脚本 diff：`git diff scripts/j3_soft_verify.py`（blob `59a2d7e`） | **现象 [L3] / 根因+修复 [L4]** | **已定案**（软件脚本缺陷，**与 RTL/位流无关**；见 §8-⑤ 更正） |
| **C8** | 修复的离线正确性/完备性（独立复核）：与退役前 `3f847e3` 恢复块**逐字节相同**；`HAS_DMA=1` 下 R_AR..R_FIN 不可达、`HAS_DMA=0` 下 R_DRET 不可达；无多驱动；3 条非阻塞项 | `rtl_fix_review_205656.md`；`sim\bdma_run.log` / `xsim_run.log` / `w4_joint_run.log`（本目录已有 `sim_*_run.log` 归档副本） | **[L2]**（离线复核，非板上） | **已取值** |
| **C9** | **判据工具侧失败纪律（[L4] 定案）**：`wr+255`/收帧停摆**不得重试**（会级联假 FAIL 并把板卡留在"256 槽未读 + 读 FSM 泊 R_DRET"半楔死状态，需重烧）；J3 必须在**新烧录后**跑；跑完轮末固件把 `R_ENGINE` 写回 0、`R_MODE` 停在 RND ⇒ 后续 ping 判据必须重新 `'d'`+`'S'` | 失败系列 `green_engine1_j3_dma.log`/`run2`/`run3_nowarmup`（`wr+255`→后续 `wr+0` 级联）；干净态反例 `green_fresh_manual_round_256.log`（`DONE wr+256 rd+256`、`echo=256`）；设计口径 `out\S0S8_DESIGN.md` §1.7/§5-10 | **[L4]**（机制+修复复验闭环） | **已定案** |
| **C10** | **NIC 判据口径（[L3]）**：静态 ARP 邻居 ⇒ 板端学不到 PC MAC ⇒ 板自发帧 dst=广播 ⇒ **`ReceivedUnicast` delta 恒 0，主判据必须用 `ReceivedBytes`**（单帧 ICMP 回包 74B；ping×4 期望 ≥296B） | `S0S8_DESIGN.md` §1.3/§5-11；绿侧实测 ping 4/4 时 `Unicast=0/Bytes=+296`；S0–S8 脚本 21:07+ 的 S4/S5 判据已改为 `Bytes ≥74/≥296`（`s0s8_20261017_210715.log` 起） | **[L3]** | **已定案（工具已按此实现）** |
| **C11** | **S7 桥级 ILA 前后对照（[L4] 闭合）**：旧位流 `0ecb8438` 桥② 写帧 19→23、**读帧恒 0**、ost 19→23；修复位流 `c8cd3a32` 桥② 写帧 777→781、**读帧 777→781（+4）**、ost 恒 0；桥① 同轮各 +4、ost 0 | `ilacap_counters_summary.txt`（旧版）+ `ilacap_rdfix_counters_summary.txt` + `ilacap_pre/post_{user,ui}.csv`（当前为修复版轮）+ `r1cap_rdfix_vivado.log` | **[L4]** | **已取值（前后对照闭合）** |
| **C12** | **S8c/S8d 收口（[L4]）**：修复版发射流 `rdcap2_rdfix.csv` 1526B、与绿 `rdcap2_green.csv` 掩 dst+IP-ID+csum+FCS 后 **`ndiff_after_mask=0` / ISOMORPHIC=YES**；修复版四档 **`DDR_VERIFY: PASS`**（20/20·12/12·12/12·300/300） | `rdcap2_cmp_green_rdfix.log`；`rdfix_4tier.log` | **[L4]** | **已取值（PASS）** |

> **一句话**：C1/C2/C7 把"桥① 读侧 + 桥① 发射字节"洗清（且 C2 与同环境绿参考掩码后**逐字节同构**）；C3 直接测到**桥② 读帧数恒 0 而写帧数在涨** ⇒ 断点 = 桥② 读路径；C7b/C9 把"绿 DMA 下 J3 FAIL"归位为**判据脚本自身缺陷**（[L4]，已修复复验）；修复（工作树）离线复核通过；**上板复验（C6）尚未发生**。

---

## 2. 板上原始证据（`out\evidence_2026-10-17\`，逐个）

### 2.1 有效轮（可直接作判据）

| 文件 | 时间/大小 | SHA256前8 | 支撑什么 | 等级 | 备注 |
|---|---|---|---|---|---|
| `clean_engine1_ping_204321.log` | 20:43:37 / 3280 B（**UTF-16LE**） | `B56EB203` | **C1 的主证据**：`'d'`→`'U'`(engine=1)→ping×4→`'U'`；`WM_WR/WM_RD` 11→15；`emit`={len=86,slot=10→14,byte0=0x55}；`arl`=slot 10→14；NIC Unicast/Bytes delta=0；ping 0/4。**中途未跑 M/A/B**（有效序列） | **[L3]** | 该文件名/内容为"退役位流 `3aa600aa` + ELF `2961b585`"场次；与 §2.2 的 `s2_s6_*` 对比即"有效 vs 无效"样本 |
| `ilacap_pre_user.csv` | **21:34:18** / 324325 B | `94D90D63` | **S7 主证据（修复版 `c8cd3a32`，user 域）**：ping 前 2048 采样；桥② `dbg_mem2_u_wr`=`dbg_mem2_u_rd`=**777**、`dbg_mem_ost_s`=0 | **[L4]**（配合 post） | ⚠️ **同名文件已被 21:34 修复版轮覆盖**（旧退役轮 `0ecb8438` 的数据保留在 `ilacap_counters_summary.txt`，写 19/0、ost 19→23；见 §1.2 对照表） |
| `ilacap_post_user.csv` | **21:34:24** / 324325 B | `5D186135` | 修复版 ping 后：桥② `dbg_mem2_u_wr`=`dbg_mem2_u_rd`=**781**（各 +4）、`dbg_mem_ost_s`=0 | **[L4]** | 与 `ilacap_rdfix_counters_summary.txt` 一致 |
| `ilacap_pre_ui.csv` | **21:34:19** / 149733 B | `C14894CC` | **S7 主证据（修复版，ui 域）**：桥① `dbg_mem_wm/wr_frm/rd_frm`=777/777/777、`ost`=0；**桥② `dbg_mem2_wm/wr_frm/rd_frm`=777/777/777、`ost`=0** | **[L4]** | ⚠️ 同名文件已被修复版轮覆盖；旧退役轮数据（桥② rd_frm 恒 0/ost 19→23）见 `ilacap_counters_summary.txt` |
| `ilacap_post_ui.csv` | **21:34:24** / 149733 B | `62BD9C73` | 修复版 ping 后：桥① 781/781/781、`ost`=0；**桥② `wm/wr_frm/rd_frm`=781/781/781、`ost`=0 ⇒ 读路径已通** | **[L4]** | 与旧退役轮（读 0/ost 只增）形成前后对照 |
| `ilacap_counters_summary.txt` | 20:53:24 / 5270 B（**UTF-16**） | `C871AB8A` | **旧退役位流 `0ecb8438` 轮**的 ILA 汇总（桥② 写 +4/读恒 0/ost 19→23）——**未被覆盖，缺陷直证** | [L3]（旧版对照） | 修复版轮汇总见 `ilacap_rdfix_counters_summary.txt`（§10） |
| `r1cap_uart_pre3.log` | 20:52:36 / 1078 B（UTF-16） | `5A3AE4D6` | 第二轮 ping **前**软核自视快照：`mode=1`、`req=0x01120056`（bit24=1）、`wmwr/wmrd=19`、`emit` slot 18、`arl=0x0112000` | **[L3]** | 与 `ilacap_pre_*` 同轮（时间上先于抓取） |
| `r1cap_uart_post3.log` | 20:53:13 / 1078 B（UTF-16） | `8E967415` | 第二轮 ping **后**：`mode=1`、`wmwr/wmrd=23`（+4）、`emit` slot 22（0x16）、`arl=0x0116000` | **[L3]** | 与 `ilacap_post_*` 同轮 |
| `rdcap2_retired.csv` | 20:54:57 / 324325 B | `E5C57221` | **C2 主证据**：桥① 发射字节流，1526 个 `dbg_mem_rden=1` 连续采样，首 8B `55×7,D5` | **[L3]** | ILA1（`mem_rd_data[7:0]`+`dbg_mem_rden`）；触发 `dbg_mem_rden_1 eq 1` |
| `rdcap2_cmp_retired.log` | 20:54:58 / 1837 B | `E629D884` | **C2 判读**：len 1526=1526；前导 OK；严格差 14 B（首差 offset 8）；差异 = dst MAC(8–13)/IPv4 ID(26–27)/IP 校验和(32–33)/FCS(末4B)；掩掩码后仍 6 B 差（=dst MAC 不在 volatile 掩码内）⇒ **判据口径要补 dst 掩码**（见 §6） | **[L3]** | 参考流 A = 归档绿 `b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv` |
| `green_engine1_ping.log` | 20:56:32 / 896 B | `CA1B6054` | **C7 绿对照**：绿位流 + 同一 `'d'` 协议，ping **4/4**（0% loss，4 条 `Reply ... TTL=128`） | **[L3]** | 与 C1（退役 0/4）同协议对照；**NIC 读数（Unicast=0/Bytes=+296）不在本文件里**，见 `S0S8_DESIGN.md` §1.3/§5 与 C10 |
| `green_engine1_uart_pre.log` | 20:56:26 / 374 B（UTF-16） | `0996F799` | 绿侧 `'U'` 截断（id/req/reqX 3 行）：`req=0x01000000` ⇒ **bit24=1（engine=1）** | **[L3]** | 截断样本，只用于 engine 位断言 |
| `green_engine1_4tier.log` | 20:58:22 / 2174 B | `9BC899C9` | **C7 绿基线四档**：ping 20/20；基础档 12/12、槽深档 12/12、稳定档 300/300（100.0%、超时 0、损坏 0）；`DDR_VERIFY: PASS` ⇒ 绿位流桥引擎全环路可用 | **[L3]** | 可作为 S8"四档"的对照基线（前提：烧绿+默认引擎/`'S'`） |
| `green_engine1_j3_dma.log` | 20:59:52 / 15060 B | `500A6FFC` | **C7b 失败留痕（修复前）**：绿位流 `--dma` 下 J3 四链 FAIL（`[M] wr+255 rd+0`；`[A]/[B] wr+0 rd+0`；"收帧停摆 @0/256"；`[B2-SOFT-VERIFY] FAIL`） | **失败留痕（[L3] 现象）** | 根因已定案为脚本 `warm_probe` 缺陷（C7b）；保留为修复前对照，**不得当"位流回归"** |
| `rdcap2_green.csv` | 20:57:06 / 324325 B | `6A457167` | **C7/C2 同环境绿参考**：绿位流发射流 1526 拍 `dbg_mem_rden=1`；触发帧首字节 0x55；首采样 `dbg_mem2_u_wr=11`/`dbg_mem2_u_rd=11`（绿侧桥②有读！） | **[L3]** | 与 `rdcap2_retired.csv` 用同一工具/同一环境抓取 ⇒ 解决 dst MAC 环境差 |
| `rdcap2_green_vivado.log` | 20:57:06 / 5089 B | `B0368337` | 绿抓取过程：ILA1、39 probes、`RDCAP2_DONE`、CSV 2048 samples | [过程留痕] | ltx = `b31b_v5rtl_2026-10-16\probes.ltx` |
| `rdcap2_send_retired_20261017_205704.log` | 20:57:06 / 392 B | `45FA2237` | 20:57 发送端：`ECHO_COUNT=1 MATCH=YES`（**绿位流场次**；文件名 mode=retired 是工具默认标签，**名不副实**，见 §6-④） | [过程留痕] | 对应 `rdcap2_green_vivado.log` 的 SEND |
| `rdcap2_send_retired_20261017_205449.log` | 20:54:57 / 258 B | `BC7C11CA` | 20:54 发送端（退役位流）：`ECHO_COUNT=0`（符合"桥② 死、上行无回显"预期） | [过程留痕] | 与 `rdcap2_retired` 同轮 |
| `r1cap3_vivado.log` | 20:53:08 / 3221 B | `3D6C5D81` | **第二轮抓取有效性**：`GRAB_PRE_USER/UI`+ping+`GRAB_POST_USER/UI` OK、`R1CAP_DONE` ⇒ 当前 `ilacap_*.csv` 出自本轮 | [过程留痕] | 与 `r1cap_uart_pre3/post3.log` 时间对齐 |
| `rtl_fix_review_205656.md` | 20:59:04 / 27628 B | `888B9B91` | **C8 独立复核**：修复完备/单一驱动/与 `3f847e3` 逐字节等价；`dma_engine` 端口已无消费者；给上板预测 P1–P7 + 失败矩阵 + 3 条非阻塞项 | **[L2]**（离线） | 复核对象 = 工作树未提交改动（blob `7fe880e`）；文件 20:59:04 有小幅更新（首版 20:57:42/27482B，结论未变） |

### 2.2 无效/失效实验（**不得作为结论证据**）

| 文件 | 时间/大小 | SHA256前8 | 为什么无效 | 留痕价值 |
|---|---|---|---|---|
| `s2_s6_204148.log` | 20:42:35 / 3079 B | `DF13BE1B` | 旧 S2–S6 序列：S4 跑 `manual_round 1`（M 轮）⇒ 轮末 `R_ENGINE=0`、`R_MODE` 留 RND ⇒ **S5 ping 期间读侧根本不启动**（S6 解码 `WM_WR 2→7`、`WM_RD 2→2`） | **C4/C5 证据**；也是"§补四 表与原始日志矛盾"的原始日志 |
| `s2_s6_201701.log` | 20:17:48 / 3085 B | `FBC4D684` | 同上（`0ecb8438` + `2961b585` 场次）：S5 ping 0/4、`WM_RD` 不涨 | C4 的第二个独立样本 |
| `r1cap_uart_pre.log` / `r1cap_uart_post.log` | 20:50:58 / 20:51:33 / 各 1078 B | `DFD7769D` / `EFD98683` | **第一轮 ILA 抓取（20:51）**：`'U' mode=0` ⇒ 当时 engine=**bridge**（`'d'` 是翻转，第一轮被翻回）⇒ 该轮 `ilacap_*` 已作废（CSV 已被第二轮覆盖） | 留痕"第一轮无效"的判定依据（配合 `r1cap_vivado.log`） |
| `r1cap_uart_post2.log` | 20:52:25 / 1078 B | `5A3AE4D6` | 第二轮切换过程的中间快照（`mode=1`、19/19），无 ping 前后差语义 | 过程留痕 |
| `r1cap_uart_pre2.log` | 20:51:56 / 374 B | `FDD6BDC7` | 截断输出（仅 id/req/reqX 3 行）；`req=0x01120056` bit24=1 | 过程留痕（不单独立论） |
| `clean_engine1_ping_204258.log` | 20:43:15 / 120 B | `FD27663F` | 内容仅 13 行 `[%s] %s`（printf 格式串未解析）⇒ 抓取失败 | 无效留痕 |
| `r1cap_vivado.log` | 20:51:28 / 3106 B | `DF4F6B06` | 第一轮抓取流程（GRAB OK、R1CAP_DONE），但**该轮 engine=0 无效**；其 CSV 已被覆盖 | 留痕：证明第一轮存在而非"没跑" |
| `r1cap2_vivado.log` | 20:52:20 / 2653 B | `E4D5251B` | 第二次抓取**失败**：`write_hw_ila_data` 缺 `-force` 报错退出 | 工具坑留痕 |
| `rdcap2_retired_vivado_10272.backup.log`（+`.jou`） | 20:54:08 / 3428 B | `3FE4969A` | 第一次字节流抓取**失败**：4 个 ILA 都 `mem_rd_data_probes=0` ⇒ "no ILA carrying a mem_rd_data* probe (ltx mismatch?)"（判据未取得） | 工具坑留痕；后续修 tcl 后成功（20:54:57 那轮） |
| `rdcap2_retired_vivado.log`（+`.jou`） | 20:54:57 / 5134 B | `BB740DD4` | 成功轮（ILA1 39 probes、trigger、`RDCAP2_DONE`） | 过程留痕（对应 `rdcap2_retired.csv`） |
| `rdcap2_send_bat_retired.log` | **21:35:02 / 1074 B** | `AC56A9DE` | 发送编排日志（20:54 与 20:57 两次运行**追加**写同一文件：先 `echo=0 match=NO`，后 `echo=1 match=YES`） | 过程留痕 | hash 为两次追加后的最终值；无单独判据价值 |

### 2.3 离线分析/审计（非板上证据）

> **路径基准**：§4 的 `sim\...` 与 §5 的 `rtl\...`/`sim\...` 均相对 `D:\FPGA\prj\project_11\`，不在本 evidence 目录内（`§6 索引覆盖检查`里它们显示"不在本目录"是预期）。
> **配套 `.jou`**：`rdcap2_green.jou`、`rdcap2_retired_vivado.jou`、`rdcap2_retired_vivado_10272.backup.jou` 是对应 `.log` 的 Vivado journal（同轮过程的伴生文件），不独立成判据，故不单列。

| 文件 | 时间/大小 | SHA256前8 | 内容与使用边界 |
|---|---|---|---|
| `rtl_audit_204519.md` | 20:47:34 / 31759 B | `7C7CA4BC` | 离线 RTL 审计（H1–H6、TX 两跳路径重建）。**已被后续板上证据更新**：其 §2 Δ5/§4.1 "u_mem2 未被退役影响"判断**错误**（漏看"读 FSM 在共享模块内、按参数展开"），见 §6-①；其 §5 H1（旧脚本 RND 使读侧不启动）被 C4 证实。保留原文不改，本索引记更正 |
| `rdcap_reference_analysis.md` | 20:51:24 / 22743 B | `D8F20F56` | 发射字节流取证**离线准备单**（归档绿流解析：1526B/前导/帧布局/掩码口径；触发方案；工具清单）。本轮 `rdcap2_*` 工具即按其实现；**不是板上结果** |
| `out\S0S8_DESIGN.md`（**out/ 根，不在本目录**） | 21:11:24 / 36364 B | `8EBAA048` | Lead 的 **S0–S8 判据设计说明**：环境/仪器口径（`'d'` 翻转、静态邻居副作用、`'U'` 解析、计数器语义、ping 前禁止跑轮）、逐步判据、旧脚本失效、J3 执行口径、NIC/掩码修正。**本记录 §三之二十 的判据口径与其一致**；[L2] 设计文档（非板上结果） |
| `out\retire_s0_s8.ps1` / `out\j3_fourchains.ps1`（**out/ 根**） | 21:10:49 / 21:11:09 · 70498 / 18406 B | `3C88A1DA` / `90CBF523` | S0–S8 一键上板判据脚本（DRY-RUN 默认、`-Run` 才执行；含 Set-EngineMode 双重确认、S2b 身份判据、ReceivedBytes 判据、NOT_OBTAINED 语义）与 J3 四链封装（逐轮独立调用、失败即停） | [L2] 工具（未提交/待入库） |

### 2.4 S0–S8 / J3 工具计划日志（**DRY-RUN，无板上结果**；Lead 21:02 起步）

| 文件 | 时间/大小 | SHA256前8 | 内容 | 等级 |
|---|---|---|---|---|
| `s0s8_20261017_210227.log` | 21:02:29 / 10628 B | `53852A54` | `out\retire_s0_s8.ps1` **DRY-RUN**：打印 S0–S8 完整判据计划（P0 预检通过：静态邻居 `Permanent`、NIC 已取初值、工具齐；S0/S1 SKIP 因未提供位流/构建日志/绿对；`S0S8_RESULT: SKIP (dry-run)`）。**无板上执行** | [过程留痕]（计划，非证据） |
| `s0s8_20261017_210314.log` | 21:03:15 / 12060 B | `DD31EEF1` | `retire_s0_s8.ps1` **DRY-RUN 自检（带旧退役位流参数）**：`-Bit=0ecb8438`、`-BuildLog=build_retire_sweep3.log` ⇒ **S0 PASS**（WNS=0/WHS=0.004、成功标记有、bit8=0ecb8438/elf8=2961b585）；S1–S8 仍为计划。**注意：这是旧退役版 `0ecb8438` 的自检，不是修复版 S0**。另记：S2 计划含加严判据 S2b（engine=0 + `'S'` + ping `-n 1` 必须 0 回包 + NIC delta=0 = 真正的位流身份判据） | [过程留痕]（**S0 判据逻辑已验证**；修复版 S0 PENDING） |
| `j3_fourchains_20261017_210239.log` | 21:02:39 / 1766 B | `0610723B` | `out\j3_fourchains.ps1` **DRY-RUN**：DMA/桥两模式各 M/A/B（nslots=256）计划 + `'d'` 翻转确认逻辑；`FOURCHAINS_RESULT: SKIP (dry-run)` | [过程留痕]（计划，非证据） |
| `j3_fourchains_20261017_210342.log` / `j3_fourchains_20261017_210343.log` | 21:03:42 / 21:03:43 · 各 1973 B | `B71F0F27` / `3B8FBEA8` | 工具迭代：同内容两次 DRY-RUN（计划参数微调） | [过程留痕] |
| `s0s8_20261017_210343.log` | 21:03:45 / 11135 B | `45E49FC9` | DRY-RUN 自检：补齐 `manual_round COM5 1` 计划与 S2b；S0 SKIP（未给 args） | [过程留痕] |
| `s0s8_20261017_210715.log` / `s0s8_20261017_210732.log` | 21:07:17 / 21:07:34 · 各 11751 B | `2C311000` / `457DD1E1` | **NIC 口径升级**：初始读数改为 `ReceivedBytes/ReceivedBroadcast/ReceivedUnicast` 三元组，判据改为 `Bytes ≥74`（S4）/`≥296`（S5）并注明"Unicast 恒 0 不可用"；S8 改为"J3 四链（退役位流只跑 --dma）" | [过程留痕]（口径升级落盘） |
| `j3_fourchains_20261017_210717.log` / `j3_fourchains_20261017_210731.log` / `j3_fourchains_20261017_210732.log` | 各 ~1.8–2.0 KB | `66125EA9` / `17EE0825` / `957EB068` | J3 封装口径迭代（模式/参数微调） | [过程留痕] |
| `s0s8_20261017_211050.log` / `s0s8_20261017_211110.log` / `s0s8_20261017_211131.log` | 各 11984 B | `3EFFA975` / `007E2EE9` / `FCF0C741` | 最终 S0–S8 计划（S8 改为"J3 四链**不带 --dma** 跑 M/A/B"、加"不要预先 'd'"；NIC 判据稳定为 Bytes） | [过程留痕]（最终口径） |
| `j3_fourchains_20261017_211052.log` / `j3_fourchains_20261017_211112.log` / `j3_fourchains_20261017_211133.log` | 各 ~2.3 KB | `634E966A` / `AC02185B` / `12E0C64D` | **最终 J3 封装设计**（21:11:33，`12E0C64D`）：不带 `--dma` 跑 M/A/B；前置 `'S'`+只读检查 `wmwr==wmrd` 且 `req.bit25=0` 连续两拍；**任一轮 FAIL 即停、不重试**；`wr+255`/收帧停摆 ⇒「判据未取得 + 板卡需重烧」 | [L2] 工具设计（判据口径） |

> 判读提示：这些是**工具自检/计划**，不得当"判据已取"。真正的 S0–S8 结果将以 `-Run` 后的 `s0s8_*.log`（含 `S0S8_RESULT: PASS/FAIL`）落盘（见 §7 PENDING）。工具口径已把 S4 从"`manual_round 1`"改为 **`ping -n 1` 单帧**（避免 M 轮副作用），NIC 判据从 `ReceivedUnicast` 改为 **`ReceivedBytes`**（C10），均与记录 §三之二十 §9 的教训一致。

### 2.5 J3 诊断 / 修复复验 / 绿基线复跑系列（20:59–21:18，[L4] 定案链）

> 背景：绿位流 `--dma` 下 J3 连续 FAIL → 定位为**判据脚本自身缺陷**（C7b）→ 修复 `scripts/j3_soft_verify.py`（`warm_probe` 参数，`--dma` 时跳过预热帧）→ 21:17 复验 PASS。下列日志按时间构成完整证据链。

| 文件 | 时间/大小 | SHA256前8 | 内容 | 等级 |
|---|---|---|---|---|
| `green_dma_predrain_uart.log` | 21:04:30 / 1078 B（UTF-16） | `8F828428` | **清槽前置实测**（只读 `'U'`）：`wmwr=wmrd=4`、`req=0x01000000`（bit25=0）、`mode=1`、`emit` slot3 ⇒ 槽表干净（设计 §1.7/§5-10 的"清槽"判据） | **[L3]** |
| `green_engine1_j3_dma_run2.log` | 21:05:51 / 15060 B | `500A6FFC` | 修复前 `--dma` FAIL 重复（与 20:59:52 内容相同 ⇒ 同 hash）：`[M] wr+255` → 级联 FAIL | 失败留痕（修复前） |
| `green_manual_round_256.log` | 21:06:09 / 588 B | `DB7A424E` | **脏状态**（上一轮残留槽未清）下 `manual_round 256` → `WAITWR-FAIL got+0` ⇒ 证明"先清槽/新烧录"是必要前置 | 失败留痕 |
| `green_fresh_manual_round_256.log` | 21:06:55 / 680 B | `5F95F304` | **新烧绿后（不发 `'d'`）** `manual_round COM5 256` → `[B2] DONE t=M wr+256 rd+256 stall=0` + `echo=256/256` ⇒ 干净态基准 | **[L3]** |
| `green_engine1_j3_dma_run3_nowarmup.log` | 21:07:16 / 1688 B | `E8E39CDB` | "跳过预热"修正尝试仍 FAIL（板未新烧/脏状态）⇒ 证明仅改脚本不够、**必须新烧录后跑** | 失败留痕 |
| `green_bridge_j3_run1.log` | 21:07:53 / 2628 B | `56401E70` | **绿 + 桥模式（不带 `--dma`）J3 四链 PASS**：`[M] wr+256 rd+256 inv=32132 miss=0`；`[A] wr+256 rd+255 inv=31629 miss=[5356]`（`5256+100` ⇒ **恰帧#100**，负向设计）；`[B] PASS`；`[B2-SOFT-VERIFY] PASS` | **[L3]** |
| `green_dma_idle_j3_run1.log` | 21:13:25 / 15002 B | `2E8B9937` | 修复前 `--dma` FAIL（idle 前置版本） | 失败留痕 |
| `green_dma_manual_round_256.log` / `green_dma_preSI_manual_round_256.log` | 21:14:19 / 21:15:01 · 各 796 B | `B98B2E1E` / `C3076918` | **DMA 模式 `manual_round 256` PASS**（`DONE wr+256 rd+256 stall=0`、`echo=256/256`）；后者加 `'S'` 前置 ⇒ 表明"手动轮"在 DMA 下正常，问题只在 `j3_soft_verify --dma` 的预热帧 | **[L3]** 旁证 |
| `green_dma_j3_run5_warmfix.log` | **21:17:36 / 1699 B** | **`EC88E541`** | **修复复验 [L4]**：绿位流 + `--dma` + 新烧录 → `[B2-SOFT-VERIFY] PASS`；`[M] wr+256 rd+256 inv=32385 miss=0` / `[A] wr+256 rd+255 inv=32131 miss=[5356]`（恰帧#100）/ `[B] wr+256 rd+256` | **[L4]（机制+修复复验闭环）** |

---

## 3. 归档产物核验（任务 4：文件名 hash 是否一致）

### 3.1 `out\archive\b31b_rdclose_2026-10-16\SHA256.txt` —— 逐项实算核对

该文件存的是 **SHA256 前 16 位**（非全量），逐项 `Get-FileHash` 实测：

| SHA256.txt 登记（前16） | 文件 | 实算前16 | 一致？ |
|---|---|---|---|
| `3aa600aa2899c361` | `aurora_mem_bridge_rdclose_3aa600aa.bit` | `3AA600AA2899C361` | ✅ |
| `5c03db6b9784b27f` | `aurora_mem_bridge_tready_fix.v` | `5C03DB6B9784B27F` | ✅ |
| `bbf5688fdd52dc83` | `jb31b_burn_rdclose.tcl` | `BBF5688FDD52DC83` | ✅ |
| `be6e21b3b86560ac` | `jb31b_diag2.tcl` | `BE6E21B3B86560AC` | ✅ |
| `b0de75696c24d9d5` | `jb31b_diag_rdclose.tcl` | `B0DE75696C24D9D5` | ✅ |
| `423571e6a437d3a3` | `jb31b_restore_v5rtl.tcl` | `423571E6A437D3A3` | ✅ |
| `cb373568c6b50de0` | `main_rdclose_reverted.c` | `CB373568C6B50DE0` | ✅ |

⇒ **7/7 全一致**，`3aa600aa` 与文件名前缀一致。

### 3.2 `out\archive\b31b_n7_2026-10-17\` —— ELF 核验

- 目录内**只有** `j3_soft_n7_2961b585.elf`（46012 B），**没有** `SHA256.txt`（相邻 n4fix/n5/n6 目录同理，均只有一个 ELF）。
- 文件名前缀 `2961b585` 与实算 SHA256 前 8 位**一致** ✅（无 SHA256.txt 可逐行比对，只能"文件名↔实算"核对）。

### 3.3 关键产物完整 SHA256（任务要求记录）

| 产物 | 大小 | 完整 SHA256 |
|---|---|---|
| **退役位流 `3aa600aa`**（`archive\b31b_rdclose_2026-10-16\aurora_mem_bridge_rdclose_3aa600aa.bit`） | 9,841,696 B | `3AA600AA2899C3612F77127BA260FAF38DC6ED55C21F49C6E74A32DBF7FDD30F` |
| **ELF `2961b585`**（`archive\b31b_n7_2026-10-17\j3_soft_n7_2961b585.elf`） | 46,012 B | `2961B585133DDE6D5C47AFAE9AA722A52D7B4E0813474ACED384B39D3771ADDF` |
| 退役位流 `0ecb8438`（今天重建版；`archive\b31b_retire_flag_2026-10-17\aurora_mem_bridge_retire_0ecb8438.bit`） | 9,248,388 B | `0ECB843807D12201C10304F870E50F74D9C4EE333E03FECE550D391D15FB7C12` |
| 探针 `probes_0ecb8438.ltx`（`archive\b31b_retire_flag_2026-10-17\`） | 194,528 B | `352A5F283D229FB91398BEA49036FCFC130CD9988916F23A8257B3297C3A11A2` |
| 构建日志 `build_retire_sweep3.log`（同目录；含 `SWEEP_WLDrivenBlockPlacement: WNS=0.000 WHS=0.004` 与 `V5_SWEEP_OK`） | 636,893 B | `446655E85BB3DA34E674392CF27D37AE8DAF8D2C071A2741B633BE470243345E` |
| `archive\b31b_v5rtl_2026-10-16\probes.ltx` | 194,528 B | `352A5F283D229FB91398BEA49036FCFC130CD9988916F23A8257B3297C3A11A2`（**与 `probes_0ecb8438.ltx` 逐字节相同**；`b31b_retire_2026-10-16\probes.ltx`、`out\probes_rdprobe.ltx` 亦同） |
| `out\probes_v5_WLDrivenBlockPlacement.ltx` | 194,528 B | `FCC2AF8A60F33E9F94A0F99E6E36F66C0247609F492037060AE0134A32576BE7`（**与上面几份不同**，勿混用） |
| `out\aurora_mem_bridge.bit`（**当前默认名产物**） | 9,248,388 B | `0ECB843807D12201C10304F870E50F74D9C4EE333E03FECE550D391D15FB7C12` ⇒ **快照时（21:02）实为 `0ecb8438`，不是文档旧述的 `3aa600aa`**；⚠️ 修复版构建（进行中）**会覆盖该默认名**，收口时须重新核（见 §6-③） |

---

## 4. 离线回归原始日志（RTL/TB 仿真；**已由 Lead 归档进本目录**）

| 原路径（`prj/project_11/sim/`） | 本目录归档副本（同 hash） | 时间/大小 | SHA256前8 | 判决 | 等级/备注 |
|---|---|---|---|---|---|
| `sim\bdma_run.log` | `sim_bridge_dma_run.log` | 20:47:36 / 3356 B | `A4C3F4DD` | `bridge_dma_tb`：`=== BRIDGE_DMA_TB: 0 errors === / PASS`（P1/P2/P3 全过；`HAS_DMA=1` 默认 ⇒ 桥① DMA 路径） | [L3] 离线 |
| `sim\xsim_run.log` | `sim_W2_mem_bridge_run.log` | 20:48:26 / 4163 B | `02F7D25E` | `mem_bridge_tb`（W2）：`prj10 W2 SIM: PASS (0 errors)`；编译行含 `axi4_master_bridge(HAS_DMA=0)` / `frame_mem_if(HAS_DMA=0)`；T1/T2/T3/T4/T5/T6 全 PASS，`rd_frame=585`、`rd_beats=8202` | [L3] 离线；**本轮改 `.HAS_DMA(0)` 后**的硬件读回归 |
| `sim\w4_joint_run.log` | `sim_W4_joint_run.log` | 20:49:10 / 6574 B | `FC40B951` | `w4_joint_tb`（W4）：**正向 `DEFECT=0` PASS 0 errors**（P1–P5；A/B 各 `rd=148`）；**负向 `DEFECT=1` FAIL/deadlock（按设计）** | [L3] 离线；两个快照 `w4_joint_defect.wdb`/`w4_joint_fixed.wdb` 亦在 sim/ |
| `sim\xsim_19752.backup.log` | —（未归档） | 20:48:26 / 2388 B | `B14B423B` | = W2 PASS 轮的备份（同 `xsim_run.log` 内容） | 辅助 |
| `sim\xsim_21116.backup.log` | —（未归档） | 20:48:59 / 1311 B | `DE697881` | = W4 **负向** `DEFECT=1` FAIL/deadlock 的备份 | 辅助 |

> **归档状态**：三份主日志已由 Lead 复制到本目录（`sim_*_run.log`，hash 与 `sim/` 原件一致 ✅）；两个 `.backup.log` 仍只在 `sim/`（辅助件，可不必归档）。
> **补充：[L4] 软件/脚本侧回归**（不是 RTL 仿真）——`scripts/j3_soft_verify.py` 的 `warm_probe` 修复与复验见 §2.5（`green_dma_j3_run5_warmfix.log`）；该文件当前是**工作树 M 文件**（见 §5）。

---

## 5. 工作树修复快照（未提交；`git status` **4 个 M 文件**）

| 文件 | 大小 | SHA256前8 | 说明 |
|---|---|---|---|
| `prj/project_11/rtl/axi4_master_bridge.v` | 47,868 B | `18DC7C4B` | 修复主体（git blob `7fe880e`；HEAD/8afa168 = `d0ed165`）；`git diff --stat`：+66/−4 |
| `prj/project_11/scripts/j3_soft_verify.py` | 28,166 B | `4E96E450` | **J3 判据脚本修复**（blob `59a2d7e`；+15/−4）：`run_round(..., warm_probe=True)`，`--dma` 时跳过预热帧（`warm_probe=(not args.dma)`）+ 机制注释；见 §2.5 / C7b |
| `prj/project_11/sim/mem_bridge_tb.sv` | 25,804 B | `5240302F` | 实例加 `.HAS_DMA(0)` |
| `prj/project_11/sim/w4_joint_tb.sv` | 34,307 B | `23392FB8` | 两处实例加 `.HAS_DMA(0)` |
| `prj/project_11/rtl/aurora_mem_bridge.v` | 65,421 B | `5C03DB6B` | **未改**（与 `b31b_rdclose` 归档 `aurora_mem_bridge_tready_fix.v` 同 hash `5C03DB6B…`） |
| `prj/project_11/rtl/frame_mem_if.v` | 25,781 B | `6DB6CB05` | **未改**（`HAS_DMA` 参数/透传早已存在：`frame_mem_if.v:35/439`） |

**git 身份**：退役提交 `8afa168`（2026-10-16 18:37:50，"B3-1c 退役桥②读引擎…"）→ `5c9a8e9`（`dma_tready` 恒接 shim）→ HEAD `96efc39`（当前 bridge 与 8afa168 相同 = `d0ed165`）。修复未提交，**提交与 commit hash 见 §7**。
**未跟踪的仓库侧新工具/设计文档**：`out\S0S8_DESIGN.md`（`8EBAA048`）、`out\retire_s0_s8.ps1`（`3C88A1DA`）、`out\j3_fourchains.ps1`（`90CBF523`）、`out\jb31b_*.{tcl,py,bat}` 一批取证工具——是否入库由 Lead 定（建议与本次修复同批提交，`.md/.ps1/.py/.tcl` 均可入库）。

---

## 6. 需在正文/文档里更正的口径（本索引负责留痕）

1. **`rtl_audit_204519.md` §2 Δ5 / §4.1 的"u_mem2 未被退役影响"是错的**：8afa168 删的是**共享模块 `axi4_master_bridge.v` 内部**的读 FSM；`u_mem2` 是 `frame_mem_if` 以 `HAS_DMA(0)` 例化的实例（`aurora_mem_bridge.v:917`），因此同样被删。**A3/C3 的板上 ILA 已直接反证**（桥② `rd_frm` 恒 0）。→ 记录正文（§三之二十 ②）写更正；审计原文保留不改。
2. **发射流"同构"判据口径**：`rdcap2_cmp_retired.log` 的掩码只掩 IP-ID/IP 校验和/FCS，**未掩 dst MAC**；本次静态邻居下 PC 不发 ARP ⇒ 板自发帧 dst = `ff:ff:ff:ff:ff:ff`（参考流 = `08:3c:03:a0:26:96`）。⇒ S8 判据必须 **掩 dst(8–13)+IP-ID(26–27)+IP 校验和(32–33)+FCS(末4B)**，或**同环境同轮抓绿参考流**（`rdcap2_green.csv` 已抓）。**按此掩码，绿 vs 旧退役两流逐字节相同（`ndiff_after_mask=0`，Lead 实测；对比日志待归档 → §7）**。`out\S0S8_DESIGN.md` §1.3 已把该掩码写成固定口径。
3. **`out/aurora_mem_bridge.bit` 快照时（21:02）实测为 `0ecb8438`，不是 AGENTS.md §十 / 记录 §三之十九之补四 末尾写的 `3aa600aa`**；且修复版构建（进行中）**会覆盖该默认名** ⇒ 文档应改为「默认名产物 hash 随每次构建变化，**一律绝对路径 + 先核 hash**；快照示例 = `0ecb8438`」，不要再写死某个 hash。**21:18 复核该文件仍为 `0ecb8438`（构建未写位流）。**
4. **`rdcap2_send_retired_20261017_205704.log` 名不副实**：它对应 20:57 的**绿位流**抓取轮（`rdcap2_green_vivado.log` 同刻），文件名 mode 标签是发送脚本默认值。用它做证据时要按"绿位流场次"引用。
5. **`'d'` 是翻转不是置位（今天踩两次）**：第一轮 ILA（20:51，`r1cap_uart_pre/post.log` `mode=0`）与 20:4x 那次 DMA 实验都是被 `'d'` **翻回 bridge** 的无效轮（`r1cap_uart_pre2.log` 等留痕）；脚本必须「`'U'` 回读 `mode`+`req.bit24` → 不匹配才发 `'d'` → 再回读；**最后同时满足 `mode=1` 且 `req.bit24=1` 才继续**」，最多翻转 3 次（`out\S0S8_DESIGN.md` §1.2；`retire_s0_s8.ps1` 的 `Set-EngineMode` 已实现）。**不要盲发两次**（第二下会关掉 DMA 驻留服务）。
6. **NIC 判据口径（[L3] 定案）**：静态邻居 ⇒ 板自发帧 dst 是广播 ⇒ **`ReceivedUnicast` delta 恒 0，主判据必须用 `ReceivedBytes`**（单帧 ICMP 回包 74B、ping×4 = 296B；`ReceivedBroadcastPackets` 仅辅助）。绿侧实测 ping 4/4 时 `Unicast=0/Bytes=+296`（`S0S8_DESIGN.md` §1.3/§5；原始 NIC 前后读数**未单独落盘**，PENDING）。用 Unicast 会假 FAIL。
7. **`ilacap_*` 同名文件被覆盖过**：当前 4 个 CSV 是第二轮（20:53）有效轮；第一轮（20:51）已覆盖，只剩 `r1cap_vivado.log`/`r1cap_uart_pre.log`/`r1cap_uart_post.log` 留痕。收口引用时务必带时间/hash。

---

## 7. PENDING 占位行（**过程台账，已于 21:36 全部 resolve —— 见 §10.3**）

> 本表原为 21:02–21:22 的过程 PENDING 台账。**最终状态：全部 resolve**（构建/位流/ltx/xsa、S0–S8、S7 ILA、S8c 发射流、四判据、绿 vs 退役比对、NIC 读数均已落盘，见 §10.1/§10.2/§10.3）。
> **唯一仍 PENDING 项 = 修复提交 commit**（4 个 M 文件未提交；本索引不产生 commit，只登记证据）。

| 原待产生证据 | 最终落点 |
|---|---|
| 修复版构建日志 / `.bit` / `.ltx` / `.xsa` | §10.1：`c8cd3a32`（`C8CD3A32…6BA80`，9,746,300 B）/ `build_retire_fix_sweep.log` / `probes_rdfix_c8cd3a32.ltx` / `mb_ctrl.xsa` |
| S0–S8 原始日志 | §10.2：`s0s8_20261017_213020.log`（`S0S8_RESULT: PASS`）+ 控制台全量 |
| 修复版 ILA 计数（桥②） | §10.2：`ilacap_rdfix_counters_summary.txt`（读帧 777→781、ost 恒 0） |
| 修复版发射字节流 | §10.2：`rdcap2_rdfix.csv` + `rdcap2_cmp_green_rdfix.log`（ISOMORPHIC=YES） |
| 四判据结果 | §10.2/§10.4：S2b/S4/S5/S6 + S8b/S8c/S8d 全部 PASS |
| 绿 vs 退役掩码比对 | §10.2：`rdcap2_cmp_green_retired.log`（ndiff=0） |
| NIC `+296` 原始读数 | §10.2：`rdcap2_nic_baseline.txt` + S4/S5 JUDGE 行 |
| J3 脚本修复/入库 | 已修（工作树 M）；**commit PENDING** |
| 绿基线重跑确认 | §10.2：S1 绿 `708f15a4`+`2961b585` ping 3/3、'L' 应答、邻居 Permanent |
| 离线回归归档 | `sim_*_run.log` 已在本目录（三份主日志），`.backup.log` 可选 |
---

## 8. 与任务书/既有文档的已知矛盾（供 Lead 复核）

1. **§三之十九之补四 的对照表**（"两侧 `wmwr/wmrd` 1/1→4/4、逐项相同"）与 `s2_s6_204148.log` 不符（`WM_WR 2→7`、`WM_RD 2→2`）。→ 该表判据无效，需在记录中更正（建议保留原表 + 加"更正"注）。
2. **`rtl_audit_204519.md` 判 u_mem2 未受影响** → 错（见 §6-①）。
3. **AGENTS.md §十 / 记录 §补四 末尾"`out/aurora_mem_bridge.bit` 现等于 `3aa600aa`"** → 实测为 `0ecb8438`（见 §3.3/§6-③）。
4. **记录 §三之十九之补四 声称 `0ecb8438` 上"ping 期间 `wmwr` 2→7 而 `wmrd` 停在 2；`3aa600aa` 上两者同步推进"** → 前者正是 `s2_s6_201701.log`（无效序列）；后者在**有效序列** `clean_engine1_ping_204321.log` 中复现为 11→15/11→15。两句并不矛盾，但"同步推进"只在**有效序列**下成立，需在正文写清"有效/无效序列"前提，否则会被读成两台位流行为不同。
5. **绿位流 `--dma` 下 J3 四链 FAIL（`green_engine1_j3_dma.log` 等）——已定案为判据脚本缺陷，不是 RTL/位流回归**：根因 `[L4]` = `scripts/j3_soft_verify.py` 的 `run_round()` 在 SEQ 窗无条件发预热帧（DMA 模式下该帧读请求永泊 `R_DRET` 占 1 槽 ⇒ 写阶段第 256 帧槽满被拒 ⇒ `wr+255` → 读阶段不启动 → 级联 FAIL；桥模式由硬件读引擎自动退休故 PASS）。**修复 + 复验 [L4]**：`warm_probe=(not args.dma)`；`green_dma_j3_run5_warmfix.log` 21:17:36 **PASS**。⇒ 记录 §三之十九之补 §1 "DMA 引擎三链全 PASS" 与今日 FAIL 的"矛盾"**消解**（当时 PASS 用的是桥模式或未踩预热帧；本次 FAIL 是脚本缺陷）。另注：`S0S8_DESIGN.md` §1.7/§5-10 的"J3 不带 `--dma`"是**修复前的临时口径**，脚本修复后 `--dma` 已可 PASS —— **最终以 Lead 统一的执行口径为准（PENDING）**。
6. **旧文档 NIC 判据用 `ReceivedUnicast` 的表述已过时**：工作清单 §二之七 S5（`ReceivedUnicast/Bytes delta`）、记录 §补四 表等按旧口径写；静态 ARP 环境下 Unicast 恒 0 ⇒ **S4/S5/S6 必须改 `ReceivedBytes`**（单帧 ≥74、4 帧 ≥296），`ReceivedUnicast` 只作辅助打印（C10）。
7. **任务书/记录称"今天已定案"** → 精确等级为 **根因 [L3]（机制板上直接观测 + 代码唯一相容）**；"定案 [L4]"必须等修复版位流 S0–S8 + 四判据全过（C6 PENDING）。**J3 脚本缺陷那一项是独立 [L4]（与 RTL 修复无关）**，不要混为同一结论。

---

## 9. 复算命令（可原地复跑，全部只读）

```powershell
$ev = 'D:\FPGA\prj\project_11\out\evidence_2026-10-17'
# 1) 本目录全部文件 hash（前8 + 全量）
Get-ChildItem -File $ev | Sort-Object Name | ForEach-Object {
  $h = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
  "{0}  {1}  {2}  {3}" -f $h.Substring(0,8), $h, $_.Length, $_.Name
}
# 2) 归档验证
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_rdclose_2026-10-16\aurora_mem_bridge_rdclose_3aa600aa.bit' -Algorithm SHA256
Get-FileHash 'D:\FPGA\prj\project_11\out\archive\b31b_n7_2026-10-17\j3_soft_n7_2961b585.elf' -Algorithm SHA256
Get-FileHash 'D:\FPGA\prj\project_11\out\aurora_mem_bridge.bit' -Algorithm SHA256   # 应为 0ECB8438…
# 3) 修复工作树事实
git -C D:\FPGA status --short
git -C D:\FPGA hash-object prj/project_11/rtl/axi4_master_bridge.v          # 期望 7fe880e…
git -C D:\FPGA hash-object prj/project_11/scripts/j3_soft_verify.py         # 期望 59a2d7e…
git -C D:\FPGA diff --stat
# 4) J3 修复复验与判据工具
Get-FileHash 'D:\FPGA\prj\project_11\out\evidence_2026-10-17\green_dma_j3_run5_warmfix.log' -Algorithm SHA256  # EC88E541…
Get-FileHash 'D:\FPGA\prj\project_11\out\S0S8_DESIGN.md' -Algorithm SHA256                                   # 8EBAA048…
```

> 本索引只登记证据，**不产生结论**；结论与等级见 `record_section_final.md`（§三之二十 **最终版**，[L4] 定案）。

---

## 10. 最终收口证据（21:25–21:36，[L4] 全过；原 §7 PENDING 已全部 resolve）

### 10.1 修复版产物（`archive\b31b_rdfix_2026-10-17\`，SHA256.txt **8/8 实算一致**）

| 文件 | 大小 | SHA256前8 | 说明 |
|---|---|---|---|
| `aurora_mem_bridge_rdfix_c8cd3a32.bit` | 9,746,300 B | `C8CD3A32` | **修复版位流 `c8cd3a32`**（完整 `C8CD3A32E6AA965F26E9429AD75204C78953366DE31571DDDB379DDA8976BA80`）；与 `out\aurora_mem_bridge.bit` 同 hash（21:28 写入） |
| `axi4_master_bridge_rdfix.v` | 47,868 B | `18DC7C4B` | 修复版 RTL 快照（= 工作树 blob `7fe880e`） |
| `build_retire_fix_sweep.log` | 303,467 B | `07D2F601` | 构建日志：`SWEEP_ExtraTimingOpt: WNS=0.004 WHS=0.004`、`V5_SWEEP_OK`、DRC 0 Errors |
| `build_retire_fix_synth.log` | 178,197 B | `732C340D` | 综合日志 |
| `probes_rdfix_c8cd3a32.ltx` | 194,528 B | `352A5F28` | 探针（与旧 v5rtl `probes.ltx` **逐字节相同**，hash `352A5F283D229FB9…C3A11A2`） |
| `j3_soft_n7_2961b585.elf` | 46,012 B | `2961B585` | ELF（未变） |
| `j3_soft_verify_rdfix.py` | 28,166 B | `4E96E450` | J3 判据脚本修复快照（+15/−4） |
| `build_retire_fix_sweep.jou` | 921 B | `468BFF58` | Vivado journal |
| `SHA256.txt` | 817 B | `ED798293` | 上述 8 项清单（逐行实算核对全一致） |
| `out\mb_ctrl.xsa` | 2,526,101 B | `C9B52DD7` | 修复版 xsa（完整 `C9B52DD79E209725…AC459350`） |

### 10.2 S0–S8 / 四判据原始日志

| 文件 | 时间/大小 | SHA256前8 | 内容 |
|---|---|---|---|
| `s0s8_20261017_213020.log` | 21:32:32 / 36,448 B | `E1E732BC` | **`S0S8_RESULT: PASS`**（S0–S8 全部 JUDGE 行；S1 绿基线 3/3；S2b 0/1；S3/S3b；S4 单帧；S5 ping 4/4；S6 emit；S8b J3 全 PASS） |
| `s0s8_run_console.log` | 21:32:32 / 66,436 B | `D82B480C` | S0–S8 控制台全量（含 exit 0 与 NOTE） |
| `j3_fourchains_20261017_213200.log` | 21:32:29 / 8,029 B | `6C428A95` | J3 四链封装 RUN（**"带 --dma 跑 M/A/B"**；`FOURCHAINS_RESULT: PASS`） |
| `j3_m_20261017_213200.log` / `j3_a_20261017_213200.log` / `j3_b_20261017_213200.log` | 各 800/805/800 B | `62C526B6` / `3E176F9A` / `254DB3F6` | 三轮独立日志：`[M] inv=30417 miss=0`、`[A] inv=30171 miss=[5100]`（=恰帧#100，base 5000）、`[B] inv=30417`；均 `[B2-SOFT-VERIFY] PASS` |
| `rdfix_4tier.log` | 21:35:49 / 2,174 B | `9BC899C9` | **S8d 四档零回归 PASS**（20/20·12/12·12/12·300/300、`DDR_VERIFY: PASS`；与 `green_engine1_4tier.log` 内容相同 ⇒ 同 hash） |
| `rdcap2_cmp_green_rdfix.log` | 21:35:03 / 3,518 B | `7635D896` | **S8c 发射流同构**：`rdcap2_rdfix.csv` vs `rdcap2_green.csv` 掩 `8-13,26-27,32-33,-4..-1` ⇒ **`ndiff_after_mask=0` / `ISOMORPHIC=YES`** |
| `rdcap2_cmp_green_retired.log` | 21:30:02 / 3,188 B | `231C0C1E` | 绿 vs 旧退役发射流：同掩码 ⇒ **`ndiff_after_mask=0` / `ISOMORPHIC=YES`** |
| `ilacap_rdfix_counters_summary.txt` | 21:34:25 / 5,646 B | `4D2DF5DC` | **S7 修复版 ILA 汇总**：桥② `wr/rd/wm` 777→781（+4）、`ost` 恒 0；桥① 777→781、ost 0 |
| `rdcap2_rdfix.csv` | 21:35:02 / 324,325 B | `0DB61051` | 修复版桥① 发射流 1526 B（dst 已恢复 PC MAC `08:3c…`，因 ping 通后 ARP 学得） |
| `rdcap2_rdfix_vivado.log` / `rdcap2_rdfix_vivado.jou` | 21:35:02 / 5,006 B / 1,018 B | `85972544` / `E5054156` | 抓取流程（ILA1、39 probes、`RDCAP2_DONE`） |
| `r1cap_rdfix_vivado.log` / `r1cap_rdfix.jou` | 21:34:24 / 3,156 B / 997 B | `2DC594B9` / `62B1D47C` | S7 抓取流程（GRAB_PRE/POST USER+UI、ping×4、`R1CAP_DONE`） |
| `ci_before_docs.log` | 21:36:30 / 3,688 B | `6D676BDC` | **CI 基线 PASS**（docs 镜像同步前跑 `scripts/ci_check.py`：`=== CI: PASS ===`；文档落盘后应再跑一次）——[L3] 过程留痕 |
| `rdcap2_nic_baseline.txt` | 21:30:04 / 426 B | `1839495F` | NIC 基线：`ReceivedUnicast=7023 / ReceivedBroadcast=2672 / ReceivedBytes=1730876`（S4/S5 delta 的起点） |
| `rdcap2_send_retired_20261017_213200.log` / `rdcap2_send_retired_20261017_213500.log` / `rdcap2_send_bat_retired.log` | 392 / 392 / 1,074 B | `D92108FF` / `4CBDDE26` / `AC56A9DE` | 发送端日志（S8c 抓取窗口） |

### 10.3 原 §7 PENDING 的 resolve 状态

| 原 PENDING | 现状态 |
|---|---|
| 修复版构建日志 / `.bit` / `.ltx` / `.xsa` | ✅ 已产生并核（§10.1：`c8cd3a32` / `07D2F601` / `352A5F28` / `C9B52DD7`） |
| S0–S8 原始日志 | ✅ `s0s8_20261017_213020.log` = **PASS**（+控制台全量） |
| 修复版 ILA 计数（桥②） | ✅ `ilacap_rdfix_counters_summary.txt`：读帧 777→781、ost 恒 0 |
| 修复版发射字节流 | ✅ `rdcap2_rdfix.csv` + `rdcap2_cmp_green_rdfix.log`（ISOMORPHIC=YES） |
| 四判据结果 | ✅ 全部取值通过（S2b/S4/S5/S6 + S8b/S8c/S8d） |
| 绿 vs 退役 掩码比对日志 | ✅ `rdcap2_cmp_green_retired.log`（`ndiff_after_mask=0`） |
| NIC `+296` 原始读数 | ✅ `rdcap2_nic_baseline.txt` + S4/S5 JUDGE 行（Bytes +74/+296） |
| `j3_soft_verify.py` 修复入库 | ⏳ 代码已修（M 文件）；**commit 仍 PENDING（4 个 M 文件未提交）** |
| 修复提交 commit | ⏳ **PENDING**（`{{PENDING:git hash}}`；本索引只登记证据） |
| 绿基线重跑确认 | ✅ S1 绿 `708f15a4`+`2961b585` ping 3/3、'L' 应答、邻居 Permanent（`s0s8_20261017_213020.log`） |

### 10.4 四判据 → 证据一句话

| 判据 | 证据 |
|---|---|
| ① ping/ARP | S2b 0/1（身份）→ S4 1/1 → **S5 4/4**（NIC ReceivedBytes +296） |
| ② 四档逐字节 | **S8d `rdfix_4tier.log`：`DDR_VERIFY: PASS`**（20/20·12/12·12/12·300/300） |
| ③ J3/J3′ | **S8b：M/A/B 全 PASS**（`--dma`；`[A]` 恰帧#100 负向设计） |
| ④ 负向 A/B | S8b 的 `[A]`（缺 1 帧按设计）/`[B]`（重读槽不产出）均 PASS |
| 附加（[L4] 闭合） | S7 桥② 读帧 +4/ost 恒 0；S8c 发射流 vs 绿参考 ndiff=0 |
