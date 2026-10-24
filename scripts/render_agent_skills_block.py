#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""render_agent_skills_block.py — 把 MANIFEST.json 渲染进 agent.md 的 BEGIN:skills 区块，
并顺带把 vault `agent.md` 脱敏同步成仓库镜像 `docs/agent.md`（镜像纪律：同步后必须重新脱敏）。

数据源（唯一真源）：
    <vault>\\.dsh\\skills\\MANIFEST.json     ← 由 scripts/gen_skills_manifest.py 从 SKILL.md frontmatter 生成
目标：
    <vault>\\agent.md                        ← 区块内容由本脚本生成，禁止手改
    D:\\FPGA\\docs\\agent.md                 ← 上者的脱敏副本（用户名 15266 → ***）

用法：
    py scripts/render_agent_skills_block.py --check     # 只校验区块是否与 MANIFEST 一致（CI 用，不写盘）
    py scripts/render_agent_skills_block.py --write     # 渲染区块 + 同步镜像（会先备份）
退出码：0 = 一致/写入成功；1 = 不一致（--check）或出错
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VAULT = Path(r"C:\Users\15266\Desktop\毕设")
MANIFEST = VAULT / ".dsh" / "skills" / "MANIFEST.json"
AGENT_MD = VAULT / "agent.md"
MIRROR_MD = ROOT / "docs" / "agent.md"
SANITIZE = (("15266", "***"),)  # 与 AGENTS.md 十二节「脱敏快照」口径一致
BEGIN = "<!-- BEGIN:skills"
END = "<!-- END:skills -->"
STATUS_LABEL = {"verified": "✅ 本机实测", "unverified": "⚠️ 未在本机实测"}


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def render_block(man: dict) -> str:
    rows = [
        f"{BEGIN} · 由 `D:\\FPGA\\scripts\\render_agent_skills_block.py` 从 "
        f"`.dsh\\skills\\MANIFEST.json` 生成，**勿手改**；数据源 = 各 `SKILL.md` frontmatter，"
        f"生成器 `D:\\FPGA\\scripts\\gen_skills_manifest.py` -->",
        "",
        "| 技能 | 版本 | AMD 基线 | 本机实测 | 状态 | 目录内脚本 |",
        "|---|---|---|---|---|---|",
    ]
    for s in man["skills"]:
        b = s.get("baseline") or {}
        amd = b.get("amd_doc") or "?"
        tested = b.get("tested_on") or "—"
        status = STATUS_LABEL.get(b.get("status"), b.get("status") or "?")
        scripts = "、".join(f"`{x}`" for x in s.get("scripts") or []) or "—"
        rows.append(f"| `{s['name']}` | {s.get('version') or '—'} | {amd} | {tested} | {status} | {scripts} |")
    rows += [
        "",
        f"<sub>source_hash `{(man.get('source_hash') or '')[:16]}…` · "
        f"mcp 工具目录 {len(man['tool_catalog']['mcp_vivado'])} 项 · "
        f"重算命令 `py D:\\FPGA\\scripts\\gen_skills_manifest.py`</sub>",
        "",
        END,
    ]
    return "\n".join(rows)


def replace_block(text: str, block: str) -> str:
    start = text.find(BEGIN)
    if start < 0:
        raise SystemExit(f"[ERROR] {AGENT_MD} 里没有 {BEGIN} 标记，先手工加一对标记")
    end = text.find(END, start)
    if end < 0:
        raise SystemExit(f"[ERROR] {AGENT_MD} 里没有配对的 {END} 标记")
    # 吃掉标记行前的缩进/空行边界，保持段落整洁
    line_start = text.rfind("\n", 0, start) + 1
    end_line = text.find("\n", end) + 1
    if end_line == 0:
        end_line = len(text)
    return text[:line_start] + block + "\n" + text[end_line:]


def sanitize(text: str) -> str:
    for a, b in SANITIZE:
        text = text.replace(a, b)
    return text


def main() -> int:
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true", help="只校验，不写盘")
    g.add_argument("--write", action="store_true", help="渲染区块并同步镜像（会备份）")
    args = ap.parse_args()

    man = load_manifest()
    cur = AGENT_MD.read_text(encoding="utf-8")
    want = replace_block(cur, render_block(man))

    if args.check:
        ok = want == cur
        print("[PASS] agent.md 的 BEGIN:skills 区块与 MANIFEST 一致" if ok else
              "[FAIL] agent.md 的 BEGIN:skills 区块与 MANIFEST 不一致（重跑 render_agent_skills_block.py --write）")
        mirror_ok = MIRROR_MD.is_file() and MIRROR_MD.read_text(encoding="utf-8") == sanitize(cur)
        print("[PASS] docs/agent.md 与 vault agent.md 脱敏等价" if mirror_ok else
              "[FAIL] docs/agent.md 与 vault agent.md 脱敏后不一致（重跑 --write 同步）")
        return 0 if (ok and mirror_ok) else 1

    bak = AGENT_MD.with_name(f"agent.md.bak-{date.today().strftime('%Y%m%d')}")
    if not bak.exists():
        bak.write_text(cur, encoding="utf-8")
        print(f"[bak] {bak}")
    AGENT_MD.write_text(want, encoding="utf-8")
    print(f"[write] {AGENT_MD}（区块已刷新）")

    # 镜像侧不再留 .bak：`docs/agent.md` 是 100% 派生文件（= sanitize(vault agent.md)），
    # 而且它在 git 里；把备份写进 docs/ 会污染「已发布快照」目录（2026-10-24 实测过：
    # docs/agent.md.bak-20261024 会让全盘回退扫描的文件数从 16388 涨到 16389）。
    MIRROR_MD.parent.mkdir(parents=True, exist_ok=True)
    MIRROR_MD.write_text(sanitize(want), encoding="utf-8")
    print(f"[write] {MIRROR_MD}（脱敏镜像已同步）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
