# rate_sweep_A.ps1 — A 侧可持续入向速率扫描（串口计数差分，快，不用 ILA）
$ErrorActionPreference = 'Continue'
$env:PYTHONUTF8 = '1'
Set-Location D:\FPGA\prj\project_13

function Read-Counters {
  $sp = New-Object System.IO.Ports.SerialPort 'COM5',9600,'None',8,'One'
  $sp.ReadTimeout = 150
  $res = $null
  try {
    $sp.Open(); $sp.DiscardInBuffer(); $sp.Write('I'); Start-Sleep -Milliseconds 250
    $sw = [Diagnostics.Stopwatch]::StartNew(); $sb = New-Object Text.StringBuilder
    while ($sw.ElapsedMilliseconds -lt 900) {
      try { $c = $sp.ReadExisting(); if ($c) { [void]$sb.Append($c) } } catch {}
      Start-Sleep -Milliseconds 20
    }
    $t = ($sb.ToString() -replace "`r?`n", ' ').Trim()
    if ($t -match 'wr=(\d+)\s+rd=(\d+)\s+drop=(\d+)') {
      $res = @{ wr = [int]$Matches[1]; rd = [int]$Matches[2]; drop = [int]$Matches[3] }
    }
  } catch {}
  try { if ($sp.IsOpen) { $sp.Close() } } catch {}
  return $res
}

$rows = @()
foreach ($iv in 20, 10, 5, 2, 1) {
  $n = 300
  $before = Read-Counters
  Start-Sleep -Milliseconds 300
  $t0 = Get-Date
  $out = & py pc\twin_send.py --pair A --dst-ip 10.10.0.2 --dst-port 47001 --count $n --len 100 --interval-ms $iv --run-id 0x40 2>&1
  $dt = ((Get-Date) - $t0).TotalSeconds
  Start-Sleep -Milliseconds 800
  $after = Read-Counters
  if ($before -and $after) {
    $dwr = $after.wr - $before.wr
    $drd = $after.rd - $before.rd
    $ddp = $after.drop - $before.drop
    $fps = if ($dt -gt 0) { [math]::Round($n / $dt, 1) } else { 0 }
    $row = [pscustomobject]@{
      interval_ms = $iv; sent = $n; secs = [math]::Round($dt, 2); host_fps = $fps
      d_wr = $dwr; d_rd = $drd; d_drop = $ddp
      drop_pct = if ($n -gt 0) { [math]::Round(100.0 * $ddp / $n, 1) } else { 0 }
      wire_mbps = if ($dt -gt 0) { [math]::Round($n * 142 * 8 / $dt / 1e6, 1) } else { 0 }
    }
    $rows += $row
    Write-Output ("  {0,3} ms | 发 {1} | {2,5}s | host {3,7} fps | {4,5} Mbps | wr+{5,4} rd+{6,4} drop+{7,4} ({8}%)" -f $iv, $n, $row.secs, $fps, $row.wire_mbps, $dwr, $drd, $ddp, $row.drop_pct)
  } else {
    Write-Output ("  {0} ms : 计数读取失败" -f $iv)
  }
  Start-Sleep -Milliseconds 500
}
$rows | Export-Csv -Path 'D:\FPGA\prj\project_13\out\evidence_20261119_p13_v4\log\tput_sweep_A.csv' -NoTypeInformation -Encoding UTF8
Write-Output "CSV: out\evidence_20261119_p13_v4\log\tput_sweep_A.csv"
