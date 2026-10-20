# -*- coding: utf-8 -*-
"""split_pitfalls_20261020.py — 把 AGENTS.md §九 坑账本全文拆到仓库根 PITFALLS.md，
§九 只保留「编号 + 主题」索引。用户已批准（2026-10-20）。

约束：不丢任何坑条目；编号 1–68 连续；新增坑只在 PITFALLS.md 表尾追加。
"""
import hashlib
import io
import os
import re

REPO = r"D:\FPGA"
AG = os.path.join(REPO, "AGENTS.md")
PIT = os.path.join(REPO, "PITFALLS.md")
AGENT = r"C:\Users\15266\Desktop\毕设\agent.md"
DAGENT = os.path.join(REPO, "docs", "agent.md")

s = io.open(AG, encoding="utf-8", newline="").read()
lines = s.split("\n")
i9 = next(i for i, x in enumerate(lines) if x.startswith("## 九、"))
i10 = next(i for i, x in enumerate(lines) if x.startswith("## 十、"))
sec_lines = lines[i9:i10]
old_sec = "\n".join(sec_lines)

# 解析表格行
rows = []
intro = []
header = None
for ln in sec_lines:
    if re.match(r"^\|\s*\d+\s*\|", ln):
        rows.append(ln)
    elif ln.startswith("| # |"):
        header = ln
    elif ln.startswith(">") and "规范化" in ln:
        intro.append(ln)

nums = []
for ln in rows:
    m = re.match(r"^\|\s*(\d+)\s*\|", ln)
    nums.append(int(m.group(1)))
assert nums == list(range(1, 69)), "pit numbers not 1..68: %s" % (nums[:5], nums[-5:])

# 主题（第 2 列）提取
def title_of(ln):
    parts = ln.split("|")
    if len(parts) >= 4:
        t = parts[2].strip()
    else:
        t = parts[1].strip() if len(parts) > 1 else ln
    t = t.replace("**", "").strip()
    t = t.replace("|", "\\|")
    return t

titles = [title_of(ln) for ln in rows]

PIT_TXT = []
PIT_TXT.append("# PITFALLS.md — 工程坑账本（#1–#68，全文）")
PIT_TXT.append("")
PIT_TXT.append("> 本文件是 `AGENTS.md` **§九** 的全文拆分（2026-10-20，用户批准）。")
PIT_TXT.append("> 定位：**踩过的坑 = 规范的来源**；本文是坑账本的唯一全文，`AGENTS.md §九` 只保留「编号 + 主题」索引。")
PIT_TXT.append("> 维护纪律：**新增坑只在表尾追加**（编号连续、不重排、不删旧条）；同族条目用互见标注；已闭环条目保留。")
PIT_TXT.append("")
for x in intro:
    PIT_TXT.append(x)
    PIT_TXT.append("")
PIT_TXT.append("| # | 坑 | 根因与修法 |")
PIT_TXT.append("|---|---|---|")
PIT_TXT.extend(rows)
PIT_TXT.append("")
PIT_TXT.append("---")
PIT_TXT.append("*拆出自 `AGENTS.md §九`（2026-10-20）；原文三列格式与全部 68 条未改动。索引见 `AGENTS.md §九`。*")
pit_txt = "\n".join(PIT_TXT) + "\n"
io.open(PIT, "w", encoding="utf-8", newline="").write(pit_txt)

# 新 §九：索引（两列对，34 行）
idx = []
idx.append("## 九、Correction（坑账本索引；全文见仓库根 `PITFALLS.md`）")
idx.append("")
idx.append("> 踩过的坑 = 规范的来源。**#1–#68 的完整「坑 / 根因与修法」已移至 `PITFALLS.md`（2026-10-20 拆分）**；本节只保留编号+主题索引。")
idx.append("> 维护：新增坑只在 `PITFALLS.md` 表尾追加（编号连续、不重排、不删旧条），并在此索引加一行。")
idx.append("")
idx.append("| # | 主题 | # | 主题 |")
idx.append("|---|---|---|---|")
half = (len(titles) + 1) // 2
for k in range(half):
    a = k + 1
    ta = titles[k]
    b = k + 1 + half
    tb = titles[k + half] if k + half < len(titles) else ""
    idx.append("| %d | %s | %s | %s |" % (a, ta, ("%d" % b) if tb else "", tb))
idx.append("")
new_sec = "\n".join(idx) + "\n"

s2 = s.replace(old_sec, new_sec, 1)
assert s2 != s, "§九 replace failed"

# §八 维护纪律补一条
anchor = "§十 只保留一个「当前状态」块，历史一律用指针。"
add = "\n" + "- **坑账本维护（2026-10-20 拆分）**：全文 `PITFALLS.md`（仓库根）；新增坑只在表尾追加并保持编号连续；`AGENTS.md §九` 只维护索引，不复制正文。"
if anchor in s2:
    s2 = s2.replace(anchor, anchor + add, 1)

io.open(AG, "w", encoding="utf-8", newline="").write(s2)

# agent.md：坑账本索引指向更新
a = io.open(AGENT, encoding="utf-8", newline="").read()
a2 = a.replace(
    "| **坑账本**（#1–#68，踩过的坑与修法） | AGENTS.md **§九** |",
    "| **坑账本**（#1–#68，踩过的坑与修法） | `PITFALLS.md`（全文，仓库根）+ AGENTS.md **§九**（索引） |",
    1,
)
if a2 != a:
    io.open(AGENT, "w", encoding="utf-8", newline="").write(a2)
    # 镜像
    m = a2.replace("C:\\Users\\15266", "C:\\Users\\***").replace("15266", "***")
    io.open(DAGENT, "w", encoding="utf-8", newline="").write(m)
    print("agent.md pit pointer updated + mirrored")
else:
    print("WARN agent.md pit pointer not found")

print("PITFALLS.md bytes=", os.path.getsize(PIT))
print("AGENTS.md bytes=", os.path.getsize(AG))
print("old §9 bytes=", len(old_sec.encode("utf-8")))
print("new §9 bytes=", len(new_sec.encode("utf-8")))
print("rows moved=", len(rows), "index rows=", half)
