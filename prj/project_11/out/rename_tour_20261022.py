# -*- coding: utf-8 -*-
"""rename_tour_20261022.py — 已完成工作说明改名为 2026-10-22，并同步全部链接（vault + docs 镜像）。

- vault: 汇报/导览_cross_已完成工作说明_2026-10-01.md -> ..._2026-10-22.md（frontmatter 加旧名 alias）
- repo: docs/导览_cross_已完成工作说明_2026-10-01.md -> ..._2026-10-22.md（git mv + 脱敏镜像）
- 链接同步：AGENTS.md / README.md / docs/README.md / docs/agent.md / vault agent.md / vault README.md
"""
import io
import os
import subprocess

VAULT = r"C:\Users\15266\Desktop\毕设"
REPO = r"D:\FPGA"
OLD = "导览_cross_已完成工作说明_2026-10-01"
NEW = "导览_cross_已完成工作说明_2026-10-22"

V_OLD = os.path.join(VAULT, "汇报", OLD + ".md")
V_NEW = os.path.join(VAULT, "汇报", NEW + ".md")
D_OLD = os.path.join(REPO, "docs", OLD + ".md")
D_NEW = os.path.join(REPO, "docs", NEW + ".md")

# 1) 重命名
assert os.path.isfile(V_OLD), "vault file missing"
os.replace(V_OLD, V_NEW)
if os.path.isfile(D_OLD):
    subprocess.run(["git", "-C", REPO, "mv", "docs/" + os.path.basename(D_OLD),
                    "docs/" + os.path.basename(D_NEW)], check=True)

# 2) 在 vault 新文件 frontmatter 加 alias，并确保 updated 日期
s = io.open(V_NEW, encoding="utf-8", newline="").read()
if "alias:" not in s.split("\n---", 1)[0]:
    s = s.replace("type: 导览", "type: 导览\nalias: " + OLD, 1)
s = s.replace("updated: 2026-10-01", "updated: 2026-10-22", 1)
io.open(V_NEW, "w", encoding="utf-8", newline="").write(s)

# 3) docs 镜像（脱敏）
m = s.replace("C:\\Users\\15266", "C:\\Users\\***").replace("15266", "***")
io.open(D_NEW, "w", encoding="utf-8", newline="").write(m)

# 4) 链接同步
targets = [
    os.path.join(REPO, "AGENTS.md"),
    os.path.join(REPO, "README.md"),
    os.path.join(REPO, "docs", "README.md"),
    os.path.join(REPO, "docs", "agent.md"),
    os.path.join(VAULT, "agent.md"),
    os.path.join(VAULT, "README.md"),
]
for p in targets:
    t = io.open(p, encoding="utf-8", newline="").read()
    n = t.count(OLD)
    if n:
        t = t.replace(OLD, NEW)
        io.open(p, "w", encoding="utf-8", newline="").write(t)
    print("%-40s replaced=%d" % (os.path.relpath(p, VAULT if p.startswith(VAULT) else REPO), n))

print("DONE")
print("VAULT new:", os.path.basename(V_NEW), os.path.getsize(V_NEW), "B")
print("DOCS  new:", os.path.basename(D_NEW), os.path.getsize(D_NEW), "B")
