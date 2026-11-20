#requires -Version 5.1
<#
.SYNOPSIS
  把 team-link 的本机地址同步到「profile patch」与「state\config.json」两处（幂等、先计划后落盘）。
.DESCRIPTION
  只做两件写操作，别的什么都不碰：
    1) profile cordis.patch.yml 的 team-link 块内 host 行（通常 2 行：a2a / mcp）
    2) state\config.json 的 a2a.host / mcp.host（给了 -PeerHost 时同时写 peer.*Url）
  默认是**只打印计划**；加 -Apply 才写盘，写前备份、写后回读校验。
  本脚本**不重启**任何东西：写完会打印接下来该跑的两条命令。
.PARAMETER HostIp
  本机要绑的 LAN 地址。缺省自动取 WLAN 当前地址。
.PARAMETER PeerHost
  对端地址（可省）。给了就同时更新 peer.a2aUrl / peer.mcpUrl。
.PARAMETER Apply
  真正落盘。不加就是 dry-run。
.EXAMPLE
  powershell -NoProfile -File scripts\tl-sync.ps1
.EXAMPLE
  powershell -NoProfile -File scripts\tl-sync.ps1 -Apply -PeerHost 10.194.13.246
#>
[CmdletBinding()]
param(
  [string]$Bundle = '',
  [ValidateSet('', 'pc1', 'pc2')][string]$Role = '',
  [string]$HostIp = '',
  [string]$PeerHost = '',
  [string]$Profile = 'desktop',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Bundle)) {
  $Bundle = Join-Path $DshHome 'bundles\dsh-vivado\optional\team-link'
}
$cfgPath   = Join-Path $Bundle 'state\config.json'
$patchPath = Join-Path (Join-Path (Join-Path $DshHome 'profiles') $Profile) 'cordis.patch.yml'
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Section($m) { Write-Host ""; Write-Host ("== " + $m) -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host ("  PASS " + $m) -ForegroundColor Green }
function Write-Bad($m)  { Write-Host ("  FAIL " + $m) -ForegroundColor Red }
function Write-Warn2($m){ Write-Host ("  WARN " + $m) -ForegroundColor Yellow }
function Write-Info($m) { Write-Host ("       " + $m) }
function Write-Plan($m) { Write-Host ("  PLAN " + $m) -ForegroundColor Magenta }
function Write-Done($m) { Write-Host ("  DONE " + $m) -ForegroundColor Green }

function Read-Json([string]$Path) {
  $raw = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
  return (($raw -replace '^\uFEFF', '') | ConvertFrom-Json)
}

function Get-BlockRange([string[]]$Lines) {
  $start = -1
  for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^-\s*id:\s*team-link\s*$') { $start = $i; break } }
  if ($start -lt 0) { return $null }
  $end = $Lines.Count - 1
  for ($j = $start + 1; $j -lt $Lines.Count; $j++) { if ($Lines[$j] -match '^-\s*id:') { $end = $j - 1; break } }
  return [pscustomobject]@{ Start = $start; End = $end }
}

Write-Section '0) 目标值'
if ([string]::IsNullOrWhiteSpace($HostIp)) {
  $w = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -match 'WLAN|Wi-Fi|无线' } | Select-Object -First 1
  if (-not $w) { Write-Bad '取不到 WLAN 地址：显式传 -HostIp <ip>'; exit 3 }
  $HostIp = $w.IPAddress
  Write-Info ('自动检测网卡 ' + $w.InterfaceAlias + ' -> ' + $HostIp + '/' + $w.PrefixLength)
} else { Write-Info ('显式指定 -> ' + $HostIp) }
if ($HostIp -match '^(127\.|169\.254\.)') { Write-Bad ('拒绝把回环/链路本地地址写进配置: ' + $HostIp); exit 4 }
if ($HostIp -match '^192\.168\.1\.') { Write-Bad '192.168.1.0/24 是两板私有链路（同 IP/同 MAC），禁止用作 PC 协作地址'; exit 4 }
if (-not (Test-Path -LiteralPath $cfgPath)) { Write-Bad ("找不到 " + $cfgPath); exit 3 }
if (-not (Test-Path -LiteralPath $patchPath)) { Write-Bad ("找不到 profile patch: " + $patchPath); exit 3 }

$cfg = Read-Json $cfgPath
$patchLines = @(Get-Content -LiteralPath $patchPath -Encoding UTF8)
$range = Get-BlockRange $patchLines
if (-not $range) { Write-Bad 'profile patch 里找不到 team-link 块（形如 - id: team-link）：插件行可能没装，先跑 install.ps1'; exit 3 }

Write-Section '1) 计划（当前 -> 目标）'
$plan = @()
$blockHostLines = @()
for ($k = $range.Start; $k -le $range.End; $k++) { if ($patchLines[$k] -match '^\s+host:') { $blockHostLines += $k } }
Write-Info ('profile patch 块内 host 行: ' + $blockHostLines.Count + ' 行（行号 ' + (($blockHostLines | ForEach-Object { $_ + 1 }) -join ',') + '）')
foreach ($k in $blockHostLines) {
  $cur = ([string]$patchLines[$k]).Trim() -replace '^host:\s*', ''
  if ($cur -ne $HostIp) { $plan += ('profile 第 ' + ($k + 1) + ' 行: ' + $cur + ' -> ' + $HostIp) }
}
if ([string]$cfg.a2a.host -ne $HostIp) { $plan += ('config.json a2a.host: ' + $cfg.a2a.host + ' -> ' + $HostIp) }
if ([string]$cfg.mcp.host -ne $HostIp) { $plan += ('config.json mcp.host: ' + $cfg.mcp.host + ' -> ' + $HostIp) }
if ($Role -and ([string]$cfg.role -ne $Role)) { $plan += ('config.json role: ' + $cfg.role + ' -> ' + $Role) }
if ($PeerHost) {
  $newA2a = 'http://' + $PeerHost + ':' + $cfg.a2a.port + '/'
  $newMcp = 'http://' + $PeerHost + ':' + $cfg.mcp.port + '/mcp'
  if ([string]$cfg.peer.a2aUrl -ne $newA2a) { $plan += ('peer.a2aUrl: ' + $cfg.peer.a2aUrl + ' -> ' + $newA2a) }
  if ([string]$cfg.peer.mcpUrl -ne $newMcp) { $plan += ('peer.mcpUrl: ' + $cfg.peer.mcpUrl + ' -> ' + $newMcp) }
}
if ($plan.Count -eq 0) { Write-Ok '两处都已是目标值，无需改动' }
else { foreach ($p in $plan) { Write-Plan $p } }

if (-not $Apply) {
  Write-Section '2) 未加 -Apply：只出计划'
  Write-Info '确认无误后加 -Apply 落盘'
  exit 0
}

Write-Section '2) 落盘'
$patchBak = $patchPath + '.bak-tlsync-' + $stamp
$cfgBak   = $cfgPath + '.bak-tlsync-' + $stamp
Copy-Item -LiteralPath $patchPath -Destination $patchBak -Force
Copy-Item -LiteralPath $cfgPath -Destination $cfgBak -Force
Write-Info ('备份: ' + (Split-Path $patchBak -Leaf) + ' / ' + (Split-Path $cfgBak -Leaf))

$newLines = @($patchLines)
foreach ($k in $blockHostLines) {
  $indent = ([regex]::Match([string]$newLines[$k], '^\s+')).Value
  $newLines[$k] = $indent + 'host: ' + $HostIp
}
[System.IO.File]::WriteAllLines($patchPath, $newLines, (New-Object System.Text.UTF8Encoding($false)))
Write-Done ('profile patch 已写 ' + $blockHostLines.Count + ' 行')

$cfg.a2a.host = $HostIp
$cfg.mcp.host = $HostIp
if ($Role) { $cfg.role = $Role; $cfg.machine = $Role.ToUpper() }
if ($PeerHost) {
  $cfg.peer.a2aUrl = 'http://' + $PeerHost + ':' + $cfg.a2a.port + '/'
  $cfg.peer.mcpUrl = 'http://' + $PeerHost + ':' + $cfg.mcp.port + '/mcp'
}
[System.IO.File]::WriteAllText($cfgPath, (($cfg | ConvertTo-Json -Depth 20) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
Write-Done 'config.json 已写'

Write-Section '3) 回读校验'
$back = @(Get-Content -LiteralPath $patchPath -Encoding UTF8)
$range2 = Get-BlockRange $back
$okPatch = $true
for ($k = $range2.Start; $k -le $range2.End; $k++) { if ($back[$k] -match '^\s+host:\s*(\S+)\s*$' -and $Matches[1] -ne $HostIp) { $okPatch = $false } }
$cfg2 = Read-Json $cfgPath
if ($okPatch -and [string]$cfg2.a2a.host -eq $HostIp -and [string]$cfg2.mcp.host -eq $HostIp) { Write-Ok "两处回读一致" }
else {
  Write-Bad ("回读不一致：patch=" + $okPatch + " cfg.a2a=" + $cfg2.a2a.host + " cfg.mcp=" + $cfg2.mcp.host)
  Write-Info ("回滚: Copy-Item '" + $patchBak + "' '" + $patchPath + "' -Force")
  exit 5
}

Write-Section '4) 还没做完的两步（本脚本故意不做）'
Write-Host '  1) 重启宿主（profile patch 只在宿主启动时物化到 config.json；不重启则下次启动会覆盖回旧地址）'
Write-Host '  2) 重起 LAN 服务（服务在启动那一刻绑地址，换地址必须重绑）'
Write-Host ('     powershell -NoProfile -File "' + (Join-Path $Bundle 'tools\start-lan.ps1') + '" -Stop')
Write-Host ('     powershell -NoProfile -File "' + (Join-Path $Bundle 'tools\start-lan.ps1') + '"')
Write-Host '  3) 把本机地址告诉对端（对端也要跑一遍同一步）'
Write-Host ('     对端应填: a2a=http://' + $HostIp + ':' + $cfg.a2a.port + '/  mcp=http://' + $HostIp + ':' + $cfg.mcp.port + '/mcp')
Write-Host ''
exit 0
