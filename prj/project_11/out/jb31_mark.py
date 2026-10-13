# -*- coding: utf-8 -*-
"""J_B3-1 判别3: 写标志帧 seq=0xDEADBEEF -> 等回显确认入 DDR"""
import sys, time
sys.path.insert(0, r"D:\FPGA\prj\project_10\prj_loop\scripts")
from j3_random_read import CmdClient, DataPlane, build_payload, MODE_SEQ, warmup_link

cli = CmdClient("192.168.1.102")
dm = DataPlane("192.168.1.102")
cli.set_mode(MODE_SEQ)
warmup_link(dm.dst[0], dm.dst[1], enabled=True, settle_s=0.8, bind_ip="192.168.1.102")
time.sleep(0.3)
dm.drain(0.3)
MARK = 0xDEADBEEF
dm.send(build_payload(MARK, 9, 64))
echo = dm.drain(1.5)
print("marker seq=0x%08x, echo frames=%d" % (MARK, len(echo)))
for e in echo:
    print("  echo first4: %s" % e[:4].hex())
print("MARKER_WRITTEN" if echo else "MARKER_FAIL")
