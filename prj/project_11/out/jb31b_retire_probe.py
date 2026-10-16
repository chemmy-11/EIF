# -*- coding: utf-8 -*-
"""retire_probe.py — 验证「退役后读回必须由软核服务」假说:
   在 'E' 服务循环运行期间 ping, 若通则说明 ARP 应答也依赖读回服务。"""
import subprocess
import threading
import time

import serial

s = serial.Serial("COM5", 9600, timeout=0.2)
s.reset_input_buffer()

out = []


def ping_during():
    for i in range(4):
        time.sleep(1.5)
        r = subprocess.run(["ping", "-n", "1", "-w", "1000", "192.168.1.10"],
                           capture_output=True, text=True, errors="replace")
        ok = "TTL=" in (r.stdout or "")
        out.append("ping#%d ok=%s" % (i, ok))


t = threading.Thread(target=ping_during, daemon=True)
t.start()

s.write(b"E")
buf = b""
t0 = time.time()
while time.time() - t0 < 12:
    buf += s.read(4096)
t.join()
print("\n".join(out))
print("UART:", buf.decode("ascii", errors="replace").replace("\r\n", " | "))
