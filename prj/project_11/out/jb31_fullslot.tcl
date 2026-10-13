# J_B3-1 判别11: DMA 整槽读 (SA=slot base 4KB对齐, LEN=4096) 看 q1 是否=CAFEBABE
connect
set mbid 3
targets $mbid
after 300
proc dmaread {sa len} {
    mwr 0x44A10000 0x4
    after 5
    mwr 0x44A10000 0x1
    after 5
    mwr 0x44A10018 $sa
    after 5
    mwr 0x44A10028 $len
    set k 0
    while {$k < 200} {
        set sr [mrd -value 0x44A10004]
        if {[expr {$sr & 0x2}] != 0} { break }
        after 5
        incr k
    }
    after 10
    set t0 [mrd -value 0x44A0002C]
    set q1 [mrd -value 0x44A0002C]
    set u0 [mrd -value 0x44A00028]
    set q0 [mrd -value 0x44A00028]
    return [list $q0 $q1]
}
set slot 111
set base [expr {0x00100000 + $slot*4096}]
puts "slot=$slot base=[format 0x%08x $base]"
set r [dmaread [format "0x%08x" $base] 4096]
puts "full-slot 4096: q0=[lindex $r 0] q1=[format 0x%08x [lindex $r 1]]"
# also len=512 at exact 4KB-aligned base
set r2 [dmaread [format "0x%08x" $base] 512]
puts "base+0 len=512: q0=[lindex $r2 0] q1=[format 0x%08x [lindex $r2 1]]"
disconnect
exit
