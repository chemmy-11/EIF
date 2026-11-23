---
name: team-link-ops
description: team-link 的巡检与协作工作流（PC1 主导，两侧都用 goal 模式）。每轮开场用 tl-watch 清收件箱（约 2 秒），有令处理并用 tl-say 回 TEAM-REPORT，`-NoAdvance` 看、成功后才 `-Advance`；含角色权威边界、goal 空转禁令、证据搬运、故障四分类与 issue 降级。DSH 自动化任务已弃用。
---

# team-link-ops

## 0. 角色定位：PC1 主导，PC2 执行

| | PC1（Lead，主导） | PC2（组员，权限同等但受令） |
|---|---|---|
| 拆任务 | ✅ 出 `TEAM-CMD`，写清判据与截止 | 收令；有异议先提，不擅自改 |
| 判据与裁决 | ✅ 唯一判定者（含「算不算通过」） | 只提供证据与建议；争议 `hand_back` 给 PC1 |
| 窗口/上板排期 | ✅ 排期 | 按排期执行，冲突先报 |
| 仓库与 issue | ✅ 开关 issue、合并、发版 | 可提 PR/评论；不擅自合并 |
| 巡检 | 每轮开场清收件箱（约 2 秒） | 每轮先看有没有令，再干自己的活 |
| 收工 | ✅ 说「收工」才算结束 | 停表前必须在 issue 留末态 |

**权限同等 ≠ 决策同等**：PC2 有完整读写与执行权限（不降权、不做阉割），但判据、排期、裁决以 PC1 为准。PC2 认为 PC1 判错时，用证据说话并 `hand_back`，**不自行改判**。

## 0.1 主模式：goal 模式（两侧都走这个）

DSH 的 goal 会**自动续轮**——这是「时刻活跃」的来源。但**每续一轮都要重载整段会话历史**，所以「用多密的轮次去等」直接决定 token 成本。

### 每轮开场：先阻塞等，不要先轮询

```powershell
# 一个 turn 覆盖最多 5 分钟的等待：等到了才醒，等不到就到点返回
powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-wait.ps1 -Bundle <TL> -TimeoutSec 300 -Quiet
```

| 退出码 | 含义 | 本轮做什么 |
|---|---|---|
| `0` | 等到新任务 | 处理（读 `state\tasks\<id>.json` 的 `history[0]`）→ `tl-say.ps1` 回 TEAM-REPORT → **全部成功后** `tl-watch.ps1 -Advance` |
| `3` | 超时仍无新任务 | 不做任何事，继续本任务；本任务已无可推进则收尾（见下方空转禁令） |
| `2` | 本机通道断 | 跑 `tl-state.ps1` 定位；30 秒修不好转 issue |

**成本对照（同样的等待，turn 数差 5–10 倍）**

| 做法 | 每小时 turn 数 | 评价 |
|---|---|---|
| 每 1 分钟 `tl-watch` | ~60 | 最贵，不要这样 |
| 每 2 分钟 `tl-watch` | ~30 | 仍贵 |
| **`tl-wait` 阻塞 5 分钟** | **~12** | 推荐 |
| `tl-wait` 阻塞 10 分钟 | ~6 | 更省，但响应上界也变成 10 分钟 |

`tl-wait` 是**有界阻塞**（脚本内部轮询本地 `state\tasks\`），不是 agent 侧的 sleep 循环——它不占额外轮次，也不会推进游标。

> 若上一轮已经处理完全部任务，本轮也可以直接跑一次 `tl-watch.ps1 -Quiet` 快速确认（约 2 秒），拿到退出码就走，不做任何输出。

### goal 不能空转（硬规则）

连续 **3 轮**没有等到新任务（用 `tl-wait -TimeoutSec 300` 时约等于 **15 分钟**无消息），且本任务已无其它可推进项，**不要再续轮**：

- PC1：把当前结论写进 issue，结束 goal 或转为等人工；
- PC2：在 issue 留一句「待令中 + 末态」，结束 goal。

否则每隔几分钟烧一次完整推理，对端还看不到任何进展。goal 是「有人推进时不要被间隔卡住」，不是「无限轮询」。

## 0.2 已弃用：DSH 自动化任务

**不要再新增。** PC2 之前配过，已确认不稳定（漏投、重复投递都出现过），现在两侧统一改走 goal 模式。已配置的请在 GUI「自动化任务」里停掉或删除。

弃用的第二个原因（结构性）：调度器的投递目标是**一个已存在的会话**（`~/.dsh/storages/schedule.json` 里 `target.kind` 只出现过 `session`），指向正在跑长任务的会话等于每隔几分钟往任务中间插一条输入——上下文被打断、token 白烧。

## 0.3 可选兜底：常驻值班（只有人守着屏幕时）

goal 不方便用时（例如只想临时盯 10 分钟），可以让会话自己循环，但必须带退避、并且**人在场**：

```
按 skill team-link-ops 值班，直到我说「收工」。
每轮 tl-watch -Lock -NoAdvance：new-tasks 就处理并回 TEAM-REPORT，成功后 -Advance；
degraded 就 tl-state 定位；idle 就退避（10min 起，连续 3 轮 idle 翻倍，上限 60min）。
不要 sleep 占位刷屏，不要在 idle 时 ping 对端。
```
## 1. 三个动作，别再多

| 动作 | 命令 | 说明 |
|---|---|---|
| **等**（首选） | `tl-wait.ps1 -TimeoutSec 300 -Quiet` | 有界阻塞，等到新任务才醒。退出码 `0=等到 / 3=超时 / 2=通道断` |
| **发现**（快查） | `tl-watch.ps1 -NoAdvance -Quiet` | 立即返回，只给退出码。`0=idle / 10=new-tasks / 2=degraded / 11=被锁挡住` |
| **回复** | `tl-say.ps1 -Text "TEAM-REPORT ..."` | 走 peer.a2aUrl + peer-a2a.token 发给对端；`0` 已送达、`2` 通道不可用、`5` 认证失败 |
| **收尾** | `tl-watch.ps1 -Advance` | 只在**全部处理成功后**推进游标 |

## 2. 幂等与并发（两条硬规则）

1. **`-NoAdvance` 看、`-Advance` 才算读过。** 默认（不带任何开关）跑 watch 会自动推进游标，等于"看一眼就算读过"——万一处理后失败，这条就再也不会被报出来。自动化里**必须**先 `-NoAdvance` 拿清单，成功后再单独 `-Advance`。
2. **`-Lock` 必带。** 自动化任务定时触发，两次运行可能重叠：`-Lock` 用排他锁保证同一时刻只有一个巡检，被挡住时退出码 **11**，此时本轮直接结束即可。锁超过 `-LockStaleMinutes`（默认 10）视为残留自动回收。

> 残留风险（已如实记录）：同一台机若同时挂两个自动化任务，或一个人工值班会话与自动化并存，仍可能重复处理。规则是**一台机只留一个调度者**；人工会话要看状态请用 `-NoAdvance` 只读。

## 3. 发令 / 回报

格式与纪律沿用 skill **prj-team-collab** §2，不要重复造。team-link 特有、必须补的三项：

| 字段 | 为什么 |
|---|---|
| `task=<8位id>` | 指回 `state/tasks/<id>.json`，对方才能核对 |
| 证据 `<root:path>` + `sha256` | 对端 `evidence_pull.ps1` 拉取后会本地重算校验，不一致视为未交付 |
| `peer=<AgentCard name>` | 防连错机器（`team-link-pc1` / `team-link-pc2`） |

```
TEAM-REPORT <id> | done|blocked|rejected | <一句话结论，数字在首句>
task=<8位id>  peer=<team-link-pcN>
做了什么：<命令与关键输出，≤5 行>
证据：<root:path> sha256=<hex>
偏差与风险：<没有就写 none>
下一步建议：<一句>
```

## 4. 证据搬运

```powershell
powershell -NoProfile -File "$TL\tools\evidence_pull.ps1" -Remote "evidence:report/p1.md" -OutDir "$TL\state\inbox"
```

归档沿用项目纪律（见 prj-team-collab §4）：`results/raw/<YYYYMMDD>_<owner>_<exp>_v1/`，append-only；
大文件（.bit/.ltx/.pcap）不入库，一律"路径 + SHA256"；`SHA256SUMS.txt` 用**带 BOM 的 UTF-8**（否则 PS 5.1 读中文名会乱）。

## 5. 停表与降级到 issue

满足任一就**停止巡检**、转 issue：
- `tl-state.ps1` 的结论里有非 PASS 项，且 30 秒内修不好；
- 对端 `name` 与预期不符（可能连错机器）；
- 需要可被第三方复核的裁决（窗口占用、判据变更、回滚）；
- 同一条任务连续 3 轮处理失败（说明是内容问题，不是通道问题）。

动作三步：① 留证（`tl-watch -NoAdvance -Json` 与 `tl-state` 的输出）；② 在共享仓开/更 issue，写清"停表时间 + verdict + 下一步"；③ 恢复后补齐期间证据并复核 SHA256。

## 6. 故障四分类

| 症状 | 一行判据 | 修法 |
|---|---|---|
| 本机通道 DOWN | `Get-NetTCPConnection -LocalPort 7310,18790 -State Listen` 为空 | 跑 `tools\start-lan.ps1`（**重启后不自启**）|
| bind 不对 | 监听地址 ≠ 当前 WLAN | `start-lan.ps1 -Stop` → `start-lan.ps1` |
| 面板改了没反应 | `state/config.json` host ≠ 面板值 | 重启宿主（详见 skill team-link-setup §0）|
| 回复 401 | `tl-say` 退出码 5 | 对端的 `state/peer-a2a.token` 不是你当前 token |

## 7. 不要做

- 不要 sleep 或空转命令"占位等待"；模式 A 里连循环都不该有。
- **不要再配 DSH 自动化任务**（已弃用：不稳定 + 会中途插话）；两侧统一走 goal 模式。
- 不要在没有实际工作可推进时继续续轮 goal（连续 3 轮 idle 就收尾，见 §0.1）。
- 不要越权裁决：PC2 不自行改判据、不开新窗口、不擅自合并。
- 不要在 `idle` 时回复对端或 ping 对端（互相打扰会烧两边 token）。
- 不要在处理成功前 `-Advance`（会静默丢消息）。
- 不要清 `state/tasks/`（唯一可复核的往来记录）、不要覆盖对端证据目录。
- 不要把 token 值、`.bit/.pcap` 二进制贴进 issue。
