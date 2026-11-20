---
name: team-link-ops
description: team-link 的巡检与协作工作流。两种模式：①自动化触发（DSH 自动化任务定时唤醒，一次触发=一次巡检，无事立即结束）②常驻值班（人守着，自循环退避）。含发现（tl-watch）、回复（tl-say）、证据搬运、排他锁与游标幂等、故障四分类与 issue 降级。
---

# team-link-ops

## 0. 两种模式，先认清你在哪个

| | 模式 A：自动化触发（PC2 用这个） | 模式 B：常驻值班（人守着） |
|---|---|---|
| 谁制造 turn | **DSH 自动化任务**定时唤醒 | agent 自循环 + 退避 |
| 一次触发做什么 | 一次巡检，**做完立即结束** | 循环多轮，直到"收工" |
| 延迟上界 | = 自动化任务的间隔（建议 1–3 min） | = 退避间隔（10 min 起，上限自定） |
| 空闲成本 | 一次 watch（约 2 秒）+ 一次判断 | 每轮一次完整 turn |
| 要不要 sleep | **绝对不要** | 用退避，不要空转 |

模式 A 的精髓：**把"等"交给调度器，把"跑"做短**。一轮里只做一次巡检，`idle` 就立刻结束，不要自作主张进入循环。

## 0.1 模式 A：粘进 DSH 自动化任务的 prompt（自终止）

```
按 skill team-link-ops 执行「一次自动化巡检」，做完立即结束：不要进入循环、不要 sleep、不要重复第 1 步。

1) 跑 TL-WATCH（把 <TL> 换成 team-link 目录）：
   powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-watch.ps1 -Bundle <TL> -Lock -NoAdvance -Json
   - 退出码 11 -> 上一次巡检还没结束，本次什么都不做，直接结束；
   - verdict=idle -> 直接结束（不回复、不通知对端、不写文件）；
   - verdict=degraded -> 跑 tl-state.ps1 取「还缺哪几步」；30 秒内修不好就把结论写进 issue 并结束。

2) verdict=new-tasks：逐条读 <TL>\state\tasks\<id>.json 的 history[0].parts[0].text，按其内容处理。
   每条处理完用 TL-SAY 回一条 TEAM-REPORT（含 task=<8位id>、证据 <root:path> + sha256、peer=<对端AgentCard name>）。
   任一条处理失败：不要推进游标，说明失败原因后结束（下一轮会自动重试同一条）。

3) 全部成功后才推进游标：
   powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-watch.ps1 -Bundle <TL> -Advance

4) 结束。
```

## 0.2 模式 B：常驻值班（人守着时才用）

```
按 skill team-link-ops 值班，直到我说"收工"或对应 issue 关闭。
每轮跑 tl-watch.ps1 -Lock -Json：new-tasks 就处理并回 TEAM-REPORT，成功后 -Advance；
degraded 就 tl-state.ps1 定位，30 秒修不好转 issue 并停表；idle 就按退避等下一轮（10min 起，连续 3 轮 idle 翻倍，上限 60min）。
不要 sleep 占位刷屏；不要在 idle 时反复 ping 对端。
```

## 1. 三个动作，别再多

| 动作 | 命令 | 说明 |
|---|---|---|
| **发现** | `tl-watch.ps1 -Lock -NoAdvance -Json` | 本机双通道 + 对端身份 + 自上次新增任务。退出码 `0=idle / 10=new-tasks / 2=degraded / 11=被锁挡住` |
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
- 不要在 `idle` 时回复对端或 ping 对端（互相打扰会烧两边 token）。
- 不要在处理成功前 `-Advance`（会静默丢消息）。
- 不要清 `state/tasks/`（唯一可复核的往来记录）、不要覆盖对端证据目录。
- 不要把 token 值、`.bit/.pcap` 二进制贴进 issue。
