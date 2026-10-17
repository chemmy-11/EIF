@echo off
setlocal EnableExtensions
rem ---------------------------------------------------------------------------
rem jb31b_rdcap2_send.bat - inner step, executed by jb31b_rdcap2.tcl via exec
rem INSIDE the armed ILA window. Keep it fast and do NOT send 'd' here:
rem the engine switch belongs to the pre-arm warm step.
rem ASCII only (cmd reads this file with the host ANSI codepage).
rem ---------------------------------------------------------------------------
set PYTHONHOME=
set PYTHONPATH=
set PYTHONUTF8=1
set PY=C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe
set ROOT=D:\FPGA\prj\project_11\out
set EVID=%ROOT%\evidence_2026-10-17
set MODE=%RDCAP_SEND_MODE%
if "%MODE%"=="" set MODE=retired
if not exist "%EVID%" mkdir "%EVID%"
"%PY%" "%ROOT%\jb31b_rdcap2_send.py" --mode %MODE% >> "%EVID%\rdcap2_send_bat_%MODE%.log" 2>&1
exit /b 0
