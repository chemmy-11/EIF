@echo off
REM ===========================================================================
REM run_lat_sweep.bat -- prj11 B3-0 latency counter sweep (reuses mem_bridge_tb)
REM Sweeps (AR_LAT, W_DLY) = (8,0) (8,5) (8,12) (200,0); W2 verdict must PASS
REM in every point and LAT_MEAS deltas must equal the parameter steps.
REM ===========================================================================
setlocal
set VIV=D:\Xilinx\Vivado\2023.1\bin
cd /d "%~dp0"

if exist xsim.dir rmdir /s /q xsim.dir
del /q lat_sweep.log 2>nul
echo === B3-0 latency sweep %DATE% %TIME% === > lat_sweep.log

call "%VIV%\xvlog.bat" -sv ..\rtl\async_fifo.v ..\rtl\axi4_master_bridge.v ..\rtl\frame_mem_if.v axi4_ram_model.v mem_bridge_tb.sv >> lat_sweep.log 2>&1
if errorlevel 1 ( echo XVLOG_FAIL & findstr /C:"ERROR" lat_sweep.log & exit /b 1 )

set RC=0
for %%P in ("8 0" "8 5" "8 12" "200 0") do (
  for /f "tokens=1,2" %%a in (%%P) do (
    call "%VIV%\xelab.bat" -debug typical mem_bridge_tb -s lat_sw_%%a_%%b -generic_top "AR_LAT_T=%%a" -generic_top "W_DLY_T=%%b" -generic_top "STALL_EN_T=0" >> lat_sweep.log 2>&1
    if errorlevel 1 ( echo XELAB_FAIL_%%a_%%b & exit /b 1 )
    call "%VIV%\xsim.bat" lat_sw_%%a_%%b -runall >> lat_sweep.log 2>&1
    if errorlevel 1 set RC=1
  )
)

set PY=C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe
set PYTHONUTF8=1
%PY% check_lat_sweep.py lat_sweep.log
if errorlevel 1 set RC=1
exit /b %RC%
