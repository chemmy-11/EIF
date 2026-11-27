# prj13 V4 双机构建输入

本包仅用于 B1 正式 V4 重建，A/B 两侧使用同一份 ZIP。基线为 EIF `dbe1526c16b19b01716c0dba48b2857332f84a5d`，附同一份 144 位 ILA 补丁、实现检查和可重定位建工程入口。配对 bit/LTX 在两端各自构建完成后交付。

| 构建机器 | 构建角色 | 实现起跑策略 | 出件后上板端 |
| --- | --- | --- | --- |
| PC2 | 软 A，`P13_BOARD=A`，无 `BOARD_B` | `ExtraPostPlacementOpt` | PC1 物理板 B |
| PC1 | 软 B，`P13_BOARD=B`，有 `BOARD_B` | `ExtraTimingOpt` | PC2 物理板 A |

## 取件与验件

从 EIF Release 实取 ZIP 与 SHA256SUMS.txt。用 Get-FileHash 对照 ZIP 哈希后，在这台机器独有、全英文的全新目录解包。运行 `verify_inputs.ps1`，逐项核对 manifest.json 的路径、字节数、SHA-256，确认没有继承 prj13.xpr、旧 DCP 或旧 out 目录。包内包含嵌套 RTL、XDC、两份建工程 Tcl、综合/实现/角色包装脚本、prj9 的五份 XCI 和 prj10 的 DDR4 MIG 原始 XCI。布局保持 prj/project_9、project_10、project_13 的兄弟关系。

环境为 Vivado 2023.1。旧候选安装日志为 SW Build 3865809 / IP Build 3864474。两机在回执中登记实际版本、build、KU060 器件/IP 可用性、许可可用和本机无冲突构建。器件为 xcku060-ffva1156-2-i，top 为 aurora_mem_bridge。板上回退仍使用两端各自已验的 D-fix 与 BA3C0220 ELF，文件名、全 SHA 和版本见 [EIF #18](https://github.com/chemmy-11/EIF/issues/18)。

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath $Zip
Expand-Archive -LiteralPath $Zip -DestinationPath $FreshRoot
& (Join-Path $FreshRoot 'verify_inputs.ps1')
& $Vivado -version
```

## 离线构建命令

在本机已核验的 PowerShell 会话运行，`$Vivado` 为 Vivado 2023.1 的可执行入口，`$FreshRoot` 为刚验的解包根。下方配置适用于 PC2。PC1 将角色及 place 策略改为上一表中的 B 对应值。三段依序执行，每段保留独立日志和退出码；先确认 `CREATE_DONE`，再确认综合及本轮 DCP，最后实现。

```powershell
$env:P13_ROOT = (Resolve-Path (Join-Path $FreshRoot 'prj/project_13')).Path
$env:P13_BOARD = 'A'
$env:P12_PLACE_DIRECTIVE = 'ExtraPostPlacementOpt'
$env:P13_SKIP_ILA8 = '0'
$env:P13_SKIP_ILA9 = '0'
$env:R3C_LITE_ILA = '0'
$env:R3C_LITE_ILA5 = '0'
Remove-Item Env:P13_PRE_HOOK -ErrorAction SilentlyContinue
$s = Join-Path $env:P13_ROOT 'scripts'
& $Vivado -mode batch -source "$s/create_project.tcl" -notrace -log "$FreshRoot/create.log"
# 确认退出 0 和 CREATE_DONE
& $Vivado -mode batch -source "$s/iso/b1_synth.tcl" -notrace -log "$FreshRoot/synth.log"
# 确认退出 0、B1_ROLE_AUDIT_OK、144 位探针、DCP 本次新写
& $Vivado -mode batch -source "$s/iso/b1_impl.tcl" -notrace -log "$FreshRoot/impl.log"
```

DSH 会话可用 dsh-vivado 的 Vivado 预设和本机已验证的异步 Tcl 后台入口，显式传入同样的环境和脚本路径，每段验证完再启动下段。建工程阶段导入 XCI、生成 MicroBlaze BD 和 IP；空工程预验失败时保留日志，由 PC1 处理工程依赖或接手这一侧。

## PC2 回执与成品交接

- 开工回执含 ZIP SHA-256、清单通过、工作目录、版本和 SW/IP build、器件与 top、BUILD A、确认无旧检查点，以及 `CREATE_DONE` 和实际 IP 列表。
- 验收先查综合和实现的实际角色、网表来源和 144 位探针。两端逐核对 `name/width/bit_offset` 与采样域。确认只删 GMII ILA 的 `ep_ok`，保留十类 32 bit、旧 D-fix 探针和原生域 ILA6。保持同版 CDC 报告并逐条比对旧候选。越域探针路径消失，新增同方向路径须审查；登记 setup/hold/pulse 各自的裕量和失败端点。
- PC2 把新软 A bit/LTX、日志、时序/CDC/DRC/check_timing、探针表和 SHA 清单交给 PC1。PC1 提供新软 B 对应材料，并在 EIF 发布成对工件 + 共用 ELF/回退入口。PC2 从正式配对发布实取软 B bit/LTX/ELF 验哈希回执。PC1 实取验软 A。上板按 A2 #10 走复链、校准、`mode=1`、双向正例、G4/T7/分类 DROP。

