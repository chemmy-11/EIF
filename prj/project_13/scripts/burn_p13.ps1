# =============================================================================
# burn_p13_pc1.ps1 — PC1 侧 prj13 单板烧录（bit + ELF）+ DMA 置位 + 校验
#   软角色映射（2026-11-19 裁决）：PC1 侧板 = 软角色 A（IP 10.10.0.11）
#   用法：
#     powershell -NoProfile -ExecutionPolicy Bypass -File burn_p13_pc1.ps1 -Bit <bit路径>
#   判据：必须打印 BURN_OK 与 DMAMODE now=DMA；「无 ERROR」不算成功。
# =============================================================================
param(
  [Parameter(Mandatory=$true)][string]$Bit,
  [string]$Elf = 'D:\FPGA\prj\project_13\out\j3_soft_r2_BA3C0220.elf',
  [string]$Cable = '210512180081',
  [string]$Com = 'COM5',
  [string]$Url = 'localhost:3121'
)
$ErrorActionPreference = 'Continue'
$env:TEMP = 'D:\FPGA\.tmp'; $env:TMP = 'D:\FPGA\.tmp'
$xsct = 'D:\Xilinx\Vitis\2023.1\bin\xsct.bat'
$burnTcl = 'D:\FPGA\prj\project_13\scripts\burn_one.tcl'

Write-Output ("T=" + (Get-Date -Format 'HH:mm:ss.fff'))

# --- 0. Vivado 串行纪律：实现/综合期间禁止烧录 ---
$v = Get-Process vivado -ErrorAction SilentlyContinue
if ($v) {
  Write-Output ("BLOCKED: 仍有 vivado 进程 " + (($v | ForEach-Object { $_.Id }) -join ','))
  Write-Output "  先等构建结束（Vivado 全局串行），不要并烧。"
  exit 3
}

# --- 1. 件存在性与哈希前缀自证（文件名里带 sha 前 8 位）---
if (-not (Test-Path $Bit)) { Write-Output "FAIL: bit not found $Bit"; exit 2 }
$sha = (Get-FileHash $Bit -Algorithm SHA256).Hash.ToLower()
Write-Output ("BIT_SHA256: " + $sha)
Write-Output ("BIT_BYTES : " + (Get-Item $Bit).Length)
$nameSha = [regex]::Match([IO.Path]::GetFileName($Bit), '([0-9a-f]{8})').Groups[1].Value
if ($nameSha -and -not $sha.StartsWith($nameSha)) {
  Write-Output ("FAIL: 文件名内 sha 前缀 '$nameSha' 与实测不符 —— 件被换过？")
  exit 2
}
Write-Output ("BIT_SHA_PREFIX_OK: " + $nameSha)

if ($Elf -ne '-' -and -not (Test-Path $Elf)) { Write-Output "FAIL: elf not found $Elf"; exit 2 }
if ($Elf -ne '-') {
  $esha = (Get-FileHash $Elf -Algorithm SHA256).Hash.ToLower()
  Write-Output ("ELF_SHA256: " + $esha)
  if ($esha -ne 'ba3c02209720b59d9f0fbc4083c2ab80b16efc9a148448b9dcfbcda001bb3559') {
    Write-Output "FAIL: ELF 哈希与登记值不符（期望 ba3c0220…3559）"; exit 2
  }
  Write-Output "ELF_SHA_OK"
}

# --- 2. 烧录 ---
Write-Output "--- burn via xsct burn_one.tcl ---"
& $xsct $burnTcl $Url $Bit $Elf $Cable 2>&1 | Tee-Object -Variable burnOut | Out-Null
$burnOut | Select-String -Pattern 'BURN_(URL|BIT|ELF|CABLE|MB_TARGET|BIT_DONE|ELF_DONE|OK|FAILED)|ERROR' |
  ForEach-Object { "  " + $_.Line.Trim() }
if (-not ($burnOut -match 'BURN_OK')) {
  Write-Output "BURN_RESULT: FAIL（未打印 BURN_OK）"
  exit 4
}
Write-Output "BURN_RESULT: PASS"

# --- 3. 串口置 DMA（d 是翻转命令，必须回读 banner 确认）---
Start-Sleep -Seconds 2
Write-Output "--- serial: d -> expect now=DMA ---"
$port = New-Object System.IO.Ports.SerialPort $Com,9600,'None',8,'One'
$port.ReadTimeout = 200
$ok = $false
for ($try = 1; $try -le 3; $try++) {
  try {
    if (-not $port.IsOpen) { $port.Open() }
    $port.DiscardInBuffer(); $port.Write('d'); Start-Sleep -Milliseconds 500
    $sw = [Diagnostics.Stopwatch]::StartNew(); $sb = New-Object Text.StringBuilder
    while ($sw.ElapsedMilliseconds -lt 900) {
      try { $c = $port.ReadExisting(); if ($c) { [void]$sb.Append($c) } } catch {}
      Start-Sleep -Milliseconds 20
    }
    $txt = ($sb.ToString() -replace "`r?`n", ' ').Trim()
    Write-Output ("  try ${try}: sent 'd' -> " + $txt)
    if ($txt -match 'now=DMA') { $ok = $true; break }
  } catch { Write-Output ("  try ${try}: SERIAL_EXCEPTION " + $_.Exception.Message) }
}
if ($port.IsOpen) { $port.Close() }
if ($ok) { Write-Output "SERIAL_RESULT: PASS"; Write-Output "BURN_AND_DMA_OK"; exit 0 }
Write-Output "SERIAL_RESULT: FAIL（3 次都没读到 now=DMA）"
exit 5
