# r2_fix_neg_patch.py -- 从「审计修复副本」生成 2 个负向缺陷副本（用于验证
# 修复后负向对照仍按设计 FAIL；不动 rtl/，产物在 sim/r2_fix_neg_*）
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'r2_fix_check', 'axi4_master_bridge.v')
if not os.path.exists(SRC):
    print('FATAL: fix copy missing:', SRC)
    sys.exit(1)
src = open(SRC, encoding='utf-8').read()

# defect 1: 被拒帧不推进槽游标
anchor = 'wr_last_slot_r  <= wd_slot_next;'
i = src.find(anchor)
assert i > 0, 'cursor anchor'
j = src.find("wr_slot_ptr <= wr_slot_ptr + 16'd1;", i)
assert j > 0, 'cursor target'
cur = src[:j] + "wr_slot_ptr <= (wd_noroom_n | wd_badlen_n) ? wr_slot_ptr : (wr_slot_ptr + 16'd1);" + \
      src[j + len("wr_slot_ptr <= wr_slot_ptr + 16'd1;"):]

# defect 2: 尾拍 TKEEP 用满 64 lane
pat = re.compile(r"wd_keep_r\[wd_bi\]\s*<=\s*1'b1;")
assert len(pat.findall(src)) == 1, 'tkeep anchor not unique'
tk = pat.sub("wd_keep_r <= {64{1'b1}};", src)

for name, txt in (('r2_fix_neg_cursor', cur), ('r2_fix_neg_tkeep', tk)):
    d = os.path.join(HERE, name)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'axi4_master_bridge.v'), 'w', encoding='utf-8', newline='\n').write(txt)
    print('written', os.path.join(d, 'axi4_master_bridge.v'))
