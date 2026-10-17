# =============================================================================
# r2_dryrun.ps1 - prj11 R2 判据工具链的「dry-run 自证」一键复现脚本
#
# 作用: 不碰板卡(不烧写/不开串口/不发 ping/不跑 Vivado/不跑四档/10MB/J3)的前提下,
#       对 r2_* 工具链做完整自证, 并把全过程写入 out\r2_dryrun.log (UTF-8 BOM):
#         1) 本目录全部 r2_*.ps1: 前 3 字节 = EF BB BF + PS 5.1 ParseFile 0 语法错误
#         2) r2_counter_recon.py: py_compile 0 错
#         3) r2_counter_recon.py --mode selftest: 判据工具正/负对照 5/5 PASS
#         4) r2_counter_recon.py --check-tcl r2_ilacap.tcl: Tcl 结构完整性(引号/花括号/方括号闭合)
#         5) r2_board.ps1 DRY-RUN (带 R1 归档工件作只读 fixture): 真校验 SHA256/构建日志
#            WNS/WHS/DRC/串口枚举/邻居/NIC/工具齐备 + 打印 S0-S11 计划 + GUARD 计数全 0
#         6) r2_mb10_sha.ps1 DRY-RUN: 真校验 10MB 源文件大小/SHA256 + json_storm 源码参数
#            (CHUNK_MAX/--gap-ms 默认/判据标记) + Python + UDP 1234 端口状态
#         7) 只读纪律自证: R1 参考脚本/设计文档在自证前后 SHA256 不变(证明未改 prj11 现有文件)
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File r2_dryrun.ps1
#   (退出码 0 = 全部自证项 PASS; 非 0 = 有 FAIL 项, 看 R2_DRYRUN_STEP 行)
# 说明: 本脚本只在 PS 5.1 下执行(ParseFile 即 -File 的真实读法); 不调用任何板卡资源。
# =============================================================================
[CmdletBinding()]
param(
    [string]$OutRoot = "",
    [string]$LogPath = ""
)

$ErrorActionPreference = "Continue"
$script:OutRoot = $PSScriptRoot
if (-not $script:OutRoot) { $script:OutRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $LogPath) { $LogPath = Join-Path $script:OutRoot "r2_dryrun.log" }
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Log = New-Object System.Collections.ArrayList
$script:Fails = New-Object System.Collections.ArrayList
$script:Steps = New-Object System.Collections.ArrayList
$script:PyExe = "C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe"
if (-not (Test-Path $script:PyExe)) { $script:PyExe = "python" }
$script:Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

function Write-Line {
    param([string]$Text = "")
    if ($null -eq $Text) { $Text = "" }
    Write-Host $Text
    [void]$script:Log.Add($Text)
}
function Write-Section {
    param([string]$Title)
    Write-Line ("=" * 78)
    Write-Line ("== " + $Title)
    Write-Line ("=" * 78)
}
function Add-Step {
    param([string]$Name, [string]$Verdict, [string]$Detail = "")
    [void]$script:Steps.Add([pscustomobject]@{ Name = $Name; Verdict = $Verdict; Detail = $Detail })
    $tag = $Verdict
    if ($Verdict -eq "FAIL") { $tag = "FAIL"; [void]$script:Fails.Add($Name) }
    Write-Line ("[R2_DRYRUN_STEP] {0} {1} {2}" -f $Name, $tag, $Detail)
}
function Get-Sha256 { param([string]$Path) try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() } catch { return "" } }
function Get-BomHex {
    param([string]$Path)
    try {
        $b = [System.IO.File]::ReadAllBytes($Path)
        if ($b.Length -lt 3) { return "" }
        return ("{0:X2}{1:X2}{2:X2}" -f $b[0], $b[1], $b[2])
    } catch { return "" }
}

# =============================================================================
# 0. 头部 + 快照：R1 只读资产 hash（自证前后一致 = 未改 prj11 现有文件）
# =============================================================================
$r1Assets = [ordered]@{
    "retire_s0_s8.ps1"  = (Join-Path $script:OutRoot "retire_s0_s8.ps1")
    "j3_fourchains.ps1" = (Join-Path $script:OutRoot "j3_fourchains.ps1")
    "S0S8_DESIGN.md"    = (Join-Path $script:OutRoot "S0S8_DESIGN.md")
    "R2_S2MM_DESIGN.md" = (Join-Path $script:OutRoot "R2_S2MM_DESIGN.md")
    "uart_probe.py"     = (Join-Path $script:OutRoot "uart_probe.py")
    "manual_round.py"   = (Join-Path $script:OutRoot "manual_round.py")
    "jb31b_burn_pair.tcl" = (Join-Path $script:OutRoot "jb31b_burn_pair.tcl")
}
$before = @{}
foreach ($k in $r1Assets.Keys) {
    $p = $r1Assets[$k]
    if (Test-Path $p) { $before[$k] = Get-Sha256 $p } else { $before[$k] = "(missing)" }
}

Write-Section "R2 判据工具链 dry-run 自证（不碰板卡）"
Write-Line ("时间: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  Asia/Shanghai")
Write-Line ("工作目录: " + $script:OutRoot)
Write-Line ("Python: " + $script:PyExe)
Write-Line ("本自证日志: " + $LogPath)
Write-Line ("说明: 本脚本不烧板/不开串口/不发 ping/不跑 Vivado/不跑四档/10MB/J3；只做只读真校验与 dry-run。")
Write-Line ""

# =============================================================================
# 1. 全部 r2_*.ps1: BOM + PS 5.1 ParseFile
# =============================================================================
Write-Section "1) r2_*.ps1 BOM(EF BB BF) + PS 5.1 [Parser]::ParseFile 语法检查"
$ps1Files = @(Get-ChildItem -LiteralPath $script:OutRoot -Filter "r2_*.ps1" | Sort-Object Name)
if ($ps1Files.Count -eq 0) { Add-Step "ps1-check" "FAIL" "未找到 r2_*.ps1" }
$ps1Ok = $true
foreach ($f in $ps1Files) {
    $bom = Get-BomHex $f.FullName
    $bomOk = ($bom -eq "EFBBBF")
    $tok = $null; $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err)
    $errCount = $err.Count
    $ok = $bomOk -and ($errCount -eq 0)
    if (-not $ok) { $ps1Ok = $false }
    Write-Line ("  {0}  size={1}  BOM={2}  PARSE_ERRORS={3}" -f $f.Name, $f.Length, $bom, $errCount)
    if ($errCount -gt 0) {
        $err | Select-Object -First 8 | ForEach-Object { Write-Line ("     line " + $_.Extent.StartLineNumber + ": " + $_.Message) }
    }
}
if ($ps1Ok) { Add-Step "ps1-check" "PASS" ($ps1Files.Count.ToString() + " 个 .ps1: BOM+ParseFile 均 0 错") }
else { Add-Step "ps1-check" "FAIL" "见上表" }
Write-Line ""

# =============================================================================
# 2. py_compile
# =============================================================================
Write-Section "2) r2_counter_recon.py: py_compile（0 错）"
$reconPy = Join-Path $script:OutRoot "r2_counter_recon.py"
$pyOk = $false
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
if (Test-Path $reconPy) {
    $out = & $script:PyExe -m py_compile $reconPy 2>&1 | ForEach-Object { [string]$_ }
    $code = $LASTEXITCODE
    foreach ($l in $out) { Write-Line ("  " + $l) }
    $pyOk = ($code -eq 0)
    Write-Line ("  py_compile exit=" + $code)
} else {
    Write-Line ("  缺 " + $reconPy)
}
if ($pyOk) { Add-Step "py-compile" "PASS" "exit=0" } else { Add-Step "py-compile" "FAIL" "exit!=0" }
Write-Line ""

# =============================================================================
# 3. 判据工具正/负对照自检
# =============================================================================
Write-Section "3) r2_counter_recon.py --mode selftest（判据工具自身正/负对照, 坑 #43/#56）"
$selfOk = $false
if (Test-Path $reconPy) {
    $out = & $script:PyExe $reconPy --mode selftest 2>&1 | ForEach-Object { [string]$_ }
    $code = $LASTEXITCODE
    foreach ($l in $out) { Write-Line ("  " + $l) }
    $selfOk = ($code -eq 0) -and (($out -join "`n") -match "R2_SELFTEST:\s*PASS")
} else {
    Write-Line ("  缺 " + $reconPy)
}
if ($selfOk) { Add-Step "recon-selftest" "PASS" "5/5 正负对照 PASS" } else { Add-Step "recon-selftest" "FAIL" "见上输出" }
Write-Line ""

# =============================================================================
# 4. Tcl 结构完整性（本机无 tclsh 的替代; 权威 = CI tclsh info-complete）
# =============================================================================
Write-Section "4) r2_ilacap.tcl: 结构完整性检查（引号/花括号/方括号闭合; 行尾 # 检测）"
$tcl = Join-Path $script:OutRoot "r2_ilacap.tcl"
$tclOk = $false
if (Test-Path $tcl) {
    $out = & $script:PyExe $reconPy --check-tcl $tcl 2>&1 | ForEach-Object { [string]$_ }
    $code = $LASTEXITCODE
    foreach ($l in $out) { Write-Line ("  " + $l) }
    $tclOk = ($code -eq 0)
    Write-Line "  注: 本机无 tclsh/Vivado 时以该结构检查+CI 远端 tclsh info-complete 为准; 本脚本不跑 Vivado。"
} else {
    Write-Line ("  缺 " + $tcl)
}
if ($tclOk) { Add-Step "tcl-check" "PASS" "结构完整" } else { Add-Step "tcl-check" "FAIL" "见上输出" }
Write-Line ""

# =============================================================================
# 5. r2_board.ps1 DRY-RUN（带 R1 归档 fixture 做真校验）
# =============================================================================
Write-Section "5) r2_board.ps1 DRY-RUN（R1 归档工件作只读 fixture: 真校验 SHA/日志/邻居/NIC/串口）"
$board = Join-Path $script:OutRoot "r2_board.ps1"
$bd = Join-Path $script:OutRoot "archive\b31b_rdfix_2026-10-17"
$fixtureBit = Join-Path $bd "aurora_mem_bridge_rdfix_c8cd3a32.bit"
$fixtureElf = Join-Path $bd "j3_soft_n7_2961b585.elf"
$fixtureLog = Join-Path $bd "build_retire_fix_sweep.log"
$childArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $board)
if ((Test-Path $fixtureBit) -and (Test-Path $fixtureElf) -and (Test-Path $fixtureLog)) {
    $childArgs += @("-Bit", $fixtureBit, "-Elf", $fixtureElf, "-BuildLog", $fixtureLog,
                    "-ExpectBitHash8", "c8cd3a32", "-ExpectElfHash8", "2961b585", "-Port", "COM5")
    Write-Line "  使用 R1 归档 fixture: c8cd3a32.bit + 2961b585.elf + build_retire_fix_sweep.log"
} else {
    Write-Line "  未找到 R1 归档 fixture（不存在则只验证 SKIP 路径）"
}
$boardText = New-Object System.Collections.ArrayList
$child = & "powershell.exe" @childArgs 2>&1
foreach ($l in $child) { $line = [string]$l; [void]$boardText.Add($line); Write-Line ("  " + $line) }
$boardCode = $LASTEXITCODE
$boardTextJoined = $boardText -join "`n"
$guardOk = ($boardTextJoined -match "GUARD 计数器必须全 0") -and ($boardTextJoined -match "实测计数合计=0")
$resultSkip = ($boardTextJoined -match "R2_RESULT:\s*SKIP \(dry-run")
$boardOk = ($boardCode -eq 0) -and $guardOk -and $resultSkip
if ($boardOk) { Add-Step "board-dryrun" "PASS" "GUARD 全 0 + R2_RESULT: SKIP + exit=0" }
else { Add-Step "board-dryrun" "FAIL" ("exit=" + $boardCode + " guard=" + $guardOk + " skip=" + $resultSkip) }
Write-Line ""

# =============================================================================
# 6. r2_mb10_sha.ps1 DRY-RUN
# =============================================================================
Write-Section "6) r2_mb10_sha.ps1 DRY-RUN（10MB 源文件大小/SHA + json_storm 参数 + 端口; 不建 socket）"
$mb10 = Join-Path $script:OutRoot "r2_mb10_sha.ps1"
$mbText = New-Object System.Collections.ArrayList
$child = & "powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $mb10 2>&1
foreach ($l in $child) { $line = [string]$l; [void]$mbText.Add($line); Write-Line ("  " + $line) }
$mbCode = $LASTEXITCODE
$mbJoined = $mbText -join "`n"
$mbOk = ($mbCode -eq 0) -and ($mbJoined -match "R2_MB10_RESULT:\s*SKIP \(dry-run") -and ($mbJoined -match "源 SHA256 与钉死期望一致") -and ($mbJoined -match "质量档默认参数\(源码实测\)")
if ($mbOk) { Add-Step "mb10-dryrun" "PASS" "源SHA/参数真校验 + R2_MB10_RESULT: SKIP + exit=0" }
else { Add-Step "mb10-dryrun" "FAIL" ("exit=" + $mbCode) }
Write-Line ""

# =============================================================================
# 7. 只读纪律自证：R1 资产 hash 前后一致
# =============================================================================
Write-Section "7) 只读纪律自证: R1 参考脚本/设计文档 自证前后 SHA256 一致"
$roOk = $true
foreach ($k in $r1Assets.Keys) {
    $p = $r1Assets[$k]
    $after = ""
    if (Test-Path $p) { $after = Get-Sha256 $p } else { $after = "(missing)" }
    $ok = ($before[$k] -eq $after)
    if (-not $ok) { $roOk = $false }
    Write-Line ("  {0}: before={1} after={2} {3}" -f $k, $before[$k].Substring(0, [Math]::Min(16, $before[$k].Length)), $after.Substring(0, [Math]::Min(16, $after.Length)), $(if ($ok) { "不变 ✓" } else { "变了 ✗" }))
}
if ($roOk) { Add-Step "readonly-discipline" "PASS" "R1 资产未被修改" } else { Add-Step "readonly-discipline" "FAIL" "R1 资产被修改!" }
Write-Line ""

# =============================================================================
# 汇总 + 落盘
# =============================================================================
Write-Section "R2 dry-run 自证汇总"
$passCount = 0
foreach ($s in $script:Steps) {
    Write-Line ("  [R2_DRYRUN_STEP] {0}: {1} {2}" -f $s.Name, $s.Verdict, $s.Detail)
    if ($s.Verdict -eq "PASS") { $passCount++ }
}
Write-Line ""
Write-Line ("证据: 本日志即 out\r2_dryrun.log; r2_board.ps1 各自的 dry-run 日志另落 evidence_2026-10-17\R2_<ts>.log / R2_mb10_<ts>.log")
if ($script:Fails.Count -eq 0) {
    Write-Line ("R2_DRYRUN_RESULT: PASS ({0}/{1})" -f $passCount, $script:Steps.Count)
    $final = 0
} else {
    Write-Line ("R2_DRYRUN_RESULT: FAIL 失败项=" + ($script:Fails -join ","))
    $final = 1
}

$text = ($script:Log -join "`r`n") + "`r`n"
try {
    [System.IO.File]::WriteAllText($LogPath, $text, $script:Utf8Bom)
    Write-Host ("日志已落盘: " + $LogPath + "  (" + $text.Length + " chars, UTF-8 BOM)")
} catch {
    Write-Host ("FATAL: 无法写日志: " + $_.Exception.Message) -ForegroundColor Red
    exit 2
}
exit $final
