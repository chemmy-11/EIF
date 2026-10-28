# =============================================================================
# twin_burn.ps1 -- prj12 双板烧录（A/B 单板或两块一起）
# 设计要点:
#   1. **默认 dry-run**（不加 -Run 只打印计划与校验结果）——板卡不在场也能验参数/路径/哈希；
#   2. 两种通道:
#        -Mode Bit     : Vivado hw_manager，按 JTAG 线缆序列号选 target（P1 首选，最稳）
#        -Mode BitElf  : xsct，位流 + MicroBlaze ELF 成对（需要软核控制台时才用）
#   3. 占位符（<FILL> / 空）在 dry-run 里只告警；在 -Run 里是硬错误（禁止"猜一块板烧"）。
#   4. 位流/ELF 的 SHA256 与 out/twin_config.json 记录比对，不一致拒绝烧（-Force 可跳过）。
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File out\twin_burn.ps1                 # dry-run
#   powershell -NoProfile -ExecutionPolicy Bypass -File out\twin_burn.ps1 -Board A -Run    # 烧 A
#   ... -Board Both -Mode BitElf -Run
# 退出码: 0 = 全部通过（dry-run 也要求参数自洽）；1 = 有板/有校验失败
# =============================================================================
param(
    [ValidateSet('A','B','Both')][string]$Board = 'Both',
    [string]$Config = 'D:\FPGA\prj\project_12\out\twin_config.json',
    [ValidateSet('Bit','BitElf')][string]$Mode = 'Bit',
    [string]$HwServer = '',
    [string]$Cable = '',
    [switch]$ListTargets,
    [switch]$Run,
    [switch]$Force,
    [string]$Root = 'D:\FPGA\prj\project_12'
)
$ErrorActionPreference = 'Stop'
$dry = -not $Run
$fail = $false

function Say([string]$s) { Write-Output $s }
function IsPlaceholder([string]$v) { return ($null -eq $v) -or ($v -eq '') -or ($v -match '^<.*>$') }
function Log-Fail([string]$s) { Write-Output "FAIL: $s"; $script:fail = $true }
function Log-Warn([string]$s) { Write-Output "WARN: $s" }

function Get-Sha256([string]$path) { return (Get-FileHash -Algorithm SHA256 -Path $path).Hash.ToLower() }

if (-not (Test-Path $Config)) { throw "config not found: $Config" }
$cfg = Get-Content -Path $Config -Raw -Encoding UTF8 | ConvertFrom-Json

$bit = Join-Path $Root $cfg.artifacts.bit
$elf = Join-Path $Root $cfg.artifacts.elf
$expectBit = [string]$cfg.artifacts.expect_bit_sha256
$expectElf = [string]$cfg.artifacts.expect_elf_sha256

# -ListTargets：只读列出 hw_server 下的 target/device（不编程），用于上板第一分钟认板
if ($ListTargets) {
    $url = if ($HwServer -ne '') { $HwServer } else { [string]$cfg.boards.A.hw_server }
    $tcl = Join-Path $Root 'scripts\list_targets.tcl'
    Say "=== twin_burn [LIST-TARGETS] hw_server=$url （只读，不编程）==="
    if (-not (Test-Path $tcl)) { throw "list_targets.tcl not found: $tcl" }
    $env:TEMP = 'D:\FPGA\.tmp'; $env:TMP = 'D:\FPGA\.tmp'
    Set-Location 'D:\FPGA'
    $console = Join-Path $Root 'out\list_targets.console.log'
    $p = Start-Process -FilePath 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat' `
            -ArgumentList @('-mode','batch','-source',$tcl,'-tclargs',$url) `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $console -RedirectStandardError "$console.err"
    Say "exit=$($p.ExitCode)"
    Say "log=$console"
    Get-Content $console -ErrorAction SilentlyContinue |
        Select-String -Pattern 'LIST_|TARGET|DEVICE' | ForEach-Object { Say $_.Line }
    if ($p.ExitCode -ne 0) { Say "TWIN_BURN_RESULT: FAIL（见 $console）"; exit 1 }
    Say "TWIN_BURN_RESULT: LIST_OK（确认两条线缆都在，再回填 cable_serial）"
    exit 0
}


Say "=== twin_burn $(if ($dry) { '[DRY-RUN]' } else { '[RUN]' }) mode=$Mode board=$Board ==="
Say "config : $Config"
Say "bit    : $bit"
Say "elf    : $elf"

# ---- 位流存在性 + SHA ----
if (-not (Test-Path $bit)) {
    Log-Fail "bitstream missing: $bit (先跑 scripts\build_impl.tcl 出流)"
} else {
    $shaBit = Get-Sha256 $bit
    Say "bit sha: $shaBit"
    if (IsPlaceholder $expectBit) {
        Log-Warn "config.expect_bit_sha256 未填（构建完成后回填，否则无法防错板）"
    } elseif ($shaBit -ne $expectBit.ToLower()) {
        if ($Force) { Log-Warn "bit sha mismatch (expect=$expectBit) -- 继续（-Force）" }
        else { Log-Fail "bit sha mismatch: expect=$expectBit actual=$shaBit" }
    } else { Say "bit sha: MATCH expect" }
}

# ---- ELF（只有 BitElf 模式需要）----
if ($Mode -eq 'BitElf') {
    if (-not (Test-Path $elf)) {
        Log-Fail "ELF missing: $elf"
    } else {
        $shaElf = Get-Sha256 $elf
        Say "elf sha: $shaElf"
        if ((IsPlaceholder $expectElf) -or $shaElf -eq $expectElf.ToLower()) { Say "elf sha: MATCH/informational" }
        else { Log-Fail "elf sha mismatch: expect=$expectElf actual=$shaElf" }
    }
}

# ---- 逐板计划 ----
$targets = if ($Board -eq 'Both') { @('A','B') } else { @($Board) }
foreach ($b in $targets) {
    $bd = $cfg.boards.$b
    if ($null -eq $bd) { Log-Fail "board $b not in config"; continue }
    $url   = if ($HwServer -ne '') { $HwServer } else { [string]$bd.hw_server }
    $cbl   = if ($Cable -ne '')    { $Cable }    else { [string]$bd.cable_serial }
    Say ""
    Say "--- board $b ($($bd.role)) ---"
    Say "  hw_server : $url"
    Say "  jtag_serial: $($bd.jtag_serial)"
    Say "  cable     : $cbl"
    Say "  com       : $($bd.com) @ $($bd.baud)"
    Say "  board ip  : $($bd.board_ip)  mac=$($bd.board_mac)  <-> pc $($bd.pc_ip) [$($bd.pc_nic)]"
    # dry-run 阶段允许占位符（板卡未归位），只告警；真正 -Run 时是硬错误
    if (IsPlaceholder $url) {
        if ($dry) { Log-Warn "board ${b}: hw_server 未配置（dry-run 允许，-Run 前必须填）" }
        else      { Log-Fail "board ${b}: hw_server 未配置" }
    }
    if (IsPlaceholder $cbl) {
        if ($dry) { Log-Warn "board ${b}: cable_serial 未配置（dry-run 允许；两板同 hw_server 时 -Run 必须给）" }
        else      { Log-Fail "board ${b}: cable_serial 未配置（两板同 hw_server 时必须给）" }
    }

    if ($Mode -eq 'Bit') {
        $tcl = Join-Path $Root 'scripts\burn_bit_vivado.tcl'
        $args = @('-mode','batch','-source',$tcl,'-tclargs',$url,$bit,$cbl)
        Say "  CMD: vivado.bat $($args -join ' ')"
    } else {
        $tcl = Join-Path $Root 'scripts\burn_one.tcl'
        $args = @($tcl,$url,$bit,$elf,$cbl)
        Say "  CMD: xsct.bat $($args -join ' ')"
    }

    if (-not $dry -and -not $script:fail) {
        $logDir = Join-Path $Root 'out'
        $tag = "burn_$b"
        $console = Join-Path $logDir "$tag.console.log"
        $env:TEMP = 'D:\FPGA\.tmp'; $env:TMP = 'D:\FPGA\.tmp'
        Set-Location 'D:\FPGA'
        if ($Mode -eq 'Bit') {
            $exe = 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat'
        } else {
            $exe = 'D:\Xilinx\Vitis\2023.1\bin\xsct.bat'
        }
        Say "  RUN: $exe"
        $p = Start-Process -FilePath $exe -ArgumentList $args -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $console -RedirectStandardError "$console.err"
        Say "  exit=$($p.ExitCode) log=$console"
        $text = Get-Content $console -Raw -ErrorAction SilentlyContinue
        $mark = if ($Mode -eq 'Bit') { 'BURN_BIT_OK' } else { 'BURN_OK' }
        if (($p.ExitCode -ne 0) -or ($text -notmatch $mark)) {
            Log-Fail ("board ${b} marker ${mark} missing (judge by marker line only, not by absence of ERROR)")
        } else { Say "  board ${b}: $mark" }
    }
}

Say ""
if ($fail) { Say "TWIN_BURN_RESULT: FAIL"; exit 1 }
if ($dry) { Say "TWIN_BURN_RESULT: DRY_RUN_OK (未烧写)"; exit 0 }
Say "TWIN_BURN_RESULT: PASS"
exit 0
