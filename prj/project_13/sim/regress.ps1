#==============================================================================
# regress.ps1 -- prj13 P1-5  B1 reset-pairing regression suite (xsim)
#-----------------------------------------------------------------------------
# WHAT IT DOES
#   Expands the prj12 evidence runs (oneside / ctrl, 2026-11-07) into a matrix
#   over the defect space of the DMA write path self-lock:
#
#     oneside : 1 flap, user-side reset only      (real aurora_rst wiring)
#     ctrl    : 1 flap, both resets together      (control group = the B1 idea)
#     mem2    : 1 flap on a HAS_DMA=0 instance    (B->A / reply-direction FIFOs)
#     multi   : 5 consecutive flaps               (no lock may accumulate)
#     silent  : Q in [5634,8191] ~ PRE=37 frames  (silent misalignment branch)
#     zero    : Q = 0, clean power-on flap        (harmless branch)
#
#   Every scenario runs TWICE, positive and negative control:
#     pos = rtl/ as shipped  (already contains B1) + -dB1_PATCHED  -> expect PASS
#     neg = sim/p1_regress/neg_rtl/frame_mem_if.v (B1 reverted)    -> expect FAIL
#   except the two branches where the defect is harmless by construction
#   (ctrl, zero), whose negative control must also PASS -- see the table below.
#
#   Q = bytes already popped mod 8192 when the flap happens. One 154-byte
#   stimulus frame becomes 155 wr_en cycles inside frame_mem_if, so
#   Q = PRE * 155 mod 8192:  PRE=3 -> 465 (hard lock), PRE=37 -> 5735 (silent).
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\regress.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\regress.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\regress.ps1 -Scenario silent
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\regress.ps1 -KeepWork
#
# DISCIPLINE
#   * xsim is a machine-wide serial resource: the script refuses to start while any
#     vivado/xsim/xvlog/xelab process is alive.
#   * TEMP/TMP are forced to D:\FPGA\.tmp (ASCII) for the child processes.
#   * xsim.dir is cleared before every compile (pit #48: stale dir = phantom build).
#   * Exit code: 0 = every case matched its expected verdict, 1 = at least one did not.
#   * NOT run automatically by anything. A first real run must be scheduled by the
#     Lead because the machine is shared.
#==============================================================================
param(
    [ValidateSet('all', 'oneside', 'ctrl', 'mem2', 'multi', 'silent', 'zero')]
    [string]$Scenario = 'all',
    [switch]$DryRun,
    [switch]$WhatIf,
    [switch]$KeepWork,
    [string]$OutRoot = 'D:\FPGA\prj\project_13\out\evidence_2026-11-08_p1_suite'
)

$ErrorActionPreference = 'Stop'
$dry = ($DryRun.IsPresent -or $WhatIf.IsPresent)

function Say([string]$s) { Write-Output $s }
function Die([string]$s) { Write-Output "REGRESS_ERROR: $s"; exit 2 }

#------------------------------------------------------------------ geometry
$Proj    = 'D:\FPGA\prj\project_13'
$RtlDir  = Join-Path $Proj 'rtl'
$SimDir  = Join-Path $Proj 'sim'
$RegDir  = Join-Path $SimDir 'p1_regress'
$NegRtl  = Join-Path $RegDir 'neg_rtl\frame_mem_if.v'
$TbMatrix = Join-Path $RegDir 'tb_b1_matrix.v'
$TbMem2   = Join-Path $RegDir 'tb_b1_mem2.v'

$Xvlog = 'D:\Xilinx\Vivado\2023.1\bin\xvlog.bat'
$Xelab = 'D:\Xilinx\Vivado\2023.1\bin\xelab.bat'
$Xsim  = 'D:\Xilinx\Vivado\2023.1\bin\xsim.bat'

# RTL compiled for BOTH variants (B1 only touches frame_mem_if + the top level)
$RtlCommon = @(
    (Join-Path $RtlDir 'async_fifo.v'),
    (Join-Path $RtlDir 'dma_rd_shim_v2.v'),
    (Join-Path $RtlDir 'axi4_master_bridge.v')
)
$RtlB1 = Join-Path $RtlDir 'frame_mem_if.v'

#------------------------------------------------------------ the case matrix
# expect : the verdict this case MUST produce for the suite to be meaningful.
#          The two PASS/PASS rows are the "defect is harmless here" branches and
#          are just as important as the FAIL rows (they bound the trigger).
$AllCases = @(
    @{ Name = 'oneside'; Tb = 'matrix'; Variant = 'pos'; Pre = 3;  Flaps = 1; Post = 3; Both = 0; Expect = 'PASS'; Why = 'B1 build survives one-sided flap' },
    @{ Name = 'oneside'; Tb = 'matrix'; Variant = 'neg'; Pre = 3;  Flaps = 1; Post = 3; Both = 0; Expect = 'FAIL'; Why = 'pre-B1 RTL must self-lock (Q=465)' },
    @{ Name = 'ctrl';    Tb = 'matrix'; Variant = 'pos'; Pre = 3;  Flaps = 1; Post = 3; Both = 1; Expect = 'PASS'; Why = 'control group: paired reset' },
    @{ Name = 'ctrl';    Tb = 'matrix'; Variant = 'neg'; Pre = 3;  Flaps = 1; Post = 3; Both = 1; Expect = 'PASS'; Why = 'paired reset cures the defect too' },
    @{ Name = 'mem2';    Tb = 'mem2';   Variant = 'pos'; Pre = 3;  Flaps = 1; Post = 3; Both = 0; Expect = 'PASS'; Why = 'HAS_DMA=0 (B->A) direction survives' },
    @{ Name = 'mem2';    Tb = 'mem2';   Variant = 'neg'; Pre = 3;  Flaps = 1; Post = 3; Both = 0; Expect = 'FAIL'; Why = 'reverse direction is equally broken' },
    @{ Name = 'multi';   Tb = 'matrix'; Variant = 'pos'; Pre = 3;  Flaps = 5; Post = 3; Both = 0; Expect = 'PASS'; Why = '5 consecutive flaps, no lock accumulates' },
    @{ Name = 'multi';   Tb = 'matrix'; Variant = 'neg'; Pre = 3;  Flaps = 5; Post = 3; Both = 0; Expect = 'FAIL'; Why = 'first flap already locks' },
    @{ Name = 'silent';  Tb = 'matrix'; Variant = 'pos'; Pre = 37; Flaps = 1; Post = 3; Both = 0; Expect = 'PASS'; Why = 'Q=5735 silent-misalignment branch, B1 clean' },
    @{ Name = 'silent';  Tb = 'matrix'; Variant = 'neg'; Pre = 37; Flaps = 1; Post = 3; Both = 0; Expect = 'FAIL'; Why = 'Q=5735: no hard lock but garbage frames committed' },
    @{ Name = 'zero';    Tb = 'matrix'; Variant = 'pos'; Pre = 0;  Flaps = 1; Post = 3; Both = 0; Expect = 'PASS'; Why = 'Q=0 clean window is harmless' },
    @{ Name = 'zero';    Tb = 'matrix'; Variant = 'neg'; Pre = 0;  Flaps = 1; Post = 3; Both = 0; Expect = 'PASS'; Why = 'Q=0: defect triggers nothing (bounds the claim)' }
)

$Cases = @($AllCases | Where-Object { ($Scenario -eq 'all') -or ($_.Name -eq $Scenario) })
if ($Cases.Count -eq 0) { Die "no case selected for -Scenario $Scenario" }

#--------------------------------------------------------------- ASCII / env
function Test-PureAscii([string]$p) {
    foreach ($ch in $p.ToCharArray()) { if ([int]$ch -gt 127) { return $false } }
    return $true
}
$AsciiTmp = 'D:\FPGA\.tmp'
foreach ($p in @($Proj, $OutRoot, $AsciiTmp, $env:TEMP, $env:TMP)) {
    if (-not (Test-PureAscii $p)) { Die "non-ASCII path in the Vivado chain: '$p' (Tcl GBK decoding would break)" }
}
New-Item -ItemType Directory -Force -Path $AsciiTmp | Out-Null
$env:TEMP = $AsciiTmp
$env:TMP  = $AsciiTmp

#------------------------------------------------------ serialisation guard
$busy = @(Get-Process -Name 'vivado', 'xsim', 'xvlog', 'xelab', 'xsimk' -ErrorAction SilentlyContinue)
if ($busy.Count -gt 0) {
    $names = ($busy | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', '
    Die "SERIAL_BUSY: xsim/vivado is machine-wide serial, another run is alive: $names"
}

#-------------------------------------------------------------- path check
$need = @($Xvlog, $Xelab, $Xsim, $TbMatrix, $TbMem2, $NegRtl, $RtlB1, $AsciiTmp) + $RtlCommon
$missing = @()
foreach ($f in $need) { if (-not (Test-Path -LiteralPath $f)) { $missing = $missing + $f } }
if ($missing.Count -gt 0) { Die ("missing input(s): " + ($missing -join '; ')) }

Say "=== prj13 P1-5 B1 regression suite ==="
Say "scenario : $Scenario  (cases=$($Cases.Count))"
Say "xsim     : $Xsim"
Say "workroot : $OutRoot"
Say "TEMP/TMP : $($env:TEMP)"

#---------------------------------------------------------------- fingerprints
Say ""
Say "=== source fingerprint (read-only inputs) ==="
$fpFiles = @($RtlCommon) + @($RtlB1, $NegRtl, $TbMatrix, $TbMem2)
$fpLines = @()
foreach ($f in $fpFiles) {
    $h = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    $line = ("  SRC {0,-24} sha256={1}" -f (Split-Path -Leaf $f), $h)
    Say $line
    $fpLines = $fpLines + $line
}

#--------------------------------------------------------------- dry-run exit
if ($dry) {
    Say ""
    Say "=== DRY-RUN: exact commands (nothing executed) ==="
    foreach ($c in $Cases) {
        $tb = $TbMatrix
        $snap = 'tb_sim'
        if ($c.Tb -eq 'mem2') { $tb = $TbMem2; $snap = 'tb_sim2' }
        $srcMid = $RtlB1
        $defArg = '-d B1_PATCHED'
        if ($c.Variant -eq 'neg') { $srcMid = $NegRtl; $defArg = '(no B1_PATCHED)' }
        Say ("[{0}.{1}]" -f $c.Name, $c.Variant)
        Say ("  xvlog  {0} --work work <3 common rtl> {1} {2}" -f $defArg, (Split-Path -Leaf $srcMid), (Split-Path -Leaf $tb))
        Say ("  xelab  --debug typical --relax -L work work.{0} -s {1}" -f [System.IO.Path]::GetFileNameWithoutExtension($tb), $snap)
        Say ("  xsim   -f xsim_args.f   (option file, one token per line; xsim.bat mangles '=' on the raw command line)")
        Say ("           {0} -runall -testplusarg PRE={1} -testplusarg FLAPS={2} -testplusarg POST={3} -testplusarg BOTH={4}" -f $snap, $c.Pre, $c.Flaps, $c.Post, $c.Both)
        Say ("           -> expect {0}" -f $c.Expect)
    }
    Say ""
    Say ("REGRESS: DRYRUN_OK cases={0} (ready to run, nothing executed)" -f $Cases.Count)
    Say "NEXT: ask the Lead for the xsim window, then run without -DryRun."
    exit 0
}

#------------------------------------------------------------------- one run
$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$runDir = Join-Path $OutRoot ("regress_run_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
Say ""
Say "run dir  : $runDir"

$rows = @()
$fails = 0
$passes = 0

foreach ($c in $Cases) {
    $caseName = "{0}.{1}" -f $c.Name, $c.Variant
    $caseDir = Join-Path $runDir $caseName
    $workDir = Join-Path $caseDir 'work'
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    $tb = $TbMatrix
    $snap = 'tb_sim'
    if ($c.Tb -eq 'mem2') { $tb = $TbMem2; $snap = 'tb_sim2' }
    $mid = $RtlB1
    if ($c.Variant -eq 'neg') { $mid = $NegRtl }

    $logXvlog = Join-Path $caseDir 'xvlog.log'
    $logXelab = Join-Path $caseDir 'xelab.log'
    $logXsim  = Join-Path $caseDir 'xsim.log'
    $logCmd   = Join-Path $caseDir 'cmd.txt'

    # pit #48: never reuse a stale xsim.dir
    $xsimDir = Join-Path $workDir 'xsim.dir'
    if (Test-Path -LiteralPath $xsimDir) { Remove-Item -LiteralPath $xsimDir -Recurse -Force }

    $xvlogArgs = @('--work', 'work')
    if ($c.Variant -eq 'pos') { $xvlogArgs += @('-d', 'B1_PATCHED') }
    $xvlogArgs += $RtlCommon
    $xvlogArgs += @($mid, $tb)

    $elabArgs = @('--debug', 'typical', '--relax', '-L', 'work', ("work." + [System.IO.Path]::GetFileNameWithoutExtension($tb)), '-s', $snap)

    $simArgs = @($snap, '-runall',
                 '-testplusarg', ("PRE="   + $c.Pre),
                 '-testplusarg', ("FLAPS=" + $c.Flaps),
                 '-testplusarg', ("POST="  + $c.Post),
                 '-testplusarg', ("BOTH="  + $c.Both))

    $cmdText = @(
        ("# case      : " + $caseName),
        ("# expect    : " + $c.Expect + "  (" + $c.Why + ")"),
        ("# variant   : " + $c.Variant),
        ("# workdir   : " + $workDir),
        ("xvlog " + ($xvlogArgs -join ' ')),
        ("xelab " + ($elabArgs -join ' ')),
        ("# xsim is invoked through an option file (xsim.bat mangles '=' on the command line)")
        ("xsim -f xsim_args.f   # file contents:")
        ($simArgs | ForEach-Object { "  " + $_ })
    ) -join "`r`n"
    Set-Content -LiteralPath $logCmd -Value $cmdText -Encoding ascii

    Say ""
    Say "---------------------------------------------------------------"
    Say "[$caseName] expect=$($c.Expect)  ($($c.Why))"

    Push-Location $workDir
    $stage = 'xvlog'
    $harnessErr = ''
    try {
        & $Xvlog @xvlogArgs 2>&1 | Out-File -FilePath $logXvlog -Encoding utf8
        if ($LASTEXITCODE -ne 0) {
            $harnessErr = "xvlog failed (exit $LASTEXITCODE), see $logXvlog"
        } else {
            $stage = 'xelab'
            & $Xelab @elabArgs 2>&1 | Out-File -FilePath $logXelab -Encoding utf8
            if ($LASTEXITCODE -ne 0) {
                $harnessErr = "xelab failed (exit $LASTEXITCODE), see $logXelab"
            } else {
                $stage = 'xsim'
                # MEASURED PITFALL (2026-11-08): xsim.bat mangles an argument that
                # contains '=' -- `xsim ... -testplusarg PRE=3` fails with
                # "Expected a switch but found 3" (the wrapper re-splits on '=').
                # Quoting for cmd, a leading '+', and '--testplusarg' all fail the
                # same way. The supported route is the option file: `xsim -f <file>`,
                # one token per line, where '=' survives untouched.
                $argsFile = Join-Path $workDir 'xsim_args.f'
                Set-Content -LiteralPath $argsFile -Value ($simArgs -join "`r`n") -Encoding ascii
                & $Xsim -f $argsFile 2>&1 | Out-File -FilePath $logXsim -Encoding utf8
                # a FAIL verdict legitimately exits non-zero ($fatal), so the exit
                # code alone is not a harness error -- the RESULT line is the judge
            }
        }
    } finally {
        Pop-Location
    }

    $observed = 'ERROR'
    $assertPass = 0
    $assertFail = 0
    $paramsLine = ''
    if ((Test-Path -LiteralPath $logXsim) -and ($harnessErr -eq '')) {
        $lines = @(Get-Content -LiteralPath $logXsim)
        $resLines = @($lines | Where-Object { $_ -match '^RESULT:' })
        $assertPass = @($lines | Where-Object { $_ -match '^\[ASSERT-PASS\]' }).Count
        $assertFail = @($lines | Where-Object { $_ -match '^\[ASSERT-FAIL\]' }).Count
        $paramsLine = (($lines | Where-Object { $_ -match 'TB_PARAMS:' } | Select-Object -First 1) -as [string])
        if ($resLines.Count -gt 0) {
            if ($resLines[0] -match 'RESULT: PASS') { $observed = 'PASS' } else { $observed = 'FAIL' }
        }
        # a PASS with failed asserts, or a FAIL without any, is a parsing/harness bug
        if (($observed -eq 'PASS') -and ($assertFail -gt 0)) { $observed = 'ERROR' }
        if (($observed -eq 'FAIL') -and ($assertFail -eq 0)) { $observed = 'ERROR' }
    }
    if ($harnessErr -ne '') { $observed = 'ERROR' }

    # plusargs must have arrived; a dropped -testplusarg must never pass silently
    $paramOk = $true
    $expectParams = "PRE=$($c.Pre) FLAPS=$($c.Flaps) POST=$($c.Post) BOTH=$($c.Both)"
    if ($observed -ne 'ERROR') {
        if ($paramsLine -notmatch [regex]::Escape($expectParams)) {
            $paramOk = $false
            Say "  PARAM MISMATCH: wanted '$expectParams' got '$paramsLine'"
            $observed = 'ERROR'
        }
    }

    $ok = ($observed -eq $c.Expect)
    if ($ok) { $passes = $passes + 1 } else { $fails = $fails + 1 }
    $mark = 'FAIL'
    if ($ok) { $mark = 'OK' }

    Say ("  observed={0} assert_pass={1} assert_fail={2} -> {3}" -f $observed, $assertPass, $assertFail, $mark)
    if ($harnessErr -ne '') { Say ("  harness: " + $harnessErr) }
    Say ("  log: " + $logXsim)

    $rows = $rows + [pscustomobject]@{
        Case      = $caseName
        Scenario  = $c.Name
        Variant   = $c.Variant
        Tb        = $c.Tb
        Pre       = $c.Pre
        Flaps     = $c.Flaps
        Post      = $c.Post
        Both      = $c.Both
        Expect    = $c.Expect
        Observed  = $observed
        Result    = $mark
        AssertPass = $assertPass
        AssertFail = $assertFail
        Harness   = $harnessErr
        Log       = $logXsim
        Cmd       = $logCmd
    }

    if (-not $KeepWork) {
        if ($ok) {
            if (Test-Path -LiteralPath $xsimDir) { Remove-Item -LiteralPath $xsimDir -Recurse -Force }
        } else {
            Say "  work dir kept for diagnosis: $workDir"
        }
    }
}

#------------------------------------------------------------------- summary
Say ""
Say "========================== SUMMARY =========================="
foreach ($r in $rows) {
    Say ("CASE {0,-12} expect={1} observed={2} {3}  ({4}/{5})" -f $r.Case, $r.Expect, $r.Observed, $r.Result, $r.AssertPass, $r.AssertFail)
}
Say ("REGRESS: PASS={0} FAIL={1}" -f $passes, $fails)

$resFile = Join-Path $runDir 'REGRESS_RESULT.txt'
$resText = @()
$resText += ("REGRESS_TIME       " + $ts)
$resText += ("REGRESS_SCENARIO   " + $Scenario)
$resText += ("REGRESS_PASS       " + $passes)
$resText += ("REGRESS_FAIL       " + $fails)
foreach ($r in $rows) {
    $resText += ("CASE {0,-12} expect={1,-4} observed={2,-5} assert_pass={3} assert_fail={4}" -f $r.Case, $r.Expect, $r.Observed, $r.AssertPass, $r.AssertFail)
}
$resText += $fpLines
Set-Content -LiteralPath $resFile -Value ($resText -join "`r`n") -Encoding ascii

$rows | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $runDir 'summary.json') -Encoding utf8

Say ("result file: " + $resFile)
if ($fails -eq 0) {
    Say "REGRESS_RESULT: ALL_EXPECTED"
    exit 0
}
Say "REGRESS_RESULT: MISMATCH (at least one case did not produce its expected verdict)"
Say "NOTE: expected-verdict mismatches are findings, not necessarily script bugs --"
Say "      check the per-case log before changing either the RTL or the table."
exit 1
