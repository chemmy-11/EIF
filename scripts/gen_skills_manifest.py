#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_skills_manifest.py — 生成技能清单 MANIFEST.json（禁手写）。

真源 = 每个技能 SKILL.md 的 frontmatter；本脚本只做「读 + 汇总 + 落盘」，
不参与任何判定。判定在 scripts/ci_check.py 的检查 7-10（本地专用）。

    py scripts/gen_skills_manifest.py                 # 默认 skills_root = 本机 vault 的 .dsh/skills
    py scripts/gen_skills_manifest.py --skills-root <dir> --out <file>
    py scripts/gen_skills_manifest.py --check         # 只校验，不写盘（见下）

`--check`（2026-10-24 增补，H1）：把同一份 `--out` 重新生成到临时文件，与盘上文件
**逐字节**比较：

  · 一致  → 打印 `[PASS]`，exit 0
  · 不一致 → 打印首个差异字节偏移 + 行级 unified diff（截断），exit 1
  · `--out` 不存在 → 直接 exit 1（先跑生成器）

为什么需要它：只有 source_hash 时，「只手改 MANIFEST 的 description / evidence /
tested_on / references（不碰 SKILL.md）」在 ci_check 里是全绿的 —— 哈希只证明 SKILL.md
没变，不证明 MANIFEST 没被改写。逐字节比较才把整份 MANIFEST 钉死在 SKILL.md 上。
`ci_check.py` 检查 7 直接调本模式的 --check，**不复制生成逻辑**（同检查 12 渲染器做法）。

契约见 `.vivado-scratch/vivado-norm-2026-10-24/SPEC.md` §3。要点：
  · source_hash = 各 SKILL.md 字节 sha256（按目录名排序）拼接后再 sha256。
  · baseline 唯一真源在 SKILL.md frontmatter；缺字段就写 null 并警告（校验会 FAIL，属预期）。
  · name 取 frontmatter 原值；与目录名不一致 ⇒ 结构性错误（exit 1），不再静默改用目录名（H2）。
  · tool_catalog 从真实 MCP server 探测（mcp_ctl.py list），探测失败则沿用旧 MANIFEST 的
    catalog 并警告 —— 这样「工具名检查」不需要每台机器都装 vivado-mcp。但**没有旧 catalog 可
    沿用**时绝不产出 `catalog=[]`：直接 exit 2（H4）。
  · 不写时间戳：避免每次生成都产生无意义 diff。

退出码：0 = 生成成功 / --check 一致（可有警告）；
        1 = 结构性错误（找不到 skills_root / 无 SKILL.md / name 与目录名不一致 / --check 不一致）；
        2 = MCP 工具探测失败且没有可沿用的旧 catalog（拒绝写/认空工具清单）。
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
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
                if not isinstance(out.get(cur_key), list):
                    # `key:` 无值时先被记成 {}，紧跟的 `- x` 才是它的列表项 ⇒ 升级成 list
                    out[cur_key] = []
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


def collect_artifacts(meta: dict) -> list[str]:
    """frontmatter ``artifacts:`` = 技能**运行时产出**的文件名（不随包发布，不要求存在）。

    设计意图（H3）：``references`` 由「正文里出现的文件名」启发式抽取（见 collect_refs
    的 REF_FILENAME 分支），会把技能自己**写出来**的产物（REPORT.md / report_data.json /
    build.tcl …）也当成随包文件收进去。显式声明 artifacts 后这些名字从 references 剔除，
    于是 references 可以要求「必须存在」，门禁才真正有牙。
    """
    raw = meta.get("artifacts")
    if not isinstance(raw, list):
        return []
    return sorted({str(x).strip().replace("\\", "/") for x in raw if str(x).strip()})


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


def probe_tool_catalog(previous: dict) -> tuple[list[str], str, bool]:
    """从真实 MCP server 取 vivado 工具名。

    返回 (工具名, 来源, 探测是否失败)。失败时沿用旧值（可能是空 list），由调用方决定
    「沿用旧值」还是「拒绝产出空 catalog」——见 H4 的 EmptyCatalogError。
    """
    if not (MCP_PYTHON.is_file() and MCP_CTL.is_file()):
        warn("vivado-mcp 不可用（缺 venv/mcp_ctl.py），沿用旧 catalog")
        return (
            list(previous.get("mcp_vivado") or []),
            str(previous.get("source") or "unavailable"),
            True,
        )
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
        return (
            list(previous.get("mcp_vivado") or []),
            str(previous.get("source") or "unavailable"),
            True,
        )
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
        return (
            list(previous.get("mcp_vivado") or []),
            str(previous.get("source") or "unavailable"),
            True,
        )
    return names, f"{MCP_CTL} list", False


def _skill_name(skill_dir: Path, meta: dict, errors: list[str]) -> str:
    """MANIFEST.name 必须**忠实记录** frontmatter 的 name（H2，2026-10-24 修）。

    旧实现硬写 `skill_dir.name`，于是 ci_check 检查 7 的 `name == dir` 判据对生成产物恒等
    ——「frontmatter name 与目录名不一致」这件事被生成器吞掉了，永远不会被报出来。
    现在：不一致 ⇒ 记入 errors（main 汇总后 exit 1，不写盘）；
    frontmatter 缺 name ⇒ 警告并退回目录名（保持旧行为，不擅自改变缺字段语义）。
    """
    raw = meta.get("name")
    fm = raw.strip() if isinstance(raw, str) else ""
    if not fm:
        warn(f"{skill_dir.name}: frontmatter 缺 name，按目录名记录")
        return skill_dir.name
    if fm != skill_dir.name:
        errors.append(
            f"{skill_dir.name}/SKILL.md: frontmatter name={fm!r} 与目录名 {skill_dir.name!r} 不一致"
            "（MANIFEST.name 记 frontmatter 原值；DSH 侧按 frontmatter name 加载，会与目录名不符）"
            " ⇒ 改 frontmatter `name` 或改目录名，二选一改一致后重跑生成器"
        )
    return fm


def build_skill(skill_dir: Path, skills_root: Path, errors: list[str]) -> dict:
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
    artifacts = collect_artifacts(meta)
    ref_names = collect_refs(body)
    if artifacts:
        _art = set(artifacts)
        ref_names = [r for r in ref_names if r not in _art]
    return {
        "name": _skill_name(skill_dir, meta, errors),
        "dir": skill_dir.name,
        "version": inner.get("version") if inner.get("version") is not None else meta.get("version"),
        "description": desc,
        "license": meta.get("license"),
        "references": ref_names,
        "artifacts": artifacts,
        "scripts": collect_scripts(skill_dir),
        "baseline": baseline,
        "_skills_root": str(skills_root),  # 内部用，落盘前剔除
    }


class _StructuralError(RuntimeError):
    """退出码 1：输入本身不成立（skills_root 缺失 / 无 SKILL.md）。"""


class _EmptyCatalogError(RuntimeError):
    """退出码 2：MCP 工具探测失败，且没有旧 catalog 可沿用（H4）。"""


def _read_previous_catalog(out_path: Path) -> dict:
    """读旧 MANIFEST 的 tool_catalog —— 探测失败时唯一的 catalog 来源（fallback）。"""
    if not out_path.is_file():
        return {}
    try:
        data = json.loads(out_path.read_text(encoding="utf-8"))
    except Exception as exc:
        warn(f"旧 MANIFEST 读取失败（按无旧值处理）: {exc}")
        return {}
    cat = data.get("tool_catalog") if isinstance(data, dict) else None
    return cat if isinstance(cat, dict) else {}


def render_manifest(skills_root: Path, out_path: Path) -> tuple[dict, list[str]]:
    """「读 SKILL.md → 组装 MANIFEST」的**唯一实现**，纯内存、不落盘。

    生成模式与 `--check` 模式都走这里：输入相同 ⇒ 字节必然相同，不存在
    「生成器写一套、校验器另算一套」的漂移。返回 (manifest, 结构性错误列表)。
    """
    if not skills_root.is_dir():
        raise _StructuralError(f"skills_root 不存在: {skills_root}")
    skill_dirs = sorted(
        p for p in skills_root.iterdir() if p.is_dir() and (p / "SKILL.md").is_file()
    )
    if not skill_dirs:
        raise _StructuralError(f"{skills_root} 下没有含 SKILL.md 的技能目录")

    previous = _read_previous_catalog(out_path)
    catalog, catalog_source, probe_failed = probe_tool_catalog(previous)
    if probe_failed and not catalog:
        # H4：绝不静默产出 catalog=[] —— 空 catalog 会让 ci_check 检查 10 静默失效，
        # 而源文件那一份「旧 MANIFEST」又不存在，等于把工具清单永久清零。
        raise _EmptyCatalogError(
            f"MCP 工具探测失败，且 {out_path} 不存在／没有可沿用的 tool_catalog ⇒ 拒绝产出空 catalog。\n"
            f"  排查：`{MCP_PYTHON} {MCP_CTL} list` 应列出 {EXPECTED_MCP_TOOLS} 个 mcp__vivado__* 工具。\n"
            "  若本机确实没有 vivado-mcp：保留一份已有的 MANIFEST.json 作为 fallback 基础"
            "（生成器会沿用它的 catalog），不要删掉后重跑。"
        )

    errors: list[str] = []
    skills = [build_skill(d, skills_root, errors) for d in skill_dirs]
    for s in skills:
        s.pop("_skills_root", None)

    manifest = {
        "schema_version": 1,
        "generated_by": "scripts/gen_skills_manifest.py",
        "source_hash": source_hash([d / "SKILL.md" for d in skill_dirs]),
        "tool_catalog": {"source": catalog_source, "mcp_vivado": catalog},
        "skills": skills,
    }
    return manifest, errors


def serialize_manifest(manifest: dict) -> str:
    """MANIFEST 的**唯一序列化实现**（生成与 --check 共用，禁两处各写一份）。"""
    return json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"


def write_manifest_text(path: Path, text: str) -> None:
    """**唯一落盘实现**。--check 把同一函数指到临时文件，才能逐字节比较。

    注意：`Path.write_text` 在 Windows 上按平台换行写出（\\n → \\r\\n）。正因如此，
    --check 必须走同一函数落到临时文件再比字节，不能拿内存字符串直接跟盘上字节比。
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


DIFF_MAX_LINES = 60


def first_byte_mismatch(expected: bytes, actual: bytes) -> str:
    limit = min(len(expected), len(actual))
    for i in range(limit):
        if expected[i] != actual[i]:
            return f"首个差异在字节偏移 {i}（期望 {expected[i]:#04x} / 实际 {actual[i]:#04x} 附近）"
    if len(expected) != len(actual):
        longer = "期望" if len(expected) > len(actual) else "实际"
        return (
            f"前 {limit} 字节相同但长度不同（期望 {len(expected)} / 实际 {len(actual)} 字节，"
            f"{longer}侧更长）"
        )
    return "字节完全一致"


def describe_difference(expected: bytes, actual: bytes) -> str:
    """--check 不一致时的诊断正文：首个字节偏移 + 行级 unified diff（前 DIFF_MAX_LINES 行）。"""
    exp = expected.decode("utf-8", errors="replace")
    act = actual.decode("utf-8", errors="replace")
    lines: list[str] = []
    diff = list(
        difflib.unified_diff(
            exp.splitlines(),
            act.splitlines(),
            fromfile="期望（由 SKILL.md 重新生成）",
            tofile="实际（盘上 --out 文件）",
            lineterm="",
            n=2,
        )
    )
    if diff:
        lines.extend(diff[:DIFF_MAX_LINES])
        if len(diff) > DIFF_MAX_LINES:
            lines.append(f"...（diff 共 {len(diff)} 行，此处只显示前 {DIFF_MAX_LINES} 行）")
    else:
        lines.append("行内容完全一致 —— 差异只在换行符/字节层面（CRLF↔LF、BOM 或编码）")
    # 换行归一后再比：区分「内容真的不同」与「只是行尾不同」，避免把后者误判成手改
    if expected.replace(b"\r\n", b"\n") == actual.replace(b"\r\n", b"\n"):
        lines.append("（归一 CRLF 后内容相等：不一致仅来自行尾/字节层，重跑生成器即可）")
    return "\n".join(lines)


def main() -> int:
    try:  # 中文输出在 GBK 控制台可能炸，统一按 UTF-8 写
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

    ap = argparse.ArgumentParser(description="生成技能清单 MANIFEST.json")
    ap.add_argument("--skills-root", default=str(DEFAULT_SKILLS_ROOT), help="技能根目录（含各技能子目录）")
    ap.add_argument("--out", default="", help="输出路径，默认 <skills-root>/MANIFEST.json")
    ap.add_argument(
        "--check",
        action="store_true",
        help="只校验：重新生成到临时文件后与 --out 逐字节比较（一致 exit 0 / 不一致 exit 1），不写任何真文件",
    )
    args = ap.parse_args()

    skills_root = Path(args.skills_root).expanduser().resolve()
    out_path = Path(args.out).expanduser().resolve() if args.out else skills_root / "MANIFEST.json"

    if args.check:
        print("[检查] 只读校验（--check）：重新生成到临时文件 → 与盘上文件逐字节比较，不写真文件")
    print(f"技能根目录: {skills_root}")

    if args.check and not out_path.is_file():
        print(
            f"[FAIL] --check 的目标不存在: {out_path}\n"
            "       先运行 `py scripts/gen_skills_manifest.py` 生成（MANIFEST 禁手写）",
            file=sys.stderr,
        )
        return 1

    try:
        manifest, errors = render_manifest(skills_root, out_path)
    except _StructuralError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1
    except _EmptyCatalogError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 2

    if errors:
        # H2 等结构性错误：**不写盘**，避免把不合规内容固化成「最新 MANIFEST」
        print(f"[ERROR] 生成中止（{len(errors)} 处结构性错误，未写盘）:", file=sys.stderr)
        for msg in errors:
            print(f"  - {msg}", file=sys.stderr)
        return 1

    text = serialize_manifest(manifest)
    skills = manifest["skills"]
    catalog = manifest["tool_catalog"]["mcp_vivado"]

    if not args.check:
        write_manifest_text(out_path, text)
        print(f"技能数: {len(skills)}")
        print(f"工具目录: {len(catalog)} 个 mcp__vivado__* 工具（来源 {manifest['tool_catalog']['source']}）")
        for s in skills:
            base = s["baseline"]
            verdict = "baseline 缺失" if base is None else f"amd_doc={base.get('amd_doc')} tested_on={base.get('tested_on')} status={base.get('status')}"
            print(f"  - {s['name']:<32} version={s['version']!s:<8} refs={len(s['references'])} scripts={len(s['scripts'])}  {verdict}")
        print(f"\n已写出: {out_path}")
        print(f"source_hash: {manifest['source_hash']}")
        return 0

    # ---- --check：落临时文件 → 逐字节比较 → 临时文件必删（真文件零写入）----
    fd, tmp_name = tempfile.mkstemp(prefix="skills-manifest-check-", suffix=".json")
    os.close(fd)
    tmp_path = Path(tmp_name)
    try:
        write_manifest_text(tmp_path, text)
        expected = tmp_path.read_bytes()
    finally:
        try:
            tmp_path.unlink()
        except OSError:
            pass
    actual = out_path.read_bytes()

    if expected == actual:
        print(f"[PASS] 与重新生成结果逐字节一致: {out_path}")
        print(
            f"       sha256={hashlib.sha256(actual).hexdigest()}  "
            f"字节数={len(actual)}  技能数={len(skills)}  工具数={len(catalog)}"
        )
        return 0

    try:
        sys.stdout.flush()  # 先落地 stdout，避免下面的 stderr 诊断与前置输出交错
    except Exception:
        pass
    print(f"[FAIL] 与重新生成结果不一致: {out_path}", file=sys.stderr)
    print(f"  {first_byte_mismatch(expected, actual)}", file=sys.stderr)
    print("  --- 差异（期望 = 由 SKILL.md 重新生成；实际 = 盘上文件）---", file=sys.stderr)
    for line in describe_difference(expected, actual).splitlines():
        print(f"  {line}", file=sys.stderr)
    print(
        "  ⇒ MANIFEST 禁手写（description/evidence/tested_on/references/tool_catalog 任一字段"
        "被手改都会暴露在此）。处置：重跑 `py scripts/gen_skills_manifest.py`",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
