#requires -Version 5.1
<#
.SYNOPSIS
  值班用「一次取数」：本机通道 + 对端可达 + 自上次以来新增的 A2A 任务。
.DESCRIPTION
  给 team-link-ops 的值班循环用，一次调用拿全本轮要看的东西，避免每轮发一堆命令。
  不做任何写操作（除了更新自己的游标文件）。
  退出码：0=一切正常且无新任务；10=有新的 A2A 任务需要处理；2=通道降级（本机服务或对端不可达）。
.PARAMETER CursorFile
  游标文件，记录上次看到的最新任务时间。缺省 <bundle>\state\ops-watch.json。
.PARAMETER NoAdvance
  只看不推进游标（下一次还会报同一批新任务）。
.EXAMPLE
  powershell -NoProfile -File scripts\tl-watch.ps1
.EXAMPLE
  powershell -NoProfile -File scripts\tl-watch.ps1 -Json
#>
[CmdletBinding()]
param(
  [string]$Bundle = '',
  [string]$CursorFile = '',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [switch]$Json,
  [switch]$NoAdvance,
  [switch]$Lock,
  [int]$LockStaleMinutes = 10,
  [switch]$Advance
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Bundle)) {
  $Bundle = Join-Path $DshHome 'bundles\dsh-vivado\optional\team-link'
}
$cfgPath = Join-Path $Bundle 'state\config.json'
$tasksDir = Join-Path $Bundle 'state\tasks'
if ([string]::IsNullOrWhiteSpace($CursorFile)) { $CursorFile = Join-Path $Bundle 'state\ops-watch.json' }

function Read-JsonSafe([string]$Path) {
  try { if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ((Get-Content -Raw -Encoding UTF8 -LiteralPath $Path) -replace '^\uFEFF', '') | ConvertFrom-Json } catch { return $null }
}

$cfg = Read-JsonSafe $cfgPath
# 排他锁：自动化任务会定时反复触发，两次运行重叠会重复处理同一批任务。
# 用 -Lock 时同一时刻只允许一个巡检；超过 LockStaleMinutes 的锁视为残留并回收。
$lockPath = Join-Path $Bundle 'state\ops-watch.lock'
$lockHeld = $false
if ($Lock) {
  if (Test-Path -LiteralPath $lockPath) {
    $age = ((Get-Date) - (Get-Item -LiteralPath $lockPath).LastWriteTime).TotalMinutes
    if ($age -gt $LockStaleMinutes) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
  }
  try {
    $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $b = [System.Text.Encoding]::UTF8.GetBytes(('pid=' + $PID + ' at=' + (Get-Date).ToString('s')))
    $fs.Write($b, 0, $b.Length); $fs.Close()
    $lockHeld = $true
  } catch {
    Write-Host 'FAIL 另一个巡检正在运行（lock 被占用），本次跳过，避免重复处理同一批任务'
    if ($Json) { '{"verdict":"locked"}' }
    exit 11
  }
}
if (-not $cfg) { if ($Json) { '{"verdict":"no-config"}' } else { Write-Host "FAIL 读不到 state\config.json" }; exit 2 }
$a2aPort = [int]$cfg.a2a.port
$mcpPort = [int]$cfg.mcp.port

# 1) 本机通道
$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in @($a2aPort, $mcpPort) })
$a2aUp = [bool](@($listeners | Where-Object { $_.LocalPort -eq $a2aPort }).Count)
$mcpUp = [bool](@($listeners | Where-Object { $_.LocalPort -eq $mcpPort }).Count)

# 2) 对端
$peerHost = ''
if ($cfg.peer.a2aUrl) { try { $peerHost = ([uri]$cfg.peer.a2aUrl).Host } catch { } }
$peerTcp = $false
$peerName = ""
if ($peerHost) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $peerTcp = ($c.ConnectAsync($peerHost, $a2aPort).Wait(1500)) -and $c.Connected } catch { $peerTcp = $false } finally { $c.Close() }
  if ($peerTcp) {
    try {
      $u = ([string]$cfg.peer.a2aUrl).TrimEnd('/') + '/.well-known/agent.json'
      $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 6
      $peerName = [string]($r.Content | ConvertFrom-Json).name
    } catch { $peerName = "?" }
  }
}

# 3) 新任务（按游标）
$cursor = 0
$c = Read-JsonSafe $CursorFile
if ($c -and $c.lastTicks) { $cursor = [long]$c.lastTicks }
$allTasks = @()
if (Test-Path -LiteralPath $tasksDir) {
  $allTasks = @(Get-ChildItem -LiteralPath $tasksDir -File -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)
}
$newTasks = @($allTasks | Where-Object { $_.LastWriteTimeUtc.Ticks -gt $cursor })
$maxTicks = $cursor
foreach ($t in $allTasks) { if ($t.LastWriteTimeUtc.Ticks -gt $maxTicks) { $maxTicks = $t.LastWriteTimeUtc.Ticks } }

# -Advance：只把游标推到当前最新（"处理成功后才算读过"），不探测、不输出清单。
if ($Advance) {
  if ($maxTicks -le $cursor) { Write-Host ("OK 游标已是最新（" + $allTasks.Count + " 条任务）") ; exit 0 }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CursorFile) | Out-Null
  ([pscustomobject]@{ lastTicks = $maxTicks; time = (Get-Date).ToString("s") } | ConvertTo-Json) |
    Set-Content -LiteralPath $CursorFile -Encoding UTF8
  Write-Host ("OK 游标已推进到最新（" + $allTasks.Count + " 条任务）")
  exit 0
}

$brief = @()
foreach ($t in ($newTasks | Select-Object -Last 5)) {
  $obj = Read-JsonSafe $t.FullName
  $state = if ($obj -and $obj.status) { [string]$obj.status.state } else { "?" }
  $reply = ""
  try { if ($obj.artifacts) { $reply = [string]$obj.artifacts[0].parts[0].text } } catch { }
  $brief += (($t.BaseName).Substring(0, [Math]::Min(8, $t.BaseName.Length)) + " state=" + $state + $(if ($reply) { " reply=" + $reply.Substring(0, [Math]::Min(60, $reply.Length)) } else { "" }))
}

$channelsOk = $a2aUp -and $mcpUp -and $peerTcp
$verdict = if (-not $channelsOk) { "degraded" } elseif ($newTasks.Count -gt 0) { "new-tasks" } else { "idle" }

if ($Json) {
  ([pscustomobject]@{
    time = (Get-Date).ToString("s")
    role = [string]$cfg.role
    local = [pscustomobject]@{ a2a = $a2aUp; mcp = $mcpUp }
    peer = [pscustomobject]@{ host = $peerHost; tcp = $peerTcp; name = $peerName }
    tasks = [pscustomobject]@{ total = $allTasks.Count; new = $newTasks.Count; brief = $brief }
    verdict = $verdict
  } | ConvertTo-Json -Depth 6 -Compress)
} else {
  Write-Host ("== team-link 值班取数 " + (Get-Date -Format "HH:mm:ss") + " ==")
  Write-Host ("  本机  a2a=" + $(if ($a2aUp) { "UP" } else { "DOWN" }) + "  mcp=" + $(if ($mcpUp) { "UP" } else { "DOWN" }) + "  role=" + $cfg.role)
  Write-Host ("  对端  " + $(if ($peerHost) { $peerHost } else { "(未配置)" }) + "  tcp=" + $(if ($peerTcp) { "UP" } else { "DOWN" }) + "  name=" + $(if ($peerName) { $peerName } else { "-" }))
  Write-Host ("  任务  累计=" + $allTasks.Count + "  自上次新增=" + $newTasks.Count)
  foreach ($b in $brief) { Write-Host ("        - " + $b) }
  Write-Host ("  判定  " + $verdict)
}

if (-not $NoAdvance -and $maxTicks -gt $cursor) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CursorFile) | Out-Null
  ([pscustomobject]@{ lastTicks = $maxTicks; time = (Get-Date).ToString("s") } | ConvertTo-Json) |
    Set-Content -LiteralPath $CursorFile -Encoding UTF8
}

$exitCode = 0
if ($verdict -eq "degraded") { $exitCode = 2 }
elseif ($verdict -eq "new-tasks") { $exitCode = 10 }
if ($lockHeld) { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue }
exit $exitCode
