# =============================================================================
# run_p2_sim.ps1 -- prj13 P2 one-click xsim runner (3 testbenches)
# -----------------------------------------------------------------------------
# Testbenches driven (each gets its own xvlog -> xelab -> xsim pass):
#   unit     tb_p2_pipeline   : 3 unit modules (extract/rewrap/steer), 23 cases
#   framebuf tb_p2_frame_buf  : p2_frame_buf whole-frame drop + per-frame sideband
#   relay    tb_p2_relay_top  : p2_relay_top integration (dual clock), I01..I09
#
# Behaviour:
#   1. refuses to run when any vivado/xsim/xvlog/xelab is already running
#      (Vivado is globally serial on this machine -> do not fight for it)
#   2. ASCII guard on every path handed to the tools (Vivado Tcl is GBK sensitive)
#   3. TEMP/TMP pinned to an ASCII scratch dir
#   4. per TB: delete xsim.dir (PITFALL #48), xvlog, xelab, xsim; all output
#      redirected to log files, never piped straight from the tool
#   5. parses each TB's verdict line, requires FAIL=0 and a minimum case count
#   6. prints one summary line:  P2_SIM: PASS (unit=<n> relay=<m> framebuf=<k>)
#      exit code 0 only when every TB passed
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_p2_sim.ps1
#   ... -Clean                  also remove historical logs / webtalk leftovers
#   ... -VivadoBin D:\Xilinx\Vivado\2023.1\bin
#   ... -Only unit|framebuf|relay    run a single testbench
#   ... -AllowConcurrent        skip the serial check (NOT recommended)
#
# Pure ASCII on purpose. PowerShell 5.1 compatible (no ??, no -Encoding utf8BOM).
# NO synthesis / NO implementation / NO project: simulator tools only.
# =============================================================================
[CmdletBinding()]
param(
    [string] $VivadoBin = 'D:\Xilinx\Vivado\2023.1\bin',
    [switch] $Clean,
    [switch] $AllowConcurrent,
    [string] $TempDir  = 'D:\FPGA\.tmp',
    [string] $Only     = ''
)

$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

$p2Root = Split-Path -Parent (Split-Path -Parent $scriptDir)
$rtlDir = Join-Path $p2Root 'rtl\p2'

function Write-Head([string] $msg) {
    Write-Host ''
    Write-Host ('=== ' + $msg + ' ===')
}

function Fail([string] $msg, [int] $code) {
    Write-Host ('[FAIL] ' + $msg)
    exit $code
}

# ---- testbench table ----------------------------------------------------
$rtl_unit = @('ipv4_packet_extract.v', 'eth_rewrap.v', 'local_steer.v')
$tb_unit  = @() ; foreach ($f in $rtl_unit) { $tb_unit += (Join-Path $rtlDir $f) }
$tb_unit += (Join-Path $scriptDir 'tb_p2_pipeline.v')

$tb_fbuf  = @((Join-Path $rtlDir 'p2_frame_buf.v'), (Join-Path $scriptDir 'tb_p2_frame_buf.v'))

$tb_relay = @()
foreach ($f in $rtl_unit) { $tb_relay += (Join-Path $rtlDir $f) }
$tb_relay += (Join-Path $rtlDir 'p2_frame_buf.v')
$tb_relay += (Join-Path $rtlDir 'p2_relay_top.v')
$tb_relay += (Join-Path $scriptDir 'tb_p2_relay_top.v')

$tbs = @(
    @{ key='unit';     top='tb_p2_pipeline';  snap='p2_sim_unit';
       srcs=$tb_unit;  verdict='P2_TB: PASS=';          min=23; label='unit' },
    @{ key='framebuf'; top='tb_p2_frame_buf'; snap='p2_sim_fbuf';
       srcs=$tb_fbuf;  verdict='P2_FRAMEBUF_TB: PASS='; min=5;  label='framebuf' },
    @{ key='relay';    top='tb_p2_relay_top'; snap='p2_sim_relay';
       srcs=$tb_relay; verdict='P2_RELAY_TB: PASS=';    min=9;  label='relay' }
)

Write-Head 'prj13 P2 xsim runner (unit + framebuf + relay)'
Write-Host ('script dir : ' + $scriptDir)
Write-Host ('vivado bin : ' + $VivadoBin)
Write-Host ('rtl dir    : ' + $rtlDir)
if ($Only -ne '') { Write-Host ('only       : ' + $Only) }

# ---- 0. tools -----------------------------------------------------------
foreach ($tool in @('xvlog.bat', 'xelab.bat', 'xsim.bat')) {
    $p = Join-Path $VivadoBin $tool
    if (-not (Test-Path $p)) { Fail ('missing simulator tool: ' + $p) 2 }
}

# ---- 0b. ASCII guard ----------------------------------------------------
foreach ($p in @($scriptDir, $rtlDir, $VivadoBin, $TempDir)) {
    if ($p -match '[^\x00-\x7F]') {
        Fail ('non-ASCII path would break Vivado Tcl/GBK decoding: ' + $p) 3
    }
}

# ---- 0c. Vivado is globally serial --------------------------------------
if (-not $AllowConcurrent) {
    $busy = @()
    foreach ($n in @('vivado', 'xsim', 'xvlog', 'xelab')) {
        $procs = Get-Process -Name $n -ErrorAction SilentlyContinue
        if ($procs) { foreach ($pr in $procs) { $busy += ($n + '(PID=' + $pr.Id + ')') } }
    }
    if ($busy.Count -gt 0) {
        Write-Host ('[BUSY] ' + ($busy -join ', '))
        Fail 'another Vivado/xsim process is running; wait and retry (or -AllowConcurrent)' 4
    }
    Write-Host 'serial check: no vivado/xsim/xvlog/xelab running'
}

# ---- 1. TEMP / TMP ------------------------------------------------------
if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }
$env:TEMP = $TempDir
$env:TMP  = $TempDir
Write-Host ('TEMP/TMP   : ' + $env:TEMP)

# ---- 2. global clean ----------------------------------------------------
if (Test-Path 'xsim.dir') { Remove-Item -Recurse -Force 'xsim.dir' }
if ($Clean) {
    Get-ChildItem $scriptDir -File | Where-Object {
        $_.Name -like '*.log' -or $_.Name -like '*console.txt' -or
        $_.Name -like 'webtalk*' -or $_.Name -like '*.jou' -or $_.Name -like '*.pb'
    } | ForEach-Object { Remove-Item -Force $_.FullName }
    if (Test-Path '.Xil') { Remove-Item -Recurse -Force '.Xil' }
}

# ---- 3. run each testbench ---------------------------------------------
$res = @{}
foreach ($tb in $tbs) {
    if (($Only -ne '') -and ($Only -ne $tb.key)) { continue }

    $key       = $tb.key
    $xvlogLog  = Join-Path $scriptDir ($key + '_xvlog_console.txt')
    $xelabLog  = Join-Path $scriptDir ($key + '_xelab_console.txt')
    $xsimLog   = Join-Path $scriptDir ($key + '_xsim_console.txt')

    Write-Head ($key + ' : ' + $tb.top)

    foreach ($s in $tb.srcs) {
        if (-not (Test-Path $s)) { Fail ('missing source: ' + $s) 5 }
    }

    if (Test-Path 'xsim.dir') { Remove-Item -Recurse -Force 'xsim.dir' }

    # -- xvlog --
    & (Join-Path $VivadoBin 'xvlog.bat') $tb.srcs *> $xvlogLog
    $rc = $LASTEXITCODE
    Write-Host ('  xvlog exit = ' + $rc)
    if ($rc -ne 0) {
        Select-String -Path $xvlogLog -Pattern 'ERROR' | ForEach-Object { Write-Host $_.Line }
        Fail ($key + ' xvlog failed') 10
    }

    # -- xelab --
    & (Join-Path $VivadoBin 'xelab.bat') '-debug' 'typical' $tb.top '-s' $tb.snap *> $xelabLog
    $rc = $LASTEXITCODE
    Write-Host ('  xelab exit = ' + $rc)
    if ($rc -ne 0) {
        Select-String -Path $xelabLog -Pattern 'ERROR' | ForEach-Object { Write-Host $_.Line }
        Fail ($key + ' xelab failed') 11
    }
    $w = Select-String -Path $xelabLog -Pattern 'not connected|remains unconnected'
    if ($w) {
        $w | ForEach-Object { Write-Host ('  ' + $_.Line) }
        Fail ($key + ': elaboration reports unconnected ports') 12
    }

    # -- xsim --
    & (Join-Path $VivadoBin 'xsim.bat') $tb.snap '-runall' *> $xsimLog
    $rc = $LASTEXITCODE
    Write-Host ('  xsim  exit = ' + $rc)
    if ($rc -ne 0) {
        Select-String -Path $xsimLog -Pattern 'ERROR' | Select-Object -First 10 |
            ForEach-Object { Write-Host ('  ' + $_.Line) }
        Fail ($key + ' xsim exited with code ' + $rc) 22
    }

    # -- verdict --
    $passLines = Select-String -Path $xsimLog -Pattern '^\[PASS\]'
    $failLines = Select-String -Path $xsimLog -Pattern '^\[FAIL\]'
    $detLines  = Select-String -Path $xsimLog -Pattern '^\s+\[DET\]'
    $infoLines = Select-String -Path $xsimLog -Pattern '^\s+\[INFO\]'
    if ($passLines) { $passLines | ForEach-Object { Write-Host $_.Line } }
    if ($failLines) { $failLines | ForEach-Object { Write-Host $_.Line } }
    if ($detLines)  { $detLines  | ForEach-Object { Write-Host $_.Line } }
    if ($infoLines) { $infoLines | ForEach-Object { Write-Host $_.Line } }

    $verdict = Select-String -Path $xsimLog -Pattern $tb.verdict
    if (-not $verdict) {
        Fail ($key + ': no "' + $tb.verdict + '" line in xsim log') 20
    }
    $vline = ($verdict | Select-Object -Last 1).Line.Trim()
    $m = [regex]::Match($vline, 'PASS=(\d+)\s+FAIL=(\d+)')
    if (-not $m.Success) { Fail ($key + ': cannot parse verdict line: ' + $vline) 21 }
    $nPass = [int] $m.Groups[1].Value
    $nFail = [int] $m.Groups[2].Value
    Write-Host ('  ' + $vline)
    if ($nFail -ne 0) { Fail ($key + ' reported FAIL=' + $nFail) 1 }
    if ($nPass -lt $tb.min) { Fail ($key + ': expected at least ' + $tb.min + ' cases, got ' + $nPass) 23 }
    $res[$tb.label] = $nPass
}

# ---- 4. RTL under test: self-certifying SHA256 --------------------------
# Pin "which RTL revision was actually simulated" into every run log, so a
# bitstream-candidate registration can copy the hashes straight from here.
# Trust content hashes only -- never mtime, never a path.
Write-Head 'RTL under test (SHA256)'
$rtlNames = @('ipv4_packet_extract.v', 'eth_rewrap.v', 'local_steer.v',
              'p2_frame_buf.v', 'p2_relay_top.v')
$sumLines = @()
foreach ($n in $rtlNames) {
    $p = Join-Path $rtlDir $n
    if (Test-Path $p) {
        $h = (Get-FileHash $p -Algorithm SHA256).Hash
        $sz = (Get-Item $p).Length
        Write-Host ('  ' + $n.PadRight(24) + $h + '  (' + $sz + ' B)')
        $sumLines += ($h + '  ' + $p)
    } else {
        Write-Host ('  ' + $n.PadRight(24) + 'MISSING')
    }
}
$sumLines | Out-File -FilePath (Join-Path $scriptDir 'RTL_SHA256.txt') -Encoding ascii
Write-Host ('  (written to ' + (Join-Path $scriptDir 'RTL_SHA256.txt') + ')')

# ---- 5. summary ---------------------------------------------------------
Write-Head 'summary'
$u = 0; if ($res.ContainsKey('unit'))     { $u = $res['unit'] }
$r = 0; if ($res.ContainsKey('relay'))    { $r = $res['relay'] }
$f = 0; if ($res.ContainsKey('framebuf')) { $f = $res['framebuf'] }

Write-Host ('unit     = ' + $u + ' cases  (tb_p2_pipeline: 3 unit modules + TB glue)')
Write-Host ('relay    = ' + $r + ' cases  (tb_p2_relay_top: p2_relay_top integration)')
Write-Host ('framebuf = ' + $f + ' cases  (tb_p2_frame_buf: whole-frame drop + sideband)')
Write-Host ('logs     : ' + $scriptDir)
Write-Host ''
Write-Host ('P2_SIM: PASS (unit=' + $u + ' relay=' + $r + ' framebuf=' + $f + ')')
exit 0
