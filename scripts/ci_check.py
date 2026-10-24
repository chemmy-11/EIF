#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ci_check.py — EIF 仓库体检（CI 与本地共用）。

检查项（全部不依赖 Vivado，可在任意机器运行）：
  1. 文档命名规范   docs/ 下 Markdown 文件名须合规范（见 docs/README.md）
  2. 相对链接可解析  所有 Markdown 里的相对链接与图片必须指向真实存在的文件
  3. Python 语法    仓库内全部 .py 可编译
  4. .ps1 编码      仓库内全部 .ps1 必须带 UTF-8 BOM（坑账本 #17/#18）
  5. Tcl 可解析     仓库内全部 .tcl 可被 tclsh 解析（无 tclsh 时跳过）
  6. 索引一致性     docs/README.md 索引须覆盖 docs/ 下全部 .md 且不列不存在的文件
                    （2026-10-17 增补；口径 = 除 docs/README.md 自身外全部 .md，含 agent.md）

本地专用检查（vault 不存在时 [跳过]，不影响远程 GitHub CI；用户裁决 D2）：
  7. 技能清单一致性    vault `.dsh/skills/MANIFEST.json` 与磁盘 7 个 SKILL.md 的
                       技能集合 / name==dir / version / baseline 四键一致；并且**逐字节**
                       校验：直接跑 `gen_skills_manifest.py --check`（重新生成后与盘上文件
                       比对，生成逻辑唯一实现不复制），任何字段被手改都在这里 FAIL（H1）。
  8. 技能 references   SKILL.md 里的 Markdown 链接与 references|scripts|examples 反引号
                       相对路径必须真实存在（占位符跳过）。
                       注：MANIFEST.skills[].references 的存在性**不另立一套检查** —— 手改它由
                       检查 7 的逐字节比对直接暴露；SKILL.md 侧的悬空引用由本检查负责。
                       （真做存在性校验会把基线判红：references 是「正文里出现的相对路径」的
                       启发式抽取，含 REPORT.md/report_data.json/build.tcl 这类**产物名**）
  9. 技能绝对路径      SKILL.md 里出现的 Windows 盘符路径必须真实存在
                       （允许侧文件 `.dsh/skills/.path-allowlist.json` 登记例外并写理由）
 10. 技能工具名        ① `mcp__vivado__<x>` 必须在 MANIFEST.tool_catalog.mcp_vivado 内；
                       ② 提及 AMD 官方工具原名（vivadoExecute/vivado_execute/vivado_start/
                       vivado_stop/vivado_list_sessions/vivado_status/vivado_log_messages）
                       的技能，须至少一行 `→` 映射到本机 MCP 工具名。
                       （`vivado_doc_search` 刻意豁免，理由见 AMD_ORIGINAL 处注释）
 11. 镜像门禁          docs/**/*.md 归一（去 UTF-8 BOM、两侧 15266→***、CRLF→LF）后
                       须与 vault 同相对路径字节相等；真漂移与 docs 独有文件须登记在
                       `scripts/mirror_allowlist.json`（每条带 kind/reason/since）。
                       用户裁决 D1：白名单外新增不一致 → FAIL。
 12. 技能区块门禁      vault `agent.md` 的 `BEGIN:skills` 区块（由
                       `scripts/render_agent_skills_block.py` 从 MANIFEST 渲染）与
                       `docs/agent.md` 脱敏镜像都必须与 MANIFEST 一致 —— 直接跑渲染器的
                       `--check`，rc≠0 即 FAIL（不复制渲染逻辑，避免两处实现漂移）。

用法：py scripts/ci_check.py    （在仓库根目录运行）
退出码：0 = 全过；1 = 有失败项
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VAULT = Path(r"C:\Users\15266\Desktop\毕设")
DOCS = ROOT / "docs"
FAILS: list[str] = []
SKIPS: list[str] = []
HINTS: list[str] = []


def tracked_files() -> list[Path]:
    """仓库已跟踪文件（CI 与本地一致；git 不可用时退回全盘扫描）。

    -c core.quotepath=false 必须带：默认 git 会把非 ASCII 文件名输出成八进制转义串
    （docs/\350\247\204...），Path 解析不到 ⇒ 全部中文名文件会被静默跳过检查（坑账本 #46）。
    """
    try:
        out = subprocess.run(
            ["git", "-c", "core.quotepath=false", "ls-files"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        return [ROOT / p for p in out.splitlines() if p.strip()]
    except Exception:
        return [p for p in ROOT.rglob("*") if p.is_file() and ".git" not in p.parts]


# ---------- 1. 文档命名规范 ----------
ALLOWED_HEAD = {
    "阶段一", "阶段二", "阶段二前置", "阶段三", "阶段四", "阶段五",
    "前置", "参考", "里程碑", "汇报", "规划", "追踪", "结论", "架构", "导览", "复现",
}
SEG_HEAD = re.compile(r"^阶段[一二三四五](前置)?(之[一二三四五六七八九十]+)?$")


def check_doc_names(files: list[Path]) -> None:
    bad = []
    for f in files:
        rel = f.relative_to(ROOT).as_posix()
        # 规范只约束仓库根的 docs/ 文档中心；工程内部 docs/（PROGRESS.md 等）不受约束
        if f.suffix != ".md" or not rel.startswith("docs/"):
            continue
        if f.name in ("README.md", "agent.md"):
            continue  # 目录级索引与会话入口豁免
        name = f.name
        head = name.split("_")[0]
        ok = (
            " " not in name
            and re.search(r"_\d{4}-\d{2}-\d{2}\.md$", name) is not None
            and (head in ALLOWED_HEAD or SEG_HEAD.match(head) is not None)
        )
        if not ok:
            bad.append(str(f.relative_to(ROOT)).replace("\\", "/"))
    if bad:
        FAILS.append("文档命名不合规范（须为 [阶段]_prj标识_概要_YYYY-MM-DD.md，禁空格）:\n    " + "\n    ".join(bad))


# ---------- 2. 相对链接可解析 ----------
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")


def check_links(files: list[Path]) -> None:
    bad = []
    for f in files:
        if f.suffix != ".md" or not f.exists():
            continue
        text = f.read_text(encoding="utf-8", errors="replace")
        for m in LINK.finditer(text):
            t = m.group(1).strip()
            if t.startswith(("http://", "https://", "mailto:", "#")):
                continue
            t = t.split("#", 1)[0]
            if not t:
                continue
            # 占位符示例（文档里演示写法用）不当作真链接
            if re.search(r"[<>*]|\.\.\.|xxx", t):
                continue
            target = (f.parent / t).resolve()
            if not target.exists():
                bad.append(f"{f.relative_to(ROOT).as_posix()}  ->  {m.group(1)}")
    if bad:
        FAILS.append("相对链接指向不存在的文件:\n    " + "\n    ".join(sorted(set(bad))))


# ---------- 3. Python 语法 ----------
def check_python(files: list[Path]) -> None:
    bad = []
    for f in files:
        if f.suffix != ".py" or not f.exists():
            continue
        try:
            compile(f.read_text(encoding="utf-8", errors="replace"), str(f), "exec")
        except SyntaxError as e:
            bad.append(f"{f.relative_to(ROOT).as_posix()}:{e.lineno}  {e.msg}")
    if bad:
        FAILS.append("Python 语法错误:\n    " + "\n    ".join(bad))


# ---------- 4. .ps1 必须带 UTF-8 BOM ----------
def check_ps1_bom(files: list[Path]) -> None:
    bad = []
    for f in files:
        if f.suffix != ".ps1" or not f.exists():
            continue
        raw = f.read_bytes()
        # 仅当脚本含非 ASCII 字符时 BOM 才是必需的：纯 ASCII 脚本 PS 5.1 按任何编码读都一样
        if any(b > 0x7F for b in raw) and raw[:3] != b"\xef\xbb\xbf":
            bad.append(f.relative_to(ROOT).as_posix())
    if bad:
        FAILS.append(
            "PowerShell 脚本缺少 UTF-8 BOM（PS 5.1 读无 BOM 中文脚本按 CP936 解码必报语法错）:\n    "
            + "\n    ".join(bad)
        )


# ---------- 5. Tcl 可解析 ----------
def check_tcl(files: list[Path]) -> None:
    try:
        subprocess.run(["tclsh", "<<exit>>"], capture_output=True, check=True, text=True)
    except Exception:
        SKIPS.append("tclsh 不可用，跳过 Tcl 语法检查")
        return
    bad = []
    for f in files:
        if f.suffix != ".tcl" or not f.exists():
            continue
        script = f'if {{![info complete [read [open {{{f.as_posix()}}} r]]]}} {{exit 1}}'
        r = subprocess.run(["tclsh"], input=script, capture_output=True, text=True)
        if r.returncode != 0:
            bad.append(f.relative_to(ROOT).as_posix())
    if bad:
        FAILS.append("Tcl 脚本不完整（引号/括号未闭合）:\n    " + "\n    ".join(bad))


# ---------- 6. docs/README.md 索引与磁盘一致性 ----------
def docs_index_targets() -> set[Path]:
    """索引口径：docs/ 下除「任意 README.md」外的全部 .md（含 agent.md）。"""
    if not DOCS.is_dir():
        return set()
    return {p for p in DOCS.rglob("*.md") if p.name != "README.md"}


def check_docs_index() -> None:
    idx = DOCS / "README.md"
    disk = docs_index_targets()
    if not idx.exists():
        if disk:
            FAILS.append("docs/README.md 不存在，索引检查无从进行")
        return
    text = idx.read_text(encoding="utf-8", errors="replace")
    linked: set[Path] = set()
    for m in LINK.finditer(text):
        t = m.group(1).strip()
        if t.startswith(("http://", "https://", "mailto:", "#")):
            continue
        t = t.split("#", 1)[0]
        if not t or re.search(r"[<>*]|\.\.\.|xxx", t):
            continue
        target = (idx.parent / t).resolve()
        # 只统计落在 docs/ 内的 .md 链接（指向仓库其它位置的链接由第 2 项负责）
        if target.suffix == ".md" and target.is_relative_to(DOCS.resolve()):
            linked.add(target)
    missing = sorted(str(p.relative_to(DOCS)).replace("\\", "/") for p in disk - linked)
    dangling = sorted(
        str(p).replace("\\", "/") for p in linked - disk if p != idx.resolve()
    )
    parts: list[str] = []
    if missing:
        parts.append("以下 docs/ 文件未收录进 docs/README.md 索引（口径：docs/ 下除任意 README.md 外的全部 .md）:\n    " + "\n    ".join(missing))
    if dangling:
        parts.append("docs/README.md 索引列出了不存在的文件:\n    " + "\n    ".join(dangling))
    if parts:
        FAILS.append("docs/README.md 索引与磁盘不一致:\n" + "\n".join(parts))


# ======================================================================
# 7~10 本地专用：vault 内 .dsh/skills 的技能校验（SPEC §4）
# ======================================================================
SKILLS_ROOT = VAULT / ".dsh" / "skills"
SKILL_MANIFEST = SKILLS_ROOT / "MANIFEST.json"
SKILL_PATH_ALLOWLIST = SKILLS_ROOT / ".path-allowlist.json"
# MANIFEST 的生成器（唯一实现）。检查 7 只调它的 --check，绝不复制生成/序列化逻辑（H1）。
GEN_SKILL_MANIFEST = ROOT / "scripts" / "gen_skills_manifest.py"

# 占位符 / 演示路径：不当作真实引用（与 gen_skills_manifest.py 同口径）
PLACEHOLDER = re.compile(r"path/to|\.\.\.|xxx|[<>*{}]")
BACKTICK = re.compile(r"`([^`\n]+)`")
SKILL_REF_PREFIXES = ("references/", "scripts/", "examples/")
# SPEC §4 检查 9 的盘符路径正则；`s://` 这类 URL 残片由 _abs_path_candidates 过滤掉
WINDOWS_ABS = re.compile(r"[A-Za-z]:[\\/][^\s`\"')\],，。；]*")
# 任何 scheme 的 URL（https://、file:// …）：先整段抹成等长空白，避免 `https://x` 里的
# `s://x` 被盘符正则吃成绝对路径（实测 amd-doc-search/SKILL.md 有 3 处这类假阳性）
URL_ANY = re.compile(r"[A-Za-z][A-Za-z0-9+.\-]*://[^\s]*")
MCP_MENTION = re.compile(r"mcp__vivado__([A-Za-z0-9_]+)")
# 「AMD 官方 MCP 工具原名」清单 —— 提到就必须给本机映射（检查 10-2）。
#
# **刻意不含 `vivado_doc_search`**（2026-10-24 用户裁决，理由写在此处防止后人误以为是凑绿）：
#   本机的文档检索引擎不是 MCP 工具 —— `amd-doc-search` 技能用自带的 `scripts/doc_search.py`；
#   另一个 server 的 `mcp__amd_doc_search__vivado_doc_search` 要重启 `dsh web` 才会出现。
#   也就是说 `mcp_vivado` 的 32 个工具里**根本不存在**与 `vivado_doc_search` 对应的名字，
#   硬要求「映射到 mcp_vivado 成员」等于要求技能写假话。
#   本判据的原意是「别让模型去调一个本机不存在的工具名」，不是「每个 AMD 名词都必须在
#   mcp_vivado 里有同义词」——`amd-doc-search` 已明确写「实际调用 doc_search.py」，
#   不会误导模型，故豁免。其余 7 个原名（同步/异步两套写法）保留严格映射要求。
AMD_ORIGINAL = re.compile(
    r"vivadoExecute|vivado_execute|vivado_start|vivado_stop"
    r"|vivado_list_sessions|vivado_status|vivado_log_messages"
)
BASELINE_KEYS = ("amd_doc", "tested_on", "status", "evidence")

_SKILL_DIRS: list[Path] | None = None


def _skills_ready() -> bool:
    """技能类检查为本地专用：vault 技能目录不存在/为空时统一 [跳过] 一次（D2）。"""
    global _SKILL_DIRS
    if _SKILL_DIRS is None:
        if SKILLS_ROOT.is_dir():
            _SKILL_DIRS = sorted(
                p for p in SKILLS_ROOT.iterdir() if p.is_dir() and (p / "SKILL.md").is_file()
            )
            if not _SKILL_DIRS:
                SKIPS.append(f"技能目录下没有含 SKILL.md 的技能（{SKILLS_ROOT.as_posix()}）：跳过检查 7-10")
        else:
            _SKILL_DIRS = []
            SKIPS.append(
                f"vault 技能目录不存在（{SKILLS_ROOT.as_posix()}）：跳过检查 7-10"
                "（本地专用；远程 CI 自动跳过，用户裁决 D2）"
            )
    return bool(_SKILL_DIRS)


def _read_text(p: Path) -> str:
    return p.read_bytes().decode("utf-8-sig", errors="replace")


def _line_of(text: str, pos: int) -> int:
    return text.count("\n", 0, pos) + 1


def _txt(val: object) -> str:
    return val.strip() if isinstance(val, str) else ""


def _generator_manifest_check() -> tuple[bool, str]:
    """跑生成器的 `--check`（MANIFEST 唯一生成实现），返回 (是否一致, 诊断文本)。

    这是「禁手写 MANIFEST」的**真正判据**：MANIFEST 必须与「由 SKILL.md 重新生成的字节」
    完全相同。旧实现只复算 source_hash —— 那只证明 SKILL.md 没变，手改 description /
    evidence / tested_on / references / tool_catalog 在任何检查里都不会红（H1 的洞）。
    生成/序列化逻辑只存在于 gen_skills_manifest.py 一处（同检查 12 用渲染器 --check 的做法）。
    """
    cmd = [sys.executable, str(GEN_SKILL_MANIFEST), "--check", "--skills-root", str(SKILLS_ROOT)]
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            timeout=600,  # 生成器内部探测 MCP 的 timeout 是 180s，留足余量
        )
    except Exception as exc:
        return False, f"执行 `{' '.join(cmd)}` 失败：{exc}"
    if proc.returncode == 0:
        return True, ""
    detail = "\n".join(
        x for x in ((proc.stdout or "").rstrip(), (proc.stderr or "").rstrip()) if x.strip()
    )
    return False, f"`{GEN_SKILL_MANIFEST.name} --check` rc={proc.returncode}\n" + (
        detail or "（生成器无输出）"
    )


def load_skill_manifest() -> dict:
    """读 MANIFEST.json；不存在/坏 JSON 返回 {}（由检查 7 报 FAIL）。"""
    if not SKILL_MANIFEST.is_file():
        return {}
    try:
        data = json.loads(SKILL_MANIFEST.read_text(encoding="utf-8"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _manifest_catalog() -> list[str]:
    cat = load_skill_manifest().get("tool_catalog")
    names = cat.get("mcp_vivado") if isinstance(cat, dict) else None
    return [str(x) for x in names] if isinstance(names, list) else []


# ---------- 7. 技能清单一致性 ----------
def check_skills_manifest() -> None:
    if not _skills_ready():
        return
    dirs = _SKILL_DIRS or []
    rel_man = SKILL_MANIFEST.as_posix()
    if not SKILL_MANIFEST.is_file():
        FAILS.append(
            f"技能清单 MANIFEST.json 不存在（{rel_man}）\n"
            "    请运行 `py scripts/gen_skills_manifest.py` 生成（MANIFEST 禁手写）"
        )
        return
    try:
        man = json.loads(SKILL_MANIFEST.read_text(encoding="utf-8"))
    except Exception as exc:
        FAILS.append(f"技能清单不是合法 JSON（{rel_man}）：{exc} ⇒ 重跑 `py scripts/gen_skills_manifest.py`（禁手写）")
        return
    if not isinstance(man, dict):
        FAILS.append(f"技能清单顶层不是 JSON 对象（{rel_man}）⇒ 重跑 `py scripts/gen_skills_manifest.py`（禁手写）")
        return

    problems: list[str] = []
    if man.get("schema_version") != 1:
        problems.append(f"schema_version={man.get('schema_version')!r}，应为 1")

    # H1：整份 MANIFEST 必须逐字节等于「由 SKILL.md 重新生成」的结果。
    # 这里只取生成器 --check 的退出码，不在本文件复算/复写生成逻辑（单一实现）。
    gen_ok, gen_detail = _generator_manifest_check()
    if not gen_ok:
        FAILS.append(
            f"MANIFEST 与「由 SKILL.md 重新生成」的结果不一致（{rel_man}）——MANIFEST 禁手写："
            "description / evidence / tested_on / references / tool_catalog 任一字段被手改都会在这里暴露。"
            "处置：跑 `py scripts/gen_skills_manifest.py` 重新生成。诊断:\n    "
            + gen_detail.replace("\n", "\n    ")
        )

    skills = man.get("skills")
    if not isinstance(skills, list):
        FAILS.append(f"技能清单缺 skills 数组（{rel_man}）⇒ 重跑生成器（禁手写）")
        return
    names_manifest = {str(s.get("name")) for s in skills if isinstance(s, dict)}
    names_disk = {d.name for d in dirs}
    only_m = sorted(names_manifest - names_disk)
    only_d = sorted(names_disk - names_manifest)
    if only_m or only_d:
        problems.append(
            "磁盘技能目录集合与 MANIFEST 不一致："
            f"仅在 MANIFEST 中 = {', '.join(only_m) or '无'}；仅在磁盘上 = {', '.join(only_d) or '无'}"
            " ⇒ 重跑生成器"
        )

    for i, s in enumerate(skills):
        if not isinstance(s, dict):
            problems.append(f"skills[{i}] 不是对象")
            continue
        name = str(s.get("name") or "")
        tag = name or f"skills[{i}]"
        if name != str(s.get("dir") or ""):
            problems.append(f"{tag}: name({name!r}) 与 dir({s.get('dir')!r}) 不一致")
        if not _txt(s.get("version")):
            problems.append(f"{tag}: version 为空/缺失（补 SKILL.md frontmatter `metadata.version`）")
        base = s.get("baseline")
        if not isinstance(base, dict):
            problems.append(
                f"{tag}: baseline 为 null ⇒ 在 SKILL.md frontmatter 补 baseline"
                "（amd_doc / tested_on / status / evidence 四键）"
            )
            continue
        miss = [k for k in BASELINE_KEYS if k not in base]
        if miss:
            problems.append(f"{tag}: baseline 缺键 {', '.join(miss)}")
        status = base.get("status")
        if status not in ("verified", "unverified"):
            problems.append(f"{tag}: baseline.status={status!r} 非法（须 verified | unverified）")
        elif status == "verified":
            empty = [k for k in ("tested_on", "evidence") if not _txt(base.get(k))]
            if empty:
                problems.append(
                    f"{tag}: status=verified 但 {', '.join(empty)} 为空"
                    "（裁决 D3：verified 必须写实测版本与证据出处，否则改 unverified + tested_on=null）"
                )

    if problems:
        FAILS.append(
            f"技能清单一致性（{rel_man}）:\n    " + "\n    ".join(problems)
        )


# ---------- 8. 技能 references 真实存在 ----------
SKILL_REF_FILENAME = re.compile(r"^[\w][\w.\-]*\.(md|py|tcl|ps1|json|v|sv|rpt)$")


def _skill_body_start(text: str) -> int:
    """frontmatter 之后的正文起点（与生成器 split_body 同口径，避免误扫前言里的反引号）。"""
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end >= 0:
            return end + 4
    return 0


def _skill_artifacts(md: Path) -> set[str]:
    """SKILL.md 前言 ``artifacts:`` = 运行时产物名（技能自己写出来的，不随包发布）。

    H3：显式声明后这些名字从「引用必须存在」里豁免；**未声明**的裸文件名不再放行。
    之前 check 8 只查 markdown 链接与 references/|scripts/|examples/ 前缀，裸文件名
    （REPORT.md / build.tcl …）从不校验 ⇒ MANIFEST.references 里可以有悬空名字。
    """
    text = _read_text(md)
    start = _skill_body_start(text)
    if start == 0:
        return set()
    out: set[str] = set()
    in_key = False
    for line in text[3:start].splitlines():
        s = line.strip()
        if not in_key:
            if s.startswith("artifacts:"):
                rest = s.split(":", 1)[1].strip()
                if rest.startswith("[") and rest.endswith("]"):
                    out |= {x.strip().strip("\"'") for x in rest[1:-1].split(",") if x.strip()}
                in_key = True
            continue
        if s.startswith("- "):
            out.add(s[2:].strip().strip("\"'"))
        elif line and not line.startswith((" ", "\t")):
            in_key = False  # 回到顶层 key，artifacts 区块结束
    return {x.replace("\\", "/") for x in out if x}


def check_skills_references() -> None:
    if not _skills_ready():
        return
    bad: list[str] = []
    for d in _SKILL_DIRS or []:
        md = d / "SKILL.md"
        text = _read_text(md)
        body_start = _skill_body_start(text)
        arts = _skill_artifacts(md)
        picked: list[tuple[int, str, str]] = []
        for m in LINK.finditer(text):
            picked.append((m.start(), "链接", m.group(1)))
        for m in BACKTICK.finditer(text):
            cand = m.group(1).strip()
            if cand.startswith(SKILL_REF_PREFIXES):
                picked.append((m.start(), "代码内路径", cand))
            elif m.start() >= body_start and SKILL_REF_FILENAME.match(cand):
                # 裸文件名：正文提到就要求随包存在，除非在 artifacts: 里声明为运行时产物
                picked.append((m.start(), "产物名/文件名", cand))
        for pos, kind, raw in picked:
            t = raw.strip()
            if not t or t.startswith(("http://", "https://", "mailto:", "#")):
                continue
            # markdown 链接可能带 title：[x](path "标题")
            if re.search(r"\s[\"']", t):
                t = t.split("\"", 1)[0].split("'", 1)[0].strip()
            t = t.split("#", 1)[0].strip()
            if not t or PLACEHOLDER.search(t):
                continue
            norm = t.replace("\\", "/")
            if norm in arts or Path(norm).name in arts:
                continue  # 已声明为运行时产物
            if re.match(r"^[A-Za-z]:[\\/]", t):
                target = Path(t)
            else:
                target = md.parent / t
            try:
                exists = target.exists()
            except OSError:
                exists = False
            if not exists:
                bad.append(f"{d.name}/SKILL.md:{_line_of(text, pos)}  [{kind}] {raw.strip()}")
    if bad:
        FAILS.append(
            "技能 SKILL.md 里的引用指向不存在的文件（解析基准 = 该 SKILL.md 所在目录；"
            "占位符 path/to|...|xxx|<>*{} 已跳过；**运行时产物必须在前言 `artifacts:` 里声明**）:\n    "
            + "\n    ".join(bad)
        )


# ---------- 9. 技能内绝对路径存在 ----------
_TRAILING_PUNCT = ".,;:!?。，；：、"


def _abs_path_candidates(text: str):
    """产出 (match_start, 原始串)：先抹掉 URL，再过滤 URL 残片（https:// 里的 `s://`）。"""
    # 抹成等长空白 ⇒ 后续 match.start() 与原文偏移一致，行号仍然准确
    scan = URL_ANY.sub(lambda m: " " * len(m.group(0)), text)
    for m in WINDOWS_ABS.finditer(scan):
        raw = m.group(0)
        if "://" in raw:
            continue
        # 只有「独立出现」的盘符路径才算：排除前面紧贴字母数字的情况（xxxC:\ 之类）
        if m.start() > 0 and (scan[m.start() - 1].isalnum() or scan[m.start() - 1] in "+._-/"):
            continue
        yield m.start(), raw


def _strip_path(raw: str) -> str:
    s = raw.rstrip(_TRAILING_PUNCT).rstrip()
    s = s.rstrip(")]}\"'")
    return s


def _path_exists_variants(raw: str) -> tuple[str, bool]:
    """去掉尾部标点/引号/尾部分隔符后再判存在；返回 (报告用的最干净形式, 是否存在)。"""
    cand = _strip_path(raw)
    variants = [cand, cand.rstrip("\\/")]
    for v in variants:
        if not v:
            continue
        try:
            if Path(v).exists():
                return v, True
        except (OSError, ValueError):
            pass
    return variants[0] if variants else cand, False


def _load_skill_path_allowlist() -> tuple[dict[str, str], list[str]]:
    """可选侧文件 <skills_root>\\.path-allowlist.json：{"<绝对路径>": "<理由>"}。"""
    if not SKILL_PATH_ALLOWLIST.is_file():
        return {}, []
    try:
        data = json.loads(SKILL_PATH_ALLOWLIST.read_text(encoding="utf-8"))
    except Exception as exc:
        return {}, [f".path-allowlist.json 不是合法 JSON：{exc}"]
    if not isinstance(data, dict):
        return {}, [".path-allowlist.json 顶层必须是 {路径: 理由} 对象"]
    out: dict[str, str] = {}
    problems: list[str] = []
    for key, val in data.items():
        norm_key = str(key).replace("\\", "/")
        if not _txt(val if isinstance(val, str) else None) and not (isinstance(val, str) and val.strip()):
            problems.append(f".path-allowlist.json 条目 {key!r} 的 reason 为空（必须写可复核理由）")
        out[norm_key] = str(val)
    return out, problems


def check_skills_paths() -> None:
    if not _skills_ready():
        return
    allow, problems = _load_skill_path_allowlist()
    bad: list[str] = list(problems)
    for d in _SKILL_DIRS or []:
        md = d / "SKILL.md"
        text = _read_text(md)
        for pos, raw in _abs_path_candidates(text):
            if PLACEHOLDER.search(raw):
                continue
            clean, ok = _path_exists_variants(raw)
            if ok:
                continue
            key = clean.replace("\\", "/")
            if key in allow or raw.replace("\\", "/") in allow:
                continue
            bad.append(f"{d.name}/SKILL.md:{_line_of(text, pos)}  {clean}")
    if bad:
        FAILS.append(
            "技能 SKILL.md 里的 Windows 绝对路径不存在（只查 SKILL.md，技能内其它 .md 是 AMD 原文不查）。"
            "处置：① 改成本机真实路径；② 若确属示例 → 改写成占位符；"
            "③ 若确需保留 → 登记 <skills_root>\\.path-allowlist.json 并写理由:\n    "
            + "\n    ".join(bad)
        )


# ---------- 10. 技能工具名可解析 ----------
def _mentions_token(line: str, token: str) -> bool:
    return re.search(r"(?<![A-Za-z0-9])" + re.escape(token) + r"(?![A-Za-z0-9])", line) is not None


def check_skills_tools() -> None:
    if not _skills_ready():
        return
    catalog = _manifest_catalog()
    cset = set(catalog)
    if not catalog:
        HINTS.append(
            "MANIFEST.tool_catalog.mcp_vivado 为空/不可读：检查 10 的工具名解析无从进行"
            "（先跑 `py scripts/gen_skills_manifest.py`）"
        )
    bad: list[str] = []
    for d in _SKILL_DIRS or []:
        md = d / "SKILL.md"
        text = _read_text(md)
        # 10-1：mcp__vivado__<x> 必须在 catalog 内
        for m in MCP_MENTION.finditer(text):
            name = m.group(1)
            if name not in cset:
                bad.append(
                    f"{d.name}/SKILL.md:{_line_of(text, m.start())}  "
                    f"mcp__vivado__{name} 不在 MANIFEST.tool_catalog.mcp_vivado（{len(catalog)} 项）"
                )
        # 10-2：提到 AMD 原名 ⇒ 须有 `→` 映射到本机 MCP 工具名
        #   判定口径 = 「同一行里既有 AMD 原名、又在 `→` 右侧给出本机 MCP 工具名」。
        #   要求同行是刻意的（比 SPEC 原文「至少含一行 `→`」更严一点）：否则任何带 → 的行
        #   只要右侧偶然出现一个 catalog 词（如「工具链不同 … start_session …」说明行）就会
        #   白送通过 —— 2026-10-24 反例验证实测到过这种假通过。
        mentions = sorted(set(AMD_ORIGINAL.findall(text)))
        if not mentions:
            continue
        first = min(m.start() for m in AMD_ORIGINAL.finditer(text))
        mapped = False
        for line in text.splitlines():
            if "→" not in line or AMD_ORIGINAL.search(line) is None:
                continue
            for chunk in line.split("→")[1:]:
                if any(_mentions_token(chunk, name) for name in catalog):
                    mapped = True
                    break
            if mapped:
                break
        if not mapped:
            bad.append(
                f"{d.name}/SKILL.md:{_line_of(text, first)}  提到 AMD 原名 "
                f"{'/'.join(mentions)}，但没有一行**同时**含 AMD 原名与 `→` 右侧的本机 MCP 工具名"
                f"（本机名 = MANIFEST.tool_catalog.mcp_vivado 成员，共 {len(catalog)} 项）"
                " ⇒ 补一行映射，例如 `vivadoExecute → run_tcl`"
            )
    if bad:
        FAILS.append(
            "技能 SKILL.md 的工具名不可解析（本地 MCP 工具清单 = MANIFEST.tool_catalog.mcp_vivado）:\n    "
            + "\n    ".join(bad)
        )


# ======================================================================
# 11. 镜像门禁：docs/ 快照 vs vault（用户裁决 D1 = 脱敏归一 + 带理由白名单）
# ======================================================================
MIRROR_ALLOWLIST = ROOT / "scripts" / "mirror_allowlist.json"
# 脱敏归一：用户名/人名 → docs 里的 ***。
# 注意：**两侧都替换**（SPEC §4.11 原文只写「vault 侧」）。实测理由——docs 里另有 5 篇本身
# 就含 `15266`（未脱敏的路径/命令片段），其中 4 篇与 vault 逐字节完全相同；若只替换 vault 侧，
# 这 4 篇会被误判成 drift（2026-10-24 实测：复现_prj9_指南、阶段三_cross_上板操作优先级清单、
# 阶段三_prj10_W4两级内存联调上板验证单、阶段三_prj11_B2软核J3上板验证单）。对称替换后
# 「原始就相同」的文件仍相同，11 篇纯脱敏差异仍归一到相等。
DESENSITIZE = (("15266", "***"),)
MIRROR_KINDS = ("drift", "docs-only")


def mirror_normalize(text: str) -> str:
    """SPEC §4 检查 11 的归一：① 去 UTF-8 BOM；② 统一 CRLF→LF。"""
    if text.startswith("\ufeff"):
        text = text[1:]
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _mirror_decode(p: Path) -> str:
    return p.read_bytes().decode("utf-8", errors="replace")


def mirror_canonical(p: Path) -> str:
    """归一后的比较用文本：BOM/换行归一 + 脱敏替换（两侧同一规则）。"""
    text = mirror_normalize(_mirror_decode(p))
    for old, new in DESENSITIZE:
        text = text.replace(old, new)
    return text


def _load_mirror_allowlist() -> tuple[dict[str, dict], list[str]]:
    """读白名单并自检结构；返回 (path→entry, 自身问题)。reason 空 ⇒ 自身 FAIL。"""
    if not MIRROR_ALLOWLIST.is_file():
        return {}, []
    try:
        data = json.loads(MIRROR_ALLOWLIST.read_text(encoding="utf-8"))
    except Exception as exc:
        return {}, [f"不是合法 JSON：{exc}"]
    if not isinstance(data, dict):
        return {}, ["顶层必须是 JSON 对象 {generated_at, entries[]}"]
    entries = data.get("entries", [])
    if not isinstance(entries, list):
        return {}, ["entries 必须是数组"]
    out: dict[str, dict] = {}
    problems: list[str] = []
    for i, e in enumerate(entries):
        if not isinstance(e, dict):
            problems.append(f"entries[{i}] 不是对象")
            continue
        path = str(e.get("path") or "").strip().replace("\\", "/")
        if not path:
            problems.append(f"entries[{i}] 缺 path")
            continue
        if path in out:
            problems.append(f"{path}: 重复登记")
        kind = e.get("kind")
        if kind not in MIRROR_KINDS:
            problems.append(f"{path}: kind={kind!r} 非法（须 {' | '.join(MIRROR_KINDS)}）")
        if not _txt(e.get("reason")):
            problems.append(f"{path}: reason 为空（每条白名单必须写可复核的具体理由）")
        if not _txt(e.get("since")):
            problems.append(f"{path}: since 为空（每条白名单必须写日期）")
        out[path] = e
    return out, problems


def check_mirror_gate() -> None:
    """docs → vault 单方向门禁。

    方向性（SPEC §4.11）：只查 docs 里有、按相对路径去 vault 找；vault 侧新增但还没镜像的
    文档不算失败（现状已分叉，且本轮会新增文档）。
    """
    if not VAULT.is_dir():
        SKIPS.append(
            f"vault 不存在（{VAULT.as_posix()}）：跳过镜像门禁（本地专用；远程 CI 自动跳过）"
        )
        return
    if not DOCS.is_dir():
        FAILS.append("docs/ 目录不存在，镜像门禁无从进行")
        return

    allow, problems = _load_mirror_allowlist()
    if problems:
        FAILS.append(
            f"镜像白名单自身不合法（{MIRROR_ALLOWLIST.as_posix()}）:\n    " + "\n    ".join(problems)
        )

    unresolved: list[str] = []
    kind_bad: list[str] = []
    used: set[str] = set()
    same = whitelisted = 0
    docs_files = sorted(DOCS.rglob("*.md"))

    for p in docs_files:
        rel = p.relative_to(DOCS).as_posix()
        entry = allow.get(rel)
        v = VAULT / p.relative_to(DOCS)
        if not v.is_file():
            if entry is None:
                unresolved.append(f"{rel}   [kind=docs-only：vault 无此相对路径，未登记]")
            else:
                used.add(rel)
                if entry.get("kind") != "docs-only":
                    kind_bad.append(
                        f"{rel}: 登记为 {entry.get('kind')!r}，但 vault 里没有该文件 ⇒ 应为 docs-only"
                    )
            continue
        if mirror_canonical(p) == mirror_canonical(v):
            same += 1
            continue
        if entry is None:
            unresolved.append(f"{rel}   [kind=drift：归一后仍与 vault 不一致，未登记]")
        else:
            used.add(rel)
            if entry.get("kind") != "drift":
                kind_bad.append(
                    f"{rel}: 登记为 {entry.get('kind')!r}，但两侧都存在且归一后不等 ⇒ 应为 drift"
                )

    whitelisted = len(used)
    # 白名单过期条目只提示（不 FAIL）：允许后续清理时不阻塞 CI
    stale: list[str] = []
    for rel in sorted(set(allow) - used):
        cand = DOCS / rel
        if not cand.is_file():
            stale.append(f"{rel}（docs/ 下已无此文件 ⇒ 可删除该条目）")
            continue
        v = VAULT / rel
        if v.is_file() and mirror_canonical(cand) == mirror_canonical(v):
            stale.append(f"{rel}（归一后已与 vault 相等 ⇒ 可删除该条目）")
    if stale:
        HINTS.append(
            f"镜像白名单有 {len(stale)} 条已无必要的条目（仅提示，可清理）:\n    " + "\n    ".join(stale)
        )

    if unresolved:
        FAILS.append(
            f"镜像门禁：docs/ 有 {len(unresolved)} 个文件与 vault 不一致（或 vault 无对应文件）且不在白名单。"
            f"白名单文件 = {MIRROR_ALLOWLIST.as_posix()}。处置："
            "① 内容该更新 → 重新脱敏后同步进 docs/；"
            "② docs 独有 / 既知真漂移 → 在白名单补一条 {path, kind: drift|docs-only, reason, since}，"
            "reason 必须写可复核的具体原因（禁「历史遗留」这类空话）:\n    "
            + "\n    ".join(unresolved)
        )
    if kind_bad:
        FAILS.append("镜像白名单 kind 与实际情况不符:\n    " + "\n    ".join(kind_bad))

    HINTS.append(
        f"镜像门禁：docs/ 共 {len(docs_files)} 篇 .md；归一后与 vault 相等 {same} 篇；"
        f"白名单豁免 {whitelisted} 篇（drift "
        f"{sum(1 for r in used if str(allow[r].get('kind')) == 'drift')}、docs-only "
        f"{sum(1 for r in used if str(allow[r].get('kind')) == 'docs-only')}）；"
        f"未登记不一致 {len(unresolved)} 篇"
    )


# ======================================================================
# 12. 技能区块门禁：agent.md 的 BEGIN:skills 区块必须与 MANIFEST 一致（本地专用）
# ======================================================================
RENDER_AGENT_BLOCK = ROOT / "scripts" / "render_agent_skills_block.py"
AGENT_MD = VAULT / "agent.md"


def check_agent_skills_block() -> None:
    """把渲染器当**唯一实现**，只读它的 `--check` 退出码 —— 不复制渲染逻辑，避免两处漂移。

    为什么需要这一条：agent.md 的技能表是 MANIFEST 的派生物，而它对外宣称「由脚本生成、
    勿手改」。检查 7 只保 MANIFEST 自身新鲜（source_hash 对 SKILL.md 字节），但「技能改了
    /MANIFEST 重跑了，agent.md 那块表格还是旧的」没人管 —— 区块会静静过期。这一条补上派生物。
    """
    if not AGENT_MD.is_file() or not SKILL_MANIFEST.is_file():
        missing = [p.as_posix() for p in (AGENT_MD, SKILL_MANIFEST) if not p.is_file()]
        SKIPS.append(
            "vault agent.md 或 MANIFEST 不存在，跳过技能区块门禁（检查 12）"
            f"（缺：{'、'.join(missing)}；本地专用，远程 CI 自动跳过）"
        )
        return
    if not RENDER_AGENT_BLOCK.is_file():
        FAILS.append(
            f"技能区块门禁（检查 12）缺渲染器：{RENDER_AGENT_BLOCK.as_posix()} 不存在"
        )
        return
    cmd = [sys.executable, str(RENDER_AGENT_BLOCK), "--check"]
    # 子进程必须显式 utf-8 io：渲染器输出中文，Windows 管道默认 cp936，父进程按 utf-8 解会花
    env = dict(os.environ)
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            timeout=120,
        )
    except Exception as exc:
        FAILS.append(
            f"技能区块门禁（检查 12）执行渲染器失败：{' '.join(cmd)}（{exc}）"
        )
        return
    if proc.returncode == 0:
        return
    detail = "\n".join(
        x for x in ((proc.stdout or "").rstrip(), (proc.stderr or "").rstrip()) if x.strip()
    )
    FAILS.append(
        "技能区块过期：vault agent.md 的 `BEGIN:skills` 区块 / docs/agent.md 脱敏镜像"
        f"与 MANIFEST 不一致（`{RENDER_AGENT_BLOCK.name} --check` rc={proc.returncode}）。"
        "处置：跑 `py D:\\FPGA\\scripts\\render_agent_skills_block.py --write` "
        "重新渲染并同步镜像。渲染器输出:\n    "
        + (detail.replace("\n", "\n    ") if detail else "（渲染器无输出）")
    )


def main() -> int:
    for stream in (sys.stdout, sys.stderr):  # 中文 + → 在 GBK 管道下会 UnicodeEncodeError
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    files = tracked_files()
    print(f"仓库体检：{len(files)} 个已跟踪文件\n")
    check_doc_names(files)
    check_links(files)
    check_python(files)
    check_ps1_bom(files)
    check_tcl(files)
    check_docs_index()
    # ---- 本地专用（vault 不存在时整段跳过）----
    check_skills_manifest()
    check_skills_references()
    check_skills_paths()
    check_skills_tools()
    check_mirror_gate()
    check_agent_skills_block()

    for h in HINTS:
        print(f"  [提示] {h}")
    for s in SKIPS:
        print(f"  [跳过] {s}")
    if FAILS:
        print(f"\n发现 {len(FAILS)} 类问题：")
        for i, msg in enumerate(FAILS, 1):
            print(f"\n[{i}] {msg}")
        print("\n=== CI: FAIL ===")
        return 1
    print("\n=== CI: PASS（全部检查通过）===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
