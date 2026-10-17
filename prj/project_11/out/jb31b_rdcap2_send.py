# -*- coding: utf-8 -*-
"""jb31b_rdcap2_send.py -- 在 ILA 武装窗口内发「那条」1472B 自描述载荷帧（并可选先切 DMA 引擎）。

用法:
  py jb31b_rdcap2_send.py --mode retired            # 捕获窗口内的快路径(不发 'd')
  py jb31b_rdcap2_send.py --mode retired --send-d   # 上电后/武装前手动补 'd'
  py jb31b_rdcap2_send.py --mode green

为什么有 --send-d:
  退役位流(bridge 硬件读引擎已退休)上电后必须切到 DMA 引擎(engine=1)才有读出路径。
  'd' 在固件里是**翻转**(toggle)语义, 所以本脚本不盲发: 先发 'U' 读回 g_dma_mode,
  只有读到 0 才补一次 'd', 最多 3 轮 —— 幂等, 不会把已切好的引擎翻回去。
  'U' 的回显行形如 "[B2] U mode=1"。

为什么 --send-d 不该放进捕获窗口:
  'U'+'d' 的状态确认要 ~1s, 会拉长「武装→目标帧」的窗口, 让别处的帧有插队机会。
  纪律: 'd' 在 warm 阶段或上电后单独做(jb31b_rdcap2_warm.py --send-d), 窗口内只发帧。

输出:
  stdout 一行机器可读: "MODE=<m> echo=<n> match=YES|NO"
  落盘 out\\evidence_2026-10-17\\rdcap2_send_<mode>_<时间戳>.log (含回显前 32B hexdump)

退出码: 0 = 正常(含 echo=0 的 0 回显现象, 那是结论不是错误); 2 = 串口/套接字异常。
"""
import argparse
import os
import re
import socket
import sys
import time

LEN = 1472
EVID_DIR = r"D:\FPGA\prj\project_11\out\evidence_2026-10-17"


def payload(n=LEN):
    """自描述载荷: byte[i] = i & 0xFF —— 帧内任意 4B 窗口可反解偏移。"""
    return bytes((i & 0xFF) for i in range(n))


def hx(data, limit=None):
    if limit is not None:
        data = data[:limit]
    return " ".join("%02x" % b for b in data) if data else "(empty)"


def read_for(ser, secs, chunk=4096, idle_stop=False):
    """读串口 secs 秒(idle_stop=True 时, 读到东西后静默 0.3s 即提前返回)。"""
    out = b""
    t0 = time.time()
    last = t0
    while time.time() - t0 < secs:
        d = ser.read(chunk)
        if d:
            out += d
            last = time.time()
        elif idle_stop and out and (time.time() - last) > 0.3:
            break
    return out


def dma_state(ser, wait=1.5):
    """发 'U' 读回 g_dma_mode; 返回 (0|1|None, raw)。"""
    ser.reset_input_buffer()
    ser.write(b"U")
    ser.flush()
    raw = read_for(ser, wait)
    m = re.search(rb"U mode=(\d)", raw)
    return (int(m.group(1)) if m else None), raw


def ensure_dma(ser, tries=3, wait=1.5, verbose=True):
    """幂等地把引擎切到 DMA(engine=1)。返回 (state|None, log_text)。"""
    log = []
    for k in range(tries):
        st, raw = dma_state(ser, wait)
        log.append("U#%d -> mode=%s" % (k, st if st is not None else "unknown"))
        if verbose:
            print("D_STATE[%d]: %s" % (k, st if st is not None else "unknown"))
        if st == 1:
            return 1, "\n".join(log)
        if st is None and k >= 1:
            break
        ser.reset_input_buffer()
        ser.write(b"d")
        ser.flush()
        time.sleep(0.3)
        raw = read_for(ser, wait, idle_stop=True)
        for line in raw.decode("latin-1", "replace").splitlines():
            if "DMAMODE" in line:
                log.append("d#%d -> %s" % (k, line.strip()))
                if verbose:
                    print("D_ACK[%d]: %s" % (k, line.strip()))
    st, raw = dma_state(ser, wait)
    log.append("final -> mode=%s" % (st if st is not None else "unknown"))
    return st, "\n".join(log)


def main(argv=None):
    ap = argparse.ArgumentParser(description="send the 1472B self-describing payload frame")
    ap.add_argument("--mode", choices=("retired", "green"), required=True)
    ap.add_argument("--com", default="COM5")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--src-ip", default="192.168.1.102")
    ap.add_argument("--dst-ip", default="192.168.1.10")
    ap.add_argument("--src-port", type=int, default=1234)
    ap.add_argument("--dst-port", type=int, default=1234)
    ap.add_argument("--send-d", action="store_true",
                    help="send 'd' first (toggle-safe, verified via the 'U' readback)")
    ap.add_argument("--no-uart", action="store_true", help="do not open the serial port at all")
    ap.add_argument("--echo-wait", type=float, default=6.0)
    ap.add_argument("--uart-wait", type=float, default=2.0)
    ap.add_argument("--out-dir", default=EVID_DIR)
    ap.add_argument("--tag", default="")
    a = ap.parse_args(argv)

    py = payload()
    stamp = time.strftime("%Y%m%d_%H%M%S")
    tag = ("_" + a.tag) if a.tag else ""
    if not os.path.isdir(a.out_dir):
        os.makedirs(a.out_dir, exist_ok=True)
    evid = os.path.join(a.out_dir, "rdcap2_send_%s_%s%s.log" % (a.mode, stamp, tag))

    if a.mode == "retired" and not a.send_d and not a.no_uart:
        print("WARN: mode=retired without --send-d; engine must already be DMA "
              "(check the 'U mode=1' readback in the warm step)")

    ser = None
    d_log = "(skipped)"
    d_state = "-"
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
            return 2
        if a.send_d:
            d_state, d_log = ensure_dma(ser)
            print("D_MODE=%s" % ("dma" if d_state == 1 else
                                ("bridge" if d_state == 0 else "unknown")))
            if d_state != 1:
                print("WARN: engine state not confirmed as DMA", flush=True)

    try:
        sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sk.bind((a.src_ip, a.src_port))
    except Exception as e:                            # noqa: BLE001
        print("ERR: bind %s:%d failed: %s" % (a.src_ip, a.src_port, e), file=sys.stderr)
        if ser:
            ser.close()
        return 2
    sk.settimeout(0.3)

    if ser:
        ser.reset_input_buffer()                     # 丢掉 'd'/'U' 的回显残包
    # 武装窗口内唯一的一发: 目标帧
    t_send = time.time()
    sk.sendto(py, (a.dst_ip, a.dst_port))

    got = []
    errs = 0
    t0 = time.time()
    while time.time() - t0 < a.echo_wait and not got:
        try:
            d, _ = sk.recvfrom(2048)
            got.append(d)
        except socket.timeout:
            pass
        except OSError:                              # ICMP unreachable -> WSAECONNRESET
            errs += 1
            if errs > 5:
                break
            time.sleep(0.1)
    dt = time.time() - t_send

    uart = b""
    if ser:
        uart = read_for(ser, a.uart_wait)
        ser.close()

    echo_n = len(got)
    match = bool(got) and got[0] == py
    print("MODE=%s echo=%d match=%s" % (a.mode, echo_n, "YES" if match else "NO"))
    if got:
        print("ECHO_LEN=%d ECHO_HEAD32=%s" % (len(got[0]), hx(got[0], 32)))
    else:
        print("ECHO_LEN=0 ECHO_HEAD32=(none)")
    print("DT_SEND_TO_ECHO=%.3fs" % dt)

    lines = [
        "MODE=%s" % a.mode,
        "TIME=%s" % time.strftime("%Y-%m-%d %H:%M:%S"),
        "SEND_D=%s" % ("yes" if a.send_d else "no"),
        "D_MODE=%s" % ("dma" if d_state == 1 else ("bridge" if d_state == 0 else "n/a")),
        "D_LOG_BEGIN",
        d_log,
        "D_LOG_END",
        "PEER=%s:%d -> %s:%d" % (a.src_ip, a.src_port, a.dst_ip, a.dst_port),
        "PAYLOAD_LEN=%d" % len(py),
        "ECHO_COUNT=%d" % echo_n,
        "ECHO_LEN=%d" % (len(got[0]) if got else 0),
        "MATCH=%s" % ("YES" if match else "NO"),
        "DT_SEND_TO_ECHO=%.3fs" % dt,
        "ECHO_HEAD32=%s" % (hx(got[0], 32) if got else "(none)"),
        "ECHO_TAIL16=%s" % (hx(got[0][-16:]) if got else "(none)"),
        "UART_TEXT=%s" % uart.decode("latin-1", "replace").replace("\r", "\\r").replace("\n", " | "),
    ]
    try:
        with open(evid, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
        print("EVIDENCE=%s" % evid)
    except OSError as e:
        print("WARN: write evidence failed: %s" % e, file=sys.stderr)
    if uart.strip():
        print("UART=%s" % uart.decode("latin-1", "replace")
              .replace("\r", "\\r").replace("\n", " | "))
    sk.close()
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass
    sys.exit(main())
