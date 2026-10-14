p = "main.c"
s = open(p, encoding="utf-8").read()
old = "                        if ((same >= 12u) && (d16(rd, rd0) == d16(wr, rd0))"
assert s.count(old) == 1, ("a", s.count(old))
new = "                        if ((same >= 600u) && (d16(rd, rd0) == d16(wr, rd0))"
s = s.replace(old, new)
old2 = "                            break;                  /* drained & stable & >=1 served:"
assert s.count(old2) == 1, ("b", s.count(old2))
new2 = "                            break;                  /* drained & >=1 served & idle ~2s:"
s = s.replace(old2, new2)
old3 = "                                                     * 帧走桥引擎 */"
assert s.count(old3) == 1
new3 = """                                                     * 帧走桥引擎; 12 次(~50ms) 短于
                                                     * 80ms 发帧间隔, 拉到 600(~2s) */"""
s = s.replace(old3, new3)
open(p, "w", encoding="utf-8", newline="\n").write(s)
print("OK")
