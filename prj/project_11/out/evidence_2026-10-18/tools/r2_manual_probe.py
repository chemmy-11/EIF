# -*- coding: utf-8 -*-
"""R2 板验现场诊断 (9600 UART): 手工序列 + ping, 逐段落日志.
用法: python r2_manual_probe.py <tag>
前置: 板卡已烧 R2 对; PC 静态 ARP 就绪; COM5 空闲.
"""
import io, subprocess, sys, time
import serial

TAG = sys.argv[1] if len(sys.argv) > 1 else "diag"
LOG = r"D:\FPGA\prj\project_11\out\evidence_2026-10-18\R2_manual_" + TAG + ".log"
out = io.open(LOG, "w", encoding="utf-8", newline="\n")


def w(s):
    out.write(s + "\n")
    out.flush()
    print(s)


def ping(n=1, timeout_ms=1200):
    r = subprocess.run(["ping.exe", "-n", str(n), "-w", str(timeout_ms), "192.168.1.10"],
                       capture_output=True, text=True)
    txt = r.stdout
    keep = [l for l in txt.splitlines() if ("TTL=" in l or "100%" in l or "Lost" in l)]
    return " | ".join(k.strip() for k in keep)


def main():
    port = serial.Serial("COM5", 9600, timeout=0.2)
    def send(cmd, wait=1.2, label=""):
        port.reset_input_buffer()
        port.write(cmd.encode())
        time.sleep(wait)
        data = port.read(port.in_waiting or 4000).decode("utf-8", "replace")
        w("== %s send=%r len=%d ==" % (label, cmd, len(data)))
        for line in data.splitlines():
            if line.strip():
                w("   " + line.strip())
        return data

    try:
        time.sleep(0.5)
        w("TAG=%s time=%s" % (TAG, time.strftime("%H:%M:%S")))
        send("U", 1.5, "baseline_U")
        send("S", 0.4, "S1")
        w("PING1: " + ping(1))
        send("U", 1.5, "after_ping_mode0")
        send("d", 0.4, "toggle_d")
        send("U", 1.5, "after_d_U")
        send("S", 0.4, "S2")
        w("PING2: " + ping(1))
        send("U", 1.5, "after_ping_mode1")
        send("I", 1.2, "I_line")
        w("PING3: " + ping(2))
        send("U", 1.5, "final_U")
        w("DONE")
    finally:
        port.close()
        out.close()


if __name__ == "__main__":
    main()
