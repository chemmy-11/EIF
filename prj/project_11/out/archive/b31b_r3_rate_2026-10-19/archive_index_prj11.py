# -*- coding: utf-8 -*-
"""archive_index_prj11.py -- prj11 归档跨轮索引生成（R4-3）

扫描 prj/project_11/out/archive/*/：
  - 文件数/总大小
  - SHA256.txt 是否存在、表内文件是否齐全（缺失数）
  - 关键产物（.bit/.ltx/.xsa/.elf）与外层 hash8
输出 out/archive/ARCHIVE_INDEX_prj11.md，并给出「0 缺失」核对结论。

用法: py scripts/archive_index_prj11.py [--check]
"""
import hashlib
import io
import os
import re
import sys
import time

PRJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARC = os.path.join(PRJ, "out", "archive")
OUT = os.path.join(ARC, "ARCHIVE_INDEX_prj11.md")
KEY_EXT = (".bit", ".ltx", ".xsa", ".elf")


def sha8(p):
    h = hashlib.sha256()
    with io.open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()[:8].upper()


def parse_sha_list(path):
    """解析 SHA256.txt 的 | file | size | sha | 表；返回 [(name, sha)]"""
    rows = []
    try:
        txt = io.open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return rows
    for m in re.finditer(r"^\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|\s*([0-9A-Fa-f]{64})\s*\|", txt, re.M):
        rows.append((m.group(1).replace("\\", "/"), m.group(3).upper()))
    return rows


def scan_dir(d):
    files = []
    for root, _dirs, fns in os.walk(d):
        for fn in fns:
            p = os.path.join(root, fn)
            files.append((os.path.relpath(p, d).replace("\\", "/"), p))
    return files


def main():
    check = "--check" in sys.argv
    dirs = sorted([x for x in os.listdir(ARC) if os.path.isdir(os.path.join(ARC, x))])
    rows = []
    total_files = 0
    total_bytes = 0
    no_sha = []
    miss_total = 0
    for name in dirs:
        d = os.path.join(ARC, name)
        files = scan_dir(d)
        n = len(files)
        size = sum(os.path.getsize(p) for _, p in files)
        total_files += n
        total_bytes += size
        sha_txt = os.path.join(d, "SHA256.txt")
        has = os.path.isfile(sha_txt)
        listed = parse_sha_list(sha_txt) if has else []
        listed_names = set(x[0] for x in listed)
        present = set(x[0] for x in files if x[0] != "SHA256.txt")
        missing = sorted(listed_names - present)
        if not has:
            no_sha.append(name)
        miss_total += len(missing)
        key = []
        for rel, p in files:
            if rel.lower().endswith(KEY_EXT):
                key.append((rel, os.path.getsize(p)))
        # 主位流 hash8：优先离 *_r2*.bit / 名字带 hash 的 bit；否则取第一个 bit 现算
        bit_hash = ""
        bit_cands = [(rel, p) for rel, p in files if rel.lower().endswith(".bit")]
        bit_cands.sort(key=lambda x: (0 if re.search(r"[0-9A-F]{8}", x[0], re.I) else 1, -os.path.getsize(x[1])))
        if bit_cands:
            rel, p = bit_cands[0]
            m = re.search(r"([0-9A-Fa-f]{8})", os.path.basename(rel))
            bit_hash = m.group(1).upper() if m else sha8(p)
        rows.append({
            "name": name, "files": n, "bytes": size,
            "has_sha": has, "listed": len(listed), "missing": missing,
            "bit": bit_hash, "key": key,
        })

    md = []
    md.append("# prj11 归档跨轮总索引（自动生成，勿手改）")
    md.append("")
    md.append("> 生成器 `scripts/archive_index_prj11.py` · 目录 `prj/project_11/out/archive/` · 生成时间：%s" % time.strftime("%Y-%m-%d %H:%M:%S"))
    md.append("")
    md.append("## 一、总览与「0 缺失」核对")
    md.append("")
    md.append("| 指标 | 值 |")
    md.append("|---|---|")
    md.append("| 归档轮次数 | **%d** |" % len(dirs))
    md.append("| 文件总数 | %d |" % total_files)
    md.append("| 总大小 | %.1f MiB |" % (total_bytes / 1048576.0))
    md.append("| 有 SHA256.txt 的轮次 | %d / %d |" % (len(dirs) - len(no_sha), len(dirs)))
    md.append("| SHA256.txt 列名缺失数 | **%d** |" % miss_total)
    md.append("| 缺 SHA256.txt 的轮次 | %s |" % (("、".join("`%s`" % x for x in no_sha)) if no_sha else "0（全部有）"))
    md.append("")
    md.append("**结论：%s**" % ("归档索引 0 缺失（每个轮次均有 SHA256.txt，且表内文件全部存在）。"
                             if (miss_total == 0 and not no_sha) else
                             "存在缺口：%d 个轮次缺 SHA256.txt，%d 个表内文件缺失（见 §三）。" % (len(no_sha), miss_total)))
    md.append("")
    md.append("## 二、逐轮明细")
    md.append("")
    md.append("| 归档轮次 | 文件数 | 大小(MiB) | SHA256.txt | 表项/缺失 | 主位流 hash8 | 关键产物 |")
    md.append("|---|---|---|---|---|---|---|")
    for r in rows:
        keytxt = "、".join("%s(%.1fMB)" % (rel.split("/")[-1], sz / 1048576.0)
                          for rel, sz in r["key"] if rel.lower().endswith((".bit", ".ltx", ".xsa")))
        if len(keytxt) > 150:
            keytxt = keytxt[:147] + "…"
        md.append("| `%s` | %d | %.1f | %s | %d/%d | %s | %s |" % (
            r["name"], r["files"], r["bytes"] / 1048576.0,
            "✓" if r["has_sha"] else "**✗**", r["listed"], len(r["missing"]),
            ("`%s`" % r["bit"]) if r["bit"] else "—", keytxt or "—"))
    md.append("")
    md.append("## 三、缺口明细")
    md.append("")
    gaps = [r for r in rows if (not r["has_sha"]) or r["missing"]]
    if not gaps:
        md.append("（无）")
    else:
        for r in gaps:
            if not r["has_sha"]:
                md.append("- `%s`：**缺 SHA256.txt**（该轮构建早于归档规范或仅作临时目录）" % r["name"])
            for m in r["missing"][:20]:
                md.append("- `%s`：表内文件缺失 `%s`" % (r["name"], m))
    md.append("")
    md.append("## 四、说明")
    md.append("")
    md.append("- 「主位流 hash8」优先取文件名内嵌 hash；无名 hash 时现算前 8 位（会标注为现算值，大小写大写）。")
    md.append("- 表内「表项/缺失」= SHA256.txt 行数 / 其中磁盘上不存在的文件数；**只核对存在性**，逐字节 hash 复核见各轮 SHA256.txt 与烧写前 Get-FileHash 纪律。")
    md.append("- 烧写一律用归档绝对路径，先核对 SHA256.txt（AGENTS §六）。")
    md.append("")
    txt = "\n".join(md) + "\n"
    if check:
        print("ARCHIVE_INDEX_CHECK: rounds=%d files=%d no_sha=%d listed_missing=%d"
              % (len(dirs), total_files, len(no_sha), miss_total))
        return 0 if (miss_total == 0 and not no_sha) else 2
    os.makedirs(ARC, exist_ok=True)
    io.open(OUT, "w", encoding="utf-8", newline="\n").write(txt)
    print("ARCHIVE_INDEX_OK:", OUT)
    print("  rounds=%d files=%d no_sha=%d listed_missing=%d"
          % (len(dirs), total_files, len(no_sha), miss_total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
