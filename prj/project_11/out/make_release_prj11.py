# -*- coding: utf-8 -*-
"""make_release_prj11.py — 为 tag prj11-routeB-closed-2026-10-19 创建 GitHub Release。
面向导师/组员：无客套称呼，结果与复现入口优先；正文给复现指南链接。
只读本地仓库，调用 github-account 技能脚本 gh.mjs 发 REST 请求。"""
import json
import subprocess
import sys
import urllib.parse

GH = r"C:\Users\15266\.agents\skills\github-account\scripts\gh.mjs"
REPO = "chemmy-11/EIF"
TAG = "prj11-routeB-closed-2026-10-19"
COMMIT = "ede6326"
BASE = "https://github.com/chemmy-11/EIF/blob/%s/" % TAG

guide_path = "docs/复现/复现_prj11_指南_2026-10-19.md"
guide_url = BASE + urllib.parse.quote(guide_path, safe="/")
record_path = "docs/调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md"
record_url = BASE + urllib.parse.quote(record_path, safe="/")
arch_url = BASE + "prj/project_11/out/archive/ARCHIVE_INDEX_prj11.md"
evid_url = BASE + "prj/project_11/out/evidence_2026-10-19/EVIDENCE_INDEX_r3c.md"
arc_bit_url = BASE + "prj/project_11/out/archive/b31b_r2_2026-10-19_round3d/"

body = f"""## prj11 路线 B 收口（R2 写侧 S2MM → R3 速率量化 → R4 文档收口）

**结论**：prj11 路线 B（B0–B5 / R1–R4）全部完成。验收位流 + 固件已上板通过 **S0–S11 13/13**；
数据面四档、10MB+SHA、J3 四链、双桥计数对账全部通过。

### 验收产物（对应 commit `{COMMIT}`）

| 项 | 标识 | 说明 |
|---|---|---|
| 位流 | `F6012BA0` | round3d，WNS **+0.002** / WHS +0.004，DRC 0 Errors |
| 探针 | `2F8AF498` | 3 核 ILA：ILA0 110b / ILA3 152b / ILA5 47b |
| XSA | `216839F4` | 硬件导出 |
| 固件 | `BA3C0220` | perf1：`s2mm_rearm` + 全速服务 |

逐项 SHA256 与归档：[`b31b_r2_2026-10-19_round3d/`]({arc_bit_url})

### 板端判据（2026-10-19）

- **S0–S11：13/13 PASS**（S4/S5 单帧+ping；S6 桥级 ILA 差分；S7 四档；S8 10MB；S9 J3；S10 双桥对账；S11 收尾）
- **四档**：20/20 · 12/12 · 12/12 · 300/300（100%）
- **10MB**：7022/7022 片，lost=0 / corrupt=0，SHA256 源=重组一致（独立复算）
- **J3 四链**：M/A/B 全 PASS（A 负向缺 1 帧属预期）
- **双桥对账**：mem/mem2 各自 `wm=wr_frm=rd_frm`、`ost=0`、`stall/len_err=0`、`wr_fault=0`

### 速率量化（R3，1466B 帧）

- 可持续 **2000 fps 零丢失**（≈23.5 Mbps 单向）；临界 ≈2500 fps；服务上限 ≈2560 fps（≈390 µs/帧）
- 归因（同一位流、三版固件 A/B）：去掉读服务整引擎复位 / 去掉写服务固定等待，上限变化均 ≤±0.4%
  ⇒ 瓶颈为**每帧软核-桥-DMA 服务往返**（结构性），非单点延时
- 本设计为 AXI DMA **Direct Register Mode**（无描述符）；`s2mm_introut` 仅作桥退休事件，固件轮询
- 对照路线 A 纯硬件帧泵 82.67k fps（≈969 Mbps）；按 Q5「不要求提速」，路线 B 以可编程控制面 + 可观测性为目标

### 复现

- **复现指南（B 章）**：[`docs/复现/复现_prj11_指南_2026-10-19.md`]({guide_url})
  - 流程：产物 hash 核对 → 烧录 → `'d'`/`U`/`W` 体检 → S0–S11 一键 → 四档/10MB/J3 → 速率量化 → ILA → 归档核对 → 8 条已知坑
- 收口记录：[`docs/调试记录/阶段三_prj11_R2写侧S2MM换层_2026-10-17.md`]({record_url}) §十九–§二十二
- 证据索引：[`EVIDENCE_INDEX_r3c.md`]({evid_url})
- 跨轮归档索引：[`ARCHIVE_INDEX_prj11.md`]({arch_url})（33 轮 / 627 文件 / 0 缺失）

### 说明

- 板卡最后在役配置 = round3d `F6012BA0` + 固件 `BA3C0220`（`'d'` 后 DMA 模式）；重烧与体检见复现指南 §2–§3。
- 路线 A（prj10）目录冻结只读，作为对照与回退资产。
"""

payload = {
    "tag_name": TAG,
    "name": "prj11 路线 B 收口（R2–R4，2026-10-19）",
    "body": body,
    "draft": False,
    "prerelease": False,
    "make_latest": "true",
}

js = json.dumps(payload, ensure_ascii=False)
cp = subprocess.run(["node", GH, "api", "POST", "/repos/%s/releases" % REPO, js],
                    capture_output=True)
out = (cp.stdout or b"").decode("utf-8", "replace")
err = (cp.stderr or b"").decode("utf-8", "replace")
print("RC=", cp.returncode)
print("STDOUT_HEAD=", out[:600].replace("\n", " "))
print("STDERR_HEAD=", err[:600].replace("\n", " "))
sys.exit(0 if cp.returncode == 0 else 1)
