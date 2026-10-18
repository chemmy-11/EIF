# run_sim.ps1 -- build + run the prj11 R2 axi_dma IP-level simulation.
# Uses cmd file redirection for Vivado stdout (project pitfall #58) and retries
# once only for a transient install-disk read failure (pitfall #61).
$ErrorActionPreference = "Continue"
$root = "D:\FPGA\prj\project_11\out\ip_sim_r2"
$viv  = "D:\Xilinx\Vivado\2023.1\bin\vivado.bat"
$con  = "$root\logs\console.log"

for ($try = 1; $try -le 2; $try++) {
    Write-Output "==== SIM TRY $try $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===="
    cmd /c "`"$viv`" -mode batch -source $root\build_sim.tcl -notrace -log $root\logs\vivado.log -journal $root\logs\vivado.jou > `"$con`" 2>&1"
    $exit = $LASTEXITCODE
    $pass = Select-String -Path $con -Pattern '^TEST_PASS' -Quiet -ErrorAction SilentlyContinue
    Write-Output "exit=$exit TEST_PASS=$pass"
    if ($pass) { break }
    $transient = Select-String -Path $con -Pattern 'Read error|cannot open|No such file|Input/output error' -Quiet -ErrorAction SilentlyContinue
    if (-not $transient) { break }
    Write-Output "---- transient install-disk signature, retry ----"
    Start-Sleep -Seconds 5
}
exit $exit
