#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_skills_manifest.py — 生成技能清单 MANIFEST.json（禁手写）。

真源 = 每个技能 SKILL.md 的 frontmatter；本脚本只做「读 + 汇总 + 落盘」，
不参与任何判定。判定在 scripts/ci_check.py 的检查 7-10（本地专用）。

    py scripts/gen_skills_manifest.py                 # 默认 skills_root = 本机 vault 的 .dsh/skills
    py scripts/gen_skills_manifest.py --skills-root <dir> --out <file>

契约见 `.vivado-scratch/vivado-norm-2026-10-24/SPEC.md` §3。要点：
  · source_hash = 各 SKILL.md 字节 sha256（按目录名排序）拼接后再 sha256
    → ci_check 用它判「MANIFEST 过期/手改」。
  · baseline 唯一真源在 SKILL.md frontmatter；缺字段就写 null 并警告（校验会 FAIL，属预期）。
  · tool_catalog 从真实 MCP server 探测（mcp_ctl.py list），探测失败则沿用旧 MANIFEST 的
    catalog 并警告 —— 这样「工具名检查」不需要每台机器都装 vivado-mcp。
  · 不写时间戳：避免每次生成都产生无意义 diff。

退出码：0 = 生成成功（可有警告）；1 = 结构性错误（找不到 skills_root / 无 SKILL.md）。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SKILLS_ROOT = Path(r"C:\Users\15266\Desktop\毕设\.dsh\skills")
MCP_PYTHON = Path(r"D:\vivado-mcp\venv\Scripts\python.exe")
MCP_CTL = Path(r"D:\vivado-mcp\mcp_ctl.py")
MCP_SITE = Path(r"D:\vivado-mcp\site")
EXPECTED_MCP_TOOLS = 32

# 占位符 / 演示路径：不当作真实引用（与 ci_check 检查 8/9 同口径）
PLACEHOLDER = re.compile(r"path/to|\.\.\.|xxx|[<>*{}]")
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
BACKTICK = re.compile(r"`([^`\n]+)`")
SCRIPT_SUFFIXES = {".py", ".tcl", ".ps1"}
REF_PREFIXES = ("references/", "scripts/", "examples/")
REF_FILENAME = re.compile(r"^[\w][\w.\-]*\.(md|py|tcl|ps1|json|v|sv|rpt)$")


def warn(msg: str) -> None:
    print(f"  [warn] {msg}")


def parse_frontmatter(text: str) -> dict:
    """取 `---` 包裹的 YAML frontmatter。优先 PyYAML，缺失时退回最小解析。"""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    raw = text[3:end]
    try:
        import yaml  # noqa: PLC0415  (可选依赖，缺失时走最小解析)
    except Exception:
        return _mini_yaml(raw)
    try:
        data = yaml.safe_load(raw)
    except Exception as exc:  # frontmatter 语法坏 → 不猜，交校验器报
        warn(f"frontmatter YAML 解析失败: {exc}")
        return {}
    return data if isinstance(data, dict) else {}


def _mini_yaml(raw: str) -> dict:
    """最小 YAML 子集：顶层 key: value + 一层嵌套 mapping + 简单列表。"""
    out: dict = {}
    cur_key: str | None = None
    for line in raw.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        body = line.strip()
        if body.startswith("- "):
            if cur_key is not None:
                out.setdefault(cur_key, [])
                if isinstance(out[cur_key], list):
                    out[cur_key].append(_scalar(body[2:]))
            continue
        if ":" not in body:
            continue
        key, _, val = body.partition(":")
        key, val = key.strip(), val.strip()
        if indent == 0:
            if val == "":
                cur_key = key
                out[key] = {}
            else:
                cur_key = None
                out[key] = _scalar(val)
        elif cur_key is not None and isinstance(out.get(cur_key), dict):
            out[cur_key][key] = _scalar(val)
    return out


def _scalar(val: str):
    val = val.strip()
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
        return val[1:-1]
    low = val.lower()
    if low in ("", "~", "null"):
        return None
    if low in ("true", "false"):
        return low == "true"
    return val


def split_body(text: str) -> str:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end >= 0:
            return text[end + 4:]
    return text


def collect_refs(body: str) -> list[str]:
    """SKILL.md 正文引用到的技能内相对路径（不含占位符、不含外链）。"""
    refs: set[str] = set()
    candidates = [m.group(1).strip() for m in LINK.finditer(body)]
    candidates += [m.group(1).strip() for m in BACKTICK.finditer(body)]
    for cand in candidates:
        if not cand or PLACEHOLDER.search(cand):
            continue
        if re.match(r"^[A-Za-z]:[\\/]", cand) or cand.startswith(("/", "\\")):
            continue  # 绝对路径归 ci_check 检查 9
        if cand.startswith(("http://", "https://", "mailto:", "#")):
            continue
        target = cand.split("#", 1)[0].strip()
        if not target or PLACEHOLDER.search(target):
            continue
        if target.startswith(REF_PREFIXES) or REF_FILENAME.match(target):
            refs.add(target.replace("\\", "/"))
    return sorted(refs)


def collect_scripts(skill_dir: Path) -> list[str]:
    return sorted(
        p.relative_to(skill_dir).as_posix()
        for p in skill_dir.rglob("*")
        if p.is_file() and p.suffix.lower() in SCRIPT_SUFFIXES
    )


def source_hash(skill_mds: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in skill_mds:
        digest.update(hashlib.sha256(path.read_bytes()).hexdigest().encode("ascii"))
    return digest.hexdigest()


def probe_tool_catalog(previous: dict) -> tuple[list[str], str]:
    """从真实 MCP server 取 vivado 工具名。失败则沿用旧值（可能是空）。"""
    if not (MCP_PYTHON.is_file() and MCP_CTL.is_file()):
        warn("vivado-mcp 不可用（缺 venv/mcp_ctl.py），沿用旧 catalog")
        return list(previous.get("mcp_vivado") or []), str(previous.get("source") or "unavailable")
    env = dict(os.environ)
    env["PYTHONPATH"] = str(MCP_SITE)
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    try:
        proc = subprocess.run(
            [str(MCP_PYTHON), str(MCP_CTL), "list"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            cwd=str(MCP_CTL.parent),  # 纯 ASCII，遵守红线
            timeout=180,
        )
    except Exception as exc:
        warn(f"探测 MCP 工具清单失败（{exc}），沿用旧 catalog")
        return list(previous.get("mcp_vivado") or []), str(previous.get("source") or "unavailable")
    names = []
    for line in proc.stdout.splitlines():
        name = line.split("\t", 1)[0].strip()
        if re.fullmatch(r"[a-z][a-z0-9_]{2,}", name):
            names.append(name)
    names = sorted(set(names))
    if len(names) != EXPECTED_MCP_TOOLS:
        warn(f"MCP 工具数 {len(names)} != 预期 {EXPECTED_MCP_TOOLS}（rc={proc.returncode}）")
    if not names:
        warn("MCP 工具清单为空，沿用旧 catalog")
        return list(previous.get("mcp_vivado") or []), str(previous.get("source") or "unavailable")
    return names, f"{MCP_CTL} list"


def build_skill(skill_dir: Path, skills_root: Path) -> dict:
    text = (skill_dir / "SKILL.md").read_text(encoding="utf-8", errors="replace")
    meta = parse_frontmatter(text)
    body = split_body(text)
    inner = meta.get("metadata") if isinstance(meta.get("metadata"), dict) else {}
    baseline = meta.get("baseline")
    if not isinstance(baseline, dict):
        baseline = None
        warn(f"{skill_dir.name}: frontmatter 缺 baseline（校验会 FAIL，需补 SKILL.md）")
    desc = meta.get("description")
    if isinstance(desc, str):
        desc = " ".join(desc.split())
        if len(desc) > 200:
            desc = desc[:200] + "…"
    return {
        "name": skill_dir.name,
        "dir": skill_dir.name,
        "version": inner.get("version") if inner.get("version") is not None else meta.get("version"),
        "description": desc,
        "license": meta.get("license"),
        "references": collect_refs(body),
        "scripts": collect_scripts(skill_dir),
        "baseline": baseline,
        "_skills_root": str(skills_root),  # 内部用，落盘前剔除
    }


def main() -> int:
    try:  # 中文输出在 GBK 控制台可能炸，统一按 UTF-8 写
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    ap = argparse.ArgumentParser(description="生成技能清单 MANIFEST.json")
    ap.add_argument("--skills-root", default=str(DEFAULT_SKILLS_ROOT), help="技能根目录（含各技能子目录）")
    ap.add_argument("--out", default="", help="输出路径，默认 <skills-root>/MANIFEST.json")
    args = ap.parse_args()

    skills_root = Path(args.skills_root).expanduser().resolve()
    out_path = Path(args.out).expanduser().resolve() if args.out else skills_root / "MANIFEST.json"
    if not skills_root.is_dir():
        print(f"[ERROR] skills_root 不存在: {skills_root}", file=sys.stderr)
        return 1

    skill_dirs = sorted(p for p in skills_root.iterdir() if p.is_dir() and (p / "SKILL.md").is_file())
    if not skill_dirs:
        print(f"[ERROR] {skills_root} 下没有含 SKILL.md 的技能目录", file=sys.stderr)
        return 1

    previous: dict = {}
    if out_path.is_file():
        try:
            previous = json.loads(out_path.read_text(encoding="utf-8")).get("tool_catalog", {}) or {}
        except Exception as exc:
            warn(f"旧 MANIFEST 读取失败（按无旧值处理）: {exc}")

    print(f"技能根目录: {skills_root}")
    print(f"技能数: {len(skill_dirs)}")
    catalog, catalog_source = probe_tool_catalog(previous)
    skills = [build_skill(d, skills_root) for d in skill_dirs]
    for s in skills:
        s.pop("_skills_root", None)

    manifest = {
        "schema_version": 1,
        "generated_by": "scripts/gen_skills_manifest.py",
        "source_hash": source_hash([d / "SKILL.md" for d in skill_dirs]),
        "tool_catalog": {"source": catalog_source, "mcp_vivado": catalog},
        "skills": skills,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"工具目录: {len(catalog)} 个 mcp__vivado__* 工具（来源 {catalog_source}）")
    for s in skills:
        base = s["baseline"]
        verdict = "baseline 缺失" if base is None else f"amd_doc={base.get('amd_doc')} tested_on={base.get('tested_on')} status={base.get('status')}"
        print(f"  - {s['name']:<32} version={s['version']!s:<8} refs={len(s['references'])} scripts={len(s['scripts'])}  {verdict}")
    print(f"\n已写出: {out_path}")
    print(f"source_hash: {manifest['source_hash']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
