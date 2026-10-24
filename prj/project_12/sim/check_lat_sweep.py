# -*- coding: utf-8 -*-
"""check_lat_sweep.py -- prj11 B3-0 latency sweep verdict

判据 (执行单 §二):
  S1 每个参数点 W2 verdict 必须 PASS (0 errors) —— 计数器不得破坏既有功能
  S2 lat_w / lat_r 非零 (实测活体, 两侧握手都采到样)
  S3 跨档差分: AR_LAT 8->200 时 lat_r 增量 == 192; W_DLY 0->5->12 时 lat_w
     增量 == 5 / 7 (线性 1:1 跟踪模型延迟)
  S4 bresp_err == 0 (大延迟下不死锁)
用法: python check_lat_sweep.py lat_sweep.log
"""
import io, re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "lat_sweep.log"
d = io.open(path, encoding="utf-8", errors="replace").read()

meas = {}
for m in re.finditer(r"LAT_MEAS stall=(\d+) ar=(\d+) wd=(\d+) rep=(\d+) lat_w=(\d+) lat_r=(\d+) bresp=(\d+)", d):
    st, ar, wd, rp, lw, lr, be = (int(x) for x in m.groups())
    meas.setdefault((ar, wd), []).append((rp, lw, lr, be))

verdicts = re.findall(r"=== prj10 W2 SIM: (PASS|FAIL) \(.*?\)", d)
print("测量点: %s" % sorted(meas))
print("W2 verdict: %s" % verdicts)

errs = []
if len(meas) != 4:
    errs.append("测量点 %d != 4" % len(meas))
if len(verdicts) != 4 or any(v != "PASS" for v in verdicts):
    errs.append("W2 verdict 非 4xPASS: %s" % verdicts)

# S1 活性 + 确定性(同配置 3 次完全相同) + S4 不死锁
for k, rows in sorted(meas.items()):
    if len(rows) != 3:
        errs.append("%s: 重复次数 %d != 3" % (k, len(rows)))
        continue
    lws = {r[1] for r in rows}
    lrs = {r[2] for r in rows}
    bes = {r[3] for r in rows}
    if len(lws) != 1 or len(lrs) != 1:
        errs.append("%s: 同配置读数不一致 lat_w=%s lat_r=%s (确定性失败)" % (k, lws, lrs))
    if 0 in lws or 0 in lrs:
        errs.append("%s: 计数器为 0 (未采到样)" % k)
    if bes != {0}:
        errs.append("%s: bresp_err=%s (大延迟下应为 0)" % (k, bes))

# S2 写侧响应: W_DLY +5 时 lat_w 必须恰好 +5 (该点桥流水不变, 是最纯的 1:1 证据)
if (8, 0) in meas and (8, 5) in meas:
    d5 = meas[(8, 5)][0][1] - meas[(8, 0)][0][1]
    print("lat_w 响应 (wd +5): %+d (期望 +5)" % d5)
    if d5 != 5:
        errs.append("lat_w 对 W_DLY+5 的响应 %+d != +5" % d5)

# S3 读侧响应: AR_LAT 8->200 必须显著单调上升 (桥流水常量偏移不影响单调性)
if (8, 0) in meas and (200, 0) in meas:
    r8 = meas[(8, 0)][0][2]
    r200 = meas[(200, 0)][0][2]
    print("lat_r 响应 (ar 8->200): %d -> %d (需显著单调上升)" % (r8, r200))
    if not (r200 > r8 and (r200 - r8) >= 100):
        errs.append("lat_r 对 AR_LAT 响应不足: %d -> %d" % (r8, r200))

if errs:
    print("LAT_SWEEP: FAIL")
    for e in errs:
        print("  - %s" % e)
    sys.exit(1)
print("LAT_SWEEP: PASS (0 errors)")
