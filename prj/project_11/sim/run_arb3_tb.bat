@echo off
REM ===========================================================================
REM run_arb3_tb.bat -- prj11 B3-1 axi_arb_3to1 unit regression (positive + negative)
REM Negative control: axi_arb_3to1_defect.v routes responses by bid/rid -> must FAIL.
REM Note: ASCII-only comments/echo (cmd.exe parses this file as CP936; see AGENTS #17).
REM ===========================================================================
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
cd /d "%~dp0"
if exist xsim_arb3.dir rmdir /s /q xsim_arb3.dir
del /q arb3_run.log 2>nul
echo === B3-1 arb3 sim %DATE% %TIME% === > arb3_run.log

echo [POS] axi_arb_3to1 >> arb3_run.log
call "%VIV%\xvlog.bat" -sv ..\rtl\axi_arb_3to1.v arb3_tb.sv >> arb3_run.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL_POS & findstr /C:"ERROR" arb3_run.log & exit /b 1 )
call "%VIV%\xelab.bat" -debug typical arb3_tb -s arb3_pos >> arb3_run.log 2>&1
if errorlevel 1 ( echo XELAB_FAIL_POS & exit /b 1 )
call "%VIV%\xsim.bat" arb3_pos -runall >> arb3_run.log 2>&1

echo [NEG] defect: route by ID >> arb3_run.log
if exist xsim.dir rmdir /s /q xsim.dir
call "%VIV%\xvlog.bat" -sv axi_arb_3to1_defect.v arb3_tb.sv >> arb3_run.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL_NEG & exit /b 1 )
call "%VIV%\xelab.bat" -debug typical arb3_tb -s arb3_neg >> arb3_run.log 2>&1
if errorlevel 1 ( echo XELAB_FAIL_NEG & exit /b 1 )
call "%VIV%\xsim.bat" arb3_neg -runall >> arb3_run.log 2>&1

findstr /C:"ARB3_TB:" /C:"[T1]" /C:"[T2]" /C:"[T3]" /C:"[FAIL]" arb3_run.log
exit /b 0
