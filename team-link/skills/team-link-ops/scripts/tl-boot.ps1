#requires -Version 5.1
<#
.SYNOPSIS
  开工 / 重启后一条命令把协作通道拉起来并自检：起 LAN 服务 → 验监听 → 探对端 → 钉选投送会话。

.DESCRIPTION
  为什么要有它：**DSH 重启后 LAN 服务不会自启**（服务是脱离宿主的长驻进程），而「已经加载
  team-link-ops 技能」并不等于「通道是通的」。这件事原来只写在另一个技能里，交接时一漏就出现
  「两边都以为通道好的，其实本机根本没监听」。

  本脚本把 ops 开工需要的四步合成一条，且**幂等**：
    1) 服务已在正确地址监听 → 跳过启动，不打断正在跑的任务
    2) 没监听 / 地址不对(换网段) / 指定 -Force → start-lan.ps1 -Stop 再 start-lan.ps1
    3) 本机 AgentCard 200 + 对端可达（有 pc1_pc2_ping.ps1 才探，缺就 SKIP）
    4) 把当前会话钉成投送目标（tl-pin.ps1；-NoPin 可跳过）

  地址权威仍是 profile 的 ①（config.json 由宿主从 ① 物化）：本脚本只做「按现有配置把服务拉起来」；
  配置里的 host 与当前 WLAN 不一致时**不猜、不改配置**，直接报 ④ 并让你走 team-link-setup 的
  tl-sync.ps1 -Apply（改配置属于 setup 的职责）。

  退出码：
    0 = 通道就绪（钉选成功或按 -NoPin 跳过）
    2 = 服务没起来（看 start-lan 的日志）
    3 = 通道就绪但钉选失败（拿不到 DSH_SESSION_ID / 写盘失败）
    4 = 配置地址与当前网卡不一致（转 team-link-setup：tl-state.ps1 定位 + tl-sync.ps1 -Apply）

.PARAMETER CheckOnly
  只看不修：不启动服务、不重启服务、不钉选（诊断 / 交接前确认用）。

.PARAMETER NoPin
  跳过钉选（不想改动当前投送目标时）。

.PARAMETER Force
  即使已在监听也重启服务（换网段后进程还在旧地址的场合）。

.PARAMETER SkipPeer
  跳过对端可达性探测（对端关机 / 只想验本机时）。

.EXAMPLE
  powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-boot.ps1 -Bundle <TL>

.EXAMPLE
  powershell -NoProfile -File <TL>\skills\team-link-ops\scripts\tl-boot.ps1 -Bundle <TL> -CheckOnly
#>
[CmdletBinding()]
param(
  [string]$Bundle = '',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [string]$Source = 'skill-ops',
  [string]$PinSessionId = '',
  [int]$WaitSec = 15,
  [switch]$CheckOnly,
  [switch]$NoPin,
  [switch]$Force,
  [switch]$SkipPeer,
  [switch]$Json
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Bundle)) { $Bundle = Join-Path $DshHome 'bundles\dsh-vivado\optional\team-link' }
$cfgPath = Join-Path $Bundle 'state\config.json'
$scriptsDir = Join-Path $Bundle 'skills\team-link-ops\scripts'
$toolsDir = Join-Path $Bundle 'tools'

function Write-Ok($m)    { Write-Host ('  PASS ' + $m) -ForegroundColor Green }
function Write-Bad($m)   { Write-Host ('  FAIL ' + $m) -ForegroundColor Red }
function Write-Warn2($m) { Write-Host ('  WARN ' + $m) -ForegroundColor Yellow }
function Write-Info($m)  { Write-Host ('       ' + $m) }
function Write-Step($m)  { Write-Host ''; Write-Host ('== ' + $m + ' ==') -ForegroundColor Cyan }

function Read-JsonSafe([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try { return ((Get-Content -Raw -Encoding UTF8 -LiteralPath $Path) -replace '^\uFEFF', '') | ConvertFrom-Json } catch { return $null }
}

# 本机 LAN 地址：优先 WLAN 网卡；没有 WLAN 就取第一条非回环 IPv4。
function Get-LanIp {
  $ips = @()
  try {
    $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
      Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' })
  } catch { $ips = @() }
  if ($ips.Count -eq 0) { return '' }
  $wlan = @($ips | Where-Object { $_.InterfaceAlias -like '*WLAN*' })
  if ($wlan.Count -gt 0) { return [string]$wlan[0].IPAddress }
  return [string]$ips[0].IPAddress
}

function Get-Listeners([int]$Port) {
  try {
    return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
  } catch { return @() }
}

$cfg = Read-JsonSafe $cfgPath
if (-not $cfg) {
  Write-Bad ('读不到 state\config.json：' + $cfgPath)
  Write-Info '宿主没起过 / 没物化配置 → 先启动 DSH，再跑本脚本'
  exit 4
}

$role = [string]$cfg.role
$a2aHost = ''
$mcpHost = ''
$a2aPort = 7310
$mcpPort = 18790
if ($cfg.a2a) { $a2aHost = [string]$cfg.a2a.host; if ($cfg.a2a.port) { $a2aPort = [int]$cfg.a2a.port } }
if ($cfg.mcp) { $mcpHost = [string]$cfg.mcp.host; if ($cfg.mcp.port) { $mcpPort = [int]$cfg.mcp.port } }
$lanIp = Get-LanIp

Write-Host ('[team-link] tl-boot  role=' + $role + '  bundle=' + $Bundle)
Write-Host ('  LAN=' + $(if ($lanIp) { $lanIp } else { '<取不到>' }) + '  config a2a=' + $a2aHost + ':' + $a2aPort + '  mcp=' + $mcpHost + ':' + $mcpPort + $(if ($CheckOnly) { '  [CheckOnly]' } else { '' })) -ForegroundColor DarkGray

# ---------- 1) 配置地址 vs 当前网卡 ----------
Write-Step '1/4 地址一致性'
$addrOk = $true
if (-not $lanIp) {
  Write-Bad '取不到本机 LAN 地址（WLAN 没连？）'
  $addrOk = $false
} elseif ($a2aHost -and ($a2aHost -ne $lanIp)) {
  Write-Bad ('config a2a.host=' + $a2aHost + ' ≠ 当前 LAN ' + $lanIp)
  Write-Info '换过网段：先启动宿主（让 ① 物化到 config.json）→ 仍不一致就用 team-link-setup 的 tl-sync.ps1 -Apply'
  $addrOk = $false
} else {
  Write-Ok ('config 地址与当前网卡一致：' + $lanIp)
}

# ---------- 2) LAN 服务 ----------
Write-Step '2/4 LAN 服务（重启后不自启）'
$needStart = $false
if (-not $addrOk) {
  Write-Warn2 '地址不一致：不启动服务（按错地址起来等于没起）'
  $needStart = $false
} else {
  foreach ($svc in @(
    [pscustomobject]@{ name = 'a2a'; host = $a2aHost; port = $a2aPort },
    [pscustomobject]@{ name = 'mcp'; host = $mcpHost; port = $mcpPort })) {
    $ls = @(Get-Listeners $svc.port)
    $onAddr = @($ls | Where-Object { $_.LocalAddress -eq $svc.host })
    if ($ls.Count -eq 0) {
      Write-Warn2 ($svc.name + ' 没监听 ' + $svc.host + ':' + $svc.port)
      $needStart = $true
    } elseif ($onAddr.Count -eq 0) {
      Write-Warn2 ($svc.name + ' 监听了但不在 ' + $svc.host + '（实际 ' + (($ls | ForEach-Object { $_.LocalAddress }) -join ',') + '）')
      $needStart = $true
    } else {
      Write-Ok ($svc.name + ' 已监听 ' + $svc.host + ':' + $svc.port)
    }
  }
  if ($Force -and -not $CheckOnly) { Write-Info '按 -Force 强制重启服务'; $needStart = $true }

  if ($needStart -and $CheckOnly) {
    Write-Warn2 'CheckOnly：需要启动服务，但本次不启动'
  } elseif ($needStart) {
    $startLan = Join-Path $toolsDir 'start-lan.ps1'
    if (-not (Test-Path -LiteralPath $startLan)) {
      Write-Bad ('找不到 ' + $startLan)
      $addrOk = $false
    } else {
      $hasListener = @((Get-Listeners $a2aPort).Count + (Get-Listeners $mcpPort).Count) -gt 0
      if ($hasListener -or $Force) {
        Write-Info '先 start-lan.ps1 -Stop'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $startLan -Stop -ConfigPath $cfgPath 2>&1 | ForEach-Object { Write-Info ('  ' + $_) }
        Start-Sleep -Milliseconds 500
      }
      Write-Info 'start-lan.ps1（绑定 ' + $a2aHost + ':' + $a2aPort + ' / ' + $mcpHost + ':' + $mcpPort + '）'
      & powershell -NoProfile -ExecutionPolicy Bypass -File $startLan -ConfigPath $cfgPath 2>&1 | ForEach-Object { Write-Info ('  ' + $_) }
      $deadline = (Get-Date).AddSeconds([Math]::Max(5, $WaitSec))
      $up = $false
      while ((Get-Date) -lt $deadline) {
        $a = @(Get-Listeners $a2aPort | Where-Object { $_.LocalAddress -eq $a2aHost })
        $m = @(Get-Listeners $mcpPort | Where-Object { $_.LocalAddress -eq $mcpHost })
        if ($a.Count -gt 0 -and $m.Count -gt 0) { $up = $true; break }
        Start-Sleep -Milliseconds 500
      }
      if ($up) { Write-Ok ('服务已起来：' + $a2aHost + ':' + $a2aPort + ' / ' + $mcpHost + ':' + $mcpPort) }
      else {
        Write-Bad ('启动后 ' + $WaitSec + ' 秒仍没监听：看 ' + (Join-Path $Bundle 'logs\') + ' 下 a2a/mcp 日志')
        $addrOk = $false
      }
    }
  }
}

$svcOk = $addrOk
if ($svcOk) {
  foreach ($svc in @(
    [pscustomobject]@{ name = 'a2a'; host = $a2aHost; port = $a2aPort },
    [pscustomobject]@{ name = 'mcp'; host = $mcpHost; port = $mcpPort })) {
    if (@(Get-Listeners $svc.port | Where-Object { $_.LocalAddress -eq $svc.host }).Count -eq 0) { $svcOk = $false }
  }
}

# ---------- 3) 本机 AgentCard + 对端 ----------
Write-Step '3/4 本机 AgentCard / 对端可达'
if (-not $svcOk) {
  Write-Warn2 '服务没起，跳过探测'
} else {
  $cardOk = $false
  try {
    $r = Invoke-WebRequest -Uri ('http://' + $a2aHost + ':' + $a2aPort + '/.well-known/agent.json') -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -eq 200) {
      $cardOk = $true
      $cardName = ''
      try { $cardName = [string](($r.Content | ConvertFrom-Json).name) } catch { $cardName = '' }
      Write-Ok ('AgentCard 200' + $(if ($cardName) { '  name=' + $cardName } else { '' }))
    } else { Write-Bad ('AgentCard 返回 ' + $r.StatusCode) }
  } catch { Write-Bad ('AgentCard 取不到：' + $_.Exception.Message.Split([char]10)[0]) }
  if (-not $cardOk) { $svcOk = $false }

  if ($SkipPeer) {
    Write-Info '按 -SkipPeer 跳过对端探测'
  } else {
    $ping = Join-Path $toolsDir 'pc1_pc2_ping.ps1'
    if (-not (Test-Path -LiteralPath $ping)) {
      Write-Warn2 '没有 tools\pc1_pc2_ping.ps1，跳过对端探测'
    } else {
      $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $ping 2>&1
      $code = $LASTEXITCODE
      $line = @($out | Where-Object { $_ -match 'name=' } | Select-Object -Last 1)
      if ($code -eq 0) { Write-Ok ('对端可达 ' + $(if ($line.Count -gt 0) { $line[0] } else { '' })) }
      else { Write-Warn2 ('对端不可达（exit=' + $code + '）——本机通道不受影响，对端开机/换网段则等它回复') }
    }
  }
}

# ---------- 4) 钉选 ----------
Write-Step '4/4 钉选投送会话'
$pinOk = $true
$pinNote = ''
if ($NoPin) {
  Write-Info '按 -NoPin 跳过钉选'
} elseif ($CheckOnly) {
  $showPin = Join-Path $scriptsDir 'tl-pin.ps1'
  if (Test-Path -LiteralPath $showPin) {
    $cur = & powershell -NoProfile -ExecutionPolicy Bypass -File $showPin -Bundle $Bundle -Show 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Ok ('当前钉选：' + (($cur -join ' ') -replace '\s+', ' ')) }
    else { Write-Warn2 '当前没有钉选（桥按「最近活跃的根会话」投递）' }
  }
} else {
  $pinScript = Join-Path $scriptsDir 'tl-pin.ps1'
  if (-not (Test-Path -LiteralPath $pinScript)) {
    Write-Warn2 '没有 tl-pin.ps1（0.3.4 之前的包），跳过钉选'
  } else {
    $pinArgs = @('-Bundle', $Bundle, '-Source', $Source)
    if (-not [string]::IsNullOrWhiteSpace($PinSessionId)) { $pinArgs += @('-SessionId', $PinSessionId) }
    $pinOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $pinScript @pinArgs 2>&1
    $pinCode = $LASTEXITCODE
    $pinOut | ForEach-Object { Write-Info ('  ' + $_) }
    if ($pinCode -eq 0) { Write-Ok '已钉选本会话为投送目标' }
    elseif ($pinCode -eq 4) { Write-Warn2 '拿不到 DSH_SESSION_ID（不在 DSH 会话里跑？）——本轮退回轮询收件'; $pinOk = $false }
    else { Write-Bad ('钉选失败 exit=' + $pinCode); $pinOk = $false }
  }
}

# ---------- 结论 ----------
Write-Step '结论'
if (-not $addrOk -or -not $svcOk) {
  Write-Bad '通道未就绪：先修上面的 FAIL，再看 state\inbox-bridge.log 与 logs\ 下服务日志'
  if (-not $addrOk) { Write-Info '地址/配置类问题属于 setup：team-link-setup 的 tl-state.ps1（只读定位）+ tl-sync.ps1 -Apply（写配置）' }
  if ($Json) { Write-Output '{"verdict":"down"}' }
  exit 2
}
Write-Ok ('通道就绪（本机监听 + AgentCard' + $(if (-not $SkipPeer) { ' + 对端探测' } else { '' }) + '）')
if (-not $pinOk) {
  if ($Json) { Write-Output '{"verdict":"up-unpinned"}' }
  exit 3
}
Write-Info '收消息不用轮询：桥会把对端消息推进本会话输入（判据：state\inbox-bridge.log 里 pin: hit / pushed: 行）'
if ($Json) { Write-Output '{"verdict":"ready"}' }
exit 0
