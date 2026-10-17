# retire_s2_s6.ps1 - 新退役位流上板判据 S0-S6 一键执行并把原始输出落盘
# 用法: powershell -ExecutionPolicy Bypass -File retire_s2_s6.ps1 -Bit <bit> -Elf <elf> [-Port COM5] [-SkipBurn]
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
function RunCapture($title, [scriptblock]$sb) {
    Say ("=== " + $title + " ===")
    $out = & $sb 2>&1 | Out-String
    Write-Output $out
    Add-Content -Path $log -Value $out -Encoding UTF8
}

$u  = Join-Path $here "uart_probe.py"
$mr = Join-Path $here "manual_round.py"
$xsct = "D:\Xilinx\Vitis\2023.1\bin\xsct.bat"
$burnTcl = "D:/FPGA/prj/project_11/out/jb31b_burn_pair.tcl"

Say ("bit=" + $Bit)
Say ("elf=" + $Elf)
Say ("bit_hash8=" + (Get-FileHash $Bit -Algorithm SHA256).Hash.Substring(0,8).ToLower())
Say ("elf_hash8=" + (Get-FileHash $Elf -Algorithm SHA256).Hash.Substring(0,8).ToLower())

RunCapture "S0 neighbor" { Get-NetNeighbor -IPAddress 192.168.1.10 | Select-Object IPAddress,LinkLayerAddress,State,PolicyStore | Format-Table -AutoSize }

if (-not $SkipBurn) {
    RunCapture "S0 burn new bitstream" { & $xsct $burnTcl ($Bit -replace "\\","/") ($Elf -replace "\\","/") 2>&1 | Select-Object -Last 3 }
    Start-Sleep -Seconds 3
}

RunCapture "S2 single-frame WITHOUT d (retirement must NOT work)" { $env:PYTHONUTF8 = "1"; py $mr $Port 1 }

RunCapture "S3 send d then read U (req bit24 must be 1)" { py $u --cmd d --wait 2 --drain 0.3 --raw; py $u --cmd U --wait 3 --drain 0.2 --raw }

RunCapture "S4 single-frame WITH d (expect wr+1 rd+1, echo=1)" { $env:PYTHONUTF8 = "1"; py $mr $Port 1 }

$nic = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq "192.168.1.102" }).InterfaceAlias
Say ("nic=" + $nic)
$b = Get-NetAdapterStatistics -Name $nic
RunCapture "S5 ping x4" { ping -n 4 -w 900 192.168.1.10 }
Start-Sleep -Milliseconds 300
$a = Get-NetAdapterStatistics -Name $nic
Say ("S5 ReceivedUnicast delta=" + ($a.ReceivedUnicastPackets - $b.ReceivedUnicastPackets))
Say ("S5 ReceivedBytes   delta=" + ($a.ReceivedBytes - $b.ReceivedBytes))

RunCapture "S6 U (arl / emit / wmrd / stat / wmwr)" { py $u --cmd U --wait 3 --drain 0.2 --raw }

Say ("LOG SAVED: " + $log)