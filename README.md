# EIF

**面向双机流水线训练实验的 FPGA 互联原型**

[![CI](https://github.com/chemmy-11/EIF/actions/workflows/ci.yml/badge.svg)](https://github.com/chemmy-11/EIF/actions/workflows/ci.yml)

EIF（Edge Interconnect Fabric）是 GSnFPipe 联合实验的 FPGA 侧工程。两台计算机分别运行模型的一部分，前向计算的中间结果和反向计算的梯度需要在两台主机之间传递。EIF 提供这条硬件数据通道，负责以太网接入、板间光纤传输、DDR4 帧缓存和板卡控制。

## 已验证的成果

| 实板验证 | 结果 |
| --- | --- |
| **A1 双向连续传输**（2026-11-27 正式签收） | 两块 FPGA 和两台 PC 的通路上，每个方向连续传输 **10,486,476 字节有效数据（超过 10 MiB）**，零丢包、零重复，逐字节核对通过。覆盖 **26–1472 字节**的六种 UDP 载荷，每个长度两向各测 20 帧；100 字节报文每向复测五轮，另有同时双向发送的抓包。 |
| **受控异常与恢复边界** | 序号缺失、等待超时、入口缓冲丢弃等受控异常均已取证。闪断（W1）与掉电（W2）后的**自主恢复未通过**；人工成对重烧可以恢复，保留 `need_reburn=Y`。 |
| **A2 GPP2 最小承载**（实测 6/6，待签收） | 双向短/最大 DATA、同路径 ACK/ERROR 通过，双端 18 个唯一 IPv4 包逐字节一致；固定 Tensor 经双 FPGA 重组尚未测试，本机回环不能代替双板重组。 |
| **网口出口故障修复** | 板间已收到数据、接收端 PC 却抓不到转发包。结合片上波形与主机抓包，把故障定位到以太网封装，补齐前导码、帧校验序列并改正目的 MAC；修复后双向各 3 帧复测通过。 |

记录：[A1 验收与证据](https://github.com/chemmy-11/GSnFPipe-FPGA-PP/issues/14) · [A2 判据](https://github.com/chemmy-11/GSnFPipe-FPGA-PP/issues/10) · [网口封装修复与上板复测](prj/project_13/docs/M1_prj13_P2双板透传晚窗签收报告_2026-11-20.md)

## 系统架构

```mermaid
flowchart LR
    H1["计算主机 1"] <-->|千兆以太网| F1["FPGA 1<br/>转发与 DDR4 缓存"]
    F1 <-->|10 Gb/s 光链路| F2["FPGA 2<br/>转发与 DDR4 缓存"]
    F2 <-->|千兆以太网| H2["计算主机 2"]
```

两块 Kintex UltraScale KU060 通过 SFP+ 光纤运行 Aurora 64B/66B，板间光段配置为 10 Gb/s，两端主机从千兆以太网接入。训练进程运行在主机上，FPGA 负责搬运与缓存数据。

- **以太网转发**　解析 IPv4 报文，按目的地址转发。跨板保留 IP 包，由接收板重建面向本地网卡的以太网帧。[转发与封装 RTL](prj/project_13/rtl/p2/)
- **缓存与数据搬运**　用异步 FIFO 在不同时钟域间交接数据，以整帧为单位在 DDR4 中写入和读出。MicroBlaze 软核处理配置与状态，AXI DMA 参与内存搬运。[帧缓存接口](prj/project_13/rtl/frame_mem_if.v) · [内存桥 RTL](prj/project_13/rtl/axi4_master_bridge.v) · [软核固件](prj/project_13/sw/src_j3/main.c)
- **实板调试**　用带序号的 UDP 测试帧把主机抓包、片上逻辑分析仪（ILA）和串口计数对在同一轮测试上，可以逐段判断帧在哪一步失去进展。[发包与抓包工具](prj/project_13/pc/) · [双板接线与验证操作单](prj/project_13/docs/M1_prj13_双板恢复与A1收口操作单_2026-11-23.md)

## 接下来验证什么

A2 是当前门槛：交付接口、配置与能力文件，完成固定 Tensor 经双 FPGA 的重组并走签收，之后进入 J1/J2 与 A3。工程侧 V4 配对工件、T6/T8 等按 issue 跟踪；10 Gb/s 是光链路的配置速率，不能当作已测端到端吞吐。[A2 判据](https://github.com/chemmy-11/GSnFPipe-FPGA-PP/issues/10) · [V4 工件](https://github.com/chemmy-11/EIF/issues/20) · [当前入口](docs/README.md#当前执行入口)

## 阅读与复现

| 想看什么 | 入口 |
| --- | --- |
| FPGA 的完整数据流 | [顶层 RTL](prj/project_13/rtl/aurora_mem_bridge.v) |
| 不接板先看一次仿真 | [帧缓存测试平台](prj/project_13/sim/p2/tb_p2_frame_buf.v) |
| 双板如何接线、烧录和验收 | [双板操作单](prj/project_13/docs/M1_prj13_双板恢复与A1收口操作单_2026-11-23.md) |
| 文档怎么组织、放哪一类 | [文档索引](docs/README.md) |
| 每件工作具体做了什么 | [已完成工作导览](docs/导览_cross_已完成工作说明_2026-11-27.md) |
| 工程规范与坑账本 | [AGENTS.md](AGENTS.md) · [PITFALLS.md](PITFALLS.md) |

把仓库放在纯英文路径（如 `D:\FPGA`）下，用 Vivado 2023.1 运行帧缓存仿真——中文路径会被 Vivado 按 GBK 解码而报 File not found。将 `$VivadoBin` 改为本机 Vivado 的 `bin` 目录。

```powershell
$VivadoBin = 'D:\Xilinx\Vivado\2023.1\bin'
powershell -NoProfile -ExecutionPolicy Bypass -File prj/project_13/sim/p2/run_p2_sim.ps1 `
  -VivadoBin $VivadoBin -Only framebuf -TempDir "$PWD\.tmp\sim"
```

通过时输出 `P2_FRAMEBUF_TB: PASS=5 FAIL=0`，包括逐字节读回和队列满时整帧丢弃。安装 Python 3 后，可用 `py -3 scripts/ci_check.py` 检查文档链接、索引与脚本语法。

## 许可

作者原创部分采用 [MIT License](LICENSE)。第三方代码、官方例程及 IP 生成物的权利归属见 [第三方声明](THIRD_PARTY.md)。
