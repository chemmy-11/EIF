#requires -Version 5.1
<#
.SYNOPSIS
  原子收件：一次调用完成「找新消息 -> 打印正文 -> 标记已读」，用 id 账本记账。
.DESCRIPTION
  取代 tl-watch / tl-wait 的两步式用法（看一次、再推进一次），从结构上消除两个竞态：
    - 不会再出现「处理期间到达的消息被 -Advance 一起跳过」；
    - 不会再出现「看一眼就被算作已读」。

  账本：state\ops-ledger.json，按消费者（-Consumer）分区，每个任务 id 记状态：
    new（未读） -> delivered（已读到，等确认完成） -> done（已回复）
  delivered 超过 -StaleMinutes 仍未 done 的，下次会带「未确认完成」提示重报，agent 被打断也不丢。
  任务文件被就地改写、~/.dsh 被备份还原，都不再影响收件（按 id 记账，不按修改时间）。

  退出码：
    0 = 有消息（已打印正文并记账；含「未确认完成」的重报）
    3 = 无消息（超时或收件箱为空）
    2 = 无消息且本机 A2A 服务没在监听（只有这种情况才需要修通道）
.PARAMETER TimeoutSec
  大于 0 时阻塞等待最多这么多秒；0（默认）立即返回。宿主侧调用必须给足够的 timeoutMs。
.PARAMETER Peek
  只打印不记账（不标记 delivered）。
.PARAMETER All
  连同「已读到但未确认完成」的一起重报。
.PARAMETER Done
  标记某任务为 done（处理并回复成功后调用）。
.PARAMETER Fail
  标记某任务为失败并附原因（记 done + note，不再重报）。
.PARAMETER Baseline\n  传 'all' 时把当前所有任务标记为 done（首次启用账本建立基线）。
  把当前所有任务标记为 done（首次启用账本时建立基线）。
.EXAMPLE
  powershell -NoProfile -File scripts\tl-recv.ps1 -TimeoutSec 240
.EXAMPLE
  powershell -NoProfile -File scripts\tl-recv.ps1 -Done 3f2a1b0c
#>
[CmdletBinding()]
param(
  [string]$Bundle = '',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [string]$Consumer = 'default',
  [int]$TimeoutSec = 0,
  [int]$PollSec = 5,
  [int]$StaleMinutes = 10,
  [int]$MaxBodyChars = 4000,
  [string]$Done = '',
  [string]$Fail = '',
  [string]$FailNote = '',
  [switch]$All,
  [switch]$Peek,
  [switch]$Json,
  [string]$Baseline = '',
  [string]$LedgerPath = ''
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Bundle)) { $Bundle = Join-Path $DshHome 'bundles\dsh-vivado\optional\team-link' }
$cfgPath = Join-Path $Bundle 'state\config.json'
$tasksDir = Join-Path $Bundle 'state\tasks'
if ([string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath = Join-Path $Bundle 'state\ops-ledger.json' }

function Read-JsonSafe([string]$Path) {
  try {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ((Get-Content -Raw -Encoding UTF8 -LiteralPath $Path) -replace '^\uFEFF', '') | ConvertFrom-Json
  } catch { return $null }
}

# 原子写：先写 .tmp 再 Move-Item 覆盖，避免读方看到半截 JSON。
function Write-JsonAtomic([string]$Path, $Obj) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = $Path + ".tmp-" + $PID
  $jsonText = ($Obj | ConvertTo-Json -Depth 12)
  [System.IO.File]::WriteAllText($tmp, ($jsonText + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-Ledger {
  $l = Read-JsonSafe $LedgerPath
  if (-not $l) {
    return [pscustomobject]@{ version = 1; consumers = [pscustomobject]@{} }
  }
  if (-not $l.PSObject.Properties.Name.Contains("consumers") -or -not $l.consumers) {
    $l | Add-Member -NotePropertyName consumers -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  return $l
}

function Get-ConsumerMap($Ledger, [string]$Name) {
  $prop = $Ledger.consumers.PSObject.Properties[$Name]
  if (-not $prop) { return $null }
  return $prop.Value
}

function Set-ConsumerEntry($Ledger, [string]$Name, [string]$Id, $Entry) {
  $prop = $Ledger.consumers.PSObject.Properties[$Name]
  if (-not $prop) {
    $Ledger.consumers | Add-Member -NotePropertyName $Name -NotePropertyValue ([pscustomobject]@{}) -Force
    $prop = $Ledger.consumers.PSObject.Properties[$Name]
  }
  $map = $prop.Value
  $map | Add-Member -NotePropertyName $Id -NotePropertyValue $Entry -Force
}

# 取任务正文：history[0].parts[*].text（不是 artifacts 里的固定回执）。
function Get-TaskBody($Task) {
  try {
    $parts = @($Task.history[0].parts)
    $texts = @()
    foreach ($p in $parts) { if ($p -and $p.text) { $texts += [string]$p.text } }
    return ($texts -join [Environment]::NewLine)
  } catch { return "" }
}

function Get-TaskState($Task) {
  try { if ($Task.status -and $Task.status.state) { return [string]$Task.status.state } } catch { }
  return "unknown"
}

function Get-ServiceUp([int]$Port) {
  $l = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $Port })
  return ($l.Count -gt 0)
}

# 把用户给的 id 解析成真实任务 id：允许唯一前缀。
# 桥接消息头部只显示 8 位前缀，直接拿去做 -Done 会记错键，这里兜住。
function Resolve-TaskId([string]$Given) {
  if ([string]::IsNullOrWhiteSpace($Given)) { return '' }
  if (Test-Path -LiteralPath (Join-Path $tasksDir ($Given + '.json'))) { return $Given }
  $hits = @(Get-ChildItem -LiteralPath $tasksDir -File -Filter ($Given + '*.json') -ErrorAction SilentlyContinue)
  if ($hits.Count -eq 1) { return $hits[0].BaseName }
  if ($hits.Count -gt 1) { return '@ambiguous' }
  return $Given
}

function Format-Body([string]$Body, [int]$Max) {
  if ($Body.Length -le $Max) { return $Body }
  return $Body.Substring(0, $Max) + [Environment]::NewLine + ("…(正文已截断，原长 " + $Body.Length + " 字符)")
}

$cfg = Read-JsonSafe $cfgPath
if (-not $cfg) {
  if ($Json) { '{"verdict":"no-config"}' } else { Write-Host "FAIL 读不到 state\config.json" }
  exit 2
}
$a2aPort = [int]$cfg.a2a.port
$ledger = Get-Ledger

# ---------- 迁移：把所有现存任务记为 done，建立基线 ----------
if ($Baseline) {
  $allFiles = @()
  if (Test-Path -LiteralPath $tasksDir) { $allFiles = @(Get-ChildItem -LiteralPath $tasksDir -File -Filter "*.json") }
  $now = (Get-Date).ToString("s")
  foreach ($f in $allFiles) {
    $entry = [pscustomobject]@{ state = "done"; at = $now; note = "migrated-baseline" }
    Set-ConsumerEntry $ledger $Consumer $f.BaseName $entry
  }
  Write-JsonAtomic $LedgerPath $ledger
  Write-Host ("OK 迁移完成：consumer=" + $Consumer + " 标记 " + $allFiles.Count + " 条为 done（基线）")
  exit 0
}

# ---------- 标记完成 / 失败 ----------
if ($Done -or $Fail) {
  $rawId = $Done
  $state = "done"
  if (-not $rawId) { $rawId = $Fail; $state = "done" }
  $id = Resolve-TaskId $rawId
  if ($id -eq "@ambiguous") { Write-Host ("FAIL id 前缀 " + $rawId + " 匹配到多条任务，请给更长的 id"); exit 6 }
  $map = Get-ConsumerMap $ledger $Consumer
  $prev = $null
  if ($map) { $p = $map.PSObject.Properties[$id]; if ($p) { $prev = $p.Value } }
  $entry = [pscustomobject]@{ state = $state; at = (Get-Date).ToString("s"); note = ($(if ($Fail) { "failed: " + $FailNote } else { "replied" })) }
  if ($prev -and $prev.PSObject.Properties.Name.Contains("taskTime")) { $entry | Add-Member -NotePropertyName taskTime -NotePropertyValue $prev.taskTime -Force }
  Set-ConsumerEntry $ledger $Consumer $id $entry
  Write-JsonAtomic $LedgerPath $ledger
  Write-Host ("OK task=" + $id + " -> " + $state)
  exit 0
}

# ---------- 主循环 ----------
$deadline = (Get-Date)
if ($TimeoutSec -gt 0) { $deadline = (Get-Date).AddSeconds($TimeoutSec) }

while ($true) {
  $map = Get-ConsumerMap $ledger $Consumer
  $files = @()
  if (Test-Path -LiteralPath $tasksDir) {
    $files = @(Get-ChildItem -LiteralPath $tasksDir -File -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc)
  }
  $fresh = @()
  $stale = @()
  $now = Get-Date
  foreach ($f in $files) {
    $id = $f.BaseName
    $e = $null
    if ($map) { $p = $map.PSObject.Properties[$id]; if ($p) { $e = $p.Value } }
    if (-not $e) { $fresh += $f; continue }
    $st = [string]$e.state
    if ($st -eq "delivered") {
      $at = $null
      try { if ($e.at) { $at = [datetime]$e.at } } catch { }
      if ($at -and (($now - $at).TotalMinutes -ge $StaleMinutes)) { $stale += $f }
    }
  }

  if ($fresh.Count -gt 0 -or $stale.Count -gt 0) {
    $out = @()
    foreach ($f in ($fresh + $stale)) {
      $task = Read-JsonSafe $f.FullName
      $body = ""
      if ($task) { $body = Get-TaskBody $task }
      $isStale = ($stale -contains $f)
      $out += [pscustomobject]@{
        id = $f.BaseName
        time = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        bytes = $f.Length
        state = $(if ($task) { Get-TaskState $task } else { "unreadable" })
        rereport = $isStale
        body = $body
      }
    }
    # 对端探测只为一行提示：消息已在本机磁盘上，对端此刻通不通不改变退出码。
    $peerWarn = ""
    $peerHost = ""
    $peerPort = $a2aPort
    try {
      if ($cfg.peer.a2aUrl) {
        $pu = [uri]$cfg.peer.a2aUrl
        $peerHost = $pu.Host
        if ($pu.Port -gt 0) { $peerPort = $pu.Port }
      }
    } catch { }
    if ($peerHost) {
      $tc = New-Object System.Net.Sockets.TcpClient
      $peerOk = $false
      try { $peerOk = ($tc.ConnectAsync($peerHost, $peerPort).Wait(800)) -and $tc.Connected } catch { $peerOk = $false } finally { $tc.Close() }
      if (-not $peerOk) { $peerWarn = "WARN peer unreachable (" + $peerHost + ":" + $peerPort + ")——本地消息不受影响" }
    }

    if (-not $Peek) {
      $nowStr = (Get-Date).ToString("s")
      foreach ($o in $out) {
        $prev = $null
        if ($map) { $p = $map.PSObject.Properties[$o.id]; if ($p) { $prev = $p.Value } }
        $entry = [pscustomobject]@{ state = "delivered"; at = $nowStr; taskTime = $o.time }
        if ($prev -and $prev.PSObject.Properties.Name.Contains("note")) { $entry | Add-Member -NotePropertyName note -NotePropertyValue $prev.note -Force }
        Set-ConsumerEntry $ledger $Consumer $o.id $entry
      }
      Write-JsonAtomic $LedgerPath $ledger
    }
    if ($Json) {
      ($out | ConvertTo-Json -Depth 6 -Compress)
    } else {
      if ($peerWarn) { Write-Host $peerWarn }
      Write-Host ("## [team-link] " + $out.Count + " 条待处理（consumer=" + $Consumer + "）")
      foreach ($o in $out) {
        $flag = ""
        if ($o.rereport) { $flag = "  << 上次读过但未确认完成，重报" }
        Write-Host ("### task=" + $o.id + "  落盘 " + $o.time + "  " + $o.bytes + "B  state=" + $o.state + $flag)
        if ($o.body) { Write-Host (Format-Body $o.body $MaxBodyChars) } else { Write-Host "(读不到正文：任务文件可能正在写入，下次会重试)" }
        Write-Host ""
      }
    }
    exit 0
  }

  if ($All) {
    if ($Json) { '[]' } else { Write-Host ("IDLE 无待处理（累计任务 " + $files.Count + " 条，consumer=" + $Consumer + "）") }
    exit 3
  }

  if ((Get-Date) -ge $deadline) {
    if (-not (Get-ServiceUp $a2aPort)) {
      if ($Json) { '{"verdict":"service-down"}' } else { Write-Host "FAIL 本机 A2A 服务没在监听（先跑 tools\start-lan.ps1）" }
      exit 2
    }
    if ($Json) { '{"verdict":"idle"}' } else { Write-Host "IDLE 无新消息" }
    exit 3
  }

  $remain = [int](([DateTime]$deadline - (Get-Date)).TotalSeconds)
  if ($remain -le 0) { continue }
  Start-Sleep -Seconds ([Math]::Min([Math]::Max(1, $PollSec), $remain))
}
