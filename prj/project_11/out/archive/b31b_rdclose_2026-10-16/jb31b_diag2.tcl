# 诊断2: DMA 状态 (DMACR/DMASR/SA/LENGTH) + 引擎位
connect
targets 3
after 300
puts "DMACR(0x00)  = [format %08x [mrd -value 0x44A10000]]"
puts "DMASR(0x04)  = [format %08x [mrd -value 0x44A10004]]"
puts "DMA_SA(0x18) = [format %08x [mrd -value 0x44A10018]]"
puts "DMA_LEN(0x28)= [format %08x [mrd -value 0x44A10028]]"
puts "ENGINE(0x0C) = [format %08x [mrd -value 0x44A0000C]]"
puts "DMAREQ(0x34) = [format %08x [mrd -value 0x44A00034]]"
puts "------------ 等待 3s 后再读一次 DMASR/DMAREQ ------------"
after 3000
puts "DMASR(0x04)  = [format %08x [mrd -value 0x44A10004]]"
puts "DMAREQ(0x34) = [format %08x [mrd -value 0x44A00034]]"
disconnect
exit
