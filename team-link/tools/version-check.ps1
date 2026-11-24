#requires -Version 5.1
<#
.SYNOPSIS
  注册 mcp-team-link 之前，核对「profile 里的 dsh-mcp-client」与「当前 dsh 运行时」是否兼容。
.DESCRIPTION
  宿主启动时对 profile 里的插件做版本兼容闸门。不兼容的 mcp-client 行会被禁用；在 nightly 版本上
  表现为**整个宿主起不来**（旧版只是「工具面消失」）。这类故障重装程序、清用户数据都无效——
  闸门读的是 ~/.dsh 的 profile 层。

  判据来自 mcp-client 自己的 package.json：它把内部包（dsh-tools / dsh-llm / cordis …）钉成
  **精确版本**。运行时 dsh 与这些钉版不一致，就是闸门要拦的组合。

  只读：不写任何文件。
  退出码：0=兼容（或有豁免）；1=不兼容且无豁免（调用方应中止注册）；3=查不到（调用方自行决定）。
.PARAMETER Profile
  profile 名，默认 desktop。
.PARAMETER InstallRoot
  DSH 安装根目录（含 Uninstall *.exe）。缺省自动探测。
.PARAMETER DshVersion
  显式指定运行时版本，覆盖自动探测（便于演练换版场景）。
.EXAMPLE
  powershell -NoProfile -File tools\version-check.ps1 -Profile desktop
.EXAMPLE
  powershell -NoProfile -File tools\version-check.ps1 -DshVersion 0.2.3-alpha.2
#>
[CmdletBinding()]
param(
  [string]$Profile = 'desktop',
  [string]$DshHome = (Join-Path $env:USERPROFILE '.dsh'),
  [string]$InstallRoot = '',
  [string]$DshVersion = ''
)
$ErrorActionPreference = 'Stop'

function Write-Info($m)  { Write-Host ("  " + $m) }
function Write-Ok($m)    { Write-Host ("  PASS " + $m) -ForegroundColor Green }
function Write-Bad($m)   { Write-Host ("  FAIL " + $m) -ForegroundColor Red }
function Write-Warn2($m) { Write-Host ("  WARN " + $m) -ForegroundColor Yellow }

function Read-JsonSafe([string]$Path) {
  try {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return ((Get-Content -Raw -Encoding UTF8 -LiteralPath $Path) -replace '^\uFEFF', '') | ConvertFrom-Json
  } catch { return $null }
}

# ---------- 1) 运行时版本 ----------
# 用卸载器的 ProductVersion：它带预发布号（0.2.2-rc.5），主 exe 的只有 0.2.2.0。
if (-not $DshVersion) { $DshVersion = $env:DSH_VERSION }
if (-not $DshVersion) {
  $roots = @()
  if ($InstallRoot) { $roots += $InstallRoot }
  $cands = @('D:\dsh')
  $cands += (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness')
  $cands += (Join-Path $env:ProgramFiles 'DeepSeek Harness')
  foreach ($c in $cands) { if ($c -and (Test-Path -LiteralPath $c)) { $roots += $c } }
  foreach ($r in $roots) {
    $exe = @(Get-ChildItem -LiteralPath $r -Filter 'Uninstall*Harness*.exe' -File -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ($exe -and $exe.VersionInfo.ProductVersion) { $DshVersion = [string]$exe.VersionInfo.ProductVersion; break }
  }
}
if ($DshVersion) { Write-Info ('运行时 dsh      : ' + $DshVersion) } else { Write-Info '运行时 dsh      : (未知)' }

# ---------- 2) profile 里的 mcp-client ----------
$profDir = Join-Path (Join-Path $DshHome 'profiles') $Profile
$mc = Read-JsonSafe (Join-Path $profDir 'node_modules\@deepseek-ai\dsh-mcp-client\package.json')
if (-not $mc) {
  Write-Warn2 'profile 里没有 @deepseek-ai/dsh-mcp-client（跳过注册前预检）'
  exit 3
}
$mcVersion = [string]$mc.version
Write-Info ('profile mcp-client: ' + $mcVersion)

# 收集 @deepseek-ai/* 的 peer，分成「精确钉版」与「范围」两类。
$pins = @()
$ranges = @()
if ($mc.peerDependencies) {
  foreach ($p in $mc.peerDependencies.PSObject.Properties) {
    if ($p.Name -notlike '@deepseek-ai/*') { continue }
    $v = [string]$p.Value
    if ($v -match '^[0-9][0-9A-Za-z.\-]*$') { $pins += [pscustomobject]@{ Name = $p.Name; Ver = $v } }
    elseif ($v -match '^[<>=~^]') { $ranges += [pscustomobject]@{ Name = $p.Name; Range = $v } }
  }
}
if ($pins.Count -gt 0) {
  $distinct = @($pins | ForEach-Object { $_.Ver } | Sort-Object -Unique)
  Write-Info ('  peer 精确钉版     : ' + ($distinct -join ', ') + '（' + $pins.Count + ' 个内部包）')
}
if ($ranges.Count -gt 0) { Write-Info ('  peer 范围         : ' + (($ranges | ForEach-Object { $_.Name + $_.Range }) -join ', ')) }

# ---------- 3) 精确版本豁免 ----------
$exempted = $false
$compat = Read-JsonSafe (Join-Path $profDir 'compatibility.json')
if ($compat -and $DshVersion) {
  foreach ($p in $compat.PSObject.Properties) {
    if ($p.Name -notlike '@deepseek-ai/dsh-mcp-client@*') { continue }
    $ver = ($p.Name -split '@')[-1]
    if ($ver -ne $mcVersion) { continue }
    if (@($p.Value) -contains $DshVersion) {
      $exempted = $true
      Write-Warn2 ('compatibility.json 有精确版本豁免：' + $p.Name + ' -> ' + $DshVersion)
      Write-Info '官方明示：豁免状态下 may cause crashes or data loss；长期应升级 mcp-client 后撤掉豁免'
    }
  }
}

# ---------- 4) 判定 ----------
if (-not $DshVersion) { Write-Warn2 '拿不到运行时版本，无法判定（可用 -DshVersion 指定）'; exit 3 }

$verdict = 'unknown'
$detail = ''
if ($pins.Count -gt 0) {
  $distinct = @($pins | ForEach-Object { $_.Ver } | Sort-Object -Unique)
  if ($distinct -contains $DshVersion) { $verdict = 'ok'; $detail = '钉版与运行时一致（' + $DshVersion + '）' }
  else { $verdict = 'mismatch'; $detail = '钉版为 ' + ($distinct -join '/') + '，运行时是 ' + $DshVersion }
} elseif ($ranges.Count -gt 0) {
  $verdict = 'unknown'
  $detail = '只有范围型 peer，本工具不猜（请人工核对）'
} else {
  $detail = 'mcp-client 没有 @deepseek-ai/* 的 peer 声明'
}

if ($verdict -eq 'ok') { Write-Ok ('兼容：' + $detail); exit 0 }
if ($verdict -eq 'unknown') { Write-Warn2 ('无法判定：' + $detail); exit 3 }
if ($exempted) { Write-Warn2 ('不兼容（' + $detail + '），但已有精确版本豁免，注册可继续'); exit 0 }

Write-Bad ('不兼容：' + $detail)
Write-Info '带着不兼容的行去启动，宿主会在兼容闸门处被拒绝（nightly 上表现为整个宿主起不来）。'
Write-Info '先升级再注册（在 profile 目录执行）：'
Write-Info ('  cd ' + $profDir)
Write-Info ('  pnpm add "@deepseek-ai/dsh-mcp-client@' + $DshVersion + '"')
Write-Info '装好后重跑本脚本，应为「兼容」；随后把 compatibility.json 里对应的豁免删掉。'
exit 1
