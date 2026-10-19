# -*- coding: utf-8 -*-
"""Repair round3c archive after an accidental re-run overwrote it with round3d artifacts.

Steps:
1) restore the round3c archive tree from commit 6190769 (contains the true round3c bit/ltx/xsa
   and its SHA256.txt);
2) add UTF-8 BOM to archived PowerShell copies lacking it (CI rule; PS5.1 + Chinese comments);
3) recompute the archive SHA256.txt table from the files actually present (self-consistent).

The round3d archive is intentionally NOT touched here (it was regenerated after the BOM fix).
"""
import hashlib
import io
import os
import subprocess

REPO = r"D:\FPGA"
ARC3C = os.path.join(REPO, "prj", "project_11", "out", "archive", "b31b_r2_2026-10-19_round3c")
COMMIT = "6190769"

# 1) restore round3c archive from the commit
subprocess.run(["git", "-C", REPO, "checkout", COMMIT, "--",
                "prj/project_11/out/archive/b31b_r2_2026-10-19_round3c"], check=True)
print("restored round3c archive from", COMMIT)


def sha256(p):
    h = hashlib.sha256()
    with io.open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest().upper()


# 2) BOM for PowerShell copies
bom_fixed = []
for root, _dirs, files in os.walk(ARC3C):
    for fn in files:
        if not fn.lower().endswith(".ps1"):
            continue
        p = os.path.join(root, fn)
        raw = io.open(p, "rb").read()
        if not raw.startswith(b"\xef\xbb\xbf"):
            io.open(p, "wb").write(b"\xef\xbb\xbf" + raw)
            bom_fixed.append(os.path.relpath(p, ARC3C))
print("BOM fixed:", bom_fixed)

# 3) recompute SHA256.txt table
txt_path = os.path.join(ARC3C, "SHA256.txt")
lines = io.open(txt_path, encoding="utf-8", newline="").read().splitlines()
head = []
for ln in lines:
    if ln.startswith("|"):
        break
    head.append(ln)
rows = []
for root, _dirs, files in os.walk(ARC3C):
    for fn in files:
        p = os.path.join(root, fn)
        rel = os.path.relpath(p, ARC3C).replace("\\", "/")
        if rel == "SHA256.txt":
            continue
        rows.append((rel, sha256(p), os.path.getsize(p)))
rows.sort(key=lambda r: r[0])
out = head + ["| 文件 | 字节 | SHA256 |", "|---|---|---|"]
for rel, h, n in rows:
    out.append("| %s | %d | %s |" % (rel, n, h))
out.append("")
out.append("注: 2026-10-19 CI 修复轮——归档内 PowerShell 副本补 UTF-8 BOM 后本表重算（bit/ltx/xsa 与 ELF 不变）；"
           "位流烧写前一律先 Get-FileHash 核对本表。")
io.open(txt_path, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("SHA256.txt rebuilt rows=", len(rows))
