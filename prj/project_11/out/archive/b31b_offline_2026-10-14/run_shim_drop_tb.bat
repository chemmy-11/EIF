@echo off
REM ===========================================================================
REM run_shim_drop_tb.bat -- prj11 B3-1b dma_rd_shim leading-drop regression
REM ASCII-only comments (cmd.exe parses this file as CP936; see AGENTS #17).
REM ===========================================================================
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
cd /d "%~dp0"
if exist xsim_shim_drop.dir rmdir /s /q xsim_shim_drop.dir
del /q shim_drop_run.log 2>nul
echo === B3-1b shim drop sim %DATE% %TIME% === > shim_drop_run.log

call "%VIV%\xvlog.bat" -sv ..\rtl\dma_rd_shim.v shim_drop_tb.sv >> shim_drop_run.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL & findstr /C:"ERROR" shim_drop_run.log & exit /b 1 )
call "%VIV%\xelab.bat" -debug typical shim_drop_tb -s shim_drop_sim >> shim_drop_run.log 2>&1
if errorlevel 1 ( echo XELAB_FAIL & exit /b 1 )
call "%VIV%\xsim.bat" shim_drop_sim -runall >> shim_drop_run.log 2>&1

findstr /C:"SHIM_DROP_TB:" /C:"[D1]" /C:"[D2]" /C:"[D3]" /C:"[D4]" /C:"[FAIL]" shim_drop_run.log
exit /b 0
