# r3c3_sweep_one_retry.ps1 -- round3c-diag single-directive (ExtraTimingOpt) sweep
$ErrorActionPreference = "Continue"
Set-Location "D:\FPGA"
$proj = "D:\FPGA\prj\project_11"
$log = "$proj\out\r3c3_one.log"
$con = "$proj\out\r3c3_one_console.log"
for ($try = 1; $try -le 3; $try++) {
    Write-Output "==== SWEEP1 TRY $try $(Get-Date -Format 'HH:mm:ss') ===="
    cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source D:\FPGA\prj\project_11\out\r3c2_sweep_one.tcl -notrace -log $log -journal $proj\out\r3c3_one.jou > $con 2>&1"
    $exit = $LASTEXITCODE
    $ok = Select-String -Path $con -Pattern 'V5_SWEEP1_OK' -Quiet -ErrorAction SilentlyContinue
    Write-Output "exit=$exit ok=$ok"
    if ($ok) { Write-Output "SWEEP1_OK try=$try"; break }
    Write-Output "---- failure tail ----"
    Get-Content $con -Tail 10 | ForEach-Object { Write-Output $_ }
    Start-Sleep -Seconds 5
}
