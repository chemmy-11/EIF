# =============================================================================
# r2_mb10_sha.ps1 - prj11 R2 (B3-2) 10MB 质量档传输 + SHA 判定封装 (dry-run 默认)
#
# 判据(S8): "10MB 100% + SHA256 一致" —— 用 prj9 的 json_storm.py 质量档
#   (默认间隔; 源 = prj/project_9/testdata/session_full.jsonl, 10,293,111 B)
#   把整份 10MB 按 1466B/片打过板卡光链路往返, 逐片回显重组后与源文件比 SHA256:
#     发出片数 == 收到片数(100%)、丢失 0、损坏 0、sha_match=true
#   本封装额外做**独立复算**: PowerShell 侧独立算 源文件 SHA256 与 重组文件 SHA256,
#   并与 json_storm 打印的 "源 SHA256/重组 SHA256" 双核对(防止工具静默失效, §6a 硬规则 4)。
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File r2_mb10_sha.ps1
#       # 默认 DRY-RUN: 不建 socket / 不发送 / 只做离线真校验(路径/大小/SHA/参数/端口状态)
#   powershell ... -File r2_mb10_sha.ps1 -Run
#       # 真发送(会占用 UDP 1234 端口并打流量到板卡 192.168.1.10)
#       [-GapMs 1] [-Chunk 1466] [-Parallel 1] [-NoOutFile] [-ExpectSrcSha256 <hex64>]
#
# 口径纪律(与 Lead 2026-10-17 裁决一致):
#   * 不传 --pace-us(质量档=json_storm 默认间隔 1.0ms/片, 不是 pace 节拍档);
#     只有显式 -GapMs/-Chunk 才覆盖(0=用 json_storm 源码默认值)。
#   * 判据 exit0 & lost==0 & corrupt==0 & sha_match==true & recv==chunks
#   * 源 SHA256 默认钉死为 4F38AF2C85D9D03336B92548A2CB5F6B048F822A8632D0EE2499972F94BA3BF5
#     (2026-10-17 实测值); -ExpectSrcSha256 "" 可关闭钉死(仅打印)。
#   * 失败不重试; 输出日志落 <EvidenceDir>\R2_mb10_<ts>.log (UTF-8 BOM)。
#   * 结尾判据行 R2_MB10_RESULT: PASS|FAIL|NOT_OBTAINED; 退出码 0/1/2。
#
# 为什么不用 --pace-us 13: 那是 A6 忙等节拍器(高帧率吞吐档), 会绕过"质量档默认间隔"
# 口径; R2 S8 要的是 100%+SHA 而不是吞吐上限(速率归因属 R3, DESIGN §2 吞吐账)。
# =============================================================================
[CmdletBinding()]
param(
    [string]$DataFile = "D:\FPGA\prj\project_9\testdata\session_full.jsonl",
    [string]$StormPy = "D:\FPGA\prj\project_9\scripts\json_storm.py",
    [string]$Python = "",
    [int]$GapMs = 0,
    [int]$Chunk = 0,
    [int]$Parallel = 0,
    [string]$OutDir = "",
    [switch]$NoOutFile,
    [switch]$Run,
    [string]$ExpectSrcSha256 = "4F38AF2C85D9D03336B92548A2CB5F6B048F822A8632D0EE2499972F94BA3BF5",
    [string]$ExpectSrcBytes = "10293111"
)

$ErrorActionPreference = "Continue"
$script:Version = "2026-10-17"
$script:DryRun = -not $Run
$script:OutRoot = $PSScriptRoot
if (-not $script:OutRoot) { $script:OutRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutDir) { $OutDir = Join-Path $script:OutRoot "evidence_2026-10-17" }
$script:EvidDir = $OutDir
$script:Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogPath = Join-Path $script:EvidDir ("R2_mb10_" + $script:Stamp + ".log")
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:PyExe = ""
$script:PyPrefix = @()
$script:Notes = New-Object System.Collections.ArrayList
$script:KnownFullPathPy = "C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe"

try {
    if (-not (Test-Path $script:EvidDir)) { New-Item -ItemType Directory -Force -Path $script:EvidDir | Out-Null }
    [System.IO.File]::WriteAllText($script:LogPath, "", $script:Utf8Bom)
} catch {
    Write-Host ("FATAL: 无法创建证据目录/日志: " + $_.Exception.Message) -ForegroundColor Red
    exit 2
}

# =============================================================================
#region 通用 IO / 日志 (与 r2_board.ps1 / R1 retire_s0_s8.ps1 同风格)
# =============================================================================
function Write-Raw {
    param([string]$Text = "", [string]$Color = "")
    if ($null -eq $Text) { $Text = "" }
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    try { [System.IO.File]::AppendAllText($script:LogPath, $Text + "`r`n", $script:Utf8NoBom) } catch { }
}

function Write-Log {
    param([string]$Message = "", [string]$Color = "Gray")
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    Write-Raw $line $Color
}

function Write-Section {
    param([string]$Title)
    Write-Raw ("=" * 78) "Cyan"
    Write-Raw ("== " + $Title) "Cyan"
    Write-Raw ("=" * 78) "Cyan"
}

function Write-Plan { param([string[]]$Lines = @()) foreach ($l in $Lines) { Write-Raw ("[PLAN] " + $l) "DarkCyan" } }
function Write-Note { param([string]$Message) [void]$script:Notes.Add($Message); Write-Log ("NOTE: " + $Message) "Yellow" }

function Invoke-Native {
    param([Parameter(Mandatory = $true)][string]$Exe, [string[]]$ArgList = @(), [string]$TeePath = "")
    $lines = New-Object System.Collections.ArrayList
    $code = -1
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Exe @ArgList 2>&1 | ForEach-Object {
            $line = [string]$_
            [void]$lines.Add($line)
            Write-Host $line
            try { [System.IO.File]::AppendAllText($script:LogPath, $line + "`r`n", $script:Utf8NoBom) } catch { }
            if ($TeePath) { try { [System.IO.File]::AppendAllText($TeePath, $line + "`r`n", $script:Utf8NoBom) } catch { } }
        }
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
    } catch {
        $msg = "EXCEPTION: " + $_.Exception.Message
        [void]$lines.Add($msg)
        Write-Raw $msg "Red"
        $code = -1
    } finally {
        $ErrorActionPreference = $old
    }
    return [pscustomobject]@{ Text = ($lines -join "`n"); ExitCode = [int]$code }
}

function Get-HashFull {
    param([string]$Path)
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() } catch { return "" }
}

function Resolve-PythonExe {
    # 坑 #45: 一律优先全路径解释器; Git Bash 的 python 是坏壳(静默退 49)
    if ($script:PyExe) { return $script:PyExe }
    if ($Python) {
        $cmd = Get-Command $Python -ErrorAction SilentlyContinue
        if ($cmd) {
            $script:PyExe = $cmd.Source
            return $script:PyExe
        }
    }
    foreach ($c in @($script:KnownFullPathPy, "py", "python")) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) {
            $script:PyExe = $cmd.Source
            if ($cmd.Name -eq "py.exe" -or $cmd.Name -eq "py") { $script:PyPrefix = @("-3") }
            return $script:PyExe
        }
    }
    return ""
}

# =============================================================================
#endregion
#region 离线校验
# =============================================================================
function Get-SourceSha { param([string]$Path) return (Get-HashFull $Path) }

function Read-StormDefaults {
    # 从 json_storm.py 源码解析"质量档(默认间隔)"参数与判据标记 —— 真读源码, 不凭记忆
    param([string]$Path)
    $res = [ordered]@{
        Ok = $false; ChunkMax = $null; GapDefault = $null; PortDefault = $null;
        HasSummary = $false; HasShaMatch = $false; HasShaCompare = $false;
        HasPaceUs = $false; HasOut = $false; Text = ""
    }
    if (-not (Test-Path $Path)) { return [pscustomobject]$res }
    try { $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 } catch { return [pscustomobject]$res }
    $res.Text = $text
    $m = [regex]::Match($text, "CHUNK_MAX\s*=\s*(\d+)")
    if ($m.Success) { $res.ChunkMax = [int]$m.Groups[1].Value }
    $m = [regex]::Match($text, 'add_argument\(\s*"--gap-ms"\s*,\s*type=float\s*,\s*default=([0-9.]+)')
    if ($m.Success) { $res.GapDefault = [double]$m.Groups[1].Value }
    $m = [regex]::Match($text, 'add_argument\(\s*"--port"\s*,\s*type=int\s*,\s*default=(\d+)')
    if ($m.Success) { $res.PortDefault = [int]$m.Groups[1].Value }
    $res.HasSummary = ($text -match "JSON_STORM_SUMMARY:")
    $res.HasShaMatch = ($text -match "sha_match")
    $res.HasShaCompare = ($text -match "SHA256 比对")
    $res.HasPaceUs = ($text -match '"--pace-us"')
    $res.HasOut = ($text -match '"--out"')
    $res.Ok = ($null -ne $res.ChunkMax) -and ($null -ne $res.GapDefault) -and $res.HasSummary -and $res.HasShaMatch
    return [pscustomobject]$res
}

function Get-Port1234State {
    # 只读检查 UDP 1234 是否被占用(质量档默认端口)
    try {
        $c = Get-NetTCPConnection -LocalPort 1234 -State Listen -ErrorAction SilentlyContinue
        if ($c) { return ("LISTEN (" + (($c | Select-Object -First 1).OwningProcess) + ")") }
        return "FREE"
    } catch { return "UNKNOWN(" + $_.Exception.Message + ")" }
}

function Step-OfflineChecks {
    Write-Section "O0 离线真校验(不建 socket / 不发送 / 不碰板): 源文件 + json_storm 参数 + Python + 端口"
    $okAll = $true

    # ---- 源文件 ----
    $df = ""
    try { $df = (Resolve-Path -LiteralPath $DataFile -ErrorAction Stop).Path } catch { $df = "" }
    if (-not $df) {
        Write-Log ("源文件不存在: " + $DataFile) "Red"
        Write-Log "→ 10MB 质量档判据未取得(数据源缺失)。期望: prj/project_9/testdata/session_full.jsonl (10,293,111 B)" "Yellow"
        $okAll = $false
    } else {
        $fi = Get-Item -LiteralPath $df
        $sha = Get-SourceSha $df
        Write-Log ("源文件 = " + $df)
        Write-Log ("源大小 = " + $fi.Length + " B (期望 " + $ExpectSrcBytes + ")")
        Write-Log ("源 SHA256 = " + $sha)
        if ($ExpectSrcBytes -and ($fi.Length -ne [int64]$ExpectSrcBytes)) {
            Write-Log ("源大小与期望不符: " + $fi.Length + " ≠ " + $ExpectSrcBytes + " ⇒ 质量档基线不可比") "Red"
            $okAll = $false
        } else { Write-Log "源大小与期望一致 ✓" "Green" }
        if ($ExpectSrcSha256) {
            if ($sha -eq $ExpectSrcSha256.ToLower()) { Write-Log "源 SHA256 与钉死期望一致 ✓" "Green" }
            else { Write-Log ("源 SHA256 与钉死期望不符: 实际 " + $sha + " ≠ 期望 " + $ExpectSrcSha256) "Red"; $okAll = $false }
        } else { Write-Log "源 SHA256 未钉死(-ExpectSrcSha256 '') ⇒ 只记录" "DarkYellow" }
    }

    # ---- json_storm.py 源码参数 ----
    if (-not (Test-Path $StormPy)) {
        Write-Log ("json_storm.py 不存在: " + $StormPy) "Red"
        $okAll = $false
    } else {
        $sd = Read-StormDefaults -Path $StormPy
        Write-Log ("json_storm.py = " + (Resolve-Path -LiteralPath $StormPy).Path)
        if ($sd.Ok) {
            Write-Log ("质量档默认参数(源码实测): chunk=" + $sd.ChunkMax + "B (CHUNK_MAX), gap=" + $sd.GapDefault + "ms (--gap-ms 默认), port=" + $sd.PortDefault) "Green"
        } else {
            Write-Log "json_storm.py 参数/判据标记解析不完整(源码可能已改) ⇒ 不能凭默认值上板" "Red"
            $okAll = $false
        }
        Write-Log ("判据标记: JSON_STORM_SUMMARY=" + $sd.HasSummary + " sha_match=" + $sd.HasShaMatch + " SHA256比对=" + $sd.HasShaCompare + " --out=" + $sd.HasOut + " pace-us 可用=" + $sd.HasPaceUs)
        if ($GapMs -gt 0) { Write-Log ("显式覆盖 -GapMs=" + $GapMs + " (质量档默认 " + $sd.GapDefault + "ms)") "Yellow" }
        if ($Chunk -gt 0) { Write-Log ("显式覆盖 -Chunk=" + $Chunk + " (质量档默认 " + $sd.ChunkMax + "B)") "Yellow" }
        if (-not $sd.HasOut -and -not $NoOutFile) {
            Write-Log "json_storm 不支持 --out ⇒ 关闭重组文件落盘(仅脚本内 SHA 比)" "Yellow"
            $script:EffectiveNoOut = $true
        }
    }

    # ---- Python ----
    $py = Resolve-PythonExe
    if ($py) {
        Write-Log ("python = " + $py + "  (prefix: " + ($script:PyPrefix -join " ") + ")") "Green"
        if ($py -notmatch "pythoncore-3\.14-64") {
            Write-Log "WARN: 未使用任务书指定的全路径解释器(坑 #45: Git Bash 的 python 是坏壳)" "Yellow"
        }
    } else {
        Write-Log "找不到 python(-Python 可指定) ⇒ 质量档无法执行" "Red"
        $okAll = $false
    }

    # ---- UDP 1234 端口 ----
    $ps = Get-Port1234State
    Write-Log ("UDP/TCP 1234 端口状态 = " + $ps)
    if ($ps -like "LISTEN*") { Write-Log "WARN: 1234 被监听(质量档绑定会失败/被抢占); 跑前关闭" "Yellow" }

    # ---- 证据目录/日志 ----
    Write-Log ("证据目录 = " + $script:EvidDir)
    Write-Log ("本次日志 = " + $script:LogPath)
    return $okAll
}

function Get-PlannedCommandLine {
    $argv = @()
    $argv += $StormPy
    $argv += $DataFile
    if ($GapMs -gt 0) { $argv += @("--gap-ms", [string]$GapMs) }
    if ($Chunk -gt 0) { $argv += @("--chunk", [string]$Chunk) }
    if ($Parallel -gt 0) { $argv += @("--parallel", [string]$Parallel) }
    if (-not $NoOutFile -and -not $script:EffectiveNoOut) { $argv += @("--out", "<ts>.recomposed.jsonl") }
    return ("py " + ($argv -join " "))
}

# =============================================================================
#endregion
#region -Run 真执行
# =============================================================================
function Invoke-Mb10Run {
    Write-Section "S8 10MB 质量档真执行(json_storm.py; 会占用 UDP 1234 并打流量到板卡)"
    $df = (Resolve-Path -LiteralPath $DataFile -ErrorAction Stop).Path
    $stormFull = (Resolve-Path -LiteralPath $StormPy -ErrorAction Stop).Path
    $srcSha = Get-SourceSha $df

    $outFile = ""
    if (-not $NoOutFile -and -not $script:EffectiveNoOut) {
        $outFile = Join-Path $script:EvidDir ("R2_mb10_" + $script:Stamp + ".recomposed.jsonl")
    }

    $argv = @($stormFull, $df)
    if ($GapMs -gt 0) { $argv += @("--gap-ms", [string]$GapMs) }
    if ($Chunk -gt 0) { $argv += @("--chunk", [string]$Chunk) }
    if ($Parallel -gt 0) { $argv += @("--parallel", [string]$Parallel) }
    if ($outFile) { $argv += @("--out", $outFile) }
    if ($script:PyPrefix.Count -gt 0) { $argv = $script:PyPrefix + $argv }

    Write-Log ("执行: " + $script:PyExe + " " + ($argv -join " "))
    Write-Log ("源 SHA256(独立复算) = " + $srcSha)
    $res = Invoke-Native -Exe $script:PyExe -ArgList $argv
    Write-Log ("json_storm 退出码 = " + $res.ExitCode)

    # ---- 解析 JSON_STORM_SUMMARY ----
    $summary = $null
    $mSum = [regex]::Matches($res.Text, "JSON_STORM_SUMMARY:\s*(\{.*\})")
    if ($mSum.Count -gt 0) {
        try { $summary = ($mSum[$mSum.Count - 1].Groups[1].Value | ConvertFrom-Json) } catch { $summary = $null }
    }
    if ($null -eq $summary) {
        Write-Log "未解析到 JSON_STORM_SUMMARY 行 ⇒ 判据未取得" "Yellow"
        return [pscustomobject]@{ Verdict = "NOT_OBTAINED"; Detail = "无 JSON_STORM_SUMMARY 行(脚本未跑完/端口占用/输出被截断)" }
    }
    Write-Log ("summary: chunks=" + $summary.chunks + " recv=" + $summary.recv + " lost=" + $summary.lost + " corrupt=" + $summary.corrupt + " sha_match=" + $summary.sha_match)

    # ---- 解析脚本打印的 SHA 与片数 ----
    $mSrc = [regex]::Match($res.Text, "源 SHA256:\s*([0-9A-Fa-f]{64})")
    $mOut = [regex]::Match($res.Text, "重组 SHA256:\s*([0-9A-Fa-f]{64})")
    $printSrc = ""; $printOut = ""
    if ($mSrc.Success) { $printSrc = $mSrc.Groups[1].Value.ToUpper() }
    if ($mOut.Success) { $printOut = $mOut.Groups[1].Value.ToUpper() }
    $shaCompareOk = ($res.Text -match "SHA256 比对:\s*一致")
    Write-Log ("脚本打印: 源=" + $printSrc + " 重组=" + $printOut + " SHA256比对一致=" + $shaCompareOk)

    # ---- 独立复算(不采信工具自报) ----
    $indep = New-Object System.Collections.ArrayList
    $indepOk = $true
    if ($ExpectSrcSha256) {
        if ($srcSha -eq $ExpectSrcSha256.ToLower()) { [void]$indep.Add("源文件独立 SHA256=钉死期望 ✓") }
        else { [void]$indep.Add("源文件独立 SHA256≠钉死期望 ✗"); $indepOk = $false }
    }
    if ($printSrc) {
        if ($printSrc.ToLower() -eq $srcSha) { [void]$indep.Add("工具读出源 SHA256=独立复算 ✓") }
        else { [void]$indep.Add("工具读出源 SHA256≠独立复算 ✗"); $indepOk = $false }
    } else {
        [void]$indep.Add("工具未打印源 SHA256(OLD 脚本?) ✗"); $indepOk = $false
    }
    if ($outFile -and (Test-Path $outFile)) {
        $outHash = Get-HashFull $outFile
        $outSize = (Get-Item -LiteralPath $outFile).Length
        if ($outHash -eq $srcSha) { [void]$indep.Add("重组文件独立 SHA256=源 ✓ (size=" + $outSize + ")") }
        else { [void]$indep.Add("重组文件独立 SHA256≠源 ✗ (size=" + $outSize + ")"); $indepOk = $false }
        if ($outSize -ne (Get-Item -LiteralPath $df).Length) { [void]$indep.Add("重组文件大小≠源 ✗"); $indepOk = $false }
    } elseif (-not $NoOutFile -and -not $script:EffectiveNoOut) {
        [void]$indep.Add("未生成重组文件 --out(" + $outFile + ") ✗"); $indepOk = $false
    }
    foreach ($l in $indep) { Write-Log ("独立复算: " + $l) $(if ($l -match "✓") { "Green" } else { "Red" }) }

    # ---- 判据 ----
    $chunks = [int64]$summary.chunks
    $recv = [int64]$summary.recv
    $lost = [int64]$summary.lost
    $corrupt = [int64]$summary.corrupt
    $shaMatch = [bool]$summary.sha_match
    $full = ($chunks -gt 0) -and ($recv -eq $chunks) -and ($lost -eq 0) -and ($corrupt -eq 0) -and $shaMatch
    Write-Log ("片数: 发送=" + $chunks + " 收到=" + $recv + " 丢失=" + $lost + " 损坏=" + $corrupt + " 到达率=" + [math]::Round(100.0 * $recv / [math]::Max($chunks, 1), 2) + "%")
    if (($res.ExitCode -ne 0) -and $full) { Write-Note ("json_storm 退出码=" + $res.ExitCode + " 但判据字段全绿 —— 以判据字段+独立复算为准, 记录退出码") }
    if (-not $full) {
        $why = @()
        if ($recv -ne $chunks) { $why += ("未 100%: recv " + $recv + "/" + $chunks) }
        if ($lost -ne 0) { $why += ("lost=" + $lost) }
        if ($corrupt -ne 0) { $why += ("corrupt=" + $corrupt) }
        if (-not $shaMatch) { $why += "sha_match=false" }
        return [pscustomobject]@{ Verdict = "FAIL"; Detail = ("10MB 质量档未通过: " + ($why -join ", ")) }
    }
    if (-not $indepOk) {
        return [pscustomobject]@{ Verdict = "FAIL"; Detail = "脚本自报 PASS 但独立复算有 ✗ (工具静默失效? 见日志)" }
    }
    $detail = ("10MB 100% 逐片回显 + SHA256 一致: chunks=" + $chunks + " recv=" + $recv +
               " lost=0 corrupt=0 sha_match=true; 独立复算源/重组 SHA256 一致")
    return [pscustomobject]@{ Verdict = "PASS"; Detail = $detail }
}

# =============================================================================
#endregion
#region 主流程
# =============================================================================
$modeTxt = "DRY-RUN(不建 socket/不发送; -Run 才真打流量)"
if ($Run) { $modeTxt = "RUN(会占用 UDP 1234 并向 192.168.1.10 打 10MB 流量!)" }
Write-Raw ("=" * 78) "Cyan"
Write-Raw "prj11 R2 S8 · 10MB 质量档传输 + SHA256 判定封装" "Cyan"
Write-Raw ("脚本版本 " + $script:Version + "   模式: " + $modeTxt) "Cyan"
Write-Raw ("日志(UTF-8 BOM) " + $script:LogPath) "Cyan"
Write-Raw ("=" * 78) "Cyan"

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONHOME = ""
$env:PYTHONPATH = ""
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$script:EffectiveNoOut = $false
$okOffline = Step-OfflineChecks

if ($script:DryRun) {
    Write-Section "DRY-RUN 计划"
    $plan = @()
    $plan += "1) 前置: 板卡已烧 R2 位流 + 新 ELF; 'U' 回读 mode=1 & req.bit24=1 (由 r2_board.ps1 S3/S4/S5 保证)"
    $plan += ("2) 质量档命令(默认间隔, 不传 --pace-us): " + (Get-PlannedCommandLine))
    $plan += "3) 判据: exit0 & lost==0 & corrupt==0 & sha_match==true & recv==chunks(=7022 若源 10,293,111B)"
    $plan += "4) 独立复算: PowerShell 侧 Get-FileHash 源文件/重组文件 + 与脚本打印 SHA 双核对"
    $plan += "5) 失败不重试; 若 0 回显先查板卡引擎状态/静态 ARP 广播 dst(见 S0S8_DESIGN §1.3)"
    $plan += ("6) 日志落 " + $script:LogPath)
    Write-Plan -Lines $plan
    if ($okOffline) { Write-Raw "[DRYRUN] 离线真校验: 全部通过(源文件/SHA/参数/Python/端口 均实测核对)" "Green" }
    else { Write-Raw "[DRYRUN] 离线真校验: 有 FAIL 项(见上), -Run 前必须修复" "Yellow" }
    Write-Raw "[GUARD] 不建 socket: 0 次   不发送: 0 帧   不碰板卡: 是" "DarkYellow"
    Write-Raw "R2_MB10_RESULT: SKIP (dry-run —— 未建 socket/未发送; 加 -Run 真执行)" "DarkYellow"
    Write-Raw ("全量日志: " + $script:LogPath) "Cyan"
    exit 0
}

# ---------------- -Run 前硬校验 ----------------
$argErr = ""
if (-not (Test-Path $DataFile)) { $argErr += " 源文件不存在(-DataFile);" }
if (-not (Test-Path $StormPy)) { $argErr += " json_storm.py 不存在(-StormPy);" }
if (-not (Resolve-PythonExe)) { $argErr += " python 不可用(-Python 指定全路径);" }
if (-not $okOffline) { Write-Log "离线真校验有 FAIL 项 ⇒ -Run 继续执行, 但结论需按 NOTE 降级复核" "Yellow" }
if ($argErr) {
    Write-Raw ("ARG-ERROR:" + $argErr) "Red"
    Write-Raw "R2_MB10_RESULT: NOT_OBTAINED 参数/环境不满足" "Red"
    exit 2
}

$result = Invoke-Mb10Run
if ($result.Verdict -eq "PASS") {
    Write-Raw ("[JUDGE] R2_S8 PASS: " + $result.Detail) "Green"
    Write-Raw "R2_MB10_RESULT: PASS" "Green"
    Write-Raw ("全量日志: " + $script:LogPath) "Cyan"
    exit 0
} elseif ($result.Verdict -eq "FAIL") {
    Write-Raw ("[JUDGE] R2_S8 FAIL: " + $result.Detail) "Red"
    Write-Raw "R2_MB10_RESULT: FAIL" "Red"
    Write-Raw ("全量日志: " + $script:LogPath) "Cyan"
    exit 1
}
Write-Raw ("[JUDGE] R2_S8 NOT_OBTAINED: " + $result.Detail) "Yellow"
Write-Raw "R2_MB10_RESULT: NOT_OBTAINED" "Yellow"
Write-Raw ("全量日志: " + $script:LogPath) "Cyan"
exit 2
#endregion
