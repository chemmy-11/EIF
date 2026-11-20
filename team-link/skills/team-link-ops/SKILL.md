---
name: team-link-ops
description: team-link 的日常值班与协作工作流。给"盯对端/等任务/发令回报/证据搬运/故障降级"用：每轮只跑一次 tl-watch 取数，按 verdict 处理；明确值班 prompt 骨架、退出与降级条件、发令回报格式、证据归档与 issue 回退。
---

# team-link-ops

## 0. 值班 prompt（解决"必须手打才能让对方盯着"）

把下面这段**原样**发给要值班的那一侧，就等于把值班状态钉进去了；不需要每次重新描述。

```
按 skill team-link-ops 值班，直到我说"收工"或对应 issue 关闭。
每轮：先跑 tl-watch.ps1（-Json）；
  verdict=new-tasks → 逐个处理，处理完回一条 TEAM-REPORT（含 task id 与证据路径+SHA256）；
  verdict=degraded  → 先跑 tl-state.ps1 定位，30 秒内仍不通就转 issue 轮询并停表；
  verdict=idle      → 什么都不做，按退避间隔等下一轮（10min 起，连续 3 轮 idle 翻倍，上限 60min）。
不要 sleep 占位刷屏；不要在 idle 时反复 ping 对端。
```

## 1. 每轮只做三件事（一次取数，别发一堆命令）

```powershell
$TL = "$env:USERPROFILE\.dsh\bundles\dsh-vivado\optional\team-link"
powershell -NoProfile -File "$TL\skills\team-link-ops\scripts\tl-watch.ps1" -Bundle $TL -Json
```

一次输出里就有：本机 a2a/mcp 是否 UP、对端 host/tcp/name、任务累计与**自上次新增**、`verdict`。
退出码即信号：**0=idle**、**10=new-tasks**、**2=degraded**。游标默认推进（`-NoAdvance` 可只看不动）。

| verdict | 你该做的 |
|---|---|
| `idle` | 什么都不做。按退避间隔等下一轮。**不要**为了"看看还在不在"再 ping 一次。 |
| `new-tasks` | 逐个看 `state/tasks/<id>.json` 的 `history`（对端说了什么），处理后回 TEAM-REPORT。 |
| `degraded` | 跑 `tl-state.ps1` 定位（四分类见下），修不好就转 issue。 |

## 2. 发令 / 回报（格式沿用 prj-team-collab，别重复造）

发令 `TEAM-CMD`、回报 `TEAM-REPORT` 的字段与纪律见 skill **prj-team-collab** §2。
team-link 特有、必须补上的三项：

| 字段 | 为什么 |
|---|---|
| `task=<8位id>` | 回报必须指回 `state/tasks/<id>.json`，否则对方无法核对 |
| 证据 `root:path` + `sha256` | 对端用 `evidence_pull.ps1` 拉取后会本地重算校验，对不上即视为未交付 |
| `peer=<对端AgentCard name>` | 防连错机器（`team-link-pc1` / `team-link-pc2`） |

回报模板：

```
TEAM-REPORT <id> | done|blocked|rejected | <一句话结论，数字在首句>
task=<8位id>  peer=<team-link-pcN>
做了什么：<命令与关键输出，≤5 行>
证据：<root:path> sha256=<hex>
偏差与风险：<没有就写 none>
下一步建议：<一句>
```

## 3. 证据搬运与归档

```powershell
# 从对端拉证据（走 MCP，落地后本地重算 SHA256 比对）
powershell -NoProfile -File "$TL\tools\evidence_pull.ps1" -Remote "evidence:report/p1.md" -OutDir "$TL\state\inbox"
```

归档约定沿用项目既有纪律（见 prj-team-collab §4）：`results/raw/<YYYYMMDD>_<owner>_<exp>_v1/`，append-only，
大文件（.bit/.ltx/.pcap）不入库，一律"路径 + SHA256"引用；`SHA256SUMS.txt` 用**带 BOM 的 UTF-8**写（否则 PS 5.1 读中文名会乱）。

## 4. 降级到 issue（什么时候停表）

满足任一就**停止值班**、转 issue 轮询：
- `tl-state.ps1` 的结论里有任一项不是 PASS，且 30 秒内修不好；
- 对端 `name` 与预期不符（可能连错机器）；
- 需要"可被第三方复核"的裁决（窗口占用、判据变更、回滚决定）；
- 对端超过 2 个退避周期都没有任何响应。

动作固定三步：① 留证（`tl-watch.ps1 -Json` 的输出 + `tl-state.ps1` 输出）；② 在共享仓开/更 issue，写清"停表时间 + verdict + 下一步"；③ 恢复后再把期间证据补齐并复核 SHA256。

## 5. 故障四分类（与 team-link-setup 同一张表，值班时按这个顺序查）

| 症状 | 一行判据 | 修法 |
|---|---|---|
| 本机 DOWN | `Get-NetTCPConnection -LocalPort 7310,18790 -State Listen` 空 | `tools\start-lan.ps1`（重启后不自启）|
| bind 不对 | 监听地址 ≠ 当前 WLAN | `start-lan.ps1 -Stop` → `start-lan.ps1` |
| 面板改了没反应 | `state/config.json` host ≠ 面板 | 重启宿主（详见 team-link-setup §0）|
| 401 | 自己正常、对端 401 | 对端的 `state/peer-*.token` 不是你当前 token |

## 6. 收工清单

1. `tl-watch.ps1 -Json -NoAdvance` 留一份末态。
2. 未处理的 `new-tasks` 逐条写进 issue（id + 一句话），别留在会话里。
3. 若改过地址/配置，交接里写清"当前 IP + 谁还需要重启"。
4. 不要关掉对端的服务；不要清 `state/tasks/`（那是唯一可复核的往来记录）。

## 7. 不要做

- 不要用 `sleep` 或空转命令"占位等待"——用退避，而不是刷屏。
- 不要在 `idle` 时反复 ping 对端（对方也在值班，互相打扰会烧两边 token）。
- 不要清 `state/tasks/`、不要覆盖对端证据目录（append-only）。
- 不要把 token 值、`.bit/.pcap` 二进制贴进 issue。
