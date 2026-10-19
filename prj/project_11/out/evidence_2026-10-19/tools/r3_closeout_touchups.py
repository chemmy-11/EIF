# -*- coding: utf-8 -*-
"""收尾杂项：①用最新 ARCHIVE_INDEX 覆盖 R3 归档内副本并更新其 SHA 行
②EVIDENCE_INDEX 追加 §13 R3/R4 证据
③docs/README 记录/清单行描述更新到收口版
"""
import hashlib
import io
import os

P = r"D:\FPGA\prj\project_11"
OUT = os.path.join(P, "out")
EV = os.path.join(OUT, "evidence_2026-10-19")
ARC = os.path.join(OUT, "archive", "b31b_r3_rate_2026-10-19")
ARCIDX = os.path.join(OUT, "archive", "ARCHIVE_INDEX_prj11.md")
DREADME = r"D:\FPGA\docs\README.md"


def read(p):
    return io.open(p, "r", encoding="utf-8", newline="").read()


def write(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


def sha(p):
    h = hashlib.sha256()
    with io.open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest().upper()


# ① R3 归档内 ARCHIVE_INDEX 副本更新 + SHA256.txt 行更新
if os.path.isfile(ARCIDX):
    dst = os.path.join(ARC, "ARCHIVE_INDEX_prj11.md")
    s = read(ARCIDX)
    write(dst, s)
    h = sha(dst)
    n = os.path.getsize(dst)
    sha_txt = os.path.join(ARC, "SHA256.txt")
    lines = read(sha_txt).splitlines()
    out = []
    for ln in lines:
        if ln.startswith("| ARCHIVE_INDEX_prj11.md |"):
            out.append("| ARCHIVE_INDEX_prj11.md | %d | %s |" % (n, h))
        else:
            out.append(ln)
    write(sha_txt, "\n".join(out) + "\n")
    print("ARCHIVE_INDEX copy refreshed in R3 archive:", n, h[:16])

# ② EVIDENCE_INDEX 追加 §13
EI = os.path.join(EV, "EVIDENCE_INDEX_r3c.md")
if os.path.isfile(EI):
    s = read(EI)
    if "## 13. R3 速率量化 + R4 收尾证据" not in s:
        sec = r'''
## 13. R3 速率量化 + R4 收尾证据（2026-10-19 收尾轮）

| 文件 | 内容 | 来源 |
|---|---|---|
| `R3_RATE_RESULTS.md` | R3 汇总：档位矩阵/膝点/三版固件 A/B/与路线 A 对照/D2 判定 | `tools/r3_analyze.py` 生成 |
| `R3_thru_tiers.json/.log`、`R3_thru_knee.json/.log`、`R3_thru_perf2.json/.log`、`R3_thru_perf3.json/.log` | perf1 矩阵+膝点、perf2/perf3 A/B 原始测量 | `tools/r3_thru.py`（board COM5 + json_storm） |
| `R3_thru_console.log`、`R3_thru_knee_console.log`、`R3_thru_perf2_console.log`、`R3_thru_perf3_console.log` | 各轮控制台逐档摘要（recv/lost/dwr/drd/evt/帧） | 同上 |
| `R3_tier_pace*_us.log` | 单档 storm 原始输出（同名档后跑覆盖，主结论以 console/json 为准） | json_storm |
| `R3_final_fourtier.log`、`R2_mb10_20261019_172807.log`、`R3_final_burn_official.log` | R3 实验后恢复官方对（round3d+perf1）并复验：四档 PASS、10MB+SHA PASS | udp_verify_ddr / r2_mb10_sha / xsct |
| `tools/r3_thru.py`、`tools/r3_analyze.py`、`tools/r3_patch_perf2.py`、`tools/r3_patch_perf3.py` | 测量/分析/固件实验脚本（perf2 `ED908502` / perf3 `47B9EB18`，均未采纳） | 本轮新增 |
| `out/W6_prj11_可观测性清单.md` | R4-2：探针/计数清单（ILA0 110b/ILA3 152b/ILA5 47b=309b；118 声明；86 未挂） | `scripts/w6_inventory_prj11.py` |
| `out/archive/ARCHIVE_INDEX_prj11.md` | R4-3：跨轮归档索引 **33 轮/627 文件/0 缺失**（13 旧轮补 SHA256） | `scripts/archive_index_prj11.py` |
| `复现/复现_prj11_指南_2026-10-19.md` | R4-1：复现指南 B 章（12 节） | vault `复现/` + docs 镜像 |
| `out/archive/b31b_r3_rate_2026-10-19/` | 本轮证据归档（43 项 + SHA256.txt + README） | 本轮 |
'''
        s = s.rstrip("\n") + "\n" + sec
        write(EI, s)
        print("EVIDENCE_INDEX §13 appended, size=", os.path.getsize(EI))
    else:
        print("EVIDENCE_INDEX already has §13")

# ③ docs/README 记录/清单行更新
dr = read(DREADME)
pairs = [
    ("**10-19 收口**：楔死根因=module-ref IP cache 陈旧（坑 #68）、50% 隔帧丢根因=固件 MM2S 复位连带 S2MM（PG021 直证，固件 `s2mm_rearm` 修复）；round3d 位流 `F6012BA0`（WNS +0.002/WHS +0.004）+ **S0–S11 13/13 PASS**（S7 四档 · S8 10MB+SHA · S9 J3 四链 · S10 双桥对账），详见记录 §十八–§二十",
     "**10-19 收口**：楔死根因=module-ref IP cache 陈旧（坑 #68）、50% 隔帧丢根因=固件 MM2S 复位连带 S2MM（PG021 直证，固件 `s2mm_rearm` 修复）；round3d 位流 `F6012BA0`（WNS +0.002/WHS +0.004）+ **S0–S11 13/13 PASS**；**R3 速率≈2000fps 零丢/临界≈2500fps/上限≈2560fps**；**R4 文档收口完成**；路线 B 全量收口，详见记录 §十八–§二十二"),
]
for old, new in pairs:
    if old in dr:
        dr = dr.replace(old, new, 1)
        print("docs README record row updated")
    else:
        print("WARN docs README record row not found")
write(DREADME, dr)
print("DONE")
