# -*- coding: utf-8 -*-
"""R3 perf3 实验：写服务 GO 之后的固定 busy_ms(1)（实测 ~150µs）改为 S2MM 完成(IOC)等待。
只改固件；perf1 源码已在归档 round3c/main_perf1.c。
（用通用换行读取，兼容 git checkout 后的 CRLF）"""
import io

MAIN = r"D:\FPGA\prj\project_11\sw\src_j3\main.c"
COPY = r"D:\FPGA\prj\project_11\sw\j3_soft\src\main.c"

raw = io.open(MAIN, "rb").read()
crlf = raw.count(b"\r\n")
s = raw.decode("utf-8").replace("\r\n", "\n")

old = """    /* ★2026-10-19 perf1: 写服务不再做 20ms 静默 + 5 次寄存器快照（那是楔死定位期的
     * 诊断动作, 会把单帧服务时间拉到 ~3ms, 1000fps 质量档必然丢帧）。改为最小 1ms
     * 窗口, 让固件服务节奏回到 round2f 同口径; 状态取证改用 'W' 命令按需读取。 */
    busy_ms(1);"""
new = """    /* ★R3 perf3 (2026-10-19 速率实验): GO 后不再固定 busy_ms(1)（实测 ~150µs/帧），
     * 改为等 S2MM 本帧完成 (DMASR.IOC=1；编程前 s2mm_rearm 已清 IOC)。
     * 目的：把"固定等待"换成"事件等待"，量化 busy 地板对每帧服务时间的贡献。 */
    {
        unsigned sr3, g3 = 0u;
        do { sr3 = dread(&S2MM_DMASR); }
        while (((sr3 & DMA_SR_IOC) == 0u) && (++g3 < 200000u));
    }"""
assert old in s, "perf1 busy block not found"
s = s.replace(old, new, 1)
out = s.encode("utf-8")
io.open(MAIN, "wb").write(out)
io.open(COPY, "wb").write(out)
print("PERF3_PATCH_OK bytes=%d crlf_before=%d" % (len(out), crlf))
