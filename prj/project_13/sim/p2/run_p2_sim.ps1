# =============================================================================
# run_p2_sim.ps1 -- prj13 P2 (v0.2 contract) one-click xsim runner
# -----------------------------------------------------------------------------
# What it does:
#   1. checks that no other Vivado/xsim process is running (Vivado is globally
#      serial on this machine -> refuse instead of fighting for it)
#   2. deletes sim\p2\xsim.dir  (PITFALL #48: an interrupted xvlog corrupts the
#      shared work library)
#   3. xvlog -> xelab -> xsim, all output redirected to log files (never pipe
#      straight from the tool)
#   4. greps the "P2_TB: PASS=<n> FAIL=<m>" line and prints a summary
#   5. exit code 0 only when FAIL=0 and the line was found
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_p2_sim.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_p2_sim.ps1 -Clean
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_p2_sim.ps1 -VivadoBin D:\Xilinx\Vivado\2023.1\bin
#
# Notes:
#   - pure ASCII on purpose (Vivado/Tcl is GBK-sensitive; keep paths ASCII)
#   - PowerShell 5.1 compatible (no ??, no -Encoding utf8BOM, no ternary)
#   - NO synthesis / NO implementation / NO project is created: this only drives
#     the standalone simulator (xvlog/xelab/xsim), which is what the P2 unit
#     acceptance needs.
# =============================================================================
[CmdletBinding()]
param(
    [string] $VivadoBin = 'D:\Xilinx\Vivado\2023.1\bin',
    [switch] $Clean,
    [switch] $AllowConcurrent,
    [string] $TempDir  = 'D:\FPGA\.tmp'
)

$ErrorActionPreference = 'Continue'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

$rtlDir  = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptDir)) 'rtl\p2'
$tbFile  = Join-Path $scriptDir 'tb_p2_pipeline.v'
$logFile = Join-Path $scriptDir 'run_p2_sim.log'
$xvlogLog= Join-Path $scriptDir 'xvlog_console.txt'
$xelabLog= Join-Path $scriptDir 'xelab_console.txt'
$xsimLog = Join-Path $scriptDir 'xsim_console.txt'
$snap    = 'p2_sim'

function Write-Head([string] $msg) {
    Write-Host ''
    Write-Host ('=== ' + $msg + ' ===')
}

function Fail([string] $msg, [int] $code) {
    Write-Host ('[FAIL] ' + $msg)
    exit $code
}

Write-Head 'prj13 P2 xsim runner'
Write-Host ('script dir : ' + $scriptDir)
Write-Host ('vivado bin : ' + $VivadoBin)
Write-Host ('rtl dir    : ' + $rtlDir)

# ---- 0. tools -----------------------------------------------------------
foreach ($tool in @('xvlog.bat', 'xelab.bat', 'xsim.bat')) {
    $p = Join-Path $VivadoBin $tool
    if (-not (Test-Path $p)) { Fail ('missing simulator tool: ' + $p) 2 }
}

# ---- 0b. ASCII guard on every path we hand to Vivado --------------------
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

# ---- 2. clean -----------------------------------------------------------
# always drop xsim.dir (PITFALL #48); -Clean also removes every log/leftover
if (Test-Path 'xsim.dir') { Remove-Item -Recurse -Force 'xsim.dir' }
foreach ($f in @('xvlog_console.txt', 'xelab_console.txt', 'xsim_console.txt')) {
    if (Test-Path $f) { Remove-Item -Force $f }
}
if ($Clean) {
    foreach ($f in @('run_p2_sim.log', 'webtalk.log', 'xsim_webtalk.log', '.Xil')) {
        if (Test-Path $f) { Remove-Item -Force -Recurse $f }
    }
}

# ---- 3. sources ---------------------------------------------------------
$sources = @()
$sources += (Join-Path $rtlDir 'ipv4_packet_extract.v')
$sources += (Join-Path $rtlDir 'eth_rewrap.v')
$sources += (Join-Path $rtlDir 'local_steer.v')
$sources += $tbFile
foreach ($s in $sources) {
    if (-not (Test-Path $s)) { Fail ('missing source: ' + $s) 5 }
    Write-Host ('  src: ' + $s)
}

'' | Out-File -FilePath $logFile -Encoding ascii
('run_p2_sim.ps1  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) | Out-File -FilePath $logFile -Append -Encoding ascii
('vivado bin: ' + $VivadoBin) | Out-File -FilePath $logFile -Append -Encoding ascii

# ---- 4. xvlog -----------------------------------------------------------
Write-Head 'xvlog'
& (Join-Path $VivadoBin 'xvlog.bat') $sources *> $xvlogLog
$rc = $LASTEXITCODE
Write-Host ('xvlog exit = ' + $rc)
Get-Content $xvlogLog | Out-File -FilePath $logFile -Append -Encoding ascii
if ($rc -ne 0) {
    Write-Host '--- xvlog errors ---'
    Select-String -Path $xvlogLog -Pattern 'ERROR' | ForEach-Object { Write-Host $_.Line }
    Fail 'xvlog failed' 10
}

# ---- 5. xelab -----------------------------------------------------------
Write-Head 'xelab'
& (Join-Path $VivadoBin 'xelab.bat') '-debug' 'typical' 'tb_p2_pipeline' '-s' $snap *> $xelabLog
$rc = $LASTEXITCODE
Write-Host ('xelab exit = ' + $rc)
Get-Content $xelabLog | Out-File -FilePath $logFile -Append -Encoding ascii
if ($rc -ne 0) {
    Write-Host '--- xelab errors ---'
    Select-String -Path $xelabLog -Pattern 'ERROR' | ForEach-Object { Write-Host $_.Line }
    Fail 'xelab failed' 11
}
$w = Select-String -Path $xelabLog -Pattern 'not connected|remains unconnected'
if ($w) {
    Write-Host '--- WARNING: unconnected ports (must be empty) ---'
    $w | ForEach-Object { Write-Host $_.Line }
    Fail 'elaboration reports unconnected ports' 12
}

# ---- 6. xsim ------------------------------------------------------------
Write-Head 'xsim'
& (Join-Path $VivadoBin 'xsim.bat') $snap '-runall' *> $xsimLog
$rc = $LASTEXITCODE
Write-Host ('xsim exit = ' + $rc)
Get-Content $xsimLog | Out-File -FilePath $logFile -Append -Encoding ascii

# ---- 7. verdict ---------------------------------------------------------
Write-Head 'results'
$passLines = Select-String -Path $xsimLog -Pattern '^\[PASS\]' 
$failLines = Select-String -Path $xsimLog -Pattern '^\[FAIL\]'
$detLines  = Select-String -Path $xsimLog -Pattern '^\s+\[DET\]'
if ($passLines) { $passLines | ForEach-Object { Write-Host $_.Line } }
if ($failLines) { $failLines | ForEach-Object { Write-Host $_.Line } }
if ($detLines)  { $detLines  | ForEach-Object { Write-Host $_.Line } }

$verdict = Select-String -Path $xsimLog -Pattern 'P2_TB: PASS='
if (-not $verdict) {
    Fail 'no "P2_TB: PASS=" line in xsim log -> simulation did not complete' 20
}
$vline = ($verdict | Select-Object -Last 1).Line.Trim()
Write-Host ''
Write-Host $vline

# parse PASS=<n> FAIL=<m>
$nPass = -1
$nFail = -1
$m = [regex]::Match($vline, 'PASS=(\d+)\s+FAIL=(\d+)')
if ($m.Success) {
    $nPass = [int] $m.Groups[1].Value
    $nFail = [int] $m.Groups[2].Value
} else {
    Fail ('cannot parse verdict line: ' + $vline) 21
}

Write-Host ''
Write-Host ('cases run : ' + ($nPass + $nFail))
Write-Host ('pass      : ' + $nPass)
Write-Host ('fail      : ' + $nFail)
Write-Host ('logs      : ' + $logFile)
Write-Host ('            ' + $xsimLog)

if ($rc -ne 0) { Fail ('xsim exited with code ' + $rc) 22 }
if ($nFail -ne 0) { Fail 'P2_TB reported FAIL' 1 }
if ($nPass -lt 21) { Fail ('expected at least 21 cases, got ' + $nPass) 23 }

Write-Host ''
Write-Host ('P2_SIM: PASS (PASS=' + $nPass + ' FAIL=' + $nFail + ')')
exit 0
