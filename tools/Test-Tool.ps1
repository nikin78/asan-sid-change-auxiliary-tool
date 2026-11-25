# ==============================================================================
# Automated Unit & Smoke Test Suite for SID_Change_Aux_Tool.bat
# Loads the actual built deliverable with SID_TOOL_TEST_MODE=1 and tests
# pure helpers, parsers, media guards, non-destructive renames, and live
# read-only diagnostics on the local Windows machine.
# ==============================================================================
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$batPath = Join-Path $repoRoot "SID_Change_Aux_Tool.bat"

if (-not (Test-Path $batPath)) {
    throw "Built deliverable not found: $batPath. Run tools\Build-Tool.ps1 first."
}

$script:Passed = 0
$script:Failed = 0

function Assert-True([bool]$cond, [string]$msg) {
    if ($cond) {
        $script:Passed++
        Write-Host "  [PASS] $msg" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  [FAIL] $msg" -ForegroundColor Red
    }
}

function Assert-Eq($actual, $expected, [string]$msg) {
    if ($actual -eq $expected) {
        $script:Passed++
        Write-Host "  [PASS] $msg (=$actual)" -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host "  [FAIL] $msg (expected '$expected', got '$actual')" -ForegroundColor Red
    }
}

# Load actual built .bat exactly like runtime wrapper does
$env:SID_TOOL_TEST_MODE = "1"
try {
    $code = [System.IO.File]::ReadAllText($batPath)
    Invoke-Expression $code
} finally {
    Remove-Item Env:SID_TOOL_TEST_MODE -ErrorAction SilentlyContinue
}

Write-Host "`n=== 1. U() Decoder & Path Safety ===" -ForegroundColor Cyan
$decodedPath = U ("\uC2E4\uD328: C:\Windows\EFI\BOOT \\MAIN-PC\Kyocera")
Assert-True ($decodedPath -like "*C:\Windows\EFI\BOOT \\MAIN-PC\Kyocera") "U() preserves Windows and UNC backslashes without throwing"
Assert-True ($decodedPath.StartsWith([char]0xC2E4 + [char]0xD328)) "U() decodes Hangul codepoints accurately"

Write-Host "`n=== 2. Parse-BcdFirmwareLines (English & Korean) ===" -ForegroundColor Cyan
$enBcd = @(
    "Firmware Boot Manager",
    "---------------------",
    "identifier              {fwbootmgr}",
    "displayorder            {bootmgr}",
    "                        {11111111-1111-1111-1111-111111111111}",
    "timeout                 1",
    "",
    "Windows Boot Manager",
    "--------------------",
    "identifier              {bootmgr}",
    "device                  partition=\Device\HarddiskVolume1",
    "path                    \EFI\Microsoft\Boot\bootmgfw.efi",
    "description             Windows Boot Manager",
    "",
    "Firmware Application (101fffff)",
    "-------------------------------",
    "identifier              {22222222-2222-2222-2222-222222222222}",
    "device                  partition=E:",
    "path                    \EFI\BOOT\BOOTX64.EFI",
    "description             UEFI: Seagate FireCuda SSD Partition 2"
)
$enEntries = @(Parse-BcdFirmwareLines $enBcd)
Assert-Eq $enEntries.Count 3 "EN bcdedit parsed 3 entries"
Assert-Eq $enEntries[0].Identifier "{fwbootmgr}" "EN {fwbootmgr} keeps its own identifier (not hijacked by displayorder GUID)"
Assert-Eq $enEntries[1].Identifier "{bootmgr}" "EN {bootmgr} identifier parsed"
Assert-Eq $enEntries[2].Device "partition=E:" "EN USB entry device parsed"

$koId = U "\uC2DD\uBCC4\uC790"
$koDev = U "\uC7A5\uCE58"
$koPath = U "\uACBD\uB85C"
$koDesc = U "\uC124\uBA85"
$koWinMgr = U "Windows \uBD80\uD305 \uAD00\uB9AC\uC790"
$koBcd = @(
    "---------------------",
    "$koId                  {fwbootmgr}",
    "displayorder            {bootmgr}",
    "                        {33333333-3333-3333-3333-333333333333}",
    "",
    "---------------------",
    "$koId                  {bootmgr}",
    "$koDev                  partition=C:",
    "$koPath                  \EFI\Microsoft\Boot\bootmgfw.efi",
    "$koDesc                  $koWinMgr",
    "",
    "---------------------",
    "$koId                  {33333333-3333-3333-3333-333333333333}",
    "$koDev                  partition=F:",
    "$koPath                  \EFI\BOOT\BOOTX64.EFI",
    "$koDesc                  UEFI: SanDisk Ultra USB 3.0"
)
$koEntries = @(Parse-BcdFirmwareLines $koBcd)
Assert-Eq $koEntries.Count 3 "KO bcdedit parsed 3 entries"
Assert-Eq $koEntries[1].Description $koWinMgr "KO Windows Boot Manager description parsed"
Assert-Eq $koEntries[2].Description "UEFI: SanDisk Ultra USB 3.0" "KO USB description parsed"

Write-Host "`n=== 3. 4-Tier NVRAM USB Matching ===" -ForegroundColor Cyan
$m1 = @(Find-MatchedUsbNvramEntries $koEntries @("partition=C:") @("partition=F:") @() @() $true)
Assert-Eq $m1.Count 1 "Tier 1 drive letter match returns 1 USB entry (excludes KO Windows Boot Manager)"
Assert-Eq $m1[0].Identifier "{33333333-3333-3333-3333-333333333333}" "Tier 1 matched exact USB GUID"

$m2 = @(Find-MatchedUsbNvramEntries $enEntries @("partition=C:") @() @("FireCuda") @() $true)
Assert-Eq $m2.Count 1 "Tier 2 model name match finds FireCuda SSD"

$m3 = @(Find-MatchedUsbNvramEntries $enEntries @("partition=C:") @() @() @("Partition\s+2\b") $true)
Assert-Eq $m3.Count 1 "Tier 3 partition match finds Partition 2"

$genericEntries = @(
    @{ Identifier = "{44444444-4444-4444-4444-444444444444}"; Description = "UEFI: USB Hard Drive"; Device = ""; Path = "" },
    @{ Identifier = "{55555555-5555-5555-5555-555555555555}"; Description = "UEFI: Samsung SSD 980 PRO (NVMe)"; Device = ""; Path = "" }
)
$m4 = @(Find-MatchedUsbNvramEntries $genericEntries @() @() @() @() $true)
Assert-Eq $m4.Count 1 "Tier 4 generic USB match finds USB Hard Drive and excludes internal NVMe"
Assert-Eq $m4[0].IsExact $false "Tier 4 marks IsExact=false"

Write-Host "`n=== 4. Media Guards, Bootloader Classifier & Non-Destructive Rename ===" -ForegroundColor Cyan
$tmpBase = Join-Path ([System.IO.Path]::GetTempPath()) ("sid_aux_test_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpBase -Force | Out-Null
try {
    # 4a. Clean Windows GPT ESP
    $pEsp = Join-Path $tmpBase "esp_win"
    New-Item -ItemType Directory -Path "$pEsp\EFI\Microsoft\Boot" -Force | Out-Null
    New-Item -ItemType Directory -Path "$pEsp\EFI\BOOT" -Force | Out-Null
    Set-Content -Path "$pEsp\EFI\Microsoft\Boot\BCD" -Value "bcd"
    Set-Content -Path "$pEsp\EFI\BOOT\BOOTX64.EFI" -Value "efi"
    Assert-Eq (Inspect-BootloaderPartition $pEsp "GPT_EFI" $false) "ACTIVE" "Windows GPT ESP detected as ACTIVE"

    # Disable & Restore GPT EFI
    $rDis = Invoke-BootloaderRenameInRoot $pEsp "GPT_EFI" "DISABLE"
    Assert-True $rDis.Success "GPT EFI disable succeeds"
    Assert-Eq (Inspect-BootloaderPartition $pEsp "GPT_EFI" $false) "DISABLED" "After disable, GPT ESP state is DISABLED"
    $rRes = Invoke-BootloaderRenameInRoot $pEsp "GPT_EFI" "RESTORE"
    Assert-True $rRes.Success "GPT EFI restore succeeds"
    Assert-Eq (Inspect-BootloaderPartition $pEsp "GPT_EFI" $false) "ACTIVE" "After restore, GPT ESP state is ACTIVE"

    # 4b. GPT ESP with BOTH EFI and EFI_OLD
    New-Item -ItemType Directory -Path "$pEsp\EFI_OLD" -Force | Out-Null
    Assert-Eq (Inspect-BootloaderPartition $pEsp "GPT_EFI" $false) "BOTH" "Coexisting EFI + EFI_OLD detected as BOTH"

    # 4c. WinPE with sources\boot.wim (Stage 1 bug fix!)
    $pWim = Join-Path $tmpBase "winpe_wim"
    New-Item -ItemType Directory -Path "$pWim\sources" -Force | Out-Null
    New-Item -ItemType Directory -Path "$pWim\EFI\Microsoft\Boot" -Force | Out-Null
    Set-Content -Path "$pWim\sources\boot.wim" -Value "wim"
    Assert-Eq (Inspect-BootloaderPartition $pWim "GPT_EFI" $false) "WINPE_BLOCKED" "sources\boot.wim guard blocks WinPE partition"
    $rBlk = Invoke-BootloaderRenameInRoot $pWim "GPT_EFI" "DISABLE"
    Assert-Eq $rBlk.Status "BLOCKED" "Rename blocked on sources\boot.wim partition"

    # 4d. WinPE / Ventoy EFI\BOOT without EFI\Microsoft (Stage 4 guard!)
    $pPeEfi = Join-Path $tmpBase "winpe_efi_only"
    New-Item -ItemType Directory -Path "$pPeEfi\EFI\BOOT" -Force | Out-Null
    Set-Content -Path "$pPeEfi\EFI\BOOT\BOOTX64.EFI" -Value "pe"
    Assert-Eq (Inspect-BootloaderPartition $pPeEfi "GPT_EFI" $false) "WINPE_BLOCKED" "EFI\BOOT without EFI\Microsoft blocked as WinPE media"

    # 4e. OS partition (ntoskrnl.exe)
    $pOs = Join-Path $tmpBase "os_part"
    New-Item -ItemType Directory -Path "$pOs\Windows\System32" -Force | Out-Null
    New-Item -ItemType Directory -Path "$pOs\EFI" -Force | Out-Null
    Set-Content -Path "$pOs\Windows\System32\ntoskrnl.exe" -Value "kernel"
    Assert-Eq (Inspect-BootloaderPartition $pOs "GPT_EFI" $false) "OS_BLOCKED" "ntoskrnl.exe blocks GPT partition"

    # 4f. MBR Active System Reserved with +R +S +H attributes on bootmgr
    $pMbr = Join-Path $tmpBase "mbr_sysres"
    New-Item -ItemType Directory -Path "$pMbr\Boot" -Force | Out-Null
    Set-Content -Path "$pMbr\bootmgr" -Value "bootmgr"
    Set-Content -Path "$pMbr\Boot\BCD" -Value "bcd"
    $bmItem = Get-Item "$pMbr\bootmgr"
    $bmItem.Attributes = [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
    Assert-Eq (Inspect-BootloaderPartition $pMbr "MBR_ACTIVE" $true) "ACTIVE" "MBR active System Reserved detected as ACTIVE"
    $rmDis = Invoke-BootloaderRenameInRoot $pMbr "MBR_ACTIVE" "DISABLE"
    Assert-True $rmDis.Success "MBR disable renames +R+S+H bootmgr and Boot folder"
    Assert-Eq (Inspect-BootloaderPartition $pMbr "MBR_ACTIVE" $false) "DISABLED" "MBR disabled state recognized even when inactive"
    $rmRes = Invoke-BootloaderRenameInRoot $pMbr "MBR_ACTIVE" "RESTORE"
    Assert-True $rmRes.Success "MBR restore brings back bootmgr and Boot folder"
    Assert-Eq (Inspect-BootloaderPartition $pMbr "MBR_ACTIVE" $true) "ACTIVE" "MBR restored state is ACTIVE"

    # 4g. MBR Active single-partition OS (bootmgr + ntoskrnl.exe)
    $pMbrOs = Join-Path $tmpBase "mbr_os"
    New-Item -ItemType Directory -Path "$pMbrOs\Windows\System32" -Force | Out-Null
    Set-Content -Path "$pMbrOs\Windows\System32\ntoskrnl.exe" -Value "k"
    Set-Content -Path "$pMbrOs\bootmgr" -Value "bm"
    Assert-Eq (Inspect-BootloaderPartition $pMbrOs "MBR_ACTIVE" $true) "MBR_OS_BLOCKED" "Single-partition MBR OS detected as MBR_OS_BLOCKED"

    # 4h. Spooler queue cleanup helper (Stage 3)
    $pQueue = Join-Path $tmpBase "PRINTERS"
    New-Item -ItemType Directory -Path $pQueue -Force | Out-Null
    Set-Content -Path "$pQueue\00001.SPL" -Value "spl"
    Set-Content -Path "$pQueue\00001.SHD" -Value "shd"
    Set-Content -Path "$pQueue\extra.tmp" -Value "tmp"
    $qRes = Clear-SpoolerQueueDirectory $pQueue
    Assert-Eq $qRes.DeletedCount 3 "Spooler queue cleanup deleted all 3 files"
    Assert-Eq $qRes.SplShdDeleted 2 "Spooler queue cleanup tracked 2 SPL/SHD job files"
    Assert-Eq $qRes.RemainingCount 0 "Spooler queue has 0 remaining files"
    Assert-True (Test-Path $pQueue) "PRINTERS directory itself is preserved"
} finally {
    Remove-Item -LiteralPath $tmpBase -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== 5. WinPE diskpart Fallback Parsers (EN & KO) ===" -ForegroundColor Cyan
$dpListEn = @(
    "  Disk ###  Status         Size     Free     Dyn  Gpt",
    "  --------  -------------  -------  -------  ---  ---",
    "  Disk 0    Online          476 GB      0 B        *",
    "  Disk 1    Online          931 GB  1024 KB",
    "  Disk 2    Offline          59 GB      0 B"
)
$pdEn = @(Parse-DiskpartListDisk $dpListEn)
Assert-Eq $pdEn.Count 3 "EN list disk parsed 3 rows"
Assert-Eq $pdEn[0].PartitionStyle "GPT" "EN Disk 0 identified as GPT"
Assert-Eq $pdEn[1].PartitionStyle "MBR" "EN Disk 1 identified as MBR"
Assert-Eq $pdEn[2].IsOnline $false "EN Disk 2 identified as Offline"

$koDisk = U "\uB514\uC2A4\uD06C"
$koOnline = U "\uC628\uB77C\uC778"
$dpListKo = @(
    "  $koDisk ###  Status         Size     Free     Dyn  Gpt",
    "  --------  -------------  -------  -------  ---  ---",
    "  $koDisk 0    $koOnline          476 GB      0 B        *",
    "  $koDisk 1    $koOnline          931 GB   1024 KB"
)
$pdKo = @(Parse-DiskpartListDisk $dpListKo)
Assert-Eq $pdKo.Count 2 "KO list disk parsed 2 rows"
Assert-Eq $pdKo[0].IsOnline $true "KO Disk 0 Online detected"
Assert-Eq $pdKo[0].PartitionStyle "GPT" "KO Disk 0 GPT detected"

$dpDetailDiskKo = @(
    "Samsung SSD 980 PRO 500GB",
    "$koDisk ID: {12345678-1234-1234-1234-1234567890AB}",
    ((U "\uC720\uD615") + "   : NVMe")
)
$ddKo = Parse-DiskpartDetailDisk $dpDetailDiskKo
Assert-Eq $ddKo.FriendlyName "Samsung SSD 980 PRO 500GB" "KO detail disk model extracted"
Assert-Eq $ddKo.IsUsb $false "KO NVMe disk is not USB"
Assert-Eq $ddKo.PartitionStyle "GPT" "KO GUID Disk ID detected as GPT"

$dpDetailUsb = @(
    "SanDisk Ultra USB 3.0",
    "Disk ID: 1A2B3C4D",
    "Type   : USB"
)
$ddUsb = Parse-DiskpartDetailDisk $dpDetailUsb
Assert-Eq $ddUsb.IsUsb $true "USB disk detected via detail disk Type : USB"
Assert-Eq $ddUsb.PartitionStyle "MBR" "MBR hex Disk ID detected as MBR"

$koPart = U "\uD30C\uD2F0\uC158"
$koSys = U "\uC2DC\uC2A4\uD15C"
$koPri = U "\uC8FC"
$dpListPart = @(
    "  $koPart 1    $koSys            100 MB  1024 KB",
    "  $koPart 2    $koPri            475 GB   101 MB"
)
$ppRes = @(Parse-DiskpartListPartition $dpListPart)
Assert-Eq $ppRes.Count 2 "KO list partition parsed 2 rows"
Assert-Eq $ppRes[0].IsEsp $true "KO System partition flagged IsEsp"
Assert-Eq $ppRes[1].IsPrimary $true "KO Primary partition flagged IsPrimary"

$dpDetPartKo = @(
    "Type  : c12a7328-f81f-11d2-ba4b-00a0c93ec93b",
    ((U "\uD65C\uC131") + ": " + (U "\uC608")),
    "  Volume ###  Ltr  Label        Fs     Type        Size     Status     Info",
    "  ----------  ---  -----------  -----  ----------  -------  ---------  --------",
    "* Volume 2     D   OldSys       NTFS   Partition    500 MB  Healthy    System"
)
$dpInfo = Parse-DiskpartDetailPartition $dpDetPartKo
Assert-Eq $dpInfo.IsEspGuid $true "detail partition ESP GUID detected"
Assert-Eq $dpInfo.IsActive $true "KO Active: Yes detected"
Assert-Eq $dpInfo.DriveLetter "D" "detail partition Ltr column parsed accurately"

Write-Host "`n=== 6. Post-SID Network Printer Parser & Live Read-Only Smoke Test ===" -ForegroundColor Cyan
Assert-Eq (Parse-NetworkPrinterServer "\\MAIN-PC\Kyocera" "" "") "MAIN-PC" "UNC printer name server extracted"
Assert-Eq (Parse-NetworkPrinterServer "LocalName" "\\192.168.0.50\HP" "") "192.168.0.50" "UNC port server extracted"

$liveSys = Get-SystemInfo
Assert-True (-not [string]::IsNullOrWhiteSpace($liveSys.Vendor)) "Live Get-SystemInfo succeeded ($($liveSys.Vendor) / $($liveSys.ModelName))"

$liveSid = Get-LocalMachineSid
Assert-True ($liveSid -match "^S-1-5-21-\d+-\d+-\d+$") "Live Get-LocalMachineSid returned valid Machine SID ($liveSid)"

$livePost = Get-PostSidStatus
Assert-Eq $livePost.ComputerName $env:COMPUTERNAME "Live Get-PostSidStatus returned ComputerName"
Assert-True ($livePost.Role -in @("Host","Client")) "Live Get-PostSidStatus classified Role=$($livePost.Role)"
Assert-True ($livePost.SpoolerStatus -ne "") "Live Get-PostSidStatus read SpoolerStatus=$($livePost.SpoolerStatus)"

$natRes = Invoke-NativeOem "bcdedit.exe" "/?"
Assert-Eq $natRes.ExitCode 0 "Live Invoke-NativeOem bcdedit /? succeeded"
Assert-True ($natRes.Lines.Count -gt 5) "Live Invoke-NativeOem returned output lines ($($natRes.Lines.Count))"

Write-Host "`n=== 7. Korean UI String Audit ===" -ForegroundColor Cyan
$uMatches = [regex]::Matches($code, 'U\s+"([^"]+)"')
$badU = 0
foreach ($m in $uMatches) {
    $dec = U $m.Groups[1].Value
    if ($dec -match '\\u[0-9a-fA-F]' -or $dec.Contains([char]0xFFFD)) {
        $badU++
        Write-Host "  [BAD U STRING] $dec" -ForegroundColor Red
    }
}
Assert-Eq $badU 0 "All $($uMatches.Count) U(...) Korean strings decode cleanly without stray escapes or U+FFFD"

Write-Host "`n==================================================================" -ForegroundColor Cyan
if ($script:Failed -eq 0) {
    Write-Host "[TEST SUMMARY] ALL $($script:Passed) TESTS PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[TEST SUMMARY] $($script:Passed) passed, $($script:Failed) FAILED!" -ForegroundColor Red
    exit 1
}
