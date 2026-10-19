# r3d_synth_retry.ps1 -- round3d full-acceptance-probe synth
#   ILA3 = 152b full (mem/mem2 counters + stall/len_err + s2mm state: S6/S10 判据所需)
#   ILA5 = 47b trimmed (tdata32/tkeep8/tvalid/tready/tlast + probe5 4b)
#   ILA4 skipped (not needed for S0-S11; saves timing margin)
$ErrorActionPreference = "Continue"
Set-Location "D:\FPGA"
$env:R3C_SKIP_ILA4 = "1"
$env:R3C_LITE_ILA5 = "1"
$proj = "D:\FPGA\prj\project_11"
$log = "$proj\out\r3d_synth.log"
$con = "$proj\out\r3d_synth_console.log"
for ($try = 1; $try -le 4; $try++) {
    Write-Output "==== SYNTH TRY $try $(Get-Date -Format 'HH:mm:ss') ===="
    cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source D:\FPGA\prj\project_11\scripts\build_synth_only.tcl -notrace -log $log -journal $proj\out\r3d_synth.jou > $con 2>&1"
    $exit = $LASTEXITCODE
    $done = Select-String -Path $con -Pattern 'SYNTH_ONLY_DONE' -Quiet -ErrorAction SilentlyContinue
    Write-Output "exit=$exit done=$done"
    if ($done) { Write-Output "SYNTH_OK try=$try"; break }
    Write-Output "---- failure tail ----"
    Get-Content $con -Tail 12 | ForEach-Object { Write-Output $_ }
    Start-Sleep -Seconds 5
}
