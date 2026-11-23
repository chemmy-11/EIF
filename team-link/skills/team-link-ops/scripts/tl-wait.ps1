#requires -Version 5.1
<#
.SYNOPSIS
  阻塞等待对端的新任务（或超时返回），把「等」压缩进一次调用。
.DESCRIPTION
  为什么需要它：goal/值班模式下每次续轮都要重载会话历史，代价很贵；
  用 tl-watch 每 2 分钟醒一次等于用最贵的机制等一条消息。
  本脚本在一个 turn 里阻塞轮询本地 state\tasks\，最多 -TimeoutSec 秒：
    - 出现新任务  -> 退出码 0（不推进游标，交给处理步骤 -Advance）
    - 超时仍无    -> 退出码 3（本轮直接结束／继续干别的活）
    - 本机通道断  -> 退出码 2（先修通道，别干等）
  注意：脚本内部的等待是**有界阻塞**，不是 agent 侧的 sleep 循环；
  它不获取 -Lock（锁属于处理步骤），因此不会和自己打架。
.EXAMPLE
  powershell -NoProfile -File scripts\tl-wait.ps1 -TimeoutSec 300 -Quiet
#>
[CmdletBinding()]
param(
  [string]$Bundle = '',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [int]$TimeoutSec = 300,
  [int]$PollSec = 10,
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Bundle)) { $Bundle = Join-Path $DshHome 'bundles\dsh-vivado\optional\team-link' }
$cfgPath = Join-Path $Bundle 'state\config.json'
$tasksDir = Join-Path $Bundle 'state\tasks'
$cursorFile = Join-Path $Bundle 'state\ops-watch.json'

function Read-JsonSafe([string]$Path) {
  try { if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ((Get-Content -Raw -Encoding UTF8 -LiteralPath $Path) -replace '^\uFEFF', '') | ConvertFrom-Json } catch { return $null }
}

$cfg = Read-JsonSafe $cfgPath
if (-not $cfg) { if (-not $Quiet) { Write-Host "FAIL 读不到 state\config.json" }; exit 2 }
$a2aPort = [int]$cfg.a2a.port
$mcpPort = [int]$cfg.mcp.port
$cursor = 0
$c = Read-JsonSafe $cursorFile
if ($c -and $c.lastTicks) { $cursor = [long]$c.lastTicks }

$deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSec))
$slept = 0
while ((Get-Date) -lt $deadline) {
  # 通道自检（只查本机监听，便宜）
  $ports = @($a2aPort, $mcpPort)
  $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in $ports })
  $up = (@($listeners | Where-Object { $_.LocalPort -eq $a2aPort }).Count -gt 0) -and (@($listeners | Where-Object { $_.LocalPort -eq $mcpPort }).Count -gt 0)
  if (-not $up) {
    if (-not $Quiet) { Write-Host "FAIL 本机 LAN 服务没起（a2a/mcp 未监听）：先跑 tools\start-lan.ps1" }
    exit 2
  }
  $newTasks = @()
  if (Test-Path -LiteralPath $tasksDir) {
    $newTasks = @(Get-ChildItem -LiteralPath $tasksDir -File -Filter "*.json" -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTimeUtc.Ticks -gt $cursor } | Sort-Object LastWriteTimeUtc)
  }
  if ($newTasks.Count -gt 0) {
    if (-not $Quiet) {
      Write-Host ("PASS 等到新任务 " + $newTasks.Count + " 条（最早 " + $newTasks[0].LastWriteTime.ToString("HH:mm:ss") + "）")
    }
    exit 0
  }
  $remain = [int](([DateTime]$deadline - (Get-Date)).TotalSeconds)
  if ($remain -le 0) { break }
  Start-Sleep -Seconds ([Math]::Min([Math]::Max(1, $PollSec), $remain))
  $slept += [Math]::Min([Math]::Max(1, $PollSec), $remain)
}

if (-not $Quiet) { Write-Host ("IDLE 等待 " + $slept + " 秒无新任务") }
exit 3
