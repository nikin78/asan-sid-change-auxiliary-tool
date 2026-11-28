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

Write-Host "`n=== 8. Scenario & Regression Tests (Read-Only USB / Local Special Chars / Shared Folder) ===" -ForegroundColor Cyan
# 8a. Korean diskpart 'select disk' line & Read-only state parsing
$dpDetailKoReal = @(
    ("Microsoft DiskPart " + (U "\uBC84\uC804") + " 10.0.26100.1"),
    ((U "\uCEF4\uD4E8\uD130") + ": SHK"),
    ("0 " + $koDisk + (U "\uAC00 \uC120\uD0DD\uD55C \uB514\uC2A4\uD06C\uC785\uB2C8\uB2E4.")),
    "Kanguru SS3 Write-Protected USB",
    "$koDisk ID: 9A8B7C6D",
    ((U "\uC720\uD615") + "   : USB"),
    ((U "\uD604\uC7AC \uC77D\uAE30 \uC804\uC6A9 \uC0C1\uD0DC") + " : " + (U "\uC608"))
)
$ddRo = Parse-DiskpartDetailDisk $dpDetailKoReal
Assert-Eq $ddRo.FriendlyName "Kanguru SS3 Write-Protected USB" "KO select-disk line skipped; actual disk model extracted"
Assert-Eq $ddRo.IsUsb $true "Write-protected USB detected as USB"
Assert-Eq $ddRo.IsReadOnly $true "KO Current Read-only State : Yes detected"

# 8b. Korean detail partition with 'Ltr' (\uBB38\uC790) header and CJK wide-char volume row
$koVol = U "\uBCFC\uB968"
$koLtr = U "\uBB38\uC790"
$dpDetPartKo2 = @(
    ((U "\uD65C\uC131") + ": " + (U "\uC608")),
    "  $koVol ###  $koLtr  Label        Fs     Type        Size     Status     Info",
    "  ----------  ---  -----------  -----  ----------  -------  ---------  --------",
    "* $koVol 3     E   Data         NTFS   Partition    500 GB  Healthy"
)
$dpInfo2 = Parse-DiskpartDetailPartition $dpDetPartKo2
Assert-Eq $dpInfo2.DriveLetter "E" "KO detail partition with Korean volume/Ltr row parsed E:"

# 8c. Multi-word partition type in list partition
$dpListPartMulti = @(
    "  Partition 1    Dynamic Data      100 GB  1024 KB",
    "  Partition 2    Primary           200 GB   100 GB"
)
$ppMulti = @(Parse-DiskpartListPartition $dpListPartMulti)
Assert-Eq $ppMulti.Count 2 "Multi-word partition type parsed without dropping row"
Assert-Eq $ppMulti[0].TypeText "Dynamic Data" "Multi-word partition TypeText preserved"

# 8d. Same-brand USB vs Internal SSD exclusion (Samsung USB vs Samsung NVMe)
$sameBrandEntries = @(
    @{ Identifier = "{aaaa1111-1111-1111-1111-111111111111}"; Description = "UEFI OS (Samsung SSD 980 PRO)"; Device = "partition=\Device\HarddiskVolume1"; Path = "" },
    @{ Identifier = "{bbbb2222-2222-2222-2222-222222222222}"; Description = "UEFI: Samsung Flash Drive BAR Plus"; Device = ""; Path = "" }
)
$fakeUsbDisk = @([PSCustomObject]@{ Number = 99; FriendlyName = "Samsung BAR Plus"; Size = 64GB; IsReadOnly = $true })
$fakeIntDisk = @([PSCustomObject]@{ Number = 0; FriendlyName = "Samsung SSD 980 PRO"; Size = 500GB; IsReadOnly = $false })
$fakeUsbInfo = Get-PhysicalUsbInfo $fakeUsbDisk $fakeIntDisk
Assert-True ($fakeUsbInfo.UsbStrictModelPatterns -notcontains "Samsung") "Shared brand token 'Samsung' excluded from USB single-word patterns"
Assert-True ($fakeUsbInfo.UsbStrictModelPatterns -contains "BAR") "Unique USB token 'BAR' retained"
$mBrand = @(Find-MatchedUsbNvramEntries $sameBrandEntries @() @() $fakeUsbInfo.UsbStrictModelPatterns @() $true)
Assert-Eq $mBrand.Count 1 "Same-brand Samsung NVMe SSD excluded; only Samsung BAR Plus USB matched"
Assert-Eq $mBrand[0].Identifier "{bbbb2222-2222-2222-2222-222222222222}" "Matched exact Samsung USB GUID"

# 8e. Standalone NVMe/SATA NVRAM entry without USB keyword excluded; USB NVMe kept
$nvmeMixEntries = @(
    @{ Identifier = "{cccc3333-3333-3333-3333-333333333333}"; Description = "NVMe: WD Black SN850X"; Device = ""; Path = "" },
    @{ Identifier = "{dddd4444-4444-4444-4444-444444444444}"; Description = "UEFI: USB NVMe Enclosure"; Device = ""; Path = "" }
)
$mNvme = @(Find-MatchedUsbNvramEntries $nvmeMixEntries @() @() @() @() $true)
Assert-Eq $mNvme.Count 1 "Standalone NVMe excluded while USB NVMe Enclosure kept"
Assert-Eq $mNvme[0].Identifier "{dddd4444-4444-4444-4444-444444444444}" "USB NVMe Enclosure matched"

# 8f. Busy drive letters includes C:
$busyLtrs = Get-BusyDriveLetters
Assert-True ($busyLtrs.ContainsKey("C")) "Get-BusyDriveLetters includes C:"

# 8g. Target-exists conflict guard inside Invoke-BootloaderRenameInRoot
$tmpGuard = Join-Path ([System.IO.Path]::GetTempPath()) ("sid_aux_guard_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path "$tmpGuard\EFI" -Force | Out-Null
New-Item -ItemType Directory -Path "$tmpGuard\EFI_OLD" -Force | Out-Null
try {
    $rConf = Invoke-BootloaderRenameInRoot $tmpGuard "GPT_EFI" "DISABLE"
    Assert-Eq $rConf.Status "BLOCKED" "Rename blocked directly when EFI_OLD target already exists"
} finally {
    Remove-Item -LiteralPath $tmpGuard -Recurse -Force -ErrorAction SilentlyContinue
}

# 8h. Read-only file attribute + local special-char path + simulated network staging self-cleanup
$tmpScen = Join-Path ([System.IO.Path]::GetTempPath()) ("sid & (test) '" + (U "\uD55C\uAE00") + "'_" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmpScen -Force | Out-Null
$roBat = Join-Path $tmpScen "SID_Change_Aux_Tool.bat"
try {
    [System.IO.File]::WriteAllBytes($roBat, [System.IO.File]::ReadAllBytes($batPath))
    (Get-Item -LiteralPath $roBat).IsReadOnly = $true
    # Verify read-only copy can be read as ASCII and loaded cleanly without writing to source dir
    $beforeCount = @(Get-ChildItem -LiteralPath $tmpScen -Force).Count
    $roCode = [System.IO.File]::ReadAllText($roBat, [System.Text.Encoding]::ASCII)
    Assert-Eq $roCode.Length $code.Length "Read-only .bat in special-char folder read cleanly as ASCII"
    $afterCount = @(Get-ChildItem -LiteralPath $tmpScen -Force).Count
    Assert-Eq $afterCount $beforeCount "Zero files created in read-only source directory"

    # Simulate network staging runner (EncodedCommand reads staged copy, deletes it, preserves SELF_PATH)
    $stageTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("SID_Aux_Stage_" + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::WriteAllBytes($stageTmp, [System.IO.File]::ReadAllBytes($roBat))
    $q = [string][char]39
    $eT = $stageTmp.Replace($q, $q + $q)
    $eO = ("\\MAIN-PC\Share & (1)\SID_Change_Aux_Tool.bat").Replace($q, $q + $q)
    $run = '$p=' + $q + $eT + $q + ';$env:SELF_PATH=' + $q + $eO + $q + ';$env:SID_TOOL_STAGED=' + $q + '1' + $q + ';$env:SID_TOOL_TEST_MODE=' + $q + '1' + $q + ';try{$c=[IO.File]::ReadAllText($p,[Text.Encoding]::ASCII)}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue};Invoke-Expression $c;Write-Output ("LOADED_VER=" + $script:ToolVersion + "|ORIG=" + $env:SELF_PATH)'
    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($run))
    $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $stRes = Invoke-NativeOem $psExe ("-NoProfile -ExecutionPolicy Bypass -EncodedCommand " + $b64)
    Assert-Eq $stRes.ExitCode 0 "Simulated network-staged EncodedCommand runner exited cleanly"
    $expectedVer = ([System.IO.File]::ReadAllText((Join-Path $repoRoot "VERSION"))).Trim()
    Assert-True ($stRes.StdOut -match ("LOADED_VER=" + [regex]::Escape($expectedVer) + "\|ORIG=\\\\MAIN-PC\\Share & \(1\)\\SID_Change_Aux_Tool\.bat")) "Staged runner loaded full tool v$expectedVer in RAM and preserved UNC SELF_PATH"
    Assert-True (-not (Test-Path -LiteralPath $stageTmp)) "Staged temp file auto-deleted immediately after RAM load"
} finally {
    if (Test-Path -LiteralPath $roBat) { try { (Get-Item -LiteralPath $roBat).IsReadOnly = $false } catch {} }
    Remove-Item -LiteralPath $tmpScen -Recurse -Force -ErrorAction SilentlyContinue
}

# 8i. Invoke-NativeOem timeout guard
$toRes = Invoke-NativeOem "cmd.exe" "/c ping -n 4 127.0.0.1 >nul" $null 300
Assert-Eq $toRes.ExitCode -2 "Invoke-NativeOem enforces timeout cleanly without hanging"

# 8j. Wrapper structural audit (WinPE X: skip, fltmc fallback, network staging, no inner double-quotes in -Command)
$wrapperLines = ($code -split "`r?`n")[0..20] -join "`n"
Assert-True ($wrapperLines -match 'SystemDrive.*X:') "Wrapper skips UAC loop in WinPE (X:)"
Assert-True ($wrapperLines -match 'fltmc >nul 2>&1') "Wrapper includes fltmc admin fallback when LanmanServer is stopped"
Assert-True ($wrapperLines -match 'SID_Aux_Stage_') "Wrapper includes local staging for UNC/mapped network drives"
Assert-True ($wrapperLines -match '-STA') "Wrapper launches PowerShell in STA mode for WinForms & Clipboard"

Write-Host "`n=== 9. Multi-Signal BIOS Cross-Verification Tests ===" -ForegroundColor Cyan
# 9a. 3-Signal Secure Boot Cross-Check
$sbAgreeOff = Resolve-SecureBootCrossCheck "Off" "Off" "Off"
Assert-Eq $sbAgreeOff.State "Off" "SecureBoot 3x Off => Off"
Assert-Eq $sbAgreeOff.Confidence "CrossConfirmed" "SecureBoot 3x Off => CrossConfirmed"

$sbApiFailRegOn = Resolve-SecureBootCrossCheck "Unavailable" "On" "Unavailable"
Assert-Eq $sbApiFailRegOn.State "On" "SecureBoot API fail + Registry On => On (never silent false-negative!)"
Assert-Eq $sbApiFailRegOn.IsOnOrRisk $true "SecureBoot API fail + Registry On flags IsOnOrRisk=True"

$sbConflict = Resolve-SecureBootCrossCheck "Off" "Off" "On"
Assert-Eq $sbConflict.State "Conflict" "SecureBoot API/Reg Off vs WMI On => Conflict"
Assert-Eq $sbConflict.IsOnOrRisk $true "SecureBoot Conflict treated conservatively as Risk"

$sbAllUnk = Resolve-SecureBootCrossCheck "Unavailable" "Unavailable" "Unavailable"
Assert-Eq $sbAllUnk.State "Unknown" "SecureBoot all unavailable => Unknown (never silent Off)"

# 9b. HP WMI Primary vs Legacy/Port separation (eliminates Legacy USB Boot=Disable false positive!)
$hpMock = @(
    [PSCustomObject]@{ Name = "USB Storage Boot"; CurrentValue = ""; Value = "*Enable,Disable" },
    [PSCustomObject]@{ Name = "Legacy USB Boot"; CurrentValue = ""; Value = "*Disable,Enable" },
    [PSCustomObject]@{ Name = "Fast Boot"; CurrentValue = "Enable"; Value = "" },
    [PSCustomObject]@{ Name = "Configure Legacy Support and Secure Boot"; CurrentValue = "Legacy Support Disable and Secure Boot Disable"; Value = "" }
)
$hpRes = Resolve-HpBiosDiagnostics $hpMock
Assert-Eq $hpRes.UsbState "Enabled" "HP USB Storage Boot=Enable is NOT falsely overridden by Legacy USB Boot=Disable"
Assert-Eq $hpRes.FastBootWarn $true "HP Fast Boot=Enable flagged"
Assert-Eq $hpRes.SecureBootWmi "Off" "HP compound Secure Boot value parsed accurately as Off"
Assert-True ($hpRes.Evidence.Count -ge 4) "HP raw evidence collected for transparency ($($hpRes.Evidence.Count))"

# 9c. Dell WMI type-safe PossibleValues lookup (int vs string) + Minimal Fastboot
$dellMock = @(
    [PSCustomObject]@{ AttributeName = "EnableUsbBootSupport"; CurrentValue = @("2"); PossibleValues = @(1, 2); PossibleValuesDescription = @("Disabled", "Enabled") },
    [PSCustomObject]@{ AttributeName = "Fastboot"; CurrentValue = @("1"); PossibleValues = @(1, 2, 3); PossibleValuesDescription = @("Minimal", "Thorough", "Auto") },
    [PSCustomObject]@{ AttributeName = "SecureBoot"; CurrentValue = @("1"); PossibleValues = @(1, 2); PossibleValuesDescription = @("Disabled", "Enabled") }
)
$dellRes = Resolve-DellBiosDiagnostics $dellMock
Assert-Eq $dellRes.UsbState "Enabled" "Dell numeric PossibleValues (int vs string) resolved cleanly to Enabled"
Assert-Eq $dellRes.FastBootWarn $true "Dell Fastboot=Minimal flagged"
Assert-Eq $dellRes.SecureBootWmi "Off" "Dell SecureBoot resolved to Off"

# 9d. Cross-Check Verdict: WMI=Disabled vs NVRAM=Found => Conflict (not blind false-positive!)
$vConf = Resolve-BiosCrossCheckVerdict "HP" "Disabled" "HP WMI: USB=Disabled" $false $false "" $true 1 1
Assert-Eq $vConf.UsbBootState "Conflict" "WMI Disabled vs NVRAM USB match triggers Conflict instead of blind block"
Assert-Eq $vConf.HasSignalConflict $true "HasSignalConflict flagged true"
Assert-Eq $vConf.IsConfirmedBlocked $false "Conflict does not blindly hard-block USB boot"

# 9e. Rule #5 check: Samsung AMI never assumes ON even when NVRAM USB observed
$vSam = Resolve-BiosCrossCheckVerdict "Samsung" "Unknown" "" $false $false "" $true 1 1
Assert-Eq $vSam.UsbBootState "UnverifiableAMI" "Samsung AMI stays UnverifiableAMI (Rule #5 preserved)"
Assert-Eq $vSam.UsbBootConfidence "NvramObserved" "Samsung AMI with NVRAM USB marks NvramObserved"

# 9f. Port blocked check
$vPort = Resolve-BiosCrossCheckVerdict "HP" "Enabled" "HP WMI: USB Storage Boot=Enable" $false $true "HP WMI: External USB=Disable" $false 0 0
Assert-Eq $vPort.UsbBootState "PortBlocked" "Enabled USB Boot + Disabled USB Port flagged PortBlocked"
Assert-Eq $vPort.IsConfirmedBlocked $true "PortBlocked triggers BIOS guidance"

# 9g. Live Boot Mode Cross-Check
$liveBm = Get-BootModeDiagnostics
Assert-True ($liveBm.Mode -in @("UEFI","Legacy")) "Live Get-BootModeDiagnostics returned Mode=$($liveBm.Mode) ($($liveBm.Confidence))"

Write-Host "`n=== 10. Contextual Guidance Engine & Live WinForms GUI Smoke Test ===" -ForegroundColor Cyan
$mockUefiOk = [PSCustomObject]@{ BootMode = [PSCustomObject]@{ IsUefi = $true }; SecureBootState = "Off"; IsConfirmedBlocked = $false; HasSignalConflict = $false; UsbBootState = "Enabled"; FastBootWarn = $false; BiosHint = "Hint" }
$mockEfiClean = [PSCustomObject]@{ HasBlockingRisk = $false; SplitBoot = $false; ActionableConflictItems = @(); ConflictItems = @() }
$mockEfiRisk  = [PSCustomObject]@{ HasBlockingRisk = $true; SplitBoot = $false; ActionableConflictItems = @([PSCustomObject]@{ DiskNumber = 1 }); ConflictItems = @([PSCustomObject]@{ DiskNumber = 1 }) }
$mockUsbOne   = [PSCustomObject]@{ PhysicalUsbList = @([PSCustomObject]@{ DiskNumber = 2 }) }
$mockUsbNone  = [PSCustomObject]@{ PhysicalUsbList = @() }

$gStep1 = Get-PreSidGuidance $liveSys $mockEfiRisk $mockUefiOk $mockUsbOne @() $false
Assert-Eq $gStep1.RecommendedAction "STEP1_FIX" "Pre-SID guidance prioritizes STEP1_FIX when auxiliary bootloader found"

$gReady = Get-PreSidGuidance $liveSys $mockEfiClean $mockUefiOk $mockUsbOne @([PSCustomObject]@{ Identifier = "{1}" }) $false
Assert-Eq $gReady.RecommendedAction "USB_REBOOT" "Pre-SID guidance recommends USB_REBOOT when STEP 1 clean & USB matched"

$gHotPlug = Get-PreSidGuidance $liveSys $mockEfiClean $mockUefiOk $mockUsbOne @() $false
Assert-Eq $gHotPlug.RecommendedAction "ADV_BOOT" "Pre-SID guidance recommends ADV_BOOT on likely Hot-Plug"

$gNoUsb = Get-PreSidGuidance $liveSys $mockEfiClean $mockUefiOk $mockUsbNone @() $false
Assert-Eq $gNoUsb.RecommendedAction "PLUG_USB" "Pre-SID guidance recommends PLUG_USB when no physical USB connected"

$gPostLive = Get-PostSidGuidance $livePost
Assert-Eq $gPostLive.RecommendedAction "SPOOLER_RESET" "Post-SID guidance recommends SPOOLER_RESET ($($gPostLive.Level))"

# Live WinForms GUI construction, Asan Desktop UI layout audit (1040x720 & 960x640),
# UX writing check, real event closures, & ShowDialog -> Close (FormClosed) smoke test
$guiAvail = Test-WinFormsAvailable
Assert-True $guiAvail "WinForms GAC assemblies available on this Windows host"
if ($guiAvail) {
    try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::ThrowException) } catch {}

    # Verify diagnostic masking helper (Asan Desktop UI Section 6)
    $masked = ConvertTo-MaskedDiagnosticText 'Password=MySecret123; "token": "abc\"def"'
    Assert-True ($masked -notmatch "MySecret123" -and $masked -match "\[REDACTED\]") "ConvertTo-MaskedDiagnosticText redacts sensitive credentials"

    # Static check: zero Anchor=Right in GUI module (DPI safety rule)
    $guiSrc = [System.IO.File]::ReadAllText((Join-Path $repoRoot "modules\06_Gui_WinForms.ps1"))
    Assert-True ($guiSrc -notmatch "AnchorStyles\]::Right") "06_Gui_WinForms.ps1 uses zero Anchor=Right (DPI-safe Dock/RightFlowStrip)"

    function Invoke-LayoutAudit($formObj, $uiCtx, [string]$label) {
        $cnt = @{ Clips = 0; Overlaps = 0; SmallGrids = 0; SmallLogs = 0; MissingTips = 0; BadBtnCopy = 0 }
        $walk = {
            param($parent)
            $visBtns = New-Object System.Collections.ArrayList
            foreach ($ch in $parent.Controls) {
                if (-not $ch.Visible) { continue }
                if ($ch -is [System.Windows.Forms.Button]) {
                    [void]$visBtns.Add($ch)
                    if (($ch.Right -gt ($parent.ClientSize.Width + 3)) -or ($ch.Bottom -gt ($parent.ClientSize.Height + 3))) {
                        $cnt.Clips++
                        Write-Host ("  [CLIP $label] Btn='$($ch.Text)' Right=$($ch.Right)/$($parent.ClientSize.Width) Bottom=$($ch.Bottom)/$($parent.ClientSize.Height)") -ForegroundColor Red
                    }
                    if (-not $ch.Enabled) {
                        if (-not $uiCtx.DisabledReasons.ContainsKey($ch) -or [string]::IsNullOrWhiteSpace([string]$uiCtx.DisabledReasons[$ch])) {
                            $cnt.MissingTips++
                            Write-Host ("  [NO TIP $label] Disabled Btn='$($ch.Text)' has no registered reason tooltip") -ForegroundColor Red
                        }
                    }
                    if ($ch.Text -match '[\[\]\(\)!]') {
                        $cnt.BadBtnCopy++
                        Write-Host ("  [COPY $label] Button contains disallowed punctuation: '$($ch.Text)'") -ForegroundColor Red
                    }
                } elseif ($ch -is [System.Windows.Forms.DataGridView]) {
                    if ($ch.Height -lt 80) {
                        $cnt.SmallGrids++
                        Write-Host ("  [GRID $label] Grid '$($ch.Name)' Height=$($ch.Height) < 80") -ForegroundColor Red
                    }
                } elseif ($ch -is [System.Windows.Forms.TextBox] -and $ch.Multiline) {
                    if ($ch.Height -lt 40) {
                        $cnt.SmallLogs++
                        Write-Host ("  [TB $label] Multiline TextBox Height=$($ch.Height) < 40") -ForegroundColor Red
                    }
                }
                if ($ch.Controls.Count -gt 0) { & $walk $ch }
            }
            for ($i = 0; $i -lt $visBtns.Count; $i++) {
                for ($j = $i + 1; $j -lt $visBtns.Count; $j++) {
                    $r = [System.Drawing.Rectangle]::Intersect($visBtns[$i].Bounds, $visBtns[$j].Bounds)
                    if ($r.Width -gt 1 -and $r.Height -gt 1) {
                        $cnt.Overlaps++
                        Write-Host ("  [OVERLAP $label] '$($visBtns[$i].Text)' vs '$($visBtns[$j].Text)'") -ForegroundColor Red
                    }
                }
            }
        }
        & $walk $formObj
        return [PSCustomObject]$cnt
    }

    $guiBundle = $null
    try {
        $guiBundle = New-SidAuxMainForm $liveSys $true
        Assert-True ($null -ne $guiBundle.Form) "WinForms Main Form instantiated cleanly"
        Assert-True ($null -ne $guiBundle.Form.Icon) "Custom GDI+ vector app icon attached cleanly"
        Assert-Eq $guiBundle.TabControl.TabPages.Count 2 "Main Form has 2 numbered tabs (Pre-SID & Post-SID)"
        Assert-True ($guiBundle.DiskGrid.Rows.Count -ge 1) "STEP 1 DiskGrid populated ($($guiBundle.DiskGrid.Rows.Count) row(s))"
        Assert-True ($guiBundle.UsbGrid.Rows.Count -ge 1) "STEP 2 Unified UsbGrid populated ($($guiBundle.UsbGrid.Rows.Count) row(s))"
        Assert-True ($guiBundle.PrinterGrid.Rows.Count -ge 1) "Post-SID PrinterGrid populated ($($guiBundle.PrinterGrid.Rows.Count) row(s))"
        $repTxt = Format-BiosCrossCheckReport $liveSys $guiBundle.State.Step2Snap.BiosDiag $guiBundle.State.Step2Snap.UsbInfo $guiBundle.State.Step2Snap.MatchedEntries
        Assert-True ($repTxt.Length -gt 200) "BIOS Cross-Check detailed report generated ($($repTxt.Length) chars)"

        # Automated Layout Audit across 1040x720 and 960x640 (+ expanded log + critical banner)
        $guiBundle.Form.Opacity = 0
        $guiBundle.Form.ShowInTaskbar = $false
        $guiBundle.Form.Show()
        [System.Windows.Forms.Application]::DoEvents()

        foreach ($sz in @(@(1040, 720, "1040x720"), @(960, 640, "960x640"))) {
            $guiBundle.Form.Size = New-Object System.Drawing.Size($sz[0], $sz[1])
            foreach ($tabIdx in @(0, 1)) {
                $guiBundle.TabControl.SelectedIndex = $tabIdx
                $guiBundle.Form.PerformLayout()
                [System.Windows.Forms.Application]::DoEvents()
                $aud = Invoke-LayoutAudit $guiBundle.Form $guiBundle.UiContext ("$($sz[2])-Tab$($tabIdx+1)")
                Assert-Eq ($aud.Clips + $aud.Overlaps) 0 "Layout $($sz[2]) Tab $($tabIdx+1): zero button clipping/overlap"
                Assert-Eq $aud.SmallGrids 0 "Layout $($sz[2]) Tab $($tabIdx+1): all visible DataGridViews Height >= 80px"
                Assert-Eq $aud.MissingTips 0 "Layout $($sz[2]) Tab $($tabIdx+1): all disabled buttons have reason tooltips"
                Assert-Eq $aud.BadBtnCopy 0 "Layout $($sz[2]) Tab $($tabIdx+1): commercial UX copy (no brackets/parentheses/!)"
            }
        }

        # Worst-case stress audit: 960x640 + Log Expanded + Tab 1 & Tab 2
        $guiBundle.Form.Size = New-Object System.Drawing.Size(960, 640)
        $guiBundle.BtnToggleLog.PerformClick()
        foreach ($tabIdx in @(0, 1)) {
            $guiBundle.TabControl.SelectedIndex = $tabIdx
            $guiBundle.Form.PerformLayout()
            [System.Windows.Forms.Application]::DoEvents()
            $audEx = Invoke-LayoutAudit $guiBundle.Form $guiBundle.UiContext ("960x640-LogOpen-Tab$($tabIdx+1)")
            Assert-Eq ($audEx.Clips + $audEx.Overlaps + $audEx.SmallGrids + $audEx.SmallLogs) 0 "Stress layout 960x640 + Expanded Log Tab $($tabIdx+1): zero clipping/overlap/squished grids or log"
        }
        $guiBundle.BtnToggleLog.PerformClick() # collapse back

        # Exercise real event handlers AFTER New-SidAuxMainForm returned (catches closure/scope bugs!)
        $clickOk = $true
        try {
            $guiBundle.TabControl.SelectedIndex = 0
            $guiBundle.BtnTopRefresh.PerformClick()
            $guiBundle.BtnRescanUsb.PerformClick()
            $guiBundle.BtnPostRefresh.PerformClick()
            if ($guiBundle.BtnStep1Fold.Enabled) {
                $guiBundle.BtnStep1Fold.PerformClick()
                $guiBundle.BtnStep1Fold.PerformClick()
            }
            if ($guiBundle.DiskGrid.Rows.Count -gt 0) {
                $guiBundle.DiskGrid.Rows[0].Selected = $true
            }
        } catch {
            $clickOk = $false
            Write-Host ("  [CLICK ERR] " + $_.Exception.Message) -ForegroundColor Red
        }
        Assert-True $clickOk "Real button PerformClick() & DiskGrid SelectionChanged succeed after factory return"

        # Close first shown form cleanly & test fresh ShowDialog -> Close() -> OnFormClosed message loop!
        $guiBundle.Form.Close()
        $guiBundle.Form.Dispose()

        $guiBundle = New-SidAuxMainForm $liveSys $false
        $closeOk = $true
        $formClosedFired = $false
        $guiBundle.Form.Opacity = 0
        $guiBundle.Form.ShowInTaskbar = $false
        $guiBundle.Form.Add_Shown({ param($s) $s.Close() })
        $guiBundle.Form.Add_FormClosed({ $script:testFormClosedFlag = $true })
        $script:testFormClosedFlag = $false
        try {
            [void]$guiBundle.Form.ShowDialog()
            $formClosedFired = [bool]$script:testFormClosedFlag
        } catch {
            $closeOk = $false
            Write-Host ("  [CLOSE ERR] " + $_.Exception.Message) -ForegroundColor Red
        }
        Assert-True $closeOk "Real ShowDialog() -> Close() -> OnFormClosed completes with zero exceptions"
        Assert-True $formClosedFired "OnFormClosed event fired cleanly"
    } finally {
        if ($guiBundle -and $guiBundle.Form) { try { $guiBundle.Form.Dispose() } catch {} }
    }
}

Write-Host "`n=== 11. Systematic Versioning & Changelog Parity ===" -ForegroundColor Cyan
$verFile = Join-Path $repoRoot "VERSION"
$chgFile = Join-Path $repoRoot "CHANGELOG.md"
Assert-True (Test-Path -LiteralPath $verFile) "Root VERSION file exists"
$verVal = ([System.IO.File]::ReadAllText($verFile)).Trim()
Assert-True ($verVal -match '^\d+\.\d+\.\d+$') "VERSION follows SemVer MAJOR.MINOR.PATCH ($verVal)"
Assert-Eq $script:ToolVersion $verVal "Built SID_Change_Aux_Tool.bat ToolVersion matches VERSION ($verVal)"
Assert-True ($script:BuildDate -match '^\d{4}-\d{2}-\d{2}$') "Built BuildDate stamped accurately ($($script:BuildDate))"
Assert-True (-not [string]::IsNullOrWhiteSpace($script:BuildCommit)) "Built BuildCommit stamped ($($script:BuildCommit))"
Assert-True (Test-Path -LiteralPath $chgFile) "CHANGELOG.md exists"
$chgTxt = [System.IO.File]::ReadAllText($chgFile)
Assert-True ($chgTxt -match ("## \[v" + [regex]::Escape($verVal) + "\]")) "CHANGELOG.md contains release entry for [v$verVal]"

Write-Host "`n=== 12. Hospital Fleet Models, UASP Enclosures, Hidden ESP & HP G8/G9 Checkbox Regression Tests ===" -ForegroundColor Cyan
# 12a. Hospital fleet model profiling (S8, S9, H1, H2, H6, H8, D1, D8)
$profS8 = Resolve-HospitalModelProfile "Samsung" "Samsung" "Desktop PC" "Intel(R) Core(TM) i5-8500 CPU @ 3.00GHz" "C191329S8"
Assert-Eq $profS8.AssetCode "S8" "Hospital asset code S8 extracted from C191329S8"
Assert-Eq $profS8.GenFamily "SAMSUNG_DB400T" "S8 mapped to SAMSUNG_DB400T family"
Assert-True ($profS8.ModelName -match "DB400T8A") "Generic Samsung S8 resolved to DB400T8A model name"

$profH2 = Resolve-HospitalModelProfile "HP" "HP" "HP Elite Tower 800 G9 Desktop PC" "13th Gen Intel(R) Core(TM) i5-13500" "C250092H2"
Assert-Eq $profH2.GenFamily "HP_G8_G9" "HP Elite Tower 800 G9 (H2) mapped to HP_G8_G9 checkbox BIOS family"

$profH8 = Resolve-HospitalModelProfile "HP" "HP" "HP ProDesk 600 G3 TWR" "Intel(R) Core(TM) i5-7500 CPU" "C180600H8"
Assert-Eq $profH8.GenFamily "HP_PRODESK_G1_G5" "HP ProDesk 600 G3 (H8) mapped to HP_PRODESK_G1_G5 family"

$profD1 = Resolve-HospitalModelProfile "Dell" "Dell" "OptiPlex 5070" "Intel(R) Core(TM) i5-9500" "C210157D1"
Assert-Eq $profD1.GenFamily "DELL_OPTIPLEX_70" "Dell OptiPlex 5070 (D1) mapped to DELL_OPTIPLEX_70 family"

$profD8 = Resolve-HospitalModelProfile "Standard" "Standard" "Desktop PC" "14th Gen Intel(R) Core(TM) i5-14500" "C260101D8"
Assert-Eq $profD8.EffectiveVendor "Dell" "2026 replacement PC code C260101D8 resolves vendor Dell"
Assert-Eq $profD8.GenFamily "DELL_MODERN" "D8 mapped to DELL_MODERN family"

# 12b. UASP External NVMe/SATA enclosures ('HSEN 10G-NVME', 'JMicron Generic SATA', 'Realtek RTL9210B-CG') NOT falsely dropped by NVMe/SATA filter!
$uaspDisks = @(
    [PSCustomObject]@{ Number = 91; FriendlyName = "HSEN 10G-NVME SCSI Disk Device"; Size = 512GB; IsReadOnly = $false; PnpTokens = @("HSEN", "10G-NVME") },
    [PSCustomObject]@{ Number = 92; FriendlyName = "JMicron Generic SATA SCSI Disk Device"; Size = 256GB; IsReadOnly = $false; PnpTokens = @("JMicron", "Generic SATA") },
    [PSCustomObject]@{ Number = 93; FriendlyName = "Realtek RTL9210B-CG SCSI Disk Device"; Size = 512GB; IsReadOnly = $false; PnpTokens = @("Realtek", "RTL9210B-CG") }
)
$intDiskH2 = @(
    [PSCustomObject]@{ Number = 0; FriendlyName = "ST1000DM014-2UB10D"; Size = 1000GB; IsReadOnly = $false },
    [PSCustomObject]@{ Number = 1; FriendlyName = "SM2P41C8-256GC6"; Size = 256GB; IsReadOnly = $false }
)
$uaspInfo = Get-PhysicalUsbInfo $uaspDisks $intDiskH2
Assert-Eq $uaspInfo.PhysicalUsbList[0].Model "HSEN 10G-NVME" "SCSI Disk Device suffix stripped cleanly from HSEN 10G-NVME"
Assert-True ($uaspInfo.UsbStrictModelPatterns -contains "RTL9210") "Base bridge chip token RTL9210 extracted from RTL9210B-CG"

$uaspBcd = @(
    @{ Identifier = "{e1111111-1111-1111-1111-111111111111}"; Description = "UEFI: HSEN 10G-NVME, Partition 1"; Device = ""; Path = "\EFI\BOOT\BOOTX64.EFI" },
    @{ Identifier = "{e2222222-2222-2222-2222-222222222222}"; Description = "UEFI: JMicron Generic SATA, Partition 1"; Device = ""; Path = "\EFI\BOOT\BOOTX64.EFI" },
    @{ Identifier = "{e3333333-3333-3333-3333-333333333333}"; Description = "UEFI: RTL9210, Partition 2"; Device = ""; Path = "\EFI\BOOT\BOOTX64.EFI" },
    @{ Identifier = "{e4444444-4444-4444-4444-444444444444}"; Description = "UEFI: SM2P41C8-256GC6 (NVMe)"; Device = "partition=\Device\HarddiskVolume1"; Path = "\EFI\Microsoft\Boot\bootmgfw.efi" }
)
$mUasp = @(Find-MatchedUsbNvramEntries $uaspBcd @("partition=\Device\HarddiskVolume1") @() $uaspInfo.UsbStrictModelPatterns @() $true @("SM2P41C8"))
Assert-Eq $mUasp.Count 3 "All 3 UASP NVMe/SATA/RTL9210 enclosures matched while internal SM2P41C8 NVMe excluded"

# 12c. Hidden EFI partition Tier 1 match via \Device\HarddiskVolumeX & Zero-DLL Resolve-DosDeviceTarget + Phison 'UEFI: PMAP'
$liveNtC = Resolve-DosDeviceTarget "C:"
Assert-True ($liveNtC -match "^\\Device\\HarddiskVolume\d+$") "Zero-DLL Resolve-DosDeviceTarget mapped C: -> $liveNtC"
$hiddenEspBcd = @(
    @{ Identifier = "{f1111111-1111-1111-1111-111111111111}"; Description = "UEFI: PMAP"; Device = "partition=\Device\HarddiskVolume14"; Path = "\EFI\BOOT\BOOTX64.EFI" },
    @{ Identifier = "{f2222222-2222-2222-2222-222222222222}"; Description = "Windows Boot Manager"; Device = "partition=\Device\HarddiskVolume1"; Path = "\EFI\Microsoft\Boot\bootmgfw.efi" }
)
$mHiddenVol = @(Find-MatchedUsbNvramEntries $hiddenEspBcd @("partition=\Device\HarddiskVolume1") @("partition=\Device\HarddiskVolume14") @("ADATA") @() $true)
Assert-Eq $mHiddenVol.Count 1 "Hidden EFI partition (\Device\HarddiskVolume14) matched 'UEFI: PMAP' at Tier 1 without falsely matching HarddiskVolume1!"
Assert-True ([bool]($mHiddenVol.Count -eq 1 -and $mHiddenVol[0].IsExact)) "Hidden EFI kernel volume match marked IsExact=true"

# 12d. Generic AMI/Phison USB NVRAM fallback ('UEFI: Generic Flash Disk', 'UEFI: General UDisk')
$amiGenBcd = @(
    @{ Identifier = "{f3333333-3333-3333-3333-333333333333}"; Description = "UEFI: Generic Flash Disk 8.07"; Device = ""; Path = "" },
    @{ Identifier = "{f4444444-4444-4444-4444-444444444444}"; Description = "Dell SupportAssist OS Recovery"; Device = ""; Path = "" }
)
$mAmiGen = @(Find-MatchedUsbNvramEntries $amiGenBcd @() @() @() @() $true)
Assert-Eq $mAmiGen.Count 1 "Tier 4 matched 'UEFI: Generic Flash Disk' and excluded Dell SupportAssist OS Recovery"

# 12e. HP G8/G9 (H1/H2) Checkbox WMI values (*Checked,Unchecked) + Compound Legacy/SecureBoot precedence on ProDesk G1~G3 (H4/H6/H8)
$hpG9CheckboxMock = @(
    [PSCustomObject]@{ Name = "USB Storage Boot "; CurrentValue = ""; Value = "*Checked,Unchecked" },
    [PSCustomObject]@{ Name = "Fast Boot "; CurrentValue = ""; Value = "*Unchecked,Checked" },
    [PSCustomObject]@{ Name = "Secure Boot "; CurrentValue = ""; Value = "*Unchecked,Checked" }
)
$hpG9Res = Resolve-HpBiosDiagnostics $hpG9CheckboxMock
Assert-Eq $hpG9Res.UsbState "Enabled" "HP G8/G9 '*Checked,Unchecked' with trailing space parsed as UsbState=Enabled"
Assert-Eq $hpG9Res.FastBootWarn $false "HP G8/G9 Fast Boot '*Unchecked,Checked' parsed as Off"
Assert-Eq $hpG9Res.SecureBootWmi "Off" "HP G8/G9 Secure Boot '*Unchecked,Checked' parsed as Off"

$hpG3CompoundMock = @(
    [PSCustomObject]@{ Name = "Removable Media Boot"; CurrentValue = ""; Value = "Disable,*Enable" },
    [PSCustomObject]@{ Name = "Configure Legacy Support and Secure Boot"; CurrentValue = ""; Value = "*Legacy Support Enable and Secure Boot Disable,Legacy Support Disable and Secure Boot Enable" },
    [PSCustomObject]@{ Name = "Secure Boot"; CurrentValue = ""; Value = "*Enable,Disable" }
)
$hpG3Res = Resolve-HpBiosDiagnostics $hpG3CompoundMock
Assert-Eq $hpG3Res.UsbState "Enabled" "HP ProDesk G1~G3 'Removable Media Boot = Disable,*Enable' parsed as Enabled"
Assert-Eq $hpG3Res.SecureBootWmi "Off" "HP ProDesk G1~G3 compound Secure Boot Disable overrides grayed-out standalone Secure Boot=Enable"

# 12f. Dell AttributeValue + prefixed enum values (EnableUsbBoot / SecBoot) + 4-signal DeviceGuard SecureBoot
$dellD8Mock = @(
    [PSCustomObject]@{ AttributeName = "UsbBoot"; AttributeValue = "EnableUsbBoot" },
    [PSCustomObject]@{ AttributeName = "SecBoot"; AttributeValue = "Disabled" },
    [PSCustomObject]@{ AttributeName = "Fastboot"; AttributeValue = "Thorough" }
)
$dellD8Res = Resolve-DellBiosDiagnostics $dellD8Mock
Assert-Eq $dellD8Res.UsbState "Enabled" "Dell AttributeValue='EnableUsbBoot' parsed as Enabled"
Assert-Eq $dellD8Res.SecureBootWmi "Off" "Dell SecBoot='Disabled' parsed as Off"

$sb4Sig = Resolve-SecureBootCrossCheck "Unavailable" "Off" "Unavailable" "Off" $false
Assert-Eq $sb4Sig.State "Off" "4-signal SecureBoot (Reg Off + DeviceGuard Off) => Off"
Assert-Eq $sb4Sig.Confidence "CrossConfirmed" "Reg + DeviceGuard gives CrossConfirmed even when Confirm-SecureBootUEFI is unavailable"

$sbLegacy = Resolve-SecureBootCrossCheck "Unavailable" "Unavailable" "Unavailable" "Unavailable" $true
Assert-Eq $sbLegacy.State "Off" "Legacy MBR mode resolves SecureBoot as Off (LegacyNotSupported)"

$vSamNoMatch = Resolve-BiosCrossCheckVerdict "Samsung" "Unknown" "" $false $false "" $false 1 0
Assert-Eq $vSamNoMatch.UsbBootState "SuspectedDisabled" "Samsung with physical USB plugged in & 0 NVRAM matches flags SuspectedDisabled"

# 12g. v2.3.1 Recursive Review Regressions (H0 profile, ghost 'unknown' NVRAM, USB NIC exclusion, token boundaries, Rule #5 HP BootOrder, masking)
$profH0 = Resolve-HospitalModelProfile "HP" "HP" "Desktop PC" "Intel(R) Core(TM) i5-10500" "C200412H0"
Assert-Eq $profH0.AssetCode "H0" "Hospital asset code H0 extracted from C200412H0"
Assert-Eq $profH0.GenFamily "HP_G8_G9" "H0 mapped to modern HP checkbox BIOS family"

$ghostAndNicBcd = @(
    @{ Identifier = "{a1111111-1111-1111-1111-111111111111}"; Description = "UEFI: SanDisk, Partition 1"; Device = "unknown"; Path = "\EFI\BOOT\BOOTX64.EFI" },
    @{ Identifier = "{a2222222-2222-2222-2222-222222222222}"; Description = "UEFI: Realtek USB GbE Family Controller"; Device = ""; Path = "" },
    @{ Identifier = "{a3333333-3333-3333-3333-333333333333}"; Description = "UEFI: FooBAR SSD"; Device = ""; Path = "" }
)
$mGhostNic = @(Find-MatchedUsbNvramEntries $ghostAndNicBcd @() @() @("SanDisk", "BAR") @() $true)
Assert-Eq $mGhostNic.Count 0 "Ghost NVRAM entry (device=unknown), USB GbE NIC, and partial substring 'FooBAR' are all strictly excluded"

$noiseUsb = @([PSCustomObject]@{ Number = 95; FriendlyName = "Samsung BAR Plus 256GB"; Size = 256GB; IsReadOnly = $false })
$noiseInt = @([PSCustomObject]@{ Number = 0; FriendlyName = "Samsung SSD 980"; Size = 500GB; IsReadOnly = $false })
$noiseInfo = Get-PhysicalUsbInfo $noiseUsb $noiseInt
Assert-True ($noiseInfo.UsbStrictModelPatterns -notcontains "Plus" -and $noiseInfo.UsbStrictModelPatterns -notcontains "256GB") "Marketing/capacity noise tokens ('Plus', '256GB') excluded from UsbStrictModelPatterns"

$nonBootDataMatch = @(Find-MatchedUsbNvramEntries $genericEntries @() @() @("DataStick") @() $false)
Assert-Eq $nonBootDataMatch.Count 0 "Non-bootable data USB (AnyEfiReadyUsb=false) never triggers generic Tier 4 NVRAM match"

$hpOrderOnly = Resolve-HpBiosDiagnostics @() @([PSCustomObject]@{ Name = "UEFI Boot Order"; Value = "OS Boot Manager,USB Flash Drive" })
Assert-Eq $hpOrderOnly.UsbState "UnverifiableHP" "HP UEFI Boot Order alone stays UnverifiableHP (Rule #5 preserved)"

$hpSemiMock = @([PSCustomObject]@{ Name = "USB Storage Boot"; CurrentValue = ""; Value = "*Checked;Unchecked" })
Assert-Eq (Resolve-HpBiosDiagnostics $hpSemiMock).UsbState "Enabled" "HP semicolon-delimited '*Checked;Unchecked' parsed as Enabled"

$dellDepMock = @([PSCustomObject]@{ AttributeName = "SecureBoot"; AttributeValue = "DeployedMode" })
Assert-Eq (Resolve-DellBiosDiagnostics $dellDepMock).SecureBootWmi "On" "Dell SecureBoot='DeployedMode' parsed as On"

$maskAdv = ConvertTo-MaskedDiagnosticText 'password = "My Secret 123" {\"apikey\":\"tok_999\"} net use \\10.1.1.5\ipc$ Pass#123 /user:admin'
Assert-True ($maskAdv -notmatch "My Secret 123|tok_999|Pass#123") "Enhanced ConvertTo-MaskedDiagnosticText redacts quoted values, escaped JSON, and net use credentials"

$virtGuiSt = Format-BootloaderGuiStatus ([PSCustomObject]@{ State = "VIRTUAL_PROTECTED" })
Assert-Eq $virtGuiSt.Kind "Info" "VIRTUAL_PROTECTED disk formatted cleanly for GUI"

# ==============================================================================
# 13. v2.4.0 Multi-Partition WinPE USB (PhoenixPE / DISM++ / Self-Hosted) & Direct EFI Boot Regression Tests
# ==============================================================================
Write-Host "`n--- [13] v2.4.0 Multi-Partition WinPE USB & Direct EFI Boot Tests ---" -ForegroundColor Yellow

$peMockRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("SidAuxTest_v240_" + [guid]::NewGuid().ToString("N"))
try {
    $dirFatEfi = Join-Path $peMockRoot "Part_UEFI_NTFS"
    $dirPeNtfs = Join-Path $peMockRoot "Part_PhoenixPE"
    $dirDataExfat = Join-Path $peMockRoot "Part_UserData"
    $dirCustomEfi = Join-Path $peMockRoot "Part_CustomLoader"

    [void](New-Item -ItemType Directory -Path (Join-Path $dirFatEfi "EFI\Boot") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $dirFatEfi "EFI\Rufus") -Force)
    [System.IO.File]::WriteAllText((Join-Path $dirFatEfi "EFI\Boot\bootx64.efi"), "MZ")
    [System.IO.File]::WriteAllText((Join-Path $dirFatEfi "EFI\Rufus\ntfs_x64.efi"), "MZ")

    [void](New-Item -ItemType Directory -Path (Join-Path $dirPeNtfs "EFI\Microsoft\Boot") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $dirPeNtfs "sources") -Force)
    [System.IO.File]::WriteAllText((Join-Path $dirPeNtfs "EFI\Microsoft\Boot\bootmgfw.efi"), "MZ")
    [System.IO.File]::WriteAllText((Join-Path $dirPeNtfs "EFI\Microsoft\Boot\BCD"), "BCD")
    [System.IO.File]::WriteAllText((Join-Path $dirPeNtfs "sources\boot.wim"), "WIM")

    [void](New-Item -ItemType Directory -Path $dirDataExfat -Force)
    [System.IO.File]::WriteAllText((Join-Path $dirDataExfat "SID_Change_Aux_Tool.bat"), "@echo off")

    [void](New-Item -ItemType Directory -Path (Join-Path $dirCustomEfi "EFI\Rufus") -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $dirCustomEfi "EFI\PhoenixPE") -Force)
    [System.IO.File]::WriteAllText((Join-Path $dirCustomEfi "EFI\Rufus\ntfs_x64.efi"), "MZ")
    [System.IO.File]::WriteAllText((Join-Path $dirCustomEfi "EFI\PhoenixPE\memtest.efi"), "MZ")
    [System.IO.File]::WriteAllText((Join-Path $dirCustomEfi "EFI\PhoenixPE\PhoenixX64.efi"), "MZ")

    # 13a. Find-BestEfiBinaryOnRoot priority & memtest/Rufus driver filtering
    Assert-Eq (Find-BestEfiBinaryOnRoot $dirFatEfi) "\EFI\BOOT\BOOTX64.EFI" "Find-BestEfiBinaryOnRoot locates standard BOOTX64.EFI"
    Assert-Eq (Find-BestEfiBinaryOnRoot $dirPeNtfs) "\EFI\Microsoft\Boot\bootmgfw.efi" "Find-BestEfiBinaryOnRoot locates DISM++/bcdboot bootmgfw.efi"
    Assert-Eq (Find-BestEfiBinaryOnRoot $dirCustomEfi) "\EFI\PhoenixPE\PhoenixX64.efi" "Find-BestEfiBinaryOnRoot skips Rufus driver & memtest.efi to find custom PE loader"
    Assert-Eq (Find-BestEfiBinaryOnRoot $dirDataExfat) "" "Find-BestEfiBinaryOnRoot returns empty on plain user data partition"

    # 13b. Multi-partition PhoenixPE + Rufus UEFI_NTFS + Self-Hosted (General Space) USB layout
    $mockPhoenixParts = @(
        [PSCustomObject]@{ PartitionNumber = 1; DriveLetter = "L"; Size = 7GB; GptType = "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"; MbrType = $null; AccessPaths = @("L:\"); Guid = "{11111111-1111-1111-1111-111111111111}"; MockFileSystem = "NTFS"; MockLabel = "PhoenixPE_SID_260806"; MockProbeRoot = $dirPeNtfs; MockNtDevice = "partition=\Device\HarddiskVolume21" },
        [PSCustomObject]@{ PartitionNumber = 2; DriveLetter = "P"; Size = 21GB; GptType = "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"; MbrType = $null; AccessPaths = @("P:\"); Guid = "{22222222-2222-2222-2222-222222222222}"; MockFileSystem = "exFAT"; MockLabel = "Driver"; MockProbeRoot = $dirDataExfat; MockNtDevice = "partition=\Device\HarddiskVolume22" },
        [PSCustomObject]@{ PartitionNumber = 3; DriveLetter = "Q"; Size = 1MB; GptType = "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"; MbrType = $null; AccessPaths = @("Q:\"); Guid = "{33333333-3333-3333-3333-333333333333}"; MockFileSystem = "FAT"; MockLabel = "UEFI_NTFS"; MockProbeRoot = $dirFatEfi; MockNtDevice = "partition=\Device\HarddiskVolume23" }
    )
    $mockPhoenixDisk = [PSCustomObject]@{
        Number = 40; FriendlyName = "USB SanDisk 3.2Gen1"; Size = 30.7GB; IsReadOnly = $false; IsSelfHostUsb = $true; MockPartitions = $mockPhoenixParts
    }
    $mockOtherUsb = [PSCustomObject]@{
        Number = 10; FriendlyName = "Generic Flash Disk"; Size = 16GB; IsReadOnly = $false; IsSelfHostUsb = $false;
        MockPartitions = @(
            [PSCustomObject]@{ PartitionNumber = 1; DriveLetter = "K"; Size = 16GB; GptType = "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"; MbrType = $null; AccessPaths = @("K:\"); Guid = "{44444444-4444-4444-4444-444444444444}"; MockFileSystem = "exFAT"; MockLabel = "OfficeData"; MockProbeRoot = $dirDataExfat }
        )
    }

    $multiRes = Get-PhysicalUsbInfo @($mockOtherUsb, $mockPhoenixDisk) @()
    Assert-True $multiRes.AnyEfiReadyUsb "Multi-partition PhoenixPE USB sets AnyEfiReadyUsb=true"
    Assert-True $multiRes.AnyDirectBootUsb "Multi-partition PhoenixPE USB sets AnyDirectBootUsb=true"
    Assert-Eq $multiRes.PhysicalUsbList[0].DiskNumber 40 "Self-hosted WinPE USB (IsSelfHostUsb=true) sorted first ahead of lower DiskNumber"
    Assert-Eq $multiRes.PhysicalUsbList[0].BestBootDevice "partition=Q:" "Dedicated FAT UEFI_NTFS partition (Q:, Score 115) outranks NTFS PE partition (L:, Score 75)"
    Assert-Eq $multiRes.PhysicalUsbList[0].BestEfiRelPath "\EFI\BOOT\BOOTX64.EFI" "BestEfiRelPath resolved on Q: without mounting"
    Assert-True ($multiRes.PhysicalUsbList[0].DisplayLabel -match "PhoenixPE_SID_260806") "DisplayLabel appends WinPE volume label for instant recognition"
    Assert-True (-not $multiRes.PhysicalUsbList[1].IsEfiReady) "Plain exFAT data-only USB stays IsEfiReady=false"

    # 13c. DISM++ / DiskPart / Bootice hidden GPT Recovery ({de94bba4-...}) EFI + Boot Files + User Space (no drive letter on EFI!)
    $mockDismParts = @(
        [PSCustomObject]@{ PartitionNumber = 1; DriveLetter = ""; Size = 512MB; GptType = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"; MbrType = $null; AccessPaths = @("\\?\Volume{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}\"); Guid = "{aaaaaaaa-1111-2222-3333-444444444444}"; MockFileSystem = "FAT32"; MockLabel = "EFI"; MockProbeRoot = $dirFatEfi; MockNtDevice = "partition=\Device\HarddiskVolume31" },
        [PSCustomObject]@{ PartitionNumber = 2; DriveLetter = ""; Size = 6GB; GptType = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"; MbrType = $null; AccessPaths = @("\\?\Volume{bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee}\"); Guid = "{bbbbbbbb-1111-2222-3333-444444444444}"; MockFileSystem = "NTFS"; MockLabel = "WINPE"; MockProbeRoot = $dirPeNtfs; MockNtDevice = "partition=\Device\HarddiskVolume32" },
        [PSCustomObject]@{ PartitionNumber = 3; DriveLetter = "M"; Size = 50GB; GptType = "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"; MbrType = $null; AccessPaths = @("M:\"); Guid = "{cccccccc-1111-2222-3333-444444444444}"; MockFileSystem = "NTFS"; MockLabel = "ToolsSpace"; MockProbeRoot = $dirDataExfat; MockNtDevice = "partition=\Device\HarddiskVolume33" }
    )
    $mockDismDisk = [PSCustomObject]@{ Number = 50; FriendlyName = "Samsung T7 Shield"; Size = 58GB; IsReadOnly = $false; IsSelfHostUsb = $true; MockPartitions = $mockDismParts }
    $dismRes = Get-PhysicalUsbInfo @($mockDismDisk) @()
    Assert-True $dismRes.PhysicalUsbList[0].IsEfiReady "GPT Recovery-hidden ({de94bba4-...}) EFI+WinPE partitions are NOT skipped"
    Assert-True $dismRes.PhysicalUsbList[0].CanDirectEfiBoot "Unmounted hidden EFI resolved via NT Volume device supports Direct UEFI Boot"
    Assert-Eq $dismRes.PhysicalUsbList[0].BestBootDevice "partition=\Device\HarddiskVolume31" "Hidden EFI partition mapped directly to NT HarddiskVolume device"

    # 13d. DISM++ / bcdboot NVRAM entry named 'Windows Boot Manager' on USB partition MUST match Tier 1 while internal OS Boot Manager stays excluded
    $dismNvramEntries = @(
        [PSCustomObject]@{ Identifier = "{bootmgr}"; Description = "Windows Boot Manager"; Device = "partition=\Device\HarddiskVolume1"; Path = "\EFI\Microsoft\Boot\bootmgfw.efi" },
        [PSCustomObject]@{ Identifier = "{99999999-aaaa-bbbb-cccc-000000000001}"; Description = "Windows Boot Manager"; Device = "partition=\Device\HarddiskVolume1"; Path = "\EFI\Microsoft\Boot\bootmgfw.efi" },
        [PSCustomObject]@{ Identifier = "{99999999-aaaa-bbbb-cccc-000000000002}"; Description = "Windows Boot Manager"; Device = "partition=\Device\HarddiskVolume31"; Path = "\EFI\Microsoft\Boot\bootmgfw.efi" }
    )
    $dismMatched = @(Find-MatchedUsbNvramEntries $dismNvramEntries @("partition=\Device\HarddiskVolume1", "partition=C:") $dismRes.UsbDrivePatterns $dismRes.UsbStrictModelPatterns $dismRes.UsbPartPatterns $true)
    Assert-Eq $dismMatched.Count 1 "DISM++/bcdboot 'Windows Boot Manager' on USB partition matched (internal OS Boot Manager excluded)"
    Assert-Eq $dismMatched[0].Identifier "{99999999-aaaa-bbbb-cccc-000000000002}" "Exact USB DISM++ NVRAM GUID selected"

    # 13e. Get-PreSidGuidance recommends direct USB_REBOOT (Level=OK) when AnyDirectBootUsb=true even with 0 NVRAM matches
    $directDiagMock = [PSCustomObject]@{
        BootMode = [PSCustomObject]@{ Mode = "UEFI"; IsUefi = $true; Confidence = "High" }
        IsConfirmedBlocked = $false; SecureBootState = "Off"; FastBootWarn = $false; HasSignalConflict = $false
    }
    $okEfiRepMock = [PSCustomObject]@{ HasBlockingRisk = $false; SplitBoot = $false; Items = @(); ConflictItems = @(); ActionableConflictItems = @() }
    $directGuid = Get-PreSidGuidance ([PSCustomObject]@{ Vendor = "Standard" }) $okEfiRepMock $directDiagMock $multiRes @() $false
    Assert-Eq $directGuid.Level "OK" "Hot-plugged Direct-EFI USB yields Level=OK guidance"
    Assert-Eq $directGuid.RecommendedAction "USB_REBOOT" "Hot-plugged Direct-EFI USB recommends direct USB_REBOOT instead of ADV_BOOT detour"
} finally {
    if (Test-Path -LiteralPath $peMockRoot) {
        Remove-Item -LiteralPath $peMockRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
if ($script:Failed -eq 0) {
    Write-Host "[TEST SUMMARY] ALL $($script:Passed) TESTS PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[TEST SUMMARY] $($script:Passed) passed, $($script:Failed) FAILED!" -ForegroundColor Red
    exit 1
}
