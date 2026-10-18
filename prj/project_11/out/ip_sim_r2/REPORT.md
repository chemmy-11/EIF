# prj11 R2 — AXI DMA S2MM 写内存字节映射 / S2MM_LENGTH / DMASR 离线 IP 仿真报告

- 日期：2026-10-18
- 范围：**仅官方 IP 行为级仿真**。不修改 `rtl/`，不做综合/实现，不接触板卡，不入 git。
- 工程：`D:\FPGA\prj\project_11`（R2 设计）
- 器件/工具：xcku060-ffva1156-2-i / Vivado 2023.1（SW Build 3865809，IP Build 3864474）
- 官方 IP：`xilinx.com:ip:axi_dma:7.1`，IP revision 29
- 结论：**PASS（`TEST_SUMMARY fails=0`，`TEST_PASS`，$finish @ 5065 ns）**

## 0. 一句话结论

在 R2 同款数据通路配置（SG=0、512-bit MM/Stream、S2MM burst 16、DRE=0）下，官方 `axi_dma` 的 S2MM：

1. 把 `s_axis_s2mm_tdata` 的 **byte k 写到目标地址 + k**（小端、无字节交换、无 lane 错位）；
2. 86 B 包**只写 86 B**，最后一拍 `WSTRB=0x0000_0000_003F_FFFF`（低 22 字节），`WLAST=1`；
3. 完成后 `S2MM_LENGTH(0x58)` 更新为**实际字节数 86**；
4. 完成后 `S2MM_DMASR(0x34)=0x0000_1002`：`Halted=0`、`Idle=1`、`IOC_Irq=1`，`DMAIntErr/SLVErr/DecErr=0`；
5. MM2S 读回同样 86 B，2 拍数据的 `TDATA/TKEEP/TLAST` 与写入一致。

**因此：板端“PC 收不到任何帧”不能归因于 AXI DMA IP 的 S2MM 字节映射、实际写入长度或完成状态语义。** 应转向固件轮询/寄存器写入次序、写引擎的数据摆放与 TLAST、以及 MM2S→以太网 TX 链路排查。详细建议见第 7 节。

## 1. 配置快照与对齐

### 1.1 来源

- `D:\FPGA\prj\project_11\scripts\create_bd_b.tcl` 第 110–111 行（BD 中 `axi_dma_0` 的 `CONFIG.*`）。
- R2 BD 解析后的 XCI：`vivado\prj11.srcs\sources_1\bd\mb_ctrl\ip\mb_ctrl_axi_dma_0_0\mb_ctrl_axi_dma_0_0.xci`。
- 独立仿真工程解析值：`config_snapshot.txt`（Tcl `list_property` 全量 dump）。
- 逐项比较：`config_compare.txt`（脚本 `compare_config.py`）。

### 1.2 关键参数

| 参数 | R2 BD XCI | 独立 IP 仿真 | 一致 |
|---|---:|---:|---|
| `C_INCLUDE_MM2S` | 1 | 1 | ✅ |
| `C_INCLUDE_S2MM` | 1 | 1 | ✅ |
| `C_INCLUDE_SG` | 0 | 0 | ✅ |
| `C_M_AXI_MM2S_DATA_WIDTH` | 512 | 512 | ✅ |
| `C_M_AXIS_MM2S_TDATA_WIDTH` | 512 | 512 | ✅ |
| `C_M_AXI_S2MM_DATA_WIDTH` | 512 | 512 | ✅ |
| `C_S_AXIS_S2MM_TDATA_WIDTH` | 512 | 512 | ✅ |
| `C_SG_LENGTH_WIDTH` | 16 | 16 | ✅ |
| `c_addr_width` | 32 | 32 | ✅ |
| `C_INCLUDE_MM2S_DRE` | 0 | 0 | ✅ |
| `C_INCLUDE_S2MM_DRE` | 0 | 0 | ✅ |
| `C_INCLUDE_MM2S_SF` | 1 | 1 | ✅ |
| `C_INCLUDE_S2MM_SF` | 1 | 1 | ✅ |
| `c_mm2s_burst_size` | 2 | 2 | ✅ |
| `c_s2mm_burst_size` | 16 | 16 | ✅ |
| `c_micro_dma` | 0 | 0 | ✅ |
| `c_single_interface` | 0 | 0 | ✅ |
| `c_enable_multi_channel` | 0 | 0 | ✅ |
| `c_increase_throughput` | 0 | 0 | ✅ |
| `c_dlytmr_resolution` | 125 | 125 | ✅ |
| `c_sg_include_stscntrl_strm` | 0 | 0 | ✅ |
| `c_sg_use_stsapp_length` | 0 | 0 | ✅ |
| `c_prmry_is_aclk_async` | **1** | **0** | ⚠️ 见下 |

**唯一差异（已评估，不影响本次结论）**：BD 中 `s_axi_lite_aclk=100 MHz`、`ui_clk=300 MHz`，两个时钟异步，因此 BD 把 `c_prmry_is_aclk_async` 传播为 1；独立仿真为简化使用单一 100 MHz 时钟，取 IP 默认 0。该参数只影响 **AXI-Lite 寄存器访问的 CDC/握手延迟**，不改变 S2MM/MM2S 数据通路的位宽、burst、DRE、SF、字节映射、长度或状态位。若后续要覆盖 100M/300M 异步寄存器路径，可另做双时钟版本；本次“IP 字节映射/长度/状态”结论不依赖该路径。

> 注：`c_mm2s_burst_size=2` 是 IP 默认值，BD 未显式设置；它只影响 MM2S 读 burst，不影响 S2MM 写 burst（16）。

## 2. 仿真平台

| 文件 | 作用 |
|---|---|
| `build_sim.tcl` | 创建独立 Vivado 工程、`create_ip axi_dma`、生成仿真目标、加 TB/RAM、`launch_simulation`、收集日志 |
| `tb/tb_axi_dma_s2mm.sv` | 自检测试平台：AXI-Lite 主、S2MM 流源、MM2S 流汇、寄存器检查、内存逐字节检查、超时/看门狗 |
| `rtl/axi_ram_model.sv` | ~190 行 AXI4 从机 RAM：512-bit、32-bit 地址、INCR burst、按 `WSTRB` 字节写、2 MiB、初值 `0xEE`、组合调试读口 |
| `run_sim.ps1` | 批处理运行器；`cmd /c` 文件重定向捕获 stdout（坑 #58），瞬态安装盘读失败重试一次（坑 #61） |
| `compare_config.py` | 生成 `config_compare.txt` |
| `logs/` | `console.log`（Vivado+仿真完整 stdout）、`simulate.log`（xsim 原始 log）、`vivado.log`、`xvlog.log`、`xvhdl.log`、`tb_axi_dma_s2mm.vcd` |

### 2.1 时钟/复位/地址

- 单时钟 100 MHz（周期 10 ns），`axi_resetn` 低 20 拍后释放。
- RAM 2 MiB，初值 `0xEE`；`0x0010_0000` 起的槽地址完全落在 RAM 内。
- 所有测试地址：`SLOT0=0x0010_0000`、`SLOT1=0x0010_1000`、`SLOT2=0x0010_2000`（4 KiB 对齐，满足 DRE=0 时 512-bit 数据通路的 64 B 对齐要求）。

### 2.2 寄存器偏移（与 IP VHDL 常量、驱动头文件交叉确认）

| 寄存器 | 偏移 | 依据 |
|---|---:|---|
| `MM2S_DMACR` | 0x00 | `axi_dma_v7_1_vh_rfs.vhd` 常量 |
| `MM2S_DMASR` | 0x04 | 同上 |
| `MM2S_SA` | 0x18 | `XAXIDMA_SRCADDR_OFFSET` |
| `MM2S_LENGTH` | 0x28 | `XAXIDMA_BUFFLEN_OFFSET` |
| `S2MM_DMACR` | 0x30 | `S2MM_DMACR_OFFSET` |
| `S2MM_DMASR` | 0x34 | `S2MM_DMASR_OFFSET` |
| `S2MM_DA` | 0x48 | `S2MM_DA_OFFSET`（PG021 的 S2MM_DA） |
| `S2MM_LENGTH` | 0x58 | `S2MM_LENGTH_OFFSET` |

### 2.3 测试内容

1. **Test 1**：S2MM 86 B @ `0x0010_0000`，完全复刻板端描述（beat0 64 B 全 TKEEP；beat1 22 B TKEEP=`0x0000_0000_003F_FFFF`、TLAST=1），逐字节检查 86 B。
2. **Test 2**：S2MM 86 B @ `0x0010_1000`，**唯一 lane 签名**：beat0 byte k = k（0x00..0x3F），beat1 byte k = 0x40+k（0x40..0x55），检查 `mem[base+k] == k`（k=0..85），无歧义证明字节顺序。
3. **Test 4**：S2MM `S2MM_LENGTH=256`，但只发 86 B 后 TLAST，检查完成后 `S2MM_LENGTH` 是否更新为 86，且 `0x56..0xFF` 保持 `0xEE`。
4. **Test 3（加分）**：MM2S 从 `0x0010_0000` 读 86 B，`TREADY=1`，抓取前 2 拍 `TDATA/TKEEP/TLAST`，并读 `MM2S_DMASR`/`MM2S_LENGTH`。

## 3. 实测结果

### 3.1 Test 1：S2MM 86 B @ 0x0010_0000

**寄存器写/读：**

```text
AXIL_WR t=605 ns   addr=0x030 data=0x00001001      # S2MM_DMACR = RS | IOCEN
AXIL_RD t=735 ns   addr=0x030 data=0x00011003      # 读回：RS=1, IOCEN=1；bit1/bit16 为 IP 内部复位位
AXIL_WR t=805 ns   addr=0x048 data=0x00100000      # S2MM_DA
AXIL_WR t=875 ns   addr=0x058 data=0x00000056      # S2MM_LENGTH = 86，最后写
S2MM_STREAM t=885 ns tdata[63:0]=0xd555555555555555 tkeep=0xffffffffffffffff tlast=0
S2MM_STREAM t=895 ns tdata[63:0]=0x7766554433221100 tkeep=0x00000000003fffff tlast=1
```

**AXI4 写事务（RAM 模型观测，等价于关键波形行）：**

```text
RAM_AW  t=1125 ns addr=0x00100000 len=1 size=6 burst=1          # 2 拍 INCR burst
RAM_W   t=1145 ns addr=0x00100000 beat=0 strb=0xffffffffffffffff last=0 data[63:0]=0xd555555555555555
RAM_W   t=1155 ns addr=0x00100040 beat=1 strb=0x00000000003fffff last=1 data[63:0]=0x7766554433221100
RAM_B   t=1165 ns
IRQ_RISE s2mm t=1235 ns
```

**内存 86 B（`MEMDUMP T1`）：**

```text
0x00100000 +0x000 : 55 55 55 55 55 55 55 d5 55 55 55 55 55 55 55 d5
0x00100000 +0x010 : 55 55 55 55 55 55 55 d5 55 55 55 55 55 55 55 d5
0x00100000 +0x020 : 55 55 55 55 55 55 55 d5 55 55 55 55 55 55 55 d5
0x00100000 +0x030 : 55 55 55 55 55 55 55 d5 55 55 55 55 55 55 55 d5
0x00100000 +0x040 : 00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff
0x00100000 +0x050 : 10 21 32 43 54 65
```

**判读：**

- beat0 在 TB 中驱动为 `{8{64'hD555_5555_5555_5555}}`，即 512-bit `tdata` 的每个 8 B lane 都是 `0xD555_5555_5555_5555`。按小端，lane 内字节为 `55 55 55 55 55 55 55 D5`，所以 64 B 呈现为 8 组 `55 55 55 55 55 55 55 d5`。**这不是反序**：`tdata` byte 0 = 0x55 写到 mem+0，byte 7 = 0xD5 写到 mem+7；64 位十六进制值 `0xD555...` 在字节 dump 中自然显示为 `55...D5`。
- beat1 低 22 字节为 `0x11*k`（k=0..21）：`00 11 22 33 44 55 66 77 88 99 aa bb cc dd ee ff 10 21 32 43 54 65`，正好落在 `+0x040..+0x055`。**byte k → mem+k，无错位**。
- AXI 最后一拍 `WSTRB=0x0000_0000_003F_FFFF`（低 22 位），`WLAST=1`，说明 IP 只写 22 B，不是写满 64 B。

**状态读回：**

```text
DMASR S2MM_T1 = 0x00001002 | Halted=0 Idle=1 SGIncld=0 DMAIntErr=0 SLVErr=0 DecErr=0
                             SGIntErr=0 SGSLVErr=0 SGDecErr=0 IOC_Irq=1 Dly_Irq=0 Err_Irq=0
TEST1 S2MM_LENGTH_AFTER=0x00000056 (86)
```

### 3.2 Test 2：唯一 lane 签名（最强字节顺序证据）

```text
S2MM_STREAM t=1985 ns tdata[63:0]=0x0706050403020100 tkeep=0xffffffffffffffff tlast=0
S2MM_STREAM t=1995 ns tdata[63:0]=0x4746454443424140 tkeep=0x00000000003fffff tlast=1
RAM_AW  t=2225 ns addr=0x00101000 len=1 size=6 burst=1
RAM_W   t=2245 ns addr=0x00101000 beat=0 strb=0xffffffffffffffff last=0
RAM_W   t=2255 ns addr=0x00101040 beat=1 strb=0x00000000003fffff last=1
```

内存 `0x00101000 + 0x00..0x55` 实测为：

```text
00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f
10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f
20 21 22 23 24 25 26 27 28 29 2a 2b 2c 2d 2e 2f
30 31 32 33 34 35 36 37 38 39 3a 3b 3c 3d 3e 3f
40 41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f
50 51 52 53 54 55
```

`mem[base+k] == k` 对 k=0..85 全部成立，**逐字节证明 `tdata` byte k 落到地址 +k**。这一测试与 D5 图案无关，排除了“8 字节组内反序看不出来”的歧义。

### 3.3 Test 4：短包与 `S2MM_LENGTH` 实际字节数语义

- 写入 `S2MM_LENGTH=256`，但流只发 86 B 后 TLAST。
- 完成后读 `S2MM_LENGTH=0x00000056`（86）——**PG021 的“完成后更新为实际写入字节数”成立**。
- 内存 `0x00102000+0x00..0x55` = 86 B 图案；`0x00102056..0x001020FF` = `0xEE`（未写）。AXI 仍只有 2 拍 burst，`WSTRB` 最后一拍 `0x3F_FFFF`，没有多写 170 B。

```text
TEST4 S2MM_LENGTH_AFTER=0x00000056 (86) expect_actual=86
0x00102000 +0x050 : 10 21 32 43 54 65 ee ee ee ee ee ee ee ee ee ee
```

### 3.4 Test 3（加分）：MM2S 读回 86 B

```text
RAM_AR  t=4525 ns addr=0x00100000 len=1 size=6 burst=1
RAM_R   t=4545 ns addr=0x00100000 beat=0 last=0 data[63:0]=0xd555555555555555
RAM_R   t=4565 ns addr=0x00100040 beat=1 last=1 data[63:0]=0x7766554433221100
MM2S_BEAT t=4585 ns idx=0 tdata[63:0]=0xd555555555555555 tdata[191:128]=0xd555555555555555 tkeep=0xffffffffffffffff tlast=0
MM2S_BEAT t=4605 ns idx=1 tdata[63:0]=0x7766554433221100 tdata[191:128]=0xeeee655443322110 tkeep=0x00000000003fffff tlast=1
IRQ_RISE mm2s t=4635 ns
DMASR MM2S_T3 = 0x00001002 | Halted=0 Idle=1 ... IOC_Irq=1
TEST3 MM2S_LENGTH_AFTER=0x00000056 (86)
```

**判读：**

- 2 拍、`TKEEP` 分别全 1 / `0x3F_FFFF`、`TLAST` 0/1，与写入完全一致。
- beat1 的 `tdata[191:128]=0xEEEE_6554_4332_2110` 高字节是 `0xEE`（DMA 实际读了 128 B，86 B 之后是 RAM 初值），但 `TKEEP=0x3F_FFFF` 只让低 22 字节有效。这是正常 AXI-Stream 语义，不是错误。
- `MM2S_DMASR=0x1002`，无错误；`MM2S_LENGTH` 保持 86（PG021 只规定 `S2MM_LENGTH` 完成后更新为实际字节数；`MM2S_LENGTH` 是请求长度，不更新）。

> **对任务描述中“读 MM2S_DMASR 看 lower bits 是否为实际传输字节数”的更正**：`MM2S_DMASR` 的 bit0/1 是 Halted/Idle，不是字节数；`0x1002` 的低位 `0x2` 是 Idle。字节数在 `MM2S_LENGTH(0x28)`，实测保持 86。PG021 的“actual bytes”更新语义属于 `S2MM_LENGTH(0x58)`，本次已单独验证。

### 3.5 `S2MM_DMASR` 位定义与实测解码

位定义来自 IP VHDL 常量（`axi_dma_v7_1_vh_rfs.vhd` 第 284–298 行）与 `xaxidma_hw.h`（HALTED=0x1、IDLE=0x2、ERR_INTERNAL=0x10、ERR_SLAVE=0x20、ERR_DECODE=0x40、SG 错误=0x100/0x200/0x400、IOC=0x1000、DLY=0x2000、ERR=0x4000），与 PG021 的 S2MM_DMASR 表一致。

| bit | 名称 | 实测 `0x0000_1002` |
|---:|---|---:|
| 0 | Halted | 0 |
| 1 | Idle | 1 |
| 2 | SGIncld / Cmplt | 0 |
| 3 | Error（保留/聚合） | 0 |
| 4 | DMAIntErr | 0 |
| 5 | SLVErr | 0 |
| 6 | DecErr | 0 |
| 7 | 保留 | 0 |
| 8 | SGIntErr | 0 |
| 9 | SGSLVErr | 0 |
| 10 | SGDecErr | 0 |
| 11 | 保留 | 0 |
| **12** | **IOC_Irq** | **1** |
| 13 | Dly_Irq | 0 |
| 14 | Err_Irq | 0 |
| 15 | 保留 | 0 |
| 23:16 | IRQThresholdSts | 0 |
| 31:24 | IRQDelaySts | 0 |

**关键：IOC_Irq 是 bit 12（0x1000），不是 bit 9。** 固件若轮询 bit 9 会永远看不到完成。

### 3.6 `S2MM_DMACR` 读回

- 复位后：`0x0001_0002`（bit1 `TAILPEN` 与 bit16 `IRQThreshold=1` 是 IP 内部默认值）。
- 写 `0x0000_1001`（RS|IOCEN）后读回：**`0x0001_1003`**（bit0 RS=1、bit12 IOCEN=1，另有 bit1/bit16 内部位）。
- 固件比较 DMACR 时应屏蔽 bit1/bit16，或直接按位判断 bit0/bit12。

### 3.7 中断

- S2MM `introut` 在完成时上升（Test1 `t=1235 ns`），IOCEN 生效。
- MM2S `introut` 在完成时上升（`t=4635 ns`）。

## 4. 期望 vs 实测总表

| # | 检查项 | 期望 | 实测 | 判定 |
|---:|---|---|---|---|
| 1 | S2MM beat0 64 B 写 `0x100000..0x10003F` | 8 组 `55…D5` | 8 组 `55 55 55 55 55 55 55 d5` | ✅ |
| 2 | S2MM beat1 22 B 写 `0x100040..0x100055` | `00 11 … 65` 顺序 | 完全一致 | ✅ |
| 3 | 86 B 之外不被写 | 保持 `0xEE` | Test4 检查 `0x56..0xFF` 全 `0xEE` | ✅ |
| 4 | AXI 写 burst | AWADDR=0x100000, AWLEN=1, 最后 WSTRB=0x3F_FFFF, WLAST=1 | 一致 | ✅ |
| 5 | 完成 DMASR | Halted=0, Idle=1, IOC=1, errors=0 | `0x1002` | ✅ |
| 6 | `S2MM_LENGTH`（86 B 包） | 86 | 86 | ✅ |
| 7 | `S2MM_LENGTH`（256 缓冲/86 B 包） | 更新为 86 | 86 | ✅ |
| 8 | 字节顺序（唯一签名） | `mem[+k]=k`，k=0..85 | 全部成立 | ✅ |
| 9 | MM2S 读回 2 拍 | 数据/TKEEP/TLAST 正确 | 一致 | ✅ |
| 10 | `MM2S_DMASR` | 0x1002（Idle+IOC，无错） | 0x1002 | ✅ |
| 11 | `MM2S_LENGTH` | 保持 86（不更新） | 86 | ✅（更正见 3.4） |
| 12 | `s2mm_introut` | 完成时上升 | 1235 ns | ✅ |
| 13 | `TEST_SUMMARY` | fails=0 | fails=0 / `TEST_PASS` | ✅ |

## 5. 波形/时序关键行

完整 VCD：`logs/tb_axi_dma_s2mm.vcd`（仅 TB 级接口信号，45 个 `$var`，52,844 B；不含 2 MiB RAM，避免巨大波形）。可直接用 GTKWave 或 Vivado 打开。关键时间行：

```text
t=885 ns   S2MM_STREAM beat0  tdata[63:0]=0xd555555555555555 tkeep=all1 tlast=0
t=895 ns   S2MM_STREAM beat1  tdata[63:0]=0x7766554433221100 tkeep=0x3fffff tlast=1
t=1125 ns  RAM_AW  addr=0x00100000 len=1 size=6 burst=1
t=1145 ns  RAM_W   beat=0 strb=all1 last=0
t=1155 ns  RAM_W   addr=0x00100040 beat=1 strb=0x3fffff last=1
t=1165 ns  RAM_B
t=1235 ns  IRQ_RISE s2mm
t=1475 ns  S2MM_DMASR=0x1002
t=1595 ns  S2MM_LENGTH=0x56
t=4525 ns  RAM_AR  addr=0x00100000 len=1 size=6 burst=1
t=4545 ns  RAM_R   beat0
t=4565 ns  RAM_R   beat1 last=1
t=4585 ns  MM2S_BEAT idx=0 tkeep=all1 tlast=0
t=4605 ns  MM2S_BEAT idx=1 tkeep=0x3fffff tlast=1
t=4635 ns  IRQ_RISE mm2s
```

## 6. 复现

```bat
cd /d D:\FPGA\prj\project_11\out\ip_sim_r2
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_sim.ps1
```

或直接单次运行：

```bat
cd /d D:\FPGA\prj\project_11\out\ip_sim_r2
cmd /c ""D:\Xilinx\Vivado\2023.1\bin\vivado.bat" -mode batch -source build_sim.tcl -notrace -log logs\vivado.log -journal logs\vivado.jou > logs\console.log 2>&1"
```

预期最后出现：

```text
TEST_SUMMARY fails=0
TEST_PASS
SIM_BUILD_DONE
```

说明：

- `run_sim.ps1` 用 `cmd /c` 文件重定向捕获 Vivado stdout（项目坑 #58），不对 Vivado 使用 PowerShell 管道。
- 只有检测到 `Read error|cannot open|No such file|Input/output error` 时才重试一次（项目坑 #61）。
- 本机默认 PowerShell 执行策略禁止直接双击 `.ps1`；用上面的 `powershell -ExecutionPolicy Bypass -File` 即可。
- `proj/` 是 `build_sim.tcl` 可重建的生成物，未纳入 SHA256 清单；清单只覆盖源文件、配置、日志和报告。

## 7. 对本问题的含义与板端排查建议

### 7.1 结论

**IP 的 S2MM 写路径在“64 B 全 TKEEP + 22 B TKEEP/TLAST、LENGTH=86”的板端刺激下行为完全正确。** 写进去的 86 B 布局、实际写入字节数、`S2MM_LENGTH` 更新、`DMASR` 完成位都符合预期。板端“PC 收不到帧”**不是** AXI DMA IP 的 S2MM 字节映射/长度/状态语义造成的。

### 7.2 优先排查顺序

1. **固件是否轮询错 DMASR 位（最高嫌疑）**  
   `IOC_Irq` 是 **bit 12 = 0x1000**；`Idle` 是 bit 1；`Halted` 是 bit 0。若固件等 bit 9（0x200）或等 `Halted` 清零，就永远等不到“完成”，自然不会触发 MM2S 读回和以太网 TX。建议直接用板端读 `0x44A1_0034`（DMA 基址 + 0x34）确认完成后是否为 `0x1002`。

2. **`S2MM_LENGTH` 必须最后写**  
   PG021 明确要求 `S2MM_LENGTH` 最后写。固件顺序应为：`DMACR(RS|IOCEN)` → `S2MM_DA` → `S2MM_LENGTH`。如果先写 LENGTH 再写 DA，可能用旧地址启动或根本不启动。板端读回 `0x30/0x48/0x58` 三个寄存器确认。

3. **写引擎 beat0 的高 448 位**  
   本次 TB 把 beat0 的 512-bit `tdata` 驱动为 `{8{64'hD555...}}`，即 8 个 8 B lane 都重复该图案，所以 64 B 全是 D5 图案。若板端写引擎只驱动 `tdata[63:0]` 而把 `tdata[511:64]` 置 0，IP 会**忠实**地把 0 写到 mem+8..+63——IP 没错，但 DDR 内容和以太网 payload 会变。请确认写引擎对 64 B 全 TKEEP 拍的 `tdata[511:64]` 也做了正确复制/拼接。

4. **写引擎 TLAST/TKEEP 时序**  
   确认 TLAST 正好在 22 B 那一拍、`TKEEP=0x0000_0000_003F_FFFF`。若 TLAST 晚来，DMA 会继续等/收；若早来，DMA 会以更短长度完成，`S2MM_LENGTH` 会小于 86。**板端完成后再读 `0x58`：如果读回 86，说明 IP 实际就收了 86 B；如果小于 86，问题在流侧 TLAST/TKEEP。**

5. **MM2S 读回路径**  
   启动 MM2S 后读 `MM2S_DMASR(0x04)`：若为 `0x1002` 且 `MM2S` 流 2 拍的 TKEEP/TLAST 正确，则 DMA 读路径正常。若 Err 位（0x770）置位，查板端 `M_AXI_MM2S` 的 interconnect/仲裁/MIG 路径，而不是 IP 配置。

6. **以太网 TX 链路**  
   如果 MM2S 已经输出正确 86 B（可用 ILA 抓 `m_axis_mm2s_tdata/tkeep/tlast`）但 PC 仍无帧，问题在 TX：帧长、FIFO/pump、TX ready、前导码/FCS、发送使能、以及固件在“S2MM 完成”后启动 TX 的条件。IP 仿真只能证明 DDR 里数据和 MM2S 流正确，不能证明 MAC/TX 正确。

7. **板端 interconnect/MIG 的 512-bit burst**  
   本仿真用简单 RAM，未建模板端 `axi_interconnect`/仲裁器/MIG。IP 的 AXI 主行为是标准的 2 拍 INCR burst（AWLEN=1、AWSIZE=6），但板端路径仍可能对 512-bit/2 拍 burst 有问题。建议用 ILA 抓 `M_AXI_S2MM` 的 AW/W/B 与 `M_AXI_MM2S` 的 AR/R，确认地址、WSTRB、WLAST、BRESP/RRESP。

8. **地址对齐**  
   `0x00100000 + slot*0x1000` 是 4 KiB 对齐，满足 DRE=0、512-bit 数据通路的 64 B 对齐要求。本次已验证 `0x100000/0x101000/0x102000` 三个地址均正常。

9. **异步 CDC（板端特有）**  
   板端 `s_axi_lite_aclk=100 MHz`、`ui_clk=300 MHz`，`c_prmry_is_aclk_async=1`。本仿真用单时钟 `0`，只覆盖数据通路。若固件连续快速写多个寄存器且不等待 AXI-Lite B 响应，CDC 路径可能表现出额外延迟；建议固件每次 `Xil_Out32` 后读回或确保 AXI-Lite 写完成，再写下一个寄存器。

### 7.3 一个可直接上板的判定实验

在板端完成一次 S2MM 后，用调试器读：

```text
DMA 基址 + 0x34 (S2MM_DMASR)  期望 0x00001002
DMA 基址 + 0x58 (S2MM_LENGTH) 期望 0x00000056 (86)
DMA 基址 + 0x30 (S2MM_DMACR)  期望 bit0=1, bit12=1（读回可能为 0x00011003）
```

- 若 `DMASR=0x1002` 且 `LENGTH=86`，则 S2MM 已完成、长度正确，问题在 MM2S/TX/固件触发；
- 若 `DMASR` 的 IOC 一直不置位，检查固件是否读到正确地址、RS 是否真的置 1、LENGTH 是否最后写；
- 若 `LENGTH` 不是 86，检查流侧 TLAST/TKEEP 或写入地址。

## 8. 文件与 SHA256

以下为最终交付文件的 SHA256（`REPORT.md` 自身的哈希见 `SHA256SUMS.txt`）：

| 文件 | 字节 | SHA256 |
|---|---:|---|
| `build_sim.tcl` | 4,444 | `3d4b17251be8ae744e90168708358c32685220a35d0e9849646220306eb6373c` |
| `run_sim.ps1` | 1,134 | `090c7bd13b385fdbd4a023fc779783423a5ef632afc9c0312bd102a42300a600` |
| `compare_config.py` | 2,377 | `176fdbea3c68c75575ea918468d600a10dbbd6611b45d8a576980c347d69b260` |
| `tb/tb_axi_dma_s2mm.sv` | 27,649 | `c41287ec5543925bda12c5c9ec6926d440c26365b0205715002a24d5a2351fd6` |
| `rtl/axi_ram_model.sv` | 6,373 | `4bd09e637dad6ff1faf7dbfcfe2a98d2425aa10bef4b5ad661778b652ff4270c` |
| `config_snapshot.txt` | 1,824 | `4c6828b771e84652097e588c20a5888af6bda7d95434b4cbbc91edf6a3bad542` |
| `config_compare.txt` | 2,214 | `e206645598299f92db27ae4fc6d8ba3ba07139a5aee16c8af8b704d5ad6c2fe0` |
| `axi_dma_0.veo` | 8,529 | `3c2e19fa82e7e2bc3b9cab9f6f39927f0decf01e49a937cae34c5d8c690edc7c` |
| `logs/console.log` | 31,993 | `ee1c1de7fff240f18336e1f0b36264432be12f4a46549b6ac127f44034b377dd` |
| `logs/simulate.log` | 11,742 | `758ccc620af659c598f77a3bc82f9785a2ccdef1f1a548f93afdc23600cb3085` |
| `logs/vivado.log` | 32,190 | `b247875c93f47549a63891c94f17e688ff5f62293387738bb3fdb49358eb2864` |
| `logs/tb_axi_dma_s2mm.vcd` | 52,844 | `e3e55d3306a9790287d80a9d87bebb13df818f0753b52b09bf39244ba9d41e18` |
| `logs/xvlog.log` | 577 | `2ca9f6a1f7af2163633ad5ac12112344549de627d2d0d477314c1e57004d423a` |
| `logs/xvhdl.log` | 217 | `7076dc3866221ef64488e972d307439b9c5628ea0aa072a0e152d9054454be0e` |

## 9. 限制与未覆盖

- 行为级 IP 仿真，非时序仿真；不包含板端 `axi_interconnect`/仲裁器/MIG/以太网 MAC。
- RAM 模型是理想从机（无 SLVERR/DECERR、无随机反压、固定 1 拍响应），不覆盖板端总线错误/拥塞。
- 单时钟 100 MHz；未覆盖板端 100M/300M 异步 CDC 的寄存器访问时序（见 1.2）。
- 未测 `s_axis_s2mm_tdata[511:64]` 的板端实际驱动值；TB 假设 beat0 的 8 个 8 B lane 都是 `0xD555...`。这是**写引擎**的职责，不是 IP 的映射问题。
- 未测以太网 TX 帧格式/前导码/FCS/发送触发；这些在 IP 之外。
- 未运行综合/实现，未生成 bit，未上板。

## 10. 参考

- AMD PG021《AXI DMA LogiCORE IP Product Guide》：
  - S2MM_LENGTH（Offset 0x58）：<https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_LENGTH-S2MM-DMA-Buffer-Length-Register-Offset-58h>  
    原文要点：“At the completion of the S2MM transfer, the number of actual bytes written on the S2MM AXI4 interface is updated to the S2MM_LENGTH register.”
  - Direct Register Mode：<https://docs.amd.com/r/en-US/pg021_axi_dma/Direct-Register-Mode-Simple-DMA>  
    原文要点：“The S2MM_LENGTH register must be written last.”
  - MM2S_LENGTH（Offset 0x28）：<https://docs.amd.com/r/en-US/pg021_axi_dma/MM2S_LENGTH-MM2S-DMA-Transfer-Length-Register-Offset-28h>
  - S2MM_DMASR（Offset 0x34）：<https://docs.amd.com/r/en-US/pg021_axi_dma/S2MM_DMASR-S2MM-DMA-Status-Register-Offset-34h>
- 本机 IP 实现常量：`D:\Xilinx\Vivado\2023.1\data\ip\xilinx\axi_dma_v7_1\hdl\axi_dma_v7_1_vh_rfs.vhd`（DMASR/DMACR/偏移常量，第 126–298 行）。
- 本机驱动头文件：`D:\Xilinx\Vivado\2023.1\data\embeddedsw-sdt\XilinxProcessorIPLib\drivers\axidma\src\xaxidma_hw.h`（HALTED/IDLE/ERR/IOC 掩码，第 139–159 行）。
- 工程配置来源：`D:\FPGA\prj\project_11\scripts\create_bd_b.tcl` 第 110–111 行；R2 BD XCI `mb_ctrl_axi_dma_0_0.xci`。
