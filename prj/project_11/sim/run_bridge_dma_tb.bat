@echo off
REM ===========================================================================
REM run_bridge_dma_tb.bat -- prj11 B3-1b dual-read-engine bridge integration TB
REM ASCII-only comments (cmd.exe parses this file as CP936; see AGENTS #17).
REM ===========================================================================
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
cd /d "%~dp0"
if exist xsim_bdma.dir rmdir /s /q xsim_bdma.dir
del /q bdma_run.log 2>nul
echo === B3-1b bridge dma-engine sim %DATE% %TIME% === > bdma_run.log

call "%VIV%\xvlog.bat" -sv ..\rtl\axi4_master_bridge.v ..\rtl\async_fifo.v ..\rtl\dma_rd_shim.v bridge_dma_tb.sv >> bdma_run.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL & findstr /C:"ERROR" bdma_run.log & exit /b 1 )
call "%VIV%\xelab.bat" -debug typical bridge_dma_tb -s bdma_sim >> bdma_run.log 2>&1
if errorlevel 1 ( echo XELAB_FAIL & exit /b 1 )
call "%VIV%\xsim.bat" bdma_sim -runall >> bdma_run.log 2>&1

findstr /C:"BRIDGE_DMA_TB:" /C:"[P1]" /C:"[P2]" /C:"[P3]" /C:"[FAIL]" bdma_run.log
exit /b 0
