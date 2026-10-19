# -*- coding: utf-8 -*-
"""Patch j3_fourchains.ps1 for R2 (2026-10-19):
1) 前置口径: R2 的 u_wr/u_rd 计数不再 1:1（mode-0/超时丢弃也会计入 wr），
   故不再要求 wmwr==wmrd；改为「bit25=0 且 wmwr/wmrd 连续两拍不变」= 槽表静默。
2) R2 桥①读出只走 DMA（硬件读引擎退役）⇒ J3 前必须 DMA 模式；脚本自检 mode，
   若 mode=0 才发一次 'd'（toggle 语义下不重复发）。
保留原脚本其余全部行为。
"""
import io
import os
import shutil

P = r"D:\FPGA\prj\project_11\out\j3_fourchains.ps1"
BAK = P + ".bak_20261019_r2"

assert os.path.exists(P), "missing script"
if not os.path.exists(BAK):
    shutil.copy2(P, BAK)

t = io.open(P, "rb").read()
bom = t.startswith(b"\xef\xbb\xbf")
if bom:
    t = t[3:]
s = t.decode("utf-8", errors="replace")

old_cond = """        if ((-not $sticky) -and ($wr -eq $rd)) {
            if ($null -ne $prev -and $prev.Wr -eq $wr -and $prev.Rd -eq $rd) {
                Write-Log ($trace -join "`n")
                return [pscustomobject]@{ Ok = $true; State = $u; Trace = ($trace -join "`n") }
            }
            $prev = [pscustomobject]@{ Wr = $wr; Rd = $rd }
        } else {
            $prev = $null
        }"""
new_cond = """        # ★R2 (2026-10-19): u_wr/u_rd 不再 1:1（mode-0/超时丢弃也计入 wr）=> 不要求相等;
        # 槽表干净 = bit25 落零 且 两拍计数不变（无待服务请求 + 无新写提交）。
        if (-not $sticky) {
            if ($null -ne $prev -and $prev.Wr -eq $wr -and $prev.Rd -eq $rd) {
                Write-Log ($trace -join "`n")
                return [pscustomobject]@{ Ok = $true; State = $u; Trace = ($trace -join "`n") }
            }
            $prev = [pscustomobject]@{ Wr = $wr; Rd = $rd }
        } else {
            $prev = $null
        }"""
assert old_cond in s, "precondition block not found"
s = s.replace(old_cond, new_cond, 1)

old_log = 'Write-Section "J3 前置: 发 \'S\' + 轮询 \'U\'（wmwr==wmrd 且 req.bit25=0 连续两拍; 不发 \'d\'）"'
new_log = 'Write-Section "J3 前置(R2 口径): 发 \'S\' → 若 mode=0 发一次 \'d\' → 轮询 \'U\'（bit25=0 且 wmwr/wmrd 两拍不变）"'
assert old_log in s, "section log line not found"
s = s.replace(old_log, new_log, 1)

old_s = """    $sres = Invoke-UartProbe -Cmd "S" -Wait 1.2 -Drain 0.15 -Title "前置 'S' 恢复 SEQ"
    Start-Sleep -Milliseconds 300"""
new_s = """    $sres = Invoke-UartProbe -Cmd "S" -Wait 1.2 -Drain 0.15 -Title "前置 'S' 恢复 SEQ"
    Start-Sleep -Milliseconds 300
    # ★R2: 桥①读出仅 DMA（硬件读引擎退役）=> J3 必须在 DMA 模式。只在 mode=0 时发一次 'd'（toggle）。
    $u0 = Get-UState -Title "前置模式自检"
    if ($null -ne $u0 -and $u0.ParseOk -and ($u0.Mode -ne 1)) {
        [void](Invoke-UartProbe -Cmd "d" -Wait 1.2 -Drain 0.15 -Title "前置 'd' 切 DMA（R2 必需）")
        Start-Sleep -Milliseconds 300
    }"""
assert old_s in s, "S-send block not found"
s = s.replace(old_s, new_s, 1)

old_fail = 'Write-Log "前置失败: 槽表不干净(wmwr!=wmrd 或 req.bit25 未落) ⇒ 判据未取得; **板卡需重烧**后再跑（本脚本不自动重试）" "Red"'
new_fail = 'Write-Log "前置失败: 槽表不干净(bit25 未落 或 计数仍在变) ⇒ 判据未取得; **板卡需重烧**后再跑（本脚本不自动重试）" "Red"'
assert old_fail in s
s = s.replace(old_fail, new_fail, 1)

old_ok = 'Write-Log "前置清槽检查通过 ✓（wmwr==wmrd & bit25=0 连续两拍）" "Green"'
new_ok = 'Write-Log "前置清槽检查通过 ✓（R2 口径: bit25=0 & wmwr/wmrd 两拍不变）" "Green"'
assert old_ok in s
s = s.replace(old_ok, new_ok, 1)

data = s.encode("utf-8")
if bom:
    data = b"\xef\xbb\xbf" + data
io.open(P + ".tmp", "wb").write(data)
os.replace(P + ".tmp", P)
print("PATCHED bytes=", len(data), "bom=", data[:3].hex())
