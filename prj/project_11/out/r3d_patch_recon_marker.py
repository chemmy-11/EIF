# -*- coding: utf-8 -*-
"""Tool maintenance (2026-10-19): r2_counter_recon.py 'recon' mode did not emit the
R2_RECON_RESULT marker that out/r2_board.ps1 Invoke-ReconJudge parses (only the
'delta' mode did), so a genuine recon PASS was reported NOT_OBTAINED. This adds the
same marker to the recon path (no judgment logic change)."""
import io
import os
import shutil

P = r"D:\FPGA\prj\project_11\out\r2_counter_recon.py"
BAK = P + ".bak_20261019_recon_marker"
if not os.path.exists(BAK):
    shutil.copy2(P, BAK)

raw = io.open(P, "rb").read()
bom = raw.startswith(b"\xef\xbb\xbf")
if bom:
    raw = raw[3:]
s = raw.decode("utf-8", errors="replace")

old1 = '''        v, r, detail = judge_recon(cols, user_post_cols or user_pre_cols, label=label,
                                   require_r2_probes=args.require_r2_probes)
        print("R2_COUNTER_RECON: %s %s" % (v, r))'''
new1 = '''        v, r, detail = judge_recon(cols, user_post_cols or user_pre_cols, label=label,
                                   require_r2_probes=args.require_r2_probes)
        print("R2_COUNTER_RECON: %s %s" % (v, r))
        # ★2026-10-19 工具维护: delta 模式一直打印 R2_RECON_RESULT, recon 模式漏了;
        #   而 out/r2_board.ps1 的 Invoke-ReconJudge 只认 R2_RECON_RESULT => 真 PASS 被
        #   汇总成 NOT_OBTAINED。此处补齐标记 (判据逻辑不变)。
        print("R2_RECON_RESULT: %s" % v)'''
assert old1 in s, "recon emit block not found"
s = s.replace(old1, new1, 1)

old2 = '''            print("R2_COUNTER_RECON: NOT_OBTAINED " + msg)
            return 2
        label = "post" if ui_post_cols else "pre"'''
new2 = '''            print("R2_COUNTER_RECON: NOT_OBTAINED " + msg)
            print("R2_RECON_RESULT: NOT_OBTAINED")
            return 2
        label = "post" if ui_post_cols else "pre"'''
assert old2 in s, "recon not-obtained block not found"
s = s.replace(old2, new2, 1)

data = s.encode("utf-8")
if bom:
    data = b"\xef\xbb\xbf" + data
io.open(P + ".tmp", "wb").write(data)
os.replace(P + ".tmp", P)
print("PATCHED recon marker: bytes=", len(data), "bom=", data[:3].hex())
