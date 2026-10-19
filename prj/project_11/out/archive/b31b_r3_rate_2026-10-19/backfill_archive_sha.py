# -*- coding: utf-8 -*-
"""backfill_archive_sha.py -- 为缺少 SHA256.txt 的旧归档轮次补生成清单（2026-10-19，R4-3）

只读归档文件、只新增 <dir>/SHA256.txt；不修改任何产物。
格式与 r2_archive_*.py 生成的清单一致（Markdown 表 + 说明脚注）。
用法: py scripts/backfill_archive_sha.py [--dry-run]
"""
import hashlib
import io
import os
import sys
import time

PRJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARC = os.path.join(PRJ, "out", "archive")
DRY = "--dry-run" in sys.argv


def sha256(p):
    h = hashlib.sha256()
    with io.open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest().upper()


def main():
    done = []
    for name in sorted(os.listdir(ARC)):
        d = os.path.join(ARC, name)
        if not os.path.isdir(d):
            continue
        sha_txt = os.path.join(d, "SHA256.txt")
        if os.path.isfile(sha_txt):
            continue
        rows = []
        for root, _dirs, fns in os.walk(d):
            for fn in fns:
                p = os.path.join(root, fn)
                rel = os.path.relpath(p, d).replace("\\", "/")
                if rel == "SHA256.txt":
                    continue
                rows.append((rel, sha256(p), os.path.getsize(p)))
        rows.sort(key=lambda x: x[0])
        lines = [
            "%s 归档清单（2026-10-19 补生成；该轮次构建时未出 SHA256.txt）" % name,
            "生成时间: " + time.strftime("%Y-%m-%d %H:%M:%S"),
            "说明: 仅补清单、未改动任何产物；烧写前仍以本表 SHA256 核对。",
            "",
            "| 文件 | 字节 | SHA256 |",
            "|---|---|---|",
        ]
        for rel, h, n in rows:
            lines.append("| %s | %d | %s |" % (rel, n, h))
        lines.append("")
        txt = "\n".join(lines) + "\n"
        if DRY:
            print("WOULD_WRITE", sha_txt, "rows=", len(rows))
        else:
            io.open(sha_txt, "w", encoding="utf-8", newline="\n").write(txt)
            print("WROTE", sha_txt, "rows=", len(rows))
        done.append(name)
    print("BACKFILL_DONE rounds=", len(done))
    return 0


if __name__ == "__main__":
    sys.exit(main())
