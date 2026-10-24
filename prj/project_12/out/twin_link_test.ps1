# =============================================================================
# twin_link_test.ps1 -- prj12 P1 双板上板执行单（可 dry-run）
# 定位: 把草案 §4.2 的 P1-01..P1-06 变成"一条命令能跑、跑不了也能看出缺什么"的骨架。
#       **不能自动化的部分（插光纤/上电/看 LED）明确标 MANUAL**，不假装自动化。
# 步骤:
#   1 preflight  参数自洽/位流哈希/COM 存在/hw_server TCP 可达/PC 网卡与 IP
#   2 burn       调 twin_burn.ps1 烧两块板
#   3 link       抓 ILA6（单核链路健康）出 CSV；判据 channel_up=1 & hard_err/soft_err 计数=0
#   4 data       PC1 发 UDP / PC2 抓包；判据 PC2 见到"目的=PC1"的帧（P1 预期语义）
#   5 recover    断电/复位后重新 step 3；判据自动恢复
#   6 evidence   把 log/csv/pcap 收进 out\evidence_<date>\
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File out\twin_link_test.ps1            # dry-run 全步骤
#   ... -Step 1 -Run        # 只做 preflight（真检查，不碰板）
#   ... -Step 2 -Run        # 真烧两块板
# 退出码: 0 = 通过 / dry-run 自洽；1 = 有失败；2 = 有 MANUAL 步骤未确认（-AcceptManual 跳过）
# =============================================================================
param(
    [ValidateSet('all','1','2','3','4','5','6')][string]$Step = 'all',
    [string]$Config = 'D:\FPGA\prj\project_12\out\twin_config.json',
    [switch]$Run,
    [switch]$AcceptManual,
    [string]$Root = 'D:\FPGA\prj\project_12'
)
$ErrorActionPreference = 'Stop'
$dry = -not $Run
$fail = $false
$manual = $false

function Say([string]$s) { Write-Output $s }
function Log-Fail([string]$s) { Write-Output "FAIL: $s"; $script:fail = $true }
function Log-Warn([string]$s) { Write-Output "WARN: $s" }
function Need-Manual([string]$s) { Write-Output "MANUAL: $s"; $script:manual = $true }

$cfg = Get-Content -Path $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$bit = Join-Path $Root $cfg.artifacts.bit
$boards = @('A','B')
$want = @()
if ($Step -eq 'all') { $want = @('1','2','3','4','5','6') } else { $want = @($Step) }

Say "=== twin_link_test $(if ($dry) { '[DRY-RUN]' } else { '[RUN]' }) step=$Step ==="
Say "config: $Config"
Say "bit   : $bit"

function Step-Preflight {
    Say ""
    Say "---- STEP 1: preflight ----"
    if (-not (Test-Path $bit)) { Log-Fail "bit missing: $bit" }
    else {
        $sha = (Get-FileHash -Algorithm SHA256 -Path $bit).Hash.ToLower()
        Say "bit sha256: $sha"
        $exp = [string]$cfg.artifacts.expect_bit_sha256
        if ($exp -eq '' -or $exp -match '^<.*>$') { Log-Warn "expect_bit_sha256 未回填" }
        elseif ($sha -ne $exp.ToLower()) { Log-Fail "bit sha mismatch (expect=$exp)" }
        else { Say "bit sha256: MATCH" }
    }
    foreach ($b in $boards) {
        $bd = $cfg.boards.$b
        Say "board $b : jtag=$($bd.jtag_serial) cable=$($bd.cable_serial) com=$($bd.com) server=$($bd.hw_server)"
        foreach ($k in @('jtag_serial','cable_serial','com','pc_nic')) {
            $v = [string]$bd.$k
            if ($v -eq '' -or $v -match '^<.*>$') { Log-Warn "board $b : $k 未配置（上板前必须填）" }
        }
        # COM 口是否在系统里（dry-run 也查，成本低）
        if ($bd.com -match '^COM\d+$') {
            $has = [System.IO.Ports.SerialPort]::GetPortNames() -contains $bd.com
            if ($has) { Say "board $b : $($bd.com) present" } else { Log-Fail "board $b : $($bd.com) not present" }
        }
        # hw_server TCP 端口
        if ($bd.hw_server -match '^(.*):(\d+)$') {
            $host_ = $Matches[1]; $port = [int]$Matches[2]
            $ok = Test-NetConnection -ComputerName $host_ -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($ok) { Say "board $b : hw_server $($bd.hw_server) reachable" }
            else { Log-Warn "board $b : hw_server $($bd.hw_server) NOT reachable（hw_server 起了吗？）" }
        }
    }
    foreach ($b in $boards) {
        $bd = $cfg.boards.$b
        Say "board $b : 光纤 = SFPA(X1Y11) <-> SFPA(X1Y11)，TX/RX 交叉；模块 10G SFP+；refclk 156.25MHz"
    }
    Need-Manual "两板 SFPA 已用 LC duplex 接好（TX->RX 交叉），模块完全插入，板已上电"
}

function Step-Burn {
    Say ""
    Say "---- STEP 2: burn both boards ----"
    $burn = Join-Path $Root 'out\twin_burn.ps1'
    $extra = if ($dry) { '' } else { ' -Run' }
    Say "CMD: powershell -NoProfile -ExecutionPolicy Bypass -File $burn -Board Both -Config $Config$extra"
    if (-not $dry) {
        # 注意：必须把 -Config 透传下去，否则换了 config 的现场会烧到默认配置那两块板
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $burn -Board Both -Config $Config -Run | ForEach-Object { Say $_ }
        if ($LASTEXITCODE -ne 0) { Log-Fail "twin_burn 失败（见 out\burn_*.console.log）" }
    }
}

function Step-Link {
    Say ""
    Say "---- STEP 3: link check via ILA6 (single-core link health) ----"
    $tcl = Join-Path $Root 'scripts\ila_capture.tcl'
    foreach ($b in $boards) {
        $bd = $cfg.boards.$b
        $csv = Join-Path $Root "out\ila6_$b.csv"
        Say "CMD(board $b): vivado -mode batch -source $tcl -tclargs $($bd.hw_server) $($bd.cable_serial) $csv"
    }
    Say "判据(P1-02): u_ila_6.probe0 = {link_ok,channel_up,lane_up,gt_pll_lock} 全 1（channel_up=1 是硬前提）"
    Say "判据(P1-02): u_ila_6.probe1 = {hard_err,soft_err} 不出现；probe3/probe4 计数 10min 不增长"
    Say "判据(P1-02): u_ila_6.probe9 aurora_rst = 0（channel_up 上升后数据通路必须已出复位）"
    Say "反例: link_ok=0 但 channel_up=1 => 漏打 P0-02 补丁"
    if (-not $dry) { Need-Manual "在 ILA 触发/抓取窗口内观察 10 分钟（可先用 trigger_now 抓快照）" }
}

function Step-Data {
    Say ""
    Say "---- STEP 4: data-plane visibility (PC1 send / PC2 capture) ----"
    Say "PC1: py pc\twin_send.py --dst-ip 192.168.1.10 --dst-port 1234 --count 20 --len 100"
    Say "PC2: py pc\twin_recv.py --from-pcap out\pc2.pcap --board-mac 00:11:22:33:44:55"
    Say "PC2 抓包: dumpcap -i <ifIndex> -f ""ether src 00:11:22:33:44:55"" -w out\pc2.pcap -a duration:30"
    Say "判据(P1-03): PC2 抓到完整帧，且 eth.dst = PC1 网卡 MAC（P1 预期语义：回显帧目的仍是原 PC）"
    Say "判据(P1-03): ILA6 probe5(进 A 核 TX 帧数)/probe6(出 A 核 RX 帧数)/probe7/8 泵计数按帧数递增"
    Say "反例: 抓不到 + probe5 不动 => 本板没发；probe5 动而 probe6 不动 => 对端没回/链路不通"
    if (-not $dry) { Need-Manual "PC2 用混杂模式抓包（防火墙/驱动可能挡，必要时先关防火墙）" }
}

function Step-Recover {
    Say ""
    Say "---- STEP 5: power cycle / reset ----"
    Say "判据(P1-05): 断电重启后 30s 内 channel_up 自动恢复=1；hard_err/soft_err 计数清零后不增长"
    Need-Manual "两板断电 10s -> 上电 -> 重跑 STEP 3"
}

function Step-Evidence {
    Say ""
    Say "---- STEP 6: evidence archive ----"
    $stamp = Get-Date -Format 'yyyy-MM-dd'
    $dir = Join-Path $Root "out\evidence_$stamp"
    Say "目标目录: $dir"
    Say "收: burn_*.console.log / ila6_*.csv / *.pcap / 串口日志 / 位流+ELF SHA256 / 两块板照片(板号)"
    if (-not $dry) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Get-ChildItem (Join-Path $Root 'out') -Filter '*.console.log' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dir -Force
        Get-ChildItem (Join-Path $Root 'out') -Filter 'ila6_*.csv' -ErrorAction SilentlyContinue |
            Copy-Item -Destination $dir -Force
        Say "已收集（pcap/照片请手工放入）"
    }
    Need-Manual "两板照片与板号、光纤接线照片入档"
}

foreach ($s in $want) {
    switch ($s) {
        '1' { Step-Preflight }
        '2' { Step-Burn }
        '3' { Step-Link }
        '4' { Step-Data }
        '5' { Step-Recover }
        '6' { Step-Evidence }
    }
}

Say ""
if ($fail) { Say "TWIN_LINK_RESULT: FAIL"; exit 1 }
if ($manual -and -not $AcceptManual -and -not $dry) { Say "TWIN_LINK_RESULT: MANUAL_PENDING"; exit 2 }
Say "TWIN_LINK_RESULT: $(if ($dry) { 'DRY_RUN_OK (未上板)' } else { 'PASS' })"
exit 0
