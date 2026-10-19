# round3d 候选补丁：影响面 / 回归建议 / 风险（配套 round3d_candidate.patch）

- 产出：rtl-auditor（独立审计，只读；未改 rtl/scripts/sw；草案未编译未仿真）
- 前提：round3d 的合入决策应**等 round3c 的 ILA4/ILA5 判读结果**（本补丁针对的是"fix2 之后仍存在的确定性结构缺陷"，不是把板端现象提前定因）
- 依据等级：机制=[L2 代码]；板端收益=待验证 [L1]

---

## 1. 变更摘要

| # | 文件 | 变更 | 性质 |
|---|---|---|---|
| A1 | `rtl/axi_lite_regs.v` | `l_rstuser_s1/s2` 补 `(* ASYNC_REG *)` | 规范修复（AGENTS §5.1 形态②） |
| A2 | 同上 | 4 相邮箱看门狗（读/写各 12b 计数，4096 aclk=41µs）+ 单驱动错误聚合块 | 结构性防御（把"永久楔死"降级为"可观测 SLVERR + sticky"） |
| A3 | 同上 | 写通道 `LW_EXEC/LW_CLOSE` 超时 → `bresp=SLVERR` + `bvalid`，清 `a_req` | 同上 |
| A4 | 同上 | 读通道 `LR_RACK/LR_DRQ` 超时 → `rresp=SLVERR` + `rvalid`，清 `r_req`；`LR_DACK` 超时强制回 IDLE | 同上 |
| A5 | 同上 | `mbox_clr_tog`（aclk→clk_user 2FF 边沿）只复位 user 侧邮箱 FSM/应答；`mbox_fault` 2FF 读回；新增 Lite 只读 `+0x50` | 恢复路径 + 可观测 |
| A6 | 同上 | `l_stuck_r` 4→8：新增 bvalid&&!bready / awvalid&&!awready / wvalid&&!wready / aw_pending\|w_pending；`dbg_o[35]` 改为 8 位 or（位图/宽度不变） | 观测补盲（对应 round3c ILA4 的 4 个漏测形态） |
| B1 | `sw/j3_soft/src/main.c` | 新增 `R_MBOX(+0x50)` 定义与 `'U'` 打印；把 "LENGTH 后立即 GO、诊断读一律放 GO 之后" 固化为注释纪律 | 防回归（16D06BD3 的教训） |

**不含**：S2MM 引擎侧改动（`wf_level`/`stat_wr_timeout` 探针属"观测扩展"，建议单独一轮评估 300MHz 余量后再加）；**不含** lite fix2 的回退（§5）。

---

## 2. 行为影响

### 2.1 正常路径（未超时）
- 无功能变化：看门狗只在"非 IDLE 停留 >4096 aclk"时动作；正常读/写 4 相往返 <100 拍（本设计 aclk 100MHz ↔ clk_user 151.5MHz，2FF 双向），余量 ≈40×。
- 正常 AXI 响应仍为 OKAY（`rresp/bresp=2'b00`）；`+0x50` 默认读回 0。
- 唯一常态开销：+~80 FF（见 §4）。

### 2.2 异常路径（超时）
- 行为从「AXI 事务永挂 ⇒ MicroBlaze `lwi` 永久停」变为「≤41µs 后返回 SLVERR ⇒ MCU 收到总线错误 ⇒ 邮箱被强制清空、user 侧 FSM 回 IDLE ⇒ 下一次 Lite 访问可继续」。
- **MicroBlaze 侧的注意点（重要决策项）**：SLVERR 会触发 MicroBlaze 的**总线异常**。若固件/BSP 未安装异常处理，可能跳异常向量/停机——即"从静默挂死变成可观测异常"。对本项目**这是期望方向**（现场可被 `g_step`/异常处理/串口抓到），但需 Lead 确认：
  - 选项 a：保留 SLVERR + 固件加最小异常处理（打印 `EAR`/`ESR` + 停机标记），推荐；
  - 选项 b：超时后不返回 SLVERR，而是**内部重试该事务一次**（读幂等可重试；写不可重试——不可取）；
  - 选项 c：只清邮箱 + 保持 AXI 悬挂（= 现状，不可取）。
- 超时阈值 4096 aclk 的标定依据：正常往返 <100 拍（代码级估算），41µs 远小于桥的 56ms fail-stop 超时，不会与桥的超时语义冲突（两者独立域/独立路径）。
- `mbox_clr_tog` 只复位邮箱 FSM（`ust/urst/a_ack/r_ack/d_req`），**不动** `cfg_mode/cfg_rd_slot/cfg_rd_engine/cfg_wr_go/cfg_wr_ack/lite_*_cnt` ⇒ 不会把软核配置状态清掉（与"user 域复位"语义严格区分）。

### 2.3 观测路径
- `dbg_o[31..34]` 语义不变；`dbg_o[35]` = 8 个 stickie 的 or ⇒ ILA4 触发条件**更强**（能抓 B 未消费/半锁存/写通道不受理），不会漏掉原 4 类。
- bit4-7 无独立 dbg_o 输出（保持 36b 位图/BD 端口不变）；逐位区分通过 `+0x50`（bit0/1）与 round3d 下一轮扩 dbg_o（如需）。

---

## 3. 集成影响

| 项 | 影响 | 处置 |
|---|---|---|
| BD / `create_bd_b.tcl` | **无**：`axi_lite_regs` 端口表不变（dbg_o 仍 36b），BD IP 接口/外部端口/地址图均不变 | 无需 BD regen；OOC run 会因 RTL 内容变化产生新 IP-cache ID 并重综合 |
| OOC run / IP cache | 需要重置 `mb_ctrl_*` runs（build_synth_only.tcl:45 已做）+ 检查新 cache ID / DCP 时间戳（坑 #35） | 构建日志应出现 `MODULE_REF_RESET: mb_ctrl_axi_lite_regs_0_0_synth_1` |
| 顶层 RTL / ILA / ltx | **无**：dbg_o 位图不变、`dbg_l_bus` 端口不变 ⇒ ILA4 位图、4 核 ltx 期望、r3c_cap 脚本断言全部沿用 | 无需改 `build_debug.tcl` / `aurora_mem_bridge.v` |
| XSA / 地址图 | **无**（+0x50 在同一 4KB Lite 段内，无新 BD 地址段） | Vitis 平台无需重建（仅固件改动需重编 ELF） |
| 固件 | `main.c` 重编 + ELF hash 必须变化（坑 #50/#53：改 `sw/src_j3`→复制 `sw/j3_soft/src`→删 main.o/elf→make→核对 hash） | 板验前按坑 #50 四步 |
| 位流 | 需要重建（RTL 变） | 时序门限沿用 +0.004 体系 |

---

## 4. 资源/时序估计（先验，非实测）

- 新增 FF：`lr_wd/lw_wd` 24 + `lr_to/lw_to` 2 + `lr_err_req/lw_err_req` 2 + `mbox_fault` 2 + `mbox_clr_tog` 1 + user 侧同步（`mbox_clr_s1/s2/last` 3 + `mbox_fault_s1/s2` 4）+ 新卡死计数器 40 + `l_stuck_r` +4 ⇒ **≈80 FF**；LUT ≈ 100–150。
- 器件利用率影响 <0.1%；100MHz aclk 域（lite_regs OOC run）时序压力可忽略。
- **不新增 300MHz（ui）路径**，不影响 round3b 的 +0.004 余量体系；但注意 `mbox_fault` 是 aclk→clk_user（151.5MHz）2FF，属慢变状态，无时序风险。
- 若 Lead 想进一步减小面积：可把看门狗阈值降到 2048（>100 拍仍 20×）并复用计数器位宽 11b。

---

## 5. 回归建议（合入前必须全过；顺序按代价升序）

### 5.1 单元仿真（复用 `sim/r2_tmp/` 既有 TB；跑前 `rmdir /s /q xsim.dir`，坑 #48）
1. `r2_lite_proto_tb.sv`（单读/单写/背靠背双读）：正常路径 **1 AR→1 R、1 AW+W→1 B、双读数据各自正确**；断言 `mbox_fault==0` 全程。
2. `r2_lite_write_proto_tb.sv`：背靠背两写 AW/W/B=2/2/2。
3. `r2_lite_pipe_wr_tb.sv`：第二笔写前 B 未消费时不得受理（fix2 语义保持）。
4. **新增超时 TB（必须）**：
   - 场景 T1：发起读后把 `rst_user_n` 拉 0（模拟 user 侧复位）并保持 → 期望 ≤4097 aclk 后 `rvalid=1,rresp=2'b10`、`mbox_fault[0]=1`、`+0x50` 读回 bit0=1；释放 `rst_user_n` 后下一笔读正常（OKAY）。
   - 场景 T2：发起写后拉低 `rst_user_n` → 期望 `bvalid=1,bresp=2'b10`、`mbox_fault[1]=1`；恢复后下一笔写正常。
   - 场景 T3（负向对照）：正常流量 1e5 笔随机读写 → 断言 `mbox_fault` 恒 0、无 SLVERR（防"判据恒真/超时误触发"）。
   - 场景 T4：`LR_DACK` 卡死（强制 `d_req` 不撤）→ 期望 41µs 后强制回 IDLE，`mbox_fault[0]=1`，后续事务正常。
5. **RTL lint/综合**：`sim/mini_synth_check.tcl` 或工程级综合（坑 #27：结构改动先跑单模块 OOC 综合再跑工程级）；检查 **0 条 MDRV-1**（多驱动，本草案已按单驱动写，但必须工具复核，坑 #25/#34）。

### 5.2 工程级构建
- 与 round3c 相同的 `build_synth_only.tcl` + `build_v5_sweep2.tcl` 流程；重点看：`MODULE_REF_RESET`、OOC DCP 时间戳（坑 #35）、`WNS/WHS ≥0`、DRC 0 Error。
- 检查 ltx：4 核、ILA4 probe0=36/probe1=1、ILA5 probe5=7（与 round3c 相同，不需改）。
- S0 dry-run（hash/时序/DRC）沿用。

### 5.3 板端回归（round3d 板验）
1. `'U'` 新增 `mbox` 行（应全 0）；`'d'`/`'W'`/ping 常规序列。
2. **强制超时实验（可选但推荐）**：在 `'d'` 后人为制造 user 侧不可用（如断开 Aurora 光纤/发复位）→ 期望：串口不再永久静默（超时后总线恢复）；`+0x50`/`'U'` 可读出 mbox_fault=1。**该实验有物理风险，需 Lead/用户决定，本审计不建议擅自做**。
3. 重跑 round3c 的 ILA4/ILA5 判读矩阵：确认 H-acklost 归档为"可观测 SLVERR"而非楔死；GO 判读不变。
4. 最小判据：S0–S11 + 四档零回归（沿用现有脚本）；新增"连续 1000 次 Lite 读写压力"观察 mbox_fault=0。

---

## 6. 风险与开放项（合入前逐条确认）

| # | 风险 | 等级 | 处置 |
|---|---|---|---|
| 1 | **SLVERR 触发 MicroBlaze 总线异常**，若无异常处理可能停机（现象从"静默挂死"变"异常停机"） | 中 | Lead 决策：固件加最小异常处理（打印 EAR/ESR + 标记），或在 BSP 中注册 handler；不可取的是无处理 |
| 2 | `mbox_clr_evt` 与正常事务竞争（user 侧 >41µs 慢响应被误清） | 低 | 41µs 相对正常 <1µs 有 40× 余量；若现场确有慢事务，需把阈值调大到 ~1ms（4096→100k 计数） |
| 3 | 超时后 user 侧仍可能残留 `d_req`/`a_ack` 一拍（2FF 延迟） | 低 | user 侧 `mbox_clr_evt` 分支强制清；aclk 侧下一事务前有 `r_ack_s[1]`/`a_ack_s[1]` 门控 |
| 4 | 多驱动（`mbox_fault`/`mbox_clr_tog` 若误放回 FSM 块） | 中 | 草案已单驱动；**必须**综合日志 0×MDRV-1 + lint 复核（坑 #25） |
| 5 | `mbox_fault[1:0]` 的 aclk→clk_user 2FF 读回为"准静态"假设（读到的一瞬可能半更新） | 低 | 仅 sticky 位、软件读取不用于实时控制；如需严格，可在 user 侧再打一拍 |
| 6 | `+0x50` 与已用地址冲突 | 低 | 现有读地址 0x00–0x44；0x50 空闲（`r_addr` 6'b010100） |
| 7 | 本轮草案未编译/未仿真 | — | 合入前必须走 §5.1/§5.2；本审计不提供"已验证"结论 |

---

## 7. 备选方案对比（为何选"超时+SLVERR"）

| 方案 | 效果 | 代价/风险 | 评价 |
|---|---|---|---|
| A. 超时 + SLVERR + sticky + 清邮箱（本草案） | 楔死降级为可观测错误；总线可恢复 | RTL ~80FF；SLVERR 异常处理需固件配合 | **推荐**：与 round3b 上一轮审计 B3 建议一致，收益最大 |
| B. 仅加 sticky 观测（不加超时） | 现场可读，但仍永久楔死（需重配 FPGA） | 极小 | 备选（如果 Lead 不想动错误语义） |
| C. 统一 aresetn 与 rst_user_n 的邮箱复位 | 去掉复位失配根因 | 需跨域复位脉冲；若 link_ok 抖动频繁会反复复位邮箱 | 可与 A 并行（A 是兜底） |
| D. 回退 lite fix2 → fix1 | **不推荐**：fix2 修的是已验证的协议违例（单读 5R/单写 5B）；回退会恢复更严重问题 | 高 | 反对（且 §B 文档证明无"仅 fix1↔fix2"对照支持回退） |
| E. 改固件绕开（永不紧接读写） | 缓解现象 | 治标；且无法覆盖任何真实复位/时钟停场景 | 临时可，不可作为收口 |

---

## 8. 与 round3c 的关系

- 本补丁**不改变** round3c 的探针语义：dbg_o 36b 位图、ILA4 位宽、BD 端口、ltx 期望全部不变；round3c 位流/脚本可直接复用（除 RTL 本体需重建）。
- round3c 的判读结果决定 round3d 的修正对象：
  - 若 ILA4 判 H-acklost/H-bstuck → A2–A5 正是对症兜底；
  - 若 ILA4 判 H-ARnever → 优先查 MCU/互联（本补丁不解决，但能把后续死等降级为可观测）；
  - 若 ILA5 判 Z1（GO 未到桥）→ 说明零 commit 是上游症状，round3d 重点在 lite/固件，不是 S2MM 引擎。
- 建议 round3d 同时补 S2MM 侧 1b sticky（`stat_wr_timeout!=0`→ILA5 probe5）以闭环 Z5 的"超时不可见"问题（需评估 300MHz 余量，单独小步）。

*本文件由 rtl-auditor 产出；补充丁为草案，无"已验证/已合入"含义。*
