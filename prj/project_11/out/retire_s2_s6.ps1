# retire_s2_s6.ps1 — 新退役位流上板判据 S1–S6 一键执行并把原始输出落盘
# 用法: pwsh -File retire_s2_s6.ps1 -Bit <绝对路径.bit> -Elf <绝对路径.elf> [-Port COM5] [-SkipBurn]
param(
    [Parameter(Mandatory = $true)][string]$Bit,
    [Parameter(Mandatory = $true)][string]$Elf,
    [string]$Port = "COM5",
    [switch]$SkipBurn
)
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ev = Join-Path $here ("evidence_" + (Get-Date -Format "yyyy-MM-dd"))
New-Item -ItemType Directory -Force $ev | Out-Null
$log = Join-Path $ev ("s2_s6_" + (Get-Date -Format "HHmmss") + ".log")

function Say($m) {
    $line = ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $m)
    Write-Output $line
    Add-Content -Path $log -Value $line -Encoding UTF8
}
function RunCapture($title, $cmd) {
    Say "=== $title ==="
    $out = & pwsh -NoProfile -Command $cmd 2>&1 | Out-String
    Write-Output $out
    Add-Content -Path $log -Value $out -Encoding UTF8
}

$py = "py"
$u  = Join-Path $here "uart_probe.py"
$mr = Join-Path $here "manual_round.py"

Say ("bit=" + $Bit)
Say ("elf=" + $Elf)
Say ("bit_hash8=" + (Get-FileHash $Bit -Algorithm SHA256).Hash.Substring(0,8).ToLower())
Say ("elf_hash8=" + (Get-FileHash $Elf -Algorithm SHA256).Hash.Substring(0,8).ToLower())
Add-Content -Path $log -Value ("bit_sha256=" + (Get-FileHash $Bit -Algorithm SHA256).Hash) -Encoding UTF8
Add-Content -Path $log -Value ("elf_sha256=" + (Get-FileHash $Elf -Algorithm SHA256).Hash) -Encoding UTF8

RunCapture "S0 neighbor" ("Get-NetNeighbor -IPAddress 192.168.1.10 | Select-Object IPAddress,LinkLayerAddress,State,PolicyStore | Format-Table -AutoSize | Out-String")

if (-not $SkipBurn) {
    RunCapture "S0 burn" ("& 'D:\Xilinx\Vitis\2023.1\bin\xsct.bat' 'D:/FPGA/prj/project_11/out/jb31b_burn_pair.tcl' '" + $Bit + "' '" + $Elf + "' 2>&1 | Select-Object -Last 2 | Out-String")
    Start-Sleep -Seconds 2
}

RunCapture "S2 single-frame WITHOUT d (expect FAIL/STALL)" ("$py '$mr' $Port 1 2>&1 | Out-String")

RunCapture "S3 d then U (req bit24 must be 1)" ("$py '$u' --cmd d --wait 2 --drain 0.3 --raw; $py '$u' --cmd U --wait 3 --drain 0.2 --raw")

RunCapture "S4 single-frame WITH d (expect wr+1 rd+1 echo=1)" ("$py '$mr' $Port 1 2>&1 | Out-String")

$nic = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq '192.168.1.102' }).InterfaceAlias
Say ("nic=" + $nic)
$b = Get-NetAdapterStatistics -Name $nic
RunCapture "S5 ping x4" ("ping -n 4 -w 900 192.168.1.10 | Out-String")
Start-Sleep -Milliseconds 300
$a = Get-NetAdapterStatistics -Name $nic
Say ("S5 ReceivedUnicast delta=" + ($a.ReceivedUnicastPackets - $b.ReceivedUnicastPackets))
Say ("S5 ReceivedBytes   delta=" + ($a.ReceivedBytes - $b.ReceivedBytes))

RunCapture "S6 U (arl / emit / wmwr / wmrd)" ("$py '$u' --cmd U --wait 3 --drain 0.2 --raw")

Say ("LOG SAVED: " + $log)