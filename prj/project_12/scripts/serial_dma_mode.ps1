# =============================================================================
# serial_dma_mode.ps1 -- prj12: put the MicroBlaze firmware into DMA write mode ('d').
#
# Why this is REQUIRED for prj12 P1 (2026-11-06 finding):
#   bridge (1) (eth -> Aurora TX) writes DDR through AXI DMA S2MM in prj11/12
#   (frame_mem_if HAS_DMA=1). That engine is serviced *by the firmware*: the
#   bridge raises a per-frame write request and the soft core programs S2MM and
#   toggles GO. The firmware only does this when g_dma_mode=1, which is set by
#   the lowercase 'd' command. Without it: pfwd_wr counts, but mem_wr_frm /
#   pk_frames stay 0 (frames never leave the pump).
#
# The 'd' command is a TOGGLE, so this script sends 'd', reads the banner and
# repeats (max 3 times) until the banner says "now=DMA".
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File serial_dma_mode.ps1 -Com COM6
#   ... -Com COM6 -DryRun
# Prereq: ELF already downloaded (twin_burn.ps1 -Board <A|B> -Mode BitElf -Run),
#         UART 9600 8N1.
# Exit: 0 = firmware reports DMA mode, 1 = failed/timeout, 2 = serial port error.
# =============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Com,
    [int]$Baud = 9600,
    [int]$Seconds = 2,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'

function Say([string]$s) { Write-Output $s }
function Finish([int]$code, [string]$s) { Say $s; exit $code }

Say "=== serial_dma_mode ==="
Say "com    : $Com @ $Baud 8N1"
$ports = [System.IO.Ports.SerialPort]::GetPortNames()
Say "ports  : $($ports -join ', ')"
if ($ports -notcontains $Com) { Finish 2 "SERIAL_RESULT: FAIL - $Com not present" }
if ($DryRun) { Finish 0 "SERIAL_RESULT: DRY_RUN_OK (would send 'd' until banner says now=DMA)" }

$port = New-Object System.IO.Ports.SerialPort $Com, $Baud, 'None', 8, 'One'
$port.ReadTimeout = 300
$port.DtrEnable = $true
$port.RtsEnable = $true
try { $port.Open() } catch { Finish 2 "SERIAL_RESULT: FAIL - open $Com : $($_.Exception.Message)" }

function Read-For([System.IO.Ports.SerialPort]$p, [int]$ms) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sb = New-Object System.Text.StringBuilder
    while ($sw.ElapsedMilliseconds -lt $ms) {
        try { $c = $p.ReadExisting(); if ($c) { [void]$sb.Append($c) } } catch { }
        Start-Sleep -Milliseconds 40
    }
    return $sb.ToString()
}

$ok = $false
$last = ''
for ($try = 1; $try -le 3; $try++) {
    Start-Sleep -Milliseconds 150
    $port.DiscardInBuffer()
    $port.Write('d')
    $rx = Read-For $port ($Seconds * 1000)
    $last = $rx
    Say "try ${try}: sent 'd' -> $(($rx -replace "`r?`n", ' ').Trim())"
    if ($rx -match 'DMAMODE\s+now=DMA') { $ok = $true; break }
}
$port.Close()

if ($ok) { Finish 0 "SERIAL_RESULT: PASS - firmware in DMA mode ('d')" }
Finish 1 "SERIAL_RESULT: FAIL - banner never said now=DMA (last RX: $last)"
