# -*- coding: utf-8 -*-
"""jb31b_rdcap2_cmp.py -- 从两份 ILA CSV 重建「发射字节流」并逐字节比对。

用法:
  py jb31b_rdcap2_cmp.py A.csv B.csv [--expect-prefix 55*7+D5] [--expect-len 1526]
                         [--mask 26-27,30-33,1522-1525] [--mask-volatile]

判据:
  退出码 0 = 同构(无差异)；1 = 有差异(含 expect-prefix/expect-len 不满足)；2 = 解析失败。
  给 --mask / --mask-volatile 时，"同构"按掩码后的差异集判定，同时仍打印严格差异集。

口径(与 10-16 out\\jb31b_rdcap_analyze.py 一致):
  mem_rden==1 的采样行取 mem_rd_data[7:0] 为一个发射字节，按采样顺序串成字节流。
  CSV 的 Radix 行决定 mem_rd_data 列的进制(HEX/DECIMAL/BINARY)，不硬编码。

掩码说明(--mask-volatile，仅对「8B 前导 + ETH14 + IP20 + UDP8 + payload + FCS4」布局成立):
  26-27 = IPv4 ID(板上协议栈每帧自增) · 32-33 = IPv4 头校验和(随 ID 变) · 末 4 字节 = FCS。
  这三处对「同一次取证的两个不同帧」必然不同，属正常口径，不是缺陷；
  其余字节(含 TTL/协议/长度/端口/payload)一律不掩，仍逐字节判。
"""
import argparse
import csv
import re
import sys

TAG_A = "A"
TAG_B = "B"


def die(msg):
    sys.stderr.write("CMP_PARSE_FAIL: %s\n" % msg)
    return 2


def col_pick(hdr, exact, sub):
    """优先精确列名，退化为子串匹配；返回下标或 None。"""
    for want in exact:
        for i, h in enumerate(hdr):
            if h == want:
                return i
    for i, h in enumerate(hdr):
        if sub in h:
            return i
    return None


def parse_radix_row(row, idx):
    """从 'Radix - UNSIGNED,UNSIGNED,...' 行取第 idx 列的进制名。"""
    if not row or not row[0].strip().lower().startswith("radix"):
        return None
    if idx >= len(row):
        return None
    return row[idx].strip().upper()


def to_byte(text, radix):
    v = text.strip()
    if v == "":
        raise ValueError("empty")
    if v.upper().startswith("0X"):
        v = v[2:]
        radix = "HEX"
    if radix == "DECIMAL" or radix == "UNSIGNED" or radix == "SIGNED":
        return int(v, 10) & 0xFF
    if radix == "BINARY":
        return int(v, 2) & 0xFF
    return int(v, 16) & 0xFF


def load_stream(path):
    """返回 dict(len, bytes, en_col, data_col, radix, samples, ones, head_rows)."""
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
        rows = list(csv.reader(f))
    if len(rows) < 2:
        raise ValueError("csv has no data rows")
    hdr = [h.strip() for h in rows[0]]
    i_en = col_pick(hdr, ("dbg_mem_rden",), "mem_rden")
    i_dt = col_pick(hdr, ("mem_rd_data[7:0]", "mem_rd_data"), "mem_rd_data")
    if i_en is None or i_dt is None:
        raise ValueError("columns not found: en=%s data=%s" % (i_en, i_dt))
    radix = None
    body = rows[1:]
    if body and parse_radix_row(body[0], i_dt):
        radix = parse_radix_row(body[0], i_dt)
        body = body[1:]
    if radix is None:
        radix = "HEX"
    out = []
    samples = 0
    bad = 0
    for r in body:
        if len(r) <= max(i_en, i_dt):
            continue
        samples += 1
        if r[i_en].strip() not in ("1", "1'b1"):
            continue
        try:
            out.append(to_byte(r[i_dt], radix))
        except ValueError:
            bad += 1
    return {
        "path": path,
        "bytes": out,
        "en_col": hdr[i_en],
        "data_col": hdr[i_dt],
        "radix": radix,
        "samples": samples,
        "bad": bad,
        "ncols": len(hdr),
    }


def hx(seq, limit=None):
    if limit is not None:
        seq = seq[:limit]
    return " ".join("%02x" % b for b in seq)


def parse_pattern(spec):
    """'55*7+D5' / '55x7+D5' / '55555555555555D5' / '55 55 55 d5' -> bytes。"""
    s = spec.strip()
    if not s:
        return b""
    out = bytearray()
    if "+" not in s and " " not in s and "*" not in s and "x" not in s.lower():
        if len(s) % 2 or not re.fullmatch(r"[0-9a-fA-F]+", s):
            raise ValueError("bad pattern: %r" % spec)
        return bytes.fromhex(s)
    for tok in re.split(r"[+,]", s):
        tok = tok.strip()
        if not tok:
            continue
        m = re.fullmatch(r"([0-9a-fA-F]{1,2})\s*[*xX]\s*(\d+)", tok)
        if m:
            out += bytes([int(m.group(1), 16)]) * int(m.group(2))
            continue
        m = re.fullmatch(r"([0-9a-fA-F]{1,2})", tok)
        if not m:
            raise ValueError("bad pattern token: %r" % tok)
        out.append(int(m.group(1), 16))
    return bytes(out)


def parse_mask(spec, n):
    """'-4' / '1522-1525' / '1522..1525' / '-4..-1' -> set(索引, 已正规化)。"""
    idx = set()
    for tok in spec.split(","):
        tok = tok.strip()
        if not tok:
            continue
        if ".." in tok:
            a, b = tok.split("..", 1)
        elif re.fullmatch(r"\d+-\d+", tok):
            a, b = tok.split("-", 1)
        else:
            a, b = tok, tok
        a, b = int(a), int(b)
        if a < 0:
            a += n
        if b < 0:
            b += n
        if a > b:
            a, b = b, a
        for i in range(a, b + 1):
            if 0 <= i < n:
                idx.add(i)
    return idx


def head_check(data, prefix):
    """返回 (ok, first_bad_index)。prefix 为空视为 ok。"""
    if not prefix:
        return True, None
    for i, p in enumerate(prefix):
        if i >= len(data):
            return False, i
        if data[i] != p:
            return False, i
    return True, None


def frame_sig(b):
    """给出一行帧签名诊断(以太网头 + IPv4 协议), 用于一眼看出抓错帧(如 ARP 请求)。"""
    if len(b) < 22:
        return "too short"
    dst = ":".join("%02x" % x for x in b[8:14]) if len(b) >= 14 else "?"
    src = ":".join("%02x" % x for x in b[14:20]) if len(b) >= 20 else "?"
    et = (b[20] << 8) | b[21] if len(b) >= 22 else -1
    name = {0x0800: "IPv4", 0x0806: "ARP", 0x86DD: "IPv6"}.get(et, "0x%04x" % (et & 0xFFFF))
    out = "dst=%s src=%s ethertype=%s" % (dst, src, name)
    if et == 0x0800 and len(b) >= 33:
        out += " ipproto=0x%02x(%s)" % (b[31], {17: "UDP", 1: "ICMP", 6: "TCP"}.get(b[31], "?"))
    if dst == "ff:ff:ff:ff:ff:ff":
        out += " BCAST"
    if et == 0x0806:
        out += " NOT_THE_TARGET"
    return out


def report_side(tag, info, prefix):
    b = info["bytes"]
    print("%s: file=%s" % (tag, info["path"]))
    print("%s: cols en=%s data=%s radix=%s samples=%d bytes=%d bad=%d"
          % (tag, info["en_col"], info["data_col"], info["radix"],
             info["samples"], len(b), info["bad"]))
    print("%s: head32 = %s" % (tag, hx(b, 32)))
    print("%s: tail16 = %s" % (tag, hx(b[-16:]) if b else "(empty)"))
    print("%s: SIG: %s" % (tag, frame_sig(b)))
    if prefix:
        ok, at = head_check(b, prefix)
        print("%s: expect-prefix(%d)=%s -> %s"
              % (tag, len(prefix), hx(prefix), "OK" if ok else "MISMATCH@%s" % at))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="compare two ILA CSV emitted-byte streams (order does not matter)")
    ap.add_argument("csv_a")
    ap.add_argument("csv_b")
    ap.add_argument("--expect-prefix", default=None,
                    help="e.g. 55*7+D5  (also accepts 55555555555555D5 or '55 55 .. d5')")
    ap.add_argument("--expect-len", type=int, default=None)
    ap.add_argument("--mask", default=None,
                    help="masked byte ranges, e.g. 26-27,30-33,1522-1525 (negative = from end)")
    ap.add_argument("--mask-volatile", action="store_true",
                    help="mask IP ID (26-27) + IP hdr checksum (32-33) + last 4B FCS")
    ap.add_argument("--ctx", type=int, default=8, help="context bytes around first diff")
    ap.add_argument("--max-diff", type=int, default=8, help="print at most N diff positions")
    a = ap.parse_args(argv)

    try:
        prefix = parse_pattern(a.expect_prefix) if a.expect_prefix else b""
    except ValueError as e:
        return die("bad --expect-prefix: %s" % e)

    infos = []
    for tag, path in ((TAG_A, a.csv_a), (TAG_B, a.csv_b)):
        try:
            infos.append(load_stream(path))
        except (OSError, ValueError) as e:
            return die("%s %s: %s" % (tag, path, e))
    ia, ib = infos
    ba, bb = ia["bytes"], ib["bytes"]

    print("=" * 78)
    for tag, info in ((TAG_A, ia), (TAG_B, ib)):
        report_side(tag, info, prefix)
        print("-" * 78)

    failed = False
    if a.expect_len is not None:
        if len(ba) != a.expect_len:
            print("LEN: A expect %d got %d -> MISMATCH" % (a.expect_len, len(ba)))
            failed = True
        if len(bb) != a.expect_len:
            print("LEN: B expect %d got %d -> MISMATCH" % (a.expect_len, len(bb)))
            failed = True
    if prefix:
        oka, ata = head_check(ba, prefix)
        okb, atb = head_check(bb, prefix)
        if not oka or not okb:
            failed = True

    n = min(len(ba), len(bb))
    diffs = [i for i in range(n) if ba[i] != bb[i]]
    len_ok = (len(ba) == len(bb))
    print("LEN: A=%d B=%d equal=%s" % (len(ba), len(bb), "YES" if len_ok else "NO"))
    if not len_ok:
        print("LEN: common prefix eval len=%d (tail of the longer stream ignored)"
              % n)

    print("STRICT: ndiff=%d first=%s" % (len(diffs), diffs[0] if diffs else "none"))
    for k, i in enumerate(diffs[:a.max_diff]):
        print("DIFF[%d]: pos=%d %s=%02x %s=%02x" % (k, i, TAG_A, ba[i], TAG_B, bb[i]))
    if len(diffs) > a.max_diff:
        print("DIFF: ... %d more positions suppressed" % (len(diffs) - a.max_diff))
    if diffs:
        lo = max(0, diffs[0] - a.ctx)
        hi = min(n, diffs[0] + a.ctx)
        print("CTX pos=%d [%d:%d]: %s=%s" % (diffs[0], lo, hi, TAG_A, hx(ba[lo:hi])))
        print("CTX pos=%d [%d:%d]: %s=%s" % (diffs[0], lo, hi, TAG_B, hx(bb[lo:hi])))

    mask_spec = a.mask
    if a.mask_volatile and mask_spec:
        mask_spec = mask_spec + ",26-27,32-33,-4..-1"
    elif a.mask_volatile:
        mask_spec = "26-27,32-33,-4..-1"
    masked = None
    if mask_spec:
        m = parse_mask(mask_spec, n)
        masked = [i for i in diffs if i not in m]
        print("MASK: spec=%s bytes_masked=%d ndiff_after_mask=%d first_after_mask=%s"
              % (mask_spec, len(m), len(masked),
                 masked[0] if masked else "none"))

    eff = masked if masked is not None else diffs
    isomorphic = (not eff) and len_ok and (not failed)
    print("VERDICT: ISOMORPHIC=%s basis=%s"
          % ("YES" if isomorphic else "NO", "masked" if masked is not None else "strict"))
    if not isomorphic:
        print("HINT: if the only diffs are IP ID/checksum/FCS, rerun with --mask-volatile")
    return 0 if isomorphic else 1


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass
    sys.exit(main())
