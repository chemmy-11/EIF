# proposals/ — 协作者方案与评审记录

本目录存放协作者（PC2）提交的下一轮实施方案与摘要，供 EIF 侧公开复核；**方案是输入，不是执行授权**。评审结论与拍板项见 EIF **#9**。

## 文件

| 文件 | 来源 | SHA256 |
|---|---|---|
| `M1_prj12_prj13_下一轮实施方案_2026-11-17.md` | PC2 方案正文（383 行，`status=proposed-for-lead-review`） | `0e1fc2f8c03e0aae447b42ea621939f5d386759169604877c5cf81ead187a90e` |
| `M1_prj12_prj13_实施方案_issue摘要_2026-11-17.md` | PC2 摘要（可粘贴草稿） | `cad28271abbd130b9e7e31f5965d49b56399d9d2ff982ae779013dca610f0ce5` |

## 评审结论（2026-11-17）

- 方案可作为下一轮执行基线；负责人已同意 EIF #9 的 **D1–D10** 全部建议。
- 方案需出 v2 修正 8 项事实勘误（C1–C8，见 #9），其中：
  - 空 Tensor 按 **count=0**（B 实现）作语义勘误 v1.1，不改 wire；
  - GPP2 业务端口统一 **47001**（B 传输层 bind/peer 可配）；
  - 旧 V3 是 **B→A 反向计数一致性核对**，不是“反向 mem2 闪断诊断”；
  - baseline/B1 位流已补推 EIF（见下）；
  - G2 拆 **W1a（M1-A 数据面）/W1b（#23 恢复+错误注入）**。

## 已随任务书补推的 prj12 对照件

| 文件 | SHA256 / 字节 |
|---|---|
| `prj/project_12/out/b1_E9BE2B14/aurora_mem_bridge_b1.bit` | `e9be2b14e819ae299682a804eb1edff5967dd280eda48f33620306444eb1308e` / 10,636,592 B |
| `prj/project_12/out/b1_E9BE2B14/probes_b1.ltx` | `b30c3903272bc7517b7db1ab9960751e73a67d0b0d761d0900184f5fe80dc525` / 134,915 B |
| `prj/project_12/out/baseline_C856BA83_2026-11-06/aurora_mem_bridge.bit` | `c856ba83781fe85ccdcb684b6cd3c60873aa43e92f89ad30000b5954e5667401` / 10,302,552 B |
| `prj/project_12/out/baseline_C856BA83_2026-11-06/probes.ltx` | `a6a4aaeaab8b3883070750f6d41eb7c2ca2e10547bfa5ae920c52977b42e0666` / 112,877 B |

> 位流/ltx 必须成对；B1D 见 `prj/project_12/out/b1d_D550FD6B/`。所有位流与 ltx 已按 `.gitattributes` 二进制保存，Git blob SHA256 与上表一致。
