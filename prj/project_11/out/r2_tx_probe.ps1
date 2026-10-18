# =============================================================================
# r2_tx_probe.ps1 - prj11 R2 round2d: PC-side TX frame zero-cost triage (NO board access)
#
# Purpose: distinguish three failure shapes of "PC pings but board reply never arrives":
#   NO_FRAME       : ping sent, PC NIC RX counters do NOT move (board emits nothing / not wired to PC)
#   BAD_FRAME      : PC NIC RX counters move (bytes/errors/discards) but ping gets no valid reply
#   COUNTER_STATIC : even TX/RX counters do not move at all (wrong adapter / stats unavailable / driver)
#   REPLY          : ping replies received (link+TX OK, this probe is not the bottleneck)
#
# Method: snapshot Get-NetAdapterStatistics -Name <adapter> + `netstat -e` BEFORE,
#         run `ping -n <Count>`, snapshot AFTER, compute deltas, classify, print markers.
#         Dry-run (default) does NOT send ping: it only validates adapter/stats/tools and prints the plan.
#         Also reports optional capture tooling (pktmon / npcap tshark / dumpcap) availability.
#
# Markers (for log parsing):
#   R2_TXPROBE_BASELINE / R2_TXPROBE_DELTA / R2_TXPROBE_CAPS / R2_TXPROBE_CLASS
#   R2_TXPROBE: <class> <detail>       (one line per run)
#   R2_TXPROBE_RESULT: PASS|FAIL|SKIP|NOT_OBTAINED <detail>
#   R2_TXPROBE_SELFTEST: PASS n/n | FAIL ...
# Exit codes: -Run: 0=REPLY(PASS) 1=NO_FRAME/BAD_FRAME 2=COUNTER_STATIC/NOT_OBTAINED 3=usage/self-test fail
#             dry-run: 0 OK (SKIP), 2 stats unavailable
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File r2_tx_probe.ps1                 # dry-run
#   powershell ... -File r2_tx_probe.ps1 -Run                                           # ping + classify
#   powershell ... -File r2_tx_probe.ps1 -Run -AdapterName '以太网' -TargetIp 192.168.1.10 -Count 4
#   powershell ... -File r2_tx_probe.ps1 -SelfTest                                      # classifier selftest
#
# Notes:
#   * read-only on the board; only PC-side counters + ICMP.
#   * `netstat -e` parsing is locale-agnostic: it takes the first 5 numeric "recv send" pairs in order
#     (bytes / unicast / non-unicast / discards / errors). If parsing fails, adapter stats are used alone.
#   * For packet capture (optional, needs admin): see R2_TXPROBE_CAPS recommendations.
# =============================================================================

[CmdletBinding()]
param(
    [string]$AdapterName = "以太网",
    [string]$TargetIp = "192.168.1.10",
    [int]$Count = 4,
    [int]$WaitTimeoutMs = 900,
    [switch]$Run,
    [switch]$SelfTest,
    [string]$OutDir = "",
    [string]$Tag = "txprobe"
)

$ErrorActionPreference = "Stop"
$script:OutRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutDir) { $OutDir = Join-Path $script:OutRoot ("evidence_" + (Get-Date -Format "yyyy-MM-dd")) }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$script:Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogPath = Join-Path $OutDir ("R2_txprobe_" + $script:Stamp + ".log")
$script:Lines = New-Object System.Collections.ArrayList

function Write-Raw {
    param([string]$Text = "", [string]$Color = "")
    [void]$script:Lines.Add($Text)
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}
function Write-Log {
    param([string]$Message, [string]$Color = "")
    Write-Raw ("[" + (Get-Date -Format "HH:mm:ss") + "] " + $Message) $Color
}
function Write-Section {
    param([string]$Title)
    Write-Raw ""
    Write-Raw ("=" * 78) "Cyan"
    Write-Raw ("== " + $Title) "Cyan"
    Write-Raw ("=" * 78) "Cyan"
}
function Save-Log {
    try {
        [System.IO.File]::WriteAllLines($script:LogPath, [string[]]$script:Lines.ToArray(), (New-Object System.Text.UTF8Encoding($true)))
        Write-Host ("日志已落盘: " + $script:LogPath + "  (" + $script:Lines.Count + " lines, UTF-8 BOM)") -ForegroundColor Cyan
    } catch {
        Write-Host ("WARN: 日志落盘失败: " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Get-AdapterStats {
    param([string]$Name)
    try {
        $s = Get-NetAdapterStatistics -Name $Name -ErrorAction Stop
        return [pscustomobject]@{
            Ok                    = $true
            Adapter               = [string]$s.Name
            ReceivedBytes         = [int64]$s.ReceivedBytes
            ReceivedUnicast       = [int64]$s.ReceivedUnicastPackets
            ReceivedMulticast     = [int64]$s.ReceivedMulticastPackets
            ReceivedBroadcast     = [int64]$s.ReceivedBroadcastPackets
            ReceivedErrors        = [int64]$s.ReceivedErrors
            ReceivedDiscarded     = [int64]$s.ReceivedDiscardedPackets
            OutboundBytes         = [int64]$s.OutboundBytes
            OutboundPackets       = [int64]$s.OutboundPackets
            OutboundErrors        = [int64]$s.OutboundErrors
            OutboundDiscarded     = [int64]$s.OutboundDiscardedPackets
        }
    } catch {
        return [pscustomobject]@{ Ok = $false; Err = $_.Exception.Message }
    }
}

function Get-NetStatE {
    try {
        $raw = (netstat -e) 2>&1 | Out-String
    } catch {
        return [pscustomobject]@{ Ok = $false; Err = $_.Exception.Message }
    }
    $pairs = New-Object System.Collections.ArrayList
    foreach ($ln in ($raw -split "`r?`n")) {
        if ($ln -match '^\s*[^\d].*?\s(\d+)\s+(\d+)\s*$') {
            [void]$pairs.Add([pscustomobject]@{ Recv = [int64]$Matches[1]; Sent = [int64]$Matches[2] })
        }
        if ($pairs.Count -ge 5) { break }
    }
    if ($pairs.Count -lt 5) {
        return [pscustomobject]@{ Ok = $false; Err = ("parse failed (pairs=" + $pairs.Count + ")") }
    }
    return [pscustomobject]@{
        Ok             = $true
        ReceivedBytes  = $pairs[0].Recv
        SentBytes      = $pairs[0].Sent
        UnicastRecv    = $pairs[1].Recv
        UnicastSent    = $pairs[1].Sent
        NonUnicastRecv = $pairs[2].Recv
        NonUnicastSent = $pairs[2].Sent
        DiscardsRecv   = $pairs[3].Recv
        DiscardsSent   = $pairs[3].Sent
        ErrorsRecv     = $pairs[4].Recv
        ErrorsSent     = $pairs[4].Sent
    }
}

function Get-Caps {
    $caps = [ordered]@{}
    try {
        $s = Get-Service -Name npcap -ErrorAction Stop
        $caps["npcap_service"] = [string]$s.Status
    } catch { $caps["npcap_service"] = "absent" }
    foreach ($t in @("tshark", "dumpcap", "pktmon")) {
        $c = Get-Command $t -ErrorAction SilentlyContinue
        if ($null -ne $c) { $caps[$t] = [string]$c.Source } else { $caps[$t] = "absent" }
    }
    return $caps
}

function Format-CounterDelta {
    param([string]$Label, [int64]$Before, [int64]$After)
    return ("{0} {1}->{2} (+{3})" -f $Label, $Before, $After, ($After - $Before))
}

# Pure classifier: given adapter before/after + netstat before/after + ping replies -> class/reason.
# Kept side-effect-free so -SelfTest can exercise it with synthetic numbers.
function Get-TxClass {
    param(
        $AdapterBefore, $AdapterAfter, $NetBefore, $NetAfter, [int]$PingReplies
    )
    if ($null -eq $AdapterBefore -or $null -eq $AdapterAfter -or (-not $AdapterBefore.Ok) -or (-not $AdapterAfter.Ok)) {
        return [pscustomobject]@{ Class = "COUNTER_STATIC"; Detail = "adapter statistics unavailable; cannot classify (统计不可用=计数不动)" }
    }
    $rxB = [int64]$AdapterAfter.ReceivedBytes - [int64]$AdapterBefore.ReceivedBytes
    $rxP = ([int64]$AdapterAfter.ReceivedUnicast + [int64]$AdapterAfter.ReceivedMulticast + [int64]$AdapterAfter.ReceivedBroadcast) -
           ([int64]$AdapterBefore.ReceivedUnicast + [int64]$AdapterBefore.ReceivedMulticast + [int64]$AdapterBefore.ReceivedBroadcast)
    $rxErr = [int64]$AdapterAfter.ReceivedErrors - [int64]$AdapterBefore.ReceivedErrors
    $rxDis = [int64]$AdapterAfter.ReceivedDiscarded - [int64]$AdapterBefore.ReceivedDiscarded
    $txB = [int64]$AdapterAfter.OutboundBytes - [int64]$AdapterBefore.OutboundBytes
    $txP = [int64]$AdapterAfter.OutboundPackets - [int64]$AdapterBefore.OutboundPackets
    $netRx = $null
    $netTx = $null
    if ($null -ne $NetBefore -and $null -ne $NetAfter -and $NetBefore.Ok -and $NetAfter.Ok) {
        $netRx = [int64]$NetAfter.ReceivedBytes - [int64]$NetBefore.ReceivedBytes
        $netTx = [int64]$NetAfter.SentBytes - [int64]$NetBefore.SentBytes
    }
    $detail = ("adapter RX bytes+{0} pkts+{1} err+{2} disc+{3}; TX bytes+{4} pkts+{5}; netstat RX+{6} TX+{7}; ping replies={8}" -f
        $rxB, $rxP, $rxErr, $rxDis, $txB, $txP, $(if ($null -eq $netRx) { "n/a" } else { $netRx }), $(if ($null -eq $netTx) { "n/a" } else { $netTx }), $PingReplies)
    if ($PingReplies -gt 0) {
        return [pscustomobject]@{ Class = "REPLY"; Detail = ("ping replies=" + $PingReplies + "/" + $Count + "; " + $detail) }
    }
    if ($rxErr -gt 0 -or $rxDis -gt 0 -or $rxB -gt 0 -or $rxP -gt 0 -or ($null -ne $netRx -and $netRx -gt 0)) {
        return [pscustomobject]@{ Class = "BAD_FRAME"; Detail = ("RX counters moved but no valid ICMP reply (坏帧/无效帧); " + $detail) }
    }
    if ($txB -gt 0 -or $txP -gt 0 -or ($null -ne $netTx -and $netTx -gt 0)) {
        return [pscustomobject]@{ Class = "NO_FRAME"; Detail = ("ping TX counters moved but PC RX counters stayed 0 => board emitted nothing (完全无帧); " + $detail) }
    }
    return [pscustomobject]@{ Class = "COUNTER_STATIC"; Detail = ("TX/RX counters did NOT move at all => counter/driver/adapter issue, not board TX (计数不动); " + $detail) }
}

function Invoke-SelfTest {
    Write-Section "r2_tx_probe 自检（分类器纯函数 4 例）"
    $A0 = [pscustomobject]@{ Ok = $true; ReceivedBytes = 1000; ReceivedUnicast = 5; ReceivedMulticast = 0; ReceivedBroadcast = 0;
        ReceivedErrors = 0; ReceivedDiscarded = 0; OutboundBytes = 2000; OutboundPackets = 10; OutboundErrors = 0; OutboundDiscarded = 0 }
    $N0 = [pscustomobject]@{ Ok = $true; ReceivedBytes = 900; SentBytes = 1800 }
    $cases = @(
        @{ Name = "no-frame"; A = $A0; Ad = ([pscustomobject]@{ Ok = $true; ReceivedBytes = 1000; ReceivedUnicast = 5; ReceivedMulticast = 0; ReceivedBroadcast = 0;
                ReceivedErrors = 0; ReceivedDiscarded = 0; OutboundBytes = 2300; OutboundPackets = 14; OutboundErrors = 0; OutboundDiscarded = 0 });
           N = $N0; Nd = ([pscustomobject]@{ Ok = $true; ReceivedBytes = 900; SentBytes = 2100 }); Replies = 0; Expect = "NO_FRAME" },
        @{ Name = "bad-frame"; A = $A0; Ad = ([pscustomobject]@{ Ok = $true; ReceivedBytes = 1120; ReceivedUnicast = 6; ReceivedMulticast = 0; ReceivedBroadcast = 0;
                ReceivedErrors = 1; ReceivedDiscarded = 0; OutboundBytes = 2300; OutboundPackets = 14; OutboundErrors = 0; OutboundDiscarded = 0 });
           N = $N0; Nd = ([pscustomobject]@{ Ok = $true; ReceivedBytes = 1020; SentBytes = 2100 }); Replies = 0; Expect = "BAD_FRAME" },
        @{ Name = "counter-static"; A = $A0; Ad = $A0;
           N = $N0; Nd = $N0; Replies = 0; Expect = "COUNTER_STATIC" },
        @{ Name = "reply"; A = $A0; Ad = ([pscustomobject]@{ Ok = $true; ReceivedBytes = 1296; ReceivedUnicast = 9; ReceivedMulticast = 0; ReceivedBroadcast = 0;
                ReceivedErrors = 0; ReceivedDiscarded = 0; OutboundBytes = 2300; OutboundPackets = 14; OutboundErrors = 0; OutboundDiscarded = 0 });
           N = $N0; Nd = ([pscustomobject]@{ Ok = $true; ReceivedBytes = 1196; SentBytes = 2100 }); Replies = 4; Expect = "REPLY" }
    )
    $pass = 0
    $i = 0
    foreach ($c in $cases) {
        $i++
        $r = Get-TxClass -AdapterBefore $c.A -AdapterAfter $c.Ad -NetBefore $c.N -NetAfter $c.Nd -PingReplies $c.Replies
        $ok = ($r.Class -eq $c.Expect)
        if ($ok) { $pass++ }
        Write-Log ("SELFTEST_CASE {0} {1}: expect {2} -> {3}  {4}" -f $i, $c.Name, $c.Expect, $r.Class, $(if ($ok) { "OK" } else { "MISMATCH" })) $(if ($ok) { "Green" } else { "Red" })
    }
    if ($pass -eq $cases.Count) {
        Write-Raw ("R2_TXPROBE_SELFTEST: PASS " + $pass + "/" + $cases.Count) "Green"
        return 0
    }
    Write-Raw ("R2_TXPROBE_SELFTEST: FAIL " + $pass + "/" + $cases.Count) "Red"
    return 3
}

# ---------------- main ----------------
Write-Raw ("=" * 78) "Cyan"
Write-Raw "r2_tx_probe.ps1 - R2 round2d PC-side TX frame triage (NO board access)" "Cyan"
Write-Raw ("模式: " + $(if ($Run) { "RUN（会发 ping）" } else { "DRY-RUN（不发 ping，只读统计+打印计划）" }) + "   adapter='" + $AdapterName + "' target=" + $TargetIp + " count=" + $Count) "Cyan"
Write-Raw ("工作目录: " + $script:OutRoot)
Write-Raw ("日志: " + $script:LogPath)
Write-Raw ("=" * 78) "Cyan"

if ($SelfTest) {
    $rc = Invoke-SelfTest
    Save-Log
    exit $rc
}

$caps = Get-Caps
Write-Section "PC 侧环境与统计快照（只读）"
$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)
Write-Log ("网卡列表: " + (($adapters | ForEach-Object { $_.Name + "(" + $_.Status + "," + $_.LinkSpeed + ")" }) -join "; "))
$ab = Get-AdapterStats $AdapterName
$nb = Get-NetStatE
if (-not $ab.Ok) {
    Write-Log ("WARN: Get-NetAdapterStatistics -Name '" + $AdapterName + "' 失败: " + $ab.Err) "Yellow"
    Write-Log "提示: 用 -AdapterName 指定真实网卡名（Get-NetAdapter 可列出）" "Yellow"
} else {
    Write-Log ("R2_TXPROBE_BASELINE_ADAPTER: " + $ab.Adapter + " ReceivedBytes=" + $ab.ReceivedBytes + " Unicast=" + $ab.ReceivedUnicast +
        " Multicast=" + $ab.ReceivedMulticast + " Broadcast=" + $ab.ReceivedBroadcast + " Err=" + $ab.ReceivedErrors +
        " Disc=" + $ab.ReceivedDiscarded + " OutBytes=" + $ab.OutboundBytes + " OutPkts=" + $ab.OutboundPackets)
}
if ($nb.Ok) {
    Write-Log ("R2_TXPROBE_BASELINE_NETSTAT: RX=" + $nb.ReceivedBytes + " TX=" + $nb.SentBytes + " RXpkts=" + $nb.UnicastRecv +
        " TXpkts=" + $nb.UnicastSent + " DiscRX=" + $nb.DiscardsRecv + " ErrRX=" + $nb.ErrorsRecv)
} else {
    Write-Log ("WARN: netstat -e 解析失败(" + $nb.Err + ") ⇒ 只用 adapter 统计分类") "Yellow"
}
$capLines = @()
foreach ($k in $caps.Keys) { $capLines += ($k + "=" + $caps[$k]) }
Write-Log ("R2_TXPROBE_CAPS: " + ($capLines -join " "))
$captureHint = ""
if ($caps["npcap_service"] -ne "absent" -and $caps["tshark"] -ne "absent") {
    $captureHint = '可选混杂抓包(需管理员): tshark -i <iface> -f "ether host 00:11:22:33:44:55" -w R2_tx.pcap'
} elseif ($caps["pktmon"] -ne "absent") {
    $captureHint = "可选抓包(需管理员): pktmon start --capture --pkt-size 0 --comp nics ; pktmon stop ; pktmon etl2txt PktMon.etl -o R2_tx.txt"
} else {
    $captureHint = "无可用的 npcap/tshark/pktmon ⇒ 不做抓包，只用 PC 计数三分类"
}
Write-Log ("R2_TXPROBE_CAPTURE: " + $captureHint)

if (-not $Run) {
    Write-Section "DRY-RUN 计划（不发 ping）"
    Write-Log "将执行: 记录 Get-NetAdapterStatistics + netstat -e 基线 → ping -n $Count -w $WaitTimeoutMs $TargetIp → 再取快照 → 三分类"
    Write-Log "分类口径: REPLY=收到回包; NO_FRAME=PC 发帧但 RX 计数不动(板未发); BAD_FRAME=RX 计数动但无有效回包; COUNTER_STATIC=TX/RX 都不动(统计/网卡问题)"
    if (-not $ab.Ok) {
        Write-Raw "R2_TXPROBE_RESULT: NOT_OBTAINED adapter statistics unavailable" "Yellow"
        Save-Log
        exit 2
    }
    Write-Raw "R2_TXPROBE_RESULT: SKIP (dry-run —— 未发 ping; 加 -Run 执行三分类)" "Yellow"
    Save-Log
    exit 0
}

# ---------------- -Run ----------------
Write-Section "RUN: 发 ping + 前后计数 delta + 三分类"
$ab = Get-AdapterStats $AdapterName
$nb = Get-NetStatE
$pingOut = ""
$pingReplies = -1
try {
    $pingOut = (ping -n $Count -w $WaitTimeoutMs $TargetIp) 2>&1 | Out-String
    $m = [regex]::Match($pingOut, "(?:Received|已接收)\s*=\s*(\d+)")
    if ($m.Success) { $pingReplies = [int]$m.Groups[1].Value } else { $pingReplies = 0 }
} catch {
    Write-Log ("WARN: ping 执行失败: " + $_.Exception.Message) "Yellow"
    $pingReplies = -1
}
$aa = Get-AdapterStats $AdapterName
$na = Get-NetStatE
if ($ab.Ok -and $aa.Ok) {
    Write-Log ("R2_TXPROBE_DELTA_ADAPTER: RX_BYTES+{0} RX_PKTS+{1} RX_ERR+{2} RX_DISC+{3} TX_BYTES+{4} TX_PKTS+{5}" -f
        ([int64]$aa.ReceivedBytes - [int64]$ab.ReceivedBytes),
        (([int64]$aa.ReceivedUnicast + [int64]$aa.ReceivedMulticast + [int64]$aa.ReceivedBroadcast) - ([int64]$ab.ReceivedUnicast + [int64]$ab.ReceivedMulticast + [int64]$ab.ReceivedBroadcast)),
        ([int64]$aa.ReceivedErrors - [int64]$ab.ReceivedErrors),
        ([int64]$aa.ReceivedDiscarded - [int64]$ab.ReceivedDiscarded),
        ([int64]$aa.OutboundBytes - [int64]$ab.OutboundBytes),
        ([int64]$aa.OutboundPackets - [int64]$ab.OutboundPackets))
}
if ($nb.Ok -and $na.Ok) {
    Write-Log ("R2_TXPROBE_DELTA_NETSTAT: RX_BYTES+{0} TX_BYTES+{1} RX_DISC+{2} RX_ERR+{3}" -f
        ([int64]$na.ReceivedBytes - [int64]$nb.ReceivedBytes), ([int64]$na.SentBytes - [int64]$nb.SentBytes),
        ([int64]$na.DiscardsRecv - [int64]$nb.DiscardsRecv), ([int64]$na.ErrorsRecv - [int64]$nb.ErrorsRecv))
}
$cls = Get-TxClass -AdapterBefore $ab -AdapterAfter $aa -NetBefore $nb -NetAfter $na -PingReplies $pingReplies
Write-Log ("R2_TXPROBE_CLASS: " + $cls.Class)
Write-Raw ("R2_TXPROBE: " + $cls.Class + " " + $cls.Detail) $(if ($cls.Class -eq "REPLY") { "Green" } else { "Yellow" })
switch ($cls.Class) {
    "REPLY" {
        Write-Raw ("R2_TXPROBE_RESULT: PASS " + $cls.Detail) "Green"
        Save-Log
        exit 0
    }
    "NO_FRAME" {
        Write-Raw ("R2_TXPROBE_RESULT: FAIL NO_FRAME " + $cls.Detail) "Red"
        Save-Log
        exit 1
    }
    "BAD_FRAME" {
        Write-Raw ("R2_TXPROBE_RESULT: FAIL BAD_FRAME " + $cls.Detail) "Red"
        Save-Log
        exit 1
    }
    default {
        Write-Raw ("R2_TXPROBE_RESULT: NOT_OBTAINED COUNTER_STATIC " + $cls.Detail) "Yellow"
        Save-Log
        exit 2
    }
}
