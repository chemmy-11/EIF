# =============================================================================
# r3c_seq.ps1 -- prj11 R2 round3c minimal board-verification sequencer
#
# PURPOSE (Lead executes on the board; the tool author never runs it on hardware)
#   Step-wise orchestration of the round3c board session:
#     Burn      : xsct = flash bit + ELF pair (jb31b_burn_pair.tcl), pre-checked
#                 by SHA256 (first 8 hex) of BOTH artifacts
#     Serial    : UART COM5 9600  'U' -> 'd' -> 'W'  (capture + parse)
#     Ping      : ping -n 1 192.168.1.10 (standalone; Cap also pings internally)
#     Cap       : vivado batch -- 4-ILA capture (r3c_cap.tcl) with PRE snapshot,
#                 trigger arming (ILA4 'dbg_l_bus[35]' = |stuck bit, ILA5
#                 dbg_wd_go_ui), the ping-1 stimulus, and POST upload --
#                 "before/after the wedge"
#                 round3c u_ila_4 shape: probe0 = packed dbg_l_bus[35:0] (36b),
#                 probe1 = bus bit35 (|stuck[3:0], the trigger bit); CSV columns
#                 are dbg_l_bus[0..35] and r3c_ila_analyze.py decodes the RTL
#                 bit map back to named AXI/mailbox/FSM signals.
#     Diag      : xsct -- post-wedge JTAG/LMB field read (r3c_diag.tcl)
#     SerialPost: best-effort 'W' after the wedge (silence itself is evidence)
#     Status    : offline summary of the newest R3C_* logs in -OutDir
#     All       : Burn -> Serial -> Cap -> Diag -> SerialPost -> summary
#     Plan      : (default) dry-run: validate artifacts/hashes/tools/port and
#                 print the exact commands -Run would execute. Touches nothing.
#
# SAFETY MODEL
#   -Run is REQUIRED to touch hardware (burn / serial / ping / vivado / xsct).
#   Without -Run every step is a dry-run that only prints the planned command
#   (same discipline as out\r2_board.ps1).
#   No automatic retries (AGENTS.md / round2d+round3b discipline: a failed
#   board experiment is not retried blindly; re-burn or power-cycle instead).
#
# WHY THE LONG VIVADO/XSCT COMMANDS GO THROUGH `cmd /c ... > log 2>&1`
#   Pitfall #58: capturing a long Vivado build's stdout through PowerShell
#   pipelines can deadlock (implement_debug_core spawns a child Vivado).
#   Logs are redirected to files natively and then read with Select-String.
#
# WHY SERIAL PRINTS NEVER INTERLEAVE WITH AXI READS (pitfall #44)
#   The script does serial probes and JTAG/ILA sessions in separate sequential
#   steps; nothing issues AXI reads while UART text is being printed, and no
#   two hardware sessions run concurrently (JTAG is single-owner).
#
# PITFALL #18/#17: this file MUST stay UTF-8 with BOM (EF BB BF) and must parse
#   with 0 errors under Windows PowerShell 5.1 [Parser]::ParseFile. Re-verify
#   after any edit:
#     $b = [System.IO.File]::ReadAllBytes($p)[0..2] -join ','
#     [System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$null,[ref]$errs)
#
# USAGE EXAMPLES
#   # dry-run plan (default, no hardware touched):
#   powershell -NoProfile -ExecutionPolicy Bypass -File r3c_seq.ps1
#   # burn round3c pair (hash pinned):
#   ... -File r3c_seq.ps1 -Step Burn -Run -Bit <r3c.bit> -Elf <r3c.elf> `
#        -ExpectBitHash8 <XXXXXXXX> -ExpectElfHash8 <YYYYYYYY> -Ltx <r3c.ltx>
#   # full sequence:
#   ... -File r3c_seq.ps1 -Step All -Run -Bit ... -Elf ... -Ltx ...
#
# EXIT CODES: 0 PASS/dry-run, 1 FAIL, 2 NOT_OBTAINED (judgement not obtained).
# =============================================================================

[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Burn', 'Serial', 'Ping', 'Cap', 'Diag', 'SerialPost', 'Status', 'All')]
    [string]$Step = 'Plan',

    [switch]$Run,

    [string]$OutDir = 'D:\FPGA\prj\project_11\out\evidence_2026-10-19',

    [string]$Round3cDir = 'D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-19_round3c',

    [string]$Bit = '',
    [string]$Elf = 'D:\FPGA\prj\project_11\sw\j3_soft\Debug\j3_soft.elf',
    [string]$Ltx = '',

    [string]$ExpectBitHash8 = '',
    [string]$ExpectElfHash8 = 'F5E0F1F3',

    [string]$Port = 'COM5',
    [int]$Baud = 9600,

    [string]$Tag = 'r3c',

    [double]$TrigTimeoutMin = 2,
    [string]$TrigILA4 = "dbg_l_bus[35]=eq1'b1",
    [string]$TrigILA5 = "dbg_wd_go_ui=eq1'b1",
    [string]$ExpectWidthILA4 = '',

    [switch]$SnapshotOnly,

    [string]$StimCmd = 'ping -n 1 -w 900 192.168.1.10',
    [string]$PingTarget = '192.168.1.10',

    [switch]$AllowUnpinned
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# constants (absolute paths; every one is existence-checked in Step Plan)
# ---------------------------------------------------------------------------
$script:ToolsDir  = $PSScriptRoot
$script:ProjRoot  = 'D:\FPGA\prj\project_11'
$script:PyExe     = 'C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe'
$script:UartProbe = 'D:\FPGA\prj\project_11\out\uart_probe.py'
$script:Xsct      = 'D:\Xilinx\Vitis\2023.1\bin\xsct.bat'
$script:Vivado    = 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat'
$script:BurnTcl   = 'D:\FPGA\prj\project_11\out\jb31b_burn_pair.tcl'
$script:CapTcl    = Join-Path $script:ToolsDir 'r3c_cap.tcl'
$script:DiagTcl   = Join-Path $script:ToolsDir 'r3c_diag.tcl'
$script:Analyzer  = Join-Path $script:ToolsDir 'r3c_ila_analyze.py'

$script:OutDir      = $OutDir
$script:Round3cDir  = $Round3cDir
$script:Bit         = $Bit
$script:Elf         = $Elf
$script:Ltx         = $Ltx
$script:ExpectBit   = $ExpectBitHash8
$script:ExpectElf   = $ExpectElfHash8
$script:Port        = $Port
$script:Baud        = $Baud
$script:Tag         = $Tag
$script:TrigMin     = $TrigTimeoutMin
$script:TrigILA4    = $TrigILA4
$script:TrigILA5    = $TrigILA5
$script:WidthILA4   = $ExpectWidthILA4
$script:StimCmd     = $StimCmd
$script:PingTarget  = $PingTarget
$script:RunMode     = [bool]$Run
$script:SnapOnly    = [bool]$SnapshotOnly

$script:Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:Results = New-Object System.Collections.ArrayList

if (-not (Test-Path -LiteralPath $script:OutDir)) {
    New-Item -ItemType Directory -Force -Path $script:OutDir | Out-Null
    Write-Host ("[r3c_seq] created OutDir " + $script:OutDir)
}
$script:LogPath = Join-Path $script:OutDir ("R3C_{0}_seq.log" -f $script:Stamp)
$null = Out-File -LiteralPath $script:LogPath -Encoding utf8 -InputObject ("# r3c_seq.ps1 log start " + (Get-Date -Format 's'))

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO'
    )
    $line = ("[{0}] {1} {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message)
    Write-Host $line
    try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 } catch { }
}

function Add-Result {
    param([string]$StepName, [string]$Result, [string]$Detail = '')
    $null = $script:Results.Add([pscustomobject]@{ Step = $StepName; Result = $Result; Detail = $Detail })
    Write-Log ("R3C_STEP_RESULT: step={0} result={1} {2}" -f $StepName, $Result, $Detail) ('RESULT')
}

function Get-Hash8 {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
        return $h.Substring(0, 8).ToUpperInvariant()
    } catch {
        return ''
    }
}

function Get-FileSizeSafe {
    param([string]$Path)
    try { return [int64](Get-Item -LiteralPath $Path -ErrorAction Stop).Length } catch { return -1 }
}

function Test-Tool {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path) {
        Write-Log ("TOOL_OK: " + $Label + " = " + $Path)
        return $true
    }
    Write-Log ("TOOL_MISSING: " + $Label + " = " + $Path) 'WARN'
    return $false
}

function Resolve-Artifacts {
    # If -Bit/-Ltx were not given, auto-pick the newest *.bit / *.ltx in the
    # round3c archive directory (Lead archives round3c under -Round3cDir).
    if ([string]::IsNullOrWhiteSpace($script:Bit)) {
        if (Test-Path -LiteralPath $script:Round3cDir) {
            $f = Get-ChildItem -LiteralPath $script:Round3cDir -Filter '*.bit' -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($null -ne $f) {
                $script:Bit = $f.FullName
                Write-Log ("ARTIFACT_AUTO: Bit <- " + $script:Bit)
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($script:Ltx)) {
        if (Test-Path -LiteralPath $script:Round3cDir) {
            $f = Get-ChildItem -LiteralPath $script:Round3cDir -Filter '*.ltx' -File -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($null -ne $f) {
                $script:Ltx = $f.FullName
                Write-Log ("ARTIFACT_AUTO: Ltx <- " + $script:Ltx)
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($script:Bit) -and (Test-Path -LiteralPath $script:Round3cDir)) {
        # fall back to the round3b bit ONLY as a dry-run placeholder marker
        Write-Log ("ARTIFACT_PENDING: no round3c *.bit in " + $script:Round3cDir + " (pin -Bit explicitly; see r3c_pin.md)") 'WARN'
    }
    if ([string]::IsNullOrWhiteSpace($script:Ltx) -and (Test-Path -LiteralPath $script:Round3cDir)) {
        Write-Log ("ARTIFACT_PENDING: no round3c *.ltx in " + $script:Round3cDir + " (pin -Ltx explicitly; see r3c_pin.md)") 'WARN'
    }
}

function Test-Artifact {
    param([string]$Path, [string]$Label, [string]$Expect8)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-Log ("ARTIFACT_MISSING: " + $Label + " path is empty (not pinned yet)") 'WARN'
        return $false
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log ("ARTIFACT_MISSING: " + $Label + " = " + $Path) 'WARN'
        return $false
    }
    $h8 = Get-Hash8 $Path
    $sz = Get-FileSizeSafe $Path
    Write-Log ("ARTIFACT: " + $Label + " path=" + $Path + " size=" + $sz + " sha8=" + $h8)
    if ([string]::IsNullOrWhiteSpace($Expect8)) {
        Write-Log ("HASH_UNPINNED: " + $Label + " actual sha8=" + $h8 + " (pass -Expect" + $Label + "Hash8 to pin)") 'WARN'
        return $false
    }
    if ($h8 -ieq $Expect8.Trim().ToUpperInvariant()) {
        Write-Log ("HASH_OK: " + $Label + " sha8=" + $h8 + " == expect " + $Expect8)
        return $true
    }
    Write-Log ("HASH_MISMATCH: " + $Label + " actual sha8=" + $h8 + " expect=" + $Expect8) 'FAIL'
    return $false
}

function Invoke-NativeToLog {
    # run a command line through cmd.exe with native file redirection to $LogPath
    param([string]$CommandLine, [string]$LogPath)
    Write-Log ("EXEC: " + $CommandLine)
    if (-not $script:RunMode) {
        Write-Log ("DRYRUN: would execute the command above; output -> " + $LogPath) 'DRYRUN'
        return -1
    }
    & cmd.exe /c $CommandLine
    return $LASTEXITCODE
}

function Get-LogMatches {
    param([string]$Path, [string]$Pattern)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try {
        return @(Select-String -LiteralPath $Path -Pattern $Pattern -ErrorAction Stop | ForEach-Object { $_.Line.Trim() })
    } catch {
        return @()
    }
}

# ---------------------------------------------------------------------------
# Step: Plan (dry-run validation; default)
# ---------------------------------------------------------------------------
function Invoke-Plan {
    Write-Log 'STEP Plan: offline validation only (no hardware access)'
    Resolve-Artifacts
    Write-Log ("INPUT: Bit=" + $script:Bit)
    Write-Log ("INPUT: Elf=" + $script:Elf)
    Write-Log ("INPUT: Ltx=" + $script:Ltx)
    Write-Log ("INPUT: OutDir=" + $script:OutDir)
    Write-Log ("INPUT: Round3cDir=" + $script:Round3cDir)
    Write-Log ("INPUT: Port=" + $script:Port + " baud=" + $script:Baud)
    Write-Log ("INPUT: Tag=" + $script:Tag + " Steps=" + $Step + " Run=" + $script:RunMode)
    Write-Log ("INPUT: TrigILA4='" + $script:TrigILA4 + "' TrigILA5='" + $script:TrigILA5 + "' timeout_min=" + $script:TrigMin)
    Write-Log ("INPUT: StimCmd='" + $script:StimCmd + "' SnapshotOnly=" + $script:SnapOnly)

    $bitOk = Test-Artifact $script:Bit 'BIT' $script:ExpectBit
    $elfOk = Test-Artifact $script:Elf 'ELF' $script:ExpectElf
    $ltxOk = Test-Artifact $script:Ltx 'LTX' ''
    if (-not $bitOk) { Write-Log 'PLAN_NOTE: BIT hash not pinned/verified; Burn will refuse unless -AllowUnpinned is given (r3c_pin.md)' 'WARN' }
    if (-not $ltxOk -and $script:RunMode) { Write-Log 'PLAN_NOTE: LTX missing; Cap cannot run (r3c_cap.tcl needs the archived probes ltx)' 'WARN' }

    $tools = @(
        @{ P = $script:PyExe; N = 'python(full path)' },
        @{ P = $script:UartProbe; N = 'uart_probe.py' },
        @{ P = $script:Xsct; N = 'xsct.bat' },
        @{ P = $script:Vivado; N = 'vivado.bat' },
        @{ P = $script:BurnTcl; N = 'jb31b_burn_pair.tcl' },
        @{ P = $script:CapTcl; N = 'r3c_cap.tcl' },
        @{ P = $script:DiagTcl; N = 'r3c_diag.tcl' },
        @{ P = $script:Analyzer; N = 'r3c_ila_analyze.py' }
    )
    foreach ($t in $tools) { $null = Test-Tool $t.P $t.N }

    if (Test-Path -LiteralPath $script:PyExe) {
        $env:PYTHONUTF8 = '1'
        $pyOut = & $script:PyExe -c "import serial; print('pyserial', serial.__version__)" 2>&1 | Out-String
        Write-Log ("PY_PYSERIAL: " + ($pyOut.Trim() -replace "`r?`n", ' '))
    }
    try {
        $ports = @([System.IO.Ports.SerialPort]::GetPortNames())
    } catch {
        $ports = @()
    }
    $portHit = @($ports | Where-Object { $_ -ieq $script:Port })
    Write-Log ("SERIAL_PORTS: " + ($ports -join ',') + " | wanted=" + $script:Port + " present=" + ($portHit.Count -gt 0))
    if ($portHit.Count -eq 0) { Write-Log 'SERIAL_PORT_WARN: wanted port not enumerated (USB-UART driver/board power?)' 'WARN' }

    Write-Log 'PLAN_NEXT_COMMANDS (dry-run; add -Run to execute per-step):'
    Write-Log ('  xsct "' + $script:Xsct + '" "' + $script:BurnTcl + '" "' + $script:Bit + '" "' + $script:Elf + '" > burn.log 2>&1')
    Write-Log ('  "' + $script:PyExe + '" "' + $script:UartProbe + '" --port ' + $script:Port + ' --cmd U --wait 2.5 --raw')
    Write-Log ('  "' + $script:PyExe + '" "' + $script:UartProbe + '" --port ' + $script:Port + ' --cmd d --wait 1.5 --raw')
    Write-Log ('  "' + $script:PyExe + '" "' + $script:UartProbe + '" --port ' + $script:Port + ' --cmd W --wait 1.5 --raw')
    Write-Log ('  "' + $script:Vivado + '" -mode batch -source "' + $script:CapTcl + '" -notrace -log cap_vivado.log > cap_console.log 2>&1')
    Write-Log ('  xsct "' + $script:Xsct + '" "' + $script:DiagTcl + '" > diag.log 2>&1')
    Write-Log ('  "' + $script:PyExe + '" "' + $script:Analyzer + '" --dir "' + $script:OutDir + '" --pattern "R3C_*.csv"')

    Add-Result 'Plan' 'PASS' ("bitOk=" + $bitOk + " elfOk=" + $elfOk + " ltxOk=" + $ltxOk)
    return 'PASS'
}

# ---------------------------------------------------------------------------
# Step: Burn
# ---------------------------------------------------------------------------
function Invoke-Burn {
    Write-Log 'STEP Burn: xsct flash bit+ELF pair'
    Resolve-Artifacts
    $okBit = Test-Artifact $script:Bit 'BIT' $script:ExpectBit
    $okElf = Test-Artifact $script:Elf 'ELF' $script:ExpectElf
    if (-not ($okBit -and $okElf) -and $script:RunMode -and (-not $script:AllowUnpinned)) {
        Write-Log 'BURN_REFUSED: bit/ELF hash not verified against pinned expectations. Pass correct -ExpectBitHash8/-ExpectElfHash8 (see r3c_pin.md), or -AllowUnpinned to override consciously.' 'FAIL'
        Add-Result 'Burn' 'FAIL' 'hash not pinned/verified'
        return 'FAIL'
    }
    if ((-not $okBit) -or (-not $okElf)) {
        Write-Log 'BURN_PIN_WARN: one artifact hash is not pinned/verified (dry-run OK; -Run refuses unless -AllowUnpinned)' 'WARN'
    }
    if (-not (Test-Path -LiteralPath $script:BurnTcl)) {
        Add-Result 'Burn' 'FAIL' ('burn tcl missing: ' + $script:BurnTcl)
        return 'FAIL'
    }
    $log = Join-Path $script:OutDir ("R3C_{0}_burn.log" -f $script:Stamp)
    $cmd = ('"' + $script:Xsct + '" "' + $script:BurnTcl + '" "' + $script:Bit + '" "' + $script:Elf + '" > "' + $log + '" 2>&1')
    $rc = Invoke-NativeToLog -CommandLine $cmd -LogPath $log
    if (-not $script:RunMode) {
        Add-Result 'Burn' 'DRYRUN' ('would burn ' + $script:Bit + ' + ' + $script:Elf)
        return 'DRYRUN'
    }
    $hit = Get-LogMatches $log 'PAIR_BURNED'
    $err = Get-LogMatches $log '^\s*ERROR|error:|Invalid|failed'
    if ($hit.Count -gt 0) {
        Write-Log ('BURN_OK: PAIR_BURNED in ' + $log)
        Add-Result 'Burn' 'PASS' $log
        Start-Sleep -Seconds 2
        return 'PASS'
    }
    Write-Log ('BURN_LOG_TAIL: ' + ((Get-Content -LiteralPath $log -Tail 10 -ErrorAction SilentlyContinue) -join ' | ')) 'FAIL'
    Add-Result 'Burn' 'FAIL' ('no PAIR_BURNED; rc=' + $rc + ' log=' + $log)
    return 'FAIL'
}

# ---------------------------------------------------------------------------
# UART helpers (pitfall #44: serial text capture never runs concurrently with
# any AXI/ILA session -- steps are strictly sequential)
# ---------------------------------------------------------------------------
function Invoke-UartProbe {
    param([string]$Cmd, [double]$Wait = 2.0, [double]$Drain = 0.2)
    $argv = @($script:UartProbe, '--port', $script:Port, '--cmd', $Cmd,
              '--wait', [string]$Wait, '--drain', [string]$Drain, '--raw')
    if (-not $script:RunMode) {
        Write-Log ('DRYRUN: would run: "' + $script:PyExe + '" ' + ($argv -join ' ')) 'DRYRUN'
        return ''
    }
    Write-Log ('UART_TX: cmd=' + $Cmd + ' wait=' + $Wait + 's')
    $out = & $script:PyExe @argv 2>&1 | Out-String
    $flat = ($out -replace "`r?`n", ' | ').Trim()
    Write-Log ('UART_RX[' + $Cmd + ']: ' + $flat)
    return $out
}

function Get-FirstGroup {
    param([string]$Text, [string]$Pattern)
    $m = [regex]::Match($Text, $Pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Show-UProbe {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Log 'SERIAL_U: NO_RESPONSE (firmware not booted / serial busy / already wedged?)' 'WARN'
        return
    }
    $mode = Get-FirstGroup $Text '\[B2\]\s+U\s+mode=(\d+)'
    $id   = Get-FirstGroup $Text '\[B2\]\s+U\s+id:\s*([0-9a-fA-F]+)'
    $wreq = Get-FirstGroup $Text '\[B2\]\s+U\s+wreq:\s*([0-9a-fA-F]+)'
    $wdbg = Get-FirstGroup $Text '\[B2\]\s+U\s+wdbg:\s*([0-9a-fA-F]+)'
    $s2sr = Get-FirstGroup $Text '\[B2\]\s+U\s+s2sr:\s*([0-9a-fA-F]+)'
    Write-Log ('SERIAL_U: mode=' + $mode + ' id1=' + $id + ' wreq1=' + $wreq + ' wdbg1=' + $wdbg + ' s2sr1=' + $s2sr)
}

function Show-DProbe {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Log 'SERIAL_D: NO_RESPONSE' 'WARN'
        return
    }
    $mode = Get-FirstGroup $Text '\[B2\]\s+DMAMODE\s+now=(\w+)'
    Write-Log ('SERIAL_D: DMAMODE=' + $mode + ' (toggle; must be DMA after boot)')
    if ($mode -ieq 'DMA') {
        Write-Log 'SERIAL_D_OK: engine=1 (DMA residency service)'
    } else {
        Write-Log 'SERIAL_D_WARN: engine is not DMA after d; do NOT blindly send another d (it is a toggle)' 'WARN'
    }
}

function Show-WProbe {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-Log 'SERIAL_W: NO_RESPONSE (wedge suspected: firmware main loop no longer prints)' 'WARN'
        return
    }
    $s2cr  = Get-FirstGroup $Text 's2cr=([0-9a-fA-F]+)'
    $s2sr  = Get-FirstGroup $Text 's2sr=([0-9a-fA-F]+)'
    $s2len = Get-FirstGroup $Text 's2len=([0-9a-fA-F]+)'
    $m2sr  = Get-FirstGroup $Text 'm2sr=([0-9a-fA-F]+)'
    $wreq  = Get-FirstGroup $Text 'wreq=([0-9a-fA-F]+)'
    $wdbg  = Get-FirstGroup $Text 'wdbg=([0-9a-fA-F]+)'
    $halt  = Get-FirstGroup $Text 'halt=(\d)'
    $idle  = Get-FirstGroup $Text 'idle=(\d)'
    $ioc   = Get-FirstGroup $Text 'ioc=(\d)'
    Write-Log ('SERIAL_W: s2cr=' + $s2cr + ' s2sr=' + $s2sr + ' s2len=' + $s2len + ' m2sr=' + $m2sr + ' wreq=' + $wreq + ' wdbg=' + $wdbg + ' halt=' + $halt + ' idle=' + $idle + ' ioc=' + $ioc)
    if ($s2len -ieq '56') { Write-Log 'SERIAL_W_INFO: s2len=0x56=86 => S2MM LENGTH equals the expected ping frame length (INFO only, not a hard judge)' }
    if ($halt -eq '1') { Write-Log 'SERIAL_W_INFO: S2MM Halted=1 => S2MM channel is stopped (INFO)' }
    if ($wdbg -ne '' -and $wdbg.Length -ge 1) {
        if ($wdbg.Substring(0, 1) -match '[89a-fA-F]') {
            Write-Log 'SERIAL_W_INFO: wdbg top bit set => write engine fault sticky (INFO; recovery = firmware ACK +0x4C or re-burn)'
        }
    }
}

# ---------------------------------------------------------------------------
# Step: Serial ('U' -> 'd' -> 'W')
# ---------------------------------------------------------------------------
function Invoke-Serial {
    Write-Log ('STEP Serial: U -> d -> W on ' + $script:Port + ' @' + [string]$script:Baud)
    if (-not $script:RunMode) {
        $null = Invoke-UartProbe 'U' 2.5 0.2
        $null = Invoke-UartProbe 'd' 1.5 0.2
        $null = Invoke-UartProbe 'W' 1.5 0.2
        Add-Result 'Serial' 'DRYRUN' 'U/d/W planned'
        return 'DRYRUN'
    }
    $u = Invoke-UartProbe 'U' 2.5 0.2
    Show-UProbe $u
    Start-Sleep -Milliseconds 300
    $d = Invoke-UartProbe 'd' 1.5 0.2
    Show-DProbe $d
    Start-Sleep -Milliseconds 500
    $w = Invoke-UartProbe 'W' 1.5 0.2
    Show-WProbe $w
    if ([string]::IsNullOrWhiteSpace($u)) {
        Add-Result 'Serial' 'FAIL' 'U no response'
        return 'FAIL'
    }
    Add-Result 'Serial' 'PASS' 'U/d/W captured'
    return 'PASS'
}

# ---------------------------------------------------------------------------
# Step: Ping
# ---------------------------------------------------------------------------
function Invoke-Ping {
    Write-Log ('STEP Ping: ping -n 1 -w 900 ' + $script:PingTarget)
    if (-not $script:RunMode) {
        Write-Log ('DRYRUN: would run: ping -n 1 -w 900 ' + $script:PingTarget) 'DRYRUN'
        Add-Result 'Ping' 'DRYRUN' 'ping planned'
        return 'DRYRUN'
    }
    $out = & ping -n 1 -w 900 $script:PingTarget 2>&1 | Out-String
    $flat = ($out -replace "`r?`n", ' | ').Trim()
    Write-Log ('PING_RAW: ' + $flat)
    $ttl = [regex]::Matches($out, 'TTL=')
    if ($ttl.Count -ge 1) {
        Write-Log ('PING_RESULT: PASS replies=' + $ttl.Count)
        Add-Result 'Ping' 'PASS' ('replies=' + $ttl.Count)
        return 'PASS'
    }
    Write-Log 'PING_RESULT: FAIL (no TTL= reply)' 'FAIL'
    Add-Result 'Ping' 'FAIL' 'no reply'
    return 'FAIL'
}

# ---------------------------------------------------------------------------
# Step: Cap (4-ILA capture via vivado batch)
# ---------------------------------------------------------------------------
function Invoke-Cap {
    Write-Log 'STEP Cap: 4-ILA capture (PRE -> arm -> stim -> POST)'
    Resolve-Artifacts
    if (-not (Test-Path -LiteralPath $script:CapTcl)) {
        Add-Result 'Cap' 'FAIL' ('r3c_cap.tcl missing: ' + $script:CapTcl)
        return 'FAIL'
    }
    if ([string]::IsNullOrWhiteSpace($script:Ltx) -or (-not (Test-Path -LiteralPath $script:Ltx))) {
        if (-not $script:RunMode) {
            Write-Log ('CAP_DRYRUN_PENDING: Ltx not pinned yet (' + $script:Ltx + '); a real run will refuse') 'WARN'
        } else {
            Add-Result 'Cap' 'FAIL' ('Ltx not resolved: ' + $script:Ltx)
            return 'FAIL'
        }
    }
    $capVivadoLog = Join-Path $script:OutDir ("R3C_{0}_cap_vivado.log" -f $script:Stamp)
    $capConsoleLog = Join-Path $script:OutDir ("R3C_{0}_cap_console.log" -f $script:Stamp)

    $env:R2_LTX = $script:Ltx
    $env:R2_OUT_DIR = $script:OutDir
    $env:R2_TAG = $script:Tag
    $env:R2_WAIT_MIN = [string]$script:TrigMin
    $env:R2_TRIG_ILA4 = $script:TrigILA4
    $env:R2_TRIG_ILA5 = $script:TrigILA5
    if (-not [string]::IsNullOrWhiteSpace($script:WidthILA4)) {
        $env:R2C_EXPECT_WIDTH_ILA4 = $script:WidthILA4
    } else {
        Remove-Item Env:\R2C_EXPECT_WIDTH_ILA4 -ErrorAction SilentlyContinue
    }
    if ($script:SnapOnly) {
        $env:R2_SNAPSHOT_ONLY = '1'
        $env:R2_STIM_CMD = ''
    } else {
        Remove-Item Env:\R2_SNAPSHOT_ONLY -ErrorAction SilentlyContinue
        $env:R2_STIM_CMD = $script:StimCmd
    }
    Write-Log ('CAP_ENV: R2_LTX=' + $env:R2_LTX + ' R2_OUT_DIR=' + $env:R2_OUT_DIR + ' R2_TAG=' + $env:R2_TAG + ' R2_SNAPSHOT_ONLY=' + $env:R2_SNAPSHOT_ONLY + ' R2_STIM_CMD=' + $env:R2_STIM_CMD + ' R2_WAIT_MIN=' + $env:R2_WAIT_MIN)

    $cmd = ('"' + $script:Vivado + '" -mode batch -source "' + $script:CapTcl + '" -notrace -log "' + $capVivadoLog + '" > "' + $capConsoleLog + '" 2>&1')
    $rc = Invoke-NativeToLog -CommandLine $cmd -LogPath $capVivadoLog
    if (-not $script:RunMode) {
        Add-Result 'Cap' 'DRYRUN' 'vivado batch 4-ILA capture planned'
        return 'DRYRUN'
    }

    $resLines = Get-LogMatches $capVivadoLog '^R3C_RESULT:'
    $trigLines = Get-LogMatches $capVivadoLog '^R3C_TRIG_STATUS|^R3C_TRIGGER_SUMMARY'
    $csvLines = Get-LogMatches $capVivadoLog '^R3C_CSV:'
    foreach ($l in $trigLines) { Write-Log ('CAP_' + $l) }
    foreach ($l in $csvLines) { Write-Log ('CAP_' + $l) }
    $res = ''
    if ($resLines.Count -gt 0) { $res = $resLines[$resLines.Count - 1] }
    if ($res -match 'R3C_RESULT:\s*PASS') {
        Write-Log ('CAP_OK: ' + $res + ' (log ' + $capVivadoLog + ')')
        Add-Result 'Cap' 'PASS' $capVivadoLog
        return 'PASS'
    }
    if ($res -match 'R3C_RESULT:\s*NO_TRIGGER') {
        Write-Log ('CAP_NO_TRIGGER: ' + $res) 'WARN'
        Add-Result 'Cap' 'NOT_OBTAINED' ('NO_TRIGGER; log ' + $capVivadoLog)
        return 'NOT_OBTAINED'
    }
    Write-Log ('CAP_FAIL: rc=' + $rc + ' result=' + $res + ' log=' + $capVivadoLog) 'FAIL'
    Add-Result 'Cap' 'FAIL' ('rc=' + $rc + ' log=' + $capVivadoLog)
    return 'FAIL'
}

# ---------------------------------------------------------------------------
# Step: Diag (post-wedge JTAG/LMB read via xsct)
# ---------------------------------------------------------------------------
function Invoke-Diag {
    Write-Log 'STEP Diag: post-wedge JTAG/LMB field read (xsct)'
    if (-not (Test-Path -LiteralPath $script:DiagTcl)) {
        Add-Result 'Diag' 'FAIL' ('r3c_diag.tcl missing: ' + $script:DiagTcl)
        return 'FAIL'
    }
    $log = Join-Path $script:OutDir ("R3C_{0}_diag.log" -f $script:Stamp)
    $cmd = ('"' + $script:Xsct + '" "' + $script:DiagTcl + '" > "' + $log + '" 2>&1')
    $rc = Invoke-NativeToLog -CommandLine $cmd -LogPath $log
    if (-not $script:RunMode) {
        Add-Result 'Diag' 'DRYRUN' 'xsct LMB read planned'
        return 'DRYRUN'
    }
    $resLines = Get-LogMatches $log '^R3C_DIAG_RESULT:'
    $keyLines = Get-LogMatches $log '^R3C_KEY:'
    $sumLines = Get-LogMatches $log '^R3C_SUMMARY:'
    $stepLines = Get-LogMatches $log '^R3C_STEP_DECODE:'
    $pcLines = Get-LogMatches $log '^R3C_PC_'
    foreach ($l in $keyLines) { Write-Log ('DIAG_' + $l) }
    foreach ($l in $sumLines) { Write-Log ('DIAG_' + $l) }
    foreach ($l in $stepLines) { Write-Log ('DIAG_' + $l) }
    foreach ($l in $pcLines) { Write-Log ('DIAG_' + $l) }
    $res = ''
    if ($resLines.Count -gt 0) { $res = $resLines[$resLines.Count - 1] }
    if ($res -match 'PASS') {
        Add-Result 'Diag' 'PASS' $log
        return 'PASS'
    }
    if ($res -match 'PARTIAL') {
        Write-Log ('DIAG_PARTIAL: ' + $res) 'WARN'
        Add-Result 'Diag' 'NOT_OBTAINED' $log
        return 'NOT_OBTAINED'
    }
    Add-Result 'Diag' 'FAIL' ('rc=' + $rc + ' log=' + $log)
    return 'FAIL'
}

# ---------------------------------------------------------------------------
# Step: SerialPost (best-effort 'W' after the wedge)
# ---------------------------------------------------------------------------
function Invoke-SerialPost {
    Write-Log "STEP SerialPost: best-effort 'W' after the wedge (silence is evidence)"
    if (-not $script:RunMode) {
        $null = Invoke-UartProbe 'W' 2.0 0.2
        Add-Result 'SerialPost' 'DRYRUN' 'W planned'
        return 'DRYRUN'
    }
    $w = Invoke-UartProbe 'W' 2.0 0.2
    Show-WProbe $w
    if ([string]::IsNullOrWhiteSpace($w)) {
        Write-Log 'SERIAL_POST_INFO: no response after ping -- consistent with a wedged firmware main loop (INFO, cross-check with g_step from Diag)' 'WARN'
        Add-Result 'SerialPost' 'NOT_OBTAINED' 'silent (wedge suspected)'
        return 'NOT_OBTAINED'
    }
    Add-Result 'SerialPost' 'PASS' 'W responded'
    return 'PASS'
}

# ---------------------------------------------------------------------------
# Step: Status (offline summary of newest logs)
# ---------------------------------------------------------------------------
function Invoke-Status {
    Write-Log ('STEP Status: offline summary of ' + $script:OutDir)
    $patterns = @('R3C_*_seq.log', 'R3C_*_burn.log', 'R3C_*_cap_vivado.log', 'R3C_*_cap_console.log', 'R3C_*_diag.log')
    $reports = @()
    foreach ($p in $patterns) {
        $reports += @(Get-ChildItem -LiteralPath $script:OutDir -Filter $p -File -ErrorAction SilentlyContinue)
    }
    if ($reports.Count -eq 0) {
        Write-Log 'STATUS: no R3C_* log in OutDir yet'
        Add-Result 'Status' 'PASS' 'no logs'
        return 'PASS'
    }
    $reports = @($reports | Sort-Object LastWriteTime -Descending | Select-Object -First 8)
    foreach ($f in $reports) {
        Write-Log ('STATUS_FILE: ' + $f.FullName + ' (' + $f.Length + ' B, ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') + ')')
        $marks = @(Select-String -LiteralPath $f.FullName -Pattern 'R3C_RESULT:|R3C_DIAG_RESULT:|R3C_STEP_RESULT:|R3C_KEY:|BURN_OK|PAIR_BURNED|R3C_SUMMARY:' -ErrorAction SilentlyContinue)
        foreach ($m in ($marks | Select-Object -Last 14)) { Write-Log ('STATUS_LINE: ' + $m.Line.Trim()) }
    }
    Add-Result 'Status' 'PASS' ('files=' + $reports.Count)
    return 'PASS'
}

# ---------------------------------------------------------------------------
# Step: All
# ---------------------------------------------------------------------------
function Invoke-All {
    Write-Log 'STEP All: Burn -> Serial -> Cap -> Diag -> SerialPost'
    $burn = Invoke-Burn
    if ($burn -ne 'PASS' -and $burn -ne 'DRYRUN') {
        Write-Log 'ALL_ABORT: burn failed; do not proceed (check hash/pins/JTAG)' 'FAIL'
        return 'FAIL'
    }
    if ($burn -eq 'PASS') { Start-Sleep -Seconds 3 }
    $null = Invoke-Serial
    $cap = Invoke-Cap
    $null = Invoke-Diag
    $null = Invoke-SerialPost
    if ($cap -eq 'PASS') { return 'PASS' }
    if ($cap -eq 'NOT_OBTAINED') { return 'NOT_OBTAINED' }
    if ($cap -eq 'DRYRUN') { return 'DRYRUN' }
    return 'FAIL'
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
function Write-FinalSummary {
    $order = @{ PASS = 0; DRYRUN = 0; NOT_OBTAINED = 2; FAIL = 1 }
    $worst = 0
    foreach ($r in $script:Results) {
        $code = 0
        if ($order.ContainsKey($r.Result)) { $code = $order[$r.Result] }
        if ($code -gt $worst) { $worst = $code }
    }
    $label = 'PASS'
    if ($worst -eq 1) { $label = 'FAIL' }
    elseif ($worst -eq 2) { $label = 'NOT_OBTAINED' }
    Write-Log ('R3C_SEQ_LOG: ' + $script:LogPath)
    Write-Log ('R3C_SEQ_RESULT: ' + $label + ' (steps=' + $script:Results.Count + ')') 'RESULT'
    return $worst
}

try {
    Write-Log ('R3C_SEQ_START step=' + $Step + ' run=' + $script:RunMode + ' tag=' + $script:Tag)
    Write-Log ('R3C_SEQ_HOST ' + $env:COMPUTERNAME)
    Write-Log ('R3C_SEQ_PS ' + $PSVersionTable.PSVersion.ToString())

    $verdict = 'PASS'
    switch ($Step) {
        'Plan'       { $verdict = Invoke-Plan }
        'Burn'       { $verdict = Invoke-Burn }
        'Serial'     { $verdict = Invoke-Serial }
        'Ping'       { $verdict = Invoke-Ping }
        'Cap'        { $verdict = Invoke-Cap }
        'Diag'       { $verdict = Invoke-Diag }
        'SerialPost' { $verdict = Invoke-SerialPost }
        'Status'     { $verdict = Invoke-Status }
        'All'        { $verdict = Invoke-All }
        default      { $verdict = 'FAIL' }
    }
    $rc = Write-FinalSummary
    exit $rc
} catch {
    $msg = $_.Exception.Message
    Write-Log ('R3C_SEQ_EXCEPTION: ' + $msg) 'FAIL'
    Write-Log ('R3C_SEQ_RESULT: FAIL (unhandled exception)') 'RESULT'
    exit 1
}
