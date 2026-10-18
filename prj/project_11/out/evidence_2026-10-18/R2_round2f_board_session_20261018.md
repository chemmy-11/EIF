# R2 round2f 板验场次（2026-10-18 20:57–21:05）—— 关键进展 + 新阻塞

状态：**round2f 位流过时序门限（WNS/WHS +0.004）并已上板**；AXI 楔死已可用固件间隔规避；**TX 上线上仍无帧（R2 特有，R1 对照正常）** → 板验仍未收口。

## 1. 构建（round2f）
- RTL 冻结：bridge `c92c20c7`（fix2）/ fmi `96d5b136` / top `1885225f` / **lite `d133b508`**（RVALID/BVALID 协议修复）
- **place/route**：`ExtraPostPlacementOpt` 后布 WNS=-0.013 → phys_opt 后 **WNS=+0.004 / WHS=+0.004** ⇒ 过门限 `V5_SWEEP2_OK`
- 产物：bit `8A8FE378`（9,958,604 B）、ltx `4AC25546`（探针与 round2c 相同：92/9/152、仅 2 核）、xsa `9403E1F2`、ELF 候选 `f8cf4022`；归档 `out/archive/b31b_r2_2026-10-18_round2f/`（24 项 + SHA256）
- S0 dry-run：**S0 PASS**（WNS/WHS/DRC/hash，bit8=8a8fe378 elf8=f8cf4022）

## 2. 板级结果
- 烧写 `8A8FE378` + 固件候选 → `PAIR_BURNED`；链路/串口/`'U'`/`'d'` 正常。
- **AXI 楔死**：纯 f8cf4022 固件上仍复现（'d'+ping 后 UART 静默）。逐项定位与规避：
  - marker 固件显示挂死点 = `dread()` 读 **lite_regs +0x40 (WR_REQ)**（PC 停在 `lwi`，`g_dbg_addr=0x44A00040`）；
  - 在 **S2MM `R_WRGO` 写后加 `busy_ms(1)` 间隔** 后：**连续多次 'd'+ping 不再楔死**，`'U'` 正常、`'I'` 计数推进；
  - ⇒ 楔死与"lite_regs 写(SET_WRGO) 后紧接读"仍相关；lite_regs RVALID/BVALID 协议修复**不是充分条件**，需继续查（写通道 bvalid/握手或读写在 AXI 上的时序竞争）。
- **写/读数据面在动**（ILA + 'I'）：`dbg_mem_wm/wr_frm/rd_frm=5/5/5`、`dbg_mem2_*=5/5/5`、`u_wr=10/u_rd=5`；`WR_DBG.last_commit_len=86` 出现 ⇒ **S2MM 写提交与 MM2S 读出均发生**。
- **TX 仍无帧**：PC ping 0/1、0/4；`r2_tx_probe.ps1 -Run` → 适配器 RX bytes/pkts/err/disc **全 +0**（netstat 全局计数不可用）⇒ 板侧无有效帧上线。
- emit 探针（ILA0 probe1）在 triggered capture 中采样到 rden=1 但 `mem_rd_data[7:0]` 恒 **0xff**（且 rden=0 时也是 0xff）⇒ 该探针观测链路本身不可信/总线空闲值，不能据此判槽内容；需新增写流/读流字节探针。
- **对照实验（关键）**：烧 **R1 绿位流 `c8cd3a32` + ELF `2961b585`**：未发 'd' ping 0/1（身份正确）；发 'd' 后 **ping 4/4 回包（TTL=128）** ⇒ 板/线缆/PC/PHY TX 链路正常，**问题在 R2 设计/固件的数据面**，不是环境。
- 收尾状态：板卡已烧回 R2 round2f 对（bit `8A8FE378` + 固件候选 **`b614a2dc`**（f8cf4022 + GO 后 1ms 间隔；50,944 B））。

## 3. 新增证据
- S0/工具：`out/evidence_2026-10-18/R2_20261018_20*.log`、`R2_txprobe_20261018_205955.log`
- ILA：`R2_ila_emittrig_*`（triggered on dbg_mem_rden）、`R2_ila_s4emit2_*`
- JTAG/marker：`r2_mark3_diag.log`（`G_CODE=1111/G_ADDR=44a00040`）、`r2_jtag_diag9.log`
- 对照：`r2_r1ctl_burn.log` + R1 ping 4/4 记录（本文件）
- 固件构建日志：`r2_finalsp_build.log`、`r2_sp_build.log`、`r2_mark3_build.log`

## 4. 下一步（建议）
1. **加写流字节探针**：`m_axis_s2mm_tdata[31:0]/tkeep[7:0]/tvalid/tready` 到 ILA0（user 域，临时移走 mem2_u_* 32b 腾位），复现单帧写并核对**前 8 字节是否 = 55×7,D5（前导+SFD）** 与首 64B 内容 → 直接判定"S2MM 写入 DDR 的槽内容是否正确"。
2. 若槽内容错：对照旧 W FSM 的字节序/前导生成，修新写引擎（最可能是 preamble 或字节序）。
3. 若槽内容对：查 TX 侧（`dma_rd_shim` DROP_BYTES 配置 vs 固件 SA/LEN、eth TX mux/TX enable）——R1 对照可复用同一固件口径。
4. 楔死根因继续：lite_regs 写通道 bvalid 单拍/awready 时序 + "写后紧接读"；目标去掉 `busy_ms(1)` 间隔后仍稳定。
5. 以上修好后重跑 S0–S11（本次已完成 S0/S1/S3；S2/S3b 判据已按新口径修正，S4/S5/S6/S7–S11 待数据面通）。
