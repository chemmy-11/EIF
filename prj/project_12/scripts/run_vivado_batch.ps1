# =============================================================================
# run_vivado_batch.ps1 -- prj12: 以「子进程 + 文件重定向」方式跑 vivado batch
# 为什么需要它（2026-10-24 本会话实测，三条都是静默失败）:
#   1) MSYS2 bash 里直接 `cmd //c vivado.bat ...` 会**终止持久 bash 进程**（exit 1）；
#   2) pwsh 里 `& vivado.bat` / `cmd /c "..." | Out-String` **静默 exit=1 且无输出**；
#   3) `Start-Process cmd.exe -ArgumentList '/c', $整串` 会把整串再套一层引号 =>
#      cmd 报「filename, directory name, or volume label syntax is incorrect」。
# 结论: 直接 Start-Process -FilePath <vivado.bat> -ArgumentList <数组> + 文件重定向，
#       已用 Tcl 8.5.14 探针验证（Vivado 2023.1）。
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_vivado_batch.ps1 `
#       -Source D:\FPGA\prj\project_12\scripts\build_synth_only.tcl -Tag synth -Wait
#   -ExtraEnv @{P12_SKIP_ILA6='1'}   # 透传构建开关（环境变量）
# 产物: out\<Tag>.log / .jou（Vivado 自己的）、out\<Tag>.console.log（stdout+stderr）
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Tag,
    [string]$ProjectRoot = 'D:\FPGA\prj\project_12',
    [hashtable]$ExtraEnv = @{},
    [string]$EnvList = '',
    [switch]$Wait
)
$ErrorActionPreference = 'Stop'

# -EnvList 是给 `powershell -File` 命令行用的（-ExtraEnv 是 hashtable，命令行传不进来）
# 格式: "K1=V1;K2=V2"
if ($EnvList -ne '') {
    foreach ($pair in ($EnvList -split ';')) {
        if ($pair -eq '') { continue }
        $kv = $pair -split '=', 2
        if ($kv.Count -ne 2) { throw "bad -EnvList item: $pair" }
        $ExtraEnv[$kv[0]] = $kv[1]
    }
}

$vivado = 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat'
if (-not (Test-Path $vivado)) { throw "vivado not found: $vivado" }
if (-not (Test-Path $Source)) { throw "source tcl not found: $Source" }
$out = Join-Path $ProjectRoot 'out'
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 工作目录 / TEMP / TMP 必须纯 ASCII（中文路径会让 Vivado 的 Tcl 解码崩）
$env:TEMP = 'D:\FPGA\.tmp'
$env:TMP  = 'D:\FPGA\.tmp'
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
Set-Location 'D:\FPGA'

foreach ($k in $ExtraEnv.Keys) { Set-Item -Path "env:$k" -Value $ExtraEnv[$k] }
$envlist = (@($ExtraEnv.Keys | ForEach-Object { "$_=$($ExtraEnv[$_])" }) -join ',')

$log     = Join-Path $out "$Tag.log"
$jou     = Join-Path $out "$Tag.jou"
$console = Join-Path $out "$Tag.console.log"
foreach ($f in @($console, "$console.err", $log)) {
    if (Test-Path $f) { Remove-Item $f -Force }
}

Write-Output "RUN_VIVADO: tag=$Tag"
Write-Output "RUN_VIVADO: source=$Source"
Write-Output "RUN_VIVADO: env=$envlist"
Write-Output "RUN_VIVADO: console=$console"

$vargs = @('-mode','batch','-source',$Source,'-notrace','-log',$log,'-journal',$jou)
$p = Start-Process -FilePath $vivado -ArgumentList $vargs -NoNewWindow -PassThru `
        -RedirectStandardOutput $console -RedirectStandardError "$console.err"
Set-Content -Path (Join-Path $out "$Tag.pid") -Value $p.Id -Encoding ascii
Write-Output "RUN_VIVADO: pid=$($p.Id)"

if ($Wait) {
    $p.WaitForExit()
    Write-Output "RUN_VIVADO: exit=$($p.ExitCode)"
    Write-Output '---- console tail ----'
    Get-Content $console -Tail 30 -ErrorAction SilentlyContinue | ForEach-Object { Write-Output $_ }
}
