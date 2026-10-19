# -*- coding: utf-8 -*-
"""Fix r2_archive_round3d.py: adapter log lives in ARC already (avoid self-copy)."""
import io

p = r"D:\FPGA\prj\project_11\out\r2_archive_round3d.py"
s = io.open(p, encoding="utf-8", newline="").read()

line = 'add("R3D_s0_buildlog_adapter.log", os.path.join(ARC, "R3D_s0_buildlog_adapter.log"))'
if line in s:
    s = s.replace(line + "\n", "")
    s = s.replace(line, "")

anchor = "copied = []\nfor dst, src in items:"
new = (
    "copied = []\n"
    "_ad = os.path.join(ARC, \"R3D_s0_buildlog_adapter.log\")\n"
    "if os.path.exists(_ad):\n"
    "    copied.append((\"R3D_s0_buildlog_adapter.log\", sha256(_ad), os.path.getsize(_ad)))\n"
    "for dst, src in items:"
)
assert anchor in s, "anchor missing"
s = s.replace(anchor, new, 1)

io.open(p, "w", encoding="utf-8", newline="").write(s)
print("FIXED archive script")
