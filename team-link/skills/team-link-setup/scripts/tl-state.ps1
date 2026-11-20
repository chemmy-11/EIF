#requires -Version 5.1
<#
.SYNOPSIS
  只读诊断 team-link 的地址与通道状态，并直接回答「现在缺哪几步」。
.DESCRIPTION
  地址在系统里有四处，本脚本把四处一次性摆出来对比：
    1) profile cordis.patch.yml 的 team-link 块（GUI 面板改的就是这份，宿主启动时物化到 2）
    2) state\config.json（服务端与三个运维工具读的那份）
    3) LAN 服务的实际 bind（服务启动那一刻决定）
    4) 对端记录的你的地址（本机看不到，只能提示去确认）
  只读，不写任何文件、不重启任何东西。
.EXAMPLE
  powershell -NoProfile -File scripts\tl-state.ps1
.EXAMPLE
  powershell -NoProfile -File scripts\tl-state.ps1 -Bundle "C:\Users\me\.dsh\bundles\dsh-vivado\optional\team-link"
#>
[CmdletBinding()]
param(
  [string]$Bundle = '',
  [string]$Profile = 'desktop',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh')
)
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Bundle)) {
  $Bundle = Join-Path (Join-Path (Join-Path $DshHome 'bundles\dsh-vivado\optional') 'team-link') ''
  $Bundle = $Bundle.TrimEnd('\')
}
$cfgPath  = Join-Path $Bundle 'state\config.json'
$patchPath = Join-Path (Join-Path (Join-Path $DshHome 'profiles') $Profile) 'cordis.patch.yml'

function Write-Ok($m)   { Write-Host ('  PASS ' + $m) -ForegroundColor Green }
function Write-Bad($m)  { Write-Host ('  FAIL ' + $m) -ForegroundColor Red }
function Write-Warn2($m){ Write-Host ('  WARN ' + $m) -ForegroundColor Yellow }
function Write-Info($m) { Write-Host ('       ' + $m) }

# 读 JSON（PS 5.1 的 -Encoding UTF8 会吃掉 BOM）
function Read-Json([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try { return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json) } catch { return $null }
}

# 在 profile patch 里定位 team-link 块，返回块内 host 行
function Get-BlockHosts([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $lines = Get-Content -LiteralPath $Path -Encoding UTF8
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^-\s*id:\s*team-link\s*$') { $start = $i; break } }
  if ($start -lt 0) { return @() }
  $end = $lines.Count - 1
  for ($j = $start + 1; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^-\s*id:') { $end = $j - 1; break } }
  $hosts = @()
  for ($k = $start; $k -le $end; $k++) {
    if ($lines[$k] -match '^\s+host:\s*(\S+)\s*$') { $hosts += $Matches[1] }
  }
  return $hosts
}

Write-Host ''
Write-Host '==== team-link 地址与通道诊断（只读）====' -ForegroundColor Cyan
Write-Info ('bundle : ' + $Bundle)
Write-Info ('profile: ' + $patchPath)

Write-Host ''
Write-Host '-- 1) 本机当前网卡 --' -ForegroundColor Cyan
$wlan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.InterfaceAlias -match 'WLAN|Wi-Fi|无线' } | Select-Object -First 1
if (-not $wlan) {
  $wlan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.IPAddress -notmatch '^192\.168\.1\.' } |
    Select-Object -First 1
}
$localIp = if ($wlan) { $wlan.IPAddress } else { '' }
if ($localIp) {
  Write-Info ('网卡 ' + $wlan.InterfaceAlias + '  ' + $localIp + '/' + $wlan.PrefixLength)
  $prof = Get-NetConnectionProfile -InterfaceAlias $wlan.InterfaceAlias -ErrorAction SilentlyContinue
  if ($prof) { Write-Info ('网络类别 ' + $prof.NetworkCategory + '（Public 时入站默认被拦，但 node.exe 的既有规则通常是 Any，见 README）') }
} else {
  Write-Bad '找不到可用的非回环 IPv4 地址'
}

Write-Host ''
Write-Host '-- 2) 两份配置里的 host --' -ForegroundColor Cyan
$cfg = Read-Json $cfgPath
$cfgA2a = if ($cfg) { [string]$cfg.a2a.host } else { '' }
$cfgMcp = if ($cfg) { [string]$cfg.mcp.host } else { '' }
$blockHosts = Get-BlockHosts $patchPath
$profHost = if ($blockHosts.Count -gt 0) { [string]$blockHosts[0] } else { '' }
Write-Info ('state\config.json  a2a.host=' + $cfgA2a + '  mcp.host=' + $cfgMcp)
Write-Info ('profile patch      team-link 块 host 行数=' + $blockHosts.Count + '  首个=' + $profHost)
if ($cfg) {
  Write-Info ('role=' + $cfg.role + '  a2a.port=' + $cfg.a2a.port + '  mcp.port=' + $cfg.mcp.port)
  Write-Info ('peer.a2aUrl=' + $cfg.peer.a2aUrl)
  Write-Info ('peer.mcpUrl=' + $cfg.peer.mcpUrl)
} else {
  Write-Bad ('读不到 ' + $cfgPath)
}

Write-Host ''
Write-Host '-- 3) 服务实际 bind --' -ForegroundColor Cyan
$ports = @()
if ($cfg) { $ports += [int]$cfg.a2a.port; $ports += [int]$cfg.mcp.port } else { $ports = @(7310, 18790) }
$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in $ports })
if ($listeners.Count -eq 0) {
  Write-Bad ('端口 ' + ($ports -join ',') + ' 上没有监听 —— LAN 服务没起（重启后不会自启）')
} else {
  foreach ($l in $listeners) { Write-Info ('监听 ' + $l.LocalAddress + ':' + $l.LocalPort + ' pid=' + $l.OwningProcess) }
}

Write-Host ''
Write-Host '-- 4) token 存在性（只报存在，不打印值）--' -ForegroundColor Cyan
if ($cfg) {
  foreach ($slot in @(
    @{ n = 'a2a(入站)'; f = $cfg.a2a.tokenFile },
    @{ n = 'mcp(入站)'; f = $cfg.mcp.tokenFile },
    @{ n = 'peer-a2a(出站)'; f = $cfg.peer.a2a.tokenFile },
    @{ n = 'peer-mcp(出站)'; f = $cfg.peer.mcp.tokenFile }
  )) {
    $p = [string]$slot.f
    if ($p -and -not [System.IO.Path]::IsPathRooted($p)) {
      $c1 = Join-Path $Bundle $p; $c2 = Join-Path (Join-Path $Bundle 'state') $p
      $p = if (Test-Path -LiteralPath $c1) { $c1 } else { $c2 }
    }
    if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) {
      Write-Info ($slot.n.PadRight(16) + 'present(' + (Get-Item -LiteralPath $p).Length + 'B)')
    } else {
      Write-Warn2 ($slot.n.PadRight(16) + 'MISSING  ' + [string]$slot.f)
    }
  }
}

Write-Host ''
Write-Host '-- 5) 对端可达性 --' -ForegroundColor Cyan
if ($cfg -and $cfg.peer.a2aUrl) {
  try { $u = [uri]$cfg.peer.a2aUrl; $ph = $u.Host } catch { $ph = '' }
  if ($ph) {
    foreach ($probe in @(@{ n = 'a2a'; h = $ph; p = [int]$cfg.a2a.port }, @{ n = 'mcp'; h = $ph; p = [int]$cfg.mcp.port })) {
      $c = New-Object System.Net.Sockets.TcpClient
      try {
        $ok = $c.ConnectAsync($probe.h, $probe.p).Wait(1800)
        if ($ok -and $c.Connected) { Write-Ok ('对端 ' + $probe.h + ':' + $probe.p + ' TCP 可连') }
        else { Write-Bad ('对端 ' + $probe.h + ':' + $probe.p + ' TCP 不可连') }
      } catch { Write-Bad ('对端 ' + $probe.h + ':' + $probe.p + ' 探测异常') } finally { $c.Close() }
    }
    try {
      $cardUrl = ([string]$cfg.peer.a2aUrl).TrimEnd('/') + '/.well-known/agent.json'
      $r = Invoke-WebRequest -Uri $cardUrl -UseBasicParsing -TimeoutSec 8
      $card = $r.Content | ConvertFrom-Json
      Write-Ok ('对端 AgentCard HTTP ' + $r.StatusCode + '  name=' + $card.name)
    } catch { Write-Bad ('对端 AgentCard 不可取: ' + $_.Exception.Message.Split([char]10)[0]) }
  }
} else {
  Write-Warn2 'config.json 里 peer.a2aUrl 为空：对端未配置'
}

Write-Host ''
Write-Host '==== 结论：还缺哪几步 ====' -ForegroundColor Cyan
$need = @()
if (-not $localIp) { $need += '取不到本机 LAN 地址，先确认 WLAN 连着' }
if ($localIp -and $profHost -and ($profHost -ne $localIp)) { $need += ('① profile patch 里 host=' + $profHost + ' ≠ 当前 ' + $localIp + ' → 改它（GUI 面板或 tl-sync.ps1 -Apply）') }
if (-not $profHost) { $need += '① profile patch 里找不到 team-link 块或无 host → 检查插件行是否还在' }
if ($localIp -and $cfgA2a -and ($cfgA2a -ne $localIp)) { $need += ('② state\config.json host=' + $cfgA2a + ' ≠ 当前 ' + $localIp + ' → 宿主启动时会从 ① 重新物化，改完 ① 后重启宿主') }
if ($localIp -and $listeners.Count -gt 0) {
  $boundOnLocal = @($listeners | Where-Object { $_.LocalAddress -eq $localIp })
  if ($boundOnLocal.Count -lt $listeners.Count) { $need += '③ 服务绑的地址不是当前 LAN 地址 → start-lan.ps1 -Stop 再 start-lan.ps1' }
}
if ($localIp -and $listeners.Count -eq 0) { $need += '③ LAN 服务没起 → powershell -NoProfile -File tools\start-lan.ps1' }
$need += '④ 对端要把它记录的你的地址也改成 ' + $(if ($localIp) { $localIp } else { '<当前地址>' }) + '（本机看不到，需口头确认）'

if ($need.Count -eq 0) { Write-Ok '四处一致，通道就绪' }
else { foreach ($n in $need) { Write-Warn2 $n } }
Write-Host ''
