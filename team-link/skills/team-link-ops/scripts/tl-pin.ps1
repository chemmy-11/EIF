#requires -Version 5.1
<#
.SYNOPSIS
  把「当前会话」锁定为 team-link 的投送目标（钉选），或查看 / 清除钉选。

.DESCRIPTION
  为什么需要：宿主的收件箱桥按「最近活跃的根会话」挑投递目标。PC1 同时开着多个会话时，
  对端消息会投给刚说过话的那个会话，而不是真正在等消息的任务会话（实测：消息投进别的会话）。

  做法：技能一加载就跑本脚本，把 $env:DSH_SESSION_ID 写进 state\pinned-session.json；
  桥优先投给被钉选的会话，钉选的会话关掉了才回退旧逻辑。

  幂等：同一会话重复跑只是刷新时间戳，不会产生第二条记录。

  退出码：
    0 = 已钉选（或 -Show 读到了 / -Clear 已清）
    3 = -Show 但当前没有钉选
    4 = 拿不到会话 id（没注入 DSH_SESSION_ID 且没传 -SessionId）
    1 = 写盘失败

.EXAMPLE
  powershell -NoProfile -File scripts\tl-pin.ps1 -Bundle <TL> -Source skill-setup

.EXAMPLE
  powershell -NoProfile -File scripts\tl-pin.ps1 -Bundle <TL> -Show

.EXAMPLE
  powershell -NoProfile -File scripts\tl-pin.ps1 -Bundle <TL> -Clear
#>
[CmdletBinding()]
param(
  [string]$Bundle = '',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [string]$SessionId = '',
  [string]$Source = 'skill',
  [string]$Note = '',
  [switch]$Show,
  [switch]$Clear,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Bundle)) { $Bundle = Join-Path $DshHome 'bundles\dsh-vivado\optional\team-link' }
$pinPath = Join-Path $Bundle 'state\pinned-session.json'

function Read-PinFile {
  if (-not (Test-Path -LiteralPath $pinPath)) { return $null }
  try {
    $txt = Get-Content -Raw -Encoding UTF8 -LiteralPath $pinPath
    return (($txt -replace '^\uFEFF', '') | ConvertFrom-Json)
  } catch { return $null }
}

function Write-PinFile($Obj) {
  $dir = Split-Path -Parent $pinPath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = $pinPath + '.tmp-' + $PID
  $outText = ($Obj | ConvertTo-Json -Depth 8)
  [System.IO.File]::WriteAllText($tmp, ($outText + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
  if (Test-Path -LiteralPath $pinPath) { Remove-Item -LiteralPath $pinPath -Force }
  Move-Item -LiteralPath $tmp -Destination $pinPath -Force
}

# ---------- -Clear ----------
if ($Clear) {
  if (Test-Path -LiteralPath $pinPath) {
    Remove-Item -LiteralPath $pinPath -Force
    if ($Json) { Write-Output '{"pin":"cleared"}' } else { Write-Host 'PASS 已清除投送会话钉选（桥回退到「最近活跃的根会话」）' }
    exit 0
  }
  if ($Json) { Write-Output '{"pin":"absent"}' } else { Write-Host 'INFO 本来就没有钉选文件，无需清除' }
  exit 0
}

# ---------- -Show ----------
if ($Show) {
  $cur = Read-PinFile
  if (-not $cur -or [string]::IsNullOrWhiteSpace([string]$cur.sessionId)) {
    if ($Json) { Write-Output '{"pin":"none"}' } else { Write-Host 'INFO 当前没有钉选：桥按「最近活跃的根会话」投递' }
    exit 3
  }
  if ($Json) {
    ($cur | ConvertTo-Json -Depth 8 -Compress)
  } else {
    Write-Host ('PIN ' + $cur.sessionId)
    Write-Host ('    source=' + [string]$cur.source + '  at=' + [string]$cur.at + '  host=' + [string]$cur.host)
    if ($cur.note) { Write-Host ('    note=' + [string]$cur.note) }
  }
  exit 0
}

# ---------- 钉选 ----------
$sid = $SessionId
if ([string]::IsNullOrWhiteSpace($sid)) { $sid = [string]$env:DSH_SESSION_ID }
if ([string]::IsNullOrWhiteSpace($sid)) {
  if ($Json) { Write-Output '{"pin":"no-session-id"}' } else {
    Write-Host 'FAIL 拿不到会话 id：本机没有注入 DSH_SESSION_ID，也没传 -SessionId' -ForegroundColor Red
    Write-Host '     在 DSH 会话里跑（宿主 pwsh 会注入 DSH_SESSION_ID），或显式 -SessionId session-xxxx'
  }
  exit 4
}
$sid = $sid.Trim()

$prev = Read-PinFile
$wasSame = ($false)
if ($prev -and ([string]$prev.sessionId -eq $sid)) { $wasSame = $true }

$pinObj = [pscustomobject]@{
  version   = 1
  sessionId = $sid
  at        = (Get-Date).ToString('o')
  source    = $Source
  host      = [string]$env:COMPUTERNAME
  profile   = [string]$env:DSH_PROFILE
  note      = $Note
}

try {
  Write-PinFile $pinObj
} catch {
  Write-Host ('FAIL 写钉选文件失败: ' + $_.Exception.Message.Split([char]10)[0]) -ForegroundColor Red
  exit 1
}

# 回读校验：写进去的和想写的必须是同一个会话（防编码/转义问题静默写坏）。
$back = Read-PinFile
if (-not $back -or ([string]$back.sessionId -ne $sid)) {
  Write-Host 'FAIL 回读校验失败：钉选文件里的 sessionId 与预期不一致' -ForegroundColor Red
  exit 1
}

if ($Json) {
  ($back | ConvertTo-Json -Depth 8 -Compress)
} else {
  $suffix = ''
  if ($wasSame) { $suffix = '（同一会话重钉，仅刷新时间戳）' }
  Write-Host ('PASS 已锁定投送会话 ' + $sid + $suffix) -ForegroundColor Green
  Write-Host '     宿主收件箱桥会把对端消息投给这个会话；该会话关掉后自动回退最近活跃。'
  Write-Host ('     查看: tl-pin.ps1 -Bundle ' + $Bundle + ' -Show    清除: ... -Clear')
}
exit 0
