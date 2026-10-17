#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""R2 快速静态检查: Verilog 模块实例端口名 vs 模块声明端口名一致性 (v2)。"""
import re, sys, io, os

ROOT = r"D:\FPGA\prj\project_11"

def read(p):
    with io.open(p, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    s = re.sub(r"//[^\n]*", " ", s)
    return s

def _names_in_segment(seg):
    seg = seg.strip().rstrip(",").strip()
    if not seg:
        return []
    seg = re.sub(r"^(?:input|output|inout)\b", " ", seg)
    out = []
    for part in seg.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\]\s*)*$", part)
        if m:
            out.append(m.group(1))
    return out

def module_ports(path, modname):
    s = strip_comments(read(path))
    m = re.search(r"\bmodule\s+" + re.escape(modname) + r"\b(.*?);", s, flags=re.S)
    if not m:
        return None
    body = m.group(1)
    names = []
    for line in body.split("\n"):
        line = line.strip()
        if not line:
            continue
        if re.match(r"^(?:input|output|inout)\b", line):
            segs = re.split(r"(?=\b(?:input|output|inout)\b)", line)
            for sg in segs:
                if re.match(r"^(?:input|output|inout)\b", sg.strip()):
                    names.extend(_names_in_segment(sg))
    if not names:
        # non-ANSI style: module m (a,b,c); -- take identifiers of the header list
        for m2 in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*", body):
            nm = m2.group(0)
            if nm not in ("input", "output", "inout", "wire", "reg", "signed", "unsigned"):
                names.append(nm)
    return names

def instance_conns(text, modname, instname=None):
    s = strip_comments(text)
    res = []
    pat = r"\b" + re.escape(modname) + r"\b\s*(?:#\s*\([^;]*?\)\s*)?([A-Za-z_][A-Za-z0-9_]*)\s*\("
    for m in re.finditer(pat, s, flags=re.S):
        inst = m.group(1)
        if inst in ("module", "begin", "end", "if", "else", "case"):
            continue
        if instname and inst != instname:
            continue
        i = m.end() - 1
        depth = 0
        j = i
        while j < len(s):
            if s[j] == "(":
                depth += 1
            elif s[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = s[i+1:j]
        conns = set(cm.group(1) for cm in re.finditer(r"\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", body))
        res.append({"inst": inst, "conns": conns})
    return res

def check(label, decl_path, modname, use_path, instname=None):
    ports = module_ports(decl_path, modname)
    if ports is None:
        print("[ERR] module %s not found in %s" % (modname, decl_path))
        return 1
    ports_set = set(ports)
    insts = instance_conns(read(use_path), modname, instname)
    if not insts:
        print("[ERR] no instance of %s in %s" % (modname, use_path))
        return 1
    bad = 0
    for it in insts:
        unknown = sorted(it["conns"] - ports_set)
        if unknown:
            bad += 1
            print("[FAIL] %s: instance %s connects unknown ports: %s" % (label, it["inst"], unknown))
        else:
            print("[ OK ] %s: instance %s (%d conns) match %s ports (%d)" % (
                label, it["inst"], len(it["conns"]), modname, len(ports_set)))
    return bad

def main():
    rc = 0
    wrapper = os.path.join(ROOT, r"vivado\prj11.gen\sources_1\bd\mb_ctrl\synth\mb_ctrl.v")
    top = os.path.join(ROOT, r"rtl\aurora_mem_bridge.v")
    rc += check("mb_ctrl", wrapper, "mb_ctrl", top, "u_mb_ctrl")
    fmi = os.path.join(ROOT, r"rtl\frame_mem_if.v")
    amb = os.path.join(ROOT, r"rtl\axi4_master_bridge.v")
    rc += check("frame_mem_if@u_mem", fmi, "frame_mem_if", top, "u_mem")
    rc += check("frame_mem_if@u_mem2", fmi, "frame_mem_if", top, "u_mem2")
    rc += check("axi4_master_bridge@frame_mem_if", amb, "axi4_master_bridge", fmi, "u_bridge")
    arb = os.path.join(ROOT, r"rtl\axi_arb_3to1.v")
    rc += check("axi_arb_3to1", arb, "axi_arb_3to1", top, "u_arb")
    ffi = os.path.join(ROOT, r"rtl\frame_fifo_pump.v")
    rc += check("frame_fifo_pump@u_pump_fwd", ffi, "frame_fifo_pump", top, "u_pump_fwd")
    print("---- RESULT: %s ----" % ("PASS" if rc == 0 else "FAIL(%d)" % rc))
    return 0 if rc == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
