# =============================================================================
# pc_side_monitor.ps1 -- Board B stability: 30 s PC-side patrol (ASCII ONLY!)
# Reason for ASCII-only: PS 5.1 -File reads UTF-8-without-BOM as ANSI/GBK and
# Chinese comments break the parser. Project twin_config.json follows the same rule.
#
# Judges: one Link Down / ping all-lost / CH340 missing => one timestamped line.
# No averaging, no "looks fine".
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File pc_side_monitor.ps1 -DurationSec 3480 -Log <path>
# =============================================================================
param(
    [int]$DurationSec = 3600,
    [int]$IntervalSec = 30,
    [string]$Log = 'D:\FPGA\prj\project_11\out\evidence_2026-11-10_boardB_stability\pc_side_monitor.log',
    [string]$NicName = [char]0x4EE5 + [char]0x592A + [char]0x7F51
)
$ErrorActionPreference = 'Continue'

function Mark([string]$s) {
    Add-Content -Path $Log -Value $s -Encoding UTF8
    Write-Output $s
}

$t0 = Get-Date
Mark ("PC_MON_START {0:yyyy-MM-dd HH:mm:ss} dur={1} ival={2} nic={3}" -f $t0, $DurationSec, $IntervalSec, $NicName)

$downs = 0
$pingfails = 0
$usbgone = 0

while (((Get-Date) - $t0).TotalSeconds -le $DurationSec) {
    $el = [int]((Get-Date) - $t0).TotalSeconds
    $nic = Get-NetAdapter -Name $NicName -ErrorAction SilentlyContinue
    $st = if ($nic) { [string]$nic.Status } else { 'MISSING' }
    $sp = if ($nic) { [string]$nic.LinkSpeed } else { '-' }
    $ping = Test-Connection -ComputerName 192.168.1.10 -Count 1 -Quiet -ErrorAction SilentlyContinue
    $ch340 = @(Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue |
               Where-Object { $_.Status -eq 'OK' -and $_.InstanceId -match 'VID_1A86' }).Count
    $jtag = @(Get-PnpDevice -ErrorAction SilentlyContinue |
              Where-Object { $_.Status -eq 'OK' -and $_.FriendlyName -match 'USB Serial Converter' }).Count

    if ($st -ne 'Up') { $downs++ }
    if (-not $ping) { $pingfails++ }
    if ($ch340 -lt 1) { $usbgone++ }

    Mark ("T+{0} NIC={1} LINK={2} PING={3} CH340={4} JTAG={5}" -f $el, $st, $sp, $ping, $ch340, $jtag)
    Start-Sleep -Seconds $IntervalSec
}

Mark ("PC_MON_DONE elapsed={0} linkdown={1} pingfail={2} usbgone={3}" -f $DurationSec, $downs, $pingfails, $usbgone)
