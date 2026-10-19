# -*- coding: utf-8 -*-
"""Append §19.6 (audit §F mechanism: stale module-ref IP cache) to the R2 record."""
import io
import os

P = r"C:\Users\15266\Desktop\毕设\调试记录\阶段三_prj11_R2写侧S2MM换层_2026-10-17.md"

SECTION = r'''
### 19.6 机制补记（独立审计 §F，[L2] 强推断）：旧位流的"楔死"= module-ref IP cache 陈旧

- 审计只读核对：旧 module-ref IPCACHE `1f8570ac5fbdb536` 的 DCP/文件 mtime 全部为 **2026-10-17 22:22:03**，`stats.txt` NumberHits=19、最后命中 **2026-10-19 00:10:59**（正是 round3b 构建）；round2f/round3/round3b 的 synth 日志分别读 `mb_ctrl_axi_lite_regs_0_0_9/...dcp`。
- 而 `axi_lite_regs.v` 在 10-18 有 fix1（`c8c8a0b` 17:09）与 fix2（`c541f16` 21:14）两次修改 ⇒ **fix1/fix2 从未进入任何位流**；`reset_run` + `MODULE_REF_RESET` 只刷新了 OOC run，并没有使 **IP cache** 失效。
- BD 全量 regen 后 module-ref 实例 `_9→_10`、接口新增 `dbg_o` ⇒ `IPCACHESYNTHCRC` 3fdf9d25→08aea834 ⇒ 新 cache（10-19 12:05:50 首次真综合当前 RTL，日志读 `_10`）。这才是"楔死消失/首次 commit"的机制；旧网表 = fix 前版本（10-18 单元仿真：单读 1AR→5R、单写 1AW+W→5B → 互连跟踪失步），因此旧位流的"读回冻结 + UART 静默"= **总线协议违例（陈旧网表）**，真 fix 进流后总线正常，才暴露出 MM2S-reset 全引擎复位这一确定性逻辑 bug（严格隔帧 50%）。
- 现象映射（陈旧网表→读回冻结）标 `[L1]`（缺板上 lite 总线直证；ILA4 在 round3c/round3d 均跳过）。**新坑（拟入 AGENTS #68）：module-ref IP cache 不随 RTL 源文件失效**；判别法 = build 日志 `<N>` 目录/cache 文件 mtime 应晚于 RTL mtime、查 `stats.txt`；修法 = 改 module-ref RTL 后**BD regen**，或删 cache / `config_ip_cache -disable_cache`。
- 判据口径修正（[L2] 事件环 + PG021）：Halted 时写 `S2MM_LENGTH` 不启动传输，但 **LENGTH 回读仍保存写入值** ⇒ "LENGTH=86"不能单独当作"传输已启动"判据；须配 `S2MM_DMASR=0x1002`（Idle+IOC）/ `0x0001`（Halted）判别。
'''

path = P
cur = io.open(path, "r", encoding="utf-8", newline="").read()
new = cur.rstrip("\n") + "\n" + SECTION
tmp = path + ".tmp_append196"
io.open(tmp, "w", encoding="utf-8", newline="").write(new)
assert os.path.getsize(tmp) > os.path.getsize(path)
os.replace(tmp, path)
print("APPENDED19.6 bytes_old=%d bytes_new=%d" % (os.path.getsize(path) - len(SECTION.encode("utf-8")), os.path.getsize(path)))
