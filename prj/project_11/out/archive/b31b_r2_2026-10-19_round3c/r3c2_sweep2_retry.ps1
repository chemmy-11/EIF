# r3c2_sweep2_retry.ps1 -- round3c-lite implementation sweep2 retry wrapper
$ErrorActionPreference = "Continue"
Set-Location "D:\FPGA"
$proj = "D:\FPGA\prj\project_11"
$log = "$proj\out\r3c2_sweep2.log"
$con = "$proj\out\r3c2_sweep2_console.log"
for ($try = 1; $try -le 3; $try++) {
    Write-Output "==== SWEEP2 TRY $try $(Get-Date -Format 'HH:mm:ss') ===="
    cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source D:\FPGA\prj\project_11\scripts\build_v5_sweep2.tcl -notrace -log $log -journal $proj\out\r3c2_sweep2.jou > $con 2>&1"
    $exit = $LASTEXITCODE
    $ok = Select-String -Path $con -Pattern 'V5_SWEEP2_OK' -Quiet -ErrorAction SilentlyContinue
    Write-Output "exit=$exit ok=$ok"
    if ($ok) { Write-Output "SWEEP2_OK try=$try"; break }
    Write-Output "---- failure tail ----"
    Get-Content $con -Tail 10 | ForEach-Object { Write-Output $_ }
    Start-Sleep -Seconds 5
}
