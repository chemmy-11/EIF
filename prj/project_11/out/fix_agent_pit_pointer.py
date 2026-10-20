# -*- coding: utf-8 -*-
"""Fix agent.md pit-ledger pointer (line text changed earlier) and refresh docs mirror."""
import io

AGENT = r"C:\Users\15266\Desktop\毕设\agent.md"
DAGENT = r"D:\FPGA\docs\agent.md"

a = io.open(AGENT, encoding="utf-8", newline="").read()
lines = a.split("\n")
hit = 0
for i, ln in enumerate(lines):
    if ln.startswith("| **坑账本**"):
        before = ln
        # 将 "AGENTS.md **§九**" 替换为 全文+索引
        if "AGENTS.md **§九**" in ln:
            lines[i] = ln.replace("AGENTS.md **§九**",
                                  "`PITFALLS.md`（全文，仓库根）+ AGENTS.md **§九**（索引）")
            hit = 1
        print("PIT_LINE_BEFORE:", before[:160])
        print("PIT_LINE_AFTER :", lines[i][:200])
        break
if hit:
    a2 = "\n".join(lines)
    io.open(AGENT, "w", encoding="utf-8", newline="").write(a2)
    m = a2.replace("C:\\Users\\15266", "C:\\Users\\***").replace("15266", "***")
    io.open(DAGENT, "w", encoding="utf-8", newline="").write(m)
    print("FIXED + MIRRORED")
else:
    print("WARN: pit line not matched")
