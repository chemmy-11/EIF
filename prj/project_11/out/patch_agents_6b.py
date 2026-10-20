# -*- coding: utf-8 -*-
"""Patch AGENTS.md §6b table rows (three rows) to reflect actual skill/MCP state."""
import io

P = r"D:\FPGA\AGENTS.md"
t = io.open(P, encoding="utf-8").read().split("\n")

new_rows = [
    "| 项目级 AI 技能（7 个：6 官方 AMD 技能 + `amd-doc-search` CLI 桥） | `<vault>\\.dsh\\skills\\` | **仅本工作区**（DSH `projectRoot/.dsh/skills`，rank 100） | 已生效（热加载）。**注意**：`hw-ila-debug`/`hw-vio-debug` 依赖的 `vivado-mcp` MCP 未挂进当前会话；两技能文首有「本机适配注记」→ 走 CLI 桥 `D:\\vivado-mcp\\mcp_ctl.py` 或 Vivado batch Tcl |",
    "| 官方文档检索（原生 MCP） | `~/.dsh/profiles/web/cordis.patch.yml` 的 `mcp-amd-doc-search` 条目 | DSH **web profile 全局**（所有工作区；重启 `dsh web` 后生效） | **已配置但当前进程未加载**（会话工具清单无 `mcp__amd_doc_search`）；重启后生效，工具名 `mcp__amd_doc_search__vivado_doc_search` |",
    "| 官方文档检索（项目级 CLI 桥） | `<vault>\\.dsh\\skills\\amd-doc-search\\doc_search.py` | **仅本工作区** | **当前实际生效**：`py doc_search.py \"<query>\"`（stdlib 直连，无需重启） |",
]

out = []
i = 0
replaced = 0
while i < len(t):
    ln = t[i]
    if ln.startswith("| 项目级 AI 技能（7 个"):
        out.extend(new_rows)
        j = i + 1
        skipped = 0
        while j < len(t) and skipped < 2:
            if t[j].startswith("| 官方文档检索（原生 MCP）") or t[j].startswith("| 官方文档检索（项目级"):
                j += 1
                skipped += 1
                continue
            break
        i = j
        replaced += 1
        continue
    out.append(ln)
    i += 1

io.open(P, "w", encoding="utf-8", newline="").write("\n".join(out))
print("6B_PATCH rows_replaced=", replaced, "skipped_following=", "?")
print("bytes=", len(io.open(P, "rb").read()))
