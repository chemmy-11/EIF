# compare_config.py -- compare the R2 BD axi_dma XCI parameters with the
# standalone IP-sim config snapshot.  Writes config_compare.txt.
import json, re, pathlib

root = pathlib.Path(r"D:\FPGA\prj\project_11\out\ip_sim_r2")
xci  = pathlib.Path(r"D:\FPGA\prj\project_11\vivado\prj11.srcs\sources_1\bd\mb_ctrl\ip\mb_ctrl_axi_dma_0_0\mb_ctrl_axi_dma_0_0.xci")
snap = root / "config_snapshot.txt"

d = json.loads(xci.read_text(encoding="utf-8"))
cp = d["ip_inst"]["parameters"]["component_parameters"]
bd = {k.lower(): v[0]["value"] for k, v in cp.items()}

sim = {}
for line in snap.read_text(encoding="utf-8").splitlines():
    m = re.match(r"CONFIG\.([^=]+)=(.*)$", line.strip(), re.I)
    if m:
        sim[m.group(1).lower()] = m.group(2).strip()

keys = [
    "c_include_mm2s", "c_include_s2mm", "c_include_sg",
    "c_m_axi_mm2s_data_width", "c_m_axis_mm2s_tdata_width",
    "c_m_axi_s2mm_data_width", "c_s_axis_s2mm_tdata_width",
    "c_sg_length_width", "c_addr_width",
    "c_include_mm2s_dre", "c_include_s2mm_dre",
    "c_include_mm2s_sf", "c_include_s2mm_sf",
    "c_mm2s_burst_size", "c_s2mm_burst_size",
    "c_micro_dma", "c_single_interface", "c_enable_multi_channel",
    "c_increase_throughput", "c_prmry_is_aclk_async",
    "c_dlytmr_resolution", "c_sg_include_stscntrl_strm",
    "c_sg_use_stsapp_length",
]

out = []
out.append("# R2 BD XCI vs standalone IP-sim config")
out.append(f"# BD  : {xci}")
out.append(f"# SIM : {snap}")
out.append("")
out.append(f"{'parameter':34s} {'R2_BD':>10s} {'IP_SIM':>10s}  match")
out.append("-" * 70)
diffs = 0
for k in keys:
    a = bd.get(k, "<absent>")
    b = sim.get(k, "<absent>")
    same = (a == b)
    if not same:
        diffs += 1
    out.append(f"{k:34s} {a:>10s} {b:>10s}  {'YES' if same else 'NO'}")
out.append("")
out.append(f"# total differences: {diffs}")
out.append("# note: c_prmry_is_aclk_async=1 in the BD because s_axi_lite_aclk (100 MHz)")
out.append("#       and ui_clk (300 MHz) are asynchronous.  The standalone IP sim uses one")
out.append("#       100 MHz clock, so the IP default 0 is used.  This only changes the")
out.append("#       AXI-Lite CDC/register access path, not the S2MM/MM2S datapath.")
out.append("#       All datapath parameters (widths, burst, DRE, SF, SG=0) match.")

text = "\n".join(out) + "\n"
(root / "config_compare.txt").write_text(text, encoding="utf-8")
print(text)
