@echo off
REM ===========================================================================
REM run_shim_tb.bat -- prj11 B3-1b dma_rd_shim unit regression
REM ASCII-only comments (cmd.exe parses this file as CP936; see AGENTS #17).
REM ===========================================================================
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
cd /d "%~dp0"
REM 10-15: shared work lib corrupted by an interrupted xvlog makes the next
REM        xvlog spin forever -> clear it first each run (seconds to recompile).
if exist xsim.dir rmdir /s /q xsim.dir
if exist xsim_shim.dir rmdir /s /q xsim_shim.dir
del /q shim_run.log 2>nul
echo === B3-1b shim sim %DATE% %TIME% === > shim_run.log

call "%VIV%\xvlog.bat" -sv ..\rtl\dma_rd_shim_v2.v shim_tb.sv >> shim_run.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL & findstr /C:"ERROR" shim_run.log & exit /b 1 )
call "%VIV%\xelab.bat" -debug typical shim_tb -s shim_sim >> shim_run.log 2>&1
if errorlevel 1 ( echo XELAB_FAIL & exit /b 1 )
call "%VIV%\xsim.bat" shim_sim -runall >> shim_run.log 2>&1

findstr /C:"SHIM_TB:" /C:"[S1]" /C:"[S2]" /C:"[S3]" /C:"[S4]" /C:"[NEG]" /C:"[FAIL]" shim_run.log
exit /b 0
