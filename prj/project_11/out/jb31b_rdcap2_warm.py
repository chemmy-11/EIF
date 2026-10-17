# -*- coding: utf-8 -*-
"""jb31b_rdcap2_warm.py -- 武装前预热(绝不进 ILA 窗口): 可选 'd' 切 DMA + ping 解 ARP + 暖机帧
+ 排空 + 「总线上已无在飞帧」的静默判据。

用法:
  py jb31b_rdcap2_warm.py --send-d          # 退役位流上电后: 切 DMA + 全套预热
  py jb31b_rdcap2_warm.py                   # 引擎已确认是 DMA 时只做预热

为什么必须先 warm 再武装:
  ILA 的触发是 "dbg_mem_rden == 1"(发射使能) 的电平比较。武装那一刻若还有任何一帧
  没读完(或随后到达任何一帧), 触发就会落在**那一帧**上, 抓到的就不是目标帧。
  所以本脚本在武装前把「ping 的 ARP/ICMP 应答 + 暖机帧」全部发完、排空, 并用软核
  自己的 'I' 计数器(wr/rd)证明 wr==rd 且两拍不变 —— 即发射侧已清空。

判据与退出码:
  0 = D_OK 且 WARM_QUIET=YES
  3 = 引擎状态读不回来 / 不是 DMA(退役位流上等于没有读出路径) —— 外层 bat 应中止武装
  4 = 不静默(wr!=rd 或计数仍在动) —— 可以 --force 强行继续, 但抓到的可能不是目标帧

注意: 本脚本只碰串口与 UDP, 不进 Vivado、不 ping 之外不发 ICMP 之外的任何探测。
"""
import argparse
import os
import re
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from jb31b_rdcap2_send import ensure_dma, read_for  # noqa: E402

WARM_PAYLOAD = b"warm" + b"." * 60      # 64B: 合法最小帧(旧脚本用 4B 会让网卡丢弃)


def ping_once(ip, verbose=True):
    try:
        rc = subprocess.run(["ping", "-n", "1", "-w", "1000", ip],
                            capture_output=True).returncode
    except OSError as e:
        if verbose:
            print("PING_RC=err(%s)" % e)
        return None
    if verbose:
        print("PING_RC=%d" % rc)
    return rc


def read_counters(ser, wait=1.2):
    """发 'I' 读回 wr/rd/drop(十进制); 返回 (wr, rd, drop) 或 None。"""
    ser.reset_input_buffer()
    ser.write(b"I")
    ser.flush()
    raw = read_for(ser, wait)
    txt = raw.decode("latin-1", "replace")
    m = re.search(r"wr=(\d+)\s+rd=(\d+)\s+drop=(\d+)", txt)
    if not m:
        return None, txt
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))), txt


def main(argv=None):
    ap = argparse.ArgumentParser(description="pre-arm warm-up / drain / quiescence check")
    ap.add_argument("--com", default="COM5")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--src-ip", default="192.168.1.102")
    ap.add_argument("--dst-ip", default="192.168.1.10")
    ap.add_argument("--src-port", type=int, default=1234)
    ap.add_argument("--dst-port", type=int, default=1234)
    ap.add_argument("--send-d", action="store_true",
                    help="ensure the read engine is DMA (toggle-safe, verified via 'U')")
    ap.add_argument("--require-dma", action="store_true",
                    help="exit 3 unless the DMA state is positively confirmed (retired bitstream)")
    ap.add_argument("--frames", type=int, default=2, help="how many warm frames to send")
    ap.add_argument("--no-ping", action="store_true")
    ap.add_argument("--drain", type=float, default=2.0, help="drain window seconds")
    ap.add_argument("--quiet-wait", type=float, default=6.0)
    ap.add_argument("--quiet-poll", type=float, default=0.4)
    ap.add_argument("--no-uart", action="store_true", help="skip all serial steps")
    ap.add_argument("--force", action="store_true", help="exit 0 even if not quiet")
    a = ap.parse_args(argv)

    ser = None
    if not a.no_uart:
        try:
            import serial
        except ImportError:
            print("ERR: pyserial missing", file=sys.stderr)
            return 2
        try:
            ser = serial.Serial(a.com, a.baud, timeout=0.2)
        except Exception as e:                       # noqa: BLE001
            print("ERR: open %s failed: %s" % (a.com, e), file=sys.stderr)
            return 3

    d_state = None
    if ser and a.send_d:
        d_state, d_log = ensure_dma(ser)
        print("D_MODE=%s" % ("dma" if d_state == 1 else
                            ("bridge" if d_state == 0 else "unknown")))
        for line in d_log.splitlines():
            print("D_TRACE: %s" % line)
        if d_state != 1:
            if d_state == 0 or a.require_dma:
                print("WARM_FAIL: engine is not DMA; the retired bitstream has no read-out path")
                ser.close()
                return 3
            print("WARM_D_NOTE: 'U' gave no answer; engine state unverified "
                  "(firmware may predate 'U' - green bitstream flow)")

    if not a.no_ping:
        ping_once(a.dst_ip)

    sk = None
    echoed = 0
    if a.frames > 0:
        try:
            sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sk.bind((a.src_ip, a.src_port))
            sk.settimeout(0.3)
        except Exception as e:                       # noqa: BLE001
            print("ERR: bind %s:%d failed: %s" % (a.src_ip, a.src_port, e), file=sys.stderr)
            if ser:
                ser.close()
            return 2
        for k in range(a.frames):
            sk.sendto(WARM_PAYLOAD, (a.dst_ip, a.dst_port))
            time.sleep(0.2)
        print("WARM_FRAMES_SENT=%d len=%d" % (a.frames, len(WARM_PAYLOAD)))
        t0 = time.time()
        while time.time() - t0 < a.drain:
            try:
                sk.recvfrom(2048)
                echoed += 1
            except socket.timeout:
                pass
            except OSError:
                break
        sk.close()
        print("WARM_ECHO=%d" % echoed)

    quiet = None
    wr = rd = drop = None
    if ser:
        prev = None
        deadline = time.time() + a.quiet_wait
        tries = 0
        while time.time() < deadline:
            tries += 1
            cur, txt = read_counters(ser)
            if cur is None:
                print("WARM_I_NOTE: counters unreadable (try %d)" % tries)
            else:
                wr, rd, drop = cur
                same = (prev is not None and cur[0] == prev[0] and cur[1] == prev[1])
                print("WARM_COUNTERS[%d]: wr=%d rd=%d drop=%d stable=%s"
                      % (tries, wr, rd, drop, "YES" if same else "NO"))
                if wr == rd and same:
                    quiet = True
                    break
                prev = cur
            time.sleep(a.quiet_poll)
        if quiet is None:
            quiet = False
        ser.close()
    else:
        print("WARM_COUNTERS: skipped (--no-uart)")

    if quiet is None:
        print("WARM_QUIET=UNKNOWN")
    else:
        print("WARM_QUIET=%s wr=%s rd=%s drop=%s"
              % ("YES" if quiet else "NO",
                 "-" if wr is None else wr,
                 "-" if rd is None else rd,
                 "-" if drop is None else drop))
    print("WARM_DONE")
    if quiet is False and not a.force:
        return 4
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass
    sys.exit(main())
