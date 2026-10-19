# r3c3_synth_retry.ps1 -- round3c-diag (lite ILA: ILA4 skipped, ILA3/ILA5 trimmed) synth
$ErrorActionPreference = "Continue"
Set-Location "D:\FPGA"
$env:R3C_SKIP_ILA4 = "1"
$env:R3C_LITE_ILA = "1"
$proj = "D:\FPGA\prj\project_11"
$log = "$proj\out\r3c3_synth.log"
$con = "$proj\out\r3c3_synth_console.log"
for ($try = 1; $try -le 4; $try++) {
    Write-Output "==== SYNTH TRY $try $(Get-Date -Format 'HH:mm:ss') ===="
    cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source D:\FPGA\prj\project_11\scripts\build_synth_only.tcl -notrace -log $log -journal $proj\out\r3c3_synth.jou > $con 2>&1"
    $exit = $LASTEXITCODE
    $done = Select-String -Path $con -Pattern 'SYNTH_ONLY_DONE' -Quiet -ErrorAction SilentlyContinue
    Write-Output "exit=$exit done=$done"
    if ($done) { Write-Output "SYNTH_OK try=$try"; break }
    Write-Output "---- failure tail ----"
    Get-Content $con -Tail 12 | ForEach-Object { Write-Output $_ }
    Start-Sleep -Seconds 5
}
