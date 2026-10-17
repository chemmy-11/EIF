connect
# 通用「位流 + ELF」烧写对: xsct jb31b_burn_pair.tcl <bit> <elf>
set bitfile [lindex $argv 0]
set elffile [lindex $argv 1]
puts "=== BURN PAIR ==="
puts "bit: $bitfile"
puts "elf: $elffile"
fpga $bitfile
after 3000
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
if {$id eq ""} { error "microblaze target id not found" }
targets $id
stop
after 300
dow $elffile
after 500
con
puts "PAIR_BURNED"
exit
