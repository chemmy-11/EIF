@echo off
REM ===========================================================================
REM run_r2_wr_tb.bat -- R2 (B3-2) S2MM write-path independent TB suite
REM   ASCII-only (cmd.exe parses as ANSI; AGENTS #17). CRLF line endings.
REM   Each run uses its own work dir and clears xsim.dir first (#48).
REM   positive : frozen RTL        -> expect "=== R2 WR TB: PASS"
REM   negative1: cursor defect     -> expect FAIL and "[FAIL-T4-CURSOR]"
REM   negative2: tail-TKEEP defect -> expect FAIL and "[FAIL-KEEP-MASK]"
REM   negatives compile with -d R2_FAST (skip T6 16.7M-cycle wait; same checks)
REM   summary: sim\r2_wr_run.log ; exit 0 = all three verdicts as designed
REM ===========================================================================
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
set PY=C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe
set SRC=%~dp0
set RT=%SRC%..\rtl
set LOG=%SRC%r2_wr_run.log
cd /d "%SRC%"
del /q "%LOG%" 2>nul
del /q "%SRC%r2_wr_pos.log" "%SRC%r2_wr_neg_cursor.log" "%SRC%r2_wr_neg_tkeep.log" 2>nul
echo === R2 WR TB suite %DATE% %TIME% === > "%LOG%"

echo [STEP] generate negative-control defect copies
set PYTHONUTF8=1
"%PY%" "%SRC%r2_neg_patch.py" >> "%LOG%" 2>&1
if errorlevel 1 goto patch_fail

set POSOK=0
set NEG1OK=0
set NEG2OK=0

REM ------------------------------ RUN1 positive ------------------------------
echo.
echo === [RUN1] positive: frozen RTL ===
if exist "%SRC%r2_work_pos" rmdir /s /q "%SRC%r2_work_pos"
mkdir "%SRC%r2_work_pos"
cd /d "%SRC%r2_work_pos"
if exist xsim.dir rmdir /s /q xsim.dir
call "%VIV%\xvlog.bat" -sv "%RT%\async_fifo.v" "%RT%\dma_rd_shim_v2.v" "%RT%\axi4_master_bridge.v" "%RT%\frame_mem_if.v" "%SRC%r2_wr_tb.sv" > "%SRC%r2_wr_pos.log" 2>&1
if errorlevel 1 goto run1_fail
call "%VIV%\xelab.bat" -debug typical r2_wr_tb -s r2_wr_sim >> "%SRC%r2_wr_pos.log" 2>&1
if errorlevel 1 goto run1_fail
call "%VIV%\xsim.bat" r2_wr_sim -runall >> "%SRC%r2_wr_pos.log" 2>&1
cd /d "%SRC%"
findstr /C:"=== R2 WR TB: PASS" "%SRC%r2_wr_pos.log" >nul
if not errorlevel 1 set POSOK=1
findstr /C:"=== R2 WR TB:" "%SRC%r2_wr_pos.log"
findstr /C:"[FAIL" "%SRC%r2_wr_pos.log"
goto run2

:run1_fail
cd /d "%SRC%"
echo XVLOG_OR_XELAB_FAIL_POS
findstr /C:"ERROR" "%SRC%r2_wr_pos.log"
goto summary

REM ------------------------------ RUN2 negative1 -----------------------------
:run2
echo.
echo === [RUN2] negative#1: cursor-not-advanced (expect FAIL-T4-CURSOR) ===
if exist "%SRC%r2_work_neg1" rmdir /s /q "%SRC%r2_work_neg1"
mkdir "%SRC%r2_work_neg1"
cd /d "%SRC%r2_work_neg1"
if exist xsim.dir rmdir /s /q xsim.dir
call "%VIV%\xvlog.bat" -sv -d R2_FAST -d R2_NEG_CURSOR "%RT%\async_fifo.v" "%RT%\dma_rd_shim_v2.v" "%SRC%r2_neg_cursor\axi4_master_bridge.v" "%RT%\frame_mem_if.v" "%SRC%r2_wr_tb.sv" > "%SRC%r2_wr_neg_cursor.log" 2>&1
if errorlevel 1 goto run2_fail
call "%VIV%\xelab.bat" -debug typical r2_wr_tb -s r2_wr_sim >> "%SRC%r2_wr_neg_cursor.log" 2>&1
if errorlevel 1 goto run2_fail
call "%VIV%\xsim.bat" r2_wr_sim -runall >> "%SRC%r2_wr_neg_cursor.log" 2>&1
cd /d "%SRC%"
findstr /C:"=== R2 WR TB: FAIL" "%SRC%r2_wr_neg_cursor.log" >nul
if errorlevel 1 goto run2_done
findstr /C:"[FAIL-T4-CURSOR]" "%SRC%r2_wr_neg_cursor.log" >nul
if not errorlevel 1 set NEG1OK=1
:run2_done
findstr /C:"=== R2 WR TB:" "%SRC%r2_wr_neg_cursor.log"
findstr /C:"[FAIL-T4-CURSOR]" "%SRC%r2_wr_neg_cursor.log"
goto run3

:run2_fail
cd /d "%SRC%"
echo XVLOG_OR_XELAB_FAIL_NEG1
findstr /C:"ERROR" "%SRC%r2_wr_neg_cursor.log"
goto summary

REM ------------------------------ RUN3 negative2 -----------------------------
:run3
echo.
echo === [RUN3] negative#2: tail-TKEEP-full-lane (expect FAIL-KEEP-MASK) ===
if exist "%SRC%r2_work_neg2" rmdir /s /q "%SRC%r2_work_neg2"
mkdir "%SRC%r2_work_neg2"
cd /d "%SRC%r2_work_neg2"
if exist xsim.dir rmdir /s /q xsim.dir
call "%VIV%\xvlog.bat" -sv -d R2_FAST -d R2_NEG_TKEEP "%RT%\async_fifo.v" "%RT%\dma_rd_shim_v2.v" "%SRC%r2_neg_tkeep\axi4_master_bridge.v" "%RT%\frame_mem_if.v" "%SRC%r2_wr_tb.sv" > "%SRC%r2_wr_neg_tkeep.log" 2>&1
if errorlevel 1 goto run3_fail
call "%VIV%\xelab.bat" -debug typical r2_wr_tb -s r2_wr_sim >> "%SRC%r2_wr_neg_tkeep.log" 2>&1
if errorlevel 1 goto run3_fail
call "%VIV%\xsim.bat" r2_wr_sim -runall >> "%SRC%r2_wr_neg_tkeep.log" 2>&1
cd /d "%SRC%"
findstr /C:"=== R2 WR TB: FAIL" "%SRC%r2_wr_neg_tkeep.log" >nul
if errorlevel 1 goto run3_done
findstr /C:"[FAIL-KEEP-MASK]" "%SRC%r2_wr_neg_tkeep.log" >nul
if not errorlevel 1 set NEG2OK=1
:run3_done
findstr /C:"=== R2 WR TB:" "%SRC%r2_wr_neg_tkeep.log"
findstr /C:"[FAIL-KEEP-MASK]" "%SRC%r2_wr_neg_tkeep.log"
goto summary

:run3_fail
cd /d "%SRC%"
echo XVLOG_OR_XELAB_FAIL_NEG2
findstr /C:"ERROR" "%SRC%r2_wr_neg_tkeep.log"
goto summary

:patch_fail
echo NEG_PATCH_FAIL
type "%LOG%"
exit /b 1

REM ------------------------------ SUMMARY -----------------------------------
:summary
echo.
echo === RUN SUMMARY === >> "%LOG%"
echo POS_PASS=%POSOK% NEG1_CURSOR_FAIL=%NEG1OK% NEG2_TKEEP_FAIL=%NEG2OK% >> "%LOG%"
echo POS_PASS=%POSOK% NEG1_CURSOR_FAIL=%NEG1OK% NEG2_TKEEP_FAIL=%NEG2OK%
if "%POSOK%%NEG1OK%%NEG2OK%"=="111" goto suite_pass
echo === R2 WR TB SUITE: FAIL ===
echo === R2 WR TB SUITE: FAIL === >> "%LOG%"
exit /b 1

:suite_pass
echo === R2 WR TB SUITE: PASS (positive PASS + 2 negative controls FAIL as designed) ===
echo === R2 WR TB SUITE: PASS === >> "%LOG%"
exit /b 0