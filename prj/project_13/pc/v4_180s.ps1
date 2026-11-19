# =============================================================================
# v4_180s.ps1 — prj13 V4 连续 >=180 s 窗口（接收侧一条命令跑完）
#   纪律：**单次连续窗口，禁分块循环**（执行单 T8 / 上板验证执行单 §4-4）。
#   流程：起抓包(后台) -> 等 5 s -> twin_send 发包 -> 等抓包结束 -> 审计 + 判定
#   用法：
#     powershell -NoProfile -ExecutionPolicy Bypass -File v4_180s.ps1 `
#       -Pair A -OutDir D:\FPGA\prj\project_13\out\evidence_20261119_p13_v4 `
#       -Seconds 185 -Count 18000 -Len 100 -IntervalMs 10 -RunId 0x20 `
#       -Port 47001 -ExpectDstIp 10.10.0.1
#   退出码：0=PASS 1=FAIL 2=参数/环境 3=抓包失败
# =============================================================================
param(
  [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$Pair,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$true)][string]$DstIp,
  [int]$Seconds = 185,
  [int]$Count = 18000,
  [int]$Len = 100,
  [int]$IntervalMs = 10,
  [string]$RunId = '0x20',
  [int]$Port = 47001,
  [string[]]$ExpectDstIp = @(),
  [string]$Iface = '以太网',
  [int]$WarmupSec = 5
)
$ErrorActionPreference = 'Continue'
$env:PYTHONUTF8 = '1'
$proj = 'D:\FPGA\prj\project_13'
$capPy = Join-Path $proj 'pc\npcap_capture.py'
$sendPy = Join-Path $proj 'pc\twin_send.py'
$recvPy = Join-Path $proj 'pc\twin_recv.py'
$auditPy = Join-Path $proj 'pc\p13_pcap_audit.py'

$pcapDir = Join-Path $OutDir 'pcap'
$logDir  = Join-Path $OutDir 'log'
New-Item -ItemType Directory -Force -Path $pcapDir, $logDir | Out-Null
$stamp = Get-Date -Format 'HHmmss'
$pcap = Join-Path $pcapDir ("v4_t8_180s_{0}_{1}_{2}.pcap" -f $Pair, $RunId, $stamp)
$capLog = Join-Path $logDir ("v4_t8_capture_{0}.log" -f $stamp)
$sendLog = Join-Path $logDir ("v4_t8_send_{0}.log" -f $stamp)

# 网卡名解析成 GUID（Npcap 描述可能为空）
$ifSel = $Iface
$na = Get-NetAdapter -Name $Iface -ErrorAction SilentlyContinue
if ($na) { $ifSel = ($na.InterfaceGuid -replace '[{}]', '') }
Write-Output ("IFACE: '$Iface' -> $ifSel  link=" + $(if ($na) { $na.LinkSpeed } else { 'n/a' }))

# 时长自检：发包时长必须 >= Seconds - Warmup，否则窗口后半段是空的
$sendDur = [math]::Round(($Count * $IntervalMs) / 1000.0, 1)
Write-Output ("PLAN: capture=${Seconds}s  send count=$Count len=$Len interval=${IntervalMs}ms  send_dur~${sendDur}s")
if ($sendDur -lt ($Seconds - $WarmupSec - 5)) {
  Write-Output ("WARN: 发包时长 ${sendDur}s 短于捕获窗 ${Seconds}s —— 后半段将无流量，判据只能看已捕获部分")
}

Write-Output ("T0=" + (Get-Date -Format 'HH:mm:ss.fff'))
# --- 起抓包（后台，抓满 Seconds）---
$capArgs = @($capPy, '--iface', $ifSel, '--seconds', "$Seconds", '--out', $pcap)
$capProc = Start-Process -FilePath 'py' -ArgumentList $capArgs -PassThru -NoNewWindow `
           -RedirectStandardOutput $capLog -RedirectStandardError ($capLog + '.err')
Write-Output ("CAPTURE_PID: " + $capProc.Id)
Start-Sleep -Seconds $WarmupSec
Write-Output ("T1_send_start=" + (Get-Date -Format 'HH:mm:ss.fff'))

# --- 发包（阻塞）---
$sendArgs = @($sendPy, '--pair', $Pair, '--dst-ip', $DstIp, '--dst-port', "$Port",
              '--count', "$Count", '--len', "$Len",
              '--interval-ms', "$IntervalMs", '--run-id', $RunId)
& py @sendArgs 2>&1 | Tee-Object -FilePath $sendLog | Select-String -Pattern 'SEND_OK|FAIL|frames' | Select-Object -First 4 | ForEach-Object { "  " + $_.Line.Trim() }
Write-Output ("T2_send_done=" + (Get-Date -Format 'HH:mm:ss.fff'))

# --- 等抓包结束 ---
$capProc | Wait-Process -Timeout ($Seconds + 60) -ErrorAction SilentlyContinue
if (-not $capProc.HasExited) { Write-Output "CAPTURE: 仍未退出（超时），强制停止"; Stop-Process -Id $capProc.Id -Force -ErrorAction SilentlyContinue }
Write-Output ("T3_capture_done=" + (Get-Date -Format 'HH:mm:ss.fff'))
Get-Content $capLog -Tail 3 -ErrorAction SilentlyContinue | ForEach-Object { "  " + $_ }
if (-not (Test-Path $pcap)) { Write-Output "CAPTURE_RESULT: FAIL（无 pcap）"; exit 3 }
Write-Output ("CAPTURE_SHA256: " + (Get-FileHash $pcap -Algorithm SHA256).Hash.ToLower())

# --- 判定 1：字节级审计（判据1/3/4）---
Write-Output "--- AUDIT ---"
$auditArgs = @($auditPy, '--pcap', $pcap, '--port', "$Port",
               '--json', ($pcap -replace '\.pcap$', '.audit.json'))
foreach ($ip in $ExpectDstIp) { $auditArgs += @('--allow-dst', $ip) }
$boardMac = if ($Pair -eq 'A') { '02:00:00:00:0a:01' } else { '02:00:00:00:0b:01' }
$auditArgs += @('--src-mac', $boardMac)
$auditOut = & py @auditArgs 2>&1
$auditOut | ForEach-Object { "  " + $_ }
$auditVerdict = ($auditOut | Select-String -Pattern 'VERDICT').Line
$auditPass = ($auditVerdict -match 'VERDICT\s*:\s*PASS')

# --- 判定 2：twin_recv 载荷/计数判据 ---
Write-Output "--- TWIN_RECV ---"
$recvArgs = @($recvPy, '--from-pcap', $pcap, '--pair', $Pair, '--port', "$Port",
              '--expect-count', "$Count", '--expect-len', "$Len", '--expect-run-id', $RunId, '--no-bcast')
foreach ($ip in $ExpectDstIp) { $recvArgs += @('--expect-dst-ip', $ip) }
$recvOut = & py @recvArgs 2>&1
$recvOut | Select-Object -Last 12 | ForEach-Object { "  " + $_ }
$recvPass = -not ($recvOut -match '(?m)^\s*FAIL')

Write-Output ("AUDIT_PASS: " + $auditPass)
Write-Output ("RECV_PASS : " + $recvPass)
if ($auditPass -and $recvPass) { Write-Output 'V4_180S_RESULT: PASS'; exit 0 }
Write-Output 'V4_180S_RESULT: FAIL'
exit 1
