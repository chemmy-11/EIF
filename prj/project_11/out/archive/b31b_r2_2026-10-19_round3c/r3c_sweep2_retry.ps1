# r3c_sweep2_retry.ps1 -- round3c implementation sweep2 retry wrapper (Vivado transient, pit #61)
# ★2026-10-19: MUST run from ASCII CWD (D:\FPGA). implement_debug_core spawns a child vivado whose
#   temp dir/scripts live under <CWD>\.Xil; a Chinese CWD (C:\Users\...\毕设) makes the child fail
#   to read its Tcl (pit #21 family) -> "Synthesis of Debug Cores has failed / dbg_hub_synth_1".
$ErrorActionPreference = "Continue"
Set-Location "D:\FPGA"
$proj = "D:\FPGA\prj\project_11"
$log = "$proj\out\r3c_sweep2.log"
$con = "$proj\out\r3c_sweep2_console.log"
for ($try = 1; $try -le 3; $try++) {
    Write-Output "==== SWEEP2 TRY $try $(Get-Date -Format 'HH:mm:ss') ===="
    cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source D:\FPGA\prj\project_11\scripts\build_v5_sweep2.tcl -notrace -log $log -journal $proj\out\r3c_sweep2.jou > $con 2>&1"
    $exit = $LASTEXITCODE
    $ok = Select-String -Path $con -Pattern 'V5_SWEEP2_OK' -Quiet -ErrorAction SilentlyContinue
    Write-Output "exit=$exit ok=$ok"
    if ($ok) { Write-Output "SWEEP2_OK try=$try"; break }
    Write-Output "---- failure tail ----"
    Get-Content $con -Tail 10 | ForEach-Object { Write-Output $_ }
    Start-Sleep -Seconds 5
}
