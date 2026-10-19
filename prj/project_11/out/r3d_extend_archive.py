# -*- coding: utf-8 -*-
"""Extend r2_archive_round3d.py evidence list with final S0-S11 evidence."""
import io

p = r"D:\FPGA\prj\project_11\out\r2_archive_round3d.py"
s = io.open(p, encoding="utf-8", newline="").read()

old = '''for fn in [
    "R3C_fourtier_perf1.log", "R3C_j3_fourchains_run2.log",
    "R3C_board_session_20261019.md", "R3C_evt2_dump.txt",
]:'''
new = '''for fn in [
    "R3C_fourtier_perf1.log", "R3C_board_session_20261019.md", "R3C_evt2_dump.txt",
    "R3D_S0-S11_run1.log", "R3D_S0-S11_run2.log", "R3D_S0-S11_run3.log",
    "EVIDENCE_INDEX_r3c.md", "R3D_S10_recon_manual.log", "R3D_S10_recon_manual.json",
    "R2_4tier_20261019_164245.log", "R2_mb10_20261019_164518.log",
]:'''
assert old in s, "evidence list block not found"
s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("EXTENDED evidence list")
