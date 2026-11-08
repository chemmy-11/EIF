# =============================================================================
# p1_selfcheck.ps1 -- prj13 M1: reproduce the whole prj12 P1 bring-up in ONE run.
#
# Why: the P1 flow (2026-11-06) is 7 hand-typed steps spread over two PCs, three
# tools and a pitfall table. Every typo or reordering costs a 90 s re-burn and
# leaves the DMA/pump in a dead state. This script is the machine-checked form
# of the prj12 dual-board bring-up manual section 2 (flow) + 3 (criteria) + 5 (triage).
#
# Steps (each prints "STEP <n> <NAME>: PASS|FAIL|SKIP <reason>"):
#   1 TARGETS  read-only  scripts\list_targets.tcl        (vivado; NEVER in -DryRun)
#   2 BURN     twin_burn.ps1 -Board <A|B> -Mode BitElf -Run   (bit + ELF, must pair)
#   3 DMA_MODE scripts\serial_dma_mode.ps1 -Com <COM>    (expect SERIAL_RESULT: PASS)
#   4 LINK     scripts\ila_capture.tcl -> CSV            (link_ok/ch_up/lane_up/pll/rst/hard/soft)
#   5 PROBE3   pc\twin_send.py --count 3 --run-id 0x91 -> ILA pk_frames +3
#   6 DUAL20   three SINGLE continuous >=180 s captures: 20 frames fwd (run_id 0x1), 20 frames
#              rev (0x2), and the 10 MiB one-way (1472 B x 7125, run_id 0x1) paced by
#              -SendIntervalMs (default 0.5 ms); every window judged by scripts\p1_judge.py
#   7 ARCHIVE  out\evidence_<date>_p1_selfcheck\  (verdict text + CSV + README + SHA256SUMS)
# Final line (always printed):
#   P1_SELFCHECK: PASS=<n> FAIL=<n> SKIP=<n>
#
# Pitfall discipline compiled in (see the manual section 5 table):
#   * both boards report the SAME JTAG cable serial (210512180081)
#     -> "-Board Both" is REJECTED here (exit 2), never "burn by guess".
#   * serial 'd' is a TOGGLE -> only the LAST DMAMODE banner counts
#     (that logic lives in serial_dma_mode.ps1, already fixed 2026-11-06).
#   * the data plane needs ONE continuous capture >= 180 s. Chunked capture is
#     how 2026-11-06 produced "0 frames but counters rising". -CaptureSeconds
#     below 180 is refused unless -AllowShortCapture is given (and then the run
#     is no longer M1 evidence).
#   * "the criterion did not fire" is NOT "the criterion passed": every step that
#     cannot actually be executed on this host reports SKIP, never PASS.
#
# -DryRun: no Vivado, no xsim, no serial port, no capture, no file written.
#          Only parameter validation + the exact command each step would run.
#          Must complete on a board-less machine and still print the summary.
#
# Helper resolution order (first hit wins; a miss is "SKIP helper-missing",
# never a crash):
#   <root>\scripts  ->  <root>\out  ->  <root>\pc  ->  ..\project_12\out
#   ->  ..\project_12\scripts  ->  ..\project_12\pc
#
# Usage (PC1 / board A):
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\p1_selfcheck.ps1 `
#       -Board A -Com COM6 -Cable 210512180081 -Iface "Ethernet"
#   powershell ... -File scripts\p1_selfcheck.ps1 -DryRun          # board-less dry run
#   ... -SkipBurn -SkipProbe     # bitstream already loaded / skip the pk+3 probe
#   ... -Step6DelaySeconds 90    # let the PEER PC catch up before the >=180 s windows
#   ... -SendIntervalMs 0.5      # 10 MiB pacing (default 0.5 ms; the 20-frame windows stay at 20 ms)
#   ... -Skip10MiB               # skip the 10 MiB window (then the run is NOT full M1 evidence)
#
# Exit: 0 = no FAIL (SKIP allowed), 1 = at least one FAIL, 2 = parameter error.
# ASCII only on purpose (Windows PowerShell 5.1 + any console codepage).
# =============================================================================
[CmdletBinding()]
param(
    [ValidateSet('A', 'B', 'Both')][string]$Board = 'A',
    [string]$Com = 'COM6',
    [string]$Cable = '210512180081',
    [ValidateSet('p1', 'handbook', 'protocol')][string]$IpScheme = 'p1',
    [switch]$DryRun,
    [string]$PrjRoot = '',
    [switch]$SkipBurn,
    [switch]$SkipProbe,
    [switch]$SkipArp,
    [string]$Iface = '',
    [string]$BoardMac = '',   # empty = derived from -IpScheme
    [int]$Port = 1234,
    [int]$CaptureSeconds = 180,
    [int]$SendDelaySeconds = 30,
    [int]$Step6DelaySeconds = 0,
    [double]$SendIntervalMs = 0.5,
    [switch]$Skip10MiB,
    [int]$WaitSeconds = 20,
    [int]$FrameLen = 100,
    [string]$HwServer = 'localhost:3121',
    [string]$Vivado = 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat',
    [string]$DateTag = '',
    [ValidateSet('auto', 'fwd', 'rev', 'none')][string]$LocalDir = 'auto',
    [switch]$JudgeOwn,
    [switch]$AllowShortCapture
)
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------- plumbing
$script:Pass = 0
$script:Fail = 0
$script:Skip = 0
$script:CmdLog = @()
$script:LogLines = @()
$script:Stamp = Get-Date -Format 'HHmmss'
$script:When = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

function Say([string]$s) {
    # Written straight to the console, NOT to the pipeline: every value-returning
    # helper below would otherwise return "message + value" and corrupt its caller.
    $script:LogLines += $s
    try { [Console]::WriteLine($s) } catch { }
}
function Add-Cmd([string]$s) {
    Say ("CMD: " + $s)
    $script:CmdLog += $s
}
function Step([string]$n, [string]$name, [string]$verdict, [string]$detail) {
    Say ("STEP {0} {1}: {2} {3}" -f $n, $name, $verdict, $detail)
    switch ($verdict) {
        'PASS' { $script:Pass++ }
        'FAIL' { $script:Fail++ }
        'SKIP' { $script:Skip++ }
    }
}
function Finish([int]$code, [string]$tail) {
    if ($tail -ne '') { Say $tail }
    Say ("P1_SELFCHECK: PASS={0} FAIL={1} SKIP={2}" -f $script:Pass, $script:Fail, $script:Skip)
    if ($script:Fail -gt 0) { Say "P1_SELFCHECK_RESULT: FAIL" } else { Say "P1_SELFCHECK_RESULT: PASS" }
    exit $code
}

# ------------------------------------------------------- project / helper paths
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$Root = $PrjRoot
if ($Root -eq '') {
    $Root = Split-Path -Parent $ScriptDir
} else {
    $Root = (Resolve-Path -LiteralPath $Root).Path
    if ((Split-Path -Leaf $Root) -eq 'scripts') { $Root = Split-Path -Parent $Root }
    elseif (-not (Test-Path (Join-Path $Root 'scripts'))) {
        $Root = Split-Path -Parent $Root
    }
}
$PrjParent = Split-Path -Parent $Root

$SearchCandidates = @(
    (Join-Path $Root 'scripts'),
    (Join-Path $Root 'out'),
    (Join-Path $Root 'pc'),
    (Join-Path $PrjParent 'project_12\out'),
    (Join-Path $PrjParent 'project_12\scripts'),
    (Join-Path $PrjParent 'project_12\pc')
)
$SearchDirs = @($SearchCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) })

function Resolve-Helper([string]$name) {
    foreach ($d in $SearchDirs) {
        $p = Join-Path $d $name
        if (Test-Path -LiteralPath $p) {
            Say ("HELPER {0}: {1}" -f $name, $p)
            if ($d -like "*project_12*" -and $p -notlike (Join-Path $Root '*')) {
                Say ("HELPER_WARN {0}: resolved from another project (prj12) - pairing/version not guaranteed" -f $name)
            }
            return $p
        }
    }
    Say ("HELPER {0}: MISSING (searched: {1})" -f $name, ($SearchCandidates -join '; '))
    return $null
}

$PsExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path $PsExe)) { $PsExe = 'powershell' }

function Invoke-Ps([string]$scriptPath, [string[]]$Arguments) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $Arguments
    Add-Cmd ("powershell " + ($a -join ' '))
    $out = & $PsExe @a 2>&1
    $rc = $LASTEXITCODE
    $text = ($out | Out-String)
    $script:LogLines += $text
    return @{ Rc = $rc; Text = $text }
}

function Invoke-Py([string]$scriptPath, [string[]]$Arguments) {
    $a = @($scriptPath) + $Arguments
    Add-Cmd ("py " + ($a -join ' '))
    $out = & py @a 2>&1
    $rc = $LASTEXITCODE
    $text = ($out | Out-String)
    $script:LogLines += $text
    return @{ Rc = $rc; Text = $text }
}

function Get-VivadoArgList([string]$TclFile, [string[]]$TclArgs, [string]$ConsoleLog) {
    $vlog = [System.IO.Path]::ChangeExtension($ConsoleLog, '.vivado.log')
    $vjou = [System.IO.Path]::ChangeExtension($ConsoleLog, '.vivado.jou')
    $a = @('-mode', 'batch', '-notrace', '-log', $vlog, '-journal', $vjou, '-source', $TclFile)
    if ($TclArgs -and $TclArgs.Count -gt 0) { $a += @('-tclargs') + $TclArgs }
    return $a
}

function Invoke-VivadoBatch([string]$TclFile, [string[]]$TclArgs, [string]$ConsoleLog) {
    if (-not (Test-Path -LiteralPath $Vivado)) {
        return @{ Rc = -1; Text = "vivado not found: $Vivado" }
    }
    $tmp = 'D:\FPGA\.tmp'
    if (-not (Test-Path -LiteralPath $tmp)) { New-Item -ItemType Directory -Force -Path $tmp | Out-Null }
    $env:TEMP = $tmp; $env:TMP = $tmp
    $a = Get-VivadoArgList $TclFile $TclArgs $ConsoleLog
    Add-Cmd ("`"$Vivado`" " + ($a -join ' '))
    $p = Start-Process -FilePath $Vivado -ArgumentList $a -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $ConsoleLog -RedirectStandardError "$ConsoleLog.err"
    $text = ''
    if (Test-Path -LiteralPath $ConsoleLog) { $text = (Get-Content -LiteralPath $ConsoleLog -Raw -ErrorAction SilentlyContinue) }
    $errf = "$ConsoleLog.err"
    if (Test-Path -LiteralPath $errf) {
        $errText = (Get-Content -LiteralPath $errf -Raw -ErrorAction SilentlyContinue)
        if ($errText -and $errText.Trim() -ne '') { $text += "`n[stderr]`n" + $errText }
    }
    $script:LogLines += $text
    return @{ Rc = $p.ExitCode; Text = $text }
}

# ------------------------------------------------------------- ILA CSV decoding
function Read-IlaCsv([string]$Path) {
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    if ($lines.Count -lt 2) { return $null }
    $hdrIdx = -1
    $scan = [Math]::Min($lines.Count - 1, 6)
    for ($i = 0; $i -le $scan; $i++) {
        if ($lines[$i] -match 'link_ok|ch_up|channel_up') { $hdrIdx = $i; break }
    }
    if ($hdrIdx -lt 0) { $hdrIdx = 0 }
    $names = @($lines[$hdrIdx].Split(',') | ForEach-Object { $_.Trim().Trim('"') })
    $vals = $null
    for ($j = $hdrIdx + 1; $j -lt $lines.Count; $j++) {
        if ($lines[$j].Trim() -ne '') {
            $vals = @($lines[$j].Split(',') | ForEach-Object { $_.Trim().Trim('"') })
            break
        }
    }
    if ($null -eq $vals) { return $null }
    $map = @{}
    for ($k = 0; $k -lt $names.Count; $k++) {
        $map[$names[$k]] = if ($k -lt $vals.Count) { $vals[$k] } else { '' }
    }
    return $map
}

function Get-Field($Map, [string[]]$Names) {
    if ($null -eq $Map) { return $null }
    foreach ($n in $Names) {
        if ($Map.ContainsKey($n) -and "$($Map[$n])" -ne '') { return "$($Map[$n])" }
    }
    return $null
}

function Convert-IlaInt($v) {
    if ($null -eq $v) { return $null }
    $s = "$v".Trim()
    if ($s -eq '') { return $null }
    if ($s -match '^0[xX][0-9a-fA-F]+$') { return [Convert]::ToInt64($s.Substring(2), 16) }
    $n = [int64]0
    if ([int64]::TryParse($s, [ref]$n)) { return $n }
    return $null
}

function Show([string]$label, $v) {
    if ($null -eq $v) { return "$label=?" }
    return "$label=$v"
}

# ============================================================== parameter gate
Say "=== p1_selfcheck (prj13 M1) ==="
Say ("when     : {0}" -f $script:When)
Say ("mode     : {0}" -f $(if ($DryRun) { 'DRY-RUN (nothing is executed, nothing is written)' } else { 'RUN' }))
Say ("root     : {0}" -f $Root)
Say ("board    : {0}  com={1}  cable={2}" -f $Board, $Com, $Cable)
Say ("vivado   : {0}" -f $Vivado)
Say ("capture  : iface='{0}' seconds={1} send-delay={2} frame-len={3}" -f $Iface, $CaptureSeconds, $SendDelaySeconds, $FrameLen)
Say ("local dir: {0}" -f $LocalDir)

if ($Board -eq 'Both') {
    Say "PARAM_FAIL: -Board Both is forbidden on this bench."
    Say "  reason: both boards report the SAME JTAG cable serial (210512180081); a 'Both' burn"
    Say "          cannot tell the two targets apart and has already been rejected by the pitfall table."
    Say "  fix   : run this script twice, once with -Board A and once with -Board B."
    Step 0 'PARAMS' 'FAIL' '-Board Both rejected (same JTAG serial on both boards)'
    Finish 2 ''
}
if ($CaptureSeconds -lt 180 -and -not $AllowShortCapture) {
    Say "PARAM_FAIL: -CaptureSeconds $CaptureSeconds < 180."
    Say "  reason: the data-plane criterion requires ONE continuous capture of >= 180 s; chunked"
    Say "          captures produced '0 frames but counters rising' on 2026-11-06."
    Say "  fix   : keep the default 180 (or pass -AllowShortCapture and label the run as non-M1)."
    Step 0 'PARAMS' 'FAIL' "-CaptureSeconds $CaptureSeconds < 180"
    Finish 2 ''
}
if ($LocalDir -eq 'auto') {
    if ($Board -eq 'B') { $LocalDir = 'rev' } else { $LocalDir = 'fwd' }
}
Say ("local dir: {0} (P1 convention: PC1/board A sends run_id 0x1, PC2/board B sends 0x2)" -f $LocalDir)
if ($FrameLen -lt 12) {
    Step 0 'PARAMS' 'FAIL' "-FrameLen $FrameLen < 12 (twin payload header)"
    Finish 2 ''
}
if ($Board -eq 'B' -and $Com -eq 'COM6') { Say "PARAM_WARN: board B normally uses COM4, not COM6 (see the manual section 1)." }

# ------------------------------------------------------------- address scheme
# 2026-11-08 decision (project lead): the DEFAULT address plan for P2 is handbook
# (10.10.0.x). THIS TOOL, however, reproduces the P1 BASELINE bitstream, whose RTL
# hardcodes 192.168.1.10 / 00:11:22:33:44:55 -> its default is 'p1' on purpose.
# Burning the wrong scheme does not break the link: every frame is simply sent to an
# address no board answers, so all data-plane criteria FAIL while link criteria PASS.
# That signature must be read as "wrong scheme / wrong bitstream", not "broken link".
$SchemeTable = @{
    'p1'       = @{
        Doc  = 'P1 baseline bitstream (rtl hardcoded 192.168.1.10)'
        Note = 'P1 baseline bitstream 192.168.1.10'
        A    = @{ Ip = '192.168.1.10'; Mac = '00:11:22:33:44:55' }
        B    = @{ Ip = '192.168.1.10'; Mac = '00:11:22:33:44:55' }
    }
    'handbook' = @{
        Doc  = 'prj13 startup manual section 8 (10.10.0.x)'
        Note = 'P2 candidate, board A 10.10.0.11 / board B 10.10.0.12'
        A    = @{ Ip = '10.10.0.11'; Mac = '02:00:00:00:0a:01' }
        B    = @{ Ip = '10.10.0.12'; Mac = '02:00:00:00:0b:01' }
    }
    'protocol' = @{
        Doc  = 'v0.2 contract 192.168.50.x (HISTORICAL reference only)'
        Note = 'v0.2 contract addresses, historical only'
        A    = @{ Ip = '192.168.50.11'; Mac = '02:00:00:00:0a:01' }
        B    = @{ Ip = '192.168.50.12'; Mac = '02:00:00:00:0b:01' }
    }
}
$Scheme = $SchemeTable[$IpScheme]
$SchemeSide = $Scheme[$Board]
$SchemeMac = if ($BoardMac -ne '') { $BoardMac } else { $SchemeSide.Mac }
$SchemeMacSrc = if ($BoardMac -ne '') { '-BoardMac override' } else { '-IpScheme' }
if ($IpScheme -eq 'p1') {
    Say "ADDR_SCHEME p1 (P1 baseline bitstream 192.168.1.10); use -IpScheme handbook after a P2 bitstream is burned"
} else {
    Say ("ADDR_SCHEME {0} ({1}); a P1 baseline bitstream does NOT answer on these addresses" -f $IpScheme, $Scheme.Doc)
    Say ("EXPECT P2 BITSTREAM (scheme {0} = {1})" -f $IpScheme, $Scheme.Note)
}
Say ("ADDR_TARGET board {0} -> {1}:{2}/udp, judge src-mac={3} (from {4})" -f $Board, $SchemeSide.Ip, $Port, $SchemeMac, $SchemeMacSrc)
Say ("ADDR_PASSTHROUGH twin_send.py --scheme {0} --pair {1} | twin_recv.py --scheme {0} --pair {1} | static_arp.ps1 -Scheme {0} -BoardPcPair {1}" -f $IpScheme, $Board)

# --------------------------------------------------------------- precheck block
Say ""
Say "--- precheck (offline, never fails a step) ---"
$helperScripts = @('list_targets.tcl', 'twin_burn.ps1', 'serial_dma_mode.ps1', 'ila_capture.tcl',
    'twin_send.py', 'twin_recv.py', 'npcap_capture.py', 'p1_judge.py', 'static_arp.ps1', 'probes.ltx')
$helperMap = @{}
foreach ($h in $helperScripts) { $helperMap[$h] = Resolve-Helper $h }

$prjOut = Join-Path $Root 'out'
$artBit = @()
foreach ($cand in @('aurora_mem_bridge.bit')) {
    $p = Join-Path $prjOut $cand
    if (Test-Path -LiteralPath $p) { $artBit += $p }
}
$artElf = @()
Get-ChildItem -LiteralPath $prjOut -Filter '*.elf' -ErrorAction SilentlyContinue | ForEach-Object { $artElf += $_.FullName }
$prjCfg = Join-Path $prjOut 'twin_config.json'

Say ("PRECHECK bitstream : {0}" -f $(if ($artBit.Count -gt 0) { $artBit[0] } else { 'absent in THIS project out\ (step 2 would use the helper pair printed below; M1 = reproduce P1, so that is expected)' }))
Say ("PRECHECK elf       : {0}" -f $(if ($artElf.Count -gt 0) { $artElf[0] } else { 'absent' }))
Say ("PRECHECK twin_cfg  : {0}" -f $(if (Test-Path -LiteralPath $prjCfg) { $prjCfg } else { "absent (twin_burn.ps1 will fall back to its own default config/root)" }))
$effCfg = if (Test-Path -LiteralPath $prjCfg) { $prjCfg } else { Join-Path $PrjParent 'project_12\out\twin_config.json' }
$eff = $null
if (Test-Path -LiteralPath $effCfg) {
    try {
        $eff = Get-Content -LiteralPath $effCfg -Raw -Encoding UTF8 | ConvertFrom-Json
        $bsha = [string]$eff.artifacts.expect_bit_sha256
        if ($bsha.Length -gt 8) { $bsha = $bsha.Substring(0, 8).ToUpper() }
        Say ("PRECHECK burn-cfg  : {0}" -f $effCfg)
        Say ("PRECHECK burn-bit  : {0} (expect sha {1})" -f $eff.artifacts.bit, $bsha)
        Say ("PRECHECK burn-elf  : {0}" -f $eff.artifacts.elf)
        if (-not (Test-Path -LiteralPath $prjCfg)) {
            Say "PRECHECK burn-note : step 2 will burn the helper default pair (prj12 P1 baseline), NOT a prj13 build."
            Say "                     that is the correct M1 path (M1 = reproduce P1), and it is logged as such."
        }
        if ($Board -eq 'B' -and ([string]$eff.boards.B.jtag_serial) -match '<FILL>') {
            Say ("PRECHECK burn-note : prj12 config board B still has <FILL> jtag/com -> -Cable {0} and -Com {1} are mandatory (this script passes both)." -f $Cable, $Com)
        }
    } catch {
        Say ("PRECHECK burn-cfg  : {0} (unreadable: {1})" -f $effCfg, $_.Exception.Message)
    }
} else {
    Say "PRECHECK burn-cfg  : no twin_config.json in this project nor in prj12/out"
}
Say ("PRECHECK vivado    : {0}" -f $(if (Test-Path -LiteralPath $Vivado) { $Vivado } else { "absent ($Vivado)" }))
$script:LtxPath = $helperMap['probes.ltx']
if ($script:LtxPath -and -not ($script:LtxPath.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase))) {
    Say ("PRECHECK ltx/probes: resolved only in another project (" + $script:LtxPath + ")")
    Say "PRECHECK ltx/probes: NOT passed to ila_capture.tcl - a bitstream and an ltx must pair;"
    Say "                     copy this project's probes.ltx into <root>\scripts before a real run."
    $script:LtxPath = $null
} elseif ($script:LtxPath) {
    Say ("PRECHECK ltx/probes: " + $script:LtxPath + " (pairs with this project's bitstream)")
} else {
    Say "PRECHECK ltx/probes: absent (build_impl.tcl writes it next to the bitstream)"
}
# The scheme table above MIRRORS pc\twin_send.py SCHEMES. Ask that script for its own
# idea of the destination (offline --dry-run, nothing is sent) so the two cannot drift
# apart silently: a mismatch here would be a wrong-address run.
$tsPy = $helperMap['twin_send.py']
if ($tsPy) {
    try {
        $syncOut = (& py $tsPy --dry-run --scheme $IpScheme --pair $Board --count 1 2>&1 | Out-String)
        $ipM = [regex]::Match($syncOut, 'dst\s+:\s*([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):')
        $macM = [regex]::Match($syncOut, 'eth dst\s+:\s*([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})')
        $pyIp = if ($ipM.Success) { $ipM.Groups[1].Value } else { '?' }
        $pyMac = if ($macM.Success) { $macM.Groups[1].Value.ToLower() } else { '?' }
        $ipOk = ($pyIp -eq $SchemeSide.Ip)
        $macOk = ($pyMac -eq $SchemeMac.ToLower()) -or ($SchemeMac -eq '')
        if ($ipOk -and $macOk) {
            Say ("PRECHECK addr-sync : ok (pc\twin_send.py agrees: dst={0} mac={1} for scheme {2}/pair {3})" -f $pyIp, $pyMac, $IpScheme, $Board)
        } else {
            Say ("PRECHECK addr-sync : MISMATCH (selfcheck dst={0} mac={1} vs pc\twin_send.py dst={2} mac={3})" -f $SchemeSide.Ip, $SchemeMac, $pyIp, $pyMac)
            Say "PRECHECK addr-sync : the two scheme tables drifted - fix the table in this script before burning anything."
        }
    } catch {
        Say ("PRECHECK addr-sync : skipped ({0})" -f $_.Exception.Message)
    }
} else {
    Say "PRECHECK addr-sync : skipped (twin_send.py not resolved)"
}
Say ""

# ================================================================= STEP 1 TARGETS
if ($DryRun) {
    $lt = $helperMap['list_targets.tcl']
    if (-not $lt) {
        Step 1 'TARGETS' 'SKIP' 'helper-missing list_targets.tcl'
    } else {
        Add-Cmd ('"' + $Vivado + '" ' + ((Get-VivadoArgList $lt @($HwServer) (Join-Path $prjOut 'list_targets.console.log')) -join ' '))
        Step 1 'TARGETS' 'SKIP' ('dry-run (vivado is not started in -DryRun; would list hw targets on ' + $HwServer + ')')
    }
} else {
    $lt = $helperMap['list_targets.tcl']
    if (-not $lt) {
        Step 1 'TARGETS' 'SKIP' 'helper-missing list_targets.tcl'
    } elseif (-not (Test-Path -LiteralPath $Vivado)) {
        Step 1 'TARGETS' 'SKIP' "vivado-missing $Vivado"
    } else {
        $clog = Join-Path $prjOut ("list_targets_{0}_{1}.console.log" -f $Board, $script:Stamp)
        $r = Invoke-VivadoBatch $lt @($HwServer) $clog
        $tgt = @([regex]::Matches($r.Text, 'LIST_TARGET:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
        $dev = @([regex]::Matches($r.Text, 'LIST_DEVICE:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
        if ($r.Rc -eq 0 -and $tgt.Count -ge 1) {
            Step 1 'TARGETS' 'PASS' ("targets={0} devices={1} log={2}" -f $tgt.Count, $dev.Count, $clog)
        } else {
            Step 1 'TARGETS' 'FAIL' ("rc={0} targets={1} (see {2})" -f $r.Rc, $tgt.Count, $clog)
        }
    }
}

# ==================================================================== STEP 2 BURN
if ($SkipBurn) {
    Step 2 'BURN' 'SKIP' 'skip-burn (-SkipBurn; a BitElf pair is NOT recoverable after POR)'
} elseif ($DryRun) {
    $tb = $helperMap['twin_burn.ps1']
    if (-not $tb) {
        Step 2 'BURN' 'SKIP' 'helper-missing twin_burn.ps1'
    } else {
        $a = @('-Board', $Board, '-Mode', 'BitElf', '-Run')
        if ($Cable -ne '') { $a += @('-Cable', $Cable) }
        if (Test-Path -LiteralPath $prjCfg) { $a += @('-Root', $Root, '-Config', $prjCfg) }
        Add-Cmd ('powershell ' + (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tb) + $a -join ' '))
        Step 2 'BURN' 'SKIP' ('dry-run (would run twin_burn.ps1 -Board {0} -Mode BitElf -Run)' -f $Board)
    }
} else {
    $tb = $helperMap['twin_burn.ps1']
    if (-not $tb) {
        Step 2 'BURN' 'SKIP' 'helper-missing twin_burn.ps1'
    } else {
        $a = @('-Board', $Board, '-Mode', 'BitElf', '-Run')
        if ($Cable -ne '') { $a += @('-Cable', $Cable) }
        if (Test-Path -LiteralPath $prjCfg) { $a += @('-Root', $Root, '-Config', $prjCfg) }
        $r = Invoke-Ps $tb $a
        if ($r.Text -match 'TWIN_BURN_RESULT:\s*PASS') {
            Step 2 'BURN' 'PASS' 'TWIN_BURN_RESULT: PASS'
        } else {
            $m = @($r.Text -split "`r?`n" | Where-Object { $_ -match 'TWIN_BURN_RESULT|FAIL:|marker' } | Select-Object -Last 4)
            Step 2 'BURN' 'FAIL' ("rc={0} {1}" -f $r.Rc, ($m -join ' | '))
        }
    }
}

# ================================================================ STEP 3 DMA_MODE
if ($DryRun) {
    $sd = $helperMap['serial_dma_mode.ps1']
    if (-not $sd) {
        Step 3 'DMA_MODE' 'SKIP' 'helper-missing serial_dma_mode.ps1'
    } else {
        Add-Cmd ('powershell ' + (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sd, '-Com', $Com) -join ' '))
        Step 3 'DMA_MODE' 'SKIP' ('dry-run (would toggle ''d'' on {0} until the LAST banner says now=DMA)' -f $Com)
    }
} else {
    $sd = $helperMap['serial_dma_mode.ps1']
    if (-not $sd) {
        Step 3 'DMA_MODE' 'SKIP' 'helper-missing serial_dma_mode.ps1'
    } else {
        $r = Invoke-Ps $sd @('-Com', $Com)
        if ($r.Text -match 'SERIAL_RESULT:\s*PASS') {
            Step 3 'DMA_MODE' 'PASS' 'SERIAL_RESULT: PASS (firmware in DMA mode)'
        } else {
            $m = @($r.Text -split "`r?`n" | Where-Object { $_ -match 'SERIAL_RESULT|FAIL' } | Select-Object -Last 3)
            Step 3 'DMA_MODE' 'FAIL' ("rc={0} {1}" -f $r.Rc, ($m -join ' | '))
        }
    }
}

# ===================================================================== STEP 3b ARP
# Manual section 2 step 4: static ARP is mandatory, not optional. The board's ARP reply
# travels over Aurora to the PEER board, so this PC never learns the board MAC and
# sendto() fails at the OS layer. The scheme decides which (ip -> mac) pair is bound.
if ($SkipArp) {
    Step '3b' 'ARP' 'SKIP' 'skip-arp (-SkipArp)'
} elseif ($DryRun) {
    $sa = $helperMap['static_arp.ps1']
    if (-not $sa) {
        Step '3b' 'ARP' 'SKIP' 'helper-missing static_arp.ps1'
    } else {
        $ifAliasShown = if ($Iface -eq '') { '<IFACE>' } else { $Iface }
        Add-Cmd ('powershell -NoProfile -ExecutionPolicy Bypass -File ' + $sa + " -Scheme $IpScheme -BoardPcPair $Board -IfAlias `"$ifAliasShown`" -Apply")
        Step '3b' 'ARP' 'SKIP' ("dry-run (would bind {0} -> {1} with scheme {2})" -f $SchemeSide.Ip, $SchemeMac, $IpScheme)
    }
} elseif (-not $helperMap['static_arp.ps1']) {
    Step '3b' 'ARP' 'SKIP' 'helper-missing static_arp.ps1'
} elseif ($Iface -eq '') {
    Step '3b' 'ARP' 'SKIP' 'no-iface (-Iface required to pick the NIC for the static ARP entry)'
} else {
    $r = Invoke-Ps $helperMap['static_arp.ps1'] @('-Scheme', $IpScheme, '-BoardPcPair', $Board, '-IfAlias', $Iface, '-Apply')
    if ($r.Text -match 'STATIC_ARP_RESULT:\s*PASS') {
        Step '3b' 'ARP' 'PASS' ("{0} -> {1} Permanent (scheme {2})" -f $SchemeSide.Ip, $SchemeMac, $IpScheme)
    } else {
        $m = @($r.Text -split "`r?`n" | Where-Object { $_ -match 'STATIC_ARP_RESULT|FAIL' } | Select-Object -Last 3)
        Step '3b' 'ARP' 'FAIL' ("rc={0} {1}" -f $r.Rc, ($m -join ' | '))
    }
}

# ==================================================================== STEP 4 LINK
$script:PkBase = $null
# $script:LtxPath was decided in the precheck block (bit/ltx pairing rule)
function Invoke-LinkCapture([string]$Tag) {
    $ic = $helperMap['ila_capture.tcl']
    $csv = Join-Path $prjOut ("ila6_{0}_{1}_{2}.csv" -f $Board, $Tag, $script:Stamp)
    $clog = Join-Path $prjOut ("ila6_{0}_{1}_{2}.console.log" -f $Board, $Tag, $script:Stamp)
    $targs = @($HwServer, $Cable, $csv)
    if ($script:LtxPath) { $targs += $script:LtxPath }
    $r = Invoke-VivadoBatch $ic $targs $clog
    return @{ Rc = $r.Rc; Text = $r.Text; Csv = $csv; Log = $clog }
}

if ($DryRun) {
    $ic = $helperMap['ila_capture.tcl']
    if (-not $ic) {
        Step 4 'LINK' 'SKIP' 'helper-missing ila_capture.tcl'
    } else {
        $csv = Join-Path $prjOut ("ila6_{0}_link_{1}.csv" -f $Board, $script:Stamp)
        $clog = Join-Path $prjOut ("ila6_{0}_link_{1}.console.log" -f $Board, $script:Stamp)
        $targs = @($HwServer, $Cable, $csv)
        if ($script:LtxPath) { $targs += $script:LtxPath }
        Add-Cmd ('"' + $Vivado + '" ' + ((Get-VivadoArgList $ic $targs $clog) -join ' '))
        Step 4 'LINK' 'SKIP' 'dry-run (would capture ILA6 and judge link_ok/ch_up/lane_up/pll/rst/hard/soft)'
    }
} else {
    $ic = $helperMap['ila_capture.tcl']
    if (-not $ic) {
        Step 4 'LINK' 'SKIP' 'helper-missing ila_capture.tcl'
    } elseif (-not (Test-Path -LiteralPath $Vivado)) {
        Step 4 'LINK' 'SKIP' "vivado-missing $Vivado"
    } else {
        $cap = Invoke-LinkCapture 'link'
        $map = Read-IlaCsv $cap.Csv
        if ($null -eq $map) {
            Step 4 'LINK' 'FAIL' ("no CSV/sample (rc={0}, see {1})" -f $cap.Rc, $cap.Log)
        } else {
            $link = Convert-IlaInt (Get-Field $map @('link_ok'))
            $chup = Convert-IlaInt (Get-Field $map @('ch_up', 'channel_up'))
            $lane = Convert-IlaInt (Get-Field $map @('lane_up'))
            $pll = Convert-IlaInt (Get-Field $map @('gt_pll_lock', 'pll', 'pll_lock'))
            $rst = Convert-IlaInt (Get-Field $map @('aurora_rst', 'rst'))
            $hard = Convert-IlaInt (Get-Field $map @('hard', 'hard_err'))
            $soft = Convert-IlaInt (Get-Field $map @('soft', 'soft_err'))
            $script:PkBase = Convert-IlaInt (Get-Field $map @('pk_frames', 'pk'))
            $ok = ($chup -eq 1) -and ($link -eq 1) -and ($lane -eq 1) -and ($pll -eq 1) -and
            ($rst -eq 0) -and ($hard -eq 0) -and ($soft -eq 0)
            $detail = (Show 'link_ok' $link) + ' ' + (Show 'ch_up' $chup) + ' ' + (Show 'lane_up' $lane) +
            ' ' + (Show 'gt_pll_lock' $pll) + ' ' + (Show 'aurora_rst' $rst) + ' ' +
            (Show 'hard' $hard) + ' ' + (Show 'soft' $soft) + ' ' + (Show 'pk_frames' $script:PkBase) +
            ' csv=' + $cap.Csv
            if ($ok) { Step 4 'LINK' 'PASS' $detail } else { Step 4 'LINK' 'FAIL' $detail }
        }
    }
}

# ================================================================== STEP 5 PROBE3
if ($SkipProbe) {
    Step 5 'PROBE3' 'SKIP' 'skip-probe (-SkipProbe)'
} elseif ($DryRun) {
    $ts = $helperMap['twin_send.py']
    if (-not $ts) {
        Step 5 'PROBE3' 'SKIP' 'helper-missing twin_send.py'
    } else {
        Add-Cmd ('py ' + $ts + (" --count 3 --len 100 --run-id 0x91 --scheme {0} --pair {1}" -f $IpScheme, $Board))
        Step 5 'PROBE3' 'SKIP' 'dry-run (would send 3 probe frames and re-capture ILA expecting pk_frames +3)'
    }
} elseif ($null -eq $script:PkBase) {
    Step 5 'PROBE3' 'SKIP' 'no-baseline (step 4 did not yield pk_frames; a delta cannot be proven)'
} else {
    $ts = $helperMap['twin_send.py']
    if (-not $ts) {
        Step 5 'PROBE3' 'SKIP' 'helper-missing twin_send.py'
    } else {
        $s = Invoke-Py $ts @('--count', '3', '--len', '100', '--run-id', '0x91', '--scheme', $IpScheme, '--pair', $Board)
        if ($s.Text -notmatch 'SEND_OK') {
            $m = @($s.Text -split "`r?`n" | Where-Object { $_ -match 'FAIL|HINT' } | Select-Object -Last 3)
            Step 5 'PROBE3' 'FAIL' ("send failed rc={0} {1}" -f $s.Rc, ($m -join ' | '))
        } else {
            Start-Sleep -Seconds 2
            $cap = Invoke-LinkCapture 'probe3'
            $map = Read-IlaCsv $cap.Csv
            $pk2 = if ($null -ne $map) { Convert-IlaInt (Get-Field $map @('pk_frames', 'pk')) } else { $null }
            if ($null -eq $pk2) {
                Step 5 'PROBE3' 'FAIL' ("probe frames sent but no second ILA sample (rc={0}, see {1})" -f $cap.Rc, $cap.Log)
            } else {
                $delta = $pk2 - $script:PkBase
                $detail = ("pk_frames {0} -> {1} delta={2} (expect +3)" -f $script:PkBase, $pk2, $delta)
                if ($delta -eq 3) { Step 5 'PROBE3' 'PASS' $detail }
                else { Step 5 'PROBE3' 'FAIL' ($detail + ' (pk frozen while pfwd grows = DMA/pump dead state, see manual 5-3)') }
            }
        }
    }
}

# ================================================================== STEP 6 DUAL20
$capPy = $helperMap['npcap_capture.py']
$sendPy = $helperMap['twin_send.py']
$judgePy = $helperMap['p1_judge.py']
$recvPy = $helperMap['twin_recv.py']
if ($Step6DelaySeconds -gt 0) {
    Say ("STEP6_WAIT: sleeping {0} s before the data-plane windows so both PCs enter window 1 together" -f $Step6DelaySeconds)
    if (-not $DryRun) { Start-Sleep -Seconds $Step6DelaySeconds }
}
$dirs = @(
    @{ Name = 'fwd'; Hex = '0x1'; Count = 20; Len = $FrameLen; Interval = '20'; Send = ($LocalDir -eq 'fwd'); MiB = $false },
    @{ Name = 'rev'; Hex = '0x2'; Count = 20; Len = $FrameLen; Interval = '20'; Send = ($LocalDir -eq 'rev'); MiB = $false },
    @{ Name = '10mib'; Hex = '0x1'; Count = 7125; Len = 1472; Interval = $SendIntervalMs.ToString([System.Globalization.CultureInfo]::InvariantCulture); Send = ($LocalDir -eq 'fwd'); MiB = $true }
)
$dualReq = 0
$dualBad = 0
$dualSkip = 0
$dualDetail = @()

foreach ($dir in $dirs) {
    $pcap = Join-Path $prjOut ("rx_{0}_{1}_{2}.pcap" -f $Board, $dir.Name, $script:Stamp)
    $clog = Join-Path $prjOut ("rx_{0}_{1}_{2}.console.log" -f $Board, $dir.Name, $script:Stamp)
    $isLocal = $dir.Send
    if ($dir.MiB -and $Skip10MiB) {
        $dualDetail += ("{0}:SKIP(-Skip10MiB)" -f $dir.Name)
        $dualSkip++
        continue
    }
    if ($DryRun) {
        if (-not $capPy) {
            $dualDetail += ("{0}:SKIP(helper-missing npcap_capture.py)" -f $dir.Name)
            continue
        }
        $ifaceShown = if ($Iface -eq '') { '<IFACE>' } else { $Iface }
        Add-Cmd ('py ' + $capPy + " --iface `"$ifaceShown`" --seconds $CaptureSeconds --out $pcap")
        if ($isLocal -and $sendPy) {
            Add-Cmd ('py ' + $sendPy + (" --count {0} --len {1} --run-id {2} --interval-ms {3} --scheme {4} --pair {5}" -f $dir.Count, $dir.Len, $dir.Hex, $dir.Interval, $IpScheme, $Board))
        }
        if ($judgePy) {
            $extra = if ($dir.MiB) { " --print-frames 5 --json-out " + (Join-Path $prjOut ("judge_10mib_{0}.json" -f $script:Stamp)) } else { '' }
            Add-Cmd ('py ' + $judgePy + (" --from-pcap $pcap --board-mac $SchemeMac --port $Port --port-direction any --expect-count {0} --count-mode exact --expect-len {1} --expect-run-id {2} --allow-dup 0{3}" -f $dir.Count, $dir.Len, $dir.Hex, $extra))
        }
        if ($recvPy) {
            Add-Cmd ('py ' + $recvPy + (" --from-pcap $pcap --scheme {0} --pair {1} --port $Port --port-direction any --expect-count {2} --expect-len {3} --expect-run-id {4}" -f $IpScheme, $Board, $dir.Count, $dir.Len, $dir.Hex))
        }
        $dualDetail += ("{0}:SKIP(dry-run)" -f $dir.Name)
        continue
    }

    # ---- real run -------------------------------------------------------
    if (-not $capPy -or -not $judgePy) {
        $dualDetail += ("{0}:SKIP(helper-missing)" -f $dir.Name)
        continue
    }
    if ($Iface -eq '') {
        $dualDetail += ("{0}:FAIL(-Iface required for capture)" -f $dir.Name)
        $dualBad++
        continue
    }
    $cargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $capPy,
        '--iface', $Iface, '--seconds', "$CaptureSeconds", '--out', $pcap)
    Add-Cmd ('powershell ' + ($cargs -join ' '))
    $capProc = Start-Process -FilePath $PsExe -ArgumentList $cargs -NoNewWindow -PassThru `
        -RedirectStandardOutput $clog -RedirectStandardError "$clog.err"
    $capOk = $true
    $windowUsed = $false
    if ($isLocal) {
        if ($sendPy) {
            Start-Sleep -Seconds $SendDelaySeconds
            $s = Invoke-Py $sendPy @('--count', "$($dir.Count)", '--len', "$($dir.Len)", '--run-id', $dir.Hex, '--interval-ms', "$($dir.Interval)", '--scheme', $IpScheme, '--pair', $Board)
            $windowUsed = $true
            if ($s.Text -match 'SEND_OK') {
                $dualDetail += ("{0}:SEND_OK" -f $dir.Name)
            } else {
                $dualDetail += ("{0}:SEND_FAIL" -f $dir.Name)
                $capOk = $false
            }
        } else {
            $dualDetail += ("{0}:SEND_SKIP(helper-missing twin_send.py)" -f $dir.Name)
        }
    }
    $capProc.WaitForExit()
    $capText = Get-Content -LiteralPath $clog -Raw -ErrorAction SilentlyContinue
    if ($null -eq $capText) { $capText = '' }
    $script:LogLines += $capText
    if ($capText -notmatch 'CAPTURE_OK') {
        $dualDetail += ("{0}:CAPTURE_FAIL" -f $dir.Name)
        $capOk = $false
    } else {
        $m = [regex]::Match($capText, 'CAPTURE_OK:\s*(\S+)\s+frames=(\d+)')
        if ($m.Success) { $dualDetail += ("{0}:CAPTURE_OK(frames={1})" -f $dir.Name, $m.Groups[2].Value) }
    }

    $judged = $false
    if ((-not $isLocal) -or $JudgeOwn) {
        $judged = $true
        $windowUsed = $true
        $jargs = @($judgePy, '--from-pcap', $pcap, '--board-mac', $SchemeMac, '--port', "$Port",
            '--port-direction', 'any', '--expect-count', "$($dir.Count)", '--count-mode', 'exact',
            '--expect-len', "$($dir.Len)", '--expect-run-id', $dir.Hex, '--allow-dup', '0')
        if ($dir.MiB) {
            $jargs += @('--print-frames', '5', '--json-out', (Join-Path $prjOut ("judge_10mib_{0}.json" -f $script:Stamp)))
        }
        $j = Invoke-Py $judgePy $jargs[1..($jargs.Count - 1)]
        $jline = @($j.Text -split "`r?`n" | Where-Object { $_ -match '^JUDGE:' } | Select-Object -Last 1)
        if ($jline.Count -eq 0) { $jline = @('JUDGE: <missing>') }
        $ok = ($j.Rc -eq 0) -and ("$jline" -match 'JUDGE: PASS')
        if ($ok) { $dualDetail += ("{0}:JUDGE_PASS" -f $dir.Name) } else { $dualDetail += ("{0}:JUDGE_FAIL({1})" -f $dir.Name, "$jline"); $capOk = $false }
        if ($recvPy) {
            $rargs = @('--from-pcap', $pcap, '--scheme', $IpScheme, '--pair', $Board, '--port', "$Port",
                '--port-direction', 'any', '--expect-count', "$($dir.Count)",
                '--expect-len', "$($dir.Len)", '--expect-run-id', $dir.Hex)
            $rc2 = Invoke-Py $recvPy $rargs
            $rl = @($rc2.Text -split "`r?`n" | Where-Object { $_ -match 'twin_recv: (PASS|FAIL)' } | Select-Object -Last 1)
            if ($rl.Count -eq 0) { $rl = @('twin_recv: <none>') }
            $script:LogLines += ("CROSSCHECK {0} twin_recv: {1}" -f $dir.Name, "$rl")
            Say ("CROSSCHECK {0} twin_recv: {1}" -f $dir.Name, "$rl")
        }
    } else {
        $dualDetail += ("{0}:JUDGE_SKIPPED(local-send direction; the peer judges)" -f $dir.Name)
    }
    if (-not $windowUsed) {
        $dualSkip++
    } elseif ($capOk) {
        $dualReq++
    } else {
        $dualBad++
    }
}

if ($DryRun) {
    if ($dualDetail.Count -gt 0 -and (@($dualDetail | Where-Object { $_ -match 'SKIP' }).Count -eq $dualDetail.Count)) {
        Step 6 'DUAL20' 'SKIP' ('dry-run (three single continuous ' + $CaptureSeconds + ' s windows: ' + ($dualDetail -join ' ') + ')')
    } else {
        Step 6 'DUAL20' 'FAIL' ($dualDetail -join ' ')
    }
} elseif ($dualBad -gt 0) {
    Step 6 'DUAL20' 'FAIL' ($dualDetail -join ' ')
} elseif ($dualReq -eq 0) {
    Step 6 'DUAL20' 'SKIP' ('no window was judged (' + ($dualDetail -join ' ') + ')')
} else {
    Step 6 'DUAL20' 'PASS' ('windows=' + $dualReq + ' ' + ($dualDetail -join ' '))
}

# =================================================================== STEP 7 ARCHIVE
if ($DateTag -eq '') { $DateTag = Get-Date -Format 'yyyy-MM-dd' }
$archRoot = Join-Path $prjOut ("evidence_{0}_p1_selfcheck" -f $DateTag)
if ($DryRun) {
    Step 7 'ARCHIVE' 'SKIP' ("dry-run (would write {0}\selfcheck_*.txt + README.md + SHA256SUMS.txt)" -f $archRoot)
} else {
    if (Test-Path -LiteralPath $archRoot) { $archRoot = $archRoot + '_' + $script:Stamp }
    try {
        New-Item -ItemType Directory -Force -Path $archRoot | Out-Null
        $artifacts = @()
        Get-ChildItem -LiteralPath $prjOut -Filter ("*_{0}*" -f $script:Stamp) -File -ErrorAction SilentlyContinue |
            ForEach-Object { $artifacts += $_.FullName }
        foreach ($f in $artifacts) { Copy-Item -LiteralPath $f -Destination $archRoot -Force }
        $verdictTxt = Join-Path $archRoot ("selfcheck_{0}.txt" -f $script:Stamp)
        $body = @()
        $body += "p1_selfcheck run log"
        $body += ("when      : {0}" -f $script:When)
        $body += ("mode      : RUN")
        $body += ("board     : {0}  com={1}  cable={2}  iface={3}" -f $Board, $Com, $Cable, $Iface)
        $body += ("capture   : seconds={0} send-delay={1} frame-len={2} local-dir={3}" -f $CaptureSeconds, $SendDelaySeconds, $FrameLen, $LocalDir)
        $body += ("verdict   : PASS={0} FAIL={1} SKIP={2}" -f $script:Pass, $script:Fail, $script:Skip)
        $body += ""
        $body += ($script:LogLines -join "`r`n")
        [System.IO.File]::WriteAllText($verdictTxt, ($body -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

        $readme = @()
        $readme += "# p1_selfcheck archive ($DateTag)"
        $readme += ""
        $readme += "Single-run reproduction of the prj12 P1 bring-up, per the prj12 dual-board bring-up manual sections 2/3."
        $readme += ""
        $readme += "| item | value |"
        $readme += "|---|---|"
        $readme += ("| board | {0} (COM {1}, cable {2}) |" -f $Board, $Com, $Cable)
        $readme += ("| local send direction | {0} (0x1 = PC1->PC2, 0x2 = PC2->PC1) |" -f $LocalDir)
        $readme += ("| capture | iface='{0}', ONE continuous window of {1} s per direction |" -f $Iface, $CaptureSeconds)
        $readme += ("| frame | {0} B payload, 20 frames per direction, 20 ms interval |" -f $FrameLen)
        $readme += ("| verdict | PASS={0} FAIL={1} SKIP={2} |" -f $script:Pass, $script:Fail, $script:Skip)
        $readme += ""
        $readme += "## Step verdicts"
        $readme += ""
        $readme += ($script:LogLines | Where-Object { $_ -match '^STEP \d' } | ForEach-Object { "- " + $_ })
        $readme += ""
        $readme += "## Discipline notes"
        $readme += ""
        $readme += "- 'the criterion did not fire' is NOT 'the criterion passed': SKIP means the check could not run."
        $readme += "- both boards share the JTAG cable serial 210512180081, so -Board Both is refused by the script."
        $readme += "- the data plane needs one continuous capture of >= 180 s; chunked captures were the 2026-11-06 false negative."
        $readme += "- the serial 'd' command is a toggle: only the LAST DMAMODE banner is authoritative."
        $readme += "- eth.dst is not judged: P1 echo frames may arrive as Ethernet broadcast."
        [System.IO.File]::WriteAllText((Join-Path $archRoot 'README.md'), ($readme -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

        $sums = @()
        Get-ChildItem -LiteralPath $archRoot -File | Where-Object { $_.Name -ne 'SHA256SUMS.txt' } | Sort-Object Name | ForEach-Object {
            $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower()
            $sums += ("{0}  {1}" -f $h, $_.Name)
        }
        [System.IO.File]::WriteAllText((Join-Path $archRoot 'SHA256SUMS.txt'), (($sums -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
        Step 7 'ARCHIVE' 'PASS' ("dir={0} files={1}" -f $archRoot, ($sums.Count + 1))
    } catch {
        Step 7 'ARCHIVE' 'FAIL' ("archive failed: {0}" -f $_.Exception.Message)
    }
}

# ======================================================================= summary
Say ""
Finish $(if ($script:Fail -gt 0) { 1 } else { 0 }) ''
