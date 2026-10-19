# -*- coding: utf-8 -*-
"""Generate out/r3c_synth_retry.ps1 (UTF-8 BOM, ASCII-only body) -- round3c synth wrapper."""
import io

LINES = [
    '# r3c_synth_retry.ps1 -- round3c synth retry wrapper (Vivado install-disk transient, pit #61)',
    '$ErrorActionPreference = "Continue"',
    '$proj = "D:\\FPGA\\prj\\project_11"',
    '$log = "$proj\\out\\r3c_synth.log"',
    '$con = "$proj\\out\\r3c_synth_console.log"',
    'for ($try = 1; $try -le 4; $try++) {',
    '    Write-Output "==== SYNTH TRY $try $(Get-Date -Format \'HH:mm:ss\') ===="',
    '    cmd /c "`"D:\\Xilinx\\Vivado\\2023.1\\bin\\vivado.bat`" -mode batch -source D:\\FPGA\\prj\\project_11\\scripts\\build_synth_only.tcl -notrace -log $log -journal $proj\\out\\r3c_synth.jou > $con 2>&1"',
    '    $exit = $LASTEXITCODE',
    '    $done = Select-String -Path $con -Pattern \'SYNTH_ONLY_DONE\' -Quiet -ErrorAction SilentlyContinue',
    '    Write-Output "exit=$exit done=$done"',
    '    if ($done) { Write-Output "SYNTH_OK try=$try"; break }',
    '    Write-Output "---- failure tail ----"',
    '    Get-Content $con -Tail 12 | ForEach-Object { Write-Output $_ }',
    '    Start-Sleep -Seconds 5',
    '}',
    '',
]

path = r'D:\FPGA\prj\project_11\out\r3c_synth_retry.ps1'
with io.open(path, 'w', encoding='utf-8-sig', newline='\r\n') as f:
    f.write('\n'.join(LINES))

data = open(path, 'rb').read()
print('written bytes=%d BOM=%02X%02X%02X' % (len(data), data[0], data[1], data[2]))
