# =============================================================================
# static_arp.ps1 -- prj13 P2 (v0.2): PC-side static ARP for the twin-board relay
#
# WHY (measured 2026-11-06, prj12 P1):
#   The board ARP/ICMP/UDP replies are all merged into stack_txd and pushed into
#   pump A -> Aurora (rtl/eth_ctrl.v:163-177, rtl/aurora_mem_bridge.v:657/808).
#   So even the ARP reply crosses the fiber to the PEER board and the sender PC
#   never gets it -> sendto() fails at the OS layer. A permanent neighbor entry
#   pins "board/peer IP -> board MAC" and removes ARP from the variable list.
#
# SCOPE: this script only touches the Windows neighbor table (netsh neighbors).
#   It does NOT change the adapter IP, MTU, firewall or the FPGA parameters.
#
# ADDRESS SCHEMES (see docs/M1_P2_<addr+arp>_v0.2 doc; ASCII-safe name below):
#   doc      : prj13/docs/M1_P2 address+ARP plan v0.2 (2026-11-08), section 1-3
#   handbook : ADJUDICATED plan (project owner decision 2026-11-08 20:40)
#              PC1 10.10.0.1 / PC2 10.10.0.2 / board A 10.10.0.11 / board B 10.10.0.12
#              boards 02:00:00:00:0A:01 / 02:00:00:00:0B:01        [DEFAULT]
#   protocol : historical protocol_v1.md 2.2  192.168.50.1/.2 + board .50.11/.50.12
#              (no longer the default; deliverable repo to sync at product stage)
#   p1       : P1 BASELINE BITSTREAM only -- 192.168.1.102 + 192.168.1.10,
#              MAC 00:11:22:33:44:55 (rtl hardcoded, aurora_mem_bridge.v:98-101)
#
# BITSTREAM GUARD (added after the 2026-11-08 20:40 decision):
#   handbook/protocol need a P2 bitstream -- the RTL address params are hardcoded.
#   Against the current P1 bitstream (=192.168.1.10) those addresses silently drop
#   frames, so the script always prints which bitstream the chosen scheme needs.
#
# USAGE (no board / no adapter needed -- -DryRun validates parameters only):
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair B -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -DryRun -Scheme protocol
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -DryRun -Scheme p1 -IfAlias "Ethernet"
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -IfAlias "Ethernet"
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -Apply -Remove -IfAlias "Ethernet"
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -BoardPcPair A -List
#   # full manual form (no preset):
#   ... -LocalIp 10.10.0.1 -PeerIp 10.10.0.2 -BoardIp 10.10.0.11 `
#       -BoardMac 02:00:00:00:0A:01 -IfAlias "Ethernet" -DryRun
#
# EXIT CODES: 0 = dry-run self-consistent / apply verified
#             1 = bad parameter / adapter or admin missing / netsh failed
# ASCII ONLY on purpose (PS 5.1 + GBK console safety, CI item 4).
# =============================================================================
[CmdletBinding()]
param(
    [ValidateSet('A', 'B', '')]
    [string]$BoardPcPair = '',

    [ValidateSet('handbook', 'protocol', 'p1')]
    [string]$Scheme = 'handbook',

    # Explicit overrides (win over the -BoardPcPair preset)
    [string]$LocalIp = '',
    [string]$PeerIp = '',
    [string]$BoardIp = '',
    [string]$BoardMac = '',
    [string]$PeerMac = '',

    # Accept either -IfAlias (new) or -InterfaceAlias (P1 back-compat)
    [string]$IfAlias = 'Ethernet',
    [string]$InterfaceAlias = '',

    [switch]$SkipPeerBinding,
    [switch]$Remove,
    [switch]$Apply,
    [switch]$DryRun,
    [switch]$List
)

$ErrorActionPreference = 'Stop'

function Say([string]$s) { Write-Output $s }

function Get-SchemePreset([string]$scheme, [string]$pair) {
    # MACs are board identity, not scheme identity -> same in protocol/handbook.
    $macA = '02:00:00:00:0A:01'
    $macB = '02:00:00:00:0B:01'
    $p = @{
        'protocol|A' = @{ Local = '192.168.50.1'; Peer = '192.168.50.2'; Board = '192.168.50.11'; BMac = $macA; PMac = $macB }
        'protocol|B' = @{ Local = '192.168.50.2'; Peer = '192.168.50.1'; Board = '192.168.50.12'; BMac = $macB; PMac = $macA }
        'handbook|A' = @{ Local = '10.10.0.1';     Peer = '10.10.0.2';     Board = '10.10.0.11';     BMac = $macA; PMac = $macB }
        'handbook|B' = @{ Local = '10.10.0.2';     Peer = '10.10.0.1';     Board = '10.10.0.12';     BMac = $macB; PMac = $macA }
        'p1|A'       = @{ Local = '192.168.1.102'; Peer = '192.168.1.102'; Board = '192.168.1.10';   BMac = '00:11:22:33:44:55'; PMac = '00:11:22:33:44:55' }
        'p1|B'       = @{ Local = '192.168.1.102'; Peer = '192.168.1.102'; Board = '192.168.1.10';   BMac = '00:11:22:33:44:55'; PMac = '00:11:22:33:44:55' }
    }
    $k = "$scheme|$pair"
    if (-not $p.ContainsKey($k)) { return $null }
    return $p[$k]
}

function Test-IPv4([string]$ip) {
    if ([string]::IsNullOrWhiteSpace($ip)) { return $false }
    $parts = $ip.Split('.')
    if ($parts.Count -ne 4) { return $false }
    foreach ($x in $parts) {
        if ($x -notmatch '^[0-9]{1,3}$') { return $false }
        if ([int]$x -gt 255) { return $false }
    }
    return $true
}

function Convert-Mac([string]$m) {
    if ([string]::IsNullOrWhiteSpace($m)) { return $null }
    $h = $m -replace '[:\.\-\s]', ''
    if ($h -notmatch '^[0-9A-Fa-f]{12}$') { return $null }
    $h = $h.ToLower()
    return ($h -replace '(..)(?=.)', '$1-')
}

function Test-IsAdmin() {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

# ------------------------------------------------------------------ parameter resolution
$effectiveAlias = $IfAlias
if (-not [string]::IsNullOrWhiteSpace($InterfaceAlias)) { $effectiveAlias = $InterfaceAlias }

$preset = $null
$usedPreset = $false
if (-not [string]::IsNullOrWhiteSpace($BoardPcPair)) {
    $preset = Get-SchemePreset $Scheme $BoardPcPair
    if ($null -eq $preset) { Say "FAIL: no preset for scheme='$Scheme' pair='$BoardPcPair'"; exit 1 }
    $usedPreset = $true
    if ([string]::IsNullOrWhiteSpace($LocalIp))   { $LocalIp = $preset.Local }
    if ([string]::IsNullOrWhiteSpace($PeerIp))    { $PeerIp = $preset.Peer }
    if ([string]::IsNullOrWhiteSpace($BoardIp))   { $BoardIp = $preset.Board }
    if ([string]::IsNullOrWhiteSpace($BoardMac))  { $BoardMac = $preset.BMac }
    if ([string]::IsNullOrWhiteSpace($PeerMac))   { $PeerMac = $preset.PMac }
} else {
    if ([string]::IsNullOrWhiteSpace($BoardIp) -and [string]::IsNullOrWhiteSpace($BoardMac)) {
        Say "FAIL: give -BoardPcPair A|B (preset) or explicit -BoardIp/-BoardMac"
        Say "      e.g. -BoardPcPair A -DryRun   (scheme=$Scheme)"
        exit 1
    }
}

# ------------------------------------------------------------------ validation (no board needed)
$errors = New-Object System.Collections.Generic.List[string]
if (-not (Test-IPv4 $BoardIp)) { $errors.Add("bad -BoardIp '$BoardIp'") }
if (-not [string]::IsNullOrWhiteSpace($PeerIp) -and -not (Test-IPv4 $PeerIp)) { $errors.Add("bad -PeerIp '$PeerIp'") }
if (-not [string]::IsNullOrWhiteSpace($LocalIp) -and -not (Test-IPv4 $LocalIp)) { $errors.Add("bad -LocalIp '$LocalIp'") }

$boardMacDashed = Convert-Mac $BoardMac
if ($null -eq $boardMacDashed) { $errors.Add("bad -BoardMac '$BoardMac' (want AA:BB:CC:DD:EE:FF / AA-BB-... / AABB.CCDD.EEFF)") }
$peerMacDashed = $null
if (-not [string]::IsNullOrWhiteSpace($PeerMac)) {
    $peerMacDashed = Convert-Mac $PeerMac
    if ($null -eq $peerMacDashed) { $errors.Add("bad -PeerMac '$PeerMac'") }
}
if ([string]::IsNullOrWhiteSpace($effectiveAlias)) { $errors.Add('-IfAlias is empty') }

$bindPeer = -not $SkipPeerBinding -and -not [string]::IsNullOrWhiteSpace($PeerIp)
$peerIsSelf = $false
if ($bindPeer -and -not [string]::IsNullOrWhiteSpace($LocalIp) -and $PeerIp -eq $LocalIp) {
    # Binding the PC's own IP to a board MAC would poison the local stack.
    $peerIsSelf = $true
    $bindPeer = $false
}
if ($bindPeer -and $BoardIp -eq $PeerIp) {
    Say "NOTE: peer ip equals board ip ($PeerIp) -> peer binding skipped (single entry)"
    $bindPeer = $false
}

Say "=== static_arp (prj13 P2 / v0.2) ==="
Say "scheme   : $Scheme"
Say "note     : scheme=handbook is the ADJUDICATED plan (project owner decision 2026-11-08 20:40);"
Say "           scheme=protocol is the historical protocol_v1.md 2.2 set;"
Say "           scheme=p1 is the P1 baseline bitstream set only."
switch ($Scheme) {
    'p1' {
        Say "BITSTREAM: p1 = P1 baseline bitstream (192.168.1.10 / 00:11:22:33:44:55)."
        Say "           Use it ONLY against the currently burned P1 bitstream -- the RTL hardcodes"
        Say "           those values (rtl/aurora_mem_bridge.v:98-101)."
    }
    'handbook' {
        Say "BITSTREAM: handbook requires a P2 bitstream -- the RTL address params must be the"
        Say "           adjudicated 10.10.0.x (BOARD_IP 10.10.0.11/.12, PEER_IP 10.10.0.2/.1)."
        Say "           Against a P1 bitstream (192.168.1.10) these entries silently drop frames."
    }
    'protocol' {
        Say "BITSTREAM: protocol requires a P2 bitstream built with the 192.168.50.x addresses."
        Say "           NOT the default any more (adjudicated plan = handbook 10.10.0.x);"
        Say "           against a P1 bitstream (192.168.1.10) these entries silently drop frames."
    }
}
Say "preset   : $(if ($usedPreset) { "BoardPcPair=$BoardPcPair" } else { 'manual (no -BoardPcPair)' })"
Say "iface    : $effectiveAlias"
Say "local ip : $(if ([string]::IsNullOrWhiteSpace($LocalIp)) { '(not given)' } else { "$LocalIp  [informational only; this script does NOT set the adapter IP]" })"
Say "board ip : $BoardIp"
Say "board mac: $(if ($null -eq $boardMacDashed) { "(invalid) '$BoardMac'" } else { $boardMacDashed })"
Say "peer ip  : $(if ([string]::IsNullOrWhiteSpace($PeerIp)) { '(none)' } else { "$PeerIp  -> board mac (proxy-ARP form, needed so PC1<->PC2 frames hit board mac)" })"
Say "peer mac : $(if ($null -eq $peerMacDashed) { '(none)' } else { "$peerMacDashed  [informational: the peer board's MAC expected on the wire; NOT bound here]" })"
Say "action   : $(if ($Remove) { 'REMOVE' } else { 'ADD (permanent)' })"

if ($errors.Count -gt 0) {
    foreach ($e in $errors) { Say "FAIL: $e" }
    Say "STATIC_ARP_RESULT: FAIL"
    exit 1
}
if ($Scheme -ne 'p1' -and $usedPreset) {
    Say "NOTE     : board MACs 02:00:00:00:0A:01 / 02:00:00:00:0B:01 are board identity and are"
    Say "           UNCHANGED by the 2026-11-08 20:40 address decision (only the IP plan changed)."
}

# ------------------------------------------------------------------ adapter probe (optional in dry-run)
$nic = $null
if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
    $nic = Get-NetAdapter -Name $effectiveAlias -ErrorAction SilentlyContinue
}
if ($null -eq $nic) {
    Say "WARN: adapter '$effectiveAlias' not found on this machine."
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        Say "candidates:"
        Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { Say ("  - '{0}'  mac={1}  status={2}" -f $_.Name, $_.MacAddress, $_.Status) }
    } else {
        Say "candidates: Get-NetAdapter unavailable (NetAdapter module missing)"
    }
    if (-not $Apply) {
        Say "DRY_RUN: parameter validation only (no adapter, nothing changed) -> PASS"
        Say "STATIC_ARP_RESULT: DRY_RUN_OK (no adapter present; parameters self-consistent)"
        exit 0
    }
    Say "FAIL: -Apply needs a real adapter; set -IfAlias to one of the names above"
    Say "STATIC_ARP_RESULT: FAIL"
    exit 1
}
Say "nic      : $($nic.Name)  mac=$($nic.MacAddress)  status=$($nic.Status)  ifIndex=$($nic.ifIndex)"

function Get-NeighborState([string]$ip) {
    if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
        $n = Get-NetNeighbor -InterfaceIndex $nic.ifIndex -IPAddress $ip -ErrorAction SilentlyContinue
        if ($n) { return ("$($n.LinkLayerAddress) state=$($n.State)") }
        return '(none)'
    }
    return '(Get-NetNeighbor unavailable)'
}

# ------------------------------------------------------------------ build the netsh command list
$entries = New-Object System.Collections.Generic.List[object]
$entries.Add(@{ Ip = $BoardIp; Mac = $boardMacDashed; Role = 'board management ip' })
if ($bindPeer) {
    $entries.Add(@{ Ip = $PeerIp; Mac = $boardMacDashed; Role = 'peer pc ip (proxy-ARP form)' })
}

$cmds = New-Object System.Collections.Generic.List[string]
foreach ($e in $entries) {
    if ($Remove) {
        $cmds.Add("netsh interface ipv4 delete neighbors `"$effectiveAlias`" $($e.Ip)")
    } else {
        # delete first (idempotent re-bind); a missing entry is not an error
        $cmds.Add("netsh interface ipv4 delete neighbors `"$effectiveAlias`" $($e.Ip)")
        $cmds.Add("netsh interface ipv4 add neighbors `"$effectiveAlias`" $($e.Ip) $($e.Mac)")
    }
}

Say "---"
foreach ($e in $entries) {
    Say "entry    : $($e.Ip) -> $($e.Mac)   [$($e.Role)]"
    Say "current  : $(Get-NeighborState $e.Ip)"
}
if ($peerIsSelf) {
    Say "NOTE     : peer ip == local ip ($PeerIp) -> peer binding skipped (would poison the local stack;"
    Say "           this is the P1 shape where both PCs use .102 and only the board entry matters)"
}

# -List is read-only: report and stop before printing the would-be commands
if ($List) {
    Say "---"
    foreach ($e in $entries) { Say "neighbor : $($e.Ip)  $(Get-NeighborState $e.Ip)" }
    Say "STATIC_ARP_RESULT: LIST_OK"
    exit 0
}

Say "---"
$i = 0
foreach ($c in $cmds) { $i++; Say ("CMD[{0}] : {1}" -f $i, $c) }

$dry = $DryRun -or (-not $Apply)
if ($dry) {
    Say "---"
    Say "DRY_RUN: neighbor table NOT modified (add -Apply to execute; needs Administrator)"
    Say "verify-when-applied: Get-NetNeighbor -IPAddress $BoardIp | Format-Table InterfaceAlias,IPAddress,LinkLayerAddress,State"
    Say "STATIC_ARP_RESULT: DRY_RUN_OK"
    exit 0
}

if (-not (Test-IsAdmin)) {
    Say "FAIL: -Apply needs Administrator (Start-Process -Verb RunAs ... or an elevated shell)"
    Say "STATIC_ARP_RESULT: FAIL"
    exit 1
}

$failed = 0
$idx = 0
foreach ($c in $cmds) {
    $idx++
    # split the printed command back into argv, keeping quoted tokens intact
    $argv = [regex]::Matches($c, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') }
    $exe = $argv[0]
    $rest = @()
    if ($argv.Count -gt 1) { $rest = $argv[1..($argv.Count - 1)] }
    Say ("RUN[{0}] : {1}" -f $idx, $c)
    $out = & $exe @rest 2>&1
    $rc = $LASTEXITCODE
    foreach ($line in $out) { if ("$line".Trim() -ne '') { Say "  | $line" } }
    if ($rc -ne 0) {
        if ($c -match 'delete neighbors') {
            Say "  (delete returned $rc; a missing entry is expected/allowed)"
        } else {
            Say "  FAIL: rc=$rc"
            $failed++
        }
    }
}

Say "---"
$bad = 0
foreach ($e in $entries) {
    $st = Get-NeighborState $e.Ip
    Say "after    : $($e.Ip)  $st"
    if ($st -notmatch 'state=Permanent') { $bad++ }
}
if ($bad -gt 0) {
    Say "FAIL: $bad entr(y/ies) not Permanent after apply"
    Say "STATIC_ARP_RESULT: FAIL"
    exit 1
}
Say "STATIC_ARP_RESULT: PASS"
exit 0
