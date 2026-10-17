# =============================================================================
# r2_board.ps1 - prj11 路线B R2(B3-2 桥①写侧换层 S2MM) 上板判据总控 S0-S11
#
# 默认 DRY-RUN: 只做离线只读真校验(路径/SHA256/构建日志/邻居/NIC/串口枚举/工具齐备),
# 打印完整执行计划; 只有加 -Run 才会真烧板/开串口/发 ping/调 ILA/四档/10MB/J3。
# 本脚本的 PC/离线侧由 script-tools 交付; 硬件在环由 Lead 亲自执行。
#
# ⚠️ 本轮场次状态(2026-10-17 构建 / 10-18 收尾, 以磁盘为准):
#   · 构建结局 = **NO_BITSTREAM**(时序门限 WNS>=0 & WHS>=0 拒收, 5 掷全败; 见
#     archive\b31b_r2_2026-10-17\BUILD_STATUS.md 与 out\r2_sweep*_console.log) ⇒ 无 R2 位流可钉身份
#     ⇒ S0 依赖项判 NOT_OBTAINED; 板验未执行(未烧/未开串口/JTAG/未 ping) ⇒ S2-S11 全部 SKIP。
#   · 等下一次成功位流对(先按 BUILD_STATUS.md §3 主修时序)后再用本脚本 -Run。判据全部保留, 未删除任何一条。
#   · 注意: out\aurora_mem_bridge.bit 仍是 R1 在库 c8cd3a32(10-17 21:28), out\mb_ctrl.xsa 仍是 R1 c9b52dd7;
#     禁止把这两个当 R2 产物烧/钉。
#
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File r2_board.ps1            # DRY-RUN
#   powershell ... -File r2_board.ps1 -Run `
#       -Bit  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\<r2>.bit `
#       -Elf  D:\FPGA\prj\project_11\out\archive\b31b_r2_2026-10-17\<r2>.elf `
#       -BuildLog <R2 构建日志> `
#       [-Port COM5] [-ExpectBitHash8 xxxxxxxx] [-ExpectElfHash8 1bc8088d] `
#       [-Xsa <xsa> -ExpectXsaHash8 xxxxxxxx] [-StrictS2sr] `
#       [-IlaCapture -IlaLtx <归档 probes_r2_<bit8>.ltx>] [-RequireR2Probes] `
#       [-SkipBurn] [-SkipS4] [-SkipS7] [-QuickS7] [-SkipS8] [-SkipS9] [-SkipS11] `
#       [-IlacapUiPre <csv> -IlacapUiPost <csv>] [-AllowNonArchive]
#
# 判据口径(2026-10-17 Lead 裁决 v1.3 + DESIGN v1.2 文档对齐, 依据等级见 AGENTS.md §6a):
#   寄存器协议(软核经 axi_lite_regs, 全部只读 PC 侧):
#     +0x40 WR_REQ 读  = {pending[31],6'b0,toggle[24],slot[23:16],len[15:0]}
#     +0x44 WR_DBG 读  = {fault[31],7'b0,last_alloc_slot[23:16],last_commit_len[15:0]}
#       (注意 A12 语义: last_alloc_slot=最近分配槽, last_commit_len=最近提交帧长; 分配≠提交)
#     +0x48 写(opcode 0x05, 任意值) = 翻 GO(软核完成 S2MM 编程+清 IOC 后写)   ← 只写不读
#     +0x4C 写(opcode 0x06, 任意值) = 翻 ACK(写引擎 fault 恢复: 桥 WD_HALT 从 HALT 退回 IDLE) ← 只写不读
#   'U' 探针新增(真实固件): `[B2] U wreq:` / `[B2] U wdbg:`(各 3 值同址连读)
#      / `[B2] U s2sr:`(S2MM_DMASR 原始值 2 值; bit0=Halted bit1=Idle bit12=IOC 高位=错误位)。
#   异常/超时(DESIGN v1.2 §13/§14, 审计 A3–A6): 四类看门狗统一 24b 0xFFFFFF≈56ms@300MHz
#      · WAITGO 超时 = 良性丢帧(丢帧/pending=0/stat_wr_timeout++/**不置 fault 不停泊**; S2 身份判据依赖该行为)
#      · STREAM/PUSH/WAITDONE 超时 = fail-stop(fault=1, 停泊 WD_HALT(6), 不 commit)
#      · fault 恢复(唯一出口) = 软核 S2MM_DMACR=0x4(reset)→等 Halted→0x1001(RS+IOC)→清 IOC→写 +0x4C(opcode 0x06) 翻 ACK
#   S0 工件身份: bit/ELF SHA256(可 -Expect*Hash8 钉死; 最终冻结 ELF 1bc8088d, 50,896 B, blob ee256c05)
#      + 构建日志 WNS/WHS>=0 + 成功/失败标记 + DRC 0 Errors (+可选 xsa hash)。
#   S1 在位配置记录(不烧绿基线): 离线记录 R1 在位对(c8cd3a32+2961b585) + -Run 时只读
#      'U'/'L'/邻居/ping1 快照, 之后 S2 烧 R2 对 = 唯一变量。
#   S2 身份(烧 R2 对后【不发 'd'】): ping 必须 0/1 + NIC ReceivedBytes delta=0 +
#      wmwr delta=0 三项硬判; WR_REQ.pending 仅 INFO(WAITGO 超时约 56ms 后会良性丢帧 ⇒ ping 后隔久读到
#      pending=0 属预期; pending=1 只在 ~56ms 窗口内可见, 均不硬判)。
#   S3 'd' 后 'U' 双确认: mode=1 & req.bit24=1 硬判; WR_DBG.fault==1 ⇒ FAIL(打印 wdbg/wreq/s2sr);
#      settle 2s 后 WR_REQ.pending 仍=1 仅 WARN; s2sr 默认 WARN(-StrictS2sr 时 Halted=0&错误位=0 硬判);
#      slot<256/len∈[0,1538] 仅 WARN。fault 恢复 = 软核写 +0x4C opcode 0x06 ACK(本脚本只读不写, 只提示)。
#   S3b 静默窗: wmwr==wmrd 且 req.bit25=0 连续两拍(清 S2 残留帧, 建 S4/S5 干净基线)。
#   S4 单帧: ping 1/1 + NIC ReceivedBytes>=74 + WM_WR+1 & WM_RD+1; 打印 s2sr 原始值
#      (S2MM 是否报错/长度异常) + emit 解码(len/slot/byte0; ping32B 期望 len_tab=86 ⇒ 86%64=22
#      天然覆盖尾拍 TKEEP→WSTRB 风险)。若 ping 通但后续字节级判据失败 ⇒ 日志标 TKEEP_SUSPECT。
#   S5 ping×4: 4/4 + ReceivedBytes>=296 + WM_WR/WM_RD 各 +4(打印 s2sr)。
#   S6 桥级 ILA(pre/post 快照): 桥② dbg_mem2_rd_frm +4 & ost 前后 0;
#      桥① dbg_mem_wm/wr_frm/rd_frm 各 +4 & ost 前后 0; R2 新计数 timeout/fault 窗口内 0
#      (ILA3@ui: dbg_s2mm_state[2:0]/tvalid/tready; ILA0@user: dbg_s2mm_reqpend/dbg_wr_fault)。
#      注: dbg_wr_timeout 未挂 ILA(有意省 300MHz ILA3 余量; R1/W6: 300MHz 加 96b 曾 WNS -1.142) 且
#      stat_wr_timeout 无 Lite 读回路径(+0x40/+0x44 不含) ⇒ 上板不可观测, 仅 INFO。
#      可观测替代(INFO): dbg_s2mm_state 编码(0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT)
#      + dbg_wr_fault(ILA0) + 'U' 的 wreq/wdbg/s2sr + ro_wm 是否推进。
#   S7 四档零回归: udp_verify_ddr.py 尾部 DDR_VERIFY: PASS。
#   S8 10MB 100%+SHA: r2_mb10_sha.ps1(json_storm 质量档默认间隔) => R2_MB10_RESULT: PASS。
#   S9 J3 四链(带 --dma): j3_fourchains.ps1 前置 'S'+槽表干净两拍, FOURCHAINS_RESULT: PASS;
#      wr+255/收帧停摆/WAITWR-FAIL ⇒ 先看 WR_DBG.fault, 判据未取得+板卡需重烧; 失败不重试; J3 后不自动 ping。
#   S10 双桥计数对账(J4 口径): 各桥 wm=wr_frm=rd_frm、ost=0; 桥① 错误硬判 len_err/stall +
#      dbg_wr_fault(ILA0@user) 硬判 0; dbg_wr_timeout 未挂 ILA 且 stat_wr_timeout 无 Lite 读回路径 ⇒ INFO; 桥① bresp 恒 0 仅 INFO。
#   S11 收尾恢复: Set-EngineMode DMA(1) 并断言 mode=1 & bit24=1(可 -RestoreEngine 0)。
#
# DESIGN v1.2 文档对齐的其它口径(仅提示, 均不作新硬判):
#   · D8/A11: 桥① AXI 写口退役后 ro_lat_w 在 u_mem 恒 0(B3-0 口径只对桥②/HAS_DMA=0 有意义)
#     ⇒ 禁止用 GET_LATENCY 的桥① 值做判据。
#   · A12: WR_DBG.last_alloc_slot=最近**分配**槽号, last_commit_len=最近**提交**帧长(分配≠提交)。
#   · D4/A9: 离线 TB 只证 DUT 输出流(TKEEP/TLAST/字节); 厂商 IP 的 TKEEP→WSTRB/IOC 行为归板验 S4 后升 L3。
#   · A3/G2: STREAM/PUSH 看门狗分支离线未触发(仅代码审查 [L1]); 板验靠 dbg_s2mm_state=6(HALT)+fault 观测承接。
#
# NIC 判据口径(R1 实测, 静态 ARP): 板自发帧 dst MAC=广播 ⇒ ReceivedUnicast 恒 0,
#   主判据只用 ReceivedBytes(单帧 ICMP 回包 74B / 4 帧 296B), Broadcast 仅辅助打印。
#
# 统一退出语义: PASS / FAIL / NOT_OBTAINED(判据未取得=实验无效) / SKIP; 末尾 R2_RESULT: ...
#   FAIL 与 NOT_OBTAINED 都使退出码非 0(-Run); dry-run 打印 R2_RESULT: SKIP 且退出码 0。
# dry-run 保证: 不烧写(xsct)、不开串口、不发 ping、不跑 Vivado、不发 10MB/四档/J3 ——
#   由 Invoke-BurnPair / Invoke-UartProbe / Invoke-Ping / Invoke-Vivado / Invoke-Python
#   的统一 GUARD 阻断并在末尾打印计数器自证(全 0)。
# =============================================================================
[CmdletBinding()]
param(
    [string]$Bit = "",
    [string]$Elf = "",
    [string]$Port = "COM5",
    [switch]$Run,
    [switch]$SkipBurn,
    [string]$BuildLog = "",
    [string]$ExpectBitHash8 = "",
    [string]$ExpectElfHash8 = "",
    [string]$ExpectRtlBlob = "",
    [string]$Xsa = "",
    [string]$ExpectXsaHash8 = "",
    [string]$GreenBit = "",
    [string]$GreenElf = "",
    [string]$NicAlias = "",
    [string]$Python = "",
    # ---- ILA / 对账(S6/S10) ----
    [string]$IlacapTcl = "",
    [string]$IlaLtx = "",
    [string]$IlaOutDir = "",
    [string]$IlaStimCmd = "",
    [switch]$IlaCapture,
    [switch]$SkipIla,
    [int]$IlaExpectPing = 4,
    [string]$IlacapUiPre = "",
    [string]$IlacapUiPost = "",
    [string]$IlacapUserPre = "",
    [string]$IlacapUserPost = "",
    [switch]$RequireR2Probes,
    [string]$ReconPy = "",
    # ---- 四档 / 10MB / J3 ----
    [string]$FourTierPy = "",
    [switch]$SkipS7,
    [switch]$QuickS7,
    [string]$Mb10Script = "",
    [switch]$SkipS8,
    [int]$Mb10GapMs = 0,
    [string]$J3Script = "",
    [switch]$SkipS9,
    [ValidateSet("auto", "retired", "green")][string]$J3Bitstream = "retired",
    # ---- 收尾/纪律 ----
    [int]$RestoreEngine = 1,
    [switch]$SkipS11,
    [switch]$SkipS2IdentityPing,
    [switch]$SkipDrcRequirement,
    [switch]$StrictS2sr,
    [switch]$AllowNonArchive
)

$ErrorActionPreference = "Continue"
$script:Version = "2026-10-17"
$script:DryRun = -not $Run
$script:OutRoot = $PSScriptRoot
if (-not $script:OutRoot) { $script:OutRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$script:EvidDir = Join-Path $script:OutRoot "evidence_2026-10-17"
$script:Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$script:LogPath = Join-Path $script:EvidDir ("R2_" + $script:Stamp + ".log")
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Steps = [ordered]@{}
$script:Failures = New-Object System.Collections.ArrayList
$script:Notes = New-Object System.Collections.ArrayList
$script:Port = $Port
$script:UartWait = 2.0
$script:UartDrain = 0.25
$script:PyExe = ""
$script:PyPrefix = @()
$script:ResolvedNicAlias = ""
$script:BoardReady = $false
$script:QuiesceOk = $false
$script:LastU = $null
$script:S4State = $null
$script:S5State = $null
$script:S3Ok = $false
$script:WrFaultSeen = $false
$script:TargetIp = "192.168.1.10"
$script:BoardMac = "00-11-22-33-44-55"
$script:PcIp = "192.168.1.102"
$script:IcmpReplyBytes = 74          # ICMP 回包帧 14+20+8+32 = 74B(ping 32B 载荷)
$script:Xsct = "D:\Xilinx\Vitis\2023.1\bin\xsct.bat"
$script:Vivado = "D:\Xilinx\Vivado\2023.1\bin\vivado.bat"
$script:KnownFullPathPy = "C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe"
$script:KnownR1BitHash8 = "c8cd3a32"
$script:KnownR1ElfHash8 = "2961b585"
$script:KnownR2ElfHash8 = "1bc8088d"     # 最终冻结固件(2026-10-17 22:4x Lead 最后一次更新; 50,896 B; blob ee256c05; fa38a8cd/67c0b73a 均已作废)
$script:KnownR2ElfPath = "D:\FPGA\prj\project_11\sw\j3_soft\Debug\j3_soft.elf"
$script:KnownR2XsaPath = Join-Path $script:OutRoot "mb_ctrl.xsa"
$script:FrameMaxLen = 1538           # frame_mem_if.v MAX_LEN
$script:ExpectedArchiveDir = Join-Path $script:OutRoot "archive\b31b_r2_2026-10-17"
$script:R1ArchiveDir = Join-Path $script:OutRoot "archive\b31b_rdfix_2026-10-17"
$script:ProbeInconsistent = New-Object System.Collections.ArrayList
$script:Guard = @{ Burn = 0; Uart = 0; Ping = 0; Vivado = 0; Python = 0 }
$script:IlaCsvUiPre = ""
$script:IlaCsvUiPost = ""
$script:IlaCsvUserPre = ""
$script:IlaCsvUserPost = ""
$script:IlaCaptured = $false
$script:IlaTag = ""
$script:EffectiveNoOut = $false
$script:ToolLogs = New-Object System.Collections.ArrayList

# 路径默认值(参数为空时落到本目录约定位置)
$script:IlacapTclPath = $IlacapTcl
if (-not $script:IlacapTclPath) { $script:IlacapTclPath = Join-Path $script:OutRoot "r2_ilacap.tcl" }
$script:ReconPyPath = $ReconPy
if (-not $script:ReconPyPath) { $script:ReconPyPath = Join-Path $script:OutRoot "r2_counter_recon.py" }
$script:Mb10ScriptPath = $Mb10Script
if (-not $script:Mb10ScriptPath) { $script:Mb10ScriptPath = Join-Path $script:OutRoot "r2_mb10_sha.ps1" }
$script:FourTierPyPath = $FourTierPy
if (-not $script:FourTierPyPath) { $script:FourTierPyPath = "D:\FPGA\prj\project_10\prj_loop\scripts\udp_verify_ddr.py" }
$script:J3ScriptPath = $J3Script
if (-not $script:J3ScriptPath) { $script:J3ScriptPath = Join-Path $script:OutRoot "j3_fourchains.ps1" }
$script:IlaLtxPath = $IlaLtx
if (-not $script:IlaLtxPath) {
    # 归档命名(Lead 2026-10-17 最终): out\archive\b31b_r2_2026-10-17\probes_r2_<bit8>.ltx
    if (Test-Path $script:ExpectedArchiveDir) {
        $ltxCands = @(Get-ChildItem -LiteralPath $script:ExpectedArchiveDir -Filter "probes_r2_*.ltx" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($ltxCands.Count -gt 0) { $script:IlaLtxPath = $ltxCands[0].FullName }
    }
    if (-not $script:IlaLtxPath) { $script:IlaLtxPath = Join-Path $script:ExpectedArchiveDir "probes_r2.ltx" }
}
$script:IlaOutDirPath = $IlaOutDir
if (-not $script:IlaOutDirPath) { $script:IlaOutDirPath = $script:EvidDir }
$script:IlaStimCmdEffective = $IlaStimCmd
if (-not $script:IlaStimCmdEffective) { $script:IlaStimCmdEffective = "ping -n $IlaExpectPing -w 900 192.168.1.10" }
$script:PowerShell51 = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $script:PowerShell51)) { $script:PowerShell51 = "powershell.exe" }

try {
    if (-not (Test-Path $script:EvidDir)) { New-Item -ItemType Directory -Force -Path $script:EvidDir | Out-Null }
    [System.IO.File]::WriteAllText($script:LogPath, "", $script:Utf8Bom)
} catch {
    Write-Host ("FATAL: 无法创建证据目录/日志: " + $_.Exception.Message) -ForegroundColor Red
    exit 2
}

# =============================================================================
#region 通用 IO / 日志 / 判据记录
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
    Write-Raw ("=" * 78) "Cyan"
    Write-Raw ("== " + $Title) "Cyan"
    Write-Raw ("=" * 78) "Cyan"
}

function Write-Plan { param([string[]]$Lines = @()) foreach ($l in $Lines) { Write-Raw ("[PLAN] " + $l) "DarkCyan" } }

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
    if ($Verdict -eq "NOT_OBTAINED") { $tag = "NOT_OBTAINED(判据未取得)" }
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

function Test-GuardBlocked {
    # dry-run 统一拦截: 所有会影响板卡/串口/网络的调用都在这里被阻断并计数(用于自证)
    param([string]$Action, [string]$Key)
    if ($script:DryRun) {
        $script:Guard[$Key] = [int]$script:Guard[$Key] + 1
        Write-Raw ("[GUARD] 已阻断: " + $Action + " (dry-run 下不执行)") "DarkYellow"
        return $true
    }
    return $false
}

function Invoke-Python {
    param([string[]]$ArgList = @(), [string]$TeePath = "")
    if (Test-GuardBlocked -Action ("python " + (($ArgList | Select-Object -First 1))) -Key "Python") {
        return [pscustomobject]@{ Text = "DRYRUN-BLOCKED"; ExitCode = -1 }
    }
    if (-not $script:PyExe) { return [pscustomobject]@{ Text = "PYTHON-UNAVAILABLE"; ExitCode = -1 } }
    $all = @()
    if ($script:PyPrefix.Count -gt 0) { $all += $script:PyPrefix }
    $all += $ArgList
    return Invoke-Native -Exe $script:PyExe -ArgList $all -TeePath $TeePath
}
# =============================================================================
#endregion

# =============================================================================
#region 环境 / 哈希 / 网口 / 串口枚举 / 工件
# =============================================================================
function Resolve-PythonExe {
    # 坑 #45: 优先任务书钉死的全路径解释器; Git Bash 的 python 是 WindowsApps 坏壳(静默退 49)
    if ($script:PyExe) { return $script:PyExe }
    if ($Python) {
        $cmd = Get-Command $Python -ErrorAction SilentlyContinue
        if ($cmd) { $script:PyExe = $cmd.Source; return $script:PyExe }
    }
    foreach ($c in @($script:KnownFullPathPy, "py", "python")) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) {
            $script:PyExe = $cmd.Source
            if ($cmd.Name -eq "py.exe" -or $cmd.Name -eq "py") { $script:PyPrefix = @("-3") }
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

function Get-SerialPortInventory {
    # dry-run 也要"真校验": 打印 PnP 串口枚举 + .NET 端口列表 + 端口来源, 核对 -Port 是否真实存在
    param([string]$Want)
    $lines = New-Object System.Collections.ArrayList
    try {
        $pnp = Get-PnpDevice -Class Ports -ErrorAction Stop | Where-Object { $_.Status -eq "OK" }
        foreach ($d in $pnp) { [void]$lines.Add(("  " + $d.FriendlyName)) }
    } catch {
        [void]$lines.Add("  (Get-PnpDevice 不可用: " + $_.Exception.Message + ")")
    }
    $names = @()
    try { $names = @([System.IO.Ports.SerialPort]::GetPortNames()) } catch { $names = @() }
    return [pscustomobject]@{
        Lines = ($lines -join "`r`n")
        Names = $names
        Present = ($names -contains $Want)
    }
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
    # ★NIC 主判据只用 ReceivedBytes: 静态 ARP 下板自发帧 dst MAC=广播 ⇒ ReceivedUnicast 恒 0
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

function Get-NicDeltaText {
    param($Delta)
    if ($null -eq $Delta) { return "n/a" }
    $b = "n/a"
    if ($null -ne $Delta.Broadcast) { $b = [string]$Delta.Broadcast }
    return ("ReceivedBytes={0}(主判据) ReceivedBroadcast={1} ReceivedUnicast={2}(广播 dst 下不可用)" -f $Delta.Bytes, $b, $Delta.Unicast)
}

# =============================================================================
#endregion
#region UART 探针('U'/'L'/'d'/'S') 与解析
# =============================================================================
function Invoke-UartProbe {
    param([string]$Cmd, [double]$Wait = 2.0, [double]$Drain = 0.25, [string]$Title = "")
    if ($Title) { Write-Section $Title }
    if (Test-GuardBlocked -Action ("串口探针 '" + $Cmd + "' (" + $script:Port + ")") -Key "Uart") {
        return [pscustomobject]@{ Text = "DRYRUN-BLOCKED"; ExitCode = -1 }
    }
    if (-not $script:PyExe) { return [pscustomobject]@{ Text = "PYTHON-UNAVAILABLE"; ExitCode = -1 } }
    $probe = Join-Path $script:OutRoot "uart_probe.py"
    $argv = @($probe, "--port", $script:Port, "--cmd", $Cmd, "--wait", [string]$Wait, "--drain", [string]$Drain, "--raw")
    return Invoke-Native -Exe $script:PyExe -ArgList $argv
}

function Get-UProbeNumber {
    # 'U' 每行首值是上一地址残值 ⇒ 丢首值; 其余要求相等(不等取最后一值并 WARN)
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
    # R2 'U' 行集 = R1 九行 + 新增三行(Lead 2026-10-17 v1.1 冻结固件口径):
    #   [B2] U wreq: <v> <v> <v>   (WR_REQ +0x40, dread 同址连读 3 次, 取最后/相等校验)
    #   [B2] U wdbg: <v> <v> <v>   (WR_DBG +0x44, 同上)
    #   [B2] U s2sr: <v> <v>       (S2MM_DMASR 原始值, 2 次连读; bit0=Halted bit1=Idle bit12=IOC 高位=错误位)
    #   解析正则容忍行内冒号后多个空白; 字段名大小写不敏感。
    param([string]$Text)
    $out = [ordered]@{
        ParseOk = $false; Raw = $Text; Id = $null; Req = $null; ReqX = $null;
        WmRd = $null; Stat = $null; Arl = $null; Emit = $null; WmWr = $null;
        Ust = $null; Mode = $null; Wreq = $null; Wdbg = $null; S2sr = $null; Inconsistent = ""
    }
    if ($script:ProbeInconsistent) { $script:ProbeInconsistent.Clear() }
    $map = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -match "^\[B2\]\s+U\s+mode=(\d+)$") { $out.Mode = [int]$Matches[1]; continue }
        if ($t -match "^\[B2\]\s+U\s+([A-Za-z_]+):\s*(.+)$") { $map[$Matches[1].ToLower()] = $Matches[2] }
    }
    $alias = @{
        id = @("id"); req = @("req"); reqx = @("reqx"); wmrd = @("wmrd"); stat = @("stat");
        arl = @("arl"); emit = @("emit"); wmwr = @("wmwr"); ust = @("ust");
        wreq = @("wreq", "wrreq", "wr_req", "dma_wr_req"); wdbg = @("wdbg", "wrdbg", "wr_dbg", "dma_wr_dbg");
        s2sr = @("s2sr", "dmasr", "s2mm_dmasr")
    }
    foreach ($field in $alias.Keys) {
        $val = $null
        foreach ($name in $alias[$field]) {
            if ($map.ContainsKey($name)) { $val = Get-UProbeNumber -Payload $map[$name] -Field $name; break }
        }
        switch ($field) {
            "id" { $out.Id = $val }
            "req" { $out.Req = $val }
            "reqx" { $out.ReqX = $val }
            "wmrd" { $out.WmRd = $val }
            "stat" { $out.Stat = $val }
            "arl" { $out.Arl = $val }
            "emit" { $out.Emit = $val }
            "wmwr" { $out.WmWr = $val }
            "ust" { $out.Ust = $val }
            "wreq" { $out.Wreq = $val }
            "wdbg" { $out.Wdbg = $val }
            "s2sr" { $out.S2sr = $val }
        }
    }
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

function Send-UartCmd {
    param([string]$Cmd, [double]$Wait = 1.5, [string]$Title = "")
    return Invoke-UartProbe -Cmd $Cmd -Wait $Wait -Drain 0.15 -Title $Title
}

function Get-ReqEngineBit { param($U) if ($null -eq $U -or $null -eq $U.Req) { return $false }; return (($U.Req -band 0x01000000) -ne 0) }
function Get-ReqStickyBit { param($U) if ($null -eq $U -or $null -eq $U.Req) { return $false }; return (($U.Req -band 0x02000000) -ne 0) }
function Get-WmWr16 { param($U) if ($null -eq $U -or $null -eq $U.WmWr) { return $null }; return ([int]($U.WmWr -band 0xFFFF)) }
function Get-WmRd16 { param($U) if ($null -eq $U -or $null -eq $U.WmRd) { return $null }; return ([int]($U.WmRd -band 0xFFFF)) }

# WR_REQ(+0x40) = {pending[31], 6'b0, toggle[24], slot[23:16], len[15:0]}  (DESIGN §4.1)
function Get-WrReqPending { param($U) if ($null -eq $U -or $null -eq $U.Wreq) { return $null }; return ((($U.Wreq -band 0x80000000) -ne 0)) }
function Get-WrReqToggle { param($U) if ($null -eq $U -or $null -eq $U.Wreq) { return $null }; return ([int](($U.Wreq -shr 24) -band 1)) }
function Get-WrReqSlot { param($U) if ($null -eq $U -or $null -eq $U.Wreq) { return $null }; return ([int](($U.Wreq -shr 16) -band 0xFF)) }
function Get-WrReqLen { param($U) if ($null -eq $U -or $null -eq $U.Wreq) { return $null }; return ([int]($U.Wreq -band 0xFFFF)) }
# WR_DBG(+0x44) = {fault[31], 7'b0, last_alloc_slot[23:16], last_commit_len[15:0]}  (DESIGN §4.1)
function Get-WrDbgFault { param($U) if ($null -eq $U -or $null -eq $U.Wdbg) { return $null }; return ((($U.Wdbg -band 0x80000000) -ne 0)) }
function Get-WrDbgSlot { param($U) if ($null -eq $U -or $null -eq $U.Wdbg) { return $null }; return ([int](($U.Wdbg -shr 16) -band 0xFF)) }
function Get-WrDbgLen { param($U) if ($null -eq $U -or $null -eq $U.Wdbg) { return $null }; return ([int]($U.Wdbg -band 0xFFFF)) }
# S2MM_DMASR(+s2sr 探针) 解码: bit0=Halted bit1=Idle bit12=IOC, 高位=错误位(SG/内部错误; 直通模式未定)
#   权威位定义见 Xilinx PG021; 直通(非 SG)下 bit4..bit7 = DMAIntErr/SlaveErr/DecErr/... 等内部错误位。
function Get-S2srHalted { param($U) if ($null -eq $U -or $null -eq $U.S2sr) { return $null }; return (($U.S2sr -band 0x1) -ne 0) }
function Get-S2srIdle { param($U) if ($null -eq $U -or $null -eq $U.S2sr) { return $null }; return (($U.S2sr -band 0x2) -ne 0) }
function Get-S2srIoc { param($U) if ($null -eq $U -or $null -eq $U.S2sr) { return $null }; return (($U.S2sr -band 0x1000) -ne 0) }
function Get-S2srErrBits { param($U) if ($null -eq $U -or $null -eq $U.S2sr) { return $null }; return ([int]($U.S2sr -band 0x00000FF0)) }
function Format-S2sr { param($U) if ($null -eq $U -or $null -eq $U.S2sr) { return "s2sr=n/a" }; return ("s2sr=0x{0:x8}(Halted={1} Idle={2} IOC={3} errbits=0x{4:x3})" -f $U.S2sr, [int](Get-S2srHalted $U), [int](Get-S2srIdle $U), [int](Get-S2srIoc $U), (Get-S2srErrBits $U)) }

function Get-TkeepSuspectHint {
    # Lead v1.1: R2 关键风险 = S2MM 尾拍 TKEEP→WSTRB([L1] 待证)。
    # 触发条件: 线上通路(S4/S5 ping)已通, 但字节级判据(S7 四档/S8 10MB/S9 J3)失败
    #   ⇒ 优先怀疑尾拍 TKEEP 掩码(而非通路/链路), 在判据行标 TKEEP_SUSPECT。
    $onlineOk = $false
    if ($null -ne $script:S4State -and $null -ne $script:S4State.Replies -and [int]$script:S4State.Replies -ge 1) { $onlineOk = $true }
    if ($null -ne $script:S5State -and $null -ne $script:S5State.Replies -and [int]$script:S5State.Replies -ge 4) { $onlineOk = $true }
    if ($onlineOk) {
        return " TKEEP_SUSPECT（S4/S5 线上已通但本次字节级判据失败 ⇒ 优先怀疑 S2MM 尾拍 TKEEP→WSTRB [L1], 查 s2sr/len_tab/ILA dbg_s2mm_*）"
    }
    return ""
}

function Format-UStateBrief {
    param($U)
    if ($null -eq $U -or -not $U.ParseOk) { return "(U 探针无应答/解析失败)" }
    $s = ("mode={0} req=0x{1:x8} engine={2} sticky={3} wmwr={4} wmrd={5} emit=0x{6:x8}" -f `
        $U.Mode, $U.Req, [int](Get-ReqEngineBit $U), [int](Get-ReqStickyBit $U), (Get-WmWr16 $U), (Get-WmRd16 $U), $U.Emit)
    if ($null -ne $U.Wreq) {
        $p = Get-WrReqPending $U
        $s += (" | WR_REQ=0x{0:x8} pending={1} toggle={2} slot={3} len={4}" -f $U.Wreq, [int]$p, (Get-WrReqToggle $U), (Get-WrReqSlot $U), (Get-WrReqLen $U))
    }
    if ($null -ne $U.Wdbg) {
        $f = Get-WrDbgFault $U
        $s += (" | WR_DBG=0x{0:x8} fault={1} slot={2} len={3}" -f $U.Wdbg, [int]$f, (Get-WrDbgSlot $U), (Get-WrDbgLen $U))
    }
    if ($null -ne $U.S2sr) { $s += (" | " + (Format-S2sr $U)) }
    return $s
}

function Test-WrFaultFromU {
    # Lead 裁决: WR_DBG.fault==1 ⇒ FAIL (粘滞; 一旦见过即记)
    param($U)
    if ($null -eq $U -or $null -eq $U.Wdbg) { return $false }
    if ((Get-WrDbgFault $U) -eq $true) { $script:WrFaultSeen = $true; return $true }
    return $false
}

function Set-EngineMode {
    # 'd' 是【翻转】命令(固件 g_dma_mode=!g_dma_mode 并写 R_ENGINE): 回读 mode+req.bit24 双重确认,
    # 不匹配才发 'd', 最多翻转 3 次; 最后必须同时满足 mode=Want 且 bit24=(Want==1)。
    param([int]$Want = 1, [int]$MaxToggles = 3)
    $trace = New-Object System.Collections.ArrayList
    $u = Get-UState -Title ("engine 目标 {0} · 回读 #1" -f $Want)
    $script:LastU = $u
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
        $script:LastU = $u
    }
    return [pscustomobject]@{ Ok = $false; State = $u; Trace = ($trace -join "`n"); Toggles = $MaxToggles }
}

function Wait-QReadQuiesce {
    # 静默窗: wmwr==wmrd 且 req.bit25(sticky)=0 连续两拍 —— 保证 S4/S5 差分基线干净。
    # 注: 本函数只读('U'), 不发 'd'/'S'; 是否处于 DMA 由调用方断言(R2 下 S3 后 engine=1)。
    param([int]$MaxPolls = 10, [switch]$RequireEngine)
    $trace = New-Object System.Collections.ArrayList
    $prev = $null
    for ($i = 0; $i -lt $MaxPolls; $i++) {
        $u = Get-UState -Title ("静默窗回读 #" + ($i + 1)) -Wait 1.6 -Drain 0.15
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
        if ($RequireEngine -and ($u.Mode -ne 1 -or -not (Get-ReqEngineBit $u))) {
            [void]$trace.Add("engine 不是 DMA(mode=1 & bit24=1) —— 停止轮询")
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

function Wait-BoardAliveR2 {
    # 烧写后 boot 探测: 'L' 应答(LAT 行) 或 'U' 解析成功(R2 新固件保留两命令); 兼容两种取先到达者。
    param([int]$TimeoutSec = 40)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $n = 0
    while ((Get-Date) -lt $deadline) {
        $n++
        $r = Invoke-UartProbe -Cmd "L" -Wait 1.2 -Drain 0.15 -Title ("boot 探测 #" + $n + " ('L')")
        if ($r.Text -match "\[B2\] LAT w=") { Write-Log "boot 探测: 'L' 应答([B2] LAT w=...) ✓" "Green"; return $true }
        $u = ConvertFrom-UProbe -Text $r.Text
        if (-not $u.ParseOk) {
            # 'L' 无 LAT 行时再试 'U'(只读)
            $res2 = Invoke-UartProbe -Cmd "U" -Wait 1.6 -Drain 0.15 -Title ("boot 探测 #" + $n + " ('U')")
            $u2 = ConvertFrom-UProbe -Text $res2.Text
            if ($u2.ParseOk) { Write-Log "boot 探测: 'U' 解析成功(固件已在跑) ✓" "Green"; $script:LastU = $u2; return $true }
        }
        Start-Sleep -Milliseconds 1200
    }
    Write-Log ("boot 探测失败: " + $TimeoutSec + "s 内 'L'/'U' 均无预期应答") "Red"
    return $false
}

# =============================================================================
#endregion
#region 烧写 / ping / Vivado / 外部工具
# =============================================================================
function Invoke-BurnPair {
    param([string]$BitPath, [string]$ElfPath)
    if (Test-GuardBlocked -Action ("xsct 烧写 " + (Split-Path -Leaf $BitPath) + " + " + (Split-Path -Leaf $ElfPath)) -Key "Burn") {
        return [pscustomobject]@{ Ok = $false; Text = "DRYRUN-BLOCKED" }
    }
    $burnTcl = Join-Path $script:OutRoot "jb31b_burn_pair.tcl"
    if (-not (Test-Path $burnTcl)) { return [pscustomobject]@{ Ok = $false; Text = ("缺 " + $burnTcl) } }
    if (-not (Test-Path $script:Xsct)) { return [pscustomobject]@{ Ok = $false; Text = ("缺 xsct: " + $script:Xsct) } }
    Write-Section ("烧写(jb31b_burn_pair.tcl): " + (Split-Path -Leaf $BitPath) + " + " + (Split-Path -Leaf $ElfPath))
    $res = Invoke-Native -Exe $script:Xsct -ArgList @($burnTcl, ($BitPath -replace "\\", "/"), ($ElfPath -replace "\\", "/"))
    $ok = ($res.Text -match "PAIR_BURNED")
    if ($ok) { Write-Log "PAIR_BURNED ✓" "Green" } else { Write-Log "烧写未确认(缺 PAIR_BURNED 行)" "Red" }
    return [pscustomobject]@{ Ok = $ok; Text = $res.Text }
}

function Invoke-Ping {
    param([int]$Count = 1, [int]$TimeoutMs = 900, [string]$Title = "")
    $title = $Title
    if (-not $title) { $title = ("ping -n {0} -w {1} {2}" -f $Count, $TimeoutMs, $script:TargetIp) }
    Write-Section $title
    if (Test-GuardBlocked -Action ("ping -n " + $Count + " " + $script:TargetIp) -Key "Ping") {
        return [pscustomobject]@{ Text = "DRYRUN-BLOCKED"; Replies = 0; ExitCode = -1 }
    }
    $res = Invoke-Native -Exe "ping" -ArgList @("-n", [string]$Count, "-w", [string]$TimeoutMs, $script:TargetIp)
    $replies = ([regex]::Matches($res.Text, "TTL=")).Count
    Write-Log ("ping 回包数 = {0}/{1}" -f $replies, $Count) $(if ($replies -ge $Count) { "Green" } else { "Yellow" })
    return [pscustomobject]@{ Text = $res.Text; Replies = $replies; ExitCode = $res.ExitCode }
}

function Invoke-VivadoBatch {
    param([string]$Source, [string]$LogPath, [string]$JournalPath = "")
    if (Test-GuardBlocked -Action ("Vivado batch -source " + (Split-Path -Leaf $Source)) -Key "Vivado") {
        return [pscustomobject]@{ Text = "DRYRUN-BLOCKED"; ExitCode = -1 }
    }
    if (-not (Test-Path $script:Vivado)) { return [pscustomobject]@{ Text = ("缺 vivado: " + $script:Vivado); ExitCode = -1 } }
    $argv = @("-mode", "batch", "-source", $Source, "-notrace", "-log", $LogPath)
    if ($JournalPath) { $argv += @("-journal", $JournalPath) }
    Write-Section ("Vivado batch: " + (Split-Path -Leaf $Source))
    return Invoke-Native -Exe $script:Vivado -ArgList $argv
}

function Invoke-ReconJudge {
    # 调 r2_counter_recon.py, 解析判据行
    param([string[]]$ArgList)
    if (-not (Test-Path $script:ReconPyPath)) {
        return [pscustomobject]@{ Verdict = "NOT_OBTAINED"; Text = ("缺 " + $script:ReconPyPath); Reason = "缺 recon 工具" }
    }
    $all = @($script:ReconPyPath) + $ArgList
    $res = Invoke-Python -ArgList $all
    $verdict = "NOT_OBTAINED"
    if ($res.Text -match "R2_RECON_RESULT:\s*(PASS|FAIL|NOT_OBTAINED)") { $verdict = $Matches[1] }
    $reason = ""
    $m = [regex]::Match($res.Text, "R2_(?:ILA_DELTA|COUNTER_RECON):\s*(PASS|FAIL|NOT_OBTAINED)\s*(.*)")
    if ($m.Success) { $reason = $m.Groups[2].Value.Trim() }
    return [pscustomobject]@{ Verdict = $verdict; Text = $res.Text; Reason = $reason; ExitCode = $res.ExitCode }
}
# =============================================================================
#endregion

# =============================================================================
#region 步骤实现 S0-S3
# =============================================================================
function Step-Preflight {
    Write-Section "P0 预检（只读）：工具/工件/串口/网络仪器"
    $modeTxt = "DRY-RUN"
    if ($Run) { $modeTxt = "RUN（会真烧板/开串口/发 ping/调 Vivado!）" }
    Write-Log ("模式 = " + $modeTxt + "   版本 " + $script:Version)
    Write-Log ("工作目录 = " + $script:OutRoot)
    Write-Log ("证据目录 = " + $script:EvidDir)
    Write-Log ("本次日志 = " + $script:LogPath)
    Write-Log ("目标板 = " + $script:TargetIp + " (" + $script:BoardMac + ")   PC " + $script:PcIp + "   串口 " + $script:Port)

    $py = Resolve-PythonExe
    if ($py) {
        Write-Log ("python = " + $py + "  (prefix args: " + ($script:PyPrefix -join " ") + ")") "Green"
        if ($py -notmatch "pythoncore-3\.14-64") {
            Write-Log "WARN: 非任务书钉死的全路径解释器（坑 #45: Git Bash 的 python 是坏壳, 会静默退 49）" "Yellow"
        }
    } else {
        Write-Log "找不到 python/py（-Python 可指定全路径）—— 串口/ILA 判据将判据未取得" "Red"
    }

    # ---- 串口枚举（dry-run 真校验: 核对 -Port 是否真实存在）----
    $inv = Get-SerialPortInventory -Want $script:Port
    Write-Log ("串口枚举(Get-PnpDevice -Class Ports 状态=OK):")
    Write-Raw $inv.Lines
    Write-Log ("[System.IO.Ports.SerialPort]::GetPortNames() = " + ($inv.Names -join ","))
    if ($inv.Present) {
        Write-Log ("-Port " + $script:Port + " 在枚举列表中 ✓") "Green"
    } else {
        Write-Log ("WARN: -Port " + $script:Port + " 不在枚举列表 —— 若 Lead 实测确认该串口在役, 用 -Port 覆盖; 否则开串口会失败") "Yellow"
        Write-Note ("串口 " + $script:Port + " 未在 GetPortNames() 枚举中（跑前核对）")
    }

    # ---- 工具/依赖齐备 ----
    $tools = [ordered]@{
        "uart_probe.py"          = (Join-Path $script:OutRoot "uart_probe.py")
        "manual_round.py"        = (Join-Path $script:OutRoot "manual_round.py")
        "jb31b_burn_pair.tcl"    = (Join-Path $script:OutRoot "jb31b_burn_pair.tcl")
        "j3_fourchains.ps1"      = $script:J3ScriptPath
        "r2_ilacap.tcl"          = $script:IlacapTclPath
        "r2_counter_recon.py"    = $script:ReconPyPath
        "r2_mb10_sha.ps1"        = $script:Mb10ScriptPath
        "udp_verify_ddr.py"      = $script:FourTierPyPath
        "json_storm.py"          = "D:\FPGA\prj\project_9\scripts\json_storm.py"
        "session_full.jsonl"     = "D:\FPGA\prj\project_9\testdata\session_full.jsonl"
        "xsct.bat"               = $script:Xsct
        "vivado.bat"             = $script:Vivado
    }
    foreach ($k in $tools.Keys) {
        $p = $tools[$k]
        if (Test-Path $p) { Write-Log ("OK   " + $k + " = " + $p) } else { Write-Log ("MISS " + $k + " = " + $p) "Yellow" }
    }

    # ---- 静态邻居 ----
    $nb = Get-NeighborInfo
    Write-Log "静态邻居检查(192.168.1.10 → 00-11-22-33-44-55, Permanent):"
    Write-Raw $nb.Text
    if ($nb.Ok) { Write-Log "邻居 = Permanent ✓（PC 不发 ARP, 板自发帧 dst 为广播）" "Green" }
    else { Write-Log ("邻居异常: State=" + $nb.State + " Mac=" + $nb.Mac + " ⇒ ping 判据会变慢/失真") "Yellow" }

    # ---- NIC 仪器 ----
    $nic = Get-NicAliasResolved
    if ($nic) {
        $snap = Get-NicSnapshot
        if ($null -ne $snap) {
            Write-Log ("NIC = " + $nic + "  ReceivedBytes=" + $snap.Bytes + "  ReceivedBroadcast=" + $snap.Broadcast + "  ReceivedUnicast=" + $snap.Unicast)
            Write-Log "NIC 判据口径: 只用 ReceivedBytes（板自发帧 dst MAC=广播 ⇒ ReceivedUnicast 恒 0, 用它会假 FAIL）"
        } else {
            Write-Log ("NIC " + $nic + " 统计不可用 ⇒ S2/S4/S5 的线上判据将判据未取得") "Red"
        }
    } else {
        Write-Log ("找不到 " + $script:PcIp + " 对应网卡 —— NIC delta 判据将不可用") "Yellow"
    }

    # ---- 工件预览 ----
    if ($Bit) { Write-Log ("-Bit  = " + $Bit + "  hash8=" + (Get-Hash8 (Resolve-ArtifactPath $Bit))) }
    else { Write-Log "-Bit  = <未提供（-Run 必须给 R2 归档位流绝对路径）>" "Yellow" }
    if ($Elf) { Write-Log ("-Elf  = " + $Elf + "  hash8=" + (Get-Hash8 (Resolve-ArtifactPath $Elf))) }
    else { Write-Log "-Elf  = <未提供（-Run 必须给 R2 归档 ELF 绝对路径）>" "Yellow" }
    if ($BuildLog) { Write-Log ("-BuildLog = " + $BuildLog) }
    Write-Log ("R2 归档目录约定 = " + $script:ExpectedArchiveDir)
    Write-Log ("S6 ILA ltx = " + $script:IlaLtxPath + "  (exists=" + (Test-Path $script:IlaLtxPath) + ")")
    Write-Log ("S6 激励命令 = " + $script:IlaStimCmdEffective)
}

function Step-S0 {
    Write-Section "S0 离线工件身份: bit/ELF SHA256 + 构建日志 WNS/WHS + DRC（不碰板）"
    $bitFull = Resolve-ArtifactPath $Bit
    $elfFull = Resolve-ArtifactPath $Elf
    $bitHash = ""; $elfHash = ""
    $missingArtifact = $false
    if ($bitFull) {
        $bitHash = Get-HashFull $bitFull
        Write-Log ("Bit = " + $bitFull)
        Write-Log ("Bit SHA256 = " + $bitHash)
        Write-Log ("Bit hash8  = " + $bitHash.Substring(0, 8))
        $volatileBit = ($bitFull -match "(?i)\\out\\aurora_mem_bridge\.bit$")
        if ($volatileBit) { Write-Log "WARN: -Bit 是 out\aurora_mem_bridge.bit（构建会覆盖; 按纪律 S2 拒绝烧它）" "Yellow" }
        if (-not (Test-ArchivePath $bitFull)) {
            Write-Log "WARN: -Bit 不在 out\archive\ 下 —— 构建会覆盖默认名产物, 必须用归档绝对路径" "Yellow"
            Write-Note ("Bit 非归档路径: " + $bitFull)
        }
    } else {
        $missingArtifact = $true
        Write-Log "Bit = <未提供（本轮构建 NO_BITSTREAM 无 R2 位流；dry-run 记录占位；等下一次成功位流对再用 -Run）>" "Yellow"
    }
    if ($elfFull) {
        $elfHash = Get-HashFull $elfFull
        Write-Log ("Elf = " + $elfFull)
        Write-Log ("Elf SHA256 = " + $elfHash)
        Write-Log ("Elf hash8  = " + $elfHash.Substring(0, 8))
        if (-not (Test-ArchivePath $elfFull)) { Write-Log "WARN: -Elf 不在 out\archive\ 下（重编会覆盖, 建议归档后再跑）" "Yellow" }
    } else {
        $missingArtifact = $true
        Write-Log "Elf = <未提供（dry-run 记录占位; -Run 必须给 R2 归档 ELF）>" "Yellow"
    }
    $hashOk = $true
    if ($ExpectBitHash8 -and $bitFull) {
        $want = $ExpectBitHash8.ToLower()
        if ($bitHash.StartsWith($want)) { Write-Log ("Bit hash8 与期望一致 (" + $want + ") ✓") "Green" }
        else { Write-Log ("Bit hash8 与期望不符: 实际 " + $bitHash.Substring(0, 8) + " ≠ 期望 " + $want) "Red"; $hashOk = $false }
    }
    if ($ExpectElfHash8 -and $elfFull) {
        $want = $ExpectElfHash8.ToLower()
        if ($elfHash.StartsWith($want)) { Write-Log ("Elf hash8 与期望一致 (" + $want + ") ✓") "Green" }
        else { Write-Log ("Elf hash8 与期望不符: 实际 " + $elfHash.Substring(0, 8) + " ≠ 期望 " + $want) "Red"; $hashOk = $false }
    }
    if (-not $ExpectElfHash8) {
        Write-Log ("提示: R2 最终冻结固件 ELF 期望 hash8 = " + $script:KnownR2ElfHash8 + "（50,896 B, blob ee256c05, Lead 2026-10-17 最后一次更新; 路径 " + $script:KnownR2ElfPath + "）; 建议 -ExpectElfHash8 " + $script:KnownR2ElfHash8 + " 钉死身份") "DarkYellow"
        if (Test-Path $script:KnownR2ElfPath) {
            Write-Log ("  当前该路径实算 hash8 = " + (Get-Hash8 $script:KnownR2ElfPath) + " size=" + (Get-Item -LiteralPath $script:KnownR2ElfPath).Length)
        }
    } elseif ($ExpectElfHash8.ToLower() -ne $script:KnownR2ElfHash8) {
        Write-Log ("WARN: -ExpectElfHash8=" + $ExpectElfHash8 + " ≠ 已知 R2 冻结固件 " + $script:KnownR2ElfHash8 + "（若这是 dry-run fixture 场景=R1 归档 ELF, 属预期; -Run 请用 -ExpectElfHash8 " + $script:KnownR2ElfHash8 + "）") "Yellow"
    }

    # ---- xsa 记录（新 xsa 含 S2MM; 可选钉死; 归档名 mb_ctrl_r2.xsa）----
    $xsaPath = $Xsa
    if (-not $xsaPath) {
        $xsaCands = @($script:KnownR2XsaPath, (Join-Path $script:ExpectedArchiveDir "mb_ctrl_r2.xsa"))
        foreach ($c in $xsaCands) { if (-not $xsaPath -and (Test-Path $c)) { $xsaPath = $c } }
    }
    $xsaHash = ""
    if ($xsaPath) {
        $xsaFull = Resolve-ArtifactPath $xsaPath
        if ($xsaFull) {
            $xsaHash = Get-HashFull $xsaFull
            Write-Log ("xsa = " + $xsaFull)
            Write-Log ("xsa SHA256 = " + $xsaHash + "  hash8 = " + $xsaHash.Substring(0, 8) + "  size = " + (Get-Item -LiteralPath $xsaFull).Length)
            if ($ExpectXsaHash8) {
                if ($xsaHash.StartsWith($ExpectXsaHash8.ToLower())) { Write-Log ("xsa hash8 与期望一致 (" + $ExpectXsaHash8 + ") ✓") "Green" }
                else { Write-Log ("xsa hash8 与期望不符: 实际 " + $xsaHash.Substring(0, 8) + " ≠ 期望 " + $ExpectXsaHash8) "Red"; $hashOk = $false }
            }
        } else {
            Write-Log ("WARN: -Xsa 路径无效: " + $xsaPath) "Yellow"
        }
    } else {
        Write-Log "xsa = 未找到 out\mb_ctrl.xsa（可 -Xsa 指定; 非 S0 硬判项）" "DarkYellow"
    }
    Write-Log ("R2 归档命名约定(Lead 2026-10-17 最终): " + $script:ExpectedArchiveDir + "\aurora_mem_bridge_r2_<bit8>.bit / probes_r2_<bit8>.ltx / j3_soft_r2_" + $script:KnownR2ElfHash8 + ".elf / mb_ctrl_r2.xsa / build_r2_synth.log / build_r2_sweep.log / SHA256.txt") "DarkYellow"

    # ---- 构建日志定位（R2: out\r2_sweep.log / out\r2_synth.log；归档 build_r2_sweep.log / build_r2_synth.log；兜底 build_*.log）----
    $buildLogFull = Resolve-ArtifactPath $BuildLog
    if (-not $buildLogFull) {
        if (-not $BuildLog) {
            $logCands = @(
                (Join-Path $script:OutRoot "r2_sweep.log"),
                (Join-Path $script:OutRoot "r2_synth.log"),
                (Join-Path $script:ExpectedArchiveDir "build_r2_sweep.log"),
                (Join-Path $script:ExpectedArchiveDir "build_r2_synth.log")
            )
            foreach ($cand in $logCands) {
                if (-not $buildLogFull -and (Test-Path $cand)) { $buildLogFull = (Resolve-Path -LiteralPath $cand).Path }
            }
            if (-not $buildLogFull -and (Test-Path $script:ExpectedArchiveDir)) {
                $cands = @(Get-ChildItem -LiteralPath $script:ExpectedArchiveDir -Filter "build_*.log" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending)
                if ($cands.Count -gt 0) { $buildLogFull = $cands[0].FullName }
            }
            if ($buildLogFull) { Write-Log ("AUTO: 未给 -BuildLog, 自动采用 = " + $buildLogFull) "Yellow" }
        }
    }
    if (-not $buildLogFull) {
        Write-Log "构建日志未提供(-BuildLog) ⇒ S0 时序门限/DRC 判据未取得: SKIP（非失败; 上板前须由 Lead 人工确认 WNS/WHS≥0 且 DRC 0）" "DarkYellow"
        Set-StepResult -Step "S0" -Verdict "SKIP" -Detail "构建日志未提供；SHA256 已记录, 门限/DRC 未核"
        return
    }
    Write-Log ("BuildLog = " + $buildLogFull)
    $text = ""
    try { $text = Get-Content -LiteralPath $buildLogFull -Raw -Encoding UTF8 } catch { $text = "" }
    if (-not $text) {
        Set-StepResult -Step "S0" -Verdict "NOT_OBTAINED" -Detail "构建日志读取为空/编码失败"
        return
    }
    $wnsList = New-Object System.Collections.ArrayList
    $whsList = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($text, "WNS_GATE:\s*(-?\d+(?:\.\d+)?)")) { [void]$wnsList.Add([double]$m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($text, "WHS_GATE:\s*(-?\d+(?:\.\d+)?)")) { [void]$whsList.Add([double]$m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($text, "SWEEP2?_[A-Za-z]+:\s*WNS=(-?\d+(?:\.\d+)?)")) { [void]$wnsList.Add([double]$m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($text, "SWEEP2?_[A-Za-z]+:\s*WNS=-?\d+(?:\.\d+)?\s+WHS=(-?\d+(?:\.\d+)?)")) { [void]$whsList.Add([double]$m.Groups[1].Value) }
    $okMarker = ($text -match "V5_SWEEP_OK|W5_BUILD_OK|DBG_BUILD_DONE")
    $failMarker = ($text -match "V5_SWEEP_ALL_FAIL|V5_SWEEP2_ALL_FAIL|W5_BUILD_TIMING_FAIL|NO_BITSTREAM")
    $wns = $null; $whs = $null
    if ($wnsList.Count -gt 0) { $wns = $wnsList[$wnsList.Count - 1] }
    if ($whsList.Count -gt 0) { $whs = $whsList[$whsList.Count - 1] }
    $bitInLog = ""
    $mBit = [regex]::Match($text, "(?:V5_SWEEP_OK|DBG_BUILD_DONE)[^\r\n]*bit=([^\s]+)")
    if ($mBit.Success) { $bitInLog = $mBit.Groups[1].Value }
    # ---- 本轮场次专项: 构建 NO_BITSTREAM(无 R2 位流)时的 S0 依赖项口径 ----
    #   仅当未提供 -Bit 且日志显示失败轮(ALL_FAIL/NO_BITSTREAM/负 WNS 扫描)时触发; 不改变成功位流后的判据。
    $noBitstreamTrial = (-not $bitFull) -and (($text -match "NO_BITSTREAM") -or $failMarker -or ($text -match "V5_SWEEP_ALL_FAIL") -or ($text -match "SWEEP2_[A-Za-z]+:\s*WNS=-\d"))
    if ($noBitstreamTrial) {
        Write-Log "本轮构建 = NO_BITSTREAM（时序门限拒收；失败轮不写位流、不覆盖在库产物）⇒ 无 R2 位流可钉身份" "Red"
        Write-Log "S0 判定 = NOT_OBTAINED（依赖项：R2 位流/ltx/xsa 身份未取得）；S2–S11 全部 SKIP；等下一次成功位流对" "Yellow"
        Set-StepResult -Step "S0" -Verdict "NOT_OBTAINED" -Detail ("构建未收口(NO_BITSTREAM): WNS=" + $wns + " WHS=" + $whs + " failMarker=" + $failMarker + "; 无 R2 位流可钉身份, 等下一次成功位流对")
        return
    }
    Write-Log ("WNS(last) = " + $wns) $(if ($null -ne $wns -and $wns -ge 0) { "Green" } else { "Red" })
    Write-Log ("WHS(last) = " + $whs) $(if ($null -ne $whs -and $whs -ge 0) { "Green" } else { "Red" })
    Write-Log ("成功标记(V5_SWEEP_OK|W5_BUILD_OK|DBG_BUILD_DONE) = " + $okMarker)
    Write-Log ("失败标记(V5_SWEEP_ALL_FAIL|V5_SWEEP2_ALL_FAIL|W5_BUILD_TIMING_FAIL|NO_BITSTREAM) = " + $failMarker)
    if ($bitInLog) { Write-Log ("构建日志内位流路径 = " + $bitInLog) }
    if ($bitInLog -and $bitFull) {
        $logLeaf = Split-Path -Leaf ($bitInLog -replace "/", "\")
        $ourLeaf = Split-Path -Leaf $bitFull
        if ($logLeaf -eq $ourLeaf) { Write-Log "构建日志位流文件名与 -Bit 一致 ✓（hash8 仍以本步实算为准）" "Green" }
        else { Write-Log ("构建日志位流文件名(" + $logLeaf + ") ≠ -Bit 文件名(" + $ourLeaf + ") —— 核对是否烧错/归档错") "Yellow" }
    }

    # ---- DRC ----
    $drcErrors = $null
    $mDrc = [regex]::Matches($text, "DRC finished with (\d+) Errors")
    if ($mDrc.Count -gt 0) { $drcErrors = [int]$mDrc[$mDrc.Count - 1].Groups[1].Value }
    $drcErrLines = ([regex]::Matches($text, "ERROR:\s*\[DRC ")).Count
    Write-Log ("DRC Errors = " + $(if ($null -ne $drcErrors) { $drcErrors } else { "未解析到" }) + "  (ERROR: [DRC 行数 = " + $drcErrLines + ")")
    $drcOk = $true
    if ($null -ne $drcErrors) {
        if ($drcErrors -eq 0 -and $drcErrLines -eq 0) { Write-Log "DRC 0 Errors ✓" "Green" }
        else { $drcOk = $false; Write-Log ("DRC 非 0: finished-with-errors=" + $drcErrors + " ERROR 行=" + $drcErrLines) "Red" }
    } elseif (-not $SkipDrcRequirement) {
        $drcOk = $false
        Write-Log "构建日志中未解析到 'DRC finished with N Errors' 行 ⇒ DRC 判据未取得(可用 -SkipDrcRequirement 降级)" "Red"
    } else {
        Write-Log "DRC 行未解析到, 已用 -SkipDrcRequirement 降级为 WARN" "Yellow"
    }

    # ---- RTL blob 指纹（可选; Lead 另给 -ExpectRtlBlob）----
    $rtlBlob = ""
    $mBlob = [regex]::Match($text, "(?i)(?:RTL[_ -]?BLOB|GIT[_ -]?HASH[_ -]?OBJECT|hash-object)[^\r\n]*?([0-9a-f]{7,40})")
    if ($mBlob.Success) { $rtlBlob = $mBlob.Groups[1].Value }
    if ($rtlBlob) { Write-Log ("RTL blob = " + $rtlBlob) }
    else { Write-Log "RTL blob = 构建日志未含（Lead 另行给出 RTL blob 指纹）" "DarkYellow" }
    $blobOk = $true
    if ($ExpectRtlBlob) {
        if (-not $rtlBlob) { Write-Log ("WARN: -ExpectRtlBlob=" + $ExpectRtlBlob + " 但日志无 blob 行 ⇒ 该判据未取得") "Yellow" }
        elseif ($rtlBlob -like ($ExpectRtlBlob + "*")) { Write-Log "RTL blob 与期望一致 ✓" "Green" }
        else { Write-Log ("RTL blob 与期望不符: " + $rtlBlob + " ≠ " + $ExpectRtlBlob) "Red"; $blobOk = $false }
    }

    $bit8 = ""; if ($bitHash.Length -ge 8) { $bit8 = $bitHash.Substring(0, 8) }
    $elf8 = ""; if ($elfHash.Length -ge 8) { $elf8 = $elfHash.Substring(0, 8) }
    $pass = $hashOk -and $blobOk -and $drcOk -and ($null -ne $wns) -and ($null -ne $whs) -and ($wns -ge 0) -and ($whs -ge 0) -and $okMarker -and (-not $failMarker)
    if ($pass) {
        Set-StepResult -Step "S0" -Verdict "PASS" -Detail ("WNS=" + $wns + " WHS=" + $whs + " DRC=0; bit8=" + $bit8 + " elf8=" + $elf8 + " okMarker=有")
    } elseif (-not $hashOk -or -not $blobOk) {
        Set-StepResult -Step "S0" -Verdict "FAIL" -Detail ("工件身份与期望不符: bit8=" + $bit8 + " elf8=" + $elf8 + " blob=" + $rtlBlob)
    } elseif ($drcOk -eq $false -and $null -eq $drcErrors -and -not $SkipDrcRequirement) {
        Set-StepResult -Step "S0" -Verdict "NOT_OBTAINED" -Detail "构建日志无 DRC 行(判据未取得); 时序/标记已核"
    } else {
        Set-StepResult -Step "S0" -Verdict "FAIL" -Detail ("WNS=" + $wns + " WHS=" + $whs + " okMarker=" + $okMarker + " failMarker=" + $failMarker + " DRC=" + $drcErrors + " hashOk=" + $hashOk)
    }
}

function Step-S1 {
    Write-Section "S1 在位配置记录（DESIGN §10: 不烧绿基线; 记录在位配置 = R2 前唯一变量基线）"
    # ---- 离线部分（任何模式都真读） ----
    $volatileBit = Join-Path $script:OutRoot "aurora_mem_bridge.bit"
    if (Test-Path $volatileBit) {
        $fi = Get-Item -LiteralPath $volatileBit
        Write-Log ("当前默认名产物 out\aurora_mem_bridge.bit: hash8=" + (Get-Hash8 $volatileBit) + " size=" + $fi.Length + " mtime=" + $fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
        Write-Log "注: 默认名产物随每次构建变化（R1 证据索引 §6-③）; 判据只认归档绝对路径+实算 hash8" "DarkYellow"
    } else {
        Write-Log ("默认名产物不存在: " + $volatileBit) "DarkYellow"
    }
    $r1Bit = $GreenBit
    $r1Elf = $GreenElf
    if (-not $r1Bit) {
        $c = Join-Path $script:R1ArchiveDir "aurora_mem_bridge_rdfix_c8cd3a32.bit"
        if (Test-Path $c) { $r1Bit = $c }
    }
    if (-not $r1Elf) {
        $c = Join-Path $script:R1ArchiveDir "j3_soft_n7_2961b585.elf"
        if (Test-Path $c) { $r1Elf = $c }
    }
    $r1BitHash = ""; $r1ElfHash = ""
    if ($r1Bit) { $r1BitHash = Get-Hash8 (Resolve-ArtifactPath $r1Bit) }
    if ($r1Elf) { $r1ElfHash = Get-Hash8 (Resolve-ArtifactPath $r1Elf) }
    Write-Log ("在位 R1 修复版对: bit8=" + $r1BitHash + " (" + $r1Bit + ")  elf8=" + $r1ElfHash + " (" + $r1Elf + ")")
    if ($r1BitHash -eq $script:KnownR1BitHash8 -and $r1ElfHash -eq $script:KnownR1ElfHash8) {
        Write-Log "与 R1 已知在位对(c8cd3a32 + 2961b585)一致 ✓" "Green"
    } elseif ($r1Bit -or $r1Elf) {
        Write-Log "WARN: 与 R1 已知在位对(c8cd3a32/2961b585)不一致 —— 在位基线需 Lead 现场确认" "Yellow"
        Write-Note ("S1 在位对 hash8: bit=" + $r1BitHash + " elf=" + $r1ElfHash)
    } else {
        Write-Log "未找到 R1 归档在位对(可 -GreenBit/-GreenElf 指定) —— 只在 -Run 时做只读现场快照" "DarkYellow"
    }
    Write-Log ("目标 R2 对(本脚本 -Bit/-Elf): bit8=" + (Get-Hash8 (Resolve-ArtifactPath $Bit)) + " elf8=" + (Get-Hash8 (Resolve-ArtifactPath $Elf)))

    if ($script:DryRun) {
        Write-Plan @(
            "(离线记录已落盘: 默认名产物 hash8 / R1 在位对 hash8 / R2 目标对 hash8 —— 见上)",
            "本次场次(2026-10-17 构建 NO_BITSTREAM, 板验未执行): S1 判 NOT_OBTAINED; 等下一次成功位流对",
            "只读现场快照(不烧绿基线、不发 'd'):",
            "  'U' 回读 → 记录 mode/req/bit24/wmwr/wmrd/emit/req 原始行",
            "  'L' 回读 → 记录 [B2] LAT w=.. r=..",
            "  Get-NetNeighbor 192.168.1.10 → 要求 Permanent + MAC=00-11-22-33-44-55",
            "  ping -n 1 -w 900 192.168.1.10 → 记录在役配置下是否回包(仅记录, 不判失败)",
            "之后 S2 烧 R2 对 = 唯一变量(不做绿基线烧录对照, 依据 DESIGN §10)"
        )
        Set-StepResult -Step "S1" -Verdict "SKIP" -Detail "dry-run 计划 + 离线在位配置记录已落盘"
        return
    }
    # ---- -Run: 只读现场快照（不烧写）----
    if (-not $script:PyExe) { Set-StepResult -Step "S1" -Verdict "NOT_OBTAINED" -Detail "python 不可用, 无法只读快照"; return }
    $nb = Get-NeighborInfo
    Write-Raw $nb.Text
    $u = Get-UState -Title "S1 在位配置只读 'U'"
    $uTxt = Format-UStateBrief $u
    Write-Log ("S1 在位 'U': " + $uTxt)
    $l = Send-UartCmd -Cmd "L" -Wait 2.0 -Title "S1 在位 'L' 回读(延迟观测)"
    $latOk = ($l.Text -match "\[B2\] LAT w=(\d+) r=(\d+)")
    if ($latOk) { Write-Log ("S1 'L' 应答: " + $Matches[0]) "Green" } else { Write-Log "S1 'L' 未应答/解析失败" "Yellow" }
    $nb0 = Get-NicSnapshot
    $p = Invoke-Ping -Count 1 -TimeoutMs 900 -Title "S1 在位配置 ping -n 1（记录用, 不判失败）"
    Start-Sleep -Milliseconds 300
    $nb1 = Get-NicSnapshot
    $d = Get-NicDelta -Before $nb0 -After $nb1
    Write-Log ("S1 在位观测: 'U'解析=" + $u.ParseOk + " 'L'=" + $latOk + " 邻居OK=" + $nb.Ok + " ping=" + $p.Replies + "/1 NIC " + (Get-NicDeltaText $d))
    $script:S1State = [pscustomobject]@{ U = $u; LatOk = $latOk; NeighborOk = $nb.Ok; Replies = $p.Replies; NicBytes = $(if ($null -ne $d) { $d.Bytes } else { $null }) }
    $recOk = $u.ParseOk -or $latOk
    if ($recOk) {
        Set-StepResult -Step "S1" -Verdict "PASS" -Detail ("在位配置只读记录完成: " + $uTxt + "; 'L'=" + $latOk + " 邻居=" + $nb.Ok + " ping=" + $p.Replies + "/1(仅记录)")
    } else {
        Set-StepResult -Step "S1" -Verdict "NOT_OBTAINED" -Detail "在位配置无 'U'/'L' 应答（板卡不在 R1 配置或串口不可用）; 后续 S2 烧 R2 后重判"
    }
}

function Step-S2 {
    Write-Section "S2 位流身份原位判据: 烧 R2 对, 全程【不发 'd'】"
    $bitFull = Resolve-ArtifactPath $Bit
    $elfFull = Resolve-ArtifactPath $Elf
    if ($script:DryRun) {
        if ($bitFull) { Write-Log ("Bit = " + $bitFull + "  hash8=" + (Get-Hash8 $bitFull)) } else { Write-Log "Bit = <未提供（本轮构建 NO_BITSTREAM 无 R2 位流; 等下一次成功位流对）>" "Yellow" }
        if ($elfFull) { Write-Log ("Elf = " + $elfFull + "  hash8=" + (Get-Hash8 $elfFull)) } else { Write-Log "Elf = <未提供>" }
        Write-Plan @(
            "本次场次无 R2 位流(构建 NO_BITSTREAM) ⇒ S2 判 NOT_OBTAINED(板验未执行), S3-S11 全部 SKIP; 等下一次成功位流对",
            "xsct D:/FPGA/prj/project_11/out/jb31b_burn_pair.tcl <Bit> <Elf>  (归档绝对路径, 先核 SHA256)",
            "等 boot: 'L' 出现 [B2] LAT w=.. 或 'U' 解析成功（'d' 一律不发）",
            "身份判据(三项硬判): ping -n 1 → 必须 0 回包; NIC ReceivedBytes delta=0; 'U' wmwr delta=0",
            "  (R2 位流: 写路径=S2MM 需软核服务, 未发 'd' 时服务未启动 ⇒ 写不提交/读出零启动 ⇒ 不回包)",
            "INFO/WARN: 'U' wreq.pending==1 = 首帧已挂起且未服务（DESIGN §10 S2 期望）; 静态 ARP 下可能无帧触发, 故不硬判",
            "S2a 位置记录: 烧写前在位对 hash8 → 烧写后 'U' hash 不适用(软核无位流 hash), 以 S0 -Expect*Hash8 钉死"
        )
        Set-StepResult -Step "S2" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $bitFull -or -not $elfFull) {
        Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "-Bit/-Elf 未提供或路径无效(-Run 必须给 R2 归档绝对路径)"
        return
    }
    $volatileBit = ($bitFull -match "(?i)\\out\\aurora_mem_bridge\.bit$")
    if ($volatileBit) {
        Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "拒绝烧 out\aurora_mem_bridge.bit（构建会覆盖; 必须用归档绝对路径）"
        return
    }
    $archiveOk = (Test-ArchivePath $bitFull) -and (Test-ArchivePath $elfFull)
    if (-not $archiveOk -and -not $AllowNonArchive) {
        Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "工件不在 out\archive\ 下; 按纪律拒绝烧写（确需加 -AllowNonArchive）"
        return
    }
    if (-not $script:PyExe) { Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "python 不可用"; return }
    if (-not $SkipBurn) {
        $burn = Invoke-BurnPair -BitPath $bitFull -ElfPath $elfFull
        if (-not $burn.Ok) {
            Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "R2 对烧写失败(缺 PAIR_BURNED)"
            $script:BoardReady = $false
            return
        }
        Start-Sleep -Milliseconds 800
        if (-not (Wait-BoardAliveR2 -TimeoutSec 40)) {
            Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "R2 对烧写后 40s 内 'L'/'U' 无应答"
            $script:BoardReady = $false
            return
        }
        $script:BoardReady = $true
    } else {
        Write-Log "-SkipBurn ⇒ 跳过 S2 烧写, 假设板上已是 R2 目标对" "Yellow"
        $script:BoardReady = $true
    }
    if ($SkipS2IdentityPing) {
        Set-StepResult -Step "S2" -Verdict "SKIP" -Detail "已用 -SkipS2IdentityPing 关闭身份 ping"
        return
    }
    # ---- 身份前置: 必须还在 bridge 模式(未发 'd') ----
    $u0 = Get-UState -Title "S2 身份前置 'U'(未发 'd')"
    if ($null -eq $u0 -or -not $u0.ParseOk) {
        Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "'U' 无应答/解析失败, 身份判据未取得"
        return
    }
    $eng0 = Get-ReqEngineBit $u0
    $mode0 = $u0.Mode
    Write-Log ("S2 前置: mode=" + $mode0 + " bit24=" + [int]$eng0 + " (要求均为 0 = 未发 'd' 的出厂态)")
    if ($mode0 -ne 0 -or $eng0) {
        Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail ("烧录后引擎位非 0(mode=" + $mode0 + " bit24=" + [int]$eng0 + ") —— 身份判据前提不成立; 不要为凑判据发 'd', 请重烧后重跑")
        return
    }
    if (Test-WrFaultFromU $u0) { Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "烧录后立即观测到 WR_DBG.fault=1（写路径故障）"; return }
    $wr0 = Get-WmWr16 $u0
    $rd0 = Get-WmRd16 $u0
    $sres = Send-UartCmd -Cmd "S" -Wait 1.5 -Title "S2 恢复 SEQ('S')"
    Start-Sleep -Milliseconds 400
    $nb = Get-NicSnapshot
    $p = Invoke-Ping -Count 1 -TimeoutMs 900 -Title "S2 身份判据: ping -n 1（未发 'd'）"
    Start-Sleep -Milliseconds 400
    $na = Get-NicSnapshot
    $d = Get-NicDelta -Before $nb -After $na
    $u1 = Get-UState -Title "S2 身份后置 'U'"
    $wrDelta = $null
    if ($null -ne $u1 -and $u1.ParseOk) { $wrDelta = ((Get-WmWr16 $u1) - $wr0) % 65536 }
    Write-Log ("S2 观测: ping=" + $p.Replies + "/1; NIC " + (Get-NicDeltaText $d) + "; wmwr " + $wr0 + "->" + $(if ($null -ne $u1 -and $u1.ParseOk) { Get-WmWr16 $u1 } else { "n/a" }) + " (delta=" + $wrDelta + "); mode=" + $(if ($null -ne $u1) { $u1.Mode } else { "n/a" }) + " bit24=" + [int](Get-ReqEngineBit $u1))
    if ($null -ne $u1 -and $u1.ParseOk) {
        if ($null -ne $u1.Wreq) {
            $pend = Get-WrReqPending $u1
            $info = ("WR_REQ=0x{0:x8} pending={1} toggle={2} slot={3} len={4}" -f $u1.Wreq, [int]$pend, (Get-WrReqToggle $u1), (Get-WrReqSlot $u1), (Get-WrReqLen $u1))
            if ($pend -eq $true) { Write-Log ("S2 INFO: " + $info + " —— 首帧已挂起且未服务(~56ms 窗口内可观测) = 写路径未启动; 比三项硬判更强的 R2 身份证据") "Green" }
            else { Write-Log ("S2 INFO: " + $info + " —— ping 后 pending 已落 0: 属预期(WAITGO 超时约 56ms 后良性丢帧, 不置 fault/不停泊; 静态 ARP 下也可能无帧触发); 不硬判") "Gray" }
            if ((Get-WrReqPending $u1) -eq $true) { Write-Log "  (S3 将在 'd' 切 DMA 后确认 pending 落 0)" }
        } else {
            Write-Log "S2 WARN: 'U' 未打印 wreq 字段（固件版本?) —— 身份判据只用三项硬判, 不硬要求该字段" "Yellow"
        }
        Write-Log ("S2 观测: " + (Format-S2sr $u1))
        if (Test-WrFaultFromU $u1) { Set-StepResult -Step "S2" -Verdict "FAIL" -Detail "身份窗口内观测到 WR_DBG.fault=1"; return }
    }
    if ($null -eq $nb -or $null -eq $na) {
        Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "NIC 统计不可用, 无法确认'线上 0 帧'"
        return
    }
    if ($null -eq $wrDelta) {
        Set-StepResult -Step "S2" -Verdict "NOT_OBTAINED" -Detail "后置 'U' 无应答/解析失败, wmwr delta 不可判"
        return
    }
    if ($p.Replies -ge 1) {
        Set-StepResult -Step "S2" -Verdict "FAIL" -Detail ("未发 'd' 却收到 ping 回包 " + $p.Replies + "/1 ⇒ 板上不是 R2 位流(或引擎位已=1): 烧错/烧旧位流")
        return
    }
    if ($wrDelta -ne 0) {
        Set-StepResult -Step "S2" -Verdict "FAIL" -Detail ("未发 'd' 但 wmwr +" + $wrDelta + " ⇒ 写路径在无服务下仍提交帧, 与 R2 身份矛盾(烧错位流?)")
        return
    }
    if ($d.Bytes -ne 0) {
        Set-StepResult -Step "S2" -Verdict "FAIL" -Detail ("未发 'd': ping 0/1 ✓, 但 NIC ReceivedBytes delta=" + $d.Bytes + " ⇒ 有线上收帧, 身份不成立(杂散流量需排查)")
        Write-Note ("S2 期间 NIC ReceivedBytes delta=" + $d.Bytes)
        return
    }
    Set-StepResult -Step "S2" -Verdict "PASS" -Detail ("未发 'd': ping 0/1 + NIC ReceivedBytes delta=0 + wmwr delta=0 ⇒ 写/读路径均未启动(R2 身份) ✓")
}

function Step-S3 {
    Write-Section "S3 切 DMA('d') 后 'U' 双确认: mode=1 & req.bit24=1 硬判; WR_DBG.fault=1 ⇒ FAIL"
    if ($script:DryRun) {
        $plan = @()
        $plan += "Set-EngineMode DMA: 读 'U' mode; 不是 DMA 才发 'd'(翻转) 并回读确认; 最多 3 次"
        $plan += "断言(硬): [B2] U mode=1 且 req.bit24=1"
        $plan += "发 'S' 恢复 SEQ; settle 2s(等驻留服务消费 S2 留下的挂起写请求)"
        $plan += "发 'U' 整段原始行落盘(id/req/reqX/wmrd/stat/arl/emit/wmwr/ust/mode/wreq/wdbg/s2sr; 原始行全文已落日志)"
        $plan += "硬判: WR_DBG.fault==1 ⇒ FAIL（打印 wdbg/wreq/s2sr; fault=1=fail-stop 进 WD_HALT(6); 唯一出口=软核 DMACR reset→RS+IOC→清 IOC→写 +0x4C(opcode 0x06) 翻 ACK; 本脚本只读不写/不重试）"
        $plan += "INFO/WARN: settle 后 WR_REQ.pending 仍=1 只 WARN; slot<256 / len∈[0,1538] 只做合法性 WARN(len=0 允许为'无请求'残值)"
        $plan += "s2sr(S2MM_DMASR): 默认 WARN(Halted=1 或 errbits!=0 记录); -StrictS2sr 时 Halted=0 且 errbits=0 硬判"
        $plan += "S3b 静默窗: 轮询 'U' 直到 wmwr==wmrd 且 req.bit25=0 连续两拍（清 S2 残留帧, 建 S4/S5 干净基线）"
        Write-Plan -Lines $plan
        Set-StepResult -Step "S3" -Verdict "SKIP" -Detail "dry-run 计划"
        Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $script:BoardReady) {
        Set-StepResult -Step "S3" -Verdict "NOT_OBTAINED" -Detail "板卡未就绪(S2 烧写/boot 失败)"
        Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "S3 前置失败"
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
    Start-Sleep -Milliseconds 2000
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
    $script:LastU = $u
    if ($null -ne $u.Wreq) {
        $pend = Get-WrReqPending $u
        $tog = Get-WrReqToggle $u
        $wslot = Get-WrReqSlot $u
        $wlen = Get-WrReqLen $u
        Write-Log ("WR_REQ=0x{0:x8} ⇒ pending={1} toggle={2} slot={3} len={4}" -f $u.Wreq, [int]$pend, $tog, $wslot, $wlen)
        if ($pend -eq $true) { Write-Log "S3 WARN: settle 2s 后 WR_REQ.pending 仍=1（服务未消费; 留证据, 不 FAIL）" "Yellow"; Write-Note "S3 settle 后 WR_REQ.pending 仍=1" }
        if ($wslot -lt 0 -or $wslot -gt 255) { Write-Log ("S3 WARN: WR_REQ.slot=" + $wslot + " 非法(应 <256)") "Yellow" }
        if ($wlen -lt 0 -or $wlen -gt $script:FrameMaxLen) { Write-Log ("S3 WARN: WR_REQ.len=" + $wlen + " 超出 [0," + $script:FrameMaxLen + "]") "Yellow" }
    } else {
        Write-Log "S3 WARN: 'U' 未打印 wreq 字段（固件版本? 请通知 Lead 更新脚本字段名）" "Yellow"
        Write-Note "S3: 'U' 无 wreq 字段"
    }
    if ($null -ne $u.Wdbg) {
        $fault = Get-WrDbgFault $u
        $dslot = Get-WrDbgSlot $u
        $dlen = Get-WrDbgLen $u
        Write-Log ("WR_DBG=0x{0:x8} ⇒ fault={1} last_alloc_slot={2} last_commit_len={3}" -f $u.Wdbg, [int]$fault, $dslot, $dlen)
        if ($fault -eq $true) {
            $script:WrFaultSeen = $true
            Write-Log ("S3 FAIL 上下文: " + (Format-UStateBrief $u)) "Red"
            Write-Log ("S3 FAIL 上下文: " + (Format-S2sr $u)) "Red"
            Write-Log "S3 恢复提示: WR_DBG.fault=1 为粘滞(fail-stop 进 WD_HALT); 唯一出口=软核恢复序列: S2MM_DMACR=0x4(reset)→等 Halted=1→0x1001(RS+IOC)→清 IOC→写 +0x4C(opcode 0x06) 翻 ACK 使桥回 IDLE。本脚本只读、不写寄存器/不重试; 按判据 FAIL 交 Lead 决定重烧或固件恢复。" "Red"
            Set-StepResult -Step "S3" -Verdict "FAIL" -Detail ("WR_DBG.fault=1（写路径故障粘滞; last_alloc_slot=" + $dslot + " last_commit_len=" + $dlen + "; " + (Format-S2sr $u) + "）")
            Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "S3 FAIL"
            return
        }
    } else {
        Write-Log "S3 WARN: 'U' 未打印 wdbg 字段（fault 判据未取得; 不据此 FAIL）" "Yellow"
        Write-Note "S3: 'U' 无 wdbg 字段(fault 判据未取得)"
    }
    # ---- s2sr(S2MM_DMASR): 默认 WARN; -StrictS2sr 时硬判 Halted=0 & errbits=0 ----
    if ($null -ne $u.S2sr) {
        $halted = Get-S2srHalted $u
        $errbits = Get-S2srErrBits $u
        Write-Log ("S3 " + (Format-S2sr $u))
        $s2srBad = ($halted -eq $true) -or ($errbits -ne 0)
        if ($s2srBad) {
            if ($StrictS2sr) {
                Set-StepResult -Step "S3" -Verdict "FAIL" -Detail ("-StrictS2sr: " + (Format-S2sr $u) + "（要求 Halted=0 且 errbits=0）")
                Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "S3 FAIL(StrictS2sr)"
                return
            }
            Write-Log ("S3 WARN: " + (Format-S2sr $u) + " ⇒ 建议断言 Halted=0/错误位=0; 位定义不确定, 默认只 WARN(可用 -StrictS2sr 升硬判)") "Yellow"
            Write-Note ("S3 s2sr 异常: " + (Format-S2sr $u))
        }
    } else {
        Write-Log "S3 WARN: 'U' 未打印 s2sr 字段（S2MM_DMASR 不可观测; 不据此 FAIL）" "Yellow"
        Write-Note "S3: 'U' 无 s2sr 字段"
    }
    if ($bit24 -and ($u.Mode -eq 1)) {
        $script:S3Ok = $true
        Set-StepResult -Step "S3" -Verdict "PASS" -Detail ("req.bit24=1 & mode=1; bit25=" + [int]$bit25 + " slot=" + $slot + " len=" + $len)
    } else {
        Set-StepResult -Step "S3" -Verdict "FAIL" -Detail ("req.bit24=" + [int]$bit24 + " mode=" + $u.Mode + " ⇒ 引擎位未确认 DMA")
        Set-StepResult -Step "S3b" -Verdict "SKIP" -Detail "S3 失败"
        return
    }
    # ---- S3b 静默窗 ----
    $q = Wait-QReadQuiesce -MaxPolls 10 -RequireEngine
    Write-Log $q.Trace
    if ($q.Ok) {
        $script:QuiesceOk = $true
        Set-StepResult -Step "S3b" -Verdict "PASS" -Detail "wmwr==wmrd & sticky=0 连续两拍 ⇒ S4/S5 差分基线干净"
    } else {
        $script:QuiesceOk = $false
        Set-StepResult -Step "S3b" -Verdict "FAIL" -Detail ("静默窗未建立(backlog=" + $q.Backlog + ") ⇒ 读出侧未排空; 后面 S4/S5 自动降级 NOT_OBTAINED")
        Write-Note ("S3b 静默窗失败: backlog=" + $q.Backlog + "（读出侧停摆/服务未运行, 与 R1 H4/H6 同形）")
    }
}
# =============================================================================
#endregion

# =============================================================================
#region 步骤实现 S4-S11
# =============================================================================
function Step-S4 {
    Write-Section "S4 单帧端到端: ping -n 1 + NIC ReceivedBytes + WM_WR/WM_RD 差分 + s2sr"
    if ($script:DryRun) {
        $plan = @()
        $plan += "前置: 'U' 回读 mode=1 & req.bit24=1（不满足先 Set-EngineMode DMA）"
        $plan += "U 前 → ping -n 1 -w 1500 192.168.1.10 → 等 0.3s → U 后"
        $plan += "硬判: ping 1/1 & NIC ReceivedBytes delta>=74（单帧 ICMP 回包 14+20+8+32=74B）& WM_WR+1 & WM_RD+1"
        $plan += "打印: s2sr(S2MM_DMASR) 原始值 + emit 解码 {len,slot,byte0}（ping 32B ⇒ emit len_tab=86 = 64+22, 86%64=22 天然覆盖尾拍 TKEEP→WSTRB）"
        $plan += "附加(R2): WR_DBG.fault=1 ⇒ FAIL; WR_REQ.pending ping 后未落 0 只 WARN; -StrictS2sr 时 Halted=0&errbits=0 硬判"
        $plan += "TKEEP 风险(Lead v1.1 [L1] 待证): 若 ping 通但 S7/S8/S9 字节级判据失败 ⇒ 判据日志标 TKEEP_SUSPECT(见 S7/S8/S9 失败分支)"
        $plan += "失败处置: 前置不满足/静默窗未建立 ⇒ NOT_OBTAINED; 计数在但线上 0/1 ⇒ FAIL(交 S6 分叉)"
        Write-Plan -Lines $plan
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
    if (Test-WrFaultFromU $u1) {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("ping 前已见 WR_DBG.fault=1（写路径故障粘滞; " + (Format-UStateBrief $u1) + "）")
        return
    }
    $wr0 = Get-WmWr16 $u1
    $rd0 = Get-WmRd16 $u1
    $nb = Get-NicSnapshot
    $p = Invoke-Ping -Count 1 -TimeoutMs 1500 -Title "S4 单帧: ping -n 1 -w 1500"
    Start-Sleep -Milliseconds 300
    $na = Get-NicSnapshot
    $d = Get-NicDelta -Before $nb -After $na
    Start-Sleep -Milliseconds 200
    $u2 = Get-UState -Title "S4 后置 'U'"
    $wr1 = $null; $rd1 = $null
    if ($null -ne $u2 -and $u2.ParseOk) { $wr1 = Get-WmWr16 $u2; $rd1 = Get-WmRd16 $u2 }
    $wrD = $null; $rdD = $null
    if ($null -ne $wr1) { $wrD = (($wr1 - $wr0) % 65536 + 65536) % 65536 }
    if ($null -ne $rd1) { $rdD = (($rd1 - $rd0) % 65536 + 65536) % 65536 }
    Write-Log ("单帧观测: ping 回包=" + $p.Replies + "/1; NIC " + (Get-NicDeltaText $d) + "; WM_WR+" + $wrD + " WM_RD+" + $rdD)
    $script:S4State = [pscustomobject]@{ U1 = $u1; U2 = $u2; Wr0 = $wr0; Wr1 = $wr1; Rd0 = $rd0; Rd1 = $rd1; WrD = $wrD; RdD = $rdD; Replies = $p.Replies; NicBytes = $(if ($null -ne $d) { $d.Bytes } else { $null }); Clean = $script:QuiesceOk }
    if ($null -ne $u2 -and $u2.ParseOk) {
        if ($null -ne $u2.Wreq) {
            $pend = Get-WrReqPending $u2
            Write-Log ("R2 WR_REQ(ping 后)=0x{0:x8} pending={1} toggle={2} slot={3} len={4}" -f $u2.Wreq, [int]$pend, (Get-WrReqToggle $u2), (Get-WrReqSlot $u2), (Get-WrReqLen $u2))
            if ($pend -eq $true) { Write-Log "S4 WARN: ping 后 WR_REQ.pending 仍=1（服务未消费该帧; 不 FAIL, 留证据）" "Yellow"; Write-Note "S4: ping 后 pending 仍=1" }
        }
        if ($null -ne $u2.Wdbg) { Write-Log ("R2 WR_DBG(ping 后)=0x{0:x8} fault={1} last_alloc_slot={2} last_commit_len={3}" -f $u2.Wdbg, [int](Get-WrDbgFault $u2), (Get-WrDbgSlot $u2), (Get-WrDbgLen $u2)) }
        # S2MM_DMASR 原始值(TKEEP/长度异常的第一现场)
        if ($null -ne $u2.S2sr) {
            Write-Log ("S4 s2sr(ping 后) " + (Format-S2sr $u2))
            $errbits4 = Get-S2srErrBits $u2
            if ($StrictS2sr -and (($errbits4 -ne 0) -or ((Get-S2srHalted $u2) -eq $true))) {
                Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("-StrictS2sr: ping 后 " + (Format-S2sr $u2) + "（要求 Halted=0 且 errbits=0）")
                return
            } elseif ($errbits4 -ne 0) {
                Write-Log ("S4 WARN: s2sr 错误位非 0 (errbits=0x" + ('{0:x3}' -f $errbits4) + ") ⇒ 优先怀疑 S2MM 长度/TKEEP 相关错误; 记录") "Yellow"
                Write-Note ("S4 s2sr errbits=0x" + ('{0:x3}' -f $errbits4))
            }
        } else {
            Write-Log "S4 WARN: 'U' 无 s2sr 字段(S2MM_DMASR 不可观测; 不据此 FAIL)" "Yellow"
        }
        # emit 解码: 字节流=8B前导+帧+4B FCS ⇒ ping 32B ⇒ 74+12=86; 86%64=22 => 尾拍自然覆盖
        $emit = [uint32]$u2.Emit
        $eLen = [int](($emit -shr 16) -band 0xFFFF)
        $eSlot = [int](($emit -shr 8) -band 0xFF)
        $eByte0 = [int]($emit -band 0xFF)
        Write-Log ("S4 emit=0x{0:x8} ⇒ len={1} slot={2} byte0=0x{3:x2}（期望 len=86=64+22 ⇒ 尾拍 TKEEP 自然覆盖; slot≈(wmwr-1)&0xFF）" -f $emit, $eLen, $eSlot, $eByte0)
        if ($eLen -ne 86 -and $eLen -ne 0) {
            Write-Log ("S4 WARN: emit.len=" + $eLen + " ≠ 86（ping 32B 期望 8B前导+74B帧+4B FCS; 口径差异或帧长异常, 记录）") "Yellow"
            Write-Note ("S4 emit.len=" + $eLen)
        }
        if (Test-WrFaultFromU $u2) {
            Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("ping 后观测到 WR_DBG.fault=1（写路径故障; " + (Format-UStateBrief $u2) + "）")
            return
        }
    }
    if ($null -eq $nb -or $null -eq $na) {
        Set-StepResult -Step "S4" -Verdict "NOT_OBTAINED" -Detail "NIC 统计不可用, 无法判'到没到线上'"
        return
    }
    if (-not $script:QuiesceOk) {
        Set-StepResult -Step "S4" -Verdict "NOT_OBTAINED" -Detail ("S3b 静默窗未建立, 单帧差分基线不干净; 观测: ping=" + $p.Replies + "/1 WM_RD+" + $rdD)
        return
    }
    if ($p.Replies -eq 1 -and $d.Bytes -ge $script:IcmpReplyBytes -and $wrD -eq 1 -and $rdD -eq 1) {
        Set-StepResult -Step "S4" -Verdict "PASS" -Detail ("单帧端到端: ping 1/1, NIC ReceivedBytes+" + $d.Bytes + " (>=74), WM_WR+1 WM_RD+1; " + (Format-S2sr $u2))
    } elseif ($wrD -eq 0) {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail "单帧未写入(WM_WR+0): 请求未达栈/ICMP 未生成应答（PHY/RX/协议栈侧）"
    } elseif ($rdD -eq 0) {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail "单帧写入成功(WM_WR+1)但读侧未推进(WM_RD+0) ⇒ 读出引擎/驻留服务未启动"
    } elseif ($p.Replies -eq 0 -and $d.Bytes -eq 0) {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("有效负结果: 写入+读出均发生(WM_WR+1 WM_RD+1), 但线上 0/1 & NIC ReceivedBytes delta=0 ⇒ 断点在 bridge① 读出之后（交 S6 分叉）")
    } else {
        Set-StepResult -Step "S4" -Verdict "FAIL" -Detail ("单帧判据不满足: ping=" + $p.Replies + "/1 NIC=" + (Get-NicDeltaText $d) + " WM_WR+" + $wrD + " WM_RD+" + $rdD)
    }
}

function Step-S5 {
    Write-Section "S5 ping ×4: NIC ReceivedBytes delta + 'U' 前后差分（WM_WR/WM_RD 各 +4 硬判）"
    if ($script:DryRun) {
        Write-Plan @(
            "前置: 'U' 确认 mode=1 & req.bit24=1 & WR_DBG.fault=0",
            "U 前 → ping -n 4 -w 900 192.168.1.10（打印 ping 统计）→ 等 0.3s → U 后",
            "硬判: WM_WR +4 且 WM_RD +4（栈应答帧 → bridge① 写入 → bridge① 读出 的硬证据）",
            "同时: ping 4/4 回包 & NIC ReceivedBytes delta>=296（4×74B ICMP 回包）",
            "      注: 板自发帧 dst MAC=广播 ⇒ ReceivedUnicast 恒 0（R1 绿位流实测 Unicast=0, Bytes=+296）"
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
    if (Test-WrFaultFromU $u1) {
        Set-StepResult -Step "S5" -Verdict "FAIL" -Detail ("ping 前已见 WR_DBG.fault=1（" + (Format-UStateBrief $u1) + "）")
        return
    }
    $wr0 = Get-WmWr16 $u1
    $rd0 = Get-WmRd16 $u1
    $nb = Get-NicSnapshot
    $p = Invoke-Ping -Count 4 -TimeoutMs 900 -Title "S5 ping -n 4 -w 900"
    Start-Sleep -Milliseconds 300
    $na = Get-NicSnapshot
    $d = Get-NicDelta -Before $nb -After $na
    Start-Sleep -Milliseconds 200
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
    if ($null -ne $u2.Wreq) {
        $pend = Get-WrReqPending $u2
        Write-Log ("R2 WR_REQ(ping×4 后)=0x{0:x8} pending={1} slot={2} len={3}" -f $u2.Wreq, [int]$pend, (Get-WrReqSlot $u2), (Get-WrReqLen $u2))
        if ($pend -eq $true) { Write-Log "S5 WARN: ping×4 后 WR_REQ.pending 仍=1（服务未消费; 不 FAIL）" "Yellow"; Write-Note "S5: pending 仍=1" }
    }
    Write-Log ("S5 观测: " + (Format-S2sr $u2))
    if (Test-WrFaultFromU $u2) {
        Set-StepResult -Step "S5" -Verdict "FAIL" -Detail ("ping×4 后观测到 WR_DBG.fault=1（" + (Format-UStateBrief $u2) + "）")
        return
    }
    Write-Log ("S5 观测: ping 回包=" + $p.Replies + "/4; NIC " + (Get-NicDeltaText $d))
    $script:S5State = [pscustomobject]@{
        U1 = $u1; U2 = $u2; Wr0 = $wr0; Wr1 = $wr1; Rd0 = $rd0; Rd1 = $rd1;
        WrD = $wrD; RdD = $rdD; Replies = $p.Replies;
        NicBytes = $(if ($null -ne $d) { $d.Bytes } else { $null }); NicBroadcast = $(if ($null -ne $d) { $d.Broadcast } else { $null }); NicUnicast = $(if ($null -ne $d) { $d.Unicast } else { $null });
        Clean = $script:QuiesceOk
    }
    if ($null -eq $nb -or $null -eq $na) {
        Set-StepResult -Step "S5" -Verdict "NOT_OBTAINED" -Detail "NIC 统计不可用"
        return
    }
    if (-not $script:QuiesceOk) {
        Set-StepResult -Step "S5" -Verdict "NOT_OBTAINED" -Detail ("S3b 静默窗未建立; 观测 WM_WR+" + $wrD + " WM_RD+" + $rdD + " ping=" + $p.Replies + "/4")
        return
    }
    if ($wrD -ne 4 -or $rdD -ne 4) {
        if ($wrD -eq 4 -and $rdD -eq 0) {
            Set-StepResult -Step "S5" -Verdict "FAIL" -Detail "有效负结果: WM_WR+4 但 WM_RD+0 ⇒ 写侧正常、读出侧零启动（引擎/服务/桥① 读 FSM)"
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
        Set-StepResult -Step "S5" -Verdict "FAIL" -Detail ("回包 4/4 但 NIC ReceivedBytes delta=" + $d.Bytes + " <296（4×74B; 若 0 说明回包未被本网卡计入/走错网卡）")
        return
    }
    Set-StepResult -Step "S5" -Verdict "PASS" -Detail ("WM_WR+4 & WM_RD+4 & ping 4/4 & NIC ReceivedBytes+" + $d.Bytes + " ⇒ 读出路径 + 线上均通")
}

function Step-S6 {
    Write-Section "S6 桥级 ILA 前后快照: 桥② rd_frm+4/ost 回落 + 桥① wm/wr_frm/rd_frm 各 +4"
    if ($SkipIla) {
        Set-StepResult -Step "S6" -Verdict "SKIP" -Detail "已用 -SkipIla 关闭（ILA 判据未取得, S10 需单独给 -IlacapUiPost）"
        return
    }
    if ($script:DryRun) {
        $plan = @()
        $plan += "抓取方式(二选一; 默认不自动抓, 打印可复制命令):"
        $plan += ("  A) -Run -IlaCapture: 自动 vivado batch 跑 " + $script:IlacapTclPath)
        $plan += ("     环境: R2_LTX=" + $script:IlaLtxPath)
        $plan += ("           R2_OUT_DIR=" + $script:IlaOutDirPath)
        $plan += ("           R2_STIM_CMD='" + $script:IlaStimCmdEffective + "' R2_TAG=<ts>")
        $plan += ("     流程: 连 hw_server → set PROBES.FILE → PRE 快照(trigger_now) → 跑 ping -n " + $IlaExpectPing + " → 静默 2s → POST 快照 → CSV")
        $plan += "  B) Lead 手工抓: 用同一 tcl, 或直接用 -IlacapUiPre/-IlacapUiPost 给定 CSV"
        $plan += ("判据: 桥② dbg_mem2_rd_frm 前后 +" + $IlaExpectPing + "(=ping 数) 且 dbg_mem2_ost 前后均 0;")
        $plan += ("      桥① dbg_mem_wm/wr_frm/rd_frm 各 +" + $IlaExpectPing + " 且 dbg_mem_ost 前后均 0;")
        $plan += "      R2 新计数(已与最终 build_synth_only.tcl/build_debug.tcl 对齐): ILA3@ui dbg_s2mm_state[2:0]/tvalid/tready; ILA0@user dbg_s2mm_reqpend/dbg_wr_fault"
        $plan += "      注: dbg_wr_timeout 未挂 ILA 且 stat_wr_timeout 无 Lite 读回路径(+0x40/+0x44 不含) ⇒ 上板不可观测, 仅 INFO, 不硬判"
        $plan += "      可观测替代(INFO): dbg_s2mm_state 编码 0=IDLE 1=WAITGO 2=STREAM 3=PUSH 4=WAITDONE 5=DRAIN 6=HALT"
        $plan += "      （窗口内 dbg_wr_fault 应为 0; 探针缺失则 WARN 不硬判; 可选列见 r2_counter_recon.py）"
        $plan += ("  ⇒ 调 " + (Join-Path $script:OutRoot "r2_counter_recon.py") + " --mode delta 判定; 抓不到 ⇒ NOT_OBTAINED")
        Write-Plan -Lines $plan
        Set-StepResult -Step "S6" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    # ---- 数据来源 1: 显式 CSV ----
    $uiPre = $IlacapUiPre; $uiPost = $IlacapUiPost
    $userPre = $IlacapUserPre; $userPost = $IlacapUserPost
    if ($uiPre -or $uiPost) {
        Write-Log "S6 使用显式给定的 ILA CSV"
    } elseif ($IlaCapture) {
        Write-Log "S6 自动 ILA 抓取(vivado batch)"
        if (-not (Test-Path $script:IlacapTclPath)) { Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail ("缺 ILA 抓取脚本 " + $script:IlacapTclPath); return }
        $tag = "r2_" + $script:Stamp
        $script:IlaTag = $tag
        $vlog = Join-Path $script:IlaOutDirPath ("R2_ilacap_vivado_" + $script:Stamp + ".log")
        $vjou = Join-Path $script:IlaOutDirPath ("R2_ilacap_vivado_" + $script:Stamp + ".jou")
        $env:R2_LTX = $script:IlaLtxPath
        $env:R2_OUT_DIR = $script:IlaOutDirPath
        $env:R2_TAG = $tag
        $env:R2_STIM_CMD = $script:IlaStimCmdEffective
        $env:R2_SETTLE_MS = "2000"
        $env:R2_ILA_MATCH_UI = "dbg_mem2_rd_frm"
        $env:R2_ILA_MATCH_USER = "dbg_mem2_u_wr"
        $env:R2_EXPECT_PROBES = "dbg_s2mm_reqpend,dbg_wr_fault,dbg_s2mm_state,dbg_s2mm_tvalid,dbg_s2mm_tready"
        $vres = Invoke-VivadoBatch -Source $script:IlacapTclPath -LogPath $vlog -JournalPath $vjou
        $capOk = ($vres.Text -match "R2CAP_RESULT:\s*PASS")
        if (-not $capOk) {
            Write-Log "vivado 输出未含 R2CAP_RESULT: PASS ⇒ 抓取失败; 见 " + $vlog "Red"
            Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail ("ILA 抓取失败(见 " + (Split-Path -Leaf $vlog) + "); 常见原因: ltx 与位流不配套/hw_server 未连/探针缺失")
            return
        }
        $uiPre = Join-Path $script:IlaOutDirPath ("R2_ila_" + $tag + "_ui_pre.csv")
        $uiPost = Join-Path $script:IlaOutDirPath ("R2_ila_" + $tag + "_ui_post.csv")
        $userPre = Join-Path $script:IlaOutDirPath ("R2_ila_" + $tag + "_user_pre.csv")
        $userPost = Join-Path $script:IlaOutDirPath ("R2_ila_" + $tag + "_user_post.csv")
        if (-not (Test-Path $uiPre) -or -not (Test-Path $uiPost)) {
            Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail "vivado 报 PASS 但 UI 域 CSV 未落盘（见 " + (Split-Path -Leaf $vlog) + "）"
            return
        }
        [void]$script:ToolLogs.Add($vlog)
    } else {
        $cmd = "vivado -mode batch -source """ + $script:IlacapTclPath + """ -notrace -log """ + (Join-Path $script:IlaOutDirPath ("R2_ilacap_vivado_" + $script:Stamp + ".log")) + """"
        Write-Section "S6 ILA 命令占位(本步未自动抓取; 由 Lead 执行)"
        Write-Raw "# 抓取命令(需先 $env:R2_LTX 指向归档 probes.ltx):" "DarkCyan"
        Write-Raw $cmd "DarkCyan"
        Write-Raw ("# 或给显式 CSV: -IlacapUiPre <csv> -IlacapUiPost <csv> [-IlacapUserPre <csv> -IlacapUserPost <csv>]") "DarkCyan"
        Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail "未抓取 ILA(-IlaCapture 未开/未给 CSV 路径) ⇒ 桥级计数判据未取得"
        return
    }
    $script:IlaCsvUiPre = $uiPre; $script:IlaCsvUiPost = $uiPost
    $script:IlaCsvUserPre = $userPre; $script:IlaCsvUserPost = $userPost
    $script:IlaCaptured = $true
    # ---- 调 recon 判 delta（user 域 CSV 仅在文件真实存在时传入: v1.1 的 dbg_wr_fault/dbg_s2mm_reqpend 在 ILA0@user）----
    $rargs = @("--mode", "delta", "--ui-pre", $uiPre, "--ui-post", $uiPost, "--expect-delta", [string]$IlaExpectPing)
    if ($userPre -and $userPost -and (Test-Path $userPre) -and (Test-Path $userPost)) {
        $rargs += @("--user-pre", $userPre, "--user-post", $userPost)
        Write-Log ("S6 user 域 CSV 一并参与全局错误计数/R2 探针查找: " + (Split-Path -Leaf $userPre) + ", " + (Split-Path -Leaf $userPost))
    } else {
        Write-Log "S6 user 域 CSV 缺失 ⇒ dbg_wr_fault/dbg_s2mm_reqpend 不可观测(仅 INFO, 不硬判)" "Yellow"
    }
    if ($RequireR2Probes) { $rargs += "--require-r2-probes" }
    $jr = Invoke-ReconJudge -ArgList $rargs
    if ($jr.Verdict -eq "PASS") {
        Set-StepResult -Step "S6" -Verdict "PASS" -Detail $jr.Reason
    } elseif ($jr.Verdict -eq "NOT_OBTAINED") {
        Set-StepResult -Step "S6" -Verdict "NOT_OBTAINED" -Detail $jr.Reason
    } else {
        Set-StepResult -Step "S6" -Verdict "FAIL" -Detail $jr.Reason
    }
}

function Step-S7 {
    Write-Section "S7 四档零回归: udp_verify_ddr.py（判据尾部 DDR_VERIFY: PASS）"
    if ($SkipS7) { Set-StepResult -Step "S7" -Verdict "SKIP" -Detail "已用 -SkipS7 关闭"; return }
    if ($script:DryRun) {
        $plan = @()
        $plan += ("py " + $script:FourTierPyPath + $(if ($QuickS7) { " --quick" } else { "" }))
        $plan += "判据: 尾部 DDR_VERIFY: PASS（链路 20/20 · 基础 12/12 · 槽深 12/12 · 稳定 300/300）"
        $plan += "前提: engine=1(S3 后保持); 跑前关闭占用 UDP 1234 的程序"
        $plan += "失败处置: 绑定失败/无回显 ⇒ 先查板卡引擎状态与静态 ARP 广播 dst, 不急于判数据面坏"
        Write-Plan -Lines $plan
        Set-StepResult -Step "S7" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not (Test-Path $script:FourTierPyPath)) {
        Set-StepResult -Step "S7" -Verdict "NOT_OBTAINED" -Detail ("缺 " + $script:FourTierPyPath)
        return
    }
    $tee = Join-Path $script:EvidDir ("R2_4tier_" + $script:Stamp + ".log")
    [System.IO.File]::WriteAllText($tee, "", $script:Utf8Bom)
    $argv = @($script:FourTierPyPath)
    if ($QuickS7) { $argv += "--quick" }
    $res = Invoke-Python -ArgList $argv -TeePath $tee
    [void]$script:ToolLogs.Add($tee)
    $bindFail = ($res.Text -match "绑定 .*失败|Address already in use|\[!\] 绑定")
    $pass = ($res.Text -match "DDR_VERIFY:\s*PASS")
    Write-Log ("四档日志 = " + $tee)
    if ($pass -and $res.ExitCode -eq 0) {
        Set-StepResult -Step "S7" -Verdict "PASS" -Detail ("四档零回归 DDR_VERIFY: PASS（" + $(if ($QuickS7) { "quick: 档1/2/3" } else { "20/20·12/12·12/12·300/300" }) + "）")
    } elseif ($bindFail) {
        Set-StepResult -Step "S7" -Verdict "NOT_OBTAINED" -Detail "UDP 1234 绑定失败/端口占用 ⇒ 实验无效（关占用程序后重跑）"
    } else {
        $hint = Get-TkeepSuspectHint
        if ($hint) { Write-Note ("S7 失败 + " + $hint) }
        Set-StepResult -Step "S7" -Verdict "FAIL" -Detail ("四档未通过(exit=" + $res.ExitCode + "; 尾部无 DDR_VERIFY: PASS); 见 " + (Split-Path -Leaf $tee) + $hint)
    }
}

function Step-S8 {
    Write-Section "S8 10MB 质量档 100%+SHA256: r2_mb10_sha.ps1（json_storm 默认间隔）"
    if ($SkipS8) { Set-StepResult -Step "S8" -Verdict "SKIP" -Detail "已用 -SkipS8 关闭"; return }
    if ($script:DryRun) {
        $plan = @()
        $plan += ("powershell -NoProfile -ExecutionPolicy Bypass -File " + $script:Mb10ScriptPath + " -Run" + $(if ($Mb10GapMs -gt 0) { " -GapMs " + $Mb10GapMs } else { "" }))
        $plan += "质量档参数 = json_storm.py 源码默认（chunk=CHUNK_MAX=1466B, gap-ms=1.0ms; 不传 --pace-us）"
        $plan += "源 = D:\FPGA\prj\project_9\testdata\session_full.jsonl (10,293,111 B)"
        $plan += "判据: exit0 & lost==0 & corrupt==0 & sha_match==true & recv==chunks(100%) + PowerShell 独立复算源/重组 SHA256"
        $plan += "失败处置: 0 回显先查 engine=1/板卡状态/静态 ARP 广播 dst; 不重试"
        Write-Plan -Lines $plan
        Set-StepResult -Step "S8" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not (Test-Path $script:Mb10ScriptPath)) {
        Set-StepResult -Step "S8" -Verdict "NOT_OBTAINED" -Detail ("缺 " + $script:Mb10ScriptPath)
        return
    }
    $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:Mb10ScriptPath, "-Run")
    if ($Mb10GapMs -gt 0) { $psArgs += @("-GapMs", [string]$Mb10GapMs) }
    $res = Invoke-Native -Exe $script:PowerShell51 -ArgList $psArgs
    $mLog = [regex]::Match($res.Text, "全量日志:\s*(.+)")
    if ($mLog.Success) { [void]$script:ToolLogs.Add($mLog.Groups[1].Value.Trim()) }
    if ($res.Text -match "R2_MB10_RESULT:\s*PASS") {
        Set-StepResult -Step "S8" -Verdict "PASS" -Detail "10MB 100% 逐片回显 + SHA256 一致（独立复算源/重组双核对; 见 R2_mb10_*.log）"
    } elseif ($res.Text -match "R2_MB10_RESULT:\s*NOT_OBTAINED") {
        Set-StepResult -Step "S8" -Verdict "NOT_OBTAINED" -Detail "10MB 质量档判据未取得（端口占用/脚本异常/无 summary）"
    } else {
        $hint = Get-TkeepSuspectHint
        if ($hint) { Write-Note ("S8 失败 + " + $hint) }
        Set-StepResult -Step "S8" -Verdict "FAIL" -Detail ("10MB 质量档未通过(exit=" + $res.ExitCode + "); 见 R2_mb10_*.log" + $hint)
    }
}

function Step-S9 {
    Write-Section "S9 J3 四链（带 --dma; 前置 'S' + 槽表干净两拍; 失败不重试, J3 后不自动 ping）"
    if ($SkipS9) { Set-StepResult -Step "S9" -Verdict "SKIP" -Detail "已用 -SkipS9 关闭"; return }
    if ($script:DryRun) {
        $plan = @()
        $plan += "前置: 发 'S' → 轮询 'U' 直到 wmwr==wmrd 且 req.bit25=0 连续两拍（只读, 不发 'd'; 由本脚本先做）"
        $plan += "  若前置不干净 ⇒ NOT_OBTAINED + 板卡需重烧, 不跑 J3（避免槽满级联假 FAIL）"
        $plan += ("powershell -NoProfile -File " + $script:J3ScriptPath + " -Run -Port " + $script:Port + " -Bitstream " + $J3Bitstream)
        $plan += "  该脚本内部带 --dma 跑 M/A/B 逐轮; nslots 默认 256; 任一轮 FAIL 即停不重试"
        $plan += "判据: FOURCHAINS_RESULT: PASS; wr+255/收帧停摆/WAITWR-FAIL ⇒ 判据未取得 + 板卡需重烧"
        $plan += "  WAITWR-FAIL 首查 WR_DBG.fault==1(写引擎 HALT; 需软核写 +0x4C ACK 恢复或重烧), 不重试"
        $plan += "J3 只读收尾; 其后不自动 ping（R1 纪律: 轮末 R_ENGINE=0/R_MODE=RND）"
        Write-Plan -Lines $plan
        Set-StepResult -Step "S9" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not (Test-Path $script:J3ScriptPath)) { Set-StepResult -Step "S9" -Verdict "NOT_OBTAINED" -Detail ("缺 " + $script:J3ScriptPath); return }
    # ---- 外层前置: 'S' + 只读槽表检查(两拍) ----
    $sres = Send-UartCmd -Cmd "S" -Wait 1.2 -Title "S9 前置 'S' 恢复 SEQ"
    Start-Sleep -Milliseconds 300
    $q = Wait-QReadQuiesce -MaxPolls 8
    Write-Log $q.Trace
    if (-not $q.Ok) {
        Set-StepResult -Step "S9" -Verdict "NOT_OBTAINED" -Detail ("J3 前置槽表不干净(backlog=" + $q.Backlog + ") ⇒ 判据未取得; 板卡需重烧后再跑（不重试）")
        return
    }
    Write-Log "J3 前置清槽检查通过 ✓（wmwr==wmrd & bit25=0 连续两拍）" "Green"
    $psArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:J3ScriptPath, "-Run", "-Port", $script:Port, "-Bitstream", $J3Bitstream)
    if ($script:PyExe) { $psArgs += @("-Python", $script:PyExe) }
    $res = Invoke-Native -Exe $script:PowerShell51 -ArgList $psArgs
    $pass = ($res.Text -match "FOURCHAINS_RESULT:\s*PASS") -and ($res.ExitCode -eq 0)
    $notobt = ($res.Text -match "判据未取得") -or ($res.Text -match "wr\+=2[0-5]\d") -or ($res.Text -match "收帧停摆") -or ($res.Text -match "WAITWR-FAIL")
    $mLog = [regex]::Match($res.Text, "日志:\s*(.+)")
    if ($mLog.Success) {
        $jl = $mLog.Groups[1].Value.Trim()
        if (Test-Path $jl) { [void]$script:ToolLogs.Add($jl) }
    }
    if ($pass) {
        Set-StepResult -Step "S9" -Verdict "PASS" -Detail ("j3_fourchains(Bitstream=" + $J3Bitstream + "): 带 --dma 的 M/A/B 全 PASS")
    } elseif ($notobt) {
        # Lead v1.1 + DESIGN v1.2: WAITWR-FAIL/wr+255 首查 WR_DBG.fault; fault=1 ⇒ fail-stop 进 WD_HALT(6),
        # 唯一出口 = 软核 DMACR reset→RS+IOC→清 IOC→写 +0x4C(opcode 0x06) 翻 ACK; 否则重烧
        $fu = Get-UState -Title "S9 失败现场 'U'（查 WR_DBG.fault）"
        $faultTxt = ""
        if ($null -ne $fu -and $fu.ParseOk) {
            $faultTxt = "; " + (Format-UStateBrief $fu) + "; " + (Format-S2sr $fu)
            if (Test-WrFaultFromU $fu) {
                $faultTxt = "; WR_DBG.fault=1 ⇒ 写引擎 fail-stop(WD_HALT): 需软核恢复序列(DMACR reset→RS+IOC→清 IOC→写 +0x4C opcode 0x06 翻 ACK)或重烧（本脚本不写寄存器/不重试）" + $faultTxt
            }
        }
        Set-StepResult -Step "S9" -Verdict "NOT_OBTAINED" -Detail ("J3 wr+255/收帧停摆/WAITWR-FAIL ⇒ 判据未取得 + 板卡需重烧; 不自动重试（见 j3_*.log）" + $faultTxt)
    } else {
        $hint = Get-TkeepSuspectHint
        if ($hint) { Write-Note ("S9 失败 + " + $hint) }
        Set-StepResult -Step "S9" -Verdict "FAIL" -Detail ("j3_fourchains 退出码=" + $res.ExitCode + "; 见 j3_*.log" + $hint)
    }
    # ---- J3 后只读状态; 不自动 ping ----
    $fin = Get-UState -Title "S9 J3 后只读 'U'（不自动 ping）"
    $finTxt = Format-UStateBrief $fin
    Write-Log ("J3 后只读状态: " + $finTxt)
    Write-Log "NOTE: 轮末固件把 R_ENGINE 写回 0、R_MODE 停 RND（R1 纪律）; 后续如需 ping 判据须重新 Set-EngineMode DMA —— 本脚本 S11 会做收尾恢复" "DarkYellow"
}

function Step-S10 {
    Write-Section "S10 双桥计数对账（J4 口径: mem/mem2 各自 wm=wr_frm=rd_frm、ost=0、错误计数 0）"
    if ($script:DryRun) {
        $plan = @()
        $plan += "数据来源: S6 的 post CSV（cumulative，静默后口径; 不另开 Vivado 会话）"
        $plan += "  或显式: -IlacapUiPost <csv> [-IlacapUserPost <csv>]"
        $plan += ("py " + $script:ReconPyPath + " --mode recon --ui-post <post.csv>" + $(if ($RequireR2Probes) { " --require-r2-probes" } else { "" }))
        $plan += "判据: 每桥 wm==wr_frm==rd_frm; ost=0; 错误计数 stall/len_err 0;"
        $plan += "      桥① 错误硬判 len_err/stall; dbg_wr_fault(ILA0@user) 硬判 0; timeout 未挂 ILA 且无 Lite 读回路径(+0x40/+0x44 不含) ⇒ INFO; 桥① bresp 恒 0 仅 INFO(S2MM 下不可见)"
        $plan += "      桥② 若无 stall/len_err/bresp 探针则记 INFO(不可观测); R2 新探针 dbg_s2mm_* 作可选列"
        $plan += "J4 口径: 两桥分别判, 不得用一桥的相等掩盖另一桥的失配"
        Write-Plan -Lines $plan
        Set-StepResult -Step "S10" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    $uiPost = $IlacapUiPost
    if (-not $uiPost) { $uiPost = $script:IlaCsvUiPost }
    $userPost = $IlacapUserPost
    if (-not $userPost) { $userPost = $script:IlaCsvUserPost }
    if (-not $uiPost) {
        $cmd = "py " + $script:ReconPyPath + " --mode recon --ui-post " + (Join-Path $script:IlaOutDirPath ("R2_ila_<tag>_ui_post.csv")) + " --user-post " + (Join-Path $script:IlaOutDirPath ("R2_ila_<tag>_user_post.csv"))
        Write-Raw "# S10 对账命令占位（需 S6 post CSV 或显式 -IlacapUiPost）:" "DarkCyan"
        Write-Raw ("# " + $cmd) "DarkCyan"
        Set-StepResult -Step "S10" -Verdict "NOT_OBTAINED" -Detail "无 post CSV（S6 未抓取且未给 -IlacapUiPost）⇒ 对账判据未取得"
        return
    }
    if (-not (Test-Path $uiPost)) { Set-StepResult -Step "S10" -Verdict "NOT_OBTAINED" -Detail ("post CSV 不存在: " + $uiPost); return }
    $rargs = @("--mode", "recon", "--ui-post", $uiPost)
    if ($userPost -and (Test-Path $userPost)) { $rargs += @("--user-post", $userPost) }
    if ($RequireR2Probes) { $rargs += "--require-r2-probes" }
    $jr = Invoke-ReconJudge -ArgList $rargs
    if ($jr.Verdict -eq "PASS") { Set-StepResult -Step "S10" -Verdict "PASS" -Detail $jr.Reason }
    elseif ($jr.Verdict -eq "NOT_OBTAINED") { Set-StepResult -Step "S10" -Verdict "NOT_OBTAINED" -Detail $jr.Reason }
    else { Set-StepResult -Step "S10" -Verdict "FAIL" -Detail $jr.Reason }
}

function Step-S11 {
    Write-Section "S11 收尾恢复: Set-EngineMode（默认 DMA=1; -RestoreEngine 0 切回 bridge）"
    if ($SkipS11) { Set-StepResult -Step "S11" -Verdict "SKIP" -Detail "已用 -SkipS11 关闭"; return }
    if ($script:DryRun) {
        $plan = @()
        $plan += ("Set-EngineMode 目标=" + $RestoreEngine + "（1=DMA/0=bridge; 'd' 是翻转, 走回读双重确认）")
        $plan += ("再发 'U' 整段回读落盘; 断言 mode=" + $RestoreEngine + " 且 req.bit24=" + [int]($RestoreEngine -eq 1))
        $plan += "若目标 DMA, 追加 'S' 恢复 SEQ（避免 R_MODE 停在 RND）"
        $plan += "失败 ⇒ FAIL（后续任何测量前必须重新确认引擎位）"
        Write-Plan -Lines $plan
        Set-StepResult -Step "S11" -Verdict "SKIP" -Detail "dry-run 计划"
        return
    }
    if (-not $script:BoardReady) { Set-StepResult -Step "S11" -Verdict "NOT_OBTAINED" -Detail "板卡未就绪"; return }
    $eng = Set-EngineMode -Want $RestoreEngine
    Write-Log $eng.Trace
    if (-not $eng.Ok) {
        Set-StepResult -Step "S11" -Verdict "FAIL" -Detail ("收尾 Set-EngineMode(" + $RestoreEngine + ") 失败: " + (Format-UStateBrief $eng.State))
        return
    }
    if ($RestoreEngine -eq 1) { $null = Send-UartCmd -Cmd "S" -Wait 1.2 -Title "S11 恢复 SEQ('S')"; Start-Sleep -Milliseconds 300 }
    $fin = Get-UState -Title "S11 收尾 'U' 回读"
    $finTxt = Format-UStateBrief $fin
    Write-Log ("S11 收尾状态: " + $finTxt)
    if ($null -ne $fin -and $fin.ParseOk -and $fin.Mode -eq $RestoreEngine -and ((Get-ReqEngineBit $fin) -eq ($RestoreEngine -eq 1))) {
        Set-StepResult -Step "S11" -Verdict "PASS" -Detail ("收尾引擎已确认: " + $finTxt)
    } else {
        Set-StepResult -Step "S11" -Verdict "FAIL" -Detail ("收尾引擎状态未确认: " + $finTxt)
    }
}
# =============================================================================
#endregion

# =============================================================================
#region 主流程
# =============================================================================
$modeTxt = "DRY-RUN（只做只读真校验 + 打印计划, 不烧板/不开串口/不发 ping; 加 -Run 才真执行）"
if ($Run) { $modeTxt = "RUN（会烧板/开串口/发 ping/调 Vivado 与各验证脚本!）" }
Write-Raw ("=" * 78) "Cyan"
Write-Raw "prj11 路线B R2 (B3-2 桥①写侧换层 S2MM) · 上板判据总控 S0-S11" "Cyan"
Write-Raw ("脚本版本 " + $script:Version + "   模式: " + $modeTxt) "Cyan"
Write-Raw ("工作目录 " + $script:OutRoot) "Cyan"
Write-Raw ("日志(UTF-8 BOM) " + $script:LogPath) "Cyan"
Write-Raw ("目标 192.168.1.10  PC " + $script:PcIp + "  Port " + $script:Port + "  静态邻居 " + $script:BoardMac) "Cyan"
Write-Raw ("=" * 78) "Cyan"

$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONHOME = ""
$env:PYTHONPATH = ""
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------------- -Run 参数硬校验 ----------------
if ($Run) {
    $usageErr = ""
    if (-not $Bit -and -not $SkipBurn) { $usageErr += " 缺 -Bit（本轮构建 NO_BITSTREAM 无 R2 位流; 等下一次成功位流对）;" }
    if (-not $Elf -and -not $SkipBurn) { $usageErr += " 缺 -Elf（R2 归档 ELF 绝对路径 1bc8088d; 若已烧好可 -SkipBurn）;" }
    if ($IlaCapture -and -not (Test-Path $script:IlaLtxPath)) {
        $usageErr += " -IlaCapture 但 ILA ltx 不存在: " + $script:IlaLtxPath + "（用 -IlaLtx 指定归档 probes_r2_<bit8>.ltx）;"
    }
    if ($RestoreEngine -ne 0 -and $RestoreEngine -ne 1) { $usageErr += " -RestoreEngine 只能是 0/1;" }
    if ($usageErr) {
        Write-Raw ("ARG-ERROR:" + $usageErr) "Red"
        Write-Raw "R2_RESULT: NOT_OBTAINED ARG（本次场次无 R2 位流可烧: 构建 NO_BITSTREAM ⇒ S0 依赖项 NOT_OBTAINED, S2-S11 全部 SKIP; 等下一次成功位流对再用 -Run）" "Yellow"
        exit 2
    }
    if ($SkipBurn -and (-not $Bit -or -not $Elf)) {
        Write-Note "-SkipBurn 且未给 -Bit/-Elf：S0/S1 的工件身份记录将简化（假设板上已是 R2 对）"
    }
}

# ---------------- 步骤执行 ----------------
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
Step-S9
Step-S10
Step-S11

# ---------------- 汇总 ----------------
Write-Section "R2 判据汇总（S0-S11）"
foreach ($k in $script:Steps.Keys) { Write-Raw ("  " + $script:Steps[$k].Line) }
if ($script:Notes.Count -gt 0) {
    Write-Log "记录项(NOTE):"
    foreach ($n in $script:Notes) { Write-Raw ("  - " + $n) "Yellow" }
}
if ($script:ToolLogs.Count -gt 0) {
    Write-Log "外部工具日志:"
    foreach ($t in $script:ToolLogs) { Write-Raw ("  - " + $t) }
}
if ($script:WrFaultSeen) { Write-Raw "  [!] 本轮曾观测到 WR_DBG.fault=1（写路径故障粘滞）" "Red" }

# ---------------- dry-run 自证 ----------------
if ($script:DryRun) {
    Write-Section "DRY-RUN 自证: 未执行任何板卡/网络动作（GUARD 计数器必须全 0）"
    $keys = @("Burn", "Uart", "Ping", "Vivado", "Python")
    $labels = @{ Burn = "xsct 烧写"; Uart = "串口探针"; Ping = "ping"; Vivado = "Vivado batch"; Python = "python/外部验证脚本" }
    $sum = 0
    foreach ($k in $keys) {
        $v = [int]$script:Guard[$k]
        $sum += $v
        $color = "Green"
        if ($v -ne 0) { $color = "Red" }
        Write-Raw ("  [GUARD] {0} = {1} 次" -f $labels[$k], $v) $color
    }
    Write-Log ("[DRYRUN] 不烧板(xsct=0) / 不开串口(0) / 不发 ping(0) / 不跑 Vivado(0) / 不执行外部验证脚本(0) —— 实测计数合计=" + $sum) $(if ($sum -eq 0) { "Green" } else { "Red" })
    Write-Log ("[DRYRUN] 只读真校验项: 工件 SHA256/构建日志 WNS/WHS/DRC/串口枚举/邻居/NIC/工具齐备/ILA ltx 存在性 —— 结果见上")
    Write-Raw ("全量日志: " + $script:LogPath) "Cyan"
    Write-Raw "R2_RESULT: SKIP (dry-run —— 未执行任何烧板/串口/ping/Vivado/外部验证脚本; 加 -Run 真执行)" "DarkYellow"
    exit 0
}

# ---------------- -Run 结论 ----------------
Write-Raw ("全量日志: " + $script:LogPath) "Cyan"
if ($script:Failures.Count -eq 0) {
    Write-Raw "R2_RESULT: PASS" "Green"
    exit 0
}
$first = $script:Failures[0]
$firstVerdict = $script:Steps[$first].Verdict
if ($firstVerdict -eq "NOT_OBTAINED") {
    Write-Raw ("FAILED_STEPS: " + ($script:Failures -join ", ")) "Yellow"
    Write-Raw ("R2_RESULT: NOT_OBTAINED " + $first + " (判据未取得) — " + $script:Steps[$first].Detail) "Yellow"
    exit 1
}
Write-Raw ("FAILED_STEPS: " + ($script:Failures -join ", ")) "Red"
Write-Raw ("R2_RESULT: FAIL " + $first + " — " + $script:Steps[$first].Detail) "Red"
exit 1
#endregion

