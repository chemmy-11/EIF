# =============================================================================
# serial_snapshot.ps1 -- prj12 上板用：串口抓一次快照（发一个字符命令，收 N 秒，落文件）
# 为什么需要：P1 的链路态（channel_up/hard_err）没有寄存器路径，只能看 ILA；
#   但桥/泵计数（u_wr_frame/u_rd_frame/u_buf_drop/mem2）软核可读，串口 `U` 能一次打出来，
#   与 ILA6 的 probe5..probe8 互为佐证。现场手敲串口容易漏行，故固化成脚本。
# 前置：板上已下载 ELF（out\twin_burn.ps1 -Mode BitElf），9600 8N1。
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File out\serial_snapshot.ps1 -DryRun
#   ... -Com COM5 -Command U -Out out\serial_A_U.txt
#   ... -Com COM7 -Command I -Seconds 2 -Out out\serial_B_I.txt
# 退出码: 0 = 收到数据（或 dry-run 自洽）；1 = 端口不在/打不开/期间零字节
# =============================================================================
param(
    [string]$Com = 'COM5',
    [int]$Baud = 9600,
    [ValidateSet('U','I','Q','W','M','A','B','D','E','L','S','?')][string]$Command = 'U',
    [int]$Seconds = 3,
    [string]$Out = '',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$dry = $DryRun.IsPresent

function Say([string]$s) { Write-Output $s }

if ($Out -eq '') { $Out = Join-Path (Join-Path $PSScriptRoot '') "serial_${Com}_${Command}.txt" }

Say "=== serial_snapshot ==="
Say "com     : $Com @ $Baud 8N1"
Say "command : '$Command'  (duration ${Seconds}s)"
Say "out     : $Out"

$ports = [System.IO.Ports.SerialPort]::GetPortNames()
Say "ports   : $($ports -join ', ')"
if ($ports -notcontains $Com) {
    if ($dry) { Say "WARN: $Com 不在系统里（dry-run 允许：板卡不在场）" }
    else { Say "FAIL: $Com 不存在（GetPortNames -> $($ports -join ',')）"; exit 1 }
}

if ($dry) {
    Say "DRY_RUN: 会打开 $Com，写 '$Command'，读 ${Seconds}s，落 $Out"
    Say "SERIAL_RESULT: DRY_RUN_OK"
    exit 0
}

$sp = New-Object System.IO.Ports.SerialPort $Com, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.ReadTimeout = 500
$sp.NewLine = "`r`n"
$buf = New-Object System.Text.StringBuilder
try {
    $sp.Open()
    Start-Sleep -Milliseconds 200
    $sp.DiscardInBuffer()
    $sp.Write($Command)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $chunk = $sp.ReadExisting()
            if ($chunk -and $chunk.Length -gt 0) { [void]$buf.Append($chunk) }
        } catch { }
        Start-Sleep -Milliseconds 100
    }
} catch {
    Say "FAIL: 串口异常: $($_.Exception.Message)"
    exit 1
} finally {
    if ($sp.IsOpen) { $sp.Close() }
    $sp.Dispose()
}

$text = $buf.ToString()
[System.IO.File]::WriteAllText($Out, $text, (New-Object System.Text.UTF8Encoding($false)))
Say "bytes   : $($text.Length)"
if ($text.Length -eq 0) {
    Say "FAIL: ${Seconds}s 内零字节（ELF 是否已下载？$Com 是否选对？波特率 9600？）"
    exit 1
}
Say "---- last 20 lines ----"
($text -split "`r?`n") | Select-Object -Last 20 | ForEach-Object { Say $_ }
Say "SERIAL_RESULT: PASS ($Out)"
exit 0
