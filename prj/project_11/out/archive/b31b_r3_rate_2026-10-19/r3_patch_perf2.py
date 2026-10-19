# -*- coding: utf-8 -*-
"""R3 perf2 实验：读服务去掉"每帧整引擎软复位"，改为 MM2S 确保运行 + IOC 等完成。
（只改固件，不动 RTL/位流；perf1 源码已在归档 round3c/main_perf1.c）"""
import io
import os
import sys

MAIN = r"D:\FPGA\prj\project_11\sw\src_j3\main.c"
COPY = r"D:\FPGA\prj\project_11\sw\j3_soft\src\main.c"

s = io.open(MAIN, encoding="utf-8", newline="").read()

# 1) 在 serve_dma_once 前插入 mm2s_ensure_run()
anchor = "static void s2mm_rearm(void);   /* fwd: 读服务后重武装 S2MM (定义见写服务段; MM2S 复位会连带复位 S2MM) */"
assert anchor in s, "anchor fwd decl not found"
helper = anchor + r'''

/* ★R3 perf2 (2026-10-19 速率实验): 读服务不再每帧做 MM2S 软复位。
 * 依据 PG021 Direct Register Mode：DMASR.Halted=0/RS=1 时直接写 SA/LENGTH 即可启动下一笔；
 * 原每帧 DMA_DMACR=0x4 会复位【整个 AXI DMA】（PG021），是每帧 ~0.1-0.2ms 量级的固定成本。
 * 本函数只保证 MM2S 处于运行态并清上一笔 IOC，然后用 IOC 等完成（不再用 Idle 判据）。 */
static void mm2s_ensure_run(void)
{
    unsigned sr, guard;
    sr = dread(&DMA_DMASR);
    if (((sr & DMA_SR_HALT) != 0u) || ((dread(&DMA_DMACR) & DMA_CR_RS) == 0u)) {
        DMA_DMACR = DMA_CR_IOCEN | DMA_CR_RS;
        guard = 0;
        while ((((sr = dread(&DMA_DMASR))) & DMA_SR_HALT) != 0u)
            if (++guard > 4000000u) break;
    }
    DMA_DMASR = DMA_SR_IOC;             /* W1C: 清上一笔完成中断 */
}'''
s = s.replace(anchor, helper, 1)

# 2) 替换原来的 reset+RS 块 与 Idle 等完成
old_block = """    DMA_DMACR = 0x4u;                   /* reset */
    guard = 0;
    while ((((sr = dread(&DMA_DMASR))) & 0x1u) == 0u)
        if (++guard > 4000000u) break;
    DMA_DMACR = 0x1u;                   /* RS=run */
    guard = 0;
    while ((((sr = dread(&DMA_DMASR))) & 0x1u) != 0u)
        if (++guard > 4000000u) break;

    DMA_SA     = sa;                    /* 配对 A: v5-RTL(DROP_BYTES=0) */
    DMA_LENGTH = len;
    guard = 0;
    do { sr = dread(&DMA_DMASR); }
    while (((sr & 0x2u) == 0u) && (++guard < 80000000u));"""
new_block = """    mm2s_ensure_run();                  /* perf2: 不再整引擎复位，只确保运行态+清 IOC */

    DMA_SA     = sa;                    /* 配对 A: v5-RTL(DROP_BYTES=0) */
    DMA_LENGTH = len;
    guard = 0;
    do { sr = dread(&DMA_DMASR); }
    while (((sr & DMA_SR_IOC) == 0u) && (++guard < 80000000u));   /* perf2: 用 IOC 判完成 */"""
assert old_block in s, "reset block not found"
s = s.replace(old_block, new_block, 1)

io.open(MAIN, "w", encoding="utf-8", newline="").write(s)
io.open(COPY, "w", encoding="utf-8", newline="").write(s)
print("PERF2_PATCH_OK", len(s))
