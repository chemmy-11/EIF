# -*- coding: utf-8 -*-
"""R2 round2 时序攻坚: 裁 ILA 探针集 (保留 S0–S11 判据必需探针), 同时改两个构建脚本.
用法: python r2_ila_trim.py [--apply]   (默认 dry-run 只打印 anchor 命中数)
保留:
  ILA0@user(probe0): 桥① user 计数(u_wr/u_rd/u_drop/rden/ost_s) + 桥② user(u_wr/u_rd) + s2mm reqpend/fault
  ILA0 probe1: 发射字节流 (S8c, 9 nets) 不变
  ILA3@ui(probe0): calib + mem wm/wr_frm/rd_frm/ost + mem2 wm/wr_frm/rd_frm/ost + s2mm state/tvalid/tready
                   (drop: mem stall/len_err/bresp/wslot/rslot 共 64b; 保留 stall/len_err 供 S10 错误硬判?)
  本脚本版本: 保留 stall/len_err (S10 硬判需要), 仅 drop bresp(16)+wslot(8)+rslot(8) = 32b
移除: ILA1@eth_rxc 整核 (111b), ILA2@user_clk_b 整核 (101b)  —— R2 S0–S11 判据不使用
"""
import io, sys

FILES = [r"D:\FPGA\prj\project_11\scripts\build_synth_only.tcl",
         r"D:\FPGA\prj\project_11\scripts\build_debug.tcl"]
APPLY = "--apply" in sys.argv

NETS0_NEW = '''set nets0 {}
# ★2026-10-18 (R2 round2 时序攻坚): ILA0 只保留 R2 板验判据必需项 (省资源/布线余量)
#   S6/S10(user 侧): 桥① u_wr/u_rd/u_drop/rden/ost_s + 桥② u_wr/u_rd;
#   S2MM 写引擎: reqpend/fault;   probe1 发射字节流 (S8c) 保留不变.
foreach n [bus_nets dbg_mem_u_wr   16] { lappend nets0 $n }
foreach n [bus_nets dbg_mem_u_rd   16] { lappend nets0 $n }
foreach n [bus_nets dbg_mem_u_drop 16] { lappend nets0 $n }
lappend nets0 [one_net dbg_mem_rden]
foreach n [bus_nets dbg_mem_ost_s   9] { lappend nets0 $n }
foreach n [bus_nets dbg_mem2_u_wr  16] { lappend nets0 $n }
foreach n [bus_nets dbg_mem2_u_rd  16] { lappend nets0 $n }
lappend nets0 [one_net dbg_s2mm_reqpend]
lappend nets0 [one_net dbg_wr_fault]
'''

ILA3_DROP = '''foreach n [bus_nets dbg_mem_bresp   16] { lappend nets3 $n }
'''
ILA3_DROP2 = '''foreach n [bus_nets dbg_mem_wslot    8] { lappend nets3 $n }
foreach n [bus_nets dbg_mem_rslot    8] { lappend nets3 $n }
'''

rc = 0
for path in FILES:
    s = io.open(path, "r", encoding="utf-8").read()
    n0 = s.count("set nets0 {}")
    n_ila1 = s.count("# ============ ILA1 @ eth_rxc")
    n_ila2 = s.count("# ============ ILA2 @ user_clk_b")
    n_ila3 = s.count("# ============ ILA3 @ ui_clk")
    n_bresp = s.count(ILA3_DROP)
    n_ws = s.count(ILA3_DROP2)
    print("%s: nets0=%d ila1=%d ila2=%d ila3=%d bresp=%d wslot_rslot=%d" %
          (path.split("\\")[-1], n0, n_ila1, n_ila2, n_ila3, n_bresp, n_ws))
    if not (n0 == 1 and n_ila1 == 1 and n_ila2 == 1 and n_ila3 == 1 and n_bresp == 1 and n_ws == 1):
        print("  !! anchor mismatch, skip")
        rc = 1
        continue
    # 1) nets0
    i = s.index("set nets0 {}")
    j = s.index("connect_debug_port u_ila_0/probe0 $nets0")
    s = s[:i] + NETS0_NEW + s[j:]
    # 2) 删除 ILA1 块
    i = s.index("# ============ ILA1 @ eth_rxc")
    j = s.index("# ============ ILA2 @ user_clk_b")
    s = s[:i] + ("# ★2026-10-18 (R2 round2): ILA1@eth_rxc 整核移除 (R2 S0–S11 判据不使用, 省资源/布线; 原 prj9 eth 域探针仅 prj9 判据用)\n\n") + s[j:]
    # 3) 删除 ILA2 块
    i = s.index("# ============ ILA2 @ user_clk_b")
    j = s.index("# ============ ILA3 @ ui_clk")
    s = s[:i] + ("# ★2026-10-18 (R2 round2): ILA2@user_clk_b 整核移除 (B 通道; R2 S0–S11 判据不使用)\n\n") + s[j:]
    # 4) ILA3 裁 bresp/wslot/rslot
    s = s.replace(ILA3_DROP, "# ★2026-10-18 round2 裁: dbg_mem_bresp (S2MM 下恒 0, INFO) 不挂\n")
    s = s.replace(ILA3_DROP2, "# ★2026-10-18 round2 裁: wslot/rslot (调试用) 不挂\n")
    if APPLY:
        io.open(path, "w", encoding="utf-8", newline="\n").write(s)
        print("  APPLIED")
    else:
        print("  dry-run OK (not written)")
print("RESULT:", "OK" if rc == 0 else "FAIL")
sys.exit(rc)
