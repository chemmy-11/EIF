# =============================================================================
# make_fork_manifest.py — prj12: 生成 fork_manifest_12.json（逐文件 SHA256 对照 prj11）
# 目的: P0-01「project_12 可重建 + 改动可追溯」的证据件——任一文件都能回答
#   「它是 prj11 原样、还是被 prj12 改过」。只读 prj11，不改它。
# 用法: py scripts\make_fork_manifest.py
# =============================================================================
import hashlib
import json
import os
from datetime import datetime, timezone, timedelta

SRC = r"D:\FPGA\prj\project_11"
DST = r"D:\FPGA\prj\project_12"
OUT = os.path.join(DST, "fork_manifest_12.json")

# 与 prj11 逐字节对照的范围（源码树；不含 .Xil/.cache/runs/gen/out）
SCOPE = ["rtl", "xdc", "sim", "scripts", "sw", "docs"]


# 只对照源码/脚本文本；构建产物扩展名一律跳过（2026-10-24：pre_impl_debug.dcp 曾混进清单）
SKIP_EXT = {".dcp", ".ltx", ".log", ".jou", ".bit", ".wdb", ".pb", ".csv",
            ".xpr", ".xci", ".bin", ".elf", ".pcap", ".rpt", ".str"}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def rel_files(root, sub):
    base = os.path.join(root, sub)
    out = []
    for dirpath, _dirnames, filenames in os.walk(base):
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            ext = os.path.splitext(fn)[1].lower()
            # 只对照源码/脚本；构建产物（dcp/ltx/log/jou/wdb...）不进清单
            if ext in SKIP_EXT:
                continue
            if os.path.getsize(p) > (1 << 20):
                continue
            out.append(os.path.relpath(p, root).replace("\\", "/"))
    return out


def main():
    files = []
    identical = modified = dst_only = 0
    for sub in SCOPE:
        for rel in sorted(rel_files(DST, sub)):
            d = os.path.join(DST, rel.replace("/", os.sep))
            s = os.path.join(SRC, rel.replace("/", os.sep))
            entry = {"dst": rel, "src": "D:/FPGA/prj/project_11/" + rel}
            if os.path.exists(s):
                hd, hs = sha256(d), sha256(s)
                entry["sha256"] = hd
                entry["src_sha256"] = hs
                if hd == hs:
                    entry["status"] = "identical"
                    identical += 1
                else:
                    entry["status"] = "modified"
                    modified += 1
            else:
                entry["sha256"] = sha256(d)
                entry["status"] = "prj12_only"
                dst_only += 1
            files.append(entry)

    tz = timezone(timedelta(hours=8))
    doc = {
        "created": datetime.now(tz).strftime("%Y-%m-%dT%H:%M:%S+08:00"),
        "purpose": "prj12 fork of prj11 (双板 P1 离线就绪); prj11 只读",
        "source_root": "D:/FPGA/prj/project_11",
        "dest_root": "D:/FPGA/prj/project_12",
        "excluded": [".Xil", ".cache", ".tmpCRC", "vivado/*.runs", "vivado/*.gen",
                     "vivado/*.cache", "out", "xsim.dir", "*.dcp", "*.log", "*.jou"],
        "summary": {"files": len(files), "identical": identical,
                    "modified": modified, "prj12_only": dst_only},
        "files": files,
    }
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"FORK_MANIFEST: {OUT}")
    print(f"FORK_MANIFEST: files={len(files)} identical={identical} "
          f"modified={modified} prj12_only={dst_only}")
    for e in files:
        if e["status"] != "identical":
            print(f"  [{e['status']}] {e['dst']}")


if __name__ == "__main__":
    main()
