@echo off
setlocal EnableExtensions
rem ---------------------------------------------------------------------------
rem jb31b_rdcap2.bat - one-shot driver: pre-arm warm -> vivado batch capture ->
rem compare with the archived green reference.
rem PRECONDITIONS (manual, NOT done here):
rem   1. retired bitstream programmed and the soft-core ELF running
rem      (UART prints "  [B2-SOFT] WAITCMD (M/A/B/S/I/L/D/E/U)" )
rem   2. hw_server reachable: JTAG cable plugged, board powered
rem STEPS: 1) warm + quiescence  2) vivado tcl: arm -> exec send -> csv  3) cmp
rem ASCII only: cmd reads this file with the host ANSI codepage.
rem ---------------------------------------------------------------------------
set PYTHONHOME=
set PYTHONPATH=
set PYTHONUTF8=1
set PY=C:\Users\15266\AppData\Local\Python\pythoncore-3.14-64\python.exe
set ROOT=D:\FPGA\prj\project_11\out
set EVID=%ROOT%\evidence_2026-10-17
set VIVADO=D:\Xilinx\Vivado\2023.1\bin\vivado.bat

rem reference = archived green v5-RTL engine=1 stream of the 1472B payload frame
set REF=%ROOT%\archive\b31b_v5rtl_2026-10-16\jb31b_rdcap_e.csv
rem probes.ltx of the retired build; byte-identical to the v5-RTL probes.ltx
rem SHA256 352A5F283D229FB91398BEA49036FCFC130CD9988916F23A8257B3297C3A11A2
set LTX=%ROOT%\archive\b31b_retire_flag_2026-10-17\probes_0ecb8438.ltx

if "%RDCAP_SEND_MODE%"=="" set RDCAP_SEND_MODE=retired
set MODE=%RDCAP_SEND_MODE%

set RDCAP_LTX=%LTX%
set RDCAP_OUT=%EVID%\rdcap2_%MODE%.csv
set RDCAP_SEND_CMD=%ROOT%\jb31b_rdcap2_send.bat
set RDCAP_PRE_MS=500
set RDCAP_WAIT_S=60
set RDCAP_MODE=%MODE%
rem optional: AND mem_rd_data==0x55 into the trigger to force a preamble-aligned
rem head. Leave empty for the defect-blind first-emitted-byte trigger of 10-16.
set RDCAP_TRIG_DATA=

if not exist "%EVID%" mkdir "%EVID%"

echo [1/3] pre-arm warm + drain + quiescence check, mode=%MODE%
"%PY%" "%ROOT%\jb31b_rdcap2_warm.py" --send-d --require-dma --drain 2.0 --quiet-wait 6.0
set WARM_RC=%ERRORLEVEL%
if "%WARM_RC%"=="3" goto :no_dma
if "%WARM_RC%"=="4" echo [warn] WARM_QUIET=NO - a stray frame may hijack the trigger
if not "%WARM_RC%"=="0" if not "%WARM_RC%"=="4" echo [warn] warm exited rc=%WARM_RC%

echo [2/3] vivado batch capture: arm then send then upload then csv
call "%VIVADO%" -mode batch -source "%ROOT%\jb31b_rdcap2.tcl" -notrace -log "%EVID%\rdcap2_%MODE%_vivado.log" -journal "%EVID%\rdcap2_%MODE%_vivado.jou"
set VIV_RC=%ERRORLEVEL%
if not "%VIV_RC%"=="0" echo [warn] vivado batch rc=%VIV_RC% - check %EVID%\rdcap2_%MODE%_vivado.log
if not exist "%RDCAP_OUT%" echo [warn] csv not produced: %RDCAP_OUT%
if not exist "%RDCAP_OUT%" exit /b 5

echo [3/3] compare retired stream with the archived green reference
"%PY%" "%ROOT%\jb31b_rdcap2_cmp.py" "%REF%" "%RDCAP_OUT%" --expect-prefix 55*7+D5 --expect-len 1526 --mask-volatile > "%EVID%\rdcap2_cmp_%MODE%.log" 2>&1
set CMP_RC=%ERRORLEVEL%
type "%EVID%\rdcap2_cmp_%MODE%.log"
echo CMP_EXIT=%CMP_RC%
echo RDCAP2_ALL_DONE
exit /b 0

:no_dma
echo [abort] engine is not DMA - the retired bitstream has no read-out path
echo [abort] check COM port, the boot banner and the 'U mode=1' readback
exit /b 3
