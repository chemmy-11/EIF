#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ci_check.py — FPGA_Project 仓库体检（CI 与本地共用）。

检查项（全部不依赖 Vivado，可在任意机器运行）：
  1. 文档命名规范   docs/ 下 Markdown 文件名须合规范（见 docs/README.md）
  2. 相对链接可解析  所有 Markdown 里的相对链接与图片必须指向真实存在的文件
  3. Python 语法    仓库内全部 .py 可编译
  4. .ps1 编码      仓库内全部 .ps1 必须带 UTF-8 BOM（坑账本 #17/#18）
  5. Tcl 可解析     仓库内全部 .tcl 可被 tclsh 解析（无 tclsh 时跳过）
  6. 索引一致性     docs/README.md 索引须覆盖 docs/ 下全部 .md 且不列不存在的文件
                    （2026-10-17 增补；口径 = 除 docs/README.md 自身外全部 .md，含 agent.md）

另有一条**本地专用提示**（不计入失败、不卡 CI）：检测到本机 vault
（C:/Users/15266/Desktop/毕设/）时比对 docs/ 快照与 vault 的字节一致性，
不一致仅打印 [提示]（镜像存在既知的归档/漂移，见 AGENTS.md §十二）。

用法：python scripts/ci_check.py    （在仓库根目录运行）
退出码：0 = 全过；1 = 有失败项
"""
from __future__ import annotations

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


# ---------- 本地提示：docs/ 快照与 vault 镜像一致性（不计失败） ----------
def check_mirror_hint() -> None:
    if not VAULT.is_dir():
        return  # 远程 CI / 异机环境：无 vault，自动跳过
    diff: list[str] = []
    for p in sorted(DOCS.rglob("*.md")):
        if p.name in ("README.md", "agent.md"):
            continue  # 协议/索引文件不参与镜像比对
        v = VAULT / p.relative_to(DOCS)
        if v.exists() and v.read_bytes() != p.read_bytes():
            diff.append(str(p.relative_to(DOCS)).replace("\\", "/"))
    if diff:
        HINTS.append(
            f"docs/ 快照与 vault 有 {len(diff)} 个文件字节不一致（仅提示，不卡 CI）。"
            "差异多为脱敏所致（vault 用户名/人名 → ***/前辈），属设计而非缺陷；"
            "禁止把 vault 原文直接覆盖进 docs/，确需同步须重新脱敏，详见 AGENTS.md 十二节:\n    "
            + "\n    ".join(diff[:20])
            + ("\n    ……" if len(diff) > 20 else "")
        )


def main() -> int:
    files = tracked_files()
    print(f"仓库体检：{len(files)} 个已跟踪文件\n")
    check_doc_names(files)
    check_links(files)
    check_python(files)
    check_ps1_bom(files)
    check_tcl(files)
    check_docs_index()
    check_mirror_hint()

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
