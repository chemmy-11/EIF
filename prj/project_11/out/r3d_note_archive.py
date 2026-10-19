# -*- coding: utf-8 -*-
"""Append CI-fix note to round3d archive SHA256.txt (table itself does not hash SHA256.txt)."""
import io

p = r"D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3d\SHA256.txt"
s = io.open(p, encoding="utf-8", newline="").read().rstrip("\n")
note = ("注: 2026-10-19 CI 修复轮——归档内 PowerShell 副本（r3d_synth_retry.ps1 等）补 UTF-8 BOM 后本表重算；"
        "bit/ltx/xsa/ELF 未变（F6012BA0/2F8AF498/216839F4/BA3C0220）。")
if note not in s:
    s = s + "\n" + note + "\n"
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)
    print("round3d SHA256 note added")
else:
    print("note already present")
