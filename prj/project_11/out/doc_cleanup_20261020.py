# -*- coding: utf-8 -*-
"""doc_cleanup_20261020.py — 指令层审计后的清理执行（用户已批准）

范围（只做已批准项，保持可逆）：
  A. AGENTS.md：合并 §十 三条路线B状态为一条当前状态；删除过时历史 bullet；
     修 COM7->COM5；更新 §6b 技能/MCP 现状；§八 增"文档分工+可维护性纪律"。
  B. agent.md（vault）：更新入口指针、当前状态；历史状态段改为指针（精简）。
  C. docs/agent.md：按脱敏规则重镜像。
  D. hw-ila-debug / hw-vio-debug SKILL.md：frontmatter 描述补"本工作区无 MCP，走 CLI 桥/Tcl"注记。
  E. 清理：~/.dsh/profiles 旧 .bak 归档；vault 根 _tmp* 移入 .trash（可逆）。
不删任何证据/归档；不碰 prj9/prj10；不改判据脚本。
"""
import hashlib
import io
import os
import re
import shutil
import time

REPO = r"D:\FPGA"
VAULT = r"C:\Users\15266\Desktop\毕设"
AG = os.path.join(REPO, "AGENTS.md")
AGENT = os.path.join(VAULT, "agent.md")
DAGENT = os.path.join(REPO, "docs", "agent.md")
SKILLS = os.path.join(VAULT, ".dsh", "skills")
PROFILES = r"C:\Users\15266\.dsh\profiles"

report = []


def rd(p):
    return io.open(p, "r", encoding="utf-8", newline="").read()


def wr(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


def sha(p):
    h = hashlib.sha256()
    with io.open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest().upper()


# ============================================================ A. AGENTS.md
s = rd(AG)
orig_len = len(s)
lines = s.split("\n")

# A1. COM7 -> COM5（硬件事实卡）
old_com = "串口 FT2232H-B COM7"
if old_com in s:
    s = s.replace(old_com, "串口 FT2232H-B **COM5**（2026-10 实测；COM7 为旧误记）", 1)
    report.append("A1 COM7->COM5 OK")
else:
    report.append("A1 COM7 anchor NOT FOUND")

# A2. §6b 技能/MCP 现状三行替换
old6b = [
    "| 项目级 AI 技能（7 个：6 官方 + `amd-doc-search` 桥） | `<vault>\\.dsh\\skills\\`（vault = `C:\\Users\\15266\\Desktop\\毕设\\`） | **仅本工作区**（DSH `projectRoot/.dsh/skills`，ran",
    "| 官方文档检索（原生 MCP） | `~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-amd-doc-search` 条目 | DSH **web profile 全局**（所有工作区；重启 `dsh web` 后生效） | 已配置；工具名 `…",
    "| 官方文档检索（项目级桥） | `<vault>\\.dsh\\skills\\amd-doc-search\\doc_search.py` | **仅本工作区** | 已生效：`py doc_search.py \"<query>\"`（stdlib 直连 MCP，无需重启） |",
]
if all(any(x[:40] in ln for ln in s.split("\n")) for x in old6b):
    new6b = (
        "| 项目级 AI 技能（7 个：6 官方 AMD 技能 + `amd-doc-search` CLI 桥） | `<vault>\\.dsh\\skills\\` | **仅本工作区**（DSH `projectRoot/.dsh/skills`） | 已加载。**注意**：`hw-ila-debug`/`hw-vio-debug` 依赖的 `vivado-mcp` MCP 未挂进本会话；该两技能文首有「本机适配注记」→ 走 CLI 桥 `D:\\vivado-mcp\\mcp_ctl.py` 或 Vivado batch Tcl |\n"
        "| 官方文档检索（原生 MCP） | `~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-amd-doc-search` 条目 | DSH web profile 全局 | **已配置但当前进程未加载**（会话工具清单无 `mcp__amd_doc_search`）；重启 `dsh web` 后生效 |\n"
        "| 官方文档检索（项目级 CLI 桥） | `<vault>\\.dsh\\skills\\amd-doc-search\\doc_search.py` | **仅本工作区** | 当前实际生效：`py doc_search.py \"<query>\"`（stdlib 直连，无需重启） |"
    )
    # 用逐行前缀匹配替换三行
    out_lines = []
    replaced = 0
    for ln in s.split("\n"):
        if replaced < 3 and ln.startswith("| 项目级 AI 技能（7 个"):
            for nl in new6b.split("\n"):
                out_lines.append(nl)
            replaced += 1
            continue
        if replaced < 3 and ln.startswith("| 官方文档检索（原生 MCP）"):
            replaced += 1
            continue
        if replaced < 3 and ln.startswith("| 官方文档检索（项目级"):
            replaced += 1
            continue
        out_lines.append(ln)
    s = "\n".join(out_lines)
    report.append("A2 §6b table replaced (%d lines)" % replaced)
else:
    report.append("A2 §6b anchors NOT FOUND (skip)")

# A3. §八 追加 文档分工 + 可维护性纪律
anchor8 = "- 工程状态变化 → 更新本文件「当前工程状态」+ README「当前推进」，并向用户报告一句。"
add8 = (
    "\n"
    "- **文档分工（2026-10-20 定）**：`README.md`=对外门面（工程血缘/快速开始）；`AGENTS.md`=AI 规范权威（§一–§十二）；"
    "`docs/README.md`=文档全量索引；vault `agent.md`=会话入口（只放指针，不复制规范正文）。\n"
    "- **可维护性纪律（2026-10-20 增补）**：单行 ≤800 字符（超长行破坏 diff/检索/阅读；长历史写记录，不堆状态节）；"
    "§十 只保留一个「当前状态」块，历史一律用指针。"
)
if anchor8 in s:
    s = s.replace(anchor8, anchor8 + add8, 1)
    report.append("A3 §8 bullets added")
else:
    report.append("A3 §8 anchor NOT FOUND")

# A4. §十 整段替换（当前状态 + 附A/B/C 精简版）
SEC10_NEW = r'''## 十、当前工程状态（一屏速览；历史详情见附 A 与调试记录）

- ✅ **路线 A（prj10，W0–W6）已收口（2026-10-09）**：DDR 四档逐字节 / 10MB 100%+SHA / 导师四环节 / 死锁专项 / 稳定性 3/3 全过；`prj/project_10/` **目录冻结（只读）**，终版位流 `DBE35734…017F`。详见 `调试记录/` 各记录。
- ✅ **路线 B（prj11，B0–B5 / R1–R4）已收口（2026-10-19）**：round3d 位流 `F6012BA0`（WNS **+0.002** / WHS +0.004）+ 固件 `BA3C0220`；`r2_board.ps1 -Run` **S0–S11 13/13 PASS**（四档 20/20·12/12·12/12·300/300；10MB 7022/7022 + SHA；J3 四链；双桥对账 mem/mem2 各自 wm=wr_frm=rd_frm=9、ost=0、fault=0）。**R3 速率**：1466B 帧可持续 **2000 fps 零丢**、临界 ≈2500 fps、服务上限 ≈2560 fps（≈390 µs/帧；perf2/perf3 A/B 证明瓶颈=每帧软核服务往返，非单点延时；Q5 不要求提速）。**R4**：复现指南 B 章 / 探针清单 / 跨轮归档索引 **33 轮·627 文件·0 缺失**。
- ⏭️ **下一步（非强制）**：双板双链路按 2026-09-30 Q4 定案**暂缓**；SG 描述符环提速 / 调度与 FL 负载验证属新范围。
- 🧭 **权威指针**：当前状态=本文件 §十 + `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十九–§二十二；复现=`复现/复现_prj11_指南_2026-10-19.md`；证据索引=`prj/project_11/out/archive/ARCHIVE_INDEX_prj11.md`。

### 附 A · 工程索引详表（内部视角；状态截至 2026-10-19）

| 目录 | 工程 | 状态 |
|---|---|---|
| `prj/project_1/` | MicroBlaze 最小系统 | ✅ M1（08-11） |
| `prj/ibert_ultrascale_gth_0/` | IBERT 眼图 | ✅ 08-27（10G PRBS 跨口过纤 0E0） |
| `prj/aurora_64b66b_loop_ex/` | Aurora 例程 + UART 桥 | ✅ 08-31（内环验证） |
| `prj/project_6/` | 以太网 UDP 网口栈 | ✅ 09-04（ping/UDP/Wireshark 四包链） |
| `prj/project_8/` | Aurora-UDP 数据级桥 | ✅ M2（09-18） |
| `prj/project_9/` | 真光链路版（双笼 A↔B） | ✅ 09-21（WNS +1.006；10MB 100%+SHA 基线） |
| `prj/project_4/` | MIG/DDR4 | ✅ D1 校准（10-06，双位流全绿）；后续 D 线闭环在 prj10 |
| `prj/project_10/` | 内存进环路（路线 A） | ✅ W0–W6 收口（10-09），**目录冻结只读**，终版 `DBE35734…017F` |
| `prj/project_11/` | 路线 B（软核 + AXI DMA） | ✅ B0–B5/R1–R4 收口（10-19），验收对 `F6012BA0` + `BA3C0220` |
| `prj/0DMA_uart2ddr/`、`prj/project_2~3/`、`prj/project_7/` | 参考实现 / 练手 / 挂起 | 🗄️ 归档或挂起（见附 B 与 vault `操作文档/挂起/`） |

### 附 B · docs/ 文档中心指向

- `docs/` = vault 文档的**脱敏快照**（用户名→`***`，人名→`前辈`；`[[双链]]` 保留）；命名 `[阶段]_prj标识_概要_YYYY-MM-DD`；索引 `docs/README.md`（CI 第 6 项强制一致）。
- 关键文档：`导览_cross_已完成工作说明_2026-10-01.md` · `规划_cross_长期路线图_2026-09-04.md` · `追踪_cross_短期待办_2026-10-10.md` · `调试记录/`（结论与证据）· `操作文档/`（照着做）。

### 附 C · 标准开发流程

1. Vivado：设计 → 综合/实现 → Generate Bitstream → Export Hardware（含 bitstream）→ `.xsa`；
2. Hardware Manager：Program Device（成功标志 `End of startup status: HIGH`）；
3. Vitis：更新 `.xsa` → Run Configuration **取消 Program FPGA**（保留 Reset entire system）→ Run → 串口 9600；
4. 批处理：`vivado -mode batch -source <script>.tcl`（幂等脚本在各自 `scripts\`；⚠️ 工作目录必须纯 ASCII）。

'''
m_start = s.find("## 十、当前工程状态")
m_end = s.find("## 十一、跨目录约定")
if m_start > 0 and m_end > m_start:
    old_sec = s[m_start:m_end]
    s = s[:m_start] + SEC10_NEW + s[m_end:]
    report.append("A4 §10 replaced: old=%d chars new=%d chars" % (len(old_sec), len(SEC10_NEW)))
else:
    report.append("A4 §10 anchors NOT FOUND")

wr(AG, s)
report.append("A AGENTS.md: %d -> %d bytes (saved %d)" % (orig_len, len(s), orig_len - len(s)))

# ============================================================ B. agent.md
a = rd(AGENT)
a_orig = len(a)

# B1 #1–#64 -> #1–#68
if "#1–#64" in a:
    a = a.replace("#1–#64", "#1–#68（截至 2026-10-19）", 1)
    report.append("B1 pit range updated")
else:
    report.append("B1 pit range not found")

# B2 L24 交接单指针
old24 = "| **交接单（新对话从这里开始）** | `操作文档/阶段三_prj11_R2板验续作交接单_2026-10-18.md`（状态/哈希/下一步/坑/开工 checklist）；进度底稿见 `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十二–§十六 |"
new24 = "| **当前入口（新对话从这里开始）** | `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十九–§二十二（路线 B 收口记录 + 速率 + 重审）；复现 `复现/复现_prj11_指南_2026-10-19.md`；剩余清单 `操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md` §七/§八 |"
if old24 in a:
    a = a.replace(old24, new24, 1)
    report.append("B2 L24 pointer updated")
else:
    report.append("B2 L24 anchor not found")

# B3 L46 文档地图交接单行
old46 = "| `操作文档/阶段三_prj11_R2板验续作交接单_2026-10-18.md` | **R2 续作交接单（新对话第一份读）**：当前状态、证据哈希、环境、下一步与坑清单 |"
new46 = "| `调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` | **路线 B 收口记录（新对话第一份读）**：全过程/判据/速率/重审，§十九–§二十二 为收口结论 |"
if old46 in a:
    a = a.replace(old46, new46, 1)
    report.append("B3 L46 updated")
else:
    report.append("B3 L46 anchor not found")

# B4 prj11 主线判据标题
old86 = "**prj11 R2 主线判据（当前在推进；prj9 段为历史基线）**："
new86 = "**prj11 路线 B 判据（已收口；prj9 段为历史基线）**："
if old86 in a:
    a = a.replace(old86, new86, 1)
    report.append("B4 heading updated")
else:
    report.append("B4 heading not found")

# B5 ILA 取证块（round3 -> round3d / r3c_cap）
old_b5 = (
    "# 写流首拍取证（round3 位流；触发 tvalid&&tready&&!tlast）\n"
    "$env:R2_LTX='<归档 ltx>'; $env:R2_OUT_DIR='D:\\FPGA\\prj\\project_11\\out\\evidence_<日期>'\n"
    "$env:R2_TAG='wstream'\n"
    "vivado -mode batch -source D:\\FPGA\\prj\\project_11\\out\\evidence_2026-10-18\\tools\\r2_ila5_capture.tcl"
)
new_b5 = (
    "# 桥级 ILA 抓取（round3d 验收 ltx；详见 复现_prj11_指南 §9）\n"
    "$env:R2_LTX='<round3d 归档 ltx>'; $env:R2_OUT_DIR='D:\\FPGA\\prj\\project_11\\out\\evidence_2026-10-19'\n"
    "$env:R2_TAG='r3d'\n"
    "vivado -mode batch -source D:\\FPGA\\prj\\project_11\\out\\evidence_2026-10-19\\tools\\r3c_cap.tcl"
)
if old_b5 in a:
    a = a.replace(old_b5, new_b5, 1)
    report.append("B5 ILA block updated")
else:
    report.append("B5 ILA block not found")

# B6 板卡物理状态
old_b6 = "- **板卡物理状态（2026-10-18 23:30 收尾）**：**已断电**；最后在役配置 = R2 round2f 位流 `8A8FE378` + 固件 `b614a2dc`（断电即失，下次开场重烧，见交接单）。"
new_b6 = "- **板卡状态（2026-10-19 收尾时的最后在役配置）**：round3d 位流 `F6012BA0` + 固件 `BA3C0220`（`'d'` 后 DMA 模式）；是否上电以现场为准，重烧与体检见 `复现/复现_prj11_指南_2026-10-19.md` §2–§3。"
if old_b6 in a:
    a = a.replace(old_b6, new_b6, 1)
    report.append("B6 board state updated")
else:
    report.append("B6 board state not found")

# B7 当前状态段（L121-126）替换
lines_a = a.split("\n")
i_start = None
i_end = None
for i, ln in enumerate(lines_a):
    if ln.startswith("## 当前状态（2026-10-18 23:30 收尾"):
        i_start = i
    if i_start is not None and ln.startswith("### 历史状态（≤2026-10-17"):
        i_end = i
        break
NEW_CUR = r'''## 当前状态（2026-10-20 更新；主线 = 路线 B 已收口）

- ✅ **路线 B（prj11）已全量收口（2026-10-19）**：round3d 位流 `F6012BA0`（WNS +0.002）+ 固件 `BA3C0220`；S0–S11 **13/13 PASS**；四档 / 10MB 100%+SHA / J3 四链 / 双桥对账全过；R3 速率：1466B 可持续 2000fps 零丢、上限≈2560fps；R4 文档收口完成（复现指南 / 探针清单 / 归档索引 0 缺失）。
- ✅ **路线 A（prj10）目录冻结只读**（终版 `DBE35734…017F`）。
- **入口**：`调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md` §十九–§二十二（收口/速率/重审）；`复现/复现_prj11_指南_2026-10-19.md`（一键复现）；`操作文档/阶段三_prj11_路线B剩余工作清单_2026-10-16.md` §七/§八（重审与收尾）。
- **下一步（非强制）**：双板双链路按 2026-09-30 Q4 暂缓；SG 描述符环 / 调度与 FL 负载验证属新范围。

'''
if i_start is not None and i_end is not None and i_end > i_start:
    old_block = "\n".join(lines_a[i_start:i_end])
    lines_a = lines_a[:i_start] + NEW_CUR.split("\n") + lines_a[i_end:]
    a = "\n".join(lines_a)
    report.append("B7 current-status block replaced (old=%d chars)" % len(old_block))
else:
    report.append("B7 current-status anchors NOT FOUND")

# B8 历史状态段 -> 指针（删 L128 起至文末）
lines_a = a.split("\n")
i_hist = None
for i, ln in enumerate(lines_a):
    if ln.startswith("### 历史状态（≤2026-10-17"):
        i_hist = i
        break
if i_hist is not None:
    old_hist = "\n".join(lines_a[i_hist:])
    NEW_HIST = r'''### 历史状态（≤2026-10-19，仅供追溯）

路线 A（W0–W6）与路线 B（B0–B5 / R1–R4）的完整过程、位流哈希、缺陷链与证据均在：
`调试记录/`（尤其 `阶段三_prj10_*`、`阶段三_prj11_*` 系列）与 `D:\FPGA\prj\project_11\out\archive\ARCHIVE_INDEX_prj11.md`。
本文件自 2026-10-20 起不再维护逐日历史（精简，约 -35KB）。
'''
    a = "\n".join(lines_a[:i_hist]) + "\n" + NEW_HIST
    report.append("B8 history section replaced (old=%d chars)" % len(old_hist))
else:
    report.append("B8 history section NOT FOUND")

# B9 顶部加一行"路线 B 已收口"状态提示（若未有）
top_anchor = "> 工程规范权威版本 = `D:\\FPGA\\AGENTS.md`；本文件与它冲突时，以 AGENTS.md 为准并回改本文件。"
if top_anchor in a and "路线 B 已收口" not in a.split("\n")[0:8].__str__():
    a = a.replace(top_anchor, top_anchor + "\n> 状态提示：**路线 A（prj10）冻结、路线 B（prj11）已于 2026-10-19 全量收口**；当前入口见下方「30 秒导航」。", 1)
    report.append("B9 top status line added")

wr(AGENT, a)
report.append("B agent.md(vault): %d -> %d bytes (saved %d)" % (a_orig, len(a), a_orig - len(a)))

# ============================================================ C. docs/agent.md 镜像
da = rd(DAGENT)
da_orig = len(da)
new_mirror = a
# 脱敏：用户名/用户路径
new_mirror = new_mirror.replace("C:\\Users\\15266", "C:\\Users\\***").replace("15266", "***")
wr(DAGENT, new_mirror)
report.append("C docs/agent.md: %d -> %d bytes" % (da_orig, len(new_mirror)))

# ============================================================ D. skills frontmatter
for name in ("hw-ila-debug", "hw-vio-debug"):
    p = os.path.join(SKILLS, name, "SKILL.md")
    t = rd(p)
    before = sha(p)
    note = " 本工作区注（2026-10-20）：未挂 MCP，走 D:/vivado-mcp/mcp_ctl.py CLI 桥或 Vivado batch Tcl（见文首本机适配注记）。"
    # description 行以双引号开头；插入到引号内末尾（行尾 " 之前）
    lines_t = t.split("\n")
    changed = False
    for i, ln in enumerate(lines_t):
        if ln.startswith("description: \"") and ln.rstrip().endswith("\""):
            lines_t[i] = ln.rstrip()[:-1] + note + "\""
            changed = True
            break
    if changed:
        wr(p, "\n".join(lines_t))
        report.append("D %s description updated (sha %s -> %s)" % (name, before[:8], sha(p)[:8]))
    else:
        report.append("D %s description anchor NOT FOUND" % name)

# ============================================================ E1. profile 备份归档
arch = os.path.join(PROFILES, "_backups_archive", "2026-10-20")
os.makedirs(arch, exist_ok=True)
moved = []
for prof in ("web", "desktop"):
    d = os.path.join(PROFILES, prof)
    baks = [f for f in os.listdir(d) if f.startswith("cordis.patch.yml.bak")]
    baks.sort(key=lambda f: os.path.getmtime(os.path.join(d, f)), reverse=True)
    for f in baks[1:]:  # 保留最新 1 份
        src = os.path.join(d, f)
        dst = os.path.join(arch, prof + "__" + f)
        shutil.move(src, dst)
        moved.append(os.path.basename(dst))
report.append("E1 profile backups archived: %d -> %s" % (len(moved), arch))

# ============================================================ E2. vault _tmp 清理
trash = os.path.join(VAULT, ".trash", "_cleanup_20261020")
os.makedirs(trash, exist_ok=True)
tmp_moved = []
for f in os.listdir(VAULT):
    if f.startswith("_tmp") and os.path.isfile(os.path.join(VAULT, f)):
        shutil.move(os.path.join(VAULT, f), os.path.join(trash, f))
        tmp_moved.append(f)
report.append("E2 vault temp files moved to .trash: %s" % ", ".join(tmp_moved))

print("\n".join(report))
