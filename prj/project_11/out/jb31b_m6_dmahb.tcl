# M6: 连续快采样 DMASR/DMACR —— 看软核是否在反复重编程 DMA(幻影 sticky 的行为指纹)
connect
targets 3
after 200
# 不 stop, 连续读 12 次, 间隔 ~100ms
for {set i 0} {$i < 12} {incr i} {
    set sr [mrd -value 0x44A10004]
    set cr [mrd -value 0x44A10000]
    puts "t$i SR=[format %08x $sr] CR=[format %08x $cr]"
    after 100
}
disconnect
exit
