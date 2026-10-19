# r3c_jtag_axi_probe_oneoff.tcl -- one-off rehearsal on wedged round3b board:
#   1) is the MicroBlaze CPU actually running (PC changes across con/stop)?
#   2) can the JTAG(MDM) AXI master still read lite_regs / axi_dma registers?
#      (distinguishes "CPU DP read path frozen" vs "slave/interconnect dead for all masters")
connect
set id ""
foreach line [split [targets] "\n"] {
    if {[regexp {^\s*(\d+)\s+MicroBlaze\s+#} $line -> n]} { set id $n; break }
}
targets $id
proc rd3 {addr} {
    if {[catch {
        mrd -value $addr
        mrd -value $addr
        set a [mrd -value $addr]
        mrd -value $addr
        set b [mrd -value $addr]
        return [format "%08x/%08x" $a $b]
    } emsg]} {
        return "ERR($emsg)"
    }
}
stop
after 200
puts "PC_stop1=[rrd pc]"
puts "ADDR 44A0001C LITE_ID   = [rd3 0x44A0001C]"
puts "ADDR 44A00018 LITE_STAT = [rd3 0x44A00018]"
puts "ADDR 44A00040 WR_REQ    = [rd3 0x44A00040]"
puts "ADDR 44A00044 WR_DBG    = [rd3 0x44A00044]"
puts "ADDR 44A10030 S2DMACR   = [rd3 0x44A10030]"
puts "ADDR 44A10034 S2DMASR   = [rd3 0x44A10034]"
puts "ADDR 44A10058 S2LENGTH  = [rd3 0x44A10058]"
puts "ADDR 44A10004 M2DMASR   = [rd3 0x44A10004]"
puts "ADDR 44A10028 M2LENGTH  = [rd3 0x44A10028]"
puts "ADDR 44A10000 M2DMACR   = [rd3 0x44A10000]"
con
after 1000
stop
after 100
puts "PC_stop2=[rrd pc]"
con
after 500
stop
after 100
puts "PC_stop3=[rrd pc]"
con
puts "JTAG_AXI_PROBE_DONE"
exit
