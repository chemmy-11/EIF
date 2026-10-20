# -*- coding: utf-8 -*-
"""Re-generate compact §九 index in AGENTS.md (truncate long titles), add README pointer.
PITFALLS.md itself is NOT touched."""
import io
import os
import re

REPO = r"D:\FPGA"
AG = os.path.join(REPO, "AGENTS.md")
PIT = os.path.join(REPO, "PITFALLS.md")
README = os.path.join(REPO, "README.md")

pt = io.open(PIT, encoding="utf-8", newline="").read()
rows = [l for l in pt.split("\n") if re.match(r"^\|\s*\d+\s*\|", l)]
assert len(rows) == 68


def title_of(ln, maxlen=46):
    parts = ln.split("|")
    t = parts[2].strip() if len(parts) >= 4 else ln
    t = t.replace("**", "").strip().replace("|", "\\|")
    t = re.sub(r"\s+", " ", t)
    if len(t) > maxlen:
        t = t[:maxlen - 1] + "…"
    return t


titles = [title_of(l) for l in rows]

idx = []
idx.append("## 九、Correction（坑账本索引；全文见仓库根 `PITFALLS.md`）")
idx.append("")
idx.append("> 踩过的坑 = 规范的来源。**#1–#68 的完整「坑 / 根因与修法」已移至 `PITFALLS.md`（2026-10-20 拆分）**；本节只保留编号+主题索引（长标题截断，全文以 `PITFALLS.md` 为准）。")
idx.append("> 维护：新增坑只在 `PITFALLS.md` 表尾追加（编号连续、不重排、不删旧条），并在此索引加一行。")
idx.append("")
idx.append("| # | 主题 | # | 主题 |")
idx.append("|---|---|---|---|")
half = (len(titles) + 1) // 2
for k in range(half):
    a = k + 1
    b = k + 1 + half
    tb = titles[k + half] if k + half < len(titles) else ""
    idx.append("| %d | %s | %s | %s |" % (a, titles[k], ("%d" % b) if tb else "", tb))
idx.append("")
new_sec = "\n".join(idx) + "\n"

s = io.open(AG, encoding="utf-8", newline="").read()
lines = s.split("\n")
i9 = next(i for i, x in enumerate(lines) if x.startswith("## 九、Correction"))
i10 = next(i for i, x in enumerate(lines) if x.startswith("## 十、"))
old = "\n".join(lines[i9:i10])
s2 = s.replace(old, new_sec, 1)
assert s2 != s
io.open(AG, "w", encoding="utf-8", newline="").write(s2)
print("AGENTS §9 compacted:", len(old.encode("utf-8")), "->", len(new_sec.encode("utf-8")), "bytes; AGENTS total", os.path.getsize(AG))

# README 关键文档区加 PITFALLS 指针（若存在且未加）
r = io.open(README, encoding="utf-8", newline="").read()
if "PITFALLS.md" not in r:
    m = re.search(r"^## 关键文档\s*$", r, re.M)
    if m:
        # 在该节第一个列表项前插入一行
        after = r[m.end():]
        mm = re.search(r"\n(\s*[-*]\s.*\n)", after)
        if mm:
            ins = "\n- **坑账本全文**：`PITFALLS.md`（#1–#68；索引见 `AGENTS.md §九`）\n"
            pos = m.end() + mm.start(1)
            r = r[:pos] + ins + r[pos:]
            io.open(README, "w", encoding="utf-8", newline="").write(r)
            print("README pointer added")
        else:
            print("WARN README bullet anchor not found")
    else:
        print("WARN README 关键文档 section not found")
else:
    print("README already mentions PITFALLS.md")
