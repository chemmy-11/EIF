#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
j3_soft_verify.py — prj11 B2 · 软核版 J3 随机读引擎（PC 侧，j3_soft 配套）

派生自 prj10 j3_random_read.py（**只读 import 载荷编解码**，prj10 原件零改动）。
角色互换（B2 = Q3 理想终态核心）：
  prj10 J3: PC 经 UDP 命令通道下发 SET_MODE/READ_SLOT
  prj11 B2: MicroBlaze 经 AXI-Lite 下发；PC 只剩 ①数据面(写帧/收读出帧)
            ②场次编排(COM5@9600 单字符命令 + 读 C 的进度/计数行)

与 C 侧 (sw/src_j3/main.c) 的 UART 协议:
  发 'M'/'A'/'B' → C: SET_MODE(SEQ)               → "[B2] SEQOK t=X"
  （PC 在 SEQ 窗做 UDP 预热刷 ARP——RND 下板卡发不出 ARP 应答,
    PC 邻居表老化会丢单播数据帧; j3_random_read.py 2026-10-08 实证）
  再发同字符=GO  → C: SET_MODE(RND)+稳定基线      → "[B2] READY t=X wr0=%d rd0=%d"
                    自动: 等 wm_wr+256 → 逆序 255..0 逐槽 RD_SLOT(每槽等 wm_rd
                    增量到位) → "[B2] DONE t=X wr+%d rd+%d stall=%d" → 恢复 SEQ
  'S' = 恢复 SEQ；'I' = ID/计数快照

判据（契约 §4.1/§4.2 由本脚本判, 不采信 C 的自评）:
  [B2-M] J3: 逆序对>0 + 逐帧槽位严格对应 + 到达序=命令序
             J3': 集合相等 0 缺/0 多/逐字节一致; 计数 wr+256 rd+256
  [B2-A] 恰缺 1 帧(=帧#100); rd+255
  [B2-B] 命令 257 实收 256(重读槽无数据); 集合仍相等; rd+256

用法:
  set PYTHONUTF8=1
  python j3_soft_verify.py --mock              # 无板自检(M/A/B 三轮, 本地回环)
  python j3_soft_verify.py                     # 真机(需板卡+COM5+192.168.1.102)
  python j3_soft_verify.py --nslots 64         # 快速冒烟
  python j3_soft_verify.py --json-out b2.json --log b2.log
"""
from __future__ import annotations

import argparse
import json
import os
import queue
import socket
import sys
import threading
import time

# ---- 载荷编解码: 单一事实源 = prj10 已验证引擎 (只读 import, 原件不动) ----
J3_ENGINE = r"D:\FPGA\prj\project_10\prj_loop\scripts\j3_random_read.py"
sys.path.insert(0, os.path.dirname(J3_ENGINE))
from j3_random_read import build_payload, parse_payload, first_diff, inversion_count  # noqa: E402

BOARD_IP, BOARD_DATA_PORT = "192.168.1.10", 1234
PC_DATA_PORT = 1236
DEFAULT_COM = "COM5"
NSLOTS_MAX = 256
WARMUP_SETTLE_S = 0.6
DONE_DRAIN_S = 1.2          # C 打印 DONE 后再收 1.2s, 收尾迟到帧


def log(msg):
    print(msg, flush=True)


# ============================================================ 控制通道抽象
class UartCtl:
    """真机控制通道: COM5@9600 单字符命令 / 行回读。"""

    def __init__(self, com, baud=9600):
        import serial
        self.s = serial.Serial(com, baud, timeout=0.2)
        self.buf = b""

    def send_cmd(self, ch):
        self.s.write(ch.encode("ascii"))

    def read_line(self, timeout_s):
        t0 = time.time()
        while time.time() - t0 < timeout_s:
            d = self.s.read(256)
            if d:
                self.buf += d
                while b"\n" in self.buf:
                    line, self.buf = self.buf.split(b"\n", 1)
                    return line.strip(b"\r").decode("ascii", errors="replace")
        return None


class MockCtl:
    """Mock 控制通道: 命令经队列喂给 MockBridge 的协议线程(复刻 C 侧算法),
    行输出走另一条队列 —— 验证路径与真机完全一致。
    defect: 负向对照注入 ('order'=顺读, 破坏 J3; 其余见 MockBridge)"""

    def __init__(self, bridge, defect=None):
        self.tx = queue.Queue()      # PC -> mockC
        self.rx = queue.Queue()      # mockC -> PC (行)
        self.bridge = bridge
        self.defect = defect
        threading.Thread(target=self._c_twin, daemon=True).start()

    def send_cmd(self, ch):
        self.tx.put(ch)

    def read_line(self, timeout_s):
        try:
            return self.rx.get(timeout=timeout_s)
        except queue.Empty:
            return None

    # ---- mock 版 C 孪生: 逐行复刻 sw/src_j3/main.c 的 round_command/run_round ----
    def _c_twin(self):
        br = self.bridge
        go = self.tx.get          # 阻塞等首命令
        def emit(line):
            self.rx.put(line)
            time.sleep(0.001)     # 9600 波特节奏的极粗近似(仅让时序不塌缩)
        while True:
            c = go(block=True)
            if c not in ("M", "A", "B"):
                if c == "S":
                    br.set_mode(0)
                    emit("[B2] SEQRESTORED (cmd S)")
                elif c == "I":
                    emit("[B2] ID=%d wr=%d rd=%d drop=%d" %
                         (0x4231, br.wr & 0xffff, br.rd & 0xffff, 0))
                continue
            # 段0: SEQ 预热窗
            br.set_mode(0)
            emit("[B2] SEQOK t=%c" % c)
            c2 = go(block=True, timeout=30)
            if c2 != c:
                emit("[B2] GO-CHAR-MISMATCH")
                continue
            # 段1: RND + 稳定基线 (SET_MODE 的 +1 已被吸收 —— 与板上实征一致)
            br.set_mode(1)
            wr0, stable = br.watermark()[0], 0
            rd0 = br.watermark()[1]
            for _ in range(8):
                w2 = br.watermark()[0]
                stable = stable + 1 if w2 == wr0 else 0
                wr0 = w2
                rd0 = br.watermark()[1]
                if stable >= 2:
                    break
            emit("[B2] READY t=%c wr0=%d rd0=%d" % (c, wr0, rd0))
            # run_round
            n = NSLOTS_MAX
            skip = (wr0 + 100) % 256 if c == "A" else 0x100
            dup = (wr0 + 50) % 256 if c == "B" else 0x100
            emit("[B2] WRWAIT t=%c want+%d" % (c, n))
            for _ in range(10000):
                if (br.wr - wr0) & 0xffff >= n:
                    break
                time.sleep(0.001)
            if (br.wr - wr0) & 0xffff < n:
                emit("[B2] WAITWR-FAIL t=%c got+%d" % (c, (br.wr - wr0) & 0xffff))
                br.set_mode(0)
                emit("[B2] SEQRESTORED t=%c" % c)
                continue
            emit("[B2] WRDONE t=%c" % c)
            issued = 0
            for i in range(n):
                s = i if self.defect == "order" else (n - 1) - i   # 负向: 顺读=读序同写序
                if s == skip:
                    continue
                br.read_slot(s)
                issued += 1
                for _ in range(300):
                    if (br.rd - rd0) & 0xffff == issued:
                        break
                    time.sleep(0.001)
                else:
                    emit("[B2] STALL t=%c s=%d issued=%d" % (c, s, issued))
                    br.set_mode(0)
                    emit("[B2] SEQRESTORED t=%c" % c)
                    break
                if issued % 64 == 0:
                    emit("[B2] RD %d/256" % issued)
            else:
                if c == "B":
                    br.read_slot(dup)
                    for _ in range(120):
                        if (br.rd - rd0) & 0xffff != issued:
                            break
                        time.sleep(0.001)
                    if (br.rd - rd0) & 0xffff == issued:
                        emit("[B2] B-DUP-NODATA s=%d" % dup)
                    else:
                        emit("[B2] B-DUP-UNEXPECTED s=%d" % dup)
                        br.set_mode(0)               # 与 C 侧一致: 中止, 不发 DONE
                        emit("[B2] SEQRESTORED t=%c" % c)
                        continue
                w1, r1 = br.watermark()[0], br.watermark()[1]
                emit("[B2] DONE t=%c wr+%d rd+%d stall=0" %
                     (c, (w1 - wr0) & 0xffff, (r1 - rd0) & 0xffff))
            br.set_mode(0)
            emit("[B2] SEQRESTORED t=%c" % c)


# ============================================================ Mock 板卡(桥)
class MockBridge(threading.Thread):
    """复刻桥①语义: 写槽=帧计数 mod 256; SEQ 自动回显; RND 读完即退休;
    非法读无输出(ill). SET_MODE 使 u_wr_frame +1 (2026-10-11 板上实征).
    defect: 'byte'=读出内容翻转 1 字节(验 J3' 逐字节); 'noretire'=读完不退休
    (验负向 B 重读槽必须无输出)."""

    def __init__(self, listen, defect=None):
        super().__init__(daemon=True)
        self.mode = 0
        self.wr = 0
        self.rd = 0
        self.defect = defect
        self.slots = [None] * 256          # payload / None=空
        self.fresh = [False] * 256
        self.lock = threading.Lock()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(listen)
        self.pc_addr = None
        self.ill = 0

    def run(self):
        while True:
            data, addr = self.sock.recvfrom(2048)
            with self.lock:
                self.pc_addr = addr        # 回显目的 = 数据帧源(契约 §2.3)
                s = self.wr & 0xff
                self.slots[s] = data
                self.fresh[s] = True
                self.wr = (self.wr + 1) & 0xffff
                if self.mode == 0:
                    self.sock.sendto(data, addr)

    def set_mode(self, m):
        with self.lock:
            self.mode = m
            self.wr = (self.wr + 1) & 0xffff   # 板上实征: SET_MODE 占一个写计数

    def read_slot(self, s):
        with self.lock:
            if self.fresh[s]:
                payload = self.slots[s]
                if self.defect == "byte" and (self.rd & 0x0f) == 7:
                    payload = bytes([payload[8] ^ 0xFF]) + payload[9:]  # 负向: 破坏内容
                if self.defect != "noretire":                           # 负向: 不退休
                    self.fresh[s] = False
                self.rd = (self.rd + 1) & 0xffff
                if self.pc_addr:
                    self.sock.sendto(payload, self.pc_addr)
            else:
                self.ill += 1

    def watermark(self):
        with self.lock:
            return (self.wr, self.rd, 0)


# ============================================================ 数据面
class DataPlane:
    """真机: PC:1236 -> 板 192.168.1.10:1234。Mock: 由 MockBridge 直接回发。"""

    def __init__(self, mock_bridge=None):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", PC_DATA_PORT))
        self.sock.settimeout(0.05)
        self.mock = mock_bridge
        self.frames = []
        self.running = False
        self._th = None

    def start_rx(self):
        self.running = True
        self._th = threading.Thread(target=self._rx, daemon=True)
        self._th.start()

    def _rx(self):
        while self.running:
            try:
                data, _ = self.sock.recvfrom(2048)
                self.frames.append((time.time(), data))
            except socket.timeout:
                pass

    def send(self, payload, pace_s):
        self.sock.sendto(payload, (BOARD_IP, BOARD_DATA_PORT))
        if pace_s > 0:
            time.sleep(pace_s)

    def stop_and_drain(self, extra_s=DONE_DRAIN_S):
        time.sleep(extra_s)
        self.running = False
        if self._th:
            self._th.join(timeout=2)


def warmup_probe(dp):
    """SEQ 窗内 UDP 预热: 触发 ARP + 刷新 PC 邻居表(真机需要, mock 无害)。"""
    try:
        dp.sock.sendto(b"\x00" * 32, (BOARD_IP, BOARD_DATA_PORT))
    except OSError:
        pass
    time.sleep(WARMUP_SETTLE_S)
    dp.frames.clear()          # 预热回显丢弃(其计数已被基线吸收)


# ============================================================ 轮次与判据
def run_round(ctl, dp, rtype, nslots, size, pace_s, seq_base, round_id):
    """跑一轮 (M/A/B)。返回 (ok, stats dict)。判据全部由本函数独立推导。"""
    st = {"type": rtype, "ok": False, "errors": [], "warnings": [],
          "wr0": None, "n_expected": None, "missing": [], "extra": 0,
          "byte_diff": 0, "order_ok": True, "inv": 0,
          "wr_delta": None, "rd_delta": None, "dup_nodata": False,
          "seq_base": seq_base}

    log("-" * 72)
    log("[%s] 段0: 发送类型字符, 等 SEQOK (SEQ 预热窗)" % rtype)
    for _ in range(10):                      # 清上一轮残留行 (SEQRESTORED 等)
        if ctl.read_line(0.05) is None:
            break
    ctl.send_cmd(rtype)
    line = None
    for _ in range(30):                      # 等 SEQOK (跳过迟到杂行)
        line = ctl.read_line(0.1)
        if line and "SEQOK" in line:
            break
    if line is None or "SEQOK" not in line:
        st["errors"].append("未收到 SEQOK (last=%r)" % line)
        log("[%s] FAIL  <- %s" % (rtype, st["errors"][0]))
        return False, st
    warmup_probe(dp)

    log("[%s] GO: 等 READY (C 侧切 RND + 稳定基线)" % rtype)
    dp.start_rx()
    time.sleep(0.3)                          # 收掉 OS 缓冲里的预热回显再清
    dp.frames.clear()
    ctl.send_cmd(rtype)
    wr0 = None
    for _ in range(60):                       # READY 最多 12s (C 基线稳定流程)
        line = ctl.read_line(0.2)
        if line and "READY" in line and "wr0=" in line:
            try:
                wr0 = int(line.split("wr0=")[1].split()[0])
            except (ValueError, IndexError):
                pass
            break
        if line and ("WAITWR-FAIL" in line or "STALL" in line):
            st["errors"].append("提前失败行: %s" % line)
    if wr0 is None:
        st["errors"].append("未收到 READY/wr0 (last=%r)" % line)
        log("[%s] FAIL  <- %s" % (rtype, st["errors"][0]))
        dp.stop_and_drain(0.2)
        return False, st
    st["wr0"] = wr0

    # 写阶段: nslots 帧, seq = seq_base + k, k=0..n-1, 槽=(wr0+k) mod 256
    log("[%s] 写阶段: %d 帧 x %dB, pace %.1fms (RND 下应零回显)"
        % (rtype, nslots, size, pace_s * 1000))
    for k in range(nslots):
        dp.send(build_payload(seq_base + k, round_id, size), pace_s)

    # 读阶段: C 自动逆序读; 等到 DONE 行
    log("[%s] 读阶段: 等 C 逆序 RD_SLOT 完成行" % rtype)
    done_line = None
    for _ in range(6000):                     # 最多 20 分钟? 0.2s*6000; 实际远短
        line = ctl.read_line(0.2)
        if line is None:
            continue
        if line.startswith("[B2] DONE"):
            done_line = line
            break
        if "STALL" in line or "WAITWR-FAIL" in line or "B-DUP-UNEXPECTED" in line:
            st["errors"].append("C 侧失败行: %s" % line)
            break
        if "B-DUP-NODATA" in line:
            st["dup_nodata"] = True
    dp.stop_and_drain()
    if done_line is None:
        st["errors"].append("未收到 DONE")
        log("[%s] FAIL  <- %s" % (rtype, "; ".join(st["errors"][:3])))
        return False, st
    try:
        st["wr_delta"] = int(done_line.split("wr+")[1].split()[0])
        st["rd_delta"] = int(done_line.split("rd+")[1].split()[0])
    except (ValueError, IndexError):
        st["errors"].append("DONE 行解析失败: %s" % done_line)

    # ---- 判据推导 (与 C 的打印互不采信) ----
    skip = (wr0 + 100) % 256 if rtype == "A" else None
    dup = (wr0 + 50) % 256 if rtype == "B" else None
    order = [s for s in range(nslots - 1, -1, -1) if s != skip]
    n_cmd = len(order) + (1 if dup is not None else 0)
    st["n_expected"] = len(order)

    expect = []                               # 命令 i -> (slot, k, seq, payload)
    for i, s in enumerate(order):
        k = (s - wr0) % 256
        expect.append((s, k, seq_base + k, build_payload(seq_base + k, round_id, size)))

    frames = [d for _, d in dp.frames]
    if len(frames) != len(expect):
        st["errors"].append("实收 %d 帧 ≠ 期望 %d 帧" % (len(frames), len(expect)))

    got_k = []
    for i, (s, k, seq, payload) in enumerate(expect):
        if i >= len(frames):
            continue                        # 缺帧由集合级判决统一处理
        got = frames[i]
        g = parse_payload(got)
        if g is None:
            st["errors"].append("帧#%d 载荷非法(短帧 %dB)" % (i, len(got)))
            continue
        gseq, ground, gk16 = g
        if ground != round_id:
            st["errors"].append("帧#%d round=%d ≠ %d (跨轮污染)" % (i, ground, round_id))
        if gseq != seq or gk16 != (seq & 0xffff):
            st["order_ok"] = False
            st["errors"].append("帧#%d 到达序不符: 期望 seq=%d 实收 seq=%d (槽 %d)"
                                % (i, seq, gseq, s))
        d = first_diff(got, payload)
        if d >= 0:
            st["byte_diff"] += 1
            if st["byte_diff"] <= 3:
                st["errors"].append("帧#%d 首个字节差 @%d" % (i, d))
        got_k.append((gseq - seq_base) & 0xffff)   # 逆序对按**实收序**计量
    if len(frames) > len(expect):
        st["extra"] = len(frames) - len(expect)
        st["errors"].append("多收 %d 帧" % st["extra"])

    st["inv"] = inversion_count(got_k) if got_k else 0
    # ---- 集合级判决 (J3' / 负向): 实收 seq 集 == 全集 - 已知跳过帧 ----
    received_seqs = [parse_payload(f)[0] for f in frames if parse_payload(f)]
    got_set = set(received_seqs)
    if len(received_seqs) != len(got_set):
        st["errors"].append("重复帧: 实收 %d 帧仅 %d 个不同 seq"
                            % (len(received_seqs), len(got_set)))
    full = {seq_base + k for k in range(nslots)}     # 完整轮应可读出的全集
    st["missing"] = sorted(full - got_set)           # 负向A 期望 = 恰帧#100
    st["extra"] = len(got_set - full)

    # 各轮判据
    if rtype == "M":
        if st["inv"] <= 0:
            st["errors"].append("J3: 逆序对=%d, 读序=写序?" % st["inv"])
        if st["missing"] or st["extra"] or st["byte_diff"]:
            st["errors"].append("J3': 缺%d 多%d 字节差%d" %
                                (len(st["missing"]), st["extra"], st["byte_diff"]))
        if st["wr_delta"] is not None:
            if st["wr_delta"] < nslots:
                st["errors"].append("wr+%d < %d (写侧丢帧)" % (st["wr_delta"], nslots))
            elif st["wr_delta"] > nslots:
                st["warnings"].append("wr+%d > %d (多发, 非丢帧)" % (st["wr_delta"], nslots))
        if st["rd_delta"] != nslots:
            st["errors"].append("rd+%d ≠ %d" % (st["rd_delta"], nslots))
    elif rtype == "A":
        if len(st["missing"]) != 1 or (st["missing"] and st["missing"][0] != seq_base + 100):
            st["errors"].append("负向A: 缺帧 %r ≠ 恰帧#100" %
                                [m - seq_base for m in st["missing"]])
        if st["extra"] or st["byte_diff"]:
            st["errors"].append("负向A: 多%d 字节差%d" % (st["extra"], st["byte_diff"]))
        if st["rd_delta"] != nslots - 1:
            st["errors"].append("负向A: rd+%d ≠ %d" % (st["rd_delta"], nslots - 1))
    elif rtype == "B":
        if not st["dup_nodata"]:
            st["errors"].append("负向B: 未见 B-DUP-NODATA")
        if st["missing"] or st["extra"] or st["byte_diff"]:
            st["errors"].append("负向B: 集合不等 缺%d 多%d 字节差%d" %
                                (len(st["missing"]), st["extra"], st["byte_diff"]))
        if st["rd_delta"] != nslots:
            st["errors"].append("负向B: rd+%d ≠ %d (重读槽不应产出)" %
                                (st["rd_delta"], nslots))

    st["ok"] = not st["errors"]
    log("[%s] %s  wr+%s rd+%s inv=%d miss=%d extra=%d bytediff=%d%s" %
        (rtype, "PASS" if st["ok"] else "FAIL", st["wr_delta"], st["rd_delta"],
         st["inv"], len(st["missing"]), st["extra"], st["byte_diff"],
         "" if st["ok"] else "  <- " + "; ".join(st["errors"][:4])))
    return st["ok"], st


# ============================================================ main
def main(argv=None):
    p = argparse.ArgumentParser(description="prj11 B2 软核版 J3 引擎 (j3_soft 配套)")
    p.add_argument("--mock", action="store_true", help="无板自检 (Mock 板卡+回环)")
    p.add_argument("--mock-defect", choices=["byte", "order", "noretire"], default=None,
                   help="负向对照: 注入缺陷验判据非恒真 (byte=内容翻转/order=顺读/noretire=不退休)")
    p.add_argument("--com", default=DEFAULT_COM, help="真机串口 (默认 %s)" % DEFAULT_COM)
    p.add_argument("--nslots", type=int, default=256)
    p.add_argument("--size", type=int, default=64)
    p.add_argument("--pace-us", type=int, default=1000)
    p.add_argument("--rounds", default="MAB", help="轮次 (M/A/B 子集)")
    p.add_argument("--no-warmup", action="store_true")
    p.add_argument("--json-out", default=None)
    args = p.parse_args(argv)
    nslots = args.nslots

    results = {}
    mock_bridge = None
    if args.mock:
        # Mock: 桥监听回环 1234, 把 PC 数据口当回显目的 (pc_addr = 数据帧源)
        mock_bridge = MockBridge(("127.0.0.1", BOARD_DATA_PORT), defect=args.mock_defect)
        mock_bridge.start()
        ctl = MockCtl(mock_bridge, defect=args.mock_defect)
        global BOARD_IP                      # 数据面发往回环
        BOARD_IP = "127.0.0.1"
    else:
        ctl = UartCtl(args.com)
        ctl.send_cmd("S")                    # 起手恢复 SEQ
        time.sleep(0.3)
        ctl.send_cmd("I")
        line = ctl.read_line(2.0)
        log("板卡状态行: %s" % line)

    dp = DataPlane(mock_bridge)
    seq_base = 5000
    all_ok = True
    for i, rtype in enumerate(args.rounds):
        ok, st = run_round(ctl, dp, rtype, nslots, args.size,
                           args.pace_us / 1e6, seq_base, i + 1)
        results[rtype] = st
        all_ok &= ok
        seq_base += nslots

    log("=" * 72)
    log("[B2-SOFT-VERIFY] %s  (%s)" %
        ("PASS" if all_ok else "FAIL",
         "mock" if args.mock else "board COM=%s" % args.com))
    for rtype, st in results.items():
        log("  [%s] %s wr+=%s rd+=%s inv=%d miss=%s extra=%d bytediff=%d" %
            (rtype, "PASS" if st["ok"] else "FAIL", st["wr_delta"], st["rd_delta"],
             st["inv"], st["missing"][:4] if st["missing"] else "0",
             st["extra"], st["byte_diff"]))
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as f:
            json.dump({"ok": all_ok, "rounds": results}, f, ensure_ascii=False, indent=1)
        log("JSON: %s" % args.json_out)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
