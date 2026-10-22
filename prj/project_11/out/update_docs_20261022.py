# -*- coding: utf-8 -*-
"""update_docs_20261022.py — 更新已完工作说明 / README / agent.md / docs 索引与镜像。

内容口径（2026-10-22）：
  路线 A 已收口（2026-10-09，prj10 冻结）；
  路线 B 已收口（2026-10-19，prj11：B0–B5/R1–R4；板上 13 项判据全过；速率 1466B≈2000fps；可编程边界）。
  发布页：https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19
"""
import io
import os

VAULT = r"C:\Users\15266\Desktop\毕设"
REPO = r"D:\FPGA"

TOUR = os.path.join(VAULT, "汇报", "导览_cross_已完成工作说明_2026-10-01.md")
TOUR_M = os.path.join(REPO, "docs", "导览_cross_已完成工作说明_2026-10-01.md")
README = os.path.join(REPO, "README.md")
AGENT = os.path.join(VAULT, "agent.md")
AGENT_M = os.path.join(REPO, "docs", "agent.md")
DREAD = os.path.join(REPO, "docs", "README.md")

REL = "https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19"
GUIDE = "docs/复现/复现_prj11_指南_2026-10-19.md"


def rd(p):
    return io.open(p, "r", encoding="utf-8", newline="").read()


def wr(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


def mirror(src, dst):
    s = rd(src).replace("C:\\Users\\15266", "C:\\Users\\***").replace("15266", "***")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    wr(dst, s)


# ============================================================ 1) 已完工作说明
t = rd(TOUR)
lines = t.split("\n")
out = []
i = 0
replaced = {"summary": 0, "updated": 0, "sec2": 0, "sec23": 0}
while i < len(lines):
    ln = lines[i]
    if ln.startswith("摘要:") and replaced["summary"] == 0:
        out.append("摘要: 项目 README 的补充说明——逐项展开 8 件已完成工作的目标、实现路径、判据与期间解决的问题，并附 DDR 两步走（路线 A 2026-10-09 收口、路线 B 2026-10-19 收口）。新同学请先读 README。")
        replaced["summary"] = 1
        i += 1
        continue
    if ln.startswith("updated:") and replaced["updated"] == 0:
        out.append("updated: 2026-10-22")
        replaced["updated"] = 1
        i += 1
        continue
    if ln.startswith("## 二、正在推进"):
        out.append("## 二、DDR 两步走（路线 A 2026-10-09 收口，路线 B 2026-10-19 收口）")
        replaced["sec2"] = 1
        i += 1
        continue
    if ln.startswith("### 2.3 路线 B"):
        # 跳到 2.4 之前整段替换
        j = i + 1
        while j < len(lines) and not lines[j].startswith("### 2.4"):
            j += 1
        NEW = r'''### 2.3 路线 B —— 软核 + C 代码控制（✅ 已于 2026-10-19 收口）

- **做法**：在路线 A 之上加入软核处理器与 C 代码来控制"读写哪个位置、按什么顺序读"。软核**只下发参数、读取状态，不进入数据通路**；数据搬运由 DMA 承担。读写位置仍以"帧 + 缓存槽"表达，槽号由软核写入 DMA 参数。
- **完成情况（B0–B5 / R1–R4 全部完成）**：
  1. **B0–B3**：脚手架与 fork 完整性、软核进入环路（不改数据面）、软核控制下的随机读写验证（导师原话四环节在软核控制下复现）、读路径换 DMA；
  2. **R2 写路径换 DMA（2026-10-19）**：写侧也改由 DMA 搬运；板上全流程判据 **13 项全部通过**——多种帧长逐字节比对、10MB 全量校验、随机读写与负向用例、两级缓存计数对账；
  3. **R3 速率量化**：1466 字节帧可持续约 **2000 帧/秒**（约 23 Mbps），临界约 2500 帧/秒；按需求以"可编程、可观测"为优先，**不追求线速**（与路线 A 的纯硬件线速通路相比，这是软核逐帧介入的取舍，已量化归因）；
  4. **R4 文档收口**：复现指南、探针/计数清单、跨轮归档索引（0 缺失）。
- **可编程能力**：C 程序可按帧/缓存槽自定义读写位置、读写顺序、限速与异常恢复；这是后续拥塞感知调度与多链路实验的入口。
- **当前边界**：数据仍按"帧队列"组织（256 槽 × 4 KB、单帧上限 1538 字节），C 程序**不能对任意 DDR 地址做通用读写**；如需该能力，要改数据通路（DMA 写回环或软核直连内存控制器），属下一步扩展项。
- **复现与发布**：复现指南 `复现/复现_prj11_指南_2026-10-19.md`；收口记录 `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十九–§二十二；发布页 <https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19>。

'''
        out.append(NEW.rstrip("\n"))
        replaced["sec23"] = 1
        i = j
        continue
    out.append(ln)
    i += 1
assert all(v == 1 for v in replaced.values()), "TOUR patch anchors: %s" % replaced
wr(TOUR, "\n".join(out))
mirror(TOUR, TOUR_M)
print("TOUR updated + mirrored")

# ============================================================ 2) README
r = rd(README)
lines = r.split("\n")
out = []
hit = {"prj11row": 0, "routeb": 0, "milestone": 0, "remain": 0, "release": 0}
for ln in lines:
    if ln.startswith("| `prj/project_11/`"):
        out.append("| `prj/project_11/` | 路线 B：MicroBlaze 软核控制面 + AXI DMA 数据面（fork prj10） | B0–B5 / R1–R4 全部完成：软核控制下随机读写（导师四环节）、四档逐字节、10MB 全量校验、两级缓存计数对账全部通过（板上 13 项）；速率 1466B ≈2000 帧/秒（可编程优先，不追线速） | ✅ 路线 B 收口（2026-10-19） |")
        hit["prj11row"] += 1
        continue
    if ln.startswith("**当前进度（2026-10-17）**"):
        out.append("**当前状态（2026-10-19）**：**路线 B 已收口**——B0 断点核查/脚手架 → B1 软核控制面 → B2 软核验证 → B3 读路径换 DMA（R1）→ **R2 写路径换 DMA（2026-10-19）**：板上全流程判据 **13 项全部通过**（四档逐字节 / 10MB 全量校验 / 随机读写 + 负向 / 两级缓存计数对账）；**R3 速率**：1466B 帧可持续约 **2000 帧/秒**（约 23 Mbps），临界约 2500 帧/秒（可编程优先，不追线速）；**R4**：复现指南 + 探针清单 + 归档索引收口。C 程序已可按帧/槽配置读写位置、顺序与限速；任意 DDR 地址通用读写属下一步扩展。复现见 [docs/复现/复现_prj11_指南_2026-10-19.md](docs/复现/复现_prj11_指南_2026-10-19.md)，发布页见 [Release](https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19)。")
        hit["routeb"] += 1
        continue
    if "最近里程碑：路线 B" in ln and ln.startswith("| [docs/调试记录/阶段三_prj11_B3-1"):
        out.append("| [docs/调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md](docs/调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md) | **路线 B 收口记录（2026-10-19）**：B0–B5 / R1–R4 全过程、板上 13 项判据、R3 速率量化与重审；§十九–§二十二 为收口结论 |")
        hit["milestone"] += 1
        continue
    if ln.startswith("| [docs/操作文档/阶段三_prj11_路线B剩余工作清单"):
        out.append("| [docs/操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md](docs/操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md) | 路线 B 剩余工作清单：**2026-10-19 全部结项**（R1–R4 完成、D1/K2 结项、D2 放弃；§八 收尾记录） |")
        hit["remain"] += 1
        continue
    if ln.startswith("| [docs/追踪_cross_短期待办"):
        out.append("| [docs/复现/复现_prj11_指南_2026-10-19.md](docs/复现/复现_prj11_指南_2026-10-19.md) | **路线 B 复现指南**：产物核对 → 烧录 → 体检 → 板上判据一键 → 四档/10MB/J3 → 速率量化 → ILA → 归档核对 |")
        out.append("| [prj11 路线 B 收口 Release](https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19) | **2026-10-19 发布页**：验收产物、板上判据、速率与复现入口 |")
        out.append(ln)
        hit["release"] += 1
        continue
    out.append(ln)
r = "\n".join(out)
assert all(v >= 1 for v in hit.values()), "README anchors: %s" % hit
wr(README, r)
print("README updated", hit)

# ============================================================ 3) agent.md
a = rd(AGENT)
lines = a.split("\n")
out = []
hit = {"status": 0, "nav": 0, "cur": 0}
for ln in lines:
    if ln.startswith("> 状态提示："):
        out.append("> 状态提示：**路线 A（prj10）冻结、路线 B（prj11）已于 2026-10-19 全量收口**；最新发布见「30 秒导航」的 Release 行，当前入口见下方「30 秒导航」。")
        hit["status"] += 1
        continue
    if ln.startswith("| **当前入口（新对话从这里开始）**"):
        out.append(ln)
        out.append("| **最新发布（Release）** | prj11 路线 B 收口（2026-10-19）— <https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19> |")
        out.append("| **已完成工作说明（补充材料）** | `汇报/导览_cross_已完成工作说明_2026-10-01.md`（vault）；GitHub 镜像 `docs/导览_cross_已完成工作说明_2026-10-01.md`（路线 A/B 均已收口） |")
        hit["nav"] += 1
        continue
    if ln.startswith("- ✅ **路线 B（prj11）已全量收口"):
        out.append(ln)
        out.append("- 📦 **发布页**：<https://github.com/chemmy-11/EIF/releases/tag/prj11-routeB-closed-2026-10-19>（tag `prj11-routeB-closed-2026-10-19`）；**已完工作说明**：vault `汇报/导览_cross_已完成工作说明_2026-10-01.md`（GitHub 镜像 `docs/导览_cross_已完成工作说明_2026-10-01.md`）。")
        hit["cur"] += 1
        continue
    out.append(ln)
a = "\n".join(out)
assert all(v >= 1 for v in hit.values()), "AGENT anchors: %s" % hit
wr(AGENT, a)
mirror(AGENT, AGENT_M)
print("agent.md updated + mirrored", hit)

# ============================================================ 4) docs/README
d = rd(DREAD)
d = d.replace(
    "| [导览_cross_已完成工作说明_2026-10-01.md](导览_cross_已完成工作说明_2026-10-01.md) | FPGA 高速互联平台 · 已完成工作说明 |",
    "| [导览_cross_已完成工作说明_2026-10-01.md](导览_cross_已完成工作说明_2026-10-01.md) | FPGA 高速互联平台 · 已完成工作说明（含 DDR 两步走：路线 A 2026-10-09、路线 B 2026-10-19 均已收口） |",
    1,
)
d = d.replace(
    "逐项说明 8 件已完成工作的内容与实现路径，附正在推进的 DDR 两步走（路线 A / 路线 B）",
    "逐项说明 8 件已完成工作的内容与实现路径，附 DDR 两步走（路线 A 2026-10-09、路线 B 2026-10-19 均已收口）",
    1,
)
wr(DREAD, d)
print("docs/README updated")
print("DONE")
