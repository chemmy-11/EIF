# -*- coding: utf-8 -*-
"""bcast_probe.py -- 绕过 PC 侧 ARP 依赖: 以广播 MAC/IP 发 UDP, 看板卡是否回显。
若回显 => 数据面(含退休位流的 DMA 读出)可用, ARP 应答是唯一坏点。
若不回显 => 数据面本身不通(ARP 只是表象)。"""
import socket, sys, time

payload = bytes(range(1, 33))
ports = [(1234, 1236)]
for dst_port, src_port in ports:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.bind(("", src_port))
    s.settimeout(0.5)
    got = []
    for k in range(5):
        s.sendto(payload, ("192.168.1.255", dst_port))
        t0 = time.time()
        while time.time() - t0 < 1.2:
            try:
                data, addr = s.recvfrom(2048)
                got.append((addr, data[:40]))
            except socket.timeout:
                pass
        time.sleep(0.1)
    print("port %d -> replies: %r" % (dst_port, got[:3]) if got else "port %d -> NO REPLY" % dst_port, flush=True)
    s.close()
