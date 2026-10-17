# =============================================================================
# retire_s0_s8.ps1 - prj11 路线B 读侧收口: 新退役位流(rdfix) S0-S8 一键上板判据
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File retire_s0_s8.ps1          # 默认 DRY-RUN: 只打印完整计划
#   powershell ... -File retire_s0_s8.ps1 -Run -Bit <归档.bit> -Elf <归档.elf> `
#            [-Port COM5] [-SkipBurn] [-GreenBit <绿.bit> -GreenElf <绿.elf>] `
#            [-BuildLog <vivado构建日志>] [-ExpectBitHash8 xxxxxxxx] [-ExpectElfHash8 xxxxxxxx] `
#            [-NicAlias 以太网] [-Python py] [-EmitCsv <S8发射流csv>] `
#            [-AllowNonArchive] [-SkipS2IdentityPing] [-SkipS8]
#
# 设计口径(2026-10-17, 依据见 out\S0S8_DESIGN.md):
#   * 'd' 是【翻转】命令, 不是"置 DMA": 固件 g_dma_mode=!g_dma_mode 并写 R_ENGINE,
#     回显 [B2] DMAMODE now=DMA|bridge (sw/src_j3/main.c:436-447)。
#     ⇒ 本脚本一律用 Set-EngineMode: 'U' 回读 mode + req.bit24 双重确认, 最多翻转 3 次。
#   * ping 前禁止跑 M/A/B 轮: round_command 把 R_MODE 留在 RND(main.c:358),
#     轮末还把 R_ENGINE 写回 0(main.c:375-379) ⇒ 之后 ping 是 engine=0+RND, 无效实验。
#   * 'U' 每行首值是上一地址残值, 只用第 2..6 个值(field_mem_if/main.c 双读口径)。
#   * WM_WR = 栈 TX 帧写入桥① 的帧数; WM_RD = 桥① 读出帧数; 两者都只看低 16 位。
#     4 次 ping ⇒ 4 个 ICMP 应答帧写入 + 4 次桥① 读出 ⇒ 各 +4 是"读出路径启动"的硬证据。
#   * dbg_emit = {len[15:0],slot[7:0],byte0}, 字节流含 8B 前导 + 帧 + 4B FCS(len=帧长+12);
#     它只覆盖【第一跳】桥①读出→pack→Aurora TX, 对第二跳(桥②→泵B→mux→PHY)零覆盖。
#   * 静态 ARP 邻居环境下板端学不到 PC MAC ⇒ 板自发帧 dst MAC = ff:ff:ff:ff:ff:ff,
#     发射流比对必须掩掉 dst MAC(8-13)/IP ID(26-27)/IP cksum(32-33)/FCS(末4B)。
#
# 失败纪律: 任一断言失败 => 退出码非 0, 末尾打印 S0S8_RESULT: FAIL <哪一步>。
#           "判据未取得"(NOT_OBTAINED) 也计失败, 但明确标注为"实验无效", 不冒充"通过"。
# =============================================================================
[CmdletBinding()]
param(
    [string]$Bit = "",
    [string]$Elf = "",
    [string]$Port = "COM5",
    [switch]$Run,
    [switch]$SkipBurn,
    [string]$GreenBit = "",
    [string]$GreenElf = "",
    [string]$BuildLog = "",
    [string]$ExpectBitHash8 = "",
    [string]$ExpectElfHash8 = "",
    [string]$NicAlias = "",
    [string]$Python = "",
    [string]$EmitCsv = "",
    [switch]$AllowNonArchive,
    [switch]$SkipS2IdentityPing,
    [switch]$SkipS8
)

$ErrorActionPreference = "Continue"
$script:Version  = "2026-10-17"
$script:DryRun   = -not $Run
$script:OutRoot  = $PSScriptRoot
if (-not $script:OutRoot) {
    $script:OutRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:EvidDir  = Join-Path $script:OutRoot "evidence_2026-10-17"
$script:Stamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogPath  = Join-Path $script:EvidDir ("s0s8_" + $script:Stamp + ".log")
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom   = New-Object System.Text.UTF8Encoding($true)
$script:Steps     = [ordered]@{}
$script:Failures  = New-Object System.Collections.ArrayList
$script:Notes     = New-Object System.Collections.ArrayList
$script:Port      = $Port
$script:UartWait  = 2.0
$script:UartDrain = 0.25
$script:PyExe     = ""
$script:PyPrefix  = @()
$script:ResolvedNicAlias = ""
$script:BoardReady = $false
$script:QuiesceOk  = $false
$script:LastU      = $null
$script:S5State    = $null
$script:S3Ok       = $false
$script:TargetIp   = "192.168.1.10"
$script:BoardMac   = "00-11-22-33-44-55"
$script:PcIp       = "192.168.1.102"
$script:IcmpReplyBytes = 74          # ICMP 回包帧长 14+20+8+32 = 74B（ping 32B 载荷）
$script:Xsct       = "D:\Xilinx\Vitis\2023.1\bin\xsct.bat"
$script:KnownGreenBitHash8 = "708f15a4"
$script:KnownGreenElfHash8 = "c13a54f5"
$script:ExpectedArchiveDir = Join-Path $script:OutRoot "archive\b31b_rdfix_2026-10-17"
$script:ProbeInconsistent  = New-Object System.Collections.ArrayList

try {
    if (-not (Test-Path $script:EvidDir)) { New-Item -ItemType Directory -Force -Path $script:EvidDir | Out-Null }
    [System.IO.File]::WriteAllText($script:LogPath, "", $script:Utf8Bom)
} catch {
    Write-Host ("FATAL: 无法创建证据目录/日志: " + $_.Exception.Message) -ForegroundColor Red
    exit 2
}

# =============================================================================
#region 通用 IO / 日志
# =============================================================================
function Write-Raw {
    param([string]$Text = "", [string]$Color = "")
    if ($null -eq $Text) { $Text = "" }
    if ($Color) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    try { [System.IO.File]::AppendAllText($script:LogPath, $Text + "`r`n", $script:Utf8NoBom) } catch { }
}

function Write-Log {
    param([string]$Message = "", [string]$Color = "Gray")
    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    Write-Raw $line $Color
}

function Write-Section {
    param([string]$Title)
    $bar = "=" * 78
    Write-Raw $bar "Cyan"
    Write-Raw ("== " + $Title) "Cyan"
    Write-Raw $bar "Cyan"
}

function Write-Plan {
    param([string[]]$Lines = @())
    foreach ($l in $Lines) { Write-Raw ("[PLAN] " + $l) "DarkCyan" }
}

function Write-Note {
    param([string]$Message)
    [void]$script:Notes.Add($Message)
    Write-Log ("NOTE: " + $Message) "Yellow"
}

function Set-StepResult {
    param(
        [string]$Step,
        [ValidateSet("PASS", "FAIL", "NOT_OBTAINED", "SKIP")][string]$Verdict,
        [string]$Detail = ""
    )
    $tag = $Verdict
    if ($Verdict -eq "NOT_OBTAINED") { $tag = "FAIL(判据未取得)" }
    $line = "[JUDGE] $Step $tag"
    if ($Detail) { $line = $line + ": " + $Detail }
    $color = "Gray"
    if ($Verdict -eq "PASS") { $color = "Green" }
    elseif ($Verdict -eq "FAIL") { $color = "Red" }
    elseif ($Verdict -eq "NOT_OBTAINED") { $color = "Yellow" }
    else { $color = "DarkYellow" }
    Write-Raw $line $color
    $script:Steps[$Step] = [pscustomobject]@{ Verdict = $Verdict; Detail = $Detail; Line = $line }
    if ($Verdict -eq "FAIL" -or $Verdict -eq "NOT_OBTAINED") { [void]$script:Failures.Add($Step) }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string[]]$ArgList = @(),
        [string]$TeePath = ""
    )
    $lines = New-Object System.Collections.ArrayList
    $code = -1
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $Exe @ArgList 2>&1 | ForEach-Object {
            $line = [string]$_
            [void]$lines.Add($line)
            Write-Host $line
            try { [System.IO.File]::AppendAllText($script:LogPath, $line + "`r`n", $script:Utf8NoBom) } catch { }
            if ($TeePath) {
                try { [System.IO.File]::AppendAllText($TeePath, $line + "`r`n", $script:Utf8NoBom) } catch { }
            }
        }
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
    } catch {
        $msg = "EXCEPTION: " + $_.Exception.Message
        [void]$lines.Add($msg)
        Write-Raw $msg "Red"
        $code = -1
    } finally {
        $ErrorActionPreference = $old
    }
    return [pscustomobject]@{ Text = ($lines -join "`n"); ExitCode = [int]$code }
}

function Invoke-Python {
    param([string[]]$ArgList = @(), [string]$TeePath = "")
    $all = @()
    if ($script:PyPrefix.Count -gt 0) { $all += $script:PyPrefix }
    $all += $ArgList
    return Invoke-Native -Exe $script:PyExe -ArgList $all -TeePath $TeePath
}

# =============================================================================
#endregion
#region 预检 / 哈希 / 环境
# =============================================================================
function Resolve-PythonExe {
    if ($script:PyExe) { return $script:PyExe }
    $cands = @()
    if ($Python) { $cands = @($Python) } else { $cands = @("py", "python") }
    foreach ($c in $cands) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) {
            $script:PyExe = $c
            if ($c -eq "py") { $script:PyPrefix = @("-3") } else { $script:PyPrefix = @() }
            return $script:PyExe
        }
    }
    return ""
}

function Get-Hash8 {
    param([string]$Path)
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.Substring(0, 8).ToLower() } catch { return "" }
}

function Get-HashFull {
    param([string]$Path)
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() } catch { return "" }
}

function Resolve-ArtifactPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    try { return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path } catch { return "" }
}

function Test-ArchivePath {
    param([string]$FullPath)
    if (-not $FullPath) { return $false }
    try {
        $arc = [System.IO.Path]::GetFullPath((Join-Path $script:OutRoot "archive"))
        $p = [System.IO.Path]::GetFullPath($FullPath)
        return $p.StartsWith($arc, [System.StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-NeighborInfo {
    $n = Get-NetNeighbor -IPAddress $script:TargetIp -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $n) { return [pscustomobject]@{ Ok = $false; Text = "(无 192.168.1.10 邻居条目)"; State = ""; Mac = "" } }
    $txt = ($n | Select-Object IPAddress, LinkLayerAddress, State, PolicyStore | Format-Table -AutoSize | Out-String).TrimEnd()
    $ok = ($n.State -eq "Permanent") -and ([string]$n.LinkLayerAddress -eq $script:BoardMac)
    return [pscustomobject]@{ Ok = $ok; Text = $txt; State = [string]$n.State; Mac = [string]$n.LinkLayerAddress }
}

function Get-NicAliasResolved {
    if ($script:ResolvedNicAlias) { return $script:ResolvedNicAlias }
    if ($NicAlias) { $script:ResolvedNicAlias = $NicAlias; return $script:ResolvedNicAlias }
    $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $script:PcIp } | Select-Object -First 1
    if (-not $ip) { return "" }
    $script:ResolvedNicAlias = [string]$ip.InterfaceAlias
    return $script:ResolvedNicAlias
}

function Get-NicSnapshot {
    # ★NIC 判据只用 ReceivedBytes（主）+ ReceivedBroadcastPackets（辅）:
    #   静态 ARP 环境下板自发帧 dst MAC=ff:ff:ff:ff:ff:ff（广播）⇒ ping 回包进 ReceivedBytes，
    #   ReceivedUnicast 恒 0（今天绿位流实测 ping 4/4: Unicast delta=0, Bytes delta=+296）。
    $alias = Get-NicAliasResolved
    if (-not $alias) { return $null }
    $s = Get-NetAdapterStatistics -Name $alias -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    $bcast = $null
    if ($null -ne $s.ReceivedBroadcastPackets) { $bcast = [uint64]$s.ReceivedBroadcastPackets }
    return [pscustomobject]@{
        Alias     = $alias
        Bytes     = [uint64]$s.ReceivedBytes
        Broadcast = $bcast
        Unicast   = [uint64]$s.ReceivedUnicastPackets
    }
}

function Get-NicDelta {
    param($Before, $After)
    if ($null -eq $Before -or $null -eq $After) { return $null }
    $bcastD = $null
    if ($null -ne $Before.Broadcast -and $null -ne $After.Broadcast) {
        $bcastD = [int64]$After.Broadcast - [int64]$Before.Broadcast
    }
    return [pscustomobject]@{
        Bytes     = [int64]$After.Bytes - [int64]$Before.Bytes
        Broadcast = $bcastD
        Unicast   = [int64]$After.Unicast - [int64]$Before.Unicast
    }
}

# =============================================================================
#endregion
#region UART 探针 ('U' / 'L' / 'd' / 'S') 与解析
# =============================================================================
function Invoke-UartProbe {
    param([string]$Cmd, [double]$Wait = 2.0, [double]$Drain = 0.25, [string]$Title = "")
    if ($Title) { Write-Section $Title }
    if (-not $script:PyExe) { return [pscustomobject]@{ Text = "PYTHON-UNAVAILABLE"; ExitCode = -1 } }
    $probe = Join-Path $script:OutRoot "uart_probe.py"
    $argv = @($probe, "--port", $script:Port, "--cmd", $Cmd, "--wait", [string]$Wait, "--drain", [string]$Drain, "--raw")
    return Invoke-Python -ArgList $argv
}

function Get-UProbeNumber {
    param([string]$Payload, [string]$Field)
    if ([string]::IsNullOrWhiteSpace($Payload)) { return $null }
    $toks = @($Payload.Trim() -split "\s+")
    $hex = New-Object System.Collections.ArrayList
    foreach ($t in $toks) {
        if ($t -match "^[0-9a-fA-F]{1,8}$") { [void]$hex.Add([Convert]::ToUInt32($t, 16)) }
    }
    if ($hex.Count -lt 2) { return $null }
    $usable = New-Object System.Collections.ArrayList
    for ($i = 1; $i -lt $hex.Count; $i++) { [void]$usable.Add([uint32]$hex[$i]) }
    for ($i = 1; $i -lt $usable.Count; $i++) {
        if ($usable[$i] -ne $usable[0]) { [void]$script:ProbeInconsistent.Add($Field); break }
    }
    return [uint32]$usable[$usable.Count - 1]
}

function ConvertFrom-UProbe {
    param([string]$Text)
    $out = [ordered]@{
        ParseOk = $false; Raw = $Text; Id = $null; Req = $null; ReqX = $null;
        WmRd = $null; Stat = $null; Arl = $null; Emit = $null; WmWr = $null;
        Ust = $null; Mode = $null; Inconsistent = ""
    }
    $script:ProbeInconsistent.Clear()
    $map = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match "^\[B2\]\s+U\s+mode=(\d+)$") { $out.Mode = [int]$Matches[1]; continue }
        if ($t -match "^\[B2\]\s+U\s+([A-Za-z]+):\s*(.+)$") { $map[$Matches[1]] = $Matches[2] }
    }
    if ($map.ContainsKey("id"))    { $out.Id   = Get-UProbeNumber -Payload $map["id"]   -Field "id" }
    if ($map.ContainsKey("req"))   { $out.Req  = Get-UProbeNumber -Payload $map["req"]  -Field "req" }
    if ($map.ContainsKey("reqX"))  { $out.ReqX = Get-UProbeNumber -Payload $map["reqX"] -Field "reqX" }
    if ($map.ContainsKey("wmrd"))  { $out.WmRd = Get-UProbeNumber -Payload $map["wmrd"] -Field "wmrd" }
    if ($map.ContainsKey("stat"))  { $out.Stat = Get-UProbeNumber -Payload $map["stat"] -Field "stat" }
    if ($map.ContainsKey("arl"))   { $out.Arl  = Get-UProbeNumber -Payload $map["arl"]  -Field "arl" }
    if ($map.ContainsKey("emit"))  { $out.Emit = Get-UProbeNumber -Payload $map["emit"] -Field "emit" }
    if ($map.ContainsKey("wmwr"))  { $out.WmWr = Get-UProbeNumber -Payload $map["wmwr"] -Field "wmwr" }
    if ($map.ContainsKey("ust"))   { $out.Ust  = Get-UProbeNumber -Payload $map["ust"]  -Field "ust" }
    if ($script:ProbeInconsistent.Count -gt 0) { $out.Inconsistent = ($script:ProbeInconsistent -join ",") }
    $out.ParseOk = ($null -ne $out.Id) -and ($null -ne $out.Req) -and ($null -ne $out.WmWr) -and ($null -ne $out.WmRd) -and ($null -ne $out.Emit) -and ($null -ne $out.Mode)
    $obj = New-Object psobject
    foreach ($key in $out.Keys) { $obj | Add-Member -MemberType NoteProperty -Name $key -Value $out[$key] }
    return $obj
}

function Get-UState {
    param([string]$Title = "", [double]$Wait = 0, [double]$Drain = 0)
    $w = $script:UartWait; if ($Wait -gt 0) { $w = $Wait }
    $d = $script:UartDrain; if ($Drain -gt 0) { $d = $Drain }
    $res = Invoke-UartProbe -Cmd "U" -Wait $w -Drain $d -Title $Title
    $u = ConvertFrom-UProbe -Text $res.Text
    $script:LastU = $u
    return $u
}

function Get-ReqEngineBit {
    param($U)
    if ($null -eq $U -or $null -eq $U.Req) { return $false }
    return (($U.Req -band 0x01000000) -ne 0)
}

function Get-ReqStickyBit {
    param($U)
    if ($null -eq $U -or $null -eq $U.Req) { return $false }
    return (($U.Req -band 0x02000000) -ne 0)
}

function Get-WmWr16 { param($U) if ($null -eq $U -or $null -eq $U.WmWr) { return $null } return ([int]($U.WmWr -band 0xFFFF)) }
function Get-WmRd16 { param($U) if ($null -eq $U -or $null -eq $U.WmRd) { return $null } return ([int]($U.WmRd -band 0xFFFF)) }

function Format-UStateBrief {
    param($U)
    if ($null -eq $U -or -not $U.ParseOk) { return "(U 探针无应答/解析失败)" }
    return ("mode={0} req=0x{1:x8} engine={2} sticky={3} wmwr={4} wmrd={5} emit=0x{6:x8}" -f `
        $U.Mode, $U.Req, [int](Get-ReqEngineBit $U), [int](Get-ReqStickyBit $U), (Get-WmWr16 $U), (Get-WmRd16 $U), $U.Emit)
}

function Send-UartCmd {
    param([string]$Cmd, [double]$Wait = 1.5, [string]$Title = "")
    return Invoke-UartProbe -Cmd $Cmd -Wait $Wait -Drain 0.15 -Title $Title
}

function Set-EngineMode {
    # 'd' 是翻转命令: 每次发 'd' 后都用 'U' 回读 mode + req.bit24 双重确认, 最多翻转 3 次。
    param([int]$Want = 1, [int]$MaxToggles = 3)
    $trace = New-Object System.Collections.ArrayList
    $u = Get-UState -Title ("engine 目标 {0} · 回读 #1" -f $Want)
    for ($i = 0; $i -le $MaxToggles; $i++) {
        if ($null -ne $u -and $u.ParseOk) {
            $modeOk = ($u.Mode -eq $Want)
            $engineOk = ((Get-ReqEngineBit $u) -eq ($Want -eq 1))
            [void]$trace.Add(("U#{0}: mode={1} req=0x{2:x8} bit24={3}" -f $i, $u.Mode, $u.Req, [int](Get-ReqEngineBit $u)))
            if ($modeOk -and $engineOk) {
                $wantTxt = "bridge"
                if ($Want -eq 1) { $wantTxt = "DMA" }
                [void]$trace.Add(("engine={0} 已确认 (mode={1} & bit24={2})" -f $wantTxt, $u.Mode, [int](Get-ReqEngineBit $u)))
                return [pscustomobject]@{ Ok = $true; State = $u; Trace = ($trace -join "`n"); Toggles = $i }
            }
        } else {
            [void]$trace.Add(("U#{0}: 回读失败" -f $i))
        }
        if ($i -ge $MaxToggles) { break }
        $dres = Send-UartCmd -Cmd "d" -Wait 1.5 -Title ("翻转 'd' #" + ($i + 1))
        $ack = ($dres.Text -split "`r?`n" | Where-Object { $_ -match "DMAMODE" } | Select-Object -Last 1)
        if ($ack) { [void]$trace.Add("d#" + ($i + 1) + " ack: " + $ack.Trim()) } else { [void]$trace.Add("d#" + ($i + 1) + " ack: (未解析到 DMAMODE 行)") }
        Start-Sleep -Milliseconds 500
        $u = Get-UState -Title ("engine 目标 {0} · 回读 #{1}" -f $Want, ($i + 2))
    }
    return [pscustomobject]@{ Ok = $false; State = $u; Trace = ($trace -join "`n"); Toggles = $MaxToggles }
}

function Wait-QReadQuiesce {
    # 静默窗: 等 wmwr==wmrd 且 req.bit25(sticky)=0 连续两拍 —— 否则 S4/S5 差分基线被上一轮残留帧污染。
    param([int]$MaxPolls = 10)
    $trace = New-Object System.Collections.ArrayList
    $prev = $null
    for ($i = 0; $i -lt $MaxPolls; $i++) {
        $u = Get-UState -Title ("S3b 静默窗回读 #" + ($i + 1)) -Wait 1.6 -Drain 0.15
        if ($null -eq $u -or -not $u.ParseOk) {
            [void]$trace.Add(("U#{0}: 解析失败" -f $i))
            Start-Sleep -Milliseconds 300
            continue
        }
        $wr = Get-WmWr16 $u
        $rd = Get-WmRd16 $u
        $backlog = (($wr - $rd) % 65536 + 65536) % 65536
        $sticky = Get-ReqStickyBit $u
        [void]$trace.Add(("U#{0}: mode={1} bit24={2} wmwr={3} wmrd={4} backlog={5} sticky={6}" -f `
            $i, $u.Mode, [int](Get-ReqEngineBit $u), $wr, $rd, $backlog, [int]$sticky))
        if ($u.Mode -ne 1 -or -not (Get-ReqEngineBit $u)) {
            [void]$trace.Add("engine 在静默窗内不是 DMA(bit24=1) —— 停止轮询")
            return [pscustomobject]@{ Ok = $false; Trace = ($trace -join "`n"); State = $u; Backlog = $backlog }
        }
        if ((-not $sticky) -and ($wr -eq $rd)) {
            if ($null -ne $prev -and $prev.Wr -eq $wr -and $prev.Rd -eq $rd) {
                return [pscustomobject]@{ Ok = $true; Trace = ($trace -join "`n"); State = $u; Backlog = 0 }
            }
            $prev = [pscustomobject]@{ Wr = $wr; Rd = $rd }
        } else {
            $prev = $null
        }
        Start-Sleep -Milliseconds 300
    }
    $last = $script:LastU
    $bl = 0
    if ($null -ne $last -and $last.ParseOk) { $bl = ((((Get-WmWr16 $last) - (Get-WmRd16 $last)) % 65536) + 65536) % 65536 }
    return [pscustomobject]@{ Ok = $false; Trace = ($trace -join "`n"); State = $last; Backlog = $bl }
}

function Wait-BoardAlive {
    # 'L' 回读在绿 ELF(c13a54f5) 与新 ELF 上都可用, 用它做烧写后 boot 探测(比 'U' 兼容性更好)。
    param([int]$TimeoutSec = 35)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $n = 0
    while ((Get-Date) -lt $deadline) {
        $n++
        $r = Invoke-UartProbe -Cmd "L" -Wait 1.2 -Drain 0.15 -Title ("boot 探测 #" + $n + " ('L')")
        if ($r.Text -match "\[B2\] LAT w=") { return $true }
        Start-Sleep -Milliseconds 1200
    }
    return $false
}

# =============================================================================
#endregion
#region 网口 / ping / 烧写
# =============================================================================
function Invoke-Ping {
    param([int]$Count = 1, [int]$TimeoutMs = 900, [string]$Title = "")
    $title = $Title
    if (-not $title) { $title = ("ping -n {0} -w {1} {2}" -f $Count, $TimeoutMs, $script:TargetIp) }
    Write-Section $title
    $res = Invoke-Native -Exe "ping" -ArgList @("-n", [string]$Count, "-w", [string]$TimeoutMs, $script:TargetIp)
    $replies = ([regex]::Matches($res.Text, "TTL=")).Count
    Write-Log ("ping 回包数 = {0}/{1}" -f $replies, $Count) $(if ($replies -ge $Count) { "Green" } else { "Yellow" })
    return [pscustomobject]@{ Text = $res.Text; Replies = $replies; ExitCode = $res.ExitCode }
}

function Invoke-BurnPair {
    param([string]$BitPath, [string]$ElfPath)
    $burnTcl = Join-Path $script:OutRoot "jb31b_burn_pair.tcl"
    if (-not (Test-Path $burnTcl)) { return [pscustomobject]@{ Ok = $false; Text = ("缺 " + $burnTcl) } }
    if (-not (Test-Path $script:Xsct)) { return [pscustomobject]@{ Ok = $false; Text = ("缺 xsct: " + $script:Xsct) } }
    Write-Section ("烧写(jb31b_burn_pair.tcl): " + (Split-Path -Leaf $BitPath) + " + " + (Split-Path -Leaf $ElfPath))
    $res = Invoke-Native -Exe $script:Xsct -ArgList @($burnTcl, ($BitPath -replace "\\", "/"), ($ElfPath -replace "\\", "/"))
    $ok = ($res.Text -match "PAIR_BURNED")
    if ($ok) { Write-Log "PAIR_BURNED ✓" "Green" } else { Write-Log "烧写未确认(缺 PAIR_BURNED 行)" "Red" }
    return [pscustomobject]@{ Ok = $ok; Text = $res.Text; ExitCode = $res.ExitCode }
}

# =============================================================================
#endregion
#region 步骤实现
# =============================================================================
function Step-Preflight {
    Write-Section "P0 预检（只读）：工具/工件/网络仪器"
    $py = Resolve-PythonExe
    if ($py) {
        Write-Log ("python = " + $py + "  (prefix args: " + ($script:PyPrefix -join " ") + ")") "Green"
    } else {
        Write-Log "找不到 python/py（可用 -Python 指定解释器）—— 所有串口/脚本步骤将判据未取得" "Red"
    }
    $tools = [ordered]@{
        "uart_probe.py"        = (Join-Path $script:OutRoot "uart_probe.py")
        "manual_round.py"      = (Join-Path $script:OutRoot "manual_round.py")
        "j3_fourchains.ps1"    = (Join-Path $script:OutRoot "j3_fourchains.ps1")
        "jb31b_burn_pair.tcl"  = (Join-Path $script:OutRoot "jb31b_burn_pair.tcl")
        "j3_soft_verify.py"    = (Join-Path (Split-Path -Parent $script:OutRoot) "scripts\j3_soft_verify.py")
        "xsct.bat"             = $script:Xsct
    }
    foreach ($k in $tools.Keys) {
        $p = $tools[$k]
        if (Test-Path $p) { Write-Log ("OK   " + $k + " = " + $p) } else { Write-Log ("MISS " + $k + " = " + $p) "Yellow" }
    }
    $nb = Get-NeighborInfo
    Write-Log "静态邻居检查(192.168.1.10 → 00-11-22-33-44-55, Permanent):"
    Write-Raw $nb.Text
    if ($nb.Ok) { Write-Log "邻居 = Permanent ✓" "Green" } else { Write-Log ("邻居异常: State=" + $nb.State + " Mac=" + $nb.Mac + " ⇒ ping 依赖 PC 发 ARP, 判据会变慢/失真") "Yellow" }
    $nic = Get-NicAliasResolved
    if ($nic) {
        $snap = Get-NicSnapshot
        Write-Log ("NIC = " + $nic + "  ReceivedBytes=" + $snap.Bytes + "  ReceivedBroadcast=" + $snap.Broadcast + "  ReceivedUnicast=" + $snap.Unicast)
        Write-Log "NIC 判据口径: 只用 ReceivedBytes（板自发帧 dst MAC=广播 ⇒ ReceivedUnicast 恒 0, 不可用）"
    } else {
        Write-Log ("找不到 " + $script:PcIp + " 对应网卡 —— NIC delta 判据将不可用") "Yellow"
    }
    Write-Log ("证据目录 = " + $script:EvidDir)
    Write-Log ("本次日志 = " + $script:LogPath)
}

function Step-S0 {
    Write-Section "S0 离线核对: 位流/ELF SHA256 + 构建日志门限（不碰板）"
    $bitFull = Resolve-ArtifactPath $Bit
    $elfFull = Resolve-ArtifactPath $Elf
    $bitHash = ""; $elfHash = ""
    if ($bitFull) {
        $bitHash = Get-HashFull $bitFull
        Write-Log ("Bit = " + $bitFull)
        Write-Log ("Bit SHA256 = " + $bitHash)
        Write-Log ("Bit hash8  = " + $bitHash.Substring(0, 8))
        if (-not (Test-ArchivePath $bitFull)) {
            Write-Log "WARN: -Bit 不在 out\archive\ 下 —— out\aurora_mem_bridge.bit 会被构建覆盖，按纪律必须用归档绝对路径" "Yellow"
            Write-Note "Bit 非归档路径: $bitFull"
        }
    } else {
        Write-Log "Bit = <未提供（dry-run 占位；-Run 必须给归档绝对路径）>"
    }
    if ($elfFull) {
        $elfHash = Get-HashFull $elfFull
        Write-Log ("Elf = " + $elfFull)
        Write-Log ("Elf SHA256 = " + $elfHash)
        Write-Log ("Elf hash8  = " + $elfHash.Substring(0, 8))
        if (-not (Test-ArchivePath $elfFull)) { Write-Log "WARN: -Elf 不在 out\archive\ 下（构建/重编会覆盖，建议归档后再跑）" "Yellow" }
    } else {
        Write-Log "Elf = <未提供（dry-run 占位；-Run 必须给归档绝对路径）>"
    }
    $hashOk = $true
    if ($ExpectBitHash8 -and $bitFull) {
        $want = $ExpectBitHash8.ToLower()
        if ($bitHash.StartsWith($want)) { Write-Log ("Bit hash8 与期望一致 (" + $want + ")") "Green" }
        else { Write-Log ("Bit hash8 与期望不符: 实际 " + $bitHash.Substring(0, 8) + " ≠ 期望 " + $want) "Red"; $hashOk = $false }
    }
    if ($ExpectElfHash8 -and $elfFull) {
        $want = $ExpectElfHash8.ToLower()
        if ($elfHash.StartsWith($want)) { Write-Log ("Elf hash8 与期望一致 (" + $want + ")") "Green" }
        else { Write-Log ("Elf hash8 与期望不符: 实际 " + $elfHash.Substring(0, 8) + " ≠ 期望 " + $want) "Red"; $hashOk = $false }
    }
    Write-Log ("归档目标目录（Lead 归档时确定实际 hash）: " + $script:ExpectedArchiveDir)
    if (-not $BuildLog) {
        Write-Log "构建日志未提供(-BuildLog) ⇒ S0 门限判据未取得: SKIP（非失败；但上板前应由 Lead 人工确认 WNS/WHS≥0）" "DarkYellow"
        Set-StepResult -Step "S0" -Verdict "SKIP" -Detail "构建日志未提供；SHA256 已记录, 门限未核"
        return
    }
    $logFull = Resolve-ArtifactPath $BuildLog
    if (-not $logFull) {
        Set-StepResult -Step "S0" -Verdict "FAIL" -Detail ("构建日志不存在: " + $BuildLog)
        return
    }
    Write-Log ("BuildLog = " + $logFull)
    $text = ""
    try { $text = Get-Content -LiteralPath $logFull -Raw -Encoding UTF8 } catch { $text = "" }
    if (-not $text) {
        Set-StepResult -Step "S0" -Verdict "NOT_OBTAINED" -Detail "构建日志读取为空/编码失败"
        return
    }
    $wnsList = New-Object System.Collections.ArrayList
    $whsList = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($text, "WNS_GATE:\s*(-?\d+(?:\.\d+)?)")) { [void]$wnsList.Add([double]$m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($text, "WHS_GATE:\s*(-?\d+(?:\.\d+)?)")) { [void]$whsList.Add([double]$m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($text, "SWEEP_[A-Za-z]+:\s*WNS=(-?\d+(?:\.\d+)?)")) { [void]$wnsList.Add([double]$m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($text, "SWEEP_[A-Za-z]+:\s*WNS=-?\d+(?:\.\d+)?\s+WHS=(-?\d+(?:\.\d+)?)")) { [void]$whsList.Add([double]$m.Groups[1].Value) }
    $okMarker = ($text -match "V5_SWEEP_OK|W5_BUILD_OK|DBG_BUILD_DONE")
    $failMarker = ($text -match "V5_SWEEP_ALL_FAIL|W5_BUILD_TIMING_FAIL")
    $bitInLog = ""
    $mBit = [regex]::Match($text, "(?:V5_SWEEP_OK|DBG_BUILD_DONE)[^\r\n]*bit=([^\s]+)")
    if ($mBit.Success) { $bitInLog = $mBit.Groups[1].Value }
    $wns = $null; $whs = $null
    if ($wnsList.Count -gt 0) { $wns = $wnsList[$wnsList.Count - 1] }
    if ($whsList.Count -gt 0) { $whs = $whsList[$whsList.Count - 1] }
    Write-Log ("WNS(last) = " + $wns) $(if ($null -ne $wns -and $wns -ge 0) { "Green" } else { "Red" })
    Write-Log ("WHS(last) = " + $whs) $(if ($null -ne $whs -and $whs -ge 0) { "Green" } else { "Red" })
    Write-Log ("成功标记(V5_SWEEP_OK|W5_BUILD_OK|DBG_BUILD_DONE) = " + $okMarker)
    Write-Log ("失败标记(V5_SWEEP_ALL_FAIL|W5_BUILD_TIMING_FAIL) = " + $failMarker)
    if ($bitInLog) { Write-Log ("构建日志内位流路径 = " + $bitInLog) }
    if ($bitInLog -and $bitFull) {
        $logLeaf = Split-Path -Leaf ($bitInLog -replace "/", "\")
        $ourLeaf = Split-Path -Leaf $bitFull
        if ($logLeaf -eq $ourLeaf) {
            Write-Log "构建日志位流文件名与 -Bit 一致 ✓（仍是不同目录拷贝；hash8 以上表为准）" "Green"
        } else {
            Write-Log ("构建日志位流文件名(" + $logLeaf + ") ≠ -Bit 文件名(" + $ourLeaf + ") —— 核对是否烧错/归档错") "Yellow"
        }
    }
    $bit8 = ""; if ($bitHash.Length -ge 8) { $bit8 = $bitHash.Substring(0, 8) }
    $elf8 = ""; if ($elfHash.Length -ge 8) { $elf8 = $elfHash.Substring(0, 8) }
    $pass = $hashOk -and ($null -ne $wns) -and ($null -ne $whs) -and ($wns -ge 0) -and ($whs -ge 0) -and $okMarker -and (-not $failMarker)
    if ($pass) {
        Set-StepResult -Step "S0" -Verdict "PASS" -Detail ("WNS=" + $wns + " WHS=" + $whs + " 成功标记=有; bit8=" + $bit8 + " elf8=" + $elf8)
    } else {
        Set-StepResult -Step "S0" -Verdict "FAIL" -Detail ("WNS=" + $wns + " WHS=" + $whs + " okMarker=" + $okMarker + " failMarker=" + $failMarker + " hashOk=" + $hashOk)
    }
}

function Step-S1 {
    Write-Section "S1 绿配置对照(可选): 烧绿 → ping 3 + 'L' 应答 + 静态邻居 Permanent"
    if (-not $GreenBit -or -not $GreenElf) {
        Write-Log "未提供 -GreenBit/-GreenElf ⇒ S1 SKIP（可选步；不改变 S2-S8 的判据，但少了'板/线/PC 侧没变'的前提）" "DarkYellow"
        Set-StepResult -Step "S1" -Verdict "SKIP" -Detail "未提供 -GreenBit/-GreenElf"
        return
    }
    $gb = Resolve-ArtifactPath $GreenBit
    $ge = Resolve-ArtifactPath $GreenElf
    if (-not $gb -or -not $ge) {
        Set-StepResult -Step "S1" -Verdict "FAIL" -Detail "绿配置工件路径无效"
        return
    }
    $gb8 = Get-Hash8 $gb
    $ge8 = Get-Hash8 $ge
    Write-Log ("GreenBit = " + $gb + "  hash8=" + $gb8)
    Write-Log ("GreenElf = " + $ge + "  hash8=" + $ge8)
    if ($gb8 -ne $script:KnownGreenBitHash8 -or $ge8 -ne $script:KnownGreenElfHash8) {
        Write-Log ("WARN: 与已知绿基线(bit 708f15a4 / elf c13a54f5)不一致 —— S1 只作'板/线可用'旁证, 不能当归档对照") "Yellow"
        Write-Note ("S1 绿配置非归档已知基线: bit8=$gb8 elf8=$ge8")
    } else {
        Write-Log "与已知绿基线(708f15a4 + c13a54f5)一致 ✓" "Green"
    }
    if ($script:DryRun) {
        Write-Plan @(
            "xsct D:/FPGA/prj/project_11/out/jb31b_burn_pair.tcl <GreenBit> <GreenElf>",
            "等 boot: 轮询 'L' 直到出现 [B2] LAT w=...",
            "Get-NetNeighbor 192.168.1.10 → 要求 State=Permanent + MAC=00-11-22-33-44-55",
            "ping -n 3 -w 900 192.168.1.10 → 要求 3/3 回包",
            "串口 'L' → 要求 [B2] LAT w=<n> r=<n>"
        )
        Set-StepResult -Step "S1" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $script:PyExe) { Set-StepResult -Step "S1" -Verdict "NOT_OBTAINED" -Detail "python 不可用"; return }
    if ($SkipBurn) {
        Write-Log "-SkipBurn ⇒ 跳过烧绿, 假设板上已是绿配置（若不符, S1 会失败）" "Yellow"
    } else {
        $burn = Invoke-BurnPair -BitPath $gb -ElfPath $ge
        if (-not $burn.Ok) { Set-StepResult -Step "S1" -Verdict "FAIL" -Detail "绿配置烧写失败"; $script:BoardReady = $false; return }
    }
    $alive = Wait-BoardAlive -TimeoutSec 35
    if (-not $alive) { Set-StepResult -Step "S1" -Verdict "FAIL" -Detail "绿配置烧写后 35s 内 'L' 无应答"; $script:BoardReady = $false; return }
    $script:BoardReady = $true
    $nb = Get-NeighborInfo
    Write-Raw $nb.Text
    $p = Invoke-Ping -Count 3 -TimeoutMs 900
    $l = Send-UartCmd -Cmd "L" -Wait 2.0 -Title "S1 'L' 回读(延迟观测)"
    $latOk = ($l.Text -match "\[B2\] LAT w=(\d+) r=(\d+)")
    if ($latOk) { Write-Log ("'L' 应答: " + $Matches[0]) "Green" } else { Write-Log "'L' 未应答/解析失败" "Red" }
    $pass = $nb.Ok -and ($p.Replies -ge 3) -and $latOk
    if ($pass) {
        Write-Log "S1 前提成立: 板/线/PC 侧与绿基线同条件 ✓（之后 S2 烧退役对被判定为【唯一变量】）" "Green"
        Set-StepResult -Step "S1" -Verdict "PASS" -Detail ("ping " + $p.Replies + "/3, 'L' 应答, 邻居 Permanent")
    } else {
        Set-StepResult -Step "S1" -Verdict "FAIL" -Detail ("ping " + $p.Replies + "/3, L=" + $latOk + ", 邻居OK=" + $nb.Ok + " ⇒ 环境前提不成立, 后续步骤结论仅作参考")
    }
}

function Step-S2 {
    Write-Section "S2 位流身份原位判据: 烧新退役对, 先不发 'd'"
    $bitFull = Resolve-ArtifactPath $Bit
    $elfFull = Resolve-ArtifactPath $Elf
    if ($script:DryRun) {
        if ($bitFull) { Write-Log ("Bit = " + $bitFull + "  hash8=" + (Get-Hash8 $bitFull)) } else { Write-Log "Bit = <未提供>" }
        if ($elfFull) { Write-Log ("Elf = " + $elfFull + "  hash8=" + (Get-Hash8 $elfFull)) } else { Write-Log "Elf = <未提供>" }
        Write-Plan @(
            "xsct D:/FPGA/prj/project_11/out/jb31b_burn_pair.tcl <Bit> <Elf>  (绝对路径, 先核 SHA256)",
            "等 boot ('L' 应答)",
            ("S2a: py manual_round.py " + $Port + " 1 → 必须失败: 出现 [B2] WAITWR-FAIL/STALL, 且无 [B2] DONE, 且 echo=0"),
            "     (NSLOTS=256 编译期固定 ⇒ 1 帧永远凑不齐一轮, 这是'未完成'而不是'通过')",
            "S2b(加严): 确认 engine=0 → 发 'S' → ping -n 1 → 必须 0 回包 + NIC delta=0",
            "     (绿位流 engine=0 时硬件读引擎在线, 会回包; 退役位流无读出路径, 不回包 => 真正的位流身份判据)"
        )
        Set-StepResult -Step "S2" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $bitFull -or -not $elfFull) {
        Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "-Bit/-Elf 未提供或路径无效（-Run 必须给归档绝对路径）"
        return
    }
    if (-not $script:PyExe) { Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "python 不可用"; return }
    # 归档路径纪律
    $archiveOk = (Test-ArchivePath $bitFull) -and (Test-ArchivePath $elfFull)
    $volatileBit = ($bitFull -match "(?i)\\out\\aurora_mem_bridge\.bit$")
    if ($volatileBit) {
        Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "拒绝烧 out\aurora_mem_bridge.bit（构建会覆盖, 必须用归档绝对路径）"
        return
    }
    if (-not $archiveOk -and -not $AllowNonArchive) {
        Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "工件不在 out\archive\ 下; 按纪律拒绝烧写（如确需, 加 -AllowNonArchive）"
        return
    }
    if (-not $SkipBurn) {
        $burn = Invoke-BurnPair -BitPath $bitFull -ElfPath $elfFull
        if (-not $burn.Ok) { Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "退役对烧写失败"; $script:BoardReady = $false; return }
        $script:BoardReady = $true
        Start-Sleep -Milliseconds 800
        if (-not (Wait-BoardAlive -TimeoutSec 35)) {
            Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "新退役对烧写后 35s 内 'L' 无应答"
            $script:BoardReady = $false
            return
        }
    } else {
        Write-Log "-SkipBurn ⇒ 跳过 S2 烧写, 假设板上已是目标退役对" "Yellow"
        $script:BoardReady = $true
    }
    # ---- S2a: manual_round 1 帧必须失败 ----
    $mr = Join-Path $script:OutRoot "manual_round.py"
    if (-not (Test-Path $mr)) { Set-StepResult -Step "S2a" -Verdict "NOT_OBTAINED" -Detail "缺 manual_round.py"; }
    else {
        $res = Invoke-Python -ArgList @($mr, $Port, "1")
        $txt = $res.Text
        $seqok = ($txt -match "\[phase0\] SEQOK=True")
        $readyok = ($txt -match "\[phase1\] READY=True")
        $hasFail = ($txt -match "WAITWR-FAIL|\[B2\] STALL")
        $hasDone = ($txt -match "\[B2\] DONE")
        $mEcho = [regex]::Match($txt, "=== echo=(\d+) ===")
        $echo = $null
        if ($mEcho.Success) { $echo = [int]$mEcho.Groups[1].Value }
        $s2aPass = $seqok -and $readyok -and $hasFail -and (-not $hasDone) -and ($echo -eq 0)
        $detail = ("SEQOK={0} READY={1} 失败行={2} DONE={3} echo={4}" -f $seqok, $readyok, $hasFail, $hasDone, $echo)
        if ($s2aPass) {
            Set-StepResult -Step "S2a" -Verdict "PASS" -Detail ("M轮1帧未完成(非身份判据, 但确认不冒充通过): " + $detail)
        } elseif (-not $seqok -or -not $readyok) {
            Set-StepResult -Step "S2a" -Verdict "NOT_OBTAINED" -Detail ("串口/固件未按预期应答: " + $detail)
        } else {
            Set-StepResult -Step "S2a" -Verdict "FAIL" -Detail ("1 帧 M 轮出现异常完成/回显(与 NSLOTS=256 矛盾): " + $detail)
        }
    }
    # ---- S2b: 不发 'd' 的 ping 身份判据（加严, 可 -SkipS2IdentityPing 关闭）----
    if ($SkipS2IdentityPing) {
        Set-StepResult -Step "S2b" -Verdict "SKIP" -Detail "已用 -SkipS2IdentityPing 关闭"
    } else {
        $eng0 = Set-EngineMode -Want 0
        Write-Log $eng0.Trace
        if (-not $eng0.Ok) {
            Set-StepResult -Step "S2b" -Verdict "NOT_OBTAINED" -Detail "engine=0 无法确认(-SkipBurn 时板上可能是 DMA)"
        } else {
            $sres = Send-UartCmd -Cmd "S" -Wait 1.5 -Title "S2b 恢复 SEQ('S')"
            Start-Sleep -Milliseconds 400
            $nb0 = Get-NicSnapshot
            $p1 = Invoke-Ping -Count 1 -TimeoutMs 900 -Title "S2b 身份判据: ping -n 1（未发 'd'）"
            Start-Sleep -Milliseconds 300
            $na0 = Get-NicSnapshot
            $d0 = Get-NicDelta -Before $nb0 -After $na0
            if ($p1.Replies -ge 1) {
                Set-StepResult -Step "S2b" -Verdict "FAIL" -Detail ("未发 'd' 却收到 ping 回包 " + $p1.Replies + "/1 ⇒ 板上不是退役位流（或 engine 位已=1）: 烧错/烧旧位流")
            } elseif ($null -eq $d0) {
                Set-StepResult -Step "S2b" -Verdict "NOT_OBTAINED" -Detail "ping 0/1 但 NIC 统计不可用, 无法确认'线上 0 帧'"
            } elseif ($d0.Bytes -eq 0) {
                Set-StepResult -Step "S2b" -Verdict "PASS" -Detail ("未发 'd': ping 0/1, NIC ReceivedBytes delta=0（Broadcast=" + $d0.Broadcast + "）⇒ 无读出路径 ✓（退役身份）")
            } else {
                Set-StepResult -Step "S2b" -Verdict "PASS" -Detail ("未发 'd': ping 0/1 ✓, 但 NIC ReceivedBytes delta=" + $d0.Bytes + " 有杂散收帧(不计失败, 记录)")
                Write-Note ("S2b 期间出现杂散 NIC ReceivedBytes delta=" + $d0.Bytes)
            }
        }
    }
    # ---- S2 汇总 ----
    $v2a = ""; $v2b = ""
    if ($script:Steps.Contains("S2a")) { $v2a = $script:Steps["S2a"].Verdict }
    if ($script:Steps.Contains("S2b")) { $v2b = $script:Steps["S2b"].Verdict }
    $all = @($v2a, $v2b) | Where-Object { $_ -ne "" -and $_ -ne "SKIP" }
    if ($all -contains "FAIL") { Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "S2a/S2b 见上" }
    elseif ($all -contains "NOT_OBTAINED") { Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "S2a/S2b 见上" }
    else { Set-StepResult -Step "S2" -Verdict "PASS" -Detail "S2a + S2b 通过" }
}

function Step-S3 {
    Write-Section "S3 切 DMA 并回读 req（断言 req.bit24=1）"
    if ($script:DryRun) {
        Write-Plan @(
            "Set-EngineMode DMA: 读 'U' mode；不是 DMA 就发 'd'(翻转) 并回读确认；最多 3 次",
            "最后断言: [B2] U mode=1 且 req.bit24=1（无效则本步失败）",
            "发 'S' 恢复 SEQ（'d' 切换为 DMA 时固件已置 SEQ, 此步幂等）",
            "发 'U' 整段原始行落盘 (id/req/reqX/wmrd/stat/arl/emit/wmwr/ust/mode)",
            "S3b 静默窗: 轮询 'U' 直到 wmwr==wmrd 且 req.bit25=0 连续两拍（清 S2a/S2b 残留待读帧）"
        )
        Set-StepResult -Step "S3" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $script:BoardReady) {
        Set-StepResult -Step "S3" -Verdict "NOT_OBTAINED" -Detail "板卡未就绪(S2 烧写/boot 失败)"
        return
    }
    $eng = Set-EngineMode -Want 1
    Write-Log $eng.Trace
    if (-not $eng.Ok) {
        Set-StepResult -Step "S3" -Verdict "FAIL" -Detail ("Set-EngineMode(DMA) 失败: " + (Format-UStateBrief $eng.State))
        Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "S3 失败"
        return
    }
    $sres = Send-UartCmd -Cmd "S" -Wait 1.5 -Title "S3 恢复 SEQ('S')"
    Start-Sleep -Milliseconds 400
    $u = Get-UState -Title "S3 'U' 整段回读（原始行已落盘）"
    if ($null -eq $u -or -not $u.ParseOk) {
        Set-StepResult -Step "S3" -Verdict "NOT_OBTAINED" -Detail "'U' 无应答/解析失败"
        Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "S3 失败"
        return
    }
    if ($u.Inconsistent) { Write-Log ("WARN: 'U' 某字段第2..N值不一致(" + $u.Inconsistent + ") —— 取最后一值") "Yellow" }
    $bit24 = Get-ReqEngineBit $u
    $bit25 = Get-ReqStickyBit $u
    $slot = [int](($u.Req -shr 16) -band 0xFF)
    $len = [int]($u.Req -band 0xFFFF)
    Write-Log ("req=0x{0:x8} ⇒ bit24(engine)={1} bit25(sticky)={2} slot={3} len={4}" -f $u.Req, [int]$bit24, [int]$bit25, $slot, $len)
    Write-Log ("'U' mode(g_dma_mode)={0} wmwr={1} wmrd={2} emit=0x{3:x8}" -f $u.Mode, (Get-WmWr16 $u), (Get-WmRd16 $u), $u.Emit)
    if ($bit24 -and ($u.Mode -eq 1)) {
        $script:S3Ok = $true
        Set-StepResult -Step "S3" -Verdict "PASS" -Detail ("req.bit24=1 & mode=1; bit25=" + [int]$bit25 + " slot=" + $slot + " len=" + $len)
    } else {
        Set-StepResult -Step "S3" -Verdict "FAIL" -Detail ("req.bit24=" + [int]$bit24 + " mode=" + $u.Mode + " ⇒ 引擎位未确认 DMA")
        Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "S3 失败"
        return
    }
    # ---- S3b 静默窗 ----
    $q = Wait-QReadQuiesce -MaxPolls 10
    Write-Log $q.Trace
    if ($q.Ok) {
        $script:QuiesceOk = $true
        Set-StepResult -Step "S3b" -Verdict "PASS" -Detail "wmwr==wmrd & sticky=0 连续两拍 ⇒ S4/S5 差分基线干净"
    } else {
        $script:QuiesceOk = $false
        Set-StepResult -Step "S3b" -Verdict "FAIL" -Detail ("静默窗未建立(backlog=" + $q.Backlog + ") ⇒ 读出侧未能排空残留帧, 后面 S4/S5 判据按'未取得'降级")
        Write-Note ("S3b 静默窗失败: backlog=" + $q.Backlog + "（读出侧停摆/服务未运行, 与 H4/H6 同形）")
    }
}

function Get-NicDeltaText {
    param($Delta)
    if ($null -eq $Delta) { return "n/a" }
    $b = "n/a"
    if ($null -ne $Delta.Broadcast) { $b = [string]$Delta.Broadcast }
    return ("ReceivedBytes={0} (主判据) ReceivedBroadcast={1} ReceivedUnicast={2}(广播 dst 下不可用)" -f $Delta.Bytes, $b, $Delta.Unicast)
}

function Step-S4 {
    Write-Section "S4 单帧判据: ping -n 1（不跑 M 轮）+ NIC delta + WM 前后差分"
    if ($script:DryRun) {
        Write-Plan @(
            "前置: 'U' 回读 mode=1 & req.bit24=1（不满足先 Set-EngineMode DMA）",
            "U 前 → ping -n 1 -w 1500 192.168.1.10 → 等 0.3s → U 后",
            "断言: ping 1/1 回包 & NIC ReceivedBytes delta>=74（单帧 ICMP 回包 14+20+8+32=74B）& WM_WR+1 & WM_RD+1",
            "      注: 板自发帧 dst MAC=广播 ⇒ ReceivedUnicast 恒 0, NIC 主判据只能用 ReceivedBytes",
            "失败处置: 前置不满足/静默窗未建立 ⇒ 标'判据未取得'; 计数在但线上 0/1 ⇒ 有效负结果(交 S6 分叉)"
        )
        Set-StepResult -Step "S4" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $script:BoardReady) { Set-StepResult -Step "S4" -Verdict "NOT_OBTAINED" -Detail "板卡未就绪"; return }
    $u1 = Get-UState -Title "S4 前置 'U'"
    if ($null -eq $u1 -or -not $u1.ParseOk -or $u1.Mode -ne 1 -or -not (Get-ReqEngineBit $u1)) {
        $eng = Set-EngineMode -Want 1
        Write-Log $eng.Trace
        $u1 = $eng.State
    }
    if ($null -eq $u1 -or -not $u1.ParseOk -or $u1.Mode -ne 1 -or -not (Get-ReqEngineBit $u1)) {
        Set-StepResult -Step "S4" -Verdict "NOT_OBTAINED" -Detail ("前置不满足: " + (Format-UStateBrief $u1))
        return
    }
    $wr0 = Get-WmWr16 $u1
    $rd0 = Get-WmRd16 $u1
    $nb = Get-NicSnapshot
    $p = Invoke-Ping -Count 1 -TimeoutMs 1500 -Title "S4 单帧: ping -n 1 -w 1500"
    Start-Sleep -Milliseconds 300
    $na = Get-NicSnapshot
    $d = Get-NicDelta -Before $nb -After $na
    $u2 = Get-UState -Title "S4 后置 'U'"
    $wr1 = $null; $rd1 = $null
    if ($null -ne $u2 -and $u2.ParseOk) { $wr1 = Get-WmWr16 $u2; $rd1 = Get-WmRd16 $u2 }
    $wrD = $null; $rdD = $null
    if ($null -ne $wr1) { $wrD = (($wr1 - $wr0) % 65536 + 65536) % 65536 }
    if ($null -ne $rd1) { $rdD = (($rd1 - $rd0) % 65536 + 65536) % 65536 }
    Write-Log ("单帧 观测: ping 回包=" + $p.Replies + "/1; NIC " + (Get-NicDeltaText $d) + "; WM_WR+" + $wrD + " WM_RD+" + $rdD)
    if ($null -eq $nb -or $null -eq $na) {
        Set-StepResult -Step "S4" -Verdict "NOT_OBTAINED" -Detail "NIC 统计不可用, 无法判'到没到线上'"
        return
    }
    if (-not $script:QuiesceOk) {
        Set-StepResult -Step "S4" -Verdict "NOT_OBTAINED" -Detail ("S3b 静默窗未建立, 单帧差分基线不干净(backlog); 观测: ping=" + $p.Replies + "/1 WM_RD+" + $rdD)
        return
    }
    if ($p.Replies -eq 1 -and $d.Bytes -ge $script:IcmpReplyBytes -and $wrD -eq 1 -and $rdD -eq 1) {
        Set-StepResult -Step "S4" -Verdict "PASS" -Detail ("单帧端到端: ping 1/1, NIC ReceivedBytes+" + $d.Bytes + " (≥74), WM_WR+1 WM_RD+1")
    } elseif ($wrD -eq 0) {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("单帧未写入(WM_WR+0): 请求未达栈/ICMP 未生成应答（PHY/RX/协议栈侧）")
    } elseif ($rdD -eq 0) {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("单帧写入成功(WM_WR+1)但读侧未推进(WM_RD+0) ⇒ 读出引擎/驻留服务未启动")
    } elseif ($p.Replies -eq 0 -and $d.Bytes -eq 0) {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("有效负结果: 写入+读出均发生(WM_WR+1 WM_RD+1), 但线上 0/1 & NIC ReceivedBytes delta=0 ⇒ 断点在 bridge① 读出之后（交 S6 分叉）")
    } else {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("单帧判据不满足: ping=" + $p.Replies + "/1 NIC=" + (Get-NicDeltaText $d) + " WM_WR+" + $wrD + " WM_RD+" + $rdD)
    }
}

function Step-S5 {
    Write-Section "S5 ping ×4 + NIC delta + 'U' 前后差分（断言 WM_WR/WM_RD 各 +4）"
    if ($script:DryRun) {
        Write-Plan @(
            "前置: 'U' 确认 mode=1 & req.bit24=1",
            "U 前 → ping -n 4 -w 900 192.168.1.10（打印 ping 统计）→ 等 0.3s → U 后",
            "断言: WM_WR +4 且 WM_RD +4（栈应答帧 → bridge① 写入 → bridge① 读出 的硬证据）",
            "同时: ping 4/4 回包 & NIC ReceivedBytes delta>=296（4×74B ICMP 回包）",
            "      注: 板自发帧 dst MAC=广播 ⇒ ReceivedUnicast 恒 0（今天绿位流实测 Unicast=0, Bytes=+296）"
        )
        Set-StepResult -Step "S5" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $script:BoardReady) { Set-StepResult -Step "S5" -Verdict "NOT_OBTAINED" -Detail "板卡未就绪"; return }
    $u1 = Get-UState -Title "S5 前置 'U'"
    if ($null -eq $u1 -or -not $u1.ParseOk -or $u1.Mode -ne 1 -or -not (Get-ReqEngineBit $u1)) {
        $eng = Set-EngineMode -Want 1
        Write-Log $eng.Trace
        $u1 = $eng.State
    }
    if ($null -eq $u1 -or -not $u1.ParseOk -or $u1.Mode -ne 1 -or -not (Get-ReqEngineBit $u1)) {
        Set-StepResult -Step "S5" -Verdict "NOT_OBTAINED" -Detail ("前置不满足: " + (Format-UStateBrief $u1))
        return
    }
    $wr0 = Get-WmWr16 $u1
    $rd0 = Get-WmRd16 $u1
    $nb = Get-NicSnapshot
    $p = Invoke-Ping -Count 4 -TimeoutMs 900 -Title "S5 ping -n 4 -w 900"
    Start-Sleep -Milliseconds 300
    $na = Get-NicSnapshot
    $d = Get-NicDelta -Before $nb -After $na
    $u2 = Get-UState -Title "S5 后置 'U'"
    if ($null -eq $u2 -or -not $u2.ParseOk) {
        Set-StepResult -Step "S5" -Verdict "NOT_OBTAINED" -Detail "后置 'U' 无应答/解析失败"
        return
    }
    $wr1 = Get-WmWr16 $u2
    $rd1 = Get-WmRd16 $u2
    $wrD = (($wr1 - $wr0) % 65536 + 65536) % 65536
    $rdD = (($rd1 - $rd0) % 65536 + 65536) % 65536
    Write-Log ("S5 观测: WM_WR {0}->{1} (+{2})  WM_RD {3}->{4} (+{5})" -f $wr0, $wr1, $wrD, $rd0, $rd1, $rdD)
    if ($null -eq $nb -or $null -eq $na) {
        Set-StepResult -Step "S5" -Verdict "NOT_OBTAINED" -Detail "NIC 统计不可用"
        return
    }
    Write-Log ("S5 观测: ping 回包=" + $p.Replies + "/4; NIC " + (Get-NicDeltaText $d))
    $script:S5State = [pscustomobject]@{
        U1 = $u1; U2 = $u2; Wr0 = $wr0; Wr1 = $wr1; Rd0 = $rd0; Rd1 = $rd1;
        WrD = $wrD; RdD = $rdD; Replies = $p.Replies;
        NicBytes = $d.Bytes; NicBroadcast = $d.Broadcast; NicUnicast = $d.Unicast;
        Clean = $script:QuiesceOk
    }
    if (-not $script:QuiesceOk) {
        Set-StepResult -Step "S5" -Verdict "NOT_OBTAINED" -Detail ("S3b 静默窗未建立; 观测 WM_WR+" + $wrD + " WM_RD+" + $rdD + " ping=" + $p.Replies + "/4")
        return
    }
    if ($wrD -ne 4 -or $rdD -ne 4) {
        if ($wrD -eq 4 -and $rdD -eq 0) {
            Set-StepResult -Step "S5" -Verdict "FAIL" -Detail ("有效负结果: WM_WR+4 但 WM_RD+0 ⇒ 写侧正常、读出侧零启动（引擎/服务/桥① 读 FSM）")
        } elseif ($wrD -eq 0) {
            Set-StepResult -Step "S5" -Verdict "FAIL" -Detail "WM_WR+0: 4 个 ping 没造成栈应答帧写入（RX/协议栈/PHY 侧）"
        } else {
            Set-StepResult -Step "S5" -Verdict "FAIL" -Detail ("断言失败: WM_WR+" + $wrD + " WM_RD+" + $rdD + "（要求各 +4）; ping=" + $p.Replies + "/4 NIC=" + (Get-NicDeltaText $d))
        }
        return
    }
    if ($p.Replies -ne 4) {
        Set-StepResult -Step "S5" -Verdict "FAIL" -Detail ("内部计数 WM_WR+4/WM_RD+4, 但线上回包 " + $p.Replies + "/4 & NIC ReceivedBytes+" + $d.Bytes + " ⇒ 断点在 bridge① 读出之后（S6 分叉 / S7 ILA）")
        return
    }
    if ($d.Bytes -lt (4 * $script:IcmpReplyBytes)) {
        Set-StepResult -Step "S5" -Verdict "FAIL" -Detail ("回包 4/4 但 NIC ReceivedBytes delta=" + $d.Bytes + " <296（4×74B；若为 0 说明回包未被本网卡计入/走错网卡）")
        return
    }
    Set-StepResult -Step "S5" -Verdict "PASS" -Detail ("WM_WR+4 & WM_RD+4 & ping 4/4 & NIC ReceivedBytes+" + $d.Bytes + " ⇒ 读出路径 + 线上均通")
}

function Step-S6 {
    Write-Section "S6 'U' 分叉判据: emit 字段 + S5 NIC delta（第一跳 vs 第二跳）"
    if ($script:DryRun) {
        Write-Plan @(
            "读 'U' emit/req/wm：emit={len[15:0],slot[7:0],byte0}（字节流=8B前导+帧+4B FCS, len=帧长+12）",
            "期望: len=0x56(86, ping 32B: 8+14+20+8+32+4), slot=(WM_WR_last-1)&0xFF, byte0=0x55(前导首字节)",
            "分叉: WM_RD 未推进 ⇒ 判据未取得; emit 空/字段错 ⇒ 断在 shim→bridge① 读出端口;",
            "       emit 正确 + 线上 0/4 ⇒ 断在 bridge① 读出之后(Aurora TX/环回/RX→桥② 读侧→泵B→mux→PHY)",
            "注: dbg_emit 只覆盖第一跳桥①→Aurora TX; 桥②→泵B→mux→PHY 必须靠 S7 ILA 计数"
        )
        Set-StepResult -Step "S6" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if ($null -eq $script:S5State) {
        Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail "S5 未取得数据, 无分叉输入"
        return
    }
    $s5 = $script:S5State
    $u = Get-UState -Title "S6 'U' 回读 (emit/req/wm)"
    if ($null -eq $u -or -not $u.ParseOk) {
        Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail "'U' 无应答/解析失败"
        return
    }
    $emit = [uint32]$u.Emit
    $eLen = [int](($emit -shr 16) -band 0xFFFF)
    $eSlot = [int](($emit -shr 8) -band 0xFF)
    $eByte0 = [int]($emit -band 0xFF)
    $wrNow = Get-WmWr16 $u
    $rdNow = Get-WmRd16 $u
    $expectedSlot = (($wrNow - 1) % 256 + 256) % 256
    $winSlots = @()
    for ($k = 1; $k -le 4; $k++) { $winSlots += ((($wrNow - $k) % 256 + 256) % 256) }
    Write-Log ("emit=0x{0:x8} ⇒ len={1}(0x{1:x}) slot={2} byte0=0x{3:x2}; WM_WR(last)={4} WM_RD(last)={5}" -f $emit, $eLen, $eSlot, $eByte0, $wrNow, $rdNow)
    Write-Log ("期望: len∈{86,74}(ping 32B 含/不含 8B前导+4B FCS), slot=" + $expectedSlot + " byte0=0x55; 最近 4 写槽=" + ($winSlots -join ","))
    $lenOk = ($eLen -eq 86) -or ($eLen -eq 74)
    if ($eLen -eq 74) { Write-Note "emit.len=74（未含 12B 前导/FCS 口径）—— 记录, 不影响分叉" }
    $byteOk = ($eByte0 -eq 0x55)
    $slotExact = ($eSlot -eq $expectedSlot)
    $slotInWin = ($winSlots -contains $eSlot)
    $emitNonZero = ($emit -ne 0) -and ($eLen -gt 0)
    if ($null -eq $s5) { Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail "S5 数据缺失"; return }
    if (-not $s5.Clean) { Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail "S5 基线不干净(S3b 静默窗失败), 分叉输入不可信"; return }
    if ($s5.RdD -ne 4) {
        Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail ("WM_RD 未推进 (S5 +" + $s5.RdD + ") ⇒ 无发射可判, 分叉不成立（先解决读出侧）")
        return
    }
    if (-not $emitNonZero) {
        Set-StepResult -Step "S6" -Verdict "FAIL" -Detail "emit=0/len=0 但 WM_RD 已推进 ⇒ 断点在「shim→bridge① 读出端口」（dbg_emit 未更新）"
        return
    }
    if (-not $lenOk -or -not $byteOk -or -not $slotInWin) {
        Set-StepResult -Step "S6" -Verdict "FAIL" -Detail ("emit 字段错(len={0} slot={1} byte0=0x{2:x2}; 期望 len∈{{86,74}}, slot∈最近4写槽, byte0=0x55) ⇒ 断点在「shim→bridge① 读出端口」" -f $eLen, $eSlot, $eByte0)
        return
    }
    if (-not $slotExact) {
        Write-Log ("WARN: emit.slot=" + $eSlot + " 与最后写槽 " + $expectedSlot + " 不同（但在最近 4 写槽内 ⇒ 读出序≠写入序, 记录不判失败）") "Yellow"
        Write-Note ("S6 emit.slot=" + $eSlot + " ≠ 期望 " + $expectedSlot + "（读出序差）")
    }
    if ($s5.Replies -eq 4 -and $s5.NicBytes -ge (4 * $script:IcmpReplyBytes)) {
        Set-StepResult -Step "S6" -Verdict "PASS" -Detail ("emit 字段正确 + 线上 4/4 + NIC ReceivedBytes+" + $s5.NicBytes + " ⇒ 第一跳(桥①读出)与第二跳(环回/桥②/泵B/PHY)全通")
        return
    }
    if ($s5.Replies -eq 0 -and $s5.NicBytes -eq 0) {
        Set-StepResult -Step "S6" -Verdict "FAIL" -Detail ("读出成功 + emit 正确(len=" + $eLen + " slot=" + $eSlot + " byte0=0x55), 但线上 0/4 & NIC ReceivedBytes delta=0 ⇒ 断点在「bridge① 读出之后」= axis_word_pack→Aurora TX→光纤环回→Aurora RX→bridge② 读侧→泵B→mux→gmii/rgmii/PHY/PC; dbg_emit 对这段零覆盖 ⇒ 用 S7 ILA 计数定位")
        Write-Note "S6 分叉结论: 断点在 bridge① 读出之后（第二跳）; 优先看桥② dbg_mem2_rd_frm/ost（旧位流实测 rd_frm=0/ost 增长 = 桥② 读侧死）"
        return
    }
    Set-StepResult -Step "S6" -Verdict "FAIL" -Detail ("不一致: emit 正确但 ping=" + $s5.Replies + "/4 NIC ReceivedBytes+" + $s5.NicBytes + " ⇒ 再核 NIC 计数/混杂帧, 或 S5 窗口受扰")
}

function Step-S7 {
    Write-Section "S7 ILA 取证命令占位（实际 ILA 由 Lead 跑；本脚本不跑 Vivado/JTAG）"
    $proj = "D:\FPGA\prj\project_11"
    $rdcapRef = Join-Path $script:OutRoot "archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv"
    $lines = @()
    $lines += "# --- S7 ILA 取证（可复制；由 Lead 执行，本脚本不跑 Vivado/JTAG）---"
    $lines += "# 前提: 已烧 rdfix 位流 + 新 ELF; 'U' 回读 mode=1 且 req.bit24=1; 先跑 warm 静默"
    $lines += ""
    $lines += "# [1] 第一跳发射字节流（bridge① 读出 → pack → Aurora TX）：发射流同构 + 前导/payload 逐字节"
    $lines += "py " + $proj + "\out\jb31b_rdcap2_warm.py --send-d --require-dma --drain 2.0 --quiet-wait 6.0"
    $lines += "cmd /c `"set RDCAP_SEND_MODE=retired&& " + $proj + "\out\jb31b_rdcap2.bat`""
    $lines += "#   或分步: vivado -mode batch -source " + $proj + "\out\jb31b_rdcap2.tcl -notrace -log <evid>\rdcap2_retired_vivado.log"
    $lines += "py " + $proj + "\out\jb31b_rdcap2_cmp.py " + $rdcapRef + " <新抓.csv> --expect-prefix 55*7+D5 --expect-len 1526 --mask 8-13,26-27,32-33,-4..-1"
    $lines += "#   掩码依据(rdcap2_cmp_retired.log 实测): dst MAC 8-13=ff:ff:..(静态 ARP 环境板端学不到 PC MAC) / IP ID 26-27 / IP cksum 32-33 / FCS 末4B"
    $lines += ""
    $lines += "# [2] 第二跳计数（Aurora RX → 桥② 读侧 → 泵B；判定 'bridge① 读出之后' 断在哪段）"
    $lines += "vivado -mode batch -source " + $proj + "\out\jb31b_r1cap.tcl -notrace -log <evid>\r1cap.log"
    $lines += "py " + $proj + "\out\jb31b_ilacnt_parse.py <pre_user.csv> <post_user.csv> <pre_ui.csv> <post_ui.csv>"
    $lines += "#   判读: dbg_mem2_wr_frm/ost 增长 而 dbg_mem2_rd_frm==0 ⇒ 断在桥② 读侧;"
    $lines += "#         dbg_mem2_rd_frm 增长 而 pump_rev 无活动 ⇒ 泵B; 两者都有 ⇒ mux/PHY/PC 侧"
    $lines += "#   参考: evidence_2026-10-17/ilacap_counters_summary.txt（旧退役 0ecb8438 实测: 桥② rd_frm 恒 0, ost 19→23 = 桥② 读侧死）"
    $lines += ""
    $lines += "# [3] 若 S6 判 emit 字段错（第一跳就断）: 优先重烧带 probe1 的位流，核对 dbg_mem_rden/mem_rd_data 与 dma_arl"
    $lines += "py " + $proj + "\out\jb31b_rdcap2_cmp.py <绿参考.csv> <新抓.csv>"
    foreach ($l in $lines) { Write-Raw $l }
    Set-StepResult -Step "S7" -Verdict "SKIP" -Detail "占位命令已打印（ILA 由 Lead 执行, 不计失败）"
}

function Step-S8 {
    Write-Section "S8 收口: J3 四链（带 --dma 跑 M/A/B, 默认 nslots=256）+ 发射流/四档命令占位 + UDP 回显核对"
    if ($SkipS8) {
        Set-StepResult -Step "S8" -Verdict "SKIP" -Detail "已用 -SkipS8 关闭"
        return
    }
    $proj = "D:\FPGA\prj\project_11"
    $fourChain = Join-Path $script:OutRoot "j3_fourchains.ps1"
    $udpVerify = "D:\FPGA\prj\project_10\prj_loop\scripts\udp_verify_ddr.py"
    $rdcapRef = Join-Path $script:OutRoot "archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv"
    if ($script:DryRun) {
        $plan = @()
        $plan += "S8a(信息项) py " + $proj + "\out\jb31b_rdcap2_send.py --mode retired --no-uart --echo-wait 6 → 单帧 UDP 回显"
        $plan += "S8b: powershell -File " + $fourChain + " -Run -Port " + $Port + " -Bitstream retired"
        $plan += "     带 --dma 跑 M/A/B（逐轮; nslots 默认 256）——j3 脚本已修预热帧槽泄漏缺陷后 --dma 复验 PASS（2026-10-17 21:2x）；失败不重试"
        $plan += "     前置: 发 'S' + 'U' 轮询直到 wmwr==wmrd 且 req.bit25=0 连续两拍（只读, 不发 'd'）"
        $plan += "     失败纪律: 任一轮 FAIL 即停, 不自动重试; M 轮 wr+255/收帧停摆 ⇒ 判据未取得 + 板卡需重烧"
        $plan += "     不要预先 'd'; 如需 ping 判据由 S3/S4/S5 单独 Set-EngineMode DMA 并断言 req.bit24=1"
        $plan += "S8c: 发射流同构（需 S7 抓取的 CSV）: py " + $proj + "\out\jb31b_rdcap2_cmp.py " + $rdcapRef + " <csv> --expect-prefix 55*7+D5 --expect-len 1526 --mask 8-13,26-27,32-33,-4..-1"
        $plan += "     （不给 -EmitCsv 时只打印占位命令, 记 SKIP；本脚本不跑 Vivado/JTAG）"
        $plan += "S8d: 四档零回归命令占位: py " + $udpVerify + "   （尾部判据 DDR_VERIFY: PASS；--quick 只跑 1/2/3 档）"
        $plan += "     静态 ARP 环境注意: 板端学不到 PC MAC ⇒ 板自发帧 dst MAC=ff:ff:ff:ff:ff:ff;"
        $plan += "     UDP 回显 0/N 而 ping 通时先查广播 dst 因素, 不要急于判数据面坏"
        $plan += "收尾: 重新 Set-EngineMode DMA 并重验 req.bit24=1（M/A/B 轮末会把 R_ENGINE 写回 0）"
        Write-Plan $plan
        Set-StepResult -Step "S8" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $script:BoardReady) { Set-StepResult -Step "S8" -Verdict "NOT_OBTAINED" -Detail "板卡未就绪"; return }
    # ---------- S8a UDP 单帧回显（信息项；广播 dst 环境不硬判） ----------
    $echoInfo = "未执行"
    $udpSend = Join-Path $script:OutRoot "jb31b_rdcap2_send.py"
    if (Test-Path $udpSend) {
        $r = Invoke-Python -ArgList @($udpSend, "--mode", "retired", "--no-uart", "--echo-wait", "6")
        $m = [regex]::Match($r.Text, "echo=(\d+)")
        $echoN = $null
        if ($m.Success) { $echoN = [int]$m.Groups[1].Value }
        $matchYes = ($r.Text -match "match=YES")
        $echoInfo = ("UDP 单帧回显 echo=" + $echoN + " match=" + $matchYes)
        Write-Log ("S8a[信息] " + $echoInfo)
        if ($echoN -ge 1 -and $matchYes) {
            Write-Log "S8a[信息] 数据面单帧 UDP 回显逐字节一致 ✓" "Green"
        } elseif ($null -eq $echoN) {
            Write-Note "S8a UDP 回显脚本输出无法解析"
        } else {
            $pingHint = "ping 状态见 S5"
            if ($null -ne $script:S5State) { $pingHint = ("S5 ping=" + $script:S5State.Replies + "/4 NIC ReceivedBytes+" + $script:S5State.NicBytes) }
            Write-Log ("S8a[WARN] UDP 单帧回显 0/1（" + $pingHint + "）—— 若 ping 通, 先查静态 ARP 环境下板自发帧 dst MAC=ff:ff:ff:ff:ff:ff 的 PC 接收因素; 不要急于判数据面坏") "Yellow"
            Write-Note "S8a UDP 回显 0/1（广播 dst MAC 环境，信息项不计失败）"
        }
    } else {
        Write-Log ("缺 " + $udpSend + " ⇒ S8a 跳过") "Yellow"
    }
    # ---------- S8b J3 四链（带 --dma 跑 M/A/B；失败不重试, wr+255 ⇒ 判据未取得+需重烧） ----------
    $s8bPass = $false
    if (-not (Test-Path $fourChain)) {
        Write-Log ("缺 " + $fourChain + " ⇒ S8b 判据未取得") "Red"
        Set-StepResult -Step "S8b" -Verdict "NOT_OBTAINED" -Detail "缺 j3_fourchains.ps1"
    } else {
        $psExe = "powershell.exe"
        $fcArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $fourChain, "-Run", "-Port", $Port, "-Bitstream", "retired")
        if ($script:PyExe) { $fcArgs += @("-Python", $script:PyExe) }
        Write-Section "S8b 调用 j3_fourchains.ps1（带 --dma 的 M/A/B, nslots=256；前置 'S'+槽表检查, 不预发 'd'）"
        $fc = Invoke-Native -Exe $psExe -ArgList $fcArgs
        $fcPass = ($fc.Text -match "FOURCHAINS_RESULT:\s*PASS") -and ($fc.ExitCode -eq 0)
        if ($fcPass) {
            $s8bPass = $true
            Set-StepResult -Step "S8b" -Verdict "PASS" -Detail "j3_fourchains(Bitstream=retired): 带 --dma 的 M/A/B 全 PASS"
        } elseif ($fc.Text -match "判据未取得") {
            Set-StepResult -Step "S8b" -Verdict "NOT_OBTAINED" -Detail ("j3_fourchains 判据未取得（wr+255/收帧停摆或槽表不干净）⇒ 板卡需重烧; 见 j3_*.log")
        } else {
            Set-StepResult -Step "S8b" -Verdict "FAIL" -Detail ("j3_fourchains 退出码=" + $fc.ExitCode + "；见 j3_m/a/b_*.log")
        }
    }
    # ---------- S8c 发射流同构（可选；需 -EmitCsv） ----------
    $s8cVerdict = "SKIP"
    $s8cDetail = "未提供 -EmitCsv（本脚本不跑 Vivado/JTAG; S7 占位命令抓取后另行比对）"
    $cmpPy = Join-Path $script:OutRoot "jb31b_rdcap2_cmp.py"
    if ($EmitCsv) {
        $csvFull = Resolve-ArtifactPath $EmitCsv
        if (-not $csvFull) {
            $s8cVerdict = "NOT_OBTAINED"; $s8cDetail = "EmitCsv 不存在: $EmitCsv"
        } elseif (-not (Test-Path $cmpPy)) {
            $s8cVerdict = "NOT_OBTAINED"; $s8cDetail = ("缺 " + $cmpPy)
        } elseif (-not (Test-Path $rdcapRef)) {
            $s8cVerdict = "NOT_OBTAINED"; $s8cDetail = ("缺绿参考流 " + $rdcapRef)
        } else {
            Write-Section "S8c 发射流同构比对（掩掉 dst MAC/IP-ID/checksum/FCS）"
            $cmp = Invoke-Python -ArgList @($cmpPy, $rdcapRef, $csvFull, "--expect-prefix", "55*7+D5", "--expect-len", "1526", "--mask", "8-13,26-27,32-33,-4..-1")
            if ($cmp.ExitCode -eq 0 -and ($cmp.Text -match "ISOMORPHIC=YES")) {
                $s8cVerdict = "PASS"; $s8cDetail = "掩码后 0 差异（第一跳发射流同构）"
            } else {
                $s8cVerdict = "FAIL"; $s8cDetail = ("cmp 退出码=" + $cmp.ExitCode + "；见 rdcap2_cmp 输出（区分 dst MAC 广播/真差异）")
            }
        }
    }
    Set-StepResult -Step "S8c" -Verdict $s8cVerdict -Detail $s8cDetail
    # ---------- S8d 四档零回归占位 ----------
    Write-Section "S8d 四档零回归 / 发射流 / 数据面命令占位（可复制）"
    $place = @()
    $place += "# 四档零回归（DDR 写-读往返逐字节）:"
    $place += "py " + $udpVerify
    $place += "#   快速: py " + $udpVerify + " --quick   （档1/2/3）"
    $place += "#   判据: 尾部 DDR_VERIFY: PASS"
    $place += ""
    $place += "# 发射流同构（第一跳; 需 ILA 抓 CSV）:"
    $place += "py " + $cmpPy + " " + $rdcapRef + " <新抓.csv> --expect-prefix 55*7+D5 --expect-len 1526 --mask 8-13,26-27,32-33,-4..-1"
    $place += ""
    $place += "# 若 S8a UDP 回显 0/1 而 ping 通: 静态 ARP 环境(PC 不发 ARP) ⇒ 板端 ARP 学不到 PC MAC"
    $place += "#   ⇒ 板自发帧 dst MAC=ff:ff:ff:ff:ff:ff(广播); 已由 2026-10-17 ILA 发射字节流证实"
    $place += "#   ⇒ 掩掉 dst MAC(8-13)+IP-ID(26-27)+IP cksum(32-33)+FCS(末4B) 后应与绿参考同构"
    foreach ($l in $place) { Write-Raw $l }
    # ---------- 收尾: 只读状态（不在 J3 之后自动发 'd'） ----------
    Write-Section "S8 收尾: 只读状态（不自动发 'd'；J3 轮末 R_ENGINE=0 / R_MODE=RND）"
    $fin = Get-UState -Title "S8 收尾 'U' 回读"
    $finTxt = "(U 无应答)"
    if ($null -ne $fin -and $fin.ParseOk) {
        $finTxt = ("mode={0} bit24={1} wmwr={2} wmrd={3} sticky={4}" -f $fin.Mode, [int](Get-ReqEngineBit $fin), (Get-WmWr16 $fin), (Get-WmRd16 $fin), [int](Get-ReqStickyBit $fin))
    }
    Write-Log ("S8 轮后状态: " + $finTxt)
    Write-Log "NOTE: 如需继续 ping/emit 判据, 请单独 Set-EngineMode DMA 并断言 req.bit24=1（本步不自动发 'd'）" "DarkYellow"
    # ---------- S8 汇总 ----------
    $subs = @()
    foreach ($k in @("S8b", "S8c")) { if ($script:Steps.Contains($k)) { $subs += $script:Steps[$k].Verdict } }
    if ($subs -contains "FAIL" -or $subs -contains "NOT_OBTAINED") { Set-StepResult -Step "S8" -Verdict "FAIL" -Detail "S8b/S8c 见上" }
    else { Set-StepResult -Step "S8" -Verdict "PASS" -Detail ("J3 M/A/B(带 --dma) PASS; 发射流=" + $s8cVerdict + "; " + $echoInfo) }
}

# =============================================================================
#endregion
#region 主流程
# =============================================================================
$modeTxt = "DRY-RUN（只打印计划，不碰板；加 -Run 才真执行）"
if ($Run) { $modeTxt = "RUN（会烧板/串口/ping！）" }
Write-Raw ("=" * 78) "Cyan"
Write-Raw "prj11 路线B 读侧收口 · 退役位流(rdfix) S0-S8 上板判据" "Cyan"
Write-Raw ("脚本版本 " + $script:Version + "   模式: " + $modeTxt) "Cyan"
Write-Raw ("工作目录 " + $script:OutRoot) "Cyan"
Write-Raw ("日志(UTF-8) " + $script:LogPath) "Cyan"
Write-Raw ("目标: 192.168.1.10  PC " + $script:PcIp + "  Port " + $script:Port + "  静态邻居 " + $script:BoardMac) "Cyan"
Write-Raw ("=" * 78) "Cyan"

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONHOME = ""
$env:PYTHONPATH = ""
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ($Run) {
    $usageErr = ""
    if (-not $Bit) { $usageErr += " 缺 -Bit（归档位流绝对路径）;" }
    if (-not $Elf) { $usageErr += " 缺 -Elf（归档 ELF 绝对路径）;" }
    if ($usageErr) {
        Write-Raw ("ARG-ERROR:" + $usageErr) "Red"
        Write-Raw "S0S8_RESULT: FAIL ARG (-Run 需 -Bit/-Elf；dry-run 不需要)" "Red"
        exit 2
    }
}

Step-Preflight
Step-S0
Step-S1
Step-S2
Step-S3
Step-S4
Step-S5
Step-S6
Step-S7
Step-S8

Write-Section "S0-S8 汇总"
foreach ($k in $script:Steps.Keys) { Write-Raw ("  " + $script:Steps[$k].Line) }
if ($script:Notes.Count -gt 0) {
    Write-Log "记录项(NOTE):"
    foreach ($n in $script:Notes) { Write-Raw ("  - " + $n) "Yellow" }
}
Write-Raw ("全量日志: " + $script:LogPath) "Cyan"
if ($script:DryRun) {
    Write-Raw "S0S8_RESULT: SKIP (dry-run —— 未执行任何烧板/串口/ping; 加 -Run 真执行)" "DarkYellow"
    exit 0
}
if ($script:Failures.Count -eq 0) {
    Write-Raw "S0S8_RESULT: PASS" "Green"
    exit 0
}
$first = $script:Failures[0]
$suffix = ""
if ($script:Steps.Contains($first) -and $script:Steps[$first].Verdict -eq "NOT_OBTAINED") { $suffix = " (判据未取得)" }
Write-Raw ("FAILED_STEPS: " + ($script:Failures -join ", ")) "Red"
Write-Raw ("S0S8_RESULT: FAIL " + $first + $suffix) "Red"
exit 1
#endregion
