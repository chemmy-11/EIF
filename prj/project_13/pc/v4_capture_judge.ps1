# =============================================================================
# v4_capture_judge.ps1 — prj13 V4 接收侧：抓包窗口 + 字节级判定（一条命令一步）
#   用法（接收侧跑；发送侧同时用 twin_send.py 发包）：
#     powershell -NoProfile -ExecutionPolicy Bypass -File v4_capture_judge.ps1 `
#       -Pair A -Out D:\FPGA\prj\project_13\out\evidence_20261119_p13_v4\pcap\v4_t5_a2b.pcap `
#       -Seconds 10 -ExpectCount 3 -ExpectLen 100 -RunId 0x1 -Port 47001 -ExpectDstIp 10.10.0.1
#   判据：twin_recv.py 的 matched == --expect-count 且无 FAIL 行；另打印字节级摘要。
#   退出码：0=PASS  1=FAIL  2=参数/环境  3=抓包失败
# =============================================================================
param(
  [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$Pair,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Seconds = 10,
  [int]$ExpectCount = 3,
  [int]$ExpectLen = 100,
  [string]$RunId = '0x1',
  [int]$Port = 47001,
  [string[]]$ExpectDstIp = @(),
  [string]$Iface = '以太网',
  [switch]$Promisc,
  [switch]$NoBcast = $true,
  [switch]$AllowDup
)
$ErrorActionPreference = 'Continue'
$env:PYTHONUTF8 = '1'
$proj = 'D:\FPGA\prj\project_13'
$cap  = Join-Path $proj 'pc\npcap_capture.py'
$recv = Join-Path $proj 'pc\twin_recv.py'
$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

if (-not (Test-Path 'C:\Windows\System32\wpcap.dll')) { Write-Output 'FAIL: wpcap.dll 缺失（Npcap 运行时未装）'; exit 2 }

Write-Output ("T0=" + (Get-Date -Format 'HH:mm:ss.fff'))

# --- 0. 网卡选择：Npcap 的设备描述可能为空，按友好名匹配不到；
#        先用 Get-NetAdapter 把名字解析成 InterfaceGuid，再用 GUID 子串选。---
$ifSel = $Iface
$na = Get-NetAdapter -Name $Iface -ErrorAction SilentlyContinue
if ($na) {
  $ifSel = ($na.InterfaceGuid -replace '[{}]', '')
  Write-Output ("IFACE_RESOLVE: '$Iface' -> $ifSel (ifIndex=" + $na.ifIndex + ", link=" + $na.LinkSpeed + ")")
} else {
  Write-Output ("IFACE_RESOLVE: '$Iface' 不是本机网卡名，按子串直传")
}
Write-Output ("CAPTURE: iface=$ifSel seconds=$Seconds out=$Out")

# --- 1. 抓包（阻塞，抓满 Seconds）---
$capArgs = @($cap, '--iface', $ifSel, '--seconds', "$Seconds", '--out', $Out)
if ($Promisc) { $capArgs += '--promisc' }
& py @capArgs 2>&1 | Tee-Object -Variable capOut | Out-Null
$capOut | Select-String -Pattern 'CAP_|written|packets|ERROR|FAIL' | Select-Object -First 8 | ForEach-Object { "  " + $_.Line.Trim() }
if (-not (Test-Path $Out)) { Write-Output 'CAPTURE_RESULT: FAIL（未生成 pcap）'; exit 3 }
$fi = Get-Item $Out
Write-Output ("CAPTURE_RESULT: OK  bytes=" + $fi.Length)
Write-Output ("CAPTURE_SHA256: " + (Get-FileHash $Out -Algorithm SHA256).Hash.ToLower())
Write-Output ("T1=" + (Get-Date -Format 'HH:mm:ss.fff'))

# --- 2. 判定 ---
$recvArgs = @($recv, '--from-pcap', $Out, '--pair', $Pair, '--port', "$Port",
              '--expect-count', "$ExpectCount", '--expect-len', "$ExpectLen", '--expect-run-id', $RunId)
foreach ($ip in $ExpectDstIp) { $recvArgs += @('--expect-dst-ip', $ip) }
if ($NoBcast) { $recvArgs += '--no-bcast' }
if ($AllowDup) { $recvArgs += '--allow-dup' }

Write-Output ('JUDGE: ' + ($recvArgs -join ' '))
& py @recvArgs 2>&1 | Tee-Object -Variable recvOut | Out-Null
$recvOut | ForEach-Object { "  " + $_ }

$txt = ($recvOut -join "`n")
$matched = $null
$m = [regex]::Match($txt, 'matched\s*[=:]\s*(\d+)')
if ($m.Success) { $matched = [int]$m.Groups[1].Value }
$hasFail = $txt -match '(?m)^\s*FAIL'

Write-Output ("MATCHED: " + $(if ($null -ne $matched) { $matched } else { 'n/a' }) + " / EXPECTED: $ExpectCount")
if ($hasFail) { Write-Output 'V4_RESULT: FAIL'; exit 1 }
if ($null -ne $matched -and $matched -eq $ExpectCount) { Write-Output 'V4_RESULT: PASS'; exit 0 }
Write-Output 'V4_RESULT: FAIL（matched 不等于期望）'
exit 1
