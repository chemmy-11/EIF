# refs/ — 跨仓库引用副本（供 EIF 侧 agent 使用）

本目录存放 **GSnFPipe 交付仓（私有）** 中、但 prj12/prj13 任务书需要引用的文档副本，避免协作者 agent 无法访问私有仓库时缺上下文。

> **源以交付仓为准**：`chemmy-11/GSnFPipe-FPGA-PP`，分支 `b/j0-handoff-20261116`（PR #36 / PR #38，冻结提交 `5efb795`）。本目录只是副本，若与源不一致以源为准。

| 文件 | 来源路径 | SHA256 |
|---|---|---|
| `protocol_v2_GPP2.md` | `docs/protocol_v2_GPP2.md`（GPP2/v1 冻结 v1.0） | `4564ab2216bfe4a0a79186b8651b5dd49f9253bdb41b57650f33ac750fd148e7` |
| `J0_GPP2_线格式冻结验证报告_2026-11-16.md` | `docs/J0_GPP2_线格式冻结验证报告_2026-11-16.md` | `2afcebd051ec247fd099ddc52b01e1657cf90b90979a228b90b2884c9c4786bc` |

## 相关但未复制的内容

- B 组最终实现包（`results/raw/20261116_bgroup_final_implementation_v1/`，579 文件 / 23 MB）仍在交付仓；需要查看 GPP2 实现（`pp/transport/b2_reliable_udp.py` 等）时请向负责人索取或按交付仓访问。
- 交付仓 issue #10/#14/#23/#25/#31/#6 与 PR #35/#36/#38 需要交付仓访问权限；EIF 侧对应记录见 EIF #2/#4/#6。

## 已随任务书推送的 prj12 执行件

| 文件 | 说明 | SHA256 |
|---|---|---|
| `prj/project_12/out/b1d_D550FD6B/aurora_mem_bridge_b1d.bit` | B1D 诊断位流（10,027,812 B） | `d550fd6b2dde12dbd5fa3ba07ee33d0be44ed1f0770d747bbcf5858a7fdcf321` |
| `prj/project_12/out/b1d_D550FD6B/probes_b1d.ltx` | B1D ILA（必须与位流成对） | `e04481898594232dd38b6f1692572c9534c9f24126566e7693125d69a0d8de14` |
| `prj/project_12/out/twin_config_b1d.json` | 烧录配置（哈希门禁；仓库已跟踪） | 见该文件内 `expect_bit_sha256` / `probes_ltx_sha256` |

> 位流/ltx 按 `.gitignore` 原本忽略，本次为跨机协作显式强制入库；不要把它们当“可再生产物”重复提交新版本，重建后按新指纹单独登记。
