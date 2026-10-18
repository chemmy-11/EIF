# R2 官方工具定位记录（2026-10-18 深夜；amd-doc-search + hw-ila-debug + 官方 axi_dma IP 仿真）

状态：**问题已从"玄学"收敛为两层** —— ① 官方 IP 行为已被仿真排除（S2MM 映射/长度/状态正确）；② 板端新卡点是 round2f 位流上 lite_regs（M01 AXI-Lite）读楔死，第一次写服务前即挂死，需 lite fix2 位流（round3b）才能继续观测。

## 1. 官方文档查证（PG021 / PG022，均带 URL 核对 family/version）

| 点 | 官方依据（URL） | 对本问题含义 |
|---|---|---|
| S2MM 完成后 LENGTH=实际写入字节 | https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_LENGTH-S2MM-DMA-Buffer-Length-Register-Offset-58h | 板上可直接读 `S2MM_LENGTH(0x58)` 判"写了多少字节" |
| S2MM 状态位 | https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_DMASR-S2MM-DMA-Status-Register-Offset-34h | bit0 Halted、bit1 Idle、bit4 DMAIntErr（直连模式：内存写错 **或输入包大于 LENGTH** → graceful halt、RS 自清）、bit5 DMASlvErr、bit6 DMADecErr、bit12 IOC；**Halted=1 时写 LENGTH 无效** |
| 流包规则 | https://docs.amd.com/r/en-US/pg022_axi_datamover/Example-DataMover-Write-S2MM-Timing | 包内 TKEEP 不得稀疏/null；**只有 TLAST 拍可稀疏**；TLAST 界定包结束；DRE=0 时非对齐地址 undefined（本工程 4KB 对齐，符合） |
| DMASR bit1=Idle | PG021 `S2MM_DMASR`/`MM2S_DMASR` | 轮询完成应看 bit1（0x2）；IOC 在 bit12（0x1000） |

## 2. 官方 axi_dma IP 仿真（Vivado 2023.1，配置与 BD 逐项对齐 22/23 项）

证据目录：`out/ip_sim_r2/`（REPORT.md `ec8243f1…`、console.log `ee1c1de7…`、simulate.log `758ccc62…`、SHA256SUMS.txt）
**结论 `[L2]`：`TEST_PASS, fails=0`**
- 字节映射 **1:1**（tdata byte k → mem+k；Test2 唯一签名 mem[+k]=k，k=0..85 全过）；
- 86B 只写 86B（AWLEN=1、末拍 WSTRB=0x3F_FFFF、WLAST=1；0x56 后保持 0xEE）；
- 完成后 **`S2MM_DMASR=0x1002`（Halted=0/Idle=1/IOC=1/无错误）**、**`S2MM_LENGTH=86`**；
- MM2S 读回 2 拍 TKEEP=0x3F_FFFF/TLAST=1、数据一致；MM2S_DMASR=0x1002（低位不是字节数；actual-bytes 更新只属 S2MM_LENGTH）。
- 配置唯一偏差：`c_prmry_is_aclk_async` BD=1 vs 仿真=0（仅 AXI-Lite CDC，不影响数据通路）。
⇒ **IP 的 S2MM 映射/长度/状态语义不是"PC 收不到帧"的原因**。

## 3. 板端实测（round2f `8A8FE378` + 诊断固件 `16D06BD3`，23:47–23:51）

- **`'d'` 后（无流量）**：`'W'`（按 PG021 新加命令）读到 `s2cr=00011003`、`s2sr=00000000`（**Halted=0 / Idle=0 / 无错误位**）、`s2len=00000000`、`m2sr=00000001` ⇒ **DMA 已启动、未报错**（与仿真"传输前"语义一致）。
- **第一次 ping 后**：UART 立即静默、ping 0/4；固件内 LMB 快照全局 `WA_CNT=0`（JTAG 读 0x446c）⇒ **写服务函数一次都没执行到**（楔死点在 serve 入口前/内、S2MM 首次写之前）。
- 结合更早 marker 定位（PC 停 `dread` 读 lite_regs 0x40/0x34）⇒ **round2f 位流（lite fix1）上 M01 AXI-Lite 读楔死仍在**，与"写后紧接读"相关；round3b（lite fix2）是继续观测的前提。

## 4. 新增诊断资产（供 round3b 板验直接使用）

- 固件 `'W'` 命令（PG021 语义）：读/解码 `S2MM_DMACR/DMASR/LENGTH + MM2S_DMASR/MM2S_LENGTH + WR_REQ/WR_DBG + DMA_REQ`；**LMB 快照全局** `g_wa_*`（0x4450–0x4470，JTAG 可在总线楔死后读取）；10ms 慢轮询（服务延迟 << 桥 56ms 超时，同时保 UART 可用）。
- `tools/r2_ila5_capture.tcl` 已按官方 `hw-ila-debug` 技能修正（BASIC_ONLY/AND、timeout 单位分钟、CSV 基名）。
- 期望值（仿真基准，板上读回应等价）：传输前 `DMASR=0x0`、完成后 `DMASR=0x1002` 且 `S2MM_LENGTH=86`。

## 5. 下一步（round3b 位流）
1. 构建：lite fix2 `d5d16d46` + `u_ila_5@ui` 写流探针 + ILA0 101b；已降 ILA5/ILA3 深度重掷（差 0.002ns）。
2. 上板：烧 round3b → `'d'` → `'W'` → ping 1 → `'W'`：
   - `s2len==86` 且 `s2sr==0x1002` ⇒ 写侧成功 → 转 ILA5 首拍（0xD555…/tkeep）与读出/TX 链；
   - `halt/int/slv/dec` 报错或 `s2len!=86` ⇒ 按 PG021 错误位定位（包长/内存写）。
3. ILA5 首拍触发抓 S2MM 写流（官方技能流程），与仿真期望对齐后继续查 MM2S→eth TX。
