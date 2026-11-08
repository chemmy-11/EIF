#==============================================================================
# qspi_program.ps1 -- prj13 P1-7  QSPI flash: image build / factory backup /
#                                   programming / boot verification
#-----------------------------------------------------------------------------
# SCOPE OF THIS SCRIPT AS OF 2026-11-08: written and dry-run self-checked only.
#   It has NEVER been executed against a board (boards offline). Every hardware
#   step is marked SKIP/TO-BE-RUN until someone runs it with the board present.
#
# WHAT IT DRIVES (all hardware work happens inside scripts\write_cfgmem.tcl,
# which is syntax-gated with the Vivado 2023.1 Tcl 8.5.14 interpreter):
#   evaluate : pure host math -- capacity, .mcs size estimate, go/no-go. No Vivado.
#   build    : write_cfgmem -format mcs -interface SPIx4 -size 16 -loadbit ...
#   backup   : read the flash back to out\flash_backup_<date>.bin (factory image)
#   program  : create_hw_cfgmem + PROGRAM.FILES/.ERASE/.CFG_PROGRAM/.VERIFY +
#              program_hw_cfgmem + boot_hw_device
#   pipeline : build -> backup -> program -> verify (each step gated)
#
# CAPACITY FACTS (measured 2026-11-08)
#   .bit P1 baseline           10,302,552 bytes   (sha256 c856ba83...7401)
#   .bit B1 candidate          10,636,592 bytes   (b1_E9BE2B14)
#   N25Q128 (128 Mbit)         16,777,216 bytes
#   => payload headroom 5.7-6.5 MB (34-39%). Compression is optional, NOT needed.
#   => the .mcs TEXT file is ~2.81x the payload (~29 MB) but that is a host-side
#      file: program_hw_cfgmem parses it and writes only the payload to flash.
#
# SAFETY GATES (deliberate, this can brick a board's boot image)
#   default            = dry-run: print every command, execute nothing
#   -Run               = allow host-side / read-only Vivado work (build, backup)
#   -Run -FlashWrite   = allow the destructive step (erase + program + verify)
#   -Verify            = after boot, capture ILA6 and require ch_up=1
#
# USAGE
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\qspi_program.ps1
#   powershell ... -Mode build -Run
#   powershell ... -Mode backup -Run
#   powershell ... -Mode program -Run -FlashWrite -Verify
#   powershell ... -Mode pipeline -Run -FlashWrite -Verify
#
# EXIT CODES  0 = ok / dry-run ok | 1 = failure | 2 = config error | 3 = backup
#             unsupported (do not program: the factory image cannot be saved)
#==============================================================================
param(
    [ValidateSet('evaluate', 'build', 'backup', 'program', 'pipeline')]
    [string]$Mode = 'evaluate',
    [string]$ProjRoot = 'D:\FPGA\prj\project_13',
    [string]$Bit = '',
    [string]$Mcs = '',
    [string]$BackupFile = '',
    [int]$SizeMB = 16,
    [string]$Interface = 'SPIx4',
    [string]$FlashPart = 'n25q128-3.3v-spi-x1_x2_x4',
    [string]$HwServer = 'localhost:3121',
    [string]$Cable = '210512180081',
    [int]$VerifyWindowSec = 30,
    [string]$OutDir = '',
    [switch]$Run,
    [switch]$FlashWrite,
    [switch]$Compress,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'

$Vivado     = 'D:\Xilinx\Vivado\2023.1\bin\vivado.bat'
$AsciiTmp   = 'D:\FPGA\.tmp'
$CfgTcl     = Join-Path $ProjRoot 'scripts\write_cfgmem.tcl'
$IlaTcl     = Join-Path $ProjRoot 'scripts\ila_capture.tcl'
$ProbesLtx  = Join-Path $ProjRoot 'scripts\probes.ltx'

$today = Get-Date -Format 'yyyyMMdd'
if ($Bit -eq '') { $Bit = Join-Path $ProjRoot 'out\aurora_mem_bridge.bit' }
if ($Mcs -eq '') { $Mcs = Join-Path $ProjRoot ('out\aurora_mem_bridge_ku060_{0}.mcs' -f $today) }
if ($BackupFile -eq '') { $BackupFile = Join-Path $ProjRoot ('out\flash_backup_{0}.bin' -f $today) }
if ($OutDir -eq '') { $OutDir = Join-Path $ProjRoot 'out\evidence_2026-11-08_p1_suite\qspi' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ts = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogPath = Join-Path $OutDir ("qspi_{0}.log" -f $ts)

function Say([string]$m) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
    Write-Host $line
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding ascii
}
function Die([string]$m) { Say ("QSPI_ERROR: " + $m); exit 2 }

function Assert-PureAscii([string]$p) {
    foreach ($ch in $p.ToCharArray()) { if ([int]$ch -gt 127) { return $false } }
    return $true
}
function Assert-NoVivadoBusy {
    $p = @(Get-Process -Name 'vivado', 'xsct', 'xsim' -ErrorAction SilentlyContinue)
    if ($p.Count -gt 0) { return (($p | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ', ') }
    return ''
}

function Invoke-CfgTcl([string]$tag, [string[]]$tclArgs) {
    $console = Join-Path $OutDir ("cfgmem_{0}_{1}.console.log" -f $tag, (Get-Date -Format 'HHmmss'))
    $busy = Assert-NoVivadoBusy
    if ($busy -ne '') { Say ("SERIAL_BUSY: {0} -> refusing to start a second Vivado" -f $busy); return $null }
    $env:TEMP = $AsciiTmp
    $env:TMP = $AsciiTmp
    $args = @('-mode', 'batch', '-source', $CfgTcl, '-notrace', '-tclargs') + $tclArgs
    Say ("VIVADO: {0} {1}" -f (Split-Path -Leaf $CfgTcl), ($tclArgs -join ' '))
    Push-Location 'D:\FPGA'
    try {
        $p = Start-Process -FilePath $Vivado -ArgumentList $args -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $console -RedirectStandardError ($console + '.err')
    } finally {
        Pop-Location
    }
    $text = ''
    if (Test-Path -LiteralPath $console) { $text = [System.IO.File]::ReadAllText($console) }
    foreach ($ln in ($text -split "`r?`n")) {
        if ($ln -match '^(CFGMEM|FLASH)_') { Say ("  " + $ln.Trim()) }
    }
    return [pscustomobject]@{ Exit = $p.ExitCode; Text = $text; Console = $console }
}

#-------------------------------------------------------------------------
# capacity evaluation (host side, no Vivado)
#-------------------------------------------------------------------------
function Get-CapacityReport {
    $cap = $SizeMB * 1024 * 1024
    $exists = Test-Path -LiteralPath $Bit
    $bitBytes = -1
    if ($exists) { $bitBytes = (Get-Item -LiteralPath $Bit).Length }
    # Intel-HEX style .mcs: 16 data bytes per record, 43 chars + CRLF = 45
    $recs = 0
    $mcsText = 0
    if ($bitBytes -gt 0) {
        $recs = [math]::Ceiling($bitBytes / 16.0)
        $mcsText = $recs * 45 + 16
    }
    $headroom = -1
    $fits = $false
    if ($bitBytes -gt 0) {
        $headroom = $cap - $bitBytes
        $fits = ($bitBytes -le $cap)
    }
    return [pscustomobject]@{
        BitPath = $Bit
        BitExists = $exists
        BitBytes = $bitBytes
        CapBytes = $cap
        Headroom = $headroom
        Fits = $fits
        Recs = $recs
        McsTextEstimate = $mcsText
        FitsPct = $(if ($bitBytes -gt 0) { [math]::Round(100.0 * $bitBytes / $cap, 1) } else { 0 })
        Reference = $false
    }
}

function Get-ReferenceCapacityReport([string]$refPath, [int]$sizeMB) {
    # The prj13 build has not produced a bitstream yet, so the evaluation may be
    # done on the prj12 baseline bit. It is the SAME design family and the same
    # geometry (10,302,552 B), so the capacity answer is unchanged -- but the
    # report says REFERENCE so nobody mistakes it for a prj13 artefact.
    $r = Get-CapacityReport
    if (-not (Test-Path -LiteralPath $refPath)) { return $null }
    $bytes = (Get-Item -LiteralPath $refPath).Length
    $cap = $sizeMB * 1024 * 1024
    $recs = [math]::Ceiling($bytes / 16.0)
    return [pscustomobject]@{
        BitPath = $refPath
        BitExists = $true
        BitBytes = $bytes
        CapBytes = $cap
        Headroom = $cap - $bytes
        Fits = ($bytes -le $cap)
        Recs = $recs
        McsTextEstimate = ($recs * 45 + 16)
        FitsPct = [math]::Round(100.0 * $bytes / $cap, 1)
        Reference = $true
    }
}

function Show-CapacityReport($r) {
    Say "=== capacity evaluation (host side) ==="
    Say ("bitstream     : {0}" -f $r.BitPath)
    if ($r.Reference) { Say "  SOURCE      : REFERENCE image (prj13 has no bitstream of its own yet)" }
    if (-not $r.BitExists) {
        Say "  BIT_MISSING : the file does not exist (build it first: scripts\build_impl.tcl)"
        return
    }
    Say ("  BIT_BYTES   : {0:N0}" -f $r.BitBytes)
    Say ("flash capacity: {0:N0} bytes ({1} MiB, N25Q128)" -f $r.CapBytes, $SizeMB)
    Say ("  HEADROOM    : {0:N0} bytes" -f $r.Headroom)
    Say ("  OCCUPANCY   : {0} % of the device" -f $r.FitsPct)
    Say ("mcs text size : ~{0:N0} bytes (~{1:N1} MB) -- HOST FILE ONLY, 16-byte records x45 chars" -f $r.McsTextEstimate, ($r.McsTextEstimate / 1MB))
    if ($r.Fits) {
        Say "VERDICT: FITS -- raw payload fits with no compression; -Compress is optional."
    } else {
        Say "VERDICT: NOT_ENOUGH_SPACE -- the .bit is larger than the flash; try -Compress or a smaller build."
    }
    Say "NOTE: only the parsed payload is written to flash; the ~29 MB .mcs text is a disk file."
}

function Invoke-Verify {
    $deadline = (Get-Date).AddSeconds($VerifyWindowSec)
    Say ("VERIFY: waiting up to {0}s for the flash boot (get_hw_ilas=4 and ch_up=1)" -f $VerifyWindowSec)
    while ((Get-Date) -lt $deadline) {
        $csv = Join-Path $OutDir ("ila6_boot_{0}.csv" -f (Get-Date -Format 'HHmmss'))
        $console = Join-Path $OutDir ("ila6_boot_{0}.console.log" -f (Get-Date -Format 'HHmmss'))
        $busy = Assert-NoVivadoBusy
        if ($busy -ne '') { Say ("SERIAL_BUSY: {0} -> retry in 10 s" -f $busy); Start-Sleep -Seconds 10; continue }
        $args = @('-mode', 'batch', '-source', $IlaTcl, '-tclargs', $HwServer, $Cable, $csv)
        Push-Location 'D:\FPGA'
        try {
            Start-Process -FilePath $Vivado -ArgumentList $args -NoNewWindow -Wait `
                -RedirectStandardOutput $console -RedirectStandardError ($console + '.err') | Out-Null
        } finally {
            Pop-Location
        }
        $text = ''
        if (Test-Path -LiteralPath $console) { $text = [System.IO.File]::ReadAllText($console) }
        $nIla = 0
        foreach ($ln in ($text -split "`r?`n")) {
            if ($ln -match '^ILA_PROBE_COUNT:') { $nIla = $nIla + 1 }
        }
        Say ("VERIFY: ILA cores reported = {0}" -f $nIla)
        if ((Test-Path -LiteralPath $csv) -and ($text -match 'ILA_CSV_OK')) {
            $raw = @(Get-Content -LiteralPath $csv)
            $data = @($raw | Where-Object { $_ -match '^\d+,\d+,' })
            if ($data.Count -gt 0) {
                $hdr = @($raw[0].Split(','))
                $row = @($data[$data.Count - 1].Split(','))
                $ci = -1
                for ($i = 0; $i -lt $hdr.Count; $i++) { if ($hdr[$i].Trim() -eq 'dbg_ch_up') { $ci = $i } }
                if ($ci -ge 0) {
                    $chup = [int]$row[$ci].Trim()
                    Say ("VERIFY: dbg_ch_up = {0}  ({1})" -f $chup, $csv)
                    if ($chup -eq 1) {
                        Say "FLASH_VERIFY: PASS (flash boot produced a live design: ILA visible, ch_up=1)"
                        return 0
                    }
                } else {
                    Say "VERIFY: dbg_ch_up probe not present in this ltx/csv"
                }
            }
        } else {
            Say "VERIFY: no ILA data yet (design may still be loading)"
        }
        Start-Sleep -Seconds 5
    }
    Say "FLASH_VERIFY: FAIL (no live design within the window -- check the boot mode pins and the image)"
    return 1
}

#=========================================================================
# MAIN
#=========================================================================
Say "=== qspi_program (prj13 P1-7) ==="
Say ("log        : " + $script:LogPath)
Say ("mode       : {0}  run={1}  flashwrite={2}  verify={3}" -f $Mode, $Run.IsPresent, $FlashWrite.IsPresent, $Verify.IsPresent)
Say ("bit        : " + $Bit)
Say ("mcs        : " + $Mcs)
Say ("backup     : " + $BackupFile)
Say ("flash      : {0} {1} MiB part={2}" -f $Interface, $SizeMB, $FlashPart)

# ---- input validation ----------------------------------------------------
foreach ($p in @($ProjRoot, $OutDir)) {
    if (-not (Assert-PureAscii $p)) { Die ("non-ASCII path: " + $p) }
}
if (-not (Test-Path -LiteralPath $CfgTcl)) { Die ("missing Tcl driver: " + $CfgTcl) }
if (-not (Test-Path -LiteralPath $Vivado)) { Die ("missing vivado: " + $Vivado) }
New-Item -ItemType Directory -Force -Path $AsciiTmp | Out-Null
$env:TEMP = $AsciiTmp
$env:TMP = $AsciiTmp

$cap = Get-CapacityReport
Show-CapacityReport $cap
if (-not $cap.BitExists) {
    $ref = 'D:\FPGA\prj\project_12\out\aurora_mem_bridge.bit'
    $refRep = Get-ReferenceCapacityReport $ref $SizeMB
    if ($null -ne $refRep) {
        Say ""
        Say "=== reference capacity evaluation (prj12 baseline bit) ==="
        Show-CapacityReport $refRep
        $cap = $refRep
    } else {
        Say ("REFERENCE_MISSING: neither {0} nor {1} exists" -f $Bit, $ref)
    }
}

$plan = @()
$plan += ("1) build   : write_cfgmem -format mcs -interface " + $Interface + " -size " + $SizeMB + " -loadbit 'up 0x0 <bit>' -force <mcs>")
$plan += ("2) backup  : readback_hw_cfgmem -> " + $BackupFile)
$plan += ("3) program : create_hw_cfgmem " + $FlashPart + " + PROGRAM.FILES/.ERASE/.CFG_PROGRAM/.VERIFY + program_hw_cfgmem")
$plan += ("4) boot    : boot_hw_device ; then verify ILA + ch_up within " + $VerifyWindowSec + "s")
Say ""
Say "=== plan ==="
foreach ($l in $plan) { Say ("  " + $l) }

if ($Mode -eq 'evaluate') {
    Say ""
    Say "QSPI_RESULT: EVALUATE_OK (no Vivado, no hardware touched)"
    Say "NEXT       : -Mode build -Run  (host side)  then  -Mode backup -Run  (read factory image)"
    exit 0
}

$wanted = $Mode
if ($Mode -eq 'pipeline') { $wanted = 'pipeline' }

# ---- step 1: build ------------------------------------------------------
$built = $false
if (($wanted -eq 'build') -or ($wanted -eq 'pipeline')) {
    if (-not (Test-Path -LiteralPath $Bit)) {
        if (-not $Run.IsPresent) {
            Say ""
            Say ("DRYRUN build: MISSING INPUT -> " + $Bit)
            Say "  the prj13 bitstream does not exist yet; run scripts\build_impl.tcl first"
            Say ("  would run: -tclargs build {0} {1} {2} {3}" -f $Bit, $Mcs, $SizeMB, $Interface)
            Say "QSPI_RESULT: DRYRUN_INCOMPLETE (missing input, nothing executed)"
            exit 0
        }
        Die ("bitstream missing: " + $Bit + " (the evaluation above may have used the prj12 REFERENCE bit, which must not be flashed from this project)")
    }
    if (-not $cap.Fits) { Die "bitstream does not fit the flash; aborting before any write" }
    if (-not $Run.IsPresent) {
        Say ""
        Say "DRYRUN build: would run write_cfgmem via $CfgTcl"
        Say ("  -tclargs build {0} {1} {2} {3}" -f $Bit, $Mcs, $SizeMB, $Interface)
        if ($wanted -eq 'build') { Say "QSPI_RESULT: DRYRUN_OK"; exit 0 }
    } else {
        $targs = @('build', $Bit, $Mcs, [string]$SizeMB, $Interface)
        if ($Compress.IsPresent) { $targs += 'compress' }
        $r = Invoke-CfgTcl 'build' $targs
        if ($null -eq $r) { exit 1 }
        if (($r.Exit -ne 0) -or ($r.Text -notmatch 'CFGMEM_BUILD_OK')) {
            Say ("QSPI_RESULT: FAIL (build marker missing, exit={0})" -f $r.Exit)
            exit 1
        }
        Say ("QSPI_STEP: BUILD_OK -> {0}" -f $Mcs)
        $built = $true
    }
}

# ---- step 2: backup ----------------------------------------------------
if (($wanted -eq 'backup') -or ($wanted -eq 'pipeline')) {
    if (-not $Run.IsPresent) {
        Say ""
        Say "DRYRUN backup: would run readback_hw_cfgmem via $CfgTcl"
        Say ("  -tclargs backup {0} {1} {2} {3} {4} {5}" -f $BackupFile, $SizeMB, $Interface, $FlashPart, $HwServer, $Cable)
        if ($wanted -eq 'backup') { Say "QSPI_RESULT: DRYRUN_OK"; exit 0 }
    } else {
        $targs = @('backup', $BackupFile, [string]$SizeMB, $Interface, $FlashPart, $HwServer, $Cable)
        $r = Invoke-CfgTcl 'backup' $targs
        if ($null -eq $r) { exit 1 }
        if ($r.Text -match 'CFGMEM_BACKUP_UNSUPPORTED') {
            Say "QSPI_RESULT: BACKUP_UNSUPPORTED"
            Say "STOP: the factory image cannot be saved with this Vivado."
            Say "      Flashing is then IRREVERSIBLE for the original image -- get an explicit"
            Say "      go/no-go from the owner before using -FlashWrite."
            exit 3
        }
        if (($r.Exit -ne 0) -or ($r.Text -notmatch 'CFGMEM_BACKUP_OK')) {
            Say ("QSPI_RESULT: FAIL (backup marker missing, exit={0})" -f $r.Exit)
            exit 1
        }
        Say ("QSPI_STEP: BACKUP_OK -> {0}" -f $BackupFile)
    }
}

# ---- step 3: program ---------------------------------------------------
if (($wanted -eq 'program') -or ($wanted -eq 'pipeline')) {
    if (-not (Test-Path -LiteralPath $Mcs)) {
        Say ("WARN: mcs missing: {0}" -f $Mcs)
        if ($wanted -eq 'program') {
            if (-not $Run.IsPresent) {
                Say ""
                Say "DRYRUN program: MISSING INPUT (no .mcs yet)"
                Say ("  would run: -tclargs program {0} {1} {2} {3} {4} {5}" -f $Mcs, $SizeMB, $Interface, $FlashPart, $HwServer, $Cable)
                Say "QSPI_RESULT: DRYRUN_INCOMPLETE (missing input, nothing executed)"
                exit 0
            }
            Die "the mcs must exist before programming (run -Mode build -Run first)"
        }
    }
    if ((-not $Run.IsPresent) -or (-not $FlashWrite.IsPresent)) {
        Say ""
        Say "DRYRUN program: needs -Run AND -FlashWrite (destructive: erase + program + verify)"
        Say ("  -tclargs program {0} {1} {2} {3} {4} {5}" -f $Mcs, $SizeMB, $Interface, $FlashPart, $HwServer, $Cable)
        if (-not (Test-Path -LiteralPath $BackupFile)) {
            Say ("  WARNING: no backup on disk yet ({0}) -- read the factory image first" -f $BackupFile)
        }
        Say "QSPI_RESULT: DRYRUN_OK"
        exit 0
    }
    $targs = @('program', $Mcs, [string]$SizeMB, $Interface, $FlashPart, $HwServer, $Cable)
    $r = Invoke-CfgTcl 'program' $targs
    if ($null -eq $r) { exit 1 }
    if (($r.Exit -ne 0) -or ($r.Text -notmatch 'CFGMEM_PROGRAM_OK')) {
        Say ("QSPI_RESULT: FAIL (program marker missing, exit={0})" -f $r.Exit)
        Say "RECOVERY: the JTAG path is independent of the flash -- re-program the .bit over JTAG"
        Say "          (out\twin_burn.ps1 -Board A -Mode Bit -Run) and re-write the flash image."
        exit 1
    }
    Say "QSPI_STEP: PROGRAM_OK"
}

# ---- step 4: verify ---------------------------------------------------
if ($Verify.IsPresent) {
    if (-not $Run.IsPresent) {
        Say "DRYRUN verify: would capture ILA6 after the boot and require ch_up=1"
    } else {
        $rc = Invoke-Verify
        if ($rc -ne 0) { Say "QSPI_RESULT: FAIL (post-boot verification)"; exit 1 }
        Say "QSPI_STEP: VERIFY_OK"
    }
}

Say ""
Say "QSPI_RESULT: PASS"
exit 0
