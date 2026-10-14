@echo off
REM ===========================================================================
REM run_dma_probe.bat -- prj11 B3-1b: DMA MM2S byte-mapping probe (xsim)
REM Elaborates the same-config IP sim netlist + probe TB; prints AR + first beat.
REM ASCII-only comments/echo (cmd.exe parses as CP936; see AGENTS #17).
REM ===========================================================================
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
set NET=D:\FPGA\prj\project_11\vivado\prj11.gen\sources_1\bd\mb_ctrl\ip\mb_ctrl_axi_dma_0_0_1\mb_ctrl_axi_dma_0_0_sim_netlist.v
cd /d "%~dp0"
if exist xsim_probe.dir rmdir /s /q xsim_probe.dir
del /q dma_probe_run.log 2>nul
echo === B3-1b DMA probe sim %DATE% %TIME% === > dma_probe_run.log

call "%VIV%\xvlog.bat" -sv "%NET%" dma_probe_tb.sv >> dma_probe_run.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL & findstr /C:"ERROR" dma_probe_run.log & exit /b 1 )

call "%VIV%\xelab.bat" -debug typical -L unisims_ver -L secureip mb_ctrl_axi_dma_0_0 glbl dma_probe_tb -s dma_probe >> dma_probe_run.log 2>&1
if errorlevel 1 ( echo XELAB_FAIL & findstr /C:"ERROR" dma_probe_run.log & exit /b 1 )

call "%VIV%\xsim.bat" dma_probe -runall >> dma_probe_run.log 2>&1
echo XSIM_EXIT=%ERRORLEVEL% >> dma_probe_run.log
findstr /C:"PROBE_DONE" /C:"AR addr" /C:"AXIS beat0" /C:"DMASR" /C:"MM2S:" dma_probe_run.log
