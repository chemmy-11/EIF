# -*- coding: utf-8 -*-
"""Fix docs mirror of 追踪_cross_短期待办: vault-only relative links -> plain note
(mirror convention: no links to files that are not mirrored under docs/)."""
import io

p = r"D:\FPGA\docs\追踪_cross_短期待办_2026-10-10.md"
s = io.open(p, "r", encoding="utf-8", newline="").read()
old = ("[长期路线图](规划_cross_长期路线图_2026-09-04.md) · "
       "[开题报告](毕设方向与论文大纲/开题报告_2026-09-22.md) · "
       "[AI-Infra 系统设计报告](AI-Infra系统设计/FPGA-AI-Infra-系统设计报告.md) · ")
new = ("[长期路线图](规划_cross_长期路线图_2026-09-04.md) · "
       "开题报告（毕设 vault，未镜像） · AI-Infra 系统设计报告（毕设 vault，未镜像） · ")
assert old in s, "link block not found"
s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8", newline="").write(s)
print("mirror links fixed, size=", len(s.encode("utf-8")))
