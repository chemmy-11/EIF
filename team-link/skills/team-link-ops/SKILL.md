---
name: team-link-ops
description: team-link 的协作工作流（PC1 主导，两侧都用 goal 模式）。每轮用 tl-recv 原子收件（等到即醒、正文直出、按 id 记账），处理完用 tl-say 回 TEAM-REPORT 再 tl-recv -Done；含角色权威边界、等待与超时契约、静默与通道故障的区分、goal 续轮与 blocked 纪律、证据搬运与 issue 降级。
skill-version: 2026-11-24
---

# team-link-ops

> 版本行写在 frontmatter 里（`skill-version`）。技能文本在会话开始时就固定了，改完后**必须开新会话**才生效；
> 排查时先看这条版本号，就能判断对方用的是哪一版。

## 0. 角色定位：PC1 主导，PC2 执行

| | PC1（Lead，主导） | PC2（组员，权限同等但受令） |
|---|---|---|
| 拆任务 | ✅ 出 `TEAM-CMD`，写清判据与截止 | 收令；有异议先提，不擅自改 |
| 判据与裁决 | ✅ 唯一判定者（含「算不算通过」） | 只提供证据与建议；争议 `hand_back` 给 PC1 |
| 窗口 / 上板排期 | ✅ 排期 | 按排期执行，冲突先报 |
| 仓库 / issue | ✅ 开关 issue、合并、发版 | 可提 PR/评论；不擅自合并 |
| 收工 | ✅ 说「收工」才算结束 | 停表前必须在 issue 留末态 |

**权限同等 ≠ 决策同等**：PC2 有完整读写与执行权限（不降权、不阉割），但判据、排期、裁决以 PC1 为准。
PC2 认为 PC1 判错时，用证据说话并 `hand_back`，**不自行改判**。

## 1. 每轮只做一件事：`tl-recv`

```powershell
powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-recv.ps1 -Bundle <TL> -TimeoutSec 240
```

一条命令完成「找新消息 → 打印正文 → 记 delivered」，**没有单独的「推进游标」步骤**，
所以不存在「处理期间到达的消息被一起跳过」或「看一眼就算已读」这两类竞态。

| 退出码 | 含义 | 本轮做法 |
|---|---|---|
| `0` | 有消息，正文已打印 | 读正文 → 处理 → `tl-say` 回 TEAM-REPORT → `tl-recv -Done <id>` |
| `3` | 没有新消息 | 不做任何事，继续本任务 |
| `2` | 没有新消息 **且本机 A2A 服务没监听** | 只有这种情况才是通道故障：`tools\start-lan.ps1` |

**收尾三件套（顺序不能反）**

```powershell
# 1) 回复对端
powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-say.ps1 -Text "TEAM-REPORT ..."
# 2) 确认完成（只有回复成功后才做）
powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-recv.ps1 -Bundle <TL> -Done <8位id>
# 3) 处理失败就别 Done，用 -Fail 留原因（不会重报）
powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-recv.ps1 -Bundle <TL> -Fail <8位id> -FailNote "为什么"
```

读了但没 `-Done` 的消息，超过 10 分钟会被带「未确认完成」标号重报——agent 被打断也不丢。

## 2. 宿主 `pwsh` 契约（不遵守就会「以为在等，其实早已返回」）

宿主的 `pwsh` 工具**超时后不杀进程，而是转后台**并返回 `[still running after <timeoutMs>ms; moved to background job <id>]`。
所以阻塞等待必须把工具超时设得比脚本等待更长：

- 调用 `tl-recv -TimeoutSec N` 时必须给 `timeoutMs ≥ (N + 60) × 1000`；不给就按默认 60 秒，脚本还在跑、结果没人接。
- 如果已经被转后台，用 `job_output({ job_id, wait: true })` 取结果，不要重发一遍命令（会重复消费）。

## 3. 静默要分两种（这条以前搞错过，害得 agent 自己收摊）

| 现象 | 是通道问题吗 | 怎么做 |
|---|---|---|
| 对端 TCP 连不上 / 本机服务没监听 | ✅ 是 | 修通道（`tl-state.ps1` 定位），修不好转 issue |
| 对端连得上、只是没说话 | ❌ **不是** | 正常工作中，继续等；PC2 跑一轮上板序列本来就要几分钟到十几分钟 |

**不要再因为「连续几轮没消息」就结束 goal 或把自己置 `blocked`。** 那条旧规则已删除：
它会让 agent 在对端正常干活时主动停止收听，正是之前「PC2 发了、PC1 没反应」的成因之一。

## 4. goal 的续轮与 blocked

- `maxGoalRounds` 建 goal 时**给够**（宁可大）；撞上限后不会自动续，需要人工「继续」。
- `blocked` 只用于「**没有人介入我无法推进**」（例如要用户拍板方案），**不用于「对端还没回」**。
- 真正该收尾的信号是任务结束（用户说收工 / issue 关闭），不是消息静默。

## 5. 发令 / 回报

格式与纪律沿用 skill **prj-team-collab** §2，不要重复造。team-link 特有、必须补的三项：

| 字段 | 为什么 |
|---|---|
| `task=<8位id>` | 指回 `state/tasks/<id>.json`，对方才能核对 |
| 证据 `root:path` + `sha256` | 对端 `evidence_pull.ps1` 拉取后本地重算校验，不一致视为未交付 |
| `peer=<AgentCard name>` | 防连错机器（`team-link-pc1` / `team-link-pc2`） |

```
TEAM-REPORT <id> | done|blocked|rejected | <一句话结论，数字在首句>
task=<8位id>  peer=<team-link-pcN>
做了什么：<命令与关键输出，≤5 行>
证据：<root:path> sha256=<hex>
偏差与风险：<没有就写 none>
下一步建议：<一句>
```

**`tl-say` 的「已送达」只表示对端服务已落盘，不代表对端 agent 已读。** 要确认对方处理了，等它的 TEAM-REPORT。

## 6. 证据搬运

```powershell
powershell -NoProfile -File <TL>\tools\evidence_pull.ps1 -Remote "evidence:report/p1.md" -OutDir <TL>\state\inbox
```

归档沿用项目纪律（`prj-team-collab` §4）：`results/raw/<YYYYMMDD>_<owner>_<exp>_v1/`，append-only；
大文件（.bit/.ltx/.pcap）不入库，一律「路径 + SHA256」；`SHA256SUMS.txt` 用**带 BOM 的 UTF-8**。

## 7. 故障四分类

| 症状 | 一行判据 | 修法 |
|---|---|---|
| 本机通道 DOWN | `Get-NetTCPConnection -LocalPort 7310,18790 -State Listen` 为空 | `tools\start-lan.ps1`（**重启后不自启**）|
| bind 不对 | 监听地址 ≠ 当前 WLAN 地址 | `start-lan.ps1 -Stop` → `start-lan.ps1`（详见 team-link-setup）|
| 面板改了没反应 | `state/config.json` host ≠ 面板值 | 重启宿主 |
| 回复 401 | `tl-say` 退出码 5 | 对端的 `state/peer-a2a.token` 不是你当前 token |

## 8. 写 PowerShell 的两个坑（本仓库真踩过）

1. **变量名大小写不敏感**：脚本里写 `$all = @()` 会覆盖参数 `[switch]$All`，跟着抛
   `Cannot convert value "System.Object[]" to type "System.Management.Automation.SwitchParameter"`。
   同类还有 `$json` 覆盖 `-Json`。**局部变量名不要和参数同名（忽略大小写）**。
2. **`.ps1` 必须带 BOM 的 UTF-8**：PS 5.1 会把无 BOM 的 UTF-8 当 GBK 读，中文全乱、解析失败。
   用 `edit` 工具改 `.ps1` 会丢 BOM，改完要补 `\uFEFF` 再写回。

## 9. 不要做

- 不要用 `sleep` 或空转命令占位等待；等待就交给 `tl-recv -TimeoutSec`。
- 不要在没回复成功前 `-Done`（会静默丢消息）。
- 不要因为消息静默就把 goal 置 `blocked` 或收摊（见 §3）。
- 不要清 `state/tasks/`（唯一可复核的往来记录）、不要覆盖对端证据目录。
- 不要把 token 值、`.bit/.pcap` 二进制贴进 issue。
- 不要越权裁决：PC2 不自行改判据、不开新窗口、不擅自合并。
