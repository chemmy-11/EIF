@echo off
rem =============================================================================
rem build_p1.cmd -- prj12 P1 offline build chain (detached-friendly, ASCII, CRLF)
rem
rem Why .cmd:
rem   (1) on this host (measured 2026-10-24) win_bash dies when it runs cmd/vivado.bat;
rem   (2) the pwsh tool disappeared mid-session;
rem   (3) Vivado must run in an independent process tree, otherwise an upper-session
rem       interrupt kills the build (first attempt died exactly that way at 21:02).
rem
rem Why retries:
rem   pitfall #61 in PITFALLS.md -- the Vivado install disk occasionally fails to
rem   read files during long builds. Observed 2026-10-24 as:
rem     ERROR [Common 17-233] Error initializing slave interpreter '::ipgen_iptclns'
rem     CRITICAL WARNING [IP_Flow 19-1747] Failed to deliver file '.../rtlFiles.xit'
rem   prj11 wrapped its synth the same way (r3d_synth_retry.ps1, 4 tries).
rem
rem Stages:
rem   1) synth + ILA insertion              (3 attempts)
rem   2) impl with ExtraTimingOpt           (2 attempts for transient errors)
rem   3) impl with ExtraPostPlacementOpt    (reuse same dcp)
rem   4) fallback: re-synth without u_ila_6, then impl
rem Gates: only marker lines SYNTH_ONLY_DONE / IMPL_BUILD_OK count as success;
rem        IMPL_BUILD_TIMING_FAIL is deterministic -> no retry.
rem Progress: out\build_status.txt
rem Outputs: out\aurora_mem_bridge.bit + scripts\probes.ltx + out\rpt_impl_*.rpt
rem =============================================================================
setlocal
set ROOT=D:\FPGA\prj\project_12
set VIV=D:\Xilinx\Vivado\2023.1\bin\vivado.bat
set OUT=%ROOT%\out
set ST=%OUT%\build_status.txt
set TEMP=D:\FPGA\.tmp
set TMP=D:\FPGA\.tmp
rem round3d acceptance recipe: ILA4 skipped, ILA5 lite, ILA3 full
set R3C_SKIP_ILA4=1
set R3C_LITE_ILA5=1
set P12_SKIP_XSA=1
rem 2026-10-24 measured: OOC IP runs crash with "TclStackFree: incorrect freePtr"
rem right after "Launching helper process" when several run concurrently on this
rem 16GB host (6 of them crashed at -jobs 4). Serial/semi-serial is stable: the
rem single-run probe finished 100% at -jobs 1. Keep 2 as the default here.
set P12_SYNTH_JOBS=2
cd /d D:\FPGA

del /q "%OUT%\*.ok" 2>nul
echo [%DATE% %TIME%] BUILD_START > "%ST%"

call :SYNTH synth
if not exist "%OUT%\synth.ok" goto FAIL

set P12_PLACE_DIRECTIVE=ExtraTimingOpt
call :IMPL impl1
if exist "%OUT%\impl1.ok" goto DONE

set P12_PLACE_DIRECTIVE=ExtraPostPlacementOpt
call :IMPL impl2
if exist "%OUT%\impl2.ok" goto DONE

set P12_SKIP_ILA6=1
call :SYNTH synth_noila6
if not exist "%OUT%\synth_noila6.ok" goto FAIL
set P12_PLACE_DIRECTIVE=ExtraTimingOpt
call :IMPL impl3
if exist "%OUT%\impl3.ok" goto DONE
goto FAIL

:DONE
echo [%DATE% %TIME%] BUILD_DONE_OK >> "%ST%"
endlocal
exit /b 0

:FAIL
echo [%DATE% %TIME%] BUILD_FAILED >> "%ST%"
endlocal
exit /b 1

rem ============================ subroutines ============================
:SYNTH
del /q "%OUT%\%~1.ok" 2>nul
set /a SYNTH_TRY=0
:SYNTH_LOOP
set /a SYNTH_TRY+=1
echo [%DATE% %TIME%] SYNTH_START %~1 try=%SYNTH_TRY% >> "%ST%"
call "%VIV%" -mode batch -source "%ROOT%\scripts\build_synth_only.tcl" -notrace -log "%OUT%\%~1.log" -journal "%OUT%\%~1.jou" > "%OUT%\%~1.console.log" 2>&1
findstr /C:"SYNTH_ONLY_DONE" "%OUT%\%~1.console.log" >nul 2>&1
if not errorlevel 1 goto SYNTH_OK
echo [%DATE% %TIME%] SYNTH_FAIL %~1 try=%SYNTH_TRY% >> "%ST%"
if %SYNTH_TRY% GEQ 3 exit /b 1
echo [%DATE% %TIME%] SYNTH_RETRY %~1 >> "%ST%"
timeout /t 5 /nobreak >nul
goto SYNTH_LOOP
:SYNTH_OK
echo ok > "%OUT%\%~1.ok"
echo [%DATE% %TIME%] SYNTH_OK %~1 try=%SYNTH_TRY% >> "%ST%"
exit /b 0

:IMPL
del /q "%OUT%\%~1.ok" 2>nul
set /a IMPL_TRY=0
:IMPL_LOOP
set /a IMPL_TRY+=1
echo [%DATE% %TIME%] IMPL_START %~1 directive=%P12_PLACE_DIRECTIVE% try=%IMPL_TRY% >> "%ST%"
call "%VIV%" -mode batch -source "%ROOT%\scripts\build_impl.tcl" -notrace -log "%OUT%\%~1.log" -journal "%OUT%\%~1.jou" > "%OUT%\%~1.console.log" 2>&1
findstr /C:"IMPL_BUILD_OK" "%OUT%\%~1.console.log" >nul 2>&1
if not errorlevel 1 goto IMPL_OK
findstr /C:"IMPL_BUILD_TIMING_FAIL" "%OUT%\%~1.console.log" >nul 2>&1
if not errorlevel 1 goto IMPL_TIMINGFAIL
echo [%DATE% %TIME%] IMPL_FAIL %~1 try=%IMPL_TRY% >> "%ST%"
if %IMPL_TRY% GEQ 2 exit /b 1
echo [%DATE% %TIME%] IMPL_RETRY %~1 >> "%ST%"
timeout /t 5 /nobreak >nul
goto IMPL_LOOP
:IMPL_OK
echo ok > "%OUT%\%~1.ok"
echo [%DATE% %TIME%] IMPL_OK %~1 try=%IMPL_TRY% >> "%ST%"
exit /b 0
:IMPL_TIMINGFAIL
echo [%DATE% %TIME%] IMPL_TIMING_FAIL %~1 >> "%ST%"
exit /b 1
