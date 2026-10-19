# r3c2_synth_retry.ps1 -- round3c-lite (ILA4 skipped via env) synth retry wrapper
# Why: attempt1 (4 ILA cores) post-route WNS=-0.029 GATE_FAIL and phys_opt extremely slow.
#      Trimmed build keeps u_ila_5 probe5 (the GO/ACK/introut instrument) and drops u_ila_4
#      to recover margin (round3b baseline +37b @100MHz removed). ltx = 3 cores.
$ErrorActionPreference = "Continue"
Set-Location "D:\FPGA"
$env:R3C_SKIP_ILA4 = "1"
$proj = "D:\FPGA\prj\project_11"
$log = "$proj\out\r3c2_synth.log"
$con = "$proj\out\r3c2_synth_console.log"
for ($try = 1; $try -le 4; $try++) {
    Write-Output "==== SYNTH TRY $try $(Get-Date -Format 'HH:mm:ss') ===="
    cmd /c "`"D:\Xilinx\Vivado\2023.1\bin\vivado.bat`" -mode batch -source D:\FPGA\prj\project_11\scripts\build_synth_only.tcl -notrace -log $log -journal $proj\out\r3c2_synth.jou > $con 2>&1"
    $exit = $LASTEXITCODE
    $done = Select-String -Path $con -Pattern 'SYNTH_ONLY_DONE' -Quiet -ErrorAction SilentlyContinue
    Write-Output "exit=$exit done=$done"
    if ($done) { Write-Output "SYNTH_OK try=$try"; break }
    Write-Output "---- failure tail ----"
    Get-Content $con -Tail 12 | ForEach-Object { Write-Output $_ }
    Start-Sleep -Seconds 5
}
