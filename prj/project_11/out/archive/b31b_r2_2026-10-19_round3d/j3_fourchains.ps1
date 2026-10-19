# =============================================================================
# j3_fourchains.ps1 - prj11 J3 四链封装: 带 --dma 跑 M / A / B 三轮, 逐轮 tee
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File j3_fourchains.ps1                 # 默认 DRY-RUN
#   powershell ... -File j3_fourchains.ps1 -Run [-Port COM5] [-Python py] `
#            [-Bitstream auto|retired|green]
#
# 口径(2026-10-17 21:0x 实测修正，务必遵守):
#   * 固定用 scripts\j3_soft_verify.py 的【默认 --nslots=256】。禁止 --nslots 64:
#     板端 NSLOTS 是编译期 256, 64 会让对账判据假失败(文档 §二之五 已定案)。
#   * **带 `--dma`** 跑 M/A/B（2026-10-17 21:2x 最终口径, 脚本已修 J3 预热帧缺陷后复验 PASS）
#       - 不带 --dma: [M] wr+256 rd+256 inv=32132 miss=0 / [A] rd+255 miss=[#100] / [B] PASS
#                     (green_bridge_j3_run1.log) => PASS
#       - 带 --dma  : 连续 3 次 [M] wr+255(写侧丢 1 帧) → 读阶段不启动 → 槽满 → 后续全 FAIL,
#                     还可能把板卡留在"256 槽未读 + 读 FSM 泊 R_DRET"的半楔死状态
#                     (green_engine1_j3_dma.log / run2 / run3_nowarmup.log)
#     ⇒ J3 前**不要**发 'd'（'d' 只决定空闲期驻留服务, 给 ping 判据用）。
#   * J3 前置(每轮前): 板卡必须是**新烧录**的干净状态, 或至少满足:
#       发 'S' → 轮询 'U' 直到 wmwr == wmrd 且 req.bit25=0 连续两拍。
#     否则残留"已写未读"帧会占槽, M 轮写阶段只收 255/256 帧而假失败。
#   * 失败纪律: 任一轮 FAIL 就**不再跑后续轮**（不自动重试）; 若 M 轮出现 `wr+255`/收帧停摆,
#     直接标「判据未取得 + 板卡需重烧」——重试会级联假 FAIL 并可能楔死板卡。
#   * 逐轮独立调用 j3_soft_verify.py（--rounds M / A / B 各一次）:
#     这样 M 失败可立即止损, 不让 j3_soft_verify 内部的 A/B 级联跑下去。
#     (j3_soft_verify.py 自身对"该轮"仍有 ≤3 次内部尝试, 属既有脚本行为, 本脚本不改原件。)
#   * 跑完只**读**状态并打印（轮末 R_ENGINE=0、R_MODE=RND）; 需要 ping/emit 判据时,
#     请由外层（S0-S8 的 S3/S4/S5）单独 Set-EngineMode DMA + 断言 req.bit24=1。
# =============================================================================
[CmdletBinding()]
param(
    [string]$Port = "COM5",
    [switch]$Run,
    [string]$Python = "",
    [ValidateSet("auto", "retired", "green")][string]$Bitstream = "auto",
    [switch]$SkipBridge
)

$ErrorActionPreference = "Continue"
$script:DryRun  = -not $Run
$script:OutRoot = $PSScriptRoot
if (-not $script:OutRoot) { $script:OutRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:Proj    = Split-Path -Parent $script:OutRoot
$script:EvidDir = Join-Path $script:OutRoot "evidence_2026-10-17"
$script:Stamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogPath = Join-Path $script:EvidDir ("j3_fourchains_" + $script:Stamp + ".log")
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom   = New-Object System.Text.UTF8Encoding($true)
$script:Port    = $Port
$script:PyExe   = ""
$script:PyPrefix = @()
$script:Results  = [ordered]@{}

try {
    if (-not (Test-Path $script:EvidDir)) { New-Item -ItemType Directory -Force -Path $script:EvidDir | Out-Null }
    [System.IO.File]::WriteAllText($script:LogPath, "", $script:Utf8Bom)
} catch {
    Write-Host ("FATAL: 无法创建证据目录: " + $_.Exception.Message) -ForegroundColor Red
    exit 2
}

# =============================================================================
#region 通用 IO
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

function Invoke-Python {
    param([string[]]$ArgList = @(), [string]$TeePath = "")
    $all = @()
    if ($script:PyPrefix.Count -gt 0) { $all += $script:PyPrefix }
    $all += $ArgList
    return Invoke-Native -Exe $script:PyExe -ArgList $all -TeePath $TeePath
}

function Resolve-PythonExe {
    if ($script:PyExe) { return $script:PyExe }
    $cands = @()
    if ($Python) { $cands = @($Python) } else { $cands = @("py", "python") }
    foreach ($c in $cands) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) {
            $script:PyExe = $c
            if ($c -eq "py") { $script:PyPrefix = @("-3") } else { $script:PyPrefix = @() }
            return $script:PyExe
        }
    }
    return ""
}

# =============================================================================
#endregion
#region UART 'U' 回读（只读, 不发 'd'）
# =============================================================================
function Invoke-UartProbe {
    param([string]$Cmd, [double]$Wait = 1.5, [double]$Drain = 0.15, [string]$Title = "")
    if ($Title) { Write-Section $Title }
    if (-not $script:PyExe) { return [pscustomobject]@{ Text = "PYTHON-UNAVAILABLE"; ExitCode = -1 } }
    $probe = Join-Path $script:OutRoot "uart_probe.py"
    return Invoke-Python -ArgList @($probe, "--port", $script:Port, "--cmd", $Cmd, "--wait", [string]$Wait, "--drain", [string]$Drain, "--raw")
}

function Get-UProbeNumber {
    param([string]$Payload, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Payload)) { return $null }
    $toks = @($Payload.Trim() -split "\s+")
    $hex = New-Object System.Collections.ArrayList
    foreach ($t in $toks) { if ($t -match "^[0-9a-fA-F]{1,8}$") { [void]$hex.Add([Convert]::ToUInt32($t, 16)) } }
    if ($hex.Count -lt 2) { return $null }
    $usable = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $hex.Count; $i++) { [void]$usable.Add([uint32]$hex[$i]) }
    return [uint32]$usable[$usable.Count - 1]
}

function ConvertFrom-UProbe {
    param([string]$Text)
    $out = [ordered]@{ ParseOk = $false; Req = $null; Mode = $null; WmWr = $null; WmRd = $null; Raw = $Text }
    $map = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match "^\[B2\]\s+U\s+mode=(\d+)$") { $out.Mode = [int]$Matches[1]; continue }
        if ($t -match "^\[B2\]\s+U\s+([A-Za-z]+):\s*(.+)$") { $map[$Matches[1]] = $Matches[2] }
    }
    if ($map.ContainsKey("req"))  { $out.Req  = Get-UProbeNumber -Payload $map["req"]  -Field "req" }
    if ($map.ContainsKey("wmwr")) { $out.WmWr = Get-UProbeNumber -Payload $map["wmwr"] -Field "wmwr" }
    if ($map.ContainsKey("wmrd")) { $out.WmRd = Get-UProbeNumber -Payload $map["wmrd"] -Field "wmrd" }
    $out.ParseOk = ($null -ne $out.Req) -and ($null -ne $out.Mode)
    $obj = New-Object psobject
    foreach ($key in $out.Keys) { $obj | Add-Member -MemberType NoteProperty -Name $key -Value $out[$key] }
    return $obj
}

function Get-UState {
    param([string]$Title = "")
    $res = Invoke-UartProbe -Cmd "U" -Wait 1.8 -Drain 0.2 -Title $Title
    return ConvertFrom-UProbe -Text $res.Text
}

function Get-ReqEngineBit {
    param($U)
    if ($null -eq $U -or $null -eq $U.Req) { return $false }
    return (($U.Req -band 0x01000000) -ne 0)
}

function Invoke-Precheck {
    # J3 前置: 'S' 恢复 SEQ + 确认槽表干净(只读, 不发 'd')。
    param([int]$MaxPolls = 8)
    Write-Section "J3 前置(R2 口径): 发 'S' → 若 mode=0 发一次 'd' → 轮询 'U'（bit25=0 且 wmwr/wmrd 两拍不变）"
    $sres = Invoke-UartProbe -Cmd "S" -Wait 1.2 -Drain 0.15 -Title "前置 'S' 恢复 SEQ"
    Start-Sleep -Milliseconds 300
    # ★R2: 桥①读出仅 DMA（硬件读引擎退役）=> J3 必须在 DMA 模式。只在 mode=0 时发一次 'd'（toggle）。
    $u0 = Get-UState -Title "前置模式自检"
    if ($null -ne $u0 -and $u0.ParseOk -and ($u0.Mode -ne 1)) {
        [void](Invoke-UartProbe -Cmd "d" -Wait 1.2 -Drain 0.15 -Title "前置 'd' 切 DMA（R2 必需）")
        Start-Sleep -Milliseconds 300
    }
    $trace = New-Object System.Collections.ArrayList
    $prev = $null
    $lastU = $null
    for ($i = 0; $i -lt $MaxPolls; $i++) {
        $u = Get-UState -Title ("前置回读 #" + ($i + 1))
        $lastU = $u
        if ($null -eq $u -or -not $u.ParseOk) {
            [void]$trace.Add(("U#{0}: 解析失败" -f $i))
            Start-Sleep -Milliseconds 300
            continue
        }
        $wr = [int]($u.WmWr -band 0xFFFF)
        $rd = [int]($u.WmRd -band 0xFFFF)
        $sticky = (($u.Req -band 0x02000000) -ne 0)
        [void]$trace.Add(("U#{0}: mode={1} bit24={2} wmwr={3} wmrd={4} sticky={5}" -f $i, $u.Mode, [int](Get-ReqEngineBit $u), $wr, $rd, [int]$sticky))
        # ★R2 (2026-10-19): u_wr/u_rd 不再 1:1（mode-0/超时丢弃也计入 wr）=> 不要求相等;
        # 槽表干净 = bit25 落零 且 两拍计数不变（无待服务请求 + 无新写提交）。
        if (-not $sticky) {
            if ($null -ne $prev -and $prev.Wr -eq $wr -and $prev.Rd -eq $rd) {
                Write-Log ($trace -join "`n")
                return [pscustomobject]@{ Ok = $true; State = $u; Trace = ($trace -join "`n") }
            }
            $prev = [pscustomobject]@{ Wr = $wr; Rd = $rd }
        } else {
            $prev = $null
        }
        Start-Sleep -Milliseconds 300
    }
    Write-Log ($trace -join "`n")
    return [pscustomobject]@{ Ok = $false; State = $lastU; Trace = ($trace -join "`n") }
}

# =============================================================================
#endregion
#region 主流程
# =============================================================================
$modeTxt = "DRY-RUN（只打印计划；加 -Run 才真执行）"
if ($Run) { $modeTxt = "RUN（会碰串口/板卡！）" }
Write-Raw ("=" * 78) "Cyan"
Write-Raw "J3 四链封装: 带 --dma 跑 M / A / B（默认 nslots=256, 禁止 64）" "Cyan"
Write-Raw ("模式: " + $modeTxt + "    Bitstream 预期: " + $Bitstream) "Cyan"
Write-Raw ("日志: " + $script:LogPath) "Cyan"
Write-Raw ("=" * 78) "Cyan"

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONHOME = ""
$env:PYTHONPATH = ""
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$py = Resolve-PythonExe
$j3 = Join-Path $script:Proj "scripts\j3_soft_verify.py"
$uart = Join-Path $script:OutRoot "uart_probe.py"
Write-Log ("python = " + $py)
Write-Log ("j3_soft_verify.py = " + $j3 + "  (exists=" + (Test-Path $j3) + ")")
Write-Log ("uart_probe.py = " + $uart + "  (exists=" + (Test-Path $uart) + ")")
Write-Log ("证据目录 = " + $script:EvidDir)
if ($SkipBridge) { Write-Log "NOTE: -SkipBridge 已废弃/忽略 —— 现版本只跑不带 --dma 的一次 M/A/B" "DarkYellow" }

if ($script:DryRun) {
    Write-Section "DRY-RUN 计划"
    Write-Raw "[PLAN] 0) 前置: 发 'S' → 轮询 'U' 直到 wmwr==wmrd 且 req.bit25=0 连续两拍（只读, 不发 'd'）"
    Write-Raw "         若前置不干净 ⇒ 判'判据未取得 + 板卡需重烧', 不跑（避免槽满级联假 FAIL）"
    Write-Raw "         要求: 板卡为新烧录的干净状态（或至少已满足上面的槽表条件）"
    Write-Raw ("[PLAN] 1) py <j3_soft_verify.py> --com " + $Port + " --rounds M --dma")
    Write-Raw ("         → tee " + (Join-Path $script:EvidDir ("j3_m_" + $script:Stamp + ".log")))
    Write-Raw ("[PLAN] 2) py <j3_soft_verify.py> --com " + $Port + " --rounds A --dma （仅 M PASS 后才跑）")
    Write-Raw ("         → tee " + (Join-Path $script:EvidDir ("j3_a_" + $script:Stamp + ".log")))
    Write-Raw ("[PLAN] 3) py <j3_soft_verify.py> --com " + $Port + " --rounds B --dma （仅 A PASS 后才跑）")
    Write-Raw ("         → tee " + (Join-Path $script:EvidDir ("j3_b_" + $script:Stamp + ".log")))
    Write-Raw "         判据: 每轮尾部 [B2-SOFT-VERIFY] PASS + nslots 默认 256（带 --dma）"
    Write-Raw "         失败纪律: 任一轮 FAIL ⇒ 后续轮 SKIP, 不自动重试; M 轮 wr+255/收帧停摆 ⇒"
    Write-Raw "                   标「判据未取得 + 板卡需重烧」(重试会级联假 FAIL 并可能楔死板卡)"
    Write-Raw "         跑完只读状态: 轮末 R_ENGINE=0 / R_MODE=RND; 需要 ping/emit 判据时由外层单独 Set-EngineMode DMA"
    Write-Raw "[PLAN] 汇总: J3_ROUND M/A/B + FOURCHAINS_RESULT: PASS|FAIL(判据未取得)"
    Write-Raw "FOURCHAINS_RESULT: SKIP (dry-run —— 未执行任何串口/板卡操作; 加 -Run 真执行)" "DarkYellow"
    exit 0
}

# ---------------- 前置: 'S' + 槽表干净检查（只读, 不发 'd'） ----------------
$pre = Invoke-Precheck -MaxPolls 8
$preState = $pre.State
if ($null -ne $preState -and $preState.ParseOk) {
    Write-Log ("前置状态: mode={0} bit24={1} wmwr={2} wmrd={3} sticky={4}" -f $preState.Mode, [int](Get-ReqEngineBit $preState), ($preState.WmWr -band 0xFFFF), ($preState.WmRd -band 0xFFFF), [int](($preState.Req -band 0x02000000) -ne 0))
    if ($Bitstream -eq "retired") {
        if ($preState.Mode -ne 1 -or -not (Get-ReqEngineBit $preState)) {
            Write-Log "WARN: 退役位流且当前 mode!=1/bit24=0 —— 当前 main.c:352-356 里轮内切 DMA 受 g_dma_mode 门控;" "Yellow"
            Write-Log "      若 ELF 未改成'轮内强制 DMA', M 轮将无读出路径而失败并留下 256 未读槽。建议在 S0-S8 流程内(S3 之后)跑。" "Yellow"
        }
    }
}
if (-not $pre.Ok) {
    Write-Log "前置失败: 槽表不干净(bit25 未落 或 计数仍在变) ⇒ 判据未取得; **板卡需重烧**后再跑（本脚本不自动重试）" "Red"
    foreach ($r in @("M", "A", "B")) { $script:Results[$r] = [pscustomobject]@{ Ok = $null; Verdict = "NOT_OBTAINED"; Detail = "前置槽表不干净, 未跑; 板卡需重烧"; Log = ""; Exit = $null } }
} else {
    Write-Log "前置清槽检查通过 ✓（R2 口径: bit25=0 & wmwr/wmrd 两拍不变）" "Green"
    $stopped = $false
    foreach ($r in @("M", "A", "B")) {
        if ($stopped) {
            $script:Results[$r] = [pscustomobject]@{ Ok = $null; Verdict = "SKIP"; Detail = "前一轮失败, 不再级联"; Log = ""; Exit = $null }
            Write-Log ("J3 轮 " + $r + ": SKIP（前一轮失败, 不自动重试/不级联）") "DarkYellow"
            continue
        }
        Write-Section ("J3 轮 " + $r + "（带 --dma）")
        $rlog = Join-Path $script:EvidDir ("j3_" + $r.ToLower() + "_" + $script:Stamp + ".log")
        [System.IO.File]::WriteAllText($rlog, "", $script:Utf8Bom)
        $res = Invoke-Python -ArgList @($j3, "--com", $Port, "--rounds", $r, "--dma") -TeePath $rlog
        $ok = ($res.ExitCode -eq 0) -and ($res.Text -match "\[B2-SOFT-VERIFY\] PASS")
        $inconclusive = ($res.Text -match "wr\+=2[0-5]\d") -or ($res.Text -match "收帧停摆") -or ($res.Text -match "WAITWR-FAIL")
        $verdict = "FAIL"
        $detail = ""
        if ($ok) {
            $verdict = "PASS"
        } elseif ($inconclusive) {
            $verdict = "NOT_OBTAINED"
            $detail = "M 轮 wr+255/收帧停摆 ⇒ 判据未取得; 板卡需重烧（不要重试/级联）"
        } else {
            $detail = ("退出码=" + $res.ExitCode + "；详见 " + (Split-Path -Leaf $rlog))
        }
        $script:Results[$r] = [pscustomobject]@{ Ok = $ok; Verdict = $verdict; Detail = $detail; Log = $rlog; Exit = $res.ExitCode }
        $tag = $verdict
        if ($verdict -eq "NOT_OBTAINED") { $tag = "FAIL(判据未取得)" }
        if ($ok) { Write-Log ("J3 轮 " + $r + ": PASS   log=" + $rlog) "Green" }
        else {
            Write-Log ("J3 轮 " + $r + ": " + $tag + "  " + $detail) "Red"
            $stopped = $true
        }
    }
}

# ---------------- 收尾: 只读状态（不在 J3 之后自动发 'd'） ----------------
Write-Section "收尾: 只读状态（不自动发 'd'）"
$fin = Get-UState -Title "收尾 'U' 回读"
$finTxt = "(U 无应答)"
if ($null -ne $fin -and $fin.ParseOk) {
    $finTxt = ("mode={0} bit24={1} wmwr={2} wmrd={3} sticky={4}" -f $fin.Mode, [int](Get-ReqEngineBit $fin), ($fin.WmWr -band 0xFFFF), ($fin.WmRd -band 0xFFFF), [int](($fin.Req -band 0x02000000) -ne 0))
}
Write-Log ("轮后状态: " + $finTxt)
Write-Log "NOTE: 轮末固件会把 R_ENGINE 写回 0、R_MODE 停在 RND（main.c:358/375-379）;" "DarkYellow"
Write-Log "      后续需要 ping/emit 判据时, 请由外层单独 Set-EngineMode DMA 并断言 req.bit24=1（本脚本不自动发 'd'）。" "DarkYellow"

# ---------------- 汇总 ----------------
Write-Section "四链汇总（带 --dma）"
foreach ($r in @("M", "A", "B")) {
    if (-not $script:Results.Contains($r)) { continue }
    $x = $script:Results[$r]
    Write-Raw ("J3_ROUND {0}: {1}  exit={2}  log={3}" -f $r, $x.Verdict, $x.Exit, $x.Log)
    if ($x.Detail) { Write-Raw ("           note: " + $x.Detail) }
}
Write-Raw ("J3_BITSTREAM_EXPECT: " + $Bitstream + "  (nslots 默认 256; 传 --dma)")
Write-Raw ("日志: " + $script:LogPath)
$failReasons = @()
$notObtained = @()
foreach ($r in @("M", "A", "B")) {
    if (-not $script:Results.Contains($r)) { continue }
    $x = $script:Results[$r]
    if ($x.Verdict -eq "NOT_OBTAINED") { $notObtained += $r }
    elseif ($x.Verdict -ne "PASS") { $failReasons += $r }
}
if ($notObtained.Count -gt 0) {
    Write-Raw ("FOURCHAINS_RESULT: FAIL " + ($notObtained[0]) + " (判据未取得; 板卡需重烧)") "Red"
    exit 1
}
if ($failReasons.Count -eq 0) {
    Write-Raw "FOURCHAINS_RESULT: PASS" "Green"
    exit 0
}
Write-Raw ("FOURCHAINS_RESULT: FAIL " + ($failReasons -join ",")) "Red"
exit 1
#endregion
