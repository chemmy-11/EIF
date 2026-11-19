# rate_sweep_A2.ps1 — A 侧入向速率扫描（用 twin_send 内部计时，排除进程启动开销）
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
foreach ($iv in 5, 1, 0.2, 0.05, 0) {
  $n = 2000
  $before = Read-Counters
  Start-Sleep -Milliseconds 300
  $out = & py pc\twin_send.py --pair A --dst-ip 10.10.0.2 --dst-port 47001 --count $n --len 100 --interval-ms $iv --run-id 0x41 2>&1
  $line = ($out | Select-String -Pattern 'SEND_OK').Line
  $sendMs = $null; $hostFps = $null; $hostMbps = $null
  if ($line -match 'in\s+([\d.]+)\s*ms\s*\(([\d.]+)\s*fps,\s*([\d.]+)\s*Mbps') {
    $sendMs = [double]$Matches[1]; $hostFps = [double]$Matches[2]; $hostMbps = [double]$Matches[3]
  }
  Start-Sleep -Milliseconds 1200
  $after = Read-Counters
  if ($before -and $after -and $sendMs) {
    $dwr = $after.wr - $before.wr
    $ddp = $after.drop - $before.drop
    $row = [pscustomobject]@{
      interval_ms = $iv; sent = $n; send_ms = $sendMs
      host_fps = [math]::Round($hostFps, 0); host_mbps_payload = [math]::Round($hostMbps, 1)
      board_wr = $dwr; board_drop = $ddp
      accept_pct = [math]::Round(100.0 * $dwr / $n, 1)
      board_fps = [math]::Round($dwr / ($sendMs / 1000.0), 0)
      board_mbps_wire = [math]::Round($dwr * 142 * 8 / ($sendMs / 1000.0) / 1e6, 2)
    }
    $rows += $row
    Write-Output ("  {0,5} ms | 发 {1} | 发送 {2,7} ms | 主机 {3,6} fps/{4,6} Mbps | 板上收 {5,5} 帧/{6,6} fps/{7,6} Mbps | 收下 {8,5}% | 丢 {9}" -f `
      $iv, $n, [math]::Round($sendMs,1), $row.host_fps, $row.host_mbps_payload, $dwr, $row.board_fps, $row.board_mbps_wire, $row.accept_pct, $ddp)
  } else {
    Write-Output ("  {0} ms : 数据不完整 (before={1} after={2} sendMs={3})" -f $iv, [bool]$before, [bool]$after, $sendMs)
  }
  Start-Sleep -Milliseconds 500
}
$rows | Export-Csv -Path 'D:\FPGA\prj\project_13\out\evidence_20261119_p13_v4\log\tput_sweep_A_v2.csv' -NoTypeInformation -Encoding UTF8
Write-Output "CSV: out\evidence_20261119_p13_v4\log\tput_sweep_A_v2.csv"
