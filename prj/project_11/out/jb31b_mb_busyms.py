# -*- coding: utf-8 -*-
"""m_b_busyms.py —— busy_ms 时基实测: 软核连打 N 个 'I' (每个之间由软核 busy_ms 延时),
用 PC 侧时间戳测 'E'-START 到 E-DONE 的真实耗时, 对照源码换算标定 busy_ms 真实时基。

方法: 'E' 轮的 stall 退出路径 = 4000 次"无 sticky"分支, 每分支 1 次 busy_ms(1) + rd_reg(内部又 busy_ms(1))。
所以 E-DONE(served=0, stall=1) 的总时长 ≈ 4000 × (2×busy_ms(1) + rd_reg 其他开销)。
直接测 E-START→E-DONE 时间差, 除以 4000×2 得 busy_ms(1) 单次真实时长。
"""
import serial
import time

s = serial.Serial("COM5", 9600, timeout=0.2)
time.sleep(0.5)
s.reset_input_buffer()

s.write(b"E")
t_start = time.time()
buf = b""
while time.time() - t_start < 300:          # 上限 5 分钟
    d = s.read(4096)
    if d:
        buf += d
        if b"E-DONE" in buf:
            t_done = time.time()
            break
else:
    t_done = None

print("UART 输出: %s" % buf.decode("ascii", errors="replace").strip())
if t_done:
    dur = t_done - t_start
    # stall 路径: 4000 轮 × [rd_reg(0x34) + busy_ms(1)] + drained 判定 [2×rd_reg]
    # rd_reg = 哑写 + busy_ms(1) + 双读(dread 无延时)
    # 每轮 busy_ms 调用数 ≈ 2 (serve 里的 rd_reg 1 次 + else 分支 busy_ms 1 次)
    # drained 判定每轮再 2 次 rd_reg = 2 次 busy_ms
    # 保守估计: 每轮 ~4 次 busy_ms(1), 4000 轮 = 16000 次
    est_per_ms = dur / (4000 * 4)
    print("E-START → E-DONE 总时长: %.1f 秒" % dur)
    print("÷ 16000 次 busy_ms(1) ≈ %.2f ms/次 (源码意图 = 1ms, 偏差 %.0f×)" % (est_per_ms * 1000, est_per_ms))
else:
    print("5 分钟内未出 E-DONE —— 说明 stall 路径耗时 > 300s, busy_ms(1) > %.1f ms" % (300000/16000))
