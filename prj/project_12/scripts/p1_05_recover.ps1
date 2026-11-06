# =============================================================================
# p1_05_recover.ps1 -- prj12 P1-05「断电恢复」后的一键恢复+判据（单板）
#
# 背景：位流是 JTAG 配置 SRAM，断电即失；ELF 与串口 `d` 也随断电丢失。
#       所以「断电 → 上电」之后必须：重烧 BitElf → 串口 `d` → 再判链路。
#
# 用法（PC1 板 A）:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\p1_05_recover.ps1 -Board A -Com COM6 -Cable 210512180081
#   ... -SkipBurn      # 只发 d + 抓 ILA（已经烧过位流时）
#   ... -WaitSeconds 30  # 烧完后等待再抓（默认 30）
#
# 判据输出（打印）：
#   [P1-05] burn=BURN_OK  d=DMAMODE_DMA  ch_up=? link_ok=? lane_up=? pll=? rst=?
#   [P1-05] counters: ch_up_evt=? hard_err_cnt=? soft_err_cnt=? pk_frames=? up_frames=? pfwd_wr=? prev_wr=?
#   P1_05_RESULT: PASS/FAIL
# 退出码：0 = 链路恢复且无错；1 = 失败
# =============================================================================
param(
    [ValidateSet('A','B')][string]$Board = 'A',
    [string]$Com = 'COM6',
    [string]$Cable = '210512180081',
    [int]$WaitSeconds = 30,
    [switch]$SkipBurn,
    [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
function Say([string]$s) { Write-Output $s }
function Finish([int]$c, [string]$s) { Say $s; exit $c }

$Root = Split-Path -Parent $PSScriptRoot
if ($OutDir -eq '') { $OutDir = Join-Path $Root 'out' }
$stamp = Get-Date -Format 'HHmmss'
$fail = $false

# ---- 1) 重烧 BitElf ---------------------------------------------------------
$burn = 'SKIPPED'
if (-not $SkipBurn) {
    $r = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'out\twin_burn.ps1') -Board $Board -Mode BitElf -Run 2>&1
    $txt = ($r | Out-String)
    if ($txt -match 'TWIN_BURN_RESULT:\s*PASS') { $burn = 'BURN_OK' } else { $burn = 'BURN_FAIL'; $fail = $true }
    Say "[P1-05] burn=$burn"
    if ($fail) { Say (($r | Select-Object -Last 12) -join "`n"); Finish 1 "P1_05_RESULT: FAIL (burn)" }
}

# ---- 2) 串口 d --------------------------------------------------------------
$d = 'FAIL'
$dr = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'scripts\serial_dma_mode.ps1') -Com $Com 2>&1
if ((($dr | Out-String)) -match 'SERIAL_RESULT:\s*PASS') { $d = 'DMAMODE_DMA' } else { $fail = $true }
Say "[P1-05] d=$d"

# ---- 3) 等链路起来 + 抓 ILA6 ------------------------------------------------
Start-Sleep -Seconds $WaitSeconds

$env:TEMP = 'D:\FPGA\.tmp'; $env:TMP = 'D:\FPGA\.tmp'
$csv = Join-Path $OutDir ("ila6_$Board`_p105_$stamp.csv")
$log = Join-Path $OutDir ("ila6_$Board`_p105_$stamp.console.log")
$tcl = Join-Path $Root 'scripts\ila_capture.tcl'
$vivado = 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat'
if (-not (Test-Path $vivado)) { $vivado = 'vivado' }
& $vivado -mode batch -source $tcl -tclargs localhost:3121 $Cable $csv *> $log
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $csv)) { Finish 1 "P1_05_RESULT: FAIL (ila capture; see $log)" }

$row = (Get-Content $csv -TotalCount 3 | Select-Object -Last 1)
$hdr = (Get-Content $csv -TotalCount 1)
Say "[P1-05] csv=$csv"
Say "[P1-05] $hdr"
Say "[P1-05] $row"

# 解析已知列序：Sample,SampleWindow,TRIGGER,link_ok,ch_up,lane_up,pll,hard,soft,evt,hcnt,scnt,pk,up,pfwd,prev,rst
$v = $row.Split(',')
if ($v.Count -lt 17) { Finish 1 "P1_05_RESULT: FAIL (unexpected csv shape)" }
$link = $v[3]; $chup = $v[4]; $lane = $v[5]; $pll = $v[6]
$hard = $v[7]; $soft = $v[8]; $evt = $v[9]; $hcnt = $v[10]; $scnt = $v[11]
$pk = $v[12]; $up = $v[13]; $pfwd = $v[14]; $prev = $v[15]; $rst = $v[16]

$ok = ($chup -eq '1') -and ($link -eq '1') -and ($lane -eq '1') -and ($pll -eq '1') -and
      ($hard -eq '0') -and ($soft -eq '0') -and ($rst -eq '0')
Say "[P1-05] counters: ch_up_evt=$evt hard_err_cnt=$hcnt soft_err_cnt=$scnt pk_frames=$pk up_frames=$up pfwd_wr=$pfwd prev_wr=$prev"
if (-not $ok) { $fail = $true }

if ($fail) { Finish 1 "P1_05_RESULT: FAIL" }
Finish 0 "P1_05_RESULT: PASS (ch_up=1, link_ok=1, lane_up=1, pll=1, rst=0, hard/soft=0)"
