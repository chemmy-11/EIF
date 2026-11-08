#==============================================================================
# stall_watchdog.ps1 -- prj13 P1-6  automatic DMA/pack stall detect + recover
#-----------------------------------------------------------------------------
# WHY
#   On 2026-11-06/07 every stall of the write path needed a manual BitElf
#   re-burn (60-90 s) before a data window could be reopened. The root cause is
#   the one-sided async_fifo reset (see prj12/out/evidence_2026-11-07_dma_stall/
#   AUDIT_mechanism.md); B1 fixes it in RTL, but the recovery watchdog is still
#   needed for (a) pre-B1 bitstreams, (b) any second/unknown lock path.
#   This script turns detect -> recover -> re-verify into one unattended loop.
#
# DETECTION (two independent evidences; never judge from ch_up alone,
#            the 2026-11-07 stall had ch_up=1 while pk_frames was already dead)
#   1) ILA6 : pfwd_wr grows by >= -RaiseThreshold while pk_frames does NOT move
#   2) UART : U mode=1 and the U wdbg word is identical across two samples
#             (frozen reporter = nothing committed since the ui-domain reset)
#   Recorded for the operator, per the stall fingerprint in the handbook pit
#   table (mem_len_err>0 + mem_stall=0 + mem_ost=0 + wdbg last_commit_len=0):
#       wdbg low 16 bits  = last_commit_len   (0 in a confirmed stall)
#       wdbg bits 23:16   = last_alloc_slot
#   -StrictFingerprint additionally requires last_commit_len == 0 and, with
#   -Ila3Confirm, mem_len_err>0 && mem_stall==0 && mem_ost==0 from ILA3.
#
# RECOVERY LADDER (-RecoverMode)
#   system : xsct "rst -system" -> MIG ui_clk_sync_rst -> ui_rst_n
#            NOT VALIDATED on board (prj12 EXPERIMENT_MATRIX.md C3). Cheap (5-15 s).
#   bitelf : twin_burn.ps1 -Mode BitElf  (known good, 60-90 s) <- default
#   ladder : system first, escalate to bitelf if the 3-frame probe fails
#   none   : detect + log only
#   Every action is followed by: serial 'd' (DMA mode) then a 3-frame probe
#   (run-id 0x91) then ILA6 and the acceptance "pk_frames +3".
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stall_watchdog.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stall_watchdog.ps1 -SelfTest
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stall_watchdog.ps1 -Com COM6 -PollSeconds 30
#   ... -RecoverMode ladder -MaxRecover 3 -Once
#
# EXIT CODES
#   0 = clean (dry-run ok / self-test ok / recovered / still healthy at -Once)
#   1 = recovery failed or MaxRecover reached (human needed)
#   2 = configuration or input error
#
# STATUS: script complete, LOGIC self-tested offline (-SelfTest); NEVER executed
#         against a board (board offline 2026-11-08). Detection thresholds are
#         hypotheses until the first on-board run. PowerShell 5.1, ASCII only.
#==============================================================================
param(
    [string]$Com = 'COM6',
    [int]$Baud = 9600,
    [string]$Cable = '210512180081',
    [string]$HwServer = 'localhost:3121',
    [ValidateSet('A', 'B')][string]$Board = 'A',
    [int]$PollSeconds = 30,
    [int]$MaxRecover = 3,
    [int]$RaiseThreshold = 3,
    [ValidateSet('bitelf', 'system', 'ladder', 'none')][string]$RecoverMode = 'bitelf',
    [int]$SettleSeconds = 8,
    [int]$ProbeWaitSeconds = 5,
    [string]$ProjRoot = 'D:\FPGA\prj\project_13',
    [string]$BurnScript = 'D:\FPGA\prj\project_12\out\twin_burn.ps1',
    [string]$SerialScript = 'D:\FPGA\prj\project_12\out\serial_snapshot.ps1',
    [string]$OutDir = '',
    [string]$PythonExe = 'py',
    # ADDRESS SEMANTICS (project decision 2026-11-08 20:40):
    #   This watchdog guards the P1/B1 BASELINE bitstream, whose board IP is
    #   hard-coded to 192.168.1.10 -> the 3-frame probe MUST use --scheme p1.
    #   The 10.10.0.x 'handbook' scheme is only valid once a P2 bitstream is on
    #   the board; 'protocol' (192.168.50.x) is the third preset.
    #   twin_send.py's own --scheme default is 'protocol', so an omitted flag
    #   would silently probe the wrong address space -- hence the explicit
    #   default below and SelfTest assertion G4 which pins it.
    [ValidateSet('p1', 'handbook', 'protocol')][string]$IpScheme = 'p1',
    [switch]$DryRun,
    [switch]$SelfTest,
    [switch]$StrictFingerprint,
    [switch]$Ila3Confirm,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'

#--------------------------------------------------------------- foundation
$Vivado  = 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat'
$Xsct    = 'D:\Xilinx\Vitis\2023.1\bin\xsct.bat'
$AsciiTmp = 'D:\FPGA\.tmp'
$IlaScript = Join-Path $ProjRoot 'scripts\ila_capture.tcl'
$Ila3Script = Join-Path $ProjRoot 'scripts\ila_capture_any.tcl'
$DmaScript = Join-Path $ProjRoot 'scripts\serial_dma_mode.ps1'
$SendScript = Join-Path $ProjRoot 'pc\twin_send.py'

if ($OutDir -eq '') {
    $OutDir = Join-Path $ProjRoot 'out\evidence_2026-11-08_p1_suite\watchdog'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogPath = Join-Path $OutDir ("watchdog_{0}.log" -f $ts)
$script:Recoveries = 0

function Say([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    # Write-Host, not Write-Output: Say is called from functions whose return
    # value is consumed, and Write-Output would be swallowed into that value.
    Write-Host $line
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding ascii
}

function Die([string]$m) {
    Say ("WATCHDOG_ERROR: " + $m)
    exit 2
}

#----------------------------------------------------------- serialisation
function Assert-NoVivadoBusy {
    $p = @(Get-Process -Name 'vivado', 'xsct', 'xsim' -ErrorAction SilentlyContinue)
    if ($p.Count -gt 0) {
        $names = ($p | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', '
        return $names
    }
    return ''
}

#-----------------------------------------------------------------------------
# DRY-RUN GUARD (2026-11-08, after a measured violation)
#   On 2026-11-08 18:35:00 a -DryRun invocation still launched Vivado: the
#   old code reached Get-Ila6Csv before checking the switch, so a board-less
#   machine paid ~20 s of a global-serial Vivado session that other work was
#   waiting for (see out/evidence_2026-11-08_p1_suite/watchdog/
#   ila6_poll_183500.console.log: "Xilinx cs_server", "Exiting Vivado").
#   A dry-run must launch NOTHING. Every external launch now goes through
#   Test-CanLaunch, which refuses under -DryRun, prints "DRY-NOEXEC: ..." with
#   the exact command it would have run, and counts the refusal.
#   -SelfTest asserts this guard is live and that the log carries none of the
#   three Vivado signatures.
#-----------------------------------------------------------------------------
$script:DryRun  = $DryRun.IsPresent
$script:DryHits = 0
$script:ForbiddenLog = @('Xilinx cs_server', 'Launch Output', 'Exiting Vivado')

function Test-CanLaunch([string]$what, [string]$cmdline) {
    if ($script:DryRun) {
        $script:DryHits = $script:DryHits + 1
        Say ("DRY-NOEXEC: {0}  [{1}]" -f $what, $cmdline)
        return $false
    }
    return $true
}

#-------------------------------------------------------------------------
# PURE DECISION LOGIC -- no I/O, so it can be self-tested offline.
# Samples are PSCustomObjects with: ChUp, Arst, Pk, Pfwd, Up, Hard, Soft
# UART blocks: Mode, Wdbg, Len, Slot
# Returns: State, Reason
#   LINK_DOWN | NO_TRAFFIC | DATA_FLOWING | SUSPECT_STALL |
#   STALL_CONFIRMED | FRESH_REPORTER
#-------------------------------------------------------------------------
function Get-WatchdogState {
    param($Prev, $Cur, $UPrev, $UCur, [int]$Raise, [switch]$Strict)

    if ($null -eq $Cur) { return [pscustomobject]@{ State = 'NO_SAMPLE'; Reason = 'no ILA sample' } }
    if ([int]$Cur.ChUp -ne 1) {
        return [pscustomobject]@{ State = 'LINK_DOWN'; Reason = 'ch_up=0, a link drop is not a stall' }
    }
    if ($null -eq $Prev) {
        return [pscustomobject]@{ State = 'NO_SAMPLE'; Reason = 'first sample, no delta yet' }
    }

    # counters are 16-bit and wrap; compare modulo 65536
    $dPk   = ([int]$Cur.Pk   - [int]$Prev.Pk)   -band 0xFFFF
    $dPfwd = ([int]$Cur.Pfwd - [int]$Prev.Pfwd) -band 0xFFFF

    if ($dPfwd -lt $Raise) {
        return [pscustomobject]@{ State = 'NO_TRAFFIC'; Reason = ("pfwd delta {0} < raise threshold {1}" -f $dPfwd, $Raise) }
    }
    if ($dPk -gt 0) {
        return [pscustomobject]@{ State = 'DATA_FLOWING'; Reason = ("pfwd +{0} and pk +{1}" -f $dPfwd, $dPk) }
    }

    # pfwd advanced, pk frozen -> corroborate with the UART reporter
    if (($null -eq $UPrev) -or ($null -eq $UCur)) {
        return [pscustomobject]@{ State = 'SUSPECT_STALL'; Reason = ("pfwd +{0} while pk frozen; no UART to confirm" -f $dPfwd) }
    }
    if ([int]$UCur.Mode -ne 1) {
        return [pscustomobject]@{ State = 'FRESH_REPORTER'; Reason = ("pfwd +{0} / pk frozen but firmware mode={1} (not DMA)" -f $dPfwd, $UCur.Mode) }
    }
    if ([string]$UPrev.Wdbg -ne [string]$UCur.Wdbg) {
        return [pscustomobject]@{ State = 'SUSPECT_STALL'; Reason = ("pfwd +{0} / pk frozen but wdbg moved {1}->{2}" -f $dPfwd, $UPrev.Wdbg, $UCur.Wdbg) }
    }
    if ($Strict) {
        if ([int]$UCur.Len -ne 0) {
            return [pscustomobject]@{ State = 'SUSPECT_STALL'; Reason = ("wdbg frozen at {0} but last_commit_len={1} (expected 0)" -f $UCur.Wdbg, $UCur.Len) }
        }
    }
    return [pscustomobject]@{ State = 'STALL_CONFIRMED'; Reason = ("pfwd +{0}, pk frozen, U mode=1, wdbg frozen at {1} (last_commit_len={2})" -f $dPfwd, $UCur.Wdbg, $UCur.Len) }
}

#-------------------------------------------------------------------------
# I/O: ILA6 capture + CSV parse
# ILA6 CSV is a named-header file (sample,window,trigger,dbg_link_ok,...), so
# parse by name and fall back to the known positional order if a name is absent.
#-------------------------------------------------------------------------
function Get-Ila6Csv([string]$tag, [string]$scriptPath) {
    if ($scriptPath -eq '') { $scriptPath = $IlaScript }
    $csv = Join-Path $OutDir ("ila6_{0}_{1}.csv" -f $tag, (Get-Date -Format 'HHmmss'))
    $console = Join-Path $OutDir ("ila6_{0}_{1}.console.log" -f $tag, (Get-Date -Format 'HHmmss'))
    $busy = Assert-NoVivadoBusy
    if ($busy -ne '') { Say ("SERIAL_BUSY: {0} -> skip this capture" -f $busy); return $null }
    $preview = "{0} -mode batch -source {1} -tclargs {2} {3} {4}" -f $Vivado, $scriptPath, $HwServer, $Cable, $csv
    if (-not (Test-CanLaunch 'vivado ILA capture' $preview)) { return $null }
    Say ("ILA: {0} -> {1}" -f (Split-Path -Leaf $scriptPath), $csv)
    Push-Location 'D:\FPGA'
    try {
        $args = @('-mode', 'batch', '-source', $scriptPath, '-tclargs', $HwServer, $Cable, $csv)
        if ($scriptPath -ne $IlaScript) { $args += @((Join-Path $ProjRoot 'scripts\probes.ltx'), 'dbg_calib') }
        $p = Start-Process -FilePath $Vivado -ArgumentList $args -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $console -RedirectStandardError ($console + '.err')
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $csv)) { Say ("WARN: no csv produced ({0}), see {1}" -f $tag, $console); return $null }
    return $csv
}

function Read-Ila6([string]$csv) {
    $raw = @(Get-Content -LiteralPath $csv)
    if ($raw.Count -lt 2) { return $null }
    $hdr = @($raw[0].Split(','))
    # data rows start after the two header rows (names + radix)
    $data = @($raw | Where-Object { $_ -match '^\d+,\d+,\d+,' })
    if ($data.Count -eq 0) { return $null }
    $last = @($data[$data.Count - 1].Split(','))
    $idx = @{}
    for ($i = 0; $i -lt $hdr.Count; $i++) { $idx[$hdr[$i].Trim()] = $i }
    function Pick([string[]]$cells, $map, [string]$name, [int]$fallback, [int]$hexDigits) {
        $v = ''
        if ($map.ContainsKey($name)) { $v = $cells[$map[$name]] } else { $v = $cells[$fallback] }
        $v = $v.Trim()
        if ($hexDigits -gt 0) { return [Convert]::ToInt32($v, 16) }
        return [int]$v
    }
    return [pscustomobject]@{
        ChUp = (Pick $last $idx 'dbg_ch_up' 4 0)
        Arst = (Pick $last $idx 'dbg_aurora_rst' 16 0)
        Pk   = (Pick $last $idx 'dbg_pk_frames[15:0]' 12 1)
        Pfwd = (Pick $last $idx 'dbg_pfwd_wr[15:0]' 14 1)
        Up   = (Pick $last $idx 'dbg_up_frames[15:0]' 13 1)
        Hard = (Pick $last $idx 'dbg_hard_err_cnt[15:0]' 10 1)
        Soft = (Pick $last $idx 'dbg_soft_err_cnt[15:0]' 11 1)
        File = $csv
    }
}

function Read-Ila3([string]$csv) {
    $raw = @(Get-Content -LiteralPath $csv)
    if ($raw.Count -lt 3) { return $null }
    $hdr = @($raw[0].Split(','))
    $data = @($raw | Where-Object { $_ -match '^\d+,\d+,\d+,' })
    if ($data.Count -eq 0) { return $null }
    $last = @($data[$data.Count - 1].Split(','))
    $idx = @{}
    for ($i = 0; $i -lt $hdr.Count; $i++) { $idx[$hdr[$i].Trim()] = $i }
    function PickH([string[]]$cells, $map, [string]$name, [int]$fallback) {
        $v = ''
        if ($map.ContainsKey($name)) { $v = $cells[$map[$name]] } else { $v = $cells[$fallback] }
        return [Convert]::ToInt32($v.Trim(), 16)
    }
    return [pscustomobject]@{
        LenErr = (PickH $last $idx 'dbg_mem_len_err[15:0]' 5)
        Stall  = (PickH $last $idx 'dbg_mem_stall[15:0]' 4)
        Ost    = (PickH $last $idx 'dbg_mem_ost[8:0]' 6)
        WrFrm  = (PickH $last $idx 'dbg_mem_wr_frm[15:0]' 3)
        File   = $csv
    }
}

#-------------------------------------------------------------------------
# I/O: UART U snapshot + parse
#-------------------------------------------------------------------------
function Get-SerialU([string]$tag) {
    $out = Join-Path $OutDir ("serial_U_{0}_{1}.txt" -f $tag, (Get-Date -Format 'HHmmss'))
    $preview = "powershell -File {0} -Com {1} -Baud {2} -Command U -Seconds 2 -Out {3}" -f $SerialScript, $Com, $Baud, $out
    if (-not (Test-CanLaunch 'serial U snapshot (opens the COM port)' $preview)) { return $null }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $SerialScript -Com $Com -Baud $Baud -Command U -Seconds 2 -Out $out 2>&1 |
        ForEach-Object { }
    if (-not (Test-Path -LiteralPath $out)) { Say ("WARN: no UART snapshot ({0})" -f $tag); return $null }
    $txt = [System.IO.File]::ReadAllText($out)
    if ($txt.Length -eq 0) { Say ("WARN: empty UART snapshot ({0})" -f $tag); return $null }
    $mode = -1
    if ($txt -match 'mode=(\d+)') { $mode = [int]$Matches[1] }
    $wdbg = ''
    foreach ($ln in ($txt -split "`r?`n")) {
        if ($ln -match 'wdbg:') {
            $toks = @($ln.Substring($ln.IndexOf('wdbg:') + 5).Trim().Split(' ') | Where-Object { $_ -ne '' })
            if ($toks.Count -gt 0) { $wdbg = $toks[$toks.Count - 1] }
        }
    }
    $len = -1
    $slot = -1
    if ($wdbg -match '^[0-9a-fA-F]{8}$') {
        $w = [Convert]::ToInt32($wdbg, 16)
        $len = $w -band 0xFFFF
        $slot = ($w -shr 16) -band 0xFF
    }
    return [pscustomobject]@{ Mode = $mode; Wdbg = $wdbg; Len = $len; Slot = $slot; File = $out }
}

#-------------------------------------------------------------------------
# recovery actions
#-------------------------------------------------------------------------
function Invoke-SystemReset {
    Say ("RECOVER: xsct rst -system (NOT validated on board; prj12 EXPERIMENT_MATRIX.md C3)")
    $tcl = Join-Path $OutDir ("xsct_rst_system_{0}.tcl" -f (Get-Date -Format 'HHmmss'))
    $body = @(
        'if {[catch {connect} e]} { puts "CONNECT_ERR: $e"; exit 1 }',
        'if {[catch {targets -set -filter {name =~ "*xcku*"}} e2]} { puts "DEV_ERR: $e2"; exit 1 }',
        'if {[catch {rst -system} e3]} { puts "RST_ERR: $e3"; exit 1 }',
        'puts "RST_SYSTEM_OK"',
        'exit 0'
    )
    Set-Content -LiteralPath $tcl -Value $body -Encoding ascii
    if (-not (Test-CanLaunch 'xsct rst -system (resets the whole device)' ("{0} {1}" -f $Xsct, $tcl))) { return 1 }
    & $Xsct $tcl 2>&1 | ForEach-Object { Say ("  xsct: " + $_) }
    return $LASTEXITCODE
}

function Invoke-BitElfBurn {
    Say ("RECOVER: twin_burn -Board {0} -Mode BitElf -Run (known good, 60-90 s)" -f $Board)
    $preview = "powershell -File {0} -Board {1} -Mode BitElf -Run" -f $BurnScript, $Board
    if (-not (Test-CanLaunch 'twin_burn BitElf (programs the board)' $preview)) { return 1 }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $BurnScript -Board $Board -Mode BitElf -Run 2>&1 |
        ForEach-Object { Say ("  burn: " + $_) }
    return $LASTEXITCODE
}

function Enter-DmaMode {
    Say ("RECOVER: serial 'd' until banner says now=DMA")
    $preview = "powershell -File {0} -Com {1} -Baud {2}" -f $DmaScript, $Com, $Baud
    if (-not (Test-CanLaunch 'serial d (toggles the firmware mode)' $preview)) { return 1 }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $DmaScript -Com $Com -Baud $Baud 2>&1 |
        ForEach-Object { Say ("  d: " + $_) }
    return $LASTEXITCODE
}

# --- one place that builds the probe argv, so the real call, the dry-run
#     preview and the SelfTest assertion can never drift apart ---------------
function Get-ProbeArgs([string]$scheme) {
    return @($SendScript, '--scheme', $scheme, '--count', '3', '--len', '100', '--run-id', '0x91')
}

function Get-ProbeCmdline([string]$scheme) {
    return ("{0} {1}" -f $PythonExe, ((Get-ProbeArgs $scheme) -join ' '))
}

# acceptance: a 3-frame probe must advance pk_frames by exactly >= 3
function Test-Recovered([int]$PkBefore, [string]$tag) {
    Say ("VERIFY: 3-frame probe (run-id 0x91, scheme={0}), pk_frames must advance from {1}" -f $IpScheme, $PkBefore)
    $preview = Get-ProbeCmdline $IpScheme
    if (-not (Test-CanLaunch '3-frame probe (sends Ethernet frames)' $preview)) { return $false }
    $probeArgs = Get-ProbeArgs $IpScheme
    & $PythonExe @probeArgs 2>&1 | ForEach-Object { Say ("  send: " + $_) }
    Start-Sleep -Seconds $ProbeWaitSeconds
    $csv = Get-Ila6Csv $tag $IlaScript
    if ($null -eq $csv) { return $false }
    $s = Read-Ila6 $csv
    if ($null -eq $s) { return $false }
    $delta = ([int]$s.Pk - $PkBefore) -band 0xFFFF
    Say ("VERIFY: pk_frames {0} -> {1} (delta={2})" -f $PkBefore, $s.Pk, $delta)
    return ($delta -ge 3)
}

function Invoke-Recovery([int]$PkBefore) {
    Say ("=== RECOVERY #{0} (mode={1}, pk_before={2}) ===" -f ($script:Recoveries + 1), $RecoverMode, $PkBefore)
    $script:Recoveries = $script:Recoveries + 1

    if ($RecoverMode -eq 'none') { Say "RECOVER: none (detect only)"; return $false }

    $tried = @()
    if (($RecoverMode -eq 'system') -or ($RecoverMode -eq 'ladder')) {
        $tried += 'system'
        Invoke-SystemReset | Out-Null
        Start-Sleep -Seconds $SettleSeconds
        Enter-DmaMode | Out-Null
        Start-Sleep -Seconds 3
        if (Test-Recovered $PkBefore 'after_system') {
            Say "RECOVERED (system reset): 3-frame probe OK"
            return $true
        }
        if ($RecoverMode -eq 'system') {
            Say "RECOVER_FAILED (system reset): escalating is disabled for -RecoverMode system"
            return $false
        }
        Say "RECOVER_FAILED (system reset) -> escalating to BitElf"
    }

    $tried += 'bitelf'
    Invoke-BitElfBurn | Out-Null
    Start-Sleep -Seconds $SettleSeconds
    Enter-DmaMode | Out-Null
    Start-Sleep -Seconds 3
    if (Test-Recovered $PkBefore 'after_bitelf') {
        Say "RECOVERED (BitElf): 3-frame probe OK"
        return $true
    }
    Say "RECOVER_HOPELESS: tried $(($tried -join '+')) -> manual intervention required"
    Say "  grab ILA0 (dbg_mem_u_wr/dbg_mem_u_drop) + ILA3 (dbg_mem_len_err/mem_stall/mem_ost) + U before rebooting"
    return $false
}

#-------------------------------------------------------------------------
# OFFLINE SELF-TEST of the decision logic (no board, no Vivado)
#-------------------------------------------------------------------------
function Invoke-SelfTest {
    Say "=== SELF-TEST (pure decision logic, no hardware touched) ==="
    function S([int]$chup, [int]$pk, [int]$pfwd) {
        return [pscustomobject]@{ ChUp = $chup; Pk = $pk; Pfwd = $pfwd; Up = 0; Hard = 0; Soft = 0 }
    }
    function U([int]$mode, [string]$wdbg) {
        $len = -1
        if ($wdbg -match '^[0-9a-fA-F]{8}$') { $len = ([Convert]::ToInt32($wdbg, 16)) -band 0xFFFF }
        return [pscustomobject]@{ Mode = $mode; Wdbg = $wdbg; Len = $len }
    }

    $cases = @(
        @{ N = 'link down is not a stall';      P = (S 1 0 0);     C = (S 0 0 0);       UP = (U 1 '00000000'); UC = (U 1 '00000000'); E = 'LINK_DOWN' },
        @{ N = 'no traffic to judge';           P = (S 1 10 10);   C = (S 1 10 12);     UP = (U 1 '000f009a'); UC = (U 1 '000f009a'); E = 'NO_TRAFFIC' },
        @{ N = 'healthy data path';             P = (S 1 10 10);   C = (S 1 30 30);     UP = (U 1 '000f009a'); UC = (U 1 '000f0120'); E = 'DATA_FLOWING' },
        @{ N = 'stall confirmed (wdbg frozen)'; P = (S 1 10 10);   C = (S 1 10 30);     UP = (U 1 '000f0000'); UC = (U 1 '000f0000'); E = 'STALL_CONFIRMED' },
        @{ N = 'suspect only (reporter moved)'; P = (S 1 10 10);   C = (S 1 10 30);     UP = (U 1 '000f009a'); UC = (U 1 '000f0120'); E = 'SUSPECT_STALL' },
        @{ N = 'not in DMA mode';               P = (S 1 10 10);   C = (S 1 10 30);     UP = (U 0 '000f009a'); UC = (U 0 '000f009a'); E = 'FRESH_REPORTER' },
        @{ N = 'counter wrap (16-bit)';         P = (S 1 65530 65530); C = (S 1 65534 65536); UP = (U 1 '000f0120'); UC = (U 1 '000f0200'); E = 'DATA_FLOWING' },
        @{ N = 'big pfwd jump, pk frozen';      P = (S 1 0 0);     C = (S 1 0 20);      UP = (U 1 '000f0000'); UC = (U 1 '000f0000'); E = 'STALL_CONFIRMED' }
    )

    $pass = 0
    $fail = 0
    foreach ($c in $cases) {
        $r = Get-WatchdogState -Prev $c.P -Cur $c.C -UPrev $c.UP -UCur $c.UC -Raise $RaiseThreshold
        $ok = ($r.State -eq $c.E)
        if ($ok) { $pass = $pass + 1 } else { $fail = $fail + 1 }
        $mark = 'FAIL'
        if ($ok) { $mark = 'OK' }
        Say ("  [{0}] {1,-34} expect={2,-16} got={3,-16} {4}" -f $mark, $c.N, $c.E, $r.State, $r.Reason)
    }

    # strict fingerprint must refuse a frozen-but-committed reporter
    $r = Get-WatchdogState -Prev (S 1 10 10) -Cur (S 1 10 30) -UPrev (U 1 '000f009a') -UCur (U 1 '000f009a') -Raise $RaiseThreshold -Strict
    $ok = ($r.State -eq 'SUSPECT_STALL')
    if ($ok) { $pass = $pass + 1 } else { $fail = $fail + 1 }
    $mark = 'FAIL'
    if ($ok) { $mark = 'OK' }
    Say ("  [{0}] {1,-34} expect={2,-16} got={3,-16} {4}" -f $mark, 'strict: len!=0 refuses', 'SUSPECT_STALL', $r.State, $r.Reason)

    #---------------------------------------------------------------------
    # DRY-RUN GUARD ASSERTIONS (added 2026-11-08 after the 18:35 violation,
    # where -DryRun still launched Vivado for ~20 s on a board-less machine).
    #   G1: the guard really refuses and counts the refusal
    #   G2: this log carries none of the three Vivado signatures
    #   G3: no new ILA capture console log was produced during this run
    #---------------------------------------------------------------------
    $startMark = (Get-Date).AddSeconds(-1)

    $savedDry = $script:DryRun
    $savedHits = $script:DryHits
    $script:DryRun = $true
    $script:DryHits = 0
    $guarded = Test-CanLaunch 'selftest dummy vivado' 'vivado.bat -mode batch (never runs)'
    $hits = $script:DryHits
    $script:DryRun = $savedDry
    $script:DryHits = $savedHits

    $okG1 = (($guarded -eq $false) -and ($hits -eq 1))
    if ($okG1) { $pass = $pass + 1 } else { $fail = $fail + 1 }
    $m1 = 'FAIL'; if ($okG1) { $m1 = 'OK' }
    Say ("  [{0}] {1,-34} expect={2,-16} got={3,-16} {4}" -f $m1, 'guard refuses under dry-run', 'blocked+counted', ("ran={0} hits={1}" -f $guarded, $hits), 'nothing launched')

    $txt = ''
    if (Test-Path -LiteralPath $script:LogPath) { $txt = [System.IO.File]::ReadAllText($script:LogPath) }
    $found = @()
    foreach ($bad in $script:ForbiddenLog) { if ($txt -match [regex]::Escape($bad)) { $found = $found + $bad } }
    $okG2 = ($found.Count -eq 0)
    if ($okG2) { $pass = $pass + 1 } else { $fail = $fail + 1 }
    $m2 = 'FAIL'; if ($okG2) { $m2 = 'OK' }
    # NOTE: the markers themselves are NEVER echoed into the log -- otherwise this
    # very assertion would make the log fail the next grep (self-defeating).
    Say ("  [{0}] {1,-34} expect={2,-16} got={3,-16} {4}" -f $m2, 'log free of vivado markers', '0 of 3 markers', ("{0} marker(s)" -f $found.Count), 'marker text intentionally not printed')

    $newConsoles = @()
    if (Test-Path -LiteralPath $OutDir) {
        $newConsoles = @(Get-ChildItem -LiteralPath $OutDir -Filter 'ila6_*.console.log' -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.LastWriteTime -gt $startMark })
    }
    $okG3 = ($newConsoles.Count -eq 0)
    if ($okG3) { $pass = $pass + 1 } else { $fail = $fail + 1 }
    $m3 = 'FAIL'; if ($okG3) { $m3 = 'OK' }
    Say ("  [{0}] {1,-34} expect={2,-16} got={3,-16} {4}" -f $m3, 'no new ILA capture log', '0', $newConsoles.Count, 'nothing launched')

    #---------------------------------------------------------------------
    # G4: ADDRESS SEMANTICS PIN (project decision 2026-11-08 20:40)
    #   This watchdog guards the P1/B1 baseline bitstream whose board IP is
    #   192.168.1.10, so the probe must carry "--scheme p1". twin_send.py's own
    #   default is "--scheme protocol"; if the pc/ defaults ever change, or if
    #   someone drops the flag while refactoring, this assertion fails instead
    #   of silently probing the wrong address space.
    #---------------------------------------------------------------------
    $probeCmd = Get-ProbeCmdline $IpScheme
    $okG4 = (($IpScheme -eq 'p1') -and ($probeCmd -match '--scheme\s+p1(\s|$)'))
    if ($okG4) { $pass = $pass + 1 } else { $fail = $fail + 1 }
    $m4 = 'FAIL'; if ($okG4) { $m4 = 'OK' }
    Say ("  [{0}] {1,-34} expect={2,-16} got={3,-16} {4}" -f $m4, 'probe scheme pinned to p1', 'p1 + --scheme p1', ("scheme={0}" -f $IpScheme), $probeCmd)

    Say ("SELFTEST: PASS={0} FAIL={1}" -f $pass, $fail)
    if ($fail -eq 0) { Say "SELFTEST_RESULT: PASS"; return 0 }
    Say "SELFTEST_RESULT: FAIL"
    return 1
}

#=========================================================================
# MAIN
#=========================================================================
Say "=== stall_watchdog (prj13 P1-6) ==="
Say ("log        : " + $script:LogPath)
Say ("board/com  : {0} / {1} @ {2}" -f $Board, $Com, $Baud)
Say ("mode       : recover={0} maxrecover={1} poll={2}s raise>={3}" -f $RecoverMode, $MaxRecover, $PollSeconds, $RaiseThreshold)
$schemeLabel = @{ p1 = 'P1 baseline'; handbook = 'P2 / handbook 10.10.0.x'; protocol = 'protocol v0.2 192.168.50.x' }
Say ("ADDR_SCHEME {0} ({1}); use -IpScheme handbook after a P2 bitstream" -f $IpScheme, $schemeLabel[$IpScheme])
Say ("probe cmd  : " + (Get-ProbeCmdline $IpScheme))
Say ("dryrun     : {0}  strict={1}  ila3confirm={2}" -f $DryRun.IsPresent, $StrictFingerprint.IsPresent, $Ila3Confirm.IsPresent)

if ($SelfTest.IsPresent) {
    $rc = Invoke-SelfTest
    exit $rc
}

# ---------------- input validation (both dry-run and real) -----------------
$need = @($ProjRoot, $IlaScript, $DmaScript, $SendScript, $Vivado, $SerialScript)
if (($RecoverMode -eq 'bitelf') -or ($RecoverMode -eq 'ladder')) { $need += $BurnScript }
if (($RecoverMode -eq 'system') -or ($RecoverMode -eq 'ladder')) { $need += $Xsct }
if ($Ila3Confirm.IsPresent) { $need += $Ila3Script }
$missing = @()
foreach ($p in $need) { if (-not (Test-Path -LiteralPath $p)) { $missing += $p } }
if ($missing.Count -gt 0) { Die ("missing input(s): " + ($missing -join '; ')) }

foreach ($p in @($ProjRoot, $OutDir, $AsciiTmp)) {
    $bad = $false
    foreach ($ch in $p.ToCharArray()) { if ([int]$ch -gt 127) { $bad = $true } }
    if ($bad) { Die ("non-ASCII path in the Vivado chain: " + $p) }
}
New-Item -ItemType Directory -Force -Path $AsciiTmp | Out-Null
$env:TEMP = $AsciiTmp
$env:TMP = $AsciiTmp
Say ("TEMP/TMP   : " + $env:TEMP)

if ($DryRun.IsPresent) {
    Say ""
    Say "=== DRY-RUN plan (no recovery action will be executed) ==="
    Say ("detect   : ILA6 -> {0}" -f $IlaScript)
    Say ("           {0} -mode batch -source <ila_capture.tcl> -tclargs {1} {2} <csv>" -f $Vivado, $HwServer, $Cable)
    Say ("uart     : {0} -Com {1} -Command U -Seconds 2 -Out <txt>" -f $SerialScript, $Com)
    if ($Ila3Confirm.IsPresent) { Say ("ila3     : {0} -mode batch -source <ila_capture_any.tcl> -tclargs {1} {2} <csv> probes.ltx dbg_calib" -f $Vivado, $HwServer, $Cable) }
    Say ("ladder   : {0}" -f $RecoverMode)
    if (($RecoverMode -eq 'system') -or ($RecoverMode -eq 'ladder')) { Say ("  step 1 : xsct rst -system (unvalidated)") }
    if (($RecoverMode -eq 'bitelf') -or ($RecoverMode -eq 'ladder')) { Say ("  step 2 : powershell -File {0} -Board {1} -Mode BitElf -Run" -f $BurnScript, $Board) }
    Say ("  then   : powershell -File {0} -Com {1}" -f $DmaScript, $Com)
    Say ("  verify : {0} ; ILA6 pk_frames must advance >= 3" -f (Get-ProbeCmdline $IpScheme))
    Say ("limits   : MaxRecover={0}, PollSeconds={1}, raise>={2}" -f $MaxRecover, $PollSeconds, $RaiseThreshold)
    Say ("evidence : {0}" -f $OutDir)
}

# ------------------------------- sampling loop ----------------------------
$prev = $null
$prevU = $null
$polls = 0
$aborted = $false

while ($true) {
    $polls = $polls + 1

    # -DryRun never touches the hardware: no Vivado, no serial, no burn.
    # It prints the exact judgement it would make and the action it would take.
    if ($DryRun.IsPresent) {
        # Exercise the guard explicitly, so the dry-run log PROVES the refusal
        # path fires (SelfTest asserts DryHits > 0 and the absence of Vivado
        # signatures). Nothing below this point may launch a process.
        $previewIla = "{0} -mode batch -source {1} -tclargs {2} {3} <csv>" -f $Vivado, $IlaScript, $HwServer, $Cable
        $previewU   = "powershell -File {0} -Com {1} -Command U -Seconds 2 -Out <txt>" -f $SerialScript, $Com
        [void](Test-CanLaunch 'vivado ILA capture' $previewIla)
        [void](Test-CanLaunch 'serial U snapshot (opens the COM port)' $previewU)
        Say ("DRYRUN sample {0}: judgement skipped (no sample taken by design)" -f $polls)
        Say "DRYRUN criteria:"
        Say ("  LINK_DOWN        when ch_up != 1 (a link drop is never a stall)")
        Say ("  NO_TRAFFIC       when pfwd_wr delta < {0}" -f $RaiseThreshold)
        Say ("  DATA_FLOWING     when pfwd_wr delta >= {0} and pk_frames delta > 0" -f $RaiseThreshold)
        Say ("  STALL_CONFIRMED  when pfwd_wr delta >= {0} and pk_frames delta = 0 and U mode=1 and wdbg frozen" -f $RaiseThreshold)
        Say ("  action           -> {0} ladder, max {1} recoveries, then a 3-frame probe (pk_frames must advance >= 3)" -f $RecoverMode, $MaxRecover)
        Say ("DRYRUN_REFUSED   : {0} external launch(es) blocked by the guard" -f $script:DryHits)
        Say "WATCHDOG: DRYRUN_OK (plan printed, nothing executed, no process launched)"
        exit 0
    }

    $csv = Get-Ila6Csv 'poll' $IlaScript
    $cur = $null
    if ($null -ne $csv) { $cur = Read-Ila6 $csv }
    if ($null -eq $cur) {
        Say ("SAMPLE {0}: ILA6 unavailable (board offline / Vivado busy)" -f $polls)
        if ($Once.IsPresent) { exit 0 }
        Start-Sleep -Seconds $PollSeconds
        continue
    }
    Say ("SAMPLE {0}: ch_up={1} aurora_rst={2} pk={3} pfwd={4} up={5} hard={6} soft={7}" -f `
            $polls, $cur.ChUp, $cur.Arst, $cur.Pk, $cur.Pfwd, $cur.Up, $cur.Hard, $cur.Soft)

    $uCur = $null
    if ($null -ne $prev) { $uCur = Get-SerialU 'poll' }

    $verdict = Get-WatchdogState -Prev $prev -Cur $cur -UPrev $prevU -UCur $uCur -Raise $RaiseThreshold -Strict:$StrictFingerprint
    Say ("STATE: {0} ({1})" -f $verdict.State, $verdict.Reason)

    if ($verdict.State -eq 'STALL_CONFIRMED') {
        if ($Ila3Confirm.IsPresent) {
            $csv3 = Get-Ila6Csv 'stall3' $Ila3Script
            if ($null -ne $csv3) {
                $i3 = Read-Ila3 $csv3
                if ($null -ne $i3) {
                    Say ("ILA3: len_err={0} stall={1} ost={2} wr_frm={3}" -f $i3.LenErr, $i3.Stall, $i3.Ost, $i3.WrFrm)
                    $fpOk = (($i3.LenErr -gt 0) -and ($i3.Stall -eq 0) -and ($i3.Ost -eq 0))
                    if ($fpOk) { Say "FINGERPRINT: matches len_err>0 / stall=0 / ost=0" }
                    else { Say "FINGERPRINT_MISMATCH: ILA3 does not match the documented stall fingerprint" }
                }
            }
        }
        if ($script:Recoveries -ge $MaxRecover) {
            Say ("ABORT: MaxRecover={0} reached -> hand over to a human" -f $MaxRecover)
            $aborted = $true
            break
        }
        $pkBefore = [int]$cur.Pk
        if (Invoke-Recovery $pkBefore) {
            $prev = $null
            $prevU = $null
            if ($Once.IsPresent) { break }
            Start-Sleep -Seconds $PollSeconds
            continue
        }
        $aborted = $true
        break
    }

    # keep the UART reference from the previous poll: "wdbg frozen across two
    # consecutive samples" is the second, independent evidence
    if ($null -ne $uCur) { $prevU = $uCur }
    $prev = $cur

    if ($Once.IsPresent) { break }
    Start-Sleep -Seconds $PollSeconds
}

Say ("watchdog exit (polls={0} recoveries={1})" -f $polls, $script:Recoveries)
if ($aborted) {
    Say "WATCHDOG_RESULT: FAIL (human intervention required)"
    exit 1
}
Say "WATCHDOG_RESULT: PASS"
exit 0
