@echo off
rem =============================================================================
rem run_p2_tb.cmd -- prj12 P2 candidate unit simulation (xvlog/xelab/xsim)
rem Usage: cmd /c D:\FPGA\prj\project_12\p2_candidate\sim\run_p2_tb.cmd
rem Gate : each TB prints "<NAME>: PASS"; this script summarizes into result.txt
rem Note : independent of the Vivado project (no project lock), but prefer running
rem        outside synthesis/implementation peak hours.
rem =============================================================================
setlocal
set ROOT=D:\FPGA\prj\project_12\p2_candidate
set BIN=D:\Xilinx\Vivado\2023.1\bin
set TEMP=D:\FPGA\.tmp
set TMP=D:\FPGA\.tmp
cd /d %ROOT%
if exist xsim.dir rmdir /s /q xsim.dir
if exist xvlog.log del /q xvlog.log
if exist result.txt del /q result.txt

echo [%DATE% %TIME%] XVLOG >> result.txt
rem NOTE 2026-10-24: do NOT redirect xvlog output to "xvlog.log" -- xvlog itself
rem opens .\xvlog.log as its own log, so the shell redirect collides with it:
rem   CRITICAL WARNING [Common 17-183] Failed to open handle xvlog.log
rem and xvlog exits 0 having compiled NOTHING (errorlevel is useless here).
rem Gate on the produced library directory instead.
call "%BIN%\xvlog.bat" -sv -work work rtl\udp_payload_extract.v rtl\relay_tx.v rtl\local_steer.v sim\tb_relay_tx.sv sim\tb_udp_payload_extract.sv sim\tb_local_steer.sv > xvlog.console.log 2>&1
if not exist xsim.dir\work (
  echo XVLOG_FAIL >> result.txt
  type result.txt
  goto :eof
)
echo XVLOG_OK >> result.txt

for %%T in (tb_relay_tx tb_udp_payload_extract tb_local_steer) do (
  call "%BIN%\xelab.bat" %%T -s %%T -debug typical > xelab_%%T.log 2>&1
  if errorlevel 1 (
    echo %%T XELAB_FAIL >> result.txt
  ) else (
    call "%BIN%\xsim.bat" %%T -R -log xsim_%%T.log > xsim_%%T.console.log 2>&1
    findstr /C:"_TB: PASS" xsim_%%T.console.log >nul 2>&1
    if errorlevel 1 (
      echo %%T FAIL >> result.txt
    ) else (
      echo %%T PASS >> result.txt
    )
  )
)

echo ---- result.txt ----
type result.txt
