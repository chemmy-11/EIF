@echo off
REM run_sink_tb.bat -- prj11 B3-1a dma_sink unit regression (ASCII only)
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
cd /d "%~dp0"
if exist xsim_sink.dir rmdir /s /q xsim_sink.dir
del /q sink_run.log 2>nul
echo === sink sim %DATE% %TIME% === > sink_run.log
call "%VIV%\xvlog.bat" -sv ..\rtl\dma_sink.v sink_tb.sv >> sink_run.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL & findstr /C:"ERROR" sink_run.log & exit /b 1 )
call "%VIV%\xelab.bat" -debug typical sink_tb -s sink_sim >> sink_run.log 2>&1
if errorlevel 1 ( echo XELAB_FAIL & exit /b 1 )
call "%VIV%\xsim.bat" sink_sim -runall >> sink_run.log 2>&1
findstr /C:"SINK_TB:" /C:"[K1]" /C:"[K2]" /C:"[K4]" /C:"[FAIL]" sink_run.log
exit /b 0
