# ==============================================================================
# Module 04: Physical USB Inspection, 4-Tier NVRAM Matching & Confirmed Reboot
# ==============================================================================

# Helper: Convert raw device token (e.g. 'partition=E:' or 'partition=\Device\HarddiskVolume1') into safe regex with digit boundary
function ConvertTo-SafeDeviceRegex([string]$token) {
 if ([string]::IsNullOrWhiteSpace($token)) { return "" }
 $t = $token.Trim()
 $escaped = [regex]::Escape($t)
 if ($t -match '(?i)HarddiskVolume\d+$') {
  return ($escaped + "(?!\d)")
 }
 return $escaped
}

# Helper: Build partition device tokens (DriveLetter + \Device\HarddiskVolumeX + Volume{GUID} + GPT Guid)
function Get-PartitionDevicePatterns($partObj) {
 $pats = New-Object System.Collections.ArrayList
 if (-not $partObj) { return @() }
 if ($partObj.DriveLetter) {
  $dl = ([string]$partObj.DriveLetter).Trim().TrimEnd(':')
  if ($dl) {
   [void]$pats.Add("partition=$($dl):")
   $ntFromLtr = Resolve-DosDeviceTarget "$($dl):"
   if ($ntFromLtr) { [void]$pats.Add(("partition=" + $ntFromLtr)) }
  }
 }
 if ($partObj.AccessPaths) {
  foreach ($ap in @($partObj.AccessPaths)) {
   $apStr = ([string]$ap).Trim()
   if ($apStr -match '^\\\\\?\\(Volume\{[^\}]+\})\\?$') {
    $volGuid = $matches[1]
    [void]$pats.Add($volGuid)
    $ntDev = Resolve-DosDeviceTarget $volGuid
    if ($ntDev) { [void]$pats.Add(("partition=" + $ntDev)) }
   }
  }
 }
 if ($partObj.Guid) {
  $gStr = ([string]$partObj.Guid).Trim()
  if ($gStr -and $gStr -ne "{00000000-0000-0000-0000-000000000000}") {
   [void]$pats.Add($gStr.Trim('{}'))
  }
 }
 return @($pats | Select-Object -Unique)
}

# Helper: Probe root path (drive letter or \\?\Volume{GUID}\) safely for UEFI / WinPE boot files
function Test-UsbBootFilesOnRoot([string]$rootPath) {
 if ([string]::IsNullOrWhiteSpace($rootPath)) { return $false }
 $r = $rootPath.TrimEnd('\')
 $relCandidates = @(
  "EFI\BOOT\BOOTX64.EFI",
  "EFI\BOOT\BOOTIA32.EFI",
  "EFI\BOOT\BOOTAA64.EFI",
  "EFI\BOOT\grubx64.efi",
  "EFI\Microsoft\Boot\bootmgfw.efi",
  "EFI\Microsoft\Boot\BCD",
  "bootmgr.efi",
  "sources\boot.wim",
  "PhoenixPE.cfg",
  "PhoenixPE.ini",
  "HBCD_PE.ini",
  "ventoy\ventoy.json"
 )
 foreach ($rel in $relCandidates) {
  try {
   if ([System.IO.File]::Exists(($r + "\" + $rel))) { return $true }
  } catch {}
 }
 try {
  if ([System.IO.File]::Exists(($r + "\bootmgr")) -and [System.IO.File]::Exists(($r + "\Boot\BCD"))) { return $true }
 } catch {}
 return $false
}

function Get-PhysicalUsbInfo([array]$usbDisks, [array]$internalDisks = @()) {
 $physicalUsbList = @()
 $usbDrivePatterns = @()
 $usbStrictModelPatterns = @()
 $usbPartPatterns = @()
 $anyEfiReadyUsb = $false
 $anyVentoy = $false

 # Collect words appearing in internal disk model names to prevent same-brand false matches (e.g. Samsung USB vs Samsung NVMe)
 $internalWords = @{}
 foreach ($idisk in $internalDisks) {
  if ($idisk -and $idisk.FriendlyName) {
   $iClean = (([string]$idisk.FriendlyName) -replace "(?i)\s+(SCSI|USB|SATA|NVMe|ATA)?\s*Disk\s+Device$", "").Trim()
   foreach ($iw in ($iClean -split "[\s_-]+")) {
    if ($iw.Length -ge 3) { $internalWords[$iw.ToLower()] = $true }
   }
  }
 }

 $genericNoiseRe = "^(?i)(USB|SSD|HDD|Disk|Drive|Device|General|Generic|Flash|Storage|Media|Mass|UFD|SCSI|SATA|NVMe|PCIE|ATA|3\.0|2\.0|3\.1|3\.2|3\.2Gen1|3\.2Gen2|Gen1|Gen2)$"
 $hasStorage = Test-StorageCmdletsAvailable
 foreach ($disk in $usbDisks) {
  $sizeGB = [math]::Round($disk.Size / 1GB, 1)
  $parts = if ($hasStorage) { @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue) } else { @() }
  $drvLetters = @()
  $mountedLettersOnly = @()
  $hasEfi = $false
  $diskIsVentoy = $false

  $rawModel = if ($disk.FriendlyName) { [string]$disk.FriendlyName } else { "USB Disk" }
  $cleanName = (($rawModel -replace "(?i)\s+(SCSI|USB|SATA|NVMe|ATA)?\s*Disk\s+Device$", "") -replace "^[\s_]+|[\s_]+$", "" -replace "\s{2,}", " ").Trim()
  if (-not $cleanName) { $cleanName = $rawModel.Trim() }

  if ($cleanName) {
   $usbStrictModelPatterns += [regex]::Escape($cleanName)
   $noLeadUsb = ($cleanName -replace "^(?i)USB\s+", "").Trim()
   if ($noLeadUsb -and $noLeadUsb -ne $cleanName -and $noLeadUsb.Length -ge 4) {
    $usbStrictModelPatterns += [regex]::Escape($noLeadUsb)
   }
   $rawCandidateWords = New-Object System.Collections.ArrayList
   foreach ($w in ($cleanName -split "[\s_]+")) { [void]$rawCandidateWords.Add($w) }
   foreach ($w in ($cleanName -split "[\s_-]+")) { [void]$rawCandidateWords.Add($w) }
   if ($disk.PSObject.Properties["PnpTokens"] -and $disk.PnpTokens) {
    foreach ($pt in @($disk.PnpTokens)) {
     if ($pt) {
      [void]$rawCandidateWords.Add([string]$pt)
      foreach ($pw in (([string]$pt) -split "[\s_-]+")) { [void]$rawCandidateWords.Add($pw) }
     }
    }
   }
   # Also add base chip root for bridge models like RTL9210B -> RTL9210
   foreach ($cw in @($rawCandidateWords)) {
    if ($cw -match "^([A-Za-z]{3,}\d{3,})[A-Za-z]$") {
     [void]$rawCandidateWords.Add($matches[1])
    }
   }
   foreach ($word in ($rawCandidateWords | Select-Object -Unique)) {
    $wTrim = ([string]$word).Trim()
    if ($wTrim.Length -ge 3 -and
        ($wTrim -notmatch $genericNoiseRe) -and
        (-not $internalWords.ContainsKey($wTrim.ToLower()))) {
     $usbStrictModelPatterns += [regex]::Escape($wTrim)
    }
   }
  }

  foreach ($p in $parts) {
   if ($p.GptType -eq $gptRecoveryGuid -or $p.GptType -eq $gptMsrGuid) { continue }
   $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
   $fs = if ($vol -and $vol.FileSystem) { [string]$vol.FileSystem } else { "" }
   $volLabel = if ($vol -and $vol.FileSystemLabel) { [string]$vol.FileSystemLabel } else { "" }
   if ($volLabel -match "(?i)^(VTOYEFI|VENTOY)$") { $diskIsVentoy = $true; $anyVentoy = $true }

   $isEfiGpt = ($p.GptType -eq $gptEfiGuid)
   $isEfiMbr = ($null -ne $p.MbrType -and ($mbrEfiFatTypes -contains [int]$p.MbrType))
   $isFatFs = ($fs -match "^(?i)(FAT|FAT12|FAT16|FAT32|exFAT)$")
   $isBootLabel = ($volLabel -match "(?i)^(VTOYEFI|VENTOY|UEFI_NTFS|PHOENIXPE|WINPE|ESD-USB|ESD-ISO|HBCD_PE|EFI|BOOT)$")

   # Check unmounted Volume{GUID} path for EFI boot files (works on hidden ESP / VTOYEFI without mounting a letter!)
   $hasHiddenBootFile = $false
   if (-not $p.DriveLetter -and $p.AccessPaths) {
    foreach ($ap in @($p.AccessPaths)) {
     $apStr = ([string]$ap).Trim()
     if ($apStr -match '^\\\\\?\\Volume\{[^\}]+\}\\?$') {
      if (Test-UsbBootFilesOnRoot $apStr) { $hasHiddenBootFile = $true; break }
     }
    }
   }
   # Small unmounted partition (512KB..4GB) on multi-partition USB (e.g. Ventoy GPT BasicData VTOYEFI or Rufus UEFI:NTFS where Get-Volume returns null)
   $isLikelyHiddenEsp = (-not $p.DriveLetter) -and ($parts.Count -ge 2 -or $isEfiGpt -or $isEfiMbr) -and ($p.Size -ge 512KB -and $p.Size -le 4GB)

   $partDevPats = @(Get-PartitionDevicePatterns $p)

   if ($p.DriveLetter) {
    $d = "$($p.DriveLetter):"
    $mountedLettersOnly += $d
    if (-not $volLabel) {
     try {
      $di = New-Object System.IO.DriveInfo ($p.DriveLetter)
      if ($di.IsReady -and $di.VolumeLabel) {
       $volLabel = $di.VolumeLabel
       if ($volLabel -match "(?i)^(VTOYEFI|VENTOY)$") { $diskIsVentoy = $true; $anyVentoy = $true }
       if ($volLabel -match "(?i)^(VTOYEFI|VENTOY|UEFI_NTFS|PHOENIXPE|WINPE|ESD-USB|ESD-ISO|HBCD_PE|EFI|BOOT)$") { $isBootLabel = $true }
      }
     } catch {}
    }
    if (Test-Path "$d\ventoy\ventoy.json") { $diskIsVentoy = $true; $anyVentoy = $true }
    $fsDisplay = if ($fs) { $fs } else { "Mounted" }
    $drvLetters += "$d($fsDisplay)"
    $hasBootFile = Test-UsbBootFilesOnRoot "$d\"
    if ($hasBootFile -or $isEfiGpt -or $isEfiMbr -or $isFatFs -or $isBootLabel) {
     $hasEfi = $true
     $anyEfiReadyUsb = $true
     $usbDrivePatterns += $partDevPats
     $usbPartPatterns += "(?:Partition|Part)\s+$($p.PartitionNumber)\b"
    }
   } elseif ($isEfiGpt -or $isEfiMbr -or $isFatFs -or $isBootLabel -or $hasHiddenBootFile -or $isLikelyHiddenEsp) {
    $partTag = if ($isEfiGpt) { "GPT-EFI" } elseif ($isEfiMbr) { "MBR-EFI/FAT" } elseif ($isFatFs) { "FAT" } else { "Boot/EFI" }
    $drvLetters += "Hidden-$partTag(Partition $($p.PartitionNumber))"
    $hasEfi = $true
    $anyEfiReadyUsb = $true
    $usbDrivePatterns += $partDevPats
    $usbPartPatterns += "(?:Partition|Part)\s+$($p.PartitionNumber)\b"
   }
  }

  $physicalUsbList += [PSCustomObject]@{
   DiskNumber = $disk.Number
   Model = $cleanName
   SizeGB = "$sizeGB GB"
   DriveSummary = if ($mountedLettersOnly.Count -gt 0) { ($mountedLettersOnly -join ",") } else { "Disk $($disk.Number)" }
   Partitions = ($drvLetters -join ", ")
   IsEfiReady = $hasEfi
   IsVentoy = $diskIsVentoy
   IsReadOnly = [bool]$disk.IsReadOnly
  }
 }

 return [PSCustomObject]@{
  PhysicalUsbList = $physicalUsbList
  UsbDrivePatterns = @($usbDrivePatterns | Select-Object -Unique)
  UsbStrictModelPatterns = @($usbStrictModelPatterns | Select-Object -Unique)
  UsbPartPatterns = @($usbPartPatterns | Select-Object -Unique)
  AnyEfiReadyUsb = $anyEfiReadyUsb
  IsVentoy = $anyVentoy
 }
}

function Find-MatchedUsbNvramEntries(
 [array]$bcdEntries,
 [array]$internalDriveLetters,
 [array]$usbDrivePatterns,
 [array]$usbStrictModelPatterns,
 [array]$usbPartPatterns,
 [bool]$anyEfiReadyUsb,
 [array]$internalModelPatterns = @()
) {
 $koBootMgr = U "Windows \uBD80\uD305 \uAD00\uB9AC\uC790"
 $excludeDesc = "(?i)(Windows Boot Manager|" + [regex]::Escape($koBootMgr) + "|PXE|IPV4|IPV6|IP4|IP6|HTTPs?\s*Boot|Network|Hard Drive \(SATA|Hard Drive \(NVMe|Onboard NIC|SupportAssist|Sure\s*Recover|BIOS\s*Connect|Firmware\s*Update|Diagnostics)"
 $internalPattern = if ($internalDriveLetters -and $internalDriveLetters.Count -gt 0) {
  (@($internalDriveLetters | ForEach-Object { ConvertTo-SafeDeviceRegex ([string]$_) } | Where-Object { $_ }) | Select-Object -Unique) -join "|"
 } else {
  ""
 }
 $usbDrvRegex = if ($usbDrivePatterns -and $usbDrivePatterns.Count -gt 0) {
  (@($usbDrivePatterns | ForEach-Object { ConvertTo-SafeDeviceRegex ([string]$_) } | Where-Object { $_ }) | Select-Object -Unique) -join "|"
 } else { "" }
 $usbModRegex = if ($usbStrictModelPatterns -and $usbStrictModelPatterns.Count -gt 0) { ($usbStrictModelPatterns | Select-Object -Unique) -join "|" } else { "" }
 $intModRegex = if ($internalModelPatterns -and $internalModelPatterns.Count -gt 0) { ($internalModelPatterns | Select-Object -Unique) -join "|" } else { "" }

 $candidateEntries = @($bcdEntries | Where-Object {
  $descStr = [string]$_.Description
  $devStr = [string]$_.Device
  $matchesUsbDev = ($usbDrvRegex -and ($devStr -match $usbDrvRegex))
  $matchesUsbMod = ($usbModRegex -and ($descStr -match $usbModRegex))
  $isOpticalNonUsb = ($descStr -match "(?i)CD/DVD|CD-ROM|Optical") -and ($descStr -notmatch "(?i)\bUSB\b")
  # Never exclude external enclosures like 'HSEN 10G-NVME' or 'JMicron Generic SATA' when they match a connected USB device/model!
  $isInternalBusWithoutUsb = (-not $matchesUsbDev) -and (-not $matchesUsbMod) -and ($descStr -match "(?i)\b(SATA\d*|NVMe\d*)\b") -and ($descStr -notmatch "(?i)\bUSB\b|External|Removable|Enclosure")
  $isInternalModelOnly = (-not $matchesUsbDev) -and (-not $matchesUsbMod) -and ($intModRegex -and ($descStr -match $intModRegex)) -and ($descStr -notmatch "(?i)\bUSB\b")

  $_.Identifier -ne "{fwbootmgr}" -and
  $_.Identifier -ne "{bootmgr}" -and
  ($descStr -notmatch $excludeDesc) -and
  (-not $isOpticalNonUsb) -and
  (-not $isInternalBusWithoutUsb) -and
  (-not $isInternalModelOnly) -and
  ($matchesUsbDev -or (-not $internalPattern) -or ($devStr -notmatch $internalPattern))
 })

 $matched = New-Object System.Collections.ArrayList
 $seenIds = @{}

 $addMatch = {
  param($entryObj, [string]$tierTag, [bool]$isExact)
  if ($entryObj -and $entryObj.Identifier -and -not $seenIds.ContainsKey($entryObj.Identifier)) {
   $seenIds[$entryObj.Identifier] = $true
   [void]$matched.Add([PSCustomObject]@{
    Identifier = $entryObj.Identifier
    Description = $entryObj.Description
    Device = $entryObj.Device
    Path = $entryObj.Path
    MatchTag = $tierTag
    IsExact = $isExact
   })
  }
 }

 # Tier 1: Exact drive letter / NT HarddiskVolume / Volume GUID match
 if ($usbDrvRegex) {
  foreach ($c in $candidateEntries) {
   if ([string]$c.Device -match $usbDrvRegex) {
    & $addMatch $c (U "\uC815\uD655 \uC77C\uCE58 - \uB4DC\uB77C\uC774\uBE0C") $true
   }
  }
 }

 # Tier 2: Exact disk model / bridge name match
 if ($usbModRegex) {
  foreach ($c in $candidateEntries) {
   if ([string]$c.Description -match $usbModRegex) {
    & $addMatch $c (U "\uC815\uD655 \uC77C\uCE58 - \uBAA8\uB378\uBA85") $true
   }
  }
 }

 # Tier 3: Partition number + UEFI/USB/Disk keyword match
 if ($matched.Count -eq 0 -and $usbPartPatterns -and $usbPartPatterns.Count -gt 0) {
  $partRegex = ($usbPartPatterns | Select-Object -Unique) -join "|"
  foreach ($c in $candidateEntries) {
   if ([string]$c.Description -match $partRegex -and [string]$c.Description -match "(?i)UEFI|USB|Partition|Part|Removable|PMAP|UDisk|Flash|Disk|Storage") {
    & $addMatch $c (U "\uD30C\uD2F0\uC158 \uC77C\uCE58") $true
   }
  }
 }

 # Tier 4: Generic UEFI USB NVRAM entry or removable \EFI\BOOT\BOOTX64.EFI fallback
 if ($matched.Count -eq 0 -and $anyEfiReadyUsb) {
  $genericUsbRegex = "(?i)(USB Hard Drive|USB Flash|USB Storage|USB Key|USB Disk|USB Device|USB Floppy|USB:|Removable|External|Mass Storage|\bUSB\b|\bPMAP\b|\bUDisk\b|Flash\s*Disk|Flash\s*Drive|Thumb\s*Drive|Memory\s*Stick|JetFlash|DataTraveler|Cruzer|Ventoy)"
  foreach ($c in $candidateEntries) {
   $cDesc = [string]$c.Description
   $cPath = [string]$c.Path
   if (($cDesc -match $genericUsbRegex) -or ($cPath -match "(?i)^\\EFI\\BOOT\\BOOT(X64|IA32|AA64)\.EFI$")) {
    & $addMatch $c (U "\uBC94\uC6A9 UEFI USB \uD56D\uBAA9") $false
   }
  }
 }

 return @($matched)
}

# Shared snapshot collector for STEP 2 (used by both WinForms GUI and Console TUI)
function Get-PreSidStep2Snapshot($sysInfo, $preClassifiedDisks = $null) {
 $bcdRes = Invoke-NativeOem "bcdedit.exe" "/enum firmware"
 $bcdOutput = @($bcdRes.Lines)
 $entries = @(Parse-BcdFirmwareLines $bcdOutput)

 $diskSplit = if ($null -ne $preClassifiedDisks) { $preClassifiedDisks } else { Get-ClassifiedDisks $false }
 $usbDisks = @($diskSplit.UsbDisks)
 $internalDisks = @($diskSplit.InternalDisks)
 $internalDrivePatterns = @()
 $internalModelPatterns = @()
 foreach ($idisk in $internalDisks) {
  if ($idisk -and $idisk.FriendlyName) {
   $iClean = (([string]$idisk.FriendlyName) -replace "(?i)\s+(SCSI|USB|SATA|NVMe|ATA)?\s*Disk\s+Device$", "").Trim()
   if ($iClean.Length -ge 4) { $internalModelPatterns += [regex]::Escape($iClean) }
   foreach ($itok in ($iClean -split "[\s_-]+")) {
    if ($itok.Length -ge 5 -and $itok -match "\d" -and $itok -notmatch "^(?i)(SATA|NVMe|PCIe|Gen\d)") {
     $internalModelPatterns += [regex]::Escape($itok)
    }
   }
  }
 }
 $internalDiskNums = @($internalDisks | Select-Object -ExpandProperty Number)
 if ($internalDiskNums.Count -gt 0 -and (Test-StorageCmdletsAvailable)) {
  foreach ($ip in @(Get-Partition -DiskNumber $internalDiskNums -ErrorAction SilentlyContinue)) {
   $internalDrivePatterns += @(Get-PartitionDevicePatterns $ip)
  }
 }

 $usbInfo = Get-PhysicalUsbInfo $usbDisks $internalDisks
 $matchedEntries = @()
 if ($usbDisks.Count -gt 0) {
  $allowGenericFallback = ([bool]$usbInfo.AnyEfiReadyUsb -or ($usbDisks.Count -gt 0))
  $matchedEntries = @(Find-MatchedUsbNvramEntries `
   $entries `
   $internalDrivePatterns `
   $usbInfo.UsbDrivePatterns `
   $usbInfo.UsbStrictModelPatterns `
   $usbInfo.UsbPartPatterns `
   $allowGenericFallback `
   $internalModelPatterns)
 }

 $diag = Get-BiosDiagnostics $sysInfo $usbDisks $entries $matchedEntries.Count

 return [PSCustomObject]@{
  BcdOutput = $bcdOutput
  BcdEntries = $entries
  UsbDisks = $usbDisks
  InternalDisks = $internalDisks
  InternalDriveLetters = $internalDrivePatterns
  UsbInfo = $usbInfo
  MatchedEntries = $matchedEntries
  BiosDiag = $diag
 }
}

function Invoke-PreSidUsbBootStep($sysInfo, [bool]$step1Bypassed) {
 $gate1Ignored = $false

 while ($true) {
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host (U " [\uC0AC\uC804 \uC791\uC5C5 - STEP 2/2] BIOS \uCC28\uB2E8 \uC694\uC18C \uC810\uAC80 \uBC0F WinPE USB \uBD80\uD305") -ForegroundColor Cyan
  Write-Host ("   System : [" + $sysInfo.Vendor + "] (" + $sysInfo.ModelName + ")") -ForegroundColor DarkCyan
  Write-Host "==================================================================" -ForegroundColor Cyan

  $snap = Get-PreSidStep2Snapshot $sysInfo
  $bcdOutput = $snap.BcdOutput
  $entries = $snap.BcdEntries
  $usbDisks = $snap.UsbDisks
  $internalDisks = $snap.InternalDisks
  $usbInfo = $snap.UsbInfo
  $matchedEntries = $snap.MatchedEntries
  $diag = $snap.BiosDiag

  Show-BiosStatusDashboard $diag $step1Bypassed

  if (-not $gate1Ignored) {
   $isVty = ($null -ne $usbInfo.PSObject.Properties["IsVentoy"] -and [bool]$usbInfo.IsVentoy)
   $g1 = Invoke-Gate1Check $diag $bcdOutput $matchedEntries.Count $isVty
   if ($g1 -eq "RETURN_MAIN") { return }
   $gate1Ignored = $true
  }

  # No physical USB detected
  if ($usbDisks.Count -eq 0) {
   Write-Host (U "`n[\uC624\uB958] \uD604\uC7AC \uBB3C\uB9AC\uC801\uC73C\uB85C \uC5F0\uACB0\uB41C \uC678\uC7A5 USB \uC800\uC7A5\uC7A5\uCE58\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
   Write-Host (U "(\uB0B4\uC7A5 SSD/HDD \uBC0F NVRAM \uACFC\uAC70 \uC720\uB839 \uAE30\uB85D\uC740 \uC790\uB3D9 \uC81C\uC678\uB429\uB2C8\uB2E4.)") -ForegroundColor Gray
   $rescanNow = $false
   while ($true) {
    Write-Host (U "`n[R] \uB2E4\uC2DC \uC2A4\uCE94 | [B] BIOS \uC124\uC815 | [E] \uB0B4\uC7A5 \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [M/Enter] \uBA54\uC778 \uBA54\uB274") -ForegroundColor DarkGray
    $noUsbChoice = (Read-Host (U "\uC120\uD0DD")).Trim()
    if ($noUsbChoice -match "^[rR]$") { $rescanNow = $true; break }
    elseif ($noUsbChoice -match "^[bB]$") { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
    elseif ($noUsbChoice -match "^[eE]$") { Show-BootloaderManager $false }
    elseif ($noUsbChoice -match "^[dD]$") { Show-BcdDebug $bcdOutput }
    elseif ($noUsbChoice -match "^[lL]$") { Show-DiskDebug }
    elseif ($noUsbChoice -eq "" -or $noUsbChoice -match "^[mMqQ]$") { return }
   }
   if ($rescanNow) { continue }
   return
  }

  # Display physical USB partitions
  Write-Host (U "`n[STEP 2-1] \uD604\uC7AC \uC5F0\uACB0\uB41C \uBB3C\uB9AC USB \uB514\uC2A4\uD06C \uBAA9\uB85D:") -ForegroundColor Cyan
  foreach ($u in $usbInfo.PhysicalUsbList) {
   $efiTag = if ($u.IsEfiReady) { U "UEFI \uBD80\uD305 \uAC00\uB2A5" } else { U "EFI \uD30C\uD2F0\uC158 \uBBF8\uD655\uC778" }
   $roTag = if ($u.IsReadOnly) { " [" + (U "\uC77D\uAE30 \uC804\uC6A9") + "]" } else { "" }
   Write-Host (" - Disk " + $u.DiskNumber + " : " + $u.Model + " [" + $u.SizeGB + "]" + $roTag + " | " + $u.Partitions + " -> (" + $efiTag + ")") -ForegroundColor White
  }

  # Gate 2: Physical USB found, but 0 matching NVRAM entries
  if ($matchedEntries.Count -eq 0) {
   $isLikelyHotPlug = (($diag.UsbBootState -eq "Enabled" -or [bool]$usbInfo.AnyEfiReadyUsb) -and -not $diag.IsConfirmedBlocked -and -not $diag.FastBootWarn)
   $rescanNow = $false
   while ($true) {
    Write-Host "`n==================================================================" -ForegroundColor Yellow
    if ($isLikelyHotPlug) {
     Write-Host (U " [\uC548\uB0B4] \uBB3C\uB9AC USB\uB294 \uC778\uC2DD\uB418\uC5C8\uC73C\uB098 \uD604\uC7AC NVRAM \uBAA9\uB85D\uC5D0 \uB4F1\uB85D\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
     Write-Host (U " - BIOS USB Boot\uAC00 \uCF1C\uC838 \uC788\uC73C\uBBC0\uB85C Windows \uBD80\uD305 \uD6C4 USB\uB97C \uC5F0\uACB0(Hot-Plug)\uD55C \uC0C1\uD0DC\uC77C \uAC00\uB2A5\uC131\uC774 \uB192\uC2B5\uB2C8\uB2E4.") -ForegroundColor Cyan
     Write-Host ""
     Write-Host (U " [Enter \uB610\uB294 O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305 (\uAD8C\uC7A5)") -ForegroundColor Green
     Write-Host (U " [B] BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Cyan
    } else {
     Write-Host (U " [\uACBD\uACE0] \uBB3C\uB9AC\uC801 USB\uB294 \uC778\uC2DD\uB418\uC5C8\uC73C\uB098 BIOS(NVRAM) \uBD80\uD305 \uBAA9\uB85D\uC5D0 \uC5C6\uC2B5\uB2C8\uB2E4!") -ForegroundColor Red
     Write-Host (" - " + $diag.BiosHint) -ForegroundColor Yellow
     Write-Host ""
     Write-Host (U " [Enter \uB610\uB294 B] \uC989\uC2DC BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305 (\uAD8C\uC7A5 - Fast Boot / USB Boot \uD655\uC778)") -ForegroundColor Cyan
     Write-Host (U " [O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Green
    }
    Write-Host (U " [R] \uB2E4\uC2DC \uC2A4\uCE94 | [E] \uB0B4\uC7A5 \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [M] \uBA54\uC778 \uBA54\uB274") -ForegroundColor Gray
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

    $defaultHint = if ($isLikelyHotPlug) { U "Enter=\uC7A5\uCE58 \uC0AC\uC6A9 \uBA54\uB274" } else { U "Enter=BIOS \uC9C4\uC785" }
    $fbChoice = (Read-Host ((U "\uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694 (") + $defaultHint + ")")).Trim()

    if ($fbChoice -match "^[rR]$") { $rescanNow = $true; break }
    elseif ($fbChoice -match "^[eE]$") { Show-BootloaderManager $false; continue }
    elseif ($fbChoice -match "^[dD]$") { Show-BcdDebug $bcdOutput; continue }
    elseif ($fbChoice -match "^[lL]$") { Show-DiskDebug; continue }
    elseif ($fbChoice -eq "") {
     if ($isLikelyHotPlug) { $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot" }
     else { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
    } elseif ($fbChoice -match "^[oO]$") { $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot" }
    elseif ($fbChoice -match "^[bB]$") { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
    elseif ($fbChoice -match "^[mMqQ]$") { return }
   }
   if ($rescanNow) { continue }
   return
  }

  # Verified USB targets: always require explicit user confirmation
  $selectedTarget = $null
  $rescanNow = $false
  while ($true) {
   Write-Host "`n==================================================================" -ForegroundColor Cyan
   Write-Host (U "[STEP 2-2] \uBD80\uD305 \uAC00\uB2A5\uD55C UEFI USB \uD56D\uBAA9\uC774 \uD655\uC778\uB418\uC5C8\uC2B5\uB2C8\uB2E4:") -ForegroundColor Green
   for ($i = 0; $i -lt $matchedEntries.Count; $i++) {
    $devInfo = if ($matchedEntries[$i].Device) { $matchedEntries[$i].Device } else { "UEFI NVRAM" }
    $tagColor = if ($matchedEntries[$i].IsExact) { "Green" } else { "Yellow" }
    Write-Host (" [" + ($i + 1) + "] [" + $matchedEntries[$i].MatchTag + "] " + $matchedEntries[$i].Description) -ForegroundColor $tagColor
    Write-Host ("     -> Device: " + $devInfo + " | GUID: " + $matchedEntries[$i].Identifier) -ForegroundColor DarkGray
   }

   Write-Host "`n------------------------------------------------------------------" -ForegroundColor DarkGray
   if ($matchedEntries.Count -eq 1) {
    Write-Host (U " [Enter \uB610\uB294 1] \uC704 [1]\uBC88 USB \uB514\uC2A4\uD06C\uAC00 \uB9DE\uC73C\uBA74 \uC989\uC2DC \uC7AC\uBD80\uD305") -ForegroundColor Green
   } else {
    Write-Host (" [1~" + $matchedEntries.Count + (U "] \uBD80\uD305\uD560 USB \uBC88\uD638 \uC785\uB825 \uD6C4 \uC989\uC2DC \uC7AC\uBD80\uD305")) -ForegroundColor Green
   }
   Write-Host (U " [O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uBA54\uB274\uB85C \uC7AC\uBD80\uD305")
   Write-Host (U " [B] BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305")
   Write-Host (U " [R] \uB2E4\uC2DC \uC2A4\uCE94 | [E] \uB0B4\uC7A5 \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8") -ForegroundColor DarkCyan
   Write-Host (U " [M] \uBA54\uC778 \uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uAE30") -ForegroundColor Gray
   Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

   $choice = (Read-Host (U "\uC2E4\uD589\uD560 \uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694")).Trim()

   if ($choice -match "^[rR]$") { $rescanNow = $true; break }
   elseif ($choice -match "^[eE]$") { Show-BootloaderManager $false; continue }
   elseif ($choice -match "^[dD]$") { Show-BcdDebug $bcdOutput; continue }
   elseif ($choice -match "^[lL]$") { Show-DiskDebug; continue }
   elseif ($choice -eq "" -and $matchedEntries.Count -eq 1) { $selectedTarget = $matchedEntries[0]; break }
   elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $matchedEntries.Count) { $selectedTarget = $matchedEntries[[int]$choice - 1]; break }
   elseif ($choice -match "^[oO]$") { $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot" }
   elseif ($choice -match "^[bB]$") { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
   elseif ($choice -match "^[mMqQ]$") { return }
  }

  if ($rescanNow) { continue }
  if (-not $selectedTarget) { return }

  # Set 1-time bootsequence and reboot
  $setRes = Invoke-NativeOem "bcdedit.exe" ("/set {fwbootmgr} bootsequence " + $selectedTarget.Identifier)
  if ($setRes.ExitCode -eq 0) {
   Write-Host ("`n-> [" + $selectedTarget.Description + (U "] \uBD80\uD305 \uC21C\uC11C \uC9C0\uC815 \uC644\uB8CC! \uC989\uC2DC \uC7AC\uBD80\uD305\uD569\uB2C8\uB2E4...")) -ForegroundColor Cyan
   $null = Invoke-SafeReboot "/r /f /t 0" "USB One-Time Boot"
   return
  } else {
   Write-Host (U "`n[\uC624\uB958] NVRAM \uBD80\uD305 \uC21C\uC11C \uBCC0\uACBD \uC2E4\uD328!") -ForegroundColor Red
   Write-Host ((U "\uC0C1\uC138 \uCD9C\uB825: ") + ($setRes.Lines -join " ")) -ForegroundColor Yellow
   Write-Host (U "[O] Windows \uC7A5\uCE58 \uC0AC\uC6A9 \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305 | [Enter/M] \uBA54\uC778 \uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uAE30") -ForegroundColor Cyan
   $errChoice = (Read-Host (U "\uC120\uD0DD")).Trim()
   if ($errChoice -match "^[oO]$") {
    $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot"
   }
   return
  }
 }
}
