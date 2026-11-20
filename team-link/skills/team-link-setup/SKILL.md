---
name: team-link-setup
description: 配置/修复 PC1↔PC2 的 team-link 协作通道。换网段、换机器、第一次装、或"配置看着对但连不上"时用：只读诊断（tl-state.ps1）指出还缺哪几步，写入（tl-sync.ps1 -Apply）把本机地址同步到 profile 与 state/config.json 两处，再按清单完成重启与自检。
---

# team-link-setup

## 0. 一句话记住四件事

**地址在系统里有四处，只改一处不算配好。**

| # | 位置 | 谁改 | 生效时机 |
|---|---|---|---|
| ① | profile `cordis.patch.yml` 的 `team-link` 块 `host:` | GUI 面板 / `tl-sync.ps1` | **宿主**下次启动 |
| ② | `state/config.json` 的 `a2a.host` / `mcp.host` | 宿主 `apply()` 从 ① 物化 / `tl-sync.ps1` | 宿主启动后 |
| ③ | LAN 服务的**实际 bind** | `tools/start-lan.ps1` 启动那一刻 | 服务启动时 |
| ④ | 对端记录的**你的地址** | 对端自己 | 对端重启后 |

推论（全是踩过的坑）：
- **只在 UI 里改，服务不会跟着走**：服务是脱离宿主的长驻进程，IP 一变它就绑在一个已不存在的地址上 → 表现是"配置看着对、对端连不上"。
- **不重启宿主，② 不会更新**，`collab_status` 会报旧值。
- ①改完②会被 `apply()` 覆盖回 ① 的值 —— 所以**只有 ① 是权威**，别只手动改 ②。
- **只有防火墙不用动**：两边 node.exe 的入站规则是 `LocalPort=Any` / `RemoteAddress=Any`。

## 1. 先诊断（只读，10 秒）

```powershell
$TL = "$env:USERPROFILE\.dsh\bundles\dsh-vivado\optional\team-link"   # 装在仓库里就指向仓库的 team-link
powershell -NoProfile -File "$TL\skills\team-link-setup\scripts\tl-state.ps1" -Bundle $TL
```

输出末段 **「结论：还缺哪几步」** 就是你要做的全部。四处一致时会直接 `PASS 四处一致，通道就绪`。

判据（三条必须同一个 IP）：本机 WLAN 地址 / 服务监听地址 / 配置里的 host。

## 2. 同步两处配置（幂等，默认只出计划）

```powershell
# 先看计划（不写盘）
powershell -NoProfile -File "$TL\skills\team-link-setup\scripts\tl-sync.ps1" -Bundle $TL

# 确认无误后落盘；对端地址变了就带 -PeerHost
powershell -NoProfile -File "$TL\skills\team-link-setup\scripts\tl-sync.ps1" -Bundle $TL -Apply -PeerHost 10.x.x.x
```

它只做两件写操作：① 的 `team-link` 块内 `host:` 行、② 的 `a2a.host`/`mcp.host`（带 `-PeerHost` 时连 `peer.*Url`）。
写前打 `.bak-tlsync-<时间戳>` 备份，写后回读校验；不重启任何东西。
**网段守卫**：拒绝回环/链路本地，以及 `192.168.1.0/24`（两板私有链路、同 IP 同 MAC）。

> 也可以走 GUI（设置 → PC 协作）改 ①，效果等价；改完同样需要下面第 3 步。

## 3. 让改动生效（两件事，脚本故意不代劳）

```powershell
# 3a. 重启宿主：把 ① 物化进 ②（Electron 下 dsh-hmr 不生效）
# 3b. 重绑 LAN 服务：换地址必须重起，否则还绑在旧地址上
powershell -NoProfile -File "$TL\tools\start-lan.ps1" -Stop
powershell -NoProfile -File "$TL\tools\start-lan.ps1"
```

判据：`start-lan.ps1` 末段应出现
`PASS a2a 监听 <你的IP>:7310（跨机模式）` 与 `PASS mcp 监听 <你的IP>:18790（跨机模式）`。

## 4. 自检（不通过就别通知对端）

```powershell
# 本机双通道
powershell -NoProfile -File "$TL\tools\collab_status.ps1"          # 期望 exit 0
# 本机 AgentCard（用 LAN 地址，不是 127.0.0.1）
Invoke-WebRequest "http://<你的IP>:7310/.well-known/agent.json" -UseBasicParsing | % StatusCode   # 期望 200
# 对端可达 + 身份（防连错机器）
powershell -NoProfile -File "$TL\tools\pc1_pc2_ping.ps1"            # 期望 exit 0 且打印对端 name
```

## 5. 交给对端的一句话（固定模板）

```
我这侧已就绪：a2a=http://<我的IP>:7310/  mcp=http://<我的IP>:18790/mcp
请把你们的面板/配置里"对端地址"改成上面两个，然后重启宿主 + start-lan -Stop/start；
token 不用换（各持对方 token 即可）。回我一句 pc1_pc2_ping 的 name 就行。
```

## 6. 故障四分类（症状 → 一行判据 → 修法）

| 症状 | 一行判据 | 修法 |
|---|---|---|
| 本机通道 DOWN | `Get-NetTCPConnection -LocalPort 7310,18790 -State Listen` 为空 | 跑 `start-lan.ps1`（**重启后不会自启**）|
| 配置对但连不上 | 监听地址 ≠ 当前 WLAN 地址 | `start-lan.ps1 -Stop` 再 start（第 3b 步）|
| 面板改了没反应 | `state/config.json` 的 host ≠ 面板值 | 没重启宿主（第 3a 步）|
| 对端 401 | 自己 `collab_status.ps1` 正常、对端回 401 | 对端的 `state/peer-*.token` 里不是你当前的 token：重发 token 或让对端用你的值 |
| 对端 name 不对 | `pc1_pc2_ping.ps1` 打印的 name 不是期望的 | 连错机器：先 `tl-state.ps1` 看 peer.a2aUrl |

## 7. 不要做

- 不要手改 `cordis.patch.yml` 里 `team-link` 块以外的行（其它插件行会被连带改坏）。
- 不要在服务没停的时候"以为改配置就生效"——绑定发生在启动那一刻。
- 不要用 `192.168.1.x` 做 PC 协作地址。
- 不要把 token 值写进 issue、聊天、或任何仓库文件；只报"存在/缺失"。
