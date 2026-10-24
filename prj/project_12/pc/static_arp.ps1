# =============================================================================
# static_arp.ps1 -- prj12 P1: PC 侧静态 ARP 绑定（绕过 ARP 解析/避免被带跑）
# 为什么需要: P1 两板 MAC 相同、且回显帧从对端板网口出去；PC 侧先用静态 ARP 把
#   "板卡 IP -> 板卡 MAC"钉死，可以让发送侧完全不依赖 ARP 应答，把变量减到一个。
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -DryRun
#   powershell -NoProfile -ExecutionPolicy Bypass -File pc\static_arp.ps1 -Apply     # 需要管理员
#   ... -Remove
# 退出码: 0 = 成功/dry-run 自洽；1 = 失败（非管理员/网卡名错）
# =============================================================================
param(
    [string]$BoardIp = '192.168.1.10',
    [string]$BoardMac = '00-11-22-33-44-55',
    [string]$InterfaceAlias = 'Ethernet',
    [switch]$Remove,
    [switch]$Apply,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$dry = -not $Apply

function Say([string]$s) { Write-Output $s }

# 归一化 MAC：接受 00:11:.. / 00-11-.. / 0011.2233.4455
$mac = $BoardMac -replace '[:\.\-]', ''
if ($mac -notmatch '^[0-9A-Fa-f]{12}$') { Say "FAIL: bad MAC '$BoardMac'"; exit 1 }
$mac = ($mac -replace '(..)(?=.)', '$1-').ToLower()

Say "=== static_arp ==="
Say "board ip : $BoardIp"
Say "board mac: $mac"
Say "iface    : $InterfaceAlias"
Say "action   : $(if ($Remove) { 'REMOVE' } else { 'ADD (permanent)' })"

$nic = Get-NetAdapter -Name $InterfaceAlias -ErrorAction SilentlyContinue
if (-not $nic) {
    Say "FAIL: 网卡 '$InterfaceAlias' 不存在。下面列出候选："
    Get-NetAdapter | ForEach-Object { Say ("  - '{0}'  {1}  {2}" -f $_.Name, $_.MacAddress, $_.Status) }
    Say "提示: 用 -InterfaceAlias '<上面列出的 Name>' 指定。"
    exit 1
}
Say "nic      : $($nic.Name)  mac=$($nic.MacAddress)  status=$($nic.Status)  ifIndex=$($nic.ifIndex)"

$existing = Get-NetNeighbor -InterfaceIndex $nic.ifIndex -IPAddress $BoardIp -ErrorAction SilentlyContinue
if ($existing) { Say "current  : $($existing.LinkLayerAddress) state=$($existing.State)" }
else { Say "current  : (none)" }

if ($Remove) {
    $cmd = "Remove-NetNeighbor -InterfaceIndex $($nic.ifIndex) -IPAddress $BoardIp -Confirm:`$false"
} else {
    $cmd = "New-NetNeighbor -InterfaceIndex $($nic.ifIndex) -IPAddress $BoardIp -LinkLayerAddress '$mac' -State Permanent -ErrorAction Stop"
}
Say "CMD: $cmd"

if ($dry) {
    Say "DRY_RUN: 未改系统邻居表（加 -Apply 才执行，且需要管理员）"
    Say "STATIC_ARP_RESULT: DRY_RUN_OK"
    exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Say "FAIL: 需要管理员权限"; exit 1 }
try {
    if ($Remove) { Remove-NetNeighbor -InterfaceIndex $nic.ifIndex -IPAddress $BoardIp -Confirm:$false -ErrorAction Stop }
    else {
        if ($existing) { Remove-NetNeighbor -InterfaceIndex $nic.ifIndex -IPAddress $BoardIp -Confirm:$false -ErrorAction SilentlyContinue }
        New-NetNeighbor -InterfaceIndex $nic.ifIndex -IPAddress $BoardIp -LinkLayerAddress $mac -State Permanent -ErrorAction Stop | Out-Null
    }
} catch {
    Say "FAIL: $($_.Exception.Message)"
    exit 1
}
$after = Get-NetNeighbor -InterfaceIndex $nic.ifIndex -IPAddress $BoardIp -ErrorAction SilentlyContinue
Say "after    : $($after.LinkLayerAddress) state=$($after.State)"
if (-not $after) { Say "FAIL: 邻居项未写入"; exit 1 }
Say "STATIC_ARP_RESULT: PASS"
exit 0
