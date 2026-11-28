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
  $dl = ([string]$partObj.DriveLetter).Trim([char]0).Trim().TrimEnd(':')
  if ($dl -and ($dl -match '^[A-Za-z]$')) {
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

# Helper: Read-only 512-byte VBR probe for hidden/unmounted USB partitions where Get-Volume returns null
function Get-RawPartitionFsHint([int]$diskNum, [int64]$offset) {
 if ($diskNum -lt 0 -or $offset -le 0) { return "" }
 $fsStream = $null
 try {
  $fsStream = New-Object System.IO.FileStream("\\.\PhysicalDrive$diskNum", [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  [void]$fsStream.Seek($offset, [System.IO.SeekOrigin]::Begin)
  $buf = New-Object byte[] 512
  $read = $fsStream.Read($buf, 0, 512)
  if ($read -ge 90 -and $buf[510] -eq 0x55 -and $buf[511] -eq 0xAA) {
   $oem = [System.Text.Encoding]::ASCII.GetString($buf, 3, 8)
   $fat16 = [System.Text.Encoding]::ASCII.GetString($buf, 54, 5)
   $fat32 = [System.Text.Encoding]::ASCII.GetString($buf, 82, 5)
   if ($fat32 -eq "FAT32") { return "FAT32" }
   if ($fat16 -match "^FAT1[26]" -or $fat16 -match "^FAT\s") { return "FAT16" }
   if ($oem -match "^EXFAT") { return "exFAT" }
   if ($oem -match "^NTFS") { return "NTFS" }
  }
 } catch {} finally {
  if ($fsStream) { try { $fsStream.Dispose() } catch {} }
 }
 return ""
}

# Helper: Locate the best UEFI .efi bootloader binary on a mounted root or \\?\Volume{GUID}\ root
function Find-BestEfiBinaryOnRoot([string]$rootPath) {
 if ([string]::IsNullOrWhiteSpace($rootPath)) { return "" }
 $r = $rootPath.TrimEnd('\')
 $orderedEfiCandidates = @(
  "EFI\BOOT\BOOTX64.EFI",
  "EFI\Microsoft\Boot\bootmgfw.efi",
  "EFI\BOOT\grubx64.efi",
  "EFI\BOOT\BOOTAA64.EFI",
  "EFI\BOOT\BOOTIA32.EFI"
 )
 foreach ($rel in $orderedEfiCandidates) {
  try {
   if ([System.IO.File]::Exists(($r + "\" + $rel))) { return ("\" + $rel) }
  } catch {}
 }
 try {
  if ([System.IO.File]::Exists(($r + "\bootmgr.efi")) -and
      ([System.IO.File]::Exists(($r + "\EFI\Microsoft\Boot\BCD")) -or [System.IO.File]::Exists(($r + "\Boot\BCD")))) {
   return "\bootmgr.efi"
  }
 } catch {}
 # 2-level scan under \EFI\* for custom PhoenixPE / DISM++ / Linux shim EFI binaries
 try {
  $efiRoot = $r + "\EFI"
  if ([System.IO.Directory]::Exists($efiRoot)) {
   foreach ($subDir in @([System.IO.Directory]::GetDirectories($efiRoot))) {
    $subLeaf = [System.IO.Path]::GetFileName($subDir)
    if ($subLeaf -match "^(?i)Rufus$") { continue }
    foreach ($ef in @([System.IO.Directory]::GetFiles($subDir, "*.efi"))) {
     $fn = [System.IO.Path]::GetFileName($ef)
     if ($fn -notmatch "^(?i)memtest\.efi$") {
      return ("\EFI\" + $subLeaf + "\" + $fn)
     }
    }
   }
  }
 } catch {}
 return ""
}

# Helper: Check if a partition root holds WinPE / Ventoy / Rufus / installer payload markers
function Test-WinPePayloadOnRoot([string]$rootPath) {
 if ([string]::IsNullOrWhiteSpace($rootPath)) { return $false }
 $r = $rootPath.TrimEnd('\')
 $markers = @(
  "sources\boot.wim",
  "sources\install.wim",
  "sources\install.esd",
  "EFI\Microsoft\Boot\BCD",
  "bootmgr.efi",
  "PhoenixPE.cfg",
  "PhoenixPE.ini",
  "HBCD_PE.ini",
  "ventoy\ventoy.json",
  "ventoy.dat",
  "EFI\Rufus\ntfs_x64.efi"
 )
 foreach ($m in $markers) {
  try { if ([System.IO.File]::Exists(($r + "\" + $m))) { return $true } } catch {}
 }
 try {
  if ([System.IO.File]::Exists(($r + "\bootmgr")) -and [System.IO.File]::Exists(($r + "\Boot\BCD"))) { return $true }
  if ([System.IO.Directory]::Exists(($r + "\ventoy")) -or [System.IO.Directory]::Exists(($r + "\EFI\Rufus"))) { return $true }
  if ([System.IO.Directory]::Exists(($r + "\sources"))) {
   $wims = @([System.IO.Directory]::GetFiles(($r + "\sources"), "*.wim"))
   if ($wims.Count -gt 0) { return $true }
  }
 } catch {}
 return $false
}

# Helper: Probe root path (drive letter or \\?\Volume{GUID}\) safely for UEFI / WinPE boot files
function Test-UsbBootFilesOnRoot([string]$rootPath) {
 if ([string]::IsNullOrWhiteSpace($rootPath)) { return $false }
 if (Find-BestEfiBinaryOnRoot $rootPath) { return $true }
 if (Test-WinPePayloadOnRoot $rootPath) { return $true }
 $r = $rootPath.TrimEnd('\')
 try {
  if ([System.IO.Directory]::Exists(($r + "\EFI\BOOT"))) { return $true }
 } catch {}
 return $false
}

function Get-PhysicalUsbInfo([array]$usbDisks, [array]$internalDisks = @()) {
 $rawUsbItems = @()
 $usbDrivePatterns = @()
 $usbStrictModelPatterns = @()
 $usbPartPatterns = @()
 $anyEfiReadyUsb = $false
 $anyDirectBootUsb = $false
 $anyVentoy = $false
 $selfLoc = if (Get-Command Get-SelfHostLocationInfo -ErrorAction SilentlyContinue) { Get-SelfHostLocationInfo } else { [PSCustomObject]@{ DiskNumber = -1; DriveLetter = "" } }

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

 $genericNoiseRe = "^(?i)(USB|SSD|HDD|Disk|Drive|Device|General|Generic|Flash|Storage|Media|Mass|UFD|SCSI|SATA|NVMe|PCIE|ATA|Realtek|Pro|Plus|Max|Mini|Ultra|Extreme|Evo|Basic|Portable|External|Pocket|Shield|Gaming|Super|Speed|Dual|Type|TypeC|Corp|Inc|Ltd|Tech|3\.0|2\.0|3\.1|3\.2|3\.2Gen1|3\.2Gen2|Gen1|Gen2|Gen3|Gen4|\d+(\.\d+)?|\d+\s*[KMGT]B|\d+G)$"
 $hasStorage = Test-StorageCmdletsAvailable
 foreach ($disk in $usbDisks) {
  $dNum = [int]$disk.Number
  $sizeGB = [math]::Round($disk.Size / 1GB, 1)
  $hasMockParts = ($null -ne $disk.PSObject.Properties["MockPartitions"] -and $null -ne $disk.MockPartitions)
  $parts = if ($hasMockParts) { @($disk.MockPartitions | Sort-Object PartitionNumber) } elseif ($hasStorage) { @(Get-Partition -DiskNumber $dNum -ErrorAction SilentlyContinue | Sort-Object PartitionNumber) } else { @() }
  $drvLetters = @()
  $mountedLettersOnly = @()
  $diskDevPatterns = @()
  $candidateHiddenParts = New-Object System.Collections.ArrayList
  $hasEfi = $false
  $diskHasPePayload = $false
  $diskIsVentoy = $false
  $isSelfUsb = (($null -ne $disk.PSObject.Properties["IsSelfHostUsb"] -and [bool]$disk.IsSelfHostUsb) -or ($selfLoc.DiskNumber -ge 0 -and $dNum -eq $selfLoc.DiskNumber))
  $peLabel = ""

  $bestScore = -1
  $bestPartNum = 0
  $bestBootDev = ""
  $bestBootNtDev = ""
  $bestEfiPath = ""
  $bestPartDisplay = ""

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
   # Never skip $gptRecoveryGuid ({de94bba4-...}) on USB disks: DISM++, Bootice, DiskPart & PhoenixPE use it to hide USB EFI/WinPE partitions!
   if ($p.GptType -eq $gptMsrGuid -or [int64]$p.Size -le 0) { continue }

   $pNum = [int]$p.PartitionNumber
   $pLtr = if ($p.DriveLetter -and ([string]$p.DriveLetter).Trim([char]0).Trim() -match '^([A-Za-z])$') { $matches[1].ToUpper() } else { "" }
   if ($pLtr -and $selfLoc.DriveLetter -and $pLtr -eq $selfLoc.DriveLetter) { $isSelfUsb = $true }

   # Always collect device/GUID patterns from ALL partitions of the physical USB so Tier 1 NVRAM matching never misses hidden partitions
   $partDevPats = @(Get-PartitionDevicePatterns $p)
   $usbDrivePatterns += $partDevPats
   $diskDevPatterns += $partDevPats
   $usbPartPatterns += "(?:Partition|Part)\s+$pNum\b"

   $vol = if ($hasMockParts) { $null } else { Get-Volume -Partition $p -ErrorAction SilentlyContinue }
   $fs = if ($p.PSObject.Properties["MockFileSystem"] -and $p.MockFileSystem) { [string]$p.MockFileSystem } elseif ($vol -and $vol.FileSystem) { [string]$vol.FileSystem } else { "" }
   $volLabel = if ($p.PSObject.Properties["MockLabel"] -and $p.MockLabel) { ([string]$p.MockLabel).Trim() } elseif ($vol -and $vol.FileSystemLabel) { ([string]$vol.FileSystemLabel).Trim() } else { "" }

   $volGuidPath = ""
   $ntVolDev = if ($p.PSObject.Properties["MockNtDevice"] -and $p.MockNtDevice) { [string]$p.MockNtDevice } else { "" }
   if ($pLtr -and -not $ntVolDev -and -not $hasMockParts) {
    $ntFromL = Resolve-DosDeviceTarget "$($pLtr):"
    if ($ntFromL) { $ntVolDev = "partition=" + $ntFromL }
   }
   if ($p.AccessPaths) {
    foreach ($ap in @($p.AccessPaths)) {
     $apStr = ([string]$ap).Trim()
     if ($apStr -match '^\\\\\?\\(Volume\{[^\}]+\})\\?$') {
      $volGuidPath = $apStr.TrimEnd('\') + "\"
      if (-not $ntVolDev -and -not $hasMockParts) {
       $ntResolved = Resolve-DosDeviceTarget $matches[1]
       if ($ntResolved) { $ntVolDev = "partition=" + $ntResolved }
      }
      break
     }
    }
   }
   if ($ntVolDev) {
    $usbDrivePatterns += $ntVolDev
    $diskDevPatterns += $ntVolDev
   }

   if ($pLtr -and -not $volLabel -and -not $hasMockParts) {
    try {
     $di = New-Object System.IO.DriveInfo ($pLtr)
     if ($di.IsReady -and $di.VolumeLabel) { $volLabel = $di.VolumeLabel.Trim() }
     if ($di.IsReady -and -not $fs -and $di.DriveFormat) { $fs = $di.DriveFormat }
    } catch {}
   }
   if (-not $fs -and -not $pLtr -and -not $hasMockParts -and $p.PSObject.Properties["Offset"] -and $null -ne $p.Offset) {
    $fs = Get-RawPartitionFsHint $dNum ([int64]$p.Offset)
   }

   if ($volLabel -match "(?i)^(VTOYEFI|VENTOY)$") { $diskIsVentoy = $true; $anyVentoy = $true }
   $isEfiGpt = ($p.GptType -eq $gptEfiGuid)
   $isRecovGpt = ($p.GptType -eq $gptRecoveryGuid)
   $isEfiMbr = ($null -ne $p.MbrType -and ($mbrEfiFatTypes -contains [int]$p.MbrType))
   # UEFI spec natively reads FAT12/FAT16/FAT32 (NOT exFAT without a chainloader like UEFI_NTFS!)
   $isTrueFatFs = ($fs -match "^(?i)(FAT|FAT12|FAT16|FAT32)$")
   $isBootLabel = ($volLabel -match "(?i)^(VTOYEFI|VENTOY|UEFI_NTFS|PHOENIXPE.*|WINPE.*|ESD-USB|ESD-ISO|HBCD_PE|EFI|BOOT|SYSTEM)$")

   $probeRoot = if ($p.PSObject.Properties["MockProbeRoot"] -and $p.MockProbeRoot) { [string]$p.MockProbeRoot } elseif ($pLtr -and -not $hasMockParts) { "$($pLtr):\" } elseif ($volGuidPath -and -not $hasMockParts) { $volGuidPath } else { "" }
   $efiRelPath = if ($probeRoot) { Find-BestEfiBinaryOnRoot $probeRoot } else { "" }
   $hasPePayload = if ($probeRoot) { Test-WinPePayloadOnRoot $probeRoot } else { $false }
   if ($probeRoot -and ([System.IO.File]::Exists(($probeRoot.TrimEnd('\') + "\ventoy\ventoy.json")) -or [System.IO.File]::Exists(($probeRoot.TrimEnd('\') + "\ventoy.dat")))) {
    $diskIsVentoy = $true; $anyVentoy = $true
   }
   if ($hasPePayload) { $diskHasPePayload = $true }
   if (-not $peLabel -and $volLabel -and ($hasPePayload -or $volLabel -match "(?i)PE|WIN|BOOT|ESD|VENTOY") -and $volLabel -notmatch "^(?i)(UEFI_NTFS|EFI|VTOYEFI|Driver|Data|New Volume)$") {
    $peLabel = $volLabel
   }

   $isHiddenCandidate = (-not $pLtr) -and (
    $isEfiGpt -or $isRecovGpt -or $isEfiMbr -or $isTrueFatFs -or $isBootLabel -or
    ($parts.Count -ge 2 -and [int64]$p.Size -ge 512KB -and [int64]$p.Size -le 16GB)
   )
   if (-not $pLtr -and -not $efiRelPath -and $isHiddenCandidate) {
    [void]$candidateHiddenParts.Add($pNum)
   }

   # Score this partition as the UEFI Direct Boot target (Dedicated FAT EFI > General FAT EFI > NTFS/exFAT EFI > Hidden ESP)
   $partScore = -1
   if ($efiRelPath) {
    if ($isTrueFatFs) {
     $partScore = 100
     if ($isEfiGpt -or [int64]$p.Size -le 4GB -or $volLabel -match "(?i)^(UEFI_NTFS|VTOYEFI|EFI|BOOT|SYSTEM)$") { $partScore = 115 }
    } else {
     $partScore = 75
    }
   } elseif ($isHiddenCandidate -and ($isEfiGpt -or $isTrueFatFs -or ($null -ne $p.MbrType -and [int]$p.MbrType -in @(18, 239)))) {
    $partScore = 60
   } elseif ($isHiddenCandidate -and ($isEfiMbr -or $isRecovGpt -or $isBootLabel)) {
    $partScore = 45
   }

   $prefDev = if ($pLtr) { "partition=$($pLtr):" } elseif ($ntVolDev) { $ntVolDev } else { "" }
   if ($partScore -gt $bestScore) {
    $bestScore = $partScore
    $bestPartNum = $pNum
    $bestBootDev = $prefDev
    $bestBootNtDev = $ntVolDev
    $bestEfiPath = $efiRelPath
    $bestPartDisplay = if ($pLtr) { "$($pLtr):" } else { "Partition $pNum" }
   }

   if ($pLtr) {
    $d = "$($pLtr):"
    $mountedLettersOnly += $d
    $fsDisplay = if ($fs) { $fs } else { "Mounted" }
    $drvLetters += "$d($fsDisplay)"
    if ($efiRelPath -or $hasPePayload -or $isEfiGpt -or $isBootLabel -or ($isTrueFatFs -and ([int64]$p.Size -le 4GB -or $parts.Count -ge 2))) {
     $hasEfi = $true
    }
   } elseif ($efiRelPath -or $hasPePayload -or $isHiddenCandidate) {
    $partTag = if ($isEfiGpt) { "GPT-EFI" } elseif ($isTrueFatFs) { $fs } elseif ($isEfiMbr) { "MBR-Boot" } elseif ($isRecovGpt) { "Hidden-PE" } else { "Hidden" }
    $drvLetters += "Hidden-$partTag(Partition $pNum)"
    if ($efiRelPath -or $hasPePayload -or $isEfiGpt -or $isTrueFatFs -or $isEfiMbr -or $isRecovGpt -or $isBootLabel) {
     $hasEfi = $true
    }
   }
  }

  if ((-not $hasEfi) -and $diskHasPePayload -and $candidateHiddenParts.Count -gt 0) {
   $hasEfi = $true
  }

  $canDirectBoot = ([bool]$bestEfiPath -and [bool]$bestBootDev) -or ($hasEfi -and $candidateHiddenParts.Count -gt 0)
  if ($hasEfi -or $canDirectBoot) { $anyEfiReadyUsb = $true }
  if ($canDirectBoot) { $anyDirectBootUsb = $true }

  $dispLabel = if ($peLabel -and ($cleanName -notmatch [regex]::Escape($peLabel))) {
   $cleanName + " (" + $peLabel + ")"
  } else {
   $cleanName
  }

  $rawUsbItems += [PSCustomObject]@{
   DiskNumber = $dNum
   Model = $cleanName
   DisplayLabel = $dispLabel
   PeVolumeLabel = $peLabel
   SizeGB = "$sizeGB GB"
   DriveSummary = if ($mountedLettersOnly.Count -gt 0) { ($mountedLettersOnly -join ",") } else { "Disk $dNum" }
   Partitions = ($drvLetters -join ", ")
   DevicePatterns = @($diskDevPatterns | Select-Object -Unique)
   IsSelfHostUsb = $isSelfUsb
   IsEfiReady = $hasEfi
   CanDirectEfiBoot = $canDirectBoot
   BestBootPartNum = $bestPartNum
   BestBootPartDisplay = $bestPartDisplay
   BestBootDevice = $bestBootDev
   BestBootNtDevice = $bestBootNtDev
   BestEfiRelPath = $bestEfiPath
   CandidatePartNums = @($candidateHiddenParts | Select-Object -Unique)
   IsVentoy = $diskIsVentoy
   IsReadOnly = [bool]$disk.IsReadOnly
  }
 }

 # Prioritize the USB hosting this tool first, then EFI-ready disks, then DiskNumber
 $physicalUsbList = @($rawUsbItems | Sort-Object @{Expression={if($_.IsSelfHostUsb){0}else{1}}}, @{Expression={if($_.IsEfiReady){0}else{1}}}, DiskNumber)

 return [PSCustomObject]@{
  PhysicalUsbList = $physicalUsbList
  UsbDrivePatterns = @($usbDrivePatterns | Select-Object -Unique)
  UsbStrictModelPatterns = @($usbStrictModelPatterns | Select-Object -Unique)
  UsbPartPatterns = @($usbPartPatterns | Select-Object -Unique)
  AnyEfiReadyUsb = $anyEfiReadyUsb
  AnyDirectBootUsb = $anyDirectBootUsb
  IsVentoy = $anyVentoy
 }
}

# Register a clean 1-time UEFI firmware boot entry (Boot#### + BootNext) directly from a physical USB's EFI partition!
# Works even when the USB was Hot-Plugged while Windows was running and has 0 prior NVRAM entries!
function Invoke-DirectUsbEfiBootSetup($usbDiskItem) {
 if (-not $usbDiskItem) {
  return [PSCustomObject]@{ Success = $false; Guid = ""; Device = ""; Path = ""; Error = "NO_USB_ITEM" }
 }
 $diskNum = [int]$usbDiskItem.DiskNumber
 $targetDev = if ($usbDiskItem.PSObject.Properties["BestBootDevice"]) { [string]$usbDiskItem.BestBootDevice } else { "" }
 $targetNtDev = if ($usbDiskItem.PSObject.Properties["BestBootNtDevice"]) { [string]$usbDiskItem.BestBootNtDevice } else { "" }
 $targetPath = if ($usbDiskItem.PSObject.Properties["BestEfiRelPath"]) { [string]$usbDiskItem.BestEfiRelPath } else { "" }

 $registerBcd = {
  param([string]$devTok, [string]$altDevTok, [string]$efiPath)
  $entryLabel = "SID Aux Tool - WinPE USB"
  try {
   $curFw = Invoke-NativeOem "bcdedit.exe" "/enum firmware"
   $parsedFw = @(Parse-BcdFirmwareLines $curFw.Lines)
   foreach ($fe in $parsedFw) {
    if ($fe.Identifier -match '^\{[0-9a-fA-F-]{36}\}$' -and [string]$fe.Description -eq $entryLabel) {
     $delTry = Invoke-NativeOem "bcdedit.exe" ("/delete " + $fe.Identifier)
     if ($delTry.ExitCode -ne 0) { $null = Invoke-NativeOem "bcdedit.exe" ("/delete " + $fe.Identifier + " /f") }
    }
   }
  } catch {}

  $crRes = Invoke-NativeOem "bcdedit.exe" ('/create /d "' + $entryLabel + '" /application firmware')
  $newGuid = ""
  foreach ($ln in $crRes.Lines) {
   if ([string]$ln -match '(\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\})') {
    $newGuid = $matches[1]
    break
   }
  }
  if ($crRes.ExitCode -ne 0 -or -not $newGuid) {
   return [PSCustomObject]@{ Success = $false; Guid = ""; Device = $devTok; Path = $efiPath; Error = ("bcdedit /create: " + ($crRes.Lines -join " ")) }
  }

  $usedDev = $devTok
  $devRes = Invoke-NativeOem "bcdedit.exe" ("/set " + $newGuid + " device " + $devTok)
  if ($devRes.ExitCode -ne 0 -and $altDevTok -and $altDevTok -ne $devTok) {
   $usedDev = $altDevTok
   $devRes = Invoke-NativeOem "bcdedit.exe" ("/set " + $newGuid + " device " + $altDevTok)
  }
  if ($devRes.ExitCode -ne 0) {
   $null = Invoke-NativeOem "bcdedit.exe" ("/delete " + $newGuid)
   return [PSCustomObject]@{ Success = $false; Guid = ""; Device = $usedDev; Path = $efiPath; Error = ("bcdedit /set device: " + ($devRes.Lines -join " ")) }
  }

  $pathRes = Invoke-NativeOem "bcdedit.exe" ('/set ' + $newGuid + ' path "' + $efiPath + '"')
  if ($pathRes.ExitCode -ne 0) {
   $null = Invoke-NativeOem "bcdedit.exe" ("/delete " + $newGuid)
   return [PSCustomObject]@{ Success = $false; Guid = ""; Device = $usedDev; Path = $efiPath; Error = ("bcdedit /set path: " + ($pathRes.Lines -join " ")) }
  }

  $seqRes = Invoke-NativeOem "bcdedit.exe" ("/set {fwbootmgr} bootsequence " + $newGuid)
  if ($seqRes.ExitCode -ne 0) {
   $null = Invoke-NativeOem "bcdedit.exe" ("/delete " + $newGuid)
   return [PSCustomObject]@{ Success = $false; Guid = ""; Device = $usedDev; Path = $efiPath; Error = ("bcdedit bootsequence: " + ($seqRes.Lines -join " ")) }
  }

  return [PSCustomObject]@{ Success = $true; Guid = $newGuid; Device = $usedDev; Path = $efiPath; Error = "" }
 }

 # Fast path: EFI file & partition device already resolved without mounting!
 if ($targetDev -and $targetPath) {
  return (& $registerBcd $targetDev $targetNtDev $targetPath)
 }

 # Hidden partition fallback: temporarily mount candidate unmounted partitions on the USB to locate the .efi binary and register BootNext
 $partsToProbe = New-Object System.Collections.ArrayList
 if ($usbDiskItem.PSObject.Properties["BestBootPartNum"] -and [int]$usbDiskItem.BestBootPartNum -gt 0) {
  [void]$partsToProbe.Add([int]$usbDiskItem.BestBootPartNum)
 }
 if ($usbDiskItem.PSObject.Properties["CandidatePartNums"] -and $usbDiskItem.CandidatePartNums) {
  foreach ($cpn in @($usbDiskItem.CandidatePartNums)) {
   if ([int]$cpn -gt 0 -and -not $partsToProbe.Contains([int]$cpn)) { [void]$partsToProbe.Add([int]$cpn) }
  }
 }
 if ($partsToProbe.Count -eq 0 -and (Test-StorageCmdletsAvailable)) {
  foreach ($up in @(Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue | Where-Object { -not $_.DriveLetter -and [int64]$_.Size -gt 0 })) {
   [void]$partsToProbe.Add([int]$up.PartitionNumber)
  }
 }

 $lastErr = U "USB \uB0B4\uC5D0\uC11C UEFI \uBD80\uD305 \uD30C\uC77C(.efi)\uC744 \uCC3E\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4."
 foreach ($pNum in $partsToProbe) {
  $mntRes = Invoke-WithEspMount $diskNum $pNum "" {
   param($drv)
   $foundEfi = Find-BestEfiBinaryOnRoot "$($drv):\"
   if (-not $foundEfi) { return $null }
   $ntD = Resolve-DosDeviceTarget "$($drv):"
   $altD = if ($ntD) { "partition=" + $ntD } else { "" }
   return (& $registerBcd "partition=$($drv):" $altD $foundEfi)
  }
  if ($mntRes -and $mntRes -ne "MOUNT_FAIL") {
   if ($mntRes.Success) { return $mntRes }
   if ($mntRes.Error) { $lastErr = $mntRes.Error }
  }
 }

 return [PSCustomObject]@{ Success = $false; Guid = ""; Device = ""; Path = ""; Error = $lastErr }
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
 $unknownDevRe = "^(?i)(unknown|" + (U "\uC54C\s*\uC218\s*\uC5C6\uC74C") + ")(\s|$)"
 $excludeDesc = "(?i)(Windows Boot Manager|" + [regex]::Escape($koBootMgr) + "|PXE|IPV4|IPV6|IP4|IP6|HTTPs?\s*Boot|Network|Hard Drive \(SATA|Hard Drive \(NVMe|Onboard NIC|Ethernet|GbE\s+Family|FE\s+Family|\bLAN\b|Wi-?Fi|Bluetooth|Built-in\s+EFI\s+Shell|SupportAssist|Sure\s*Recover|BIOS\s*Connect|Firmware\s*Update|Diagnostics)"
 $internalPattern = if ($internalDriveLetters -and $internalDriveLetters.Count -gt 0) {
  (@($internalDriveLetters | ForEach-Object { ConvertTo-SafeDeviceRegex ([string]$_) } | Where-Object { $_ }) | Select-Object -Unique) -join "|"
 } else {
  ""
 }
 $usbDrvRegex = if ($usbDrivePatterns -and $usbDrivePatterns.Count -gt 0) {
  (@($usbDrivePatterns | ForEach-Object { ConvertTo-SafeDeviceRegex ([string]$_) } | Where-Object { $_ }) | Select-Object -Unique) -join "|"
 } else { "" }
 $usbModRegex = if ($usbStrictModelPatterns -and $usbStrictModelPatterns.Count -gt 0) {
  (@($usbStrictModelPatterns | Where-Object { $_ } | Select-Object -Unique | ForEach-Object { "(?<![A-Za-z0-9])(?:" + $_ + ")(?![A-Za-z0-9])" })) -join "|"
 } else { "" }
 $intModRegex = if ($internalModelPatterns -and $internalModelPatterns.Count -gt 0) { ($internalModelPatterns | Select-Object -Unique) -join "|" } else { "" }

 $candidateEntries = @($bcdEntries | Where-Object {
  $descStr = [string]$_.Description
  $devStr = ([string]$_.Device).Trim()
  $isUnknownGhostDev = ($devStr -ne "" -and ($devStr -match $unknownDevRe))
  $matchesInternalDev = ($internalPattern -and ($devStr -match $internalPattern))
  $matchesUsbDev = (-not $isUnknownGhostDev) -and (-not $matchesInternalDev) -and ($usbDrvRegex -and ($devStr -match $usbDrvRegex))
  $matchesUsbMod = (-not $isUnknownGhostDev) -and ($usbModRegex -and ($descStr -match $usbModRegex))
  $isOpticalNonUsb = ($descStr -match "(?i)CD/DVD|CD-ROM|Optical") -and ($descStr -notmatch "(?i)\bUSB\b")
  # Never exclude external enclosures OR DISM++/bcdboot USB entries named 'Windows Boot Manager' when $matchesUsbDev proves the partition is on the USB!
  $isInternalBusWithoutUsb = (-not $matchesUsbDev) -and (-not $matchesUsbMod) -and ($descStr -match "(?i)\b(SATA\d*|NVMe\d*)\b") -and ($descStr -notmatch "(?i)\bUSB\b|External|Removable|Enclosure")
  $isInternalModelOnly = (-not $matchesUsbDev) -and (-not $matchesUsbMod) -and ($intModRegex -and ($descStr -match $intModRegex)) -and ($descStr -notmatch "(?i)\bUSB\b")

  $_.Identifier -ne "{fwbootmgr}" -and
  $_.Identifier -ne "{bootmgr}" -and
  ([string]$_.Description -ne "SID Aux Tool - WinPE USB") -and
  (-not $isUnknownGhostDev) -and
  ($matchesUsbDev -or ($descStr -notmatch $excludeDesc)) -and
  (-not $isOpticalNonUsb) -and
  (-not $isInternalBusWithoutUsb) -and
  (-not $isInternalModelOnly) -and
  ($matchesUsbDev -or (-not $matchesInternalDev))
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
  $allowGenericFallback = [bool]$usbInfo.AnyEfiReadyUsb
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
  $usbDisks = $snap.UsbDisks
  $usbInfo = $snap.UsbInfo
  $matchedEntries = $snap.MatchedEntries
  $diag = $snap.BiosDiag

  Show-BiosStatusDashboard $diag $step1Bypassed

  if (-not $gate1Ignored) {
   $isVty = ($null -ne $usbInfo.PSObject.Properties["IsVentoy"] -and [bool]$usbInfo.IsVentoy)
   $hasDirBoot = ($null -ne $usbInfo.PSObject.Properties["AnyDirectBootUsb"] -and [bool]$usbInfo.AnyDirectBootUsb)
   $g1 = Invoke-Gate1Check $diag $bcdOutput $matchedEntries.Count $isVty $hasDirBoot
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
   $selfTag = if ($u.PSObject.Properties["IsSelfHostUsb"] -and $u.IsSelfHostUsb) { " [" + (U "\uD604\uC7AC \uC2E4\uD589 \uC911\uC778 USB") + "]" } else { "" }
   $roTag = if ($u.IsReadOnly) { " [" + (U "\uC77D\uAE30 \uC804\uC6A9") + "]" } else { "" }
   $lblName = if ($u.PSObject.Properties["DisplayLabel"] -and $u.DisplayLabel) { $u.DisplayLabel } else { $u.Model }
   Write-Host (" - Disk " + $u.DiskNumber + " : " + $lblName + " [" + $u.SizeGB + "]" + $selfTag + $roTag + " | " + $u.Partitions + " -> (" + $efiTag + ")") -ForegroundColor White
  }

  # Gate 2: Physical USB found, 0 pre-existing NVRAM entries -> offer Direct UEFI EFI Boot when EFI partition is ready!
  if ($matchedEntries.Count -eq 0) {
   $directTargetUsb = $usbInfo.PhysicalUsbList | Where-Object { $_.IsEfiReady } | Select-Object -First 1
   $isNonBootUsb = (-not [bool]$usbInfo.AnyEfiReadyUsb)
   $rescanNow = $false
   while ($true) {
    Write-Host "`n==================================================================" -ForegroundColor Yellow
    if ($directTargetUsb -and -not $diag.IsConfirmedBlocked) {
     $dLbl = if ($directTargetUsb.DisplayLabel) { $directTargetUsb.DisplayLabel } else { $directTargetUsb.Model }
     $dPathInfo = if ($directTargetUsb.BestEfiRelPath) { $directTargetUsb.BestBootPartDisplay + $directTargetUsb.BestEfiRelPath } else { $directTargetUsb.BestBootPartDisplay }
     Write-Host (U " [\uC900\uBE44 \uC644\uB8CC] WinPE USB\uC758 EFI \uBD80\uD305 \uC601\uC5ED\uC744 \uD655\uC778\uD588\uC2B5\uB2C8\uB2E4 (EFI \uC9C1\uC811 \uBD80\uD305 \uC9C0\uC6D0).") -ForegroundColor Green
     Write-Host (" - Disk " + $directTargetUsb.DiskNumber + " : " + $dLbl + " | EFI: " + $dPathInfo) -ForegroundColor Cyan
     Write-Host ""
     Write-Host (U " [Enter \uB610\uB294 1] \uC704 WinPE USB\uB85C \uBC14\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305 (\uAD8C\uC7A5 - EFI \uC9C1\uC811 \uB4F1\uB85D)") -ForegroundColor Green
     Write-Host (U " [O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor White
     Write-Host (U " [B] BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Cyan
    } elseif ($isNonBootUsb) {
     Write-Host (U " [\uC8FC\uC758] \uC5F0\uACB0\uB41C USB\uC5D0\uC11C UEFI/WinPE \uBD80\uD305 \uD30C\uC77C\uC774 \uD655\uC778\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
     Write-Host (U " - \uC228\uAE40 \uD30C\uD2F0\uC158 \uD0D0\uC0C9 \uBD80\uD305\uC740 [1], Windows \uACE0\uAE09 \uBD80\uD305\uC740 [O]\uB97C \uC120\uD0DD\uD558\uC138\uC694.") -ForegroundColor Gray
     Write-Host ""
     Write-Host (U " [1] \uC228\uAE40 EFI \uD30C\uD2F0\uC158 \uD0D0\uC0C9 \uBC0F \uC9C1\uC811 \uBD80\uD305 \uC2DC\uB3C4") -ForegroundColor Green
     Write-Host (U " [O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Green
     Write-Host (U " [B] BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Cyan
    } else {
     Write-Host (U " [\uACBD\uACE0] BIOS\uC5D0\uC11C USB \uBD80\uD305\uC774 \uCC28\uB2E8\uB418\uC5C8\uAC70\uB098 NVRAM \uBAA9\uB85D\uC5D0 \uC5C6\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
     Write-Host (" - " + $diag.BiosHint) -ForegroundColor Yellow
     Write-Host ""
     Write-Host (U " [Enter \uB610\uB294 B] \uC989\uC2DC BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305 (\uAD8C\uC7A5)") -ForegroundColor Cyan
     Write-Host (U " [O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Green
    }
    Write-Host (U " [R] \uB2E4\uC2DC \uC2A4\uCE94 | [E] \uB0B4\uC7A5 \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [M] \uBA54\uC778 \uBA54\uB274") -ForegroundColor Gray
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

    $defaultHint = if ($directTargetUsb -and -not $diag.IsConfirmedBlocked) { U "Enter=USB \uC9C1\uC811 \uBD80\uD305" } elseif ($isNonBootUsb) { "O/1/B" } else { U "Enter=BIOS \uC9C4\uC785" }
    $fbChoice = (Read-Host ((U "\uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694 (") + $defaultHint + ")")).Trim()

    if ($fbChoice -match "^[rR]$") { $rescanNow = $true; break }
    elseif ($fbChoice -match "^[eE]$") { Show-BootloaderManager $false; continue }
    elseif ($fbChoice -match "^[dD]$") { Show-BcdDebug $bcdOutput; continue }
    elseif ($fbChoice -match "^[lL]$") { Show-DiskDebug; continue }
    elseif (($fbChoice -eq "1") -or ($fbChoice -eq "" -and $directTargetUsb -and -not $diag.IsConfirmedBlocked)) {
     $candUsb = if ($directTargetUsb) { $directTargetUsb } else { $usbInfo.PhysicalUsbList[0] }
     $dSet = Invoke-DirectUsbEfiBootSetup $candUsb
     if ($dSet.Success) {
      Write-Host ("`n-> [" + $candUsb.Model + " " + $dSet.Path + (U "] 1\uD68C\uC131 EFI \uBD80\uD305 \uB4F1\uB85D \uC644\uB8CC! \uC989\uC2DC \uC7AC\uBD80\uD305\uD569\uB2C8\uB2E4...")) -ForegroundColor Cyan
      $null = Invoke-SafeReboot "/r /f /t 0" "USB Direct EFI Boot"
      return
     } else {
      Write-Host ((U "`n[\uC548\uB0B4] EFI \uC9C1\uC811 \uBD80\uD305 \uB4F1\uB85D \uC2E4\uD328: ") + $dSet.Error) -ForegroundColor Yellow
      $goAdv = (Read-Host (U "Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9)\uC73C\uB85C \uC7AC\uBD80\uD305\uD560\uAE4C\uC694? (Y/N)")).Trim()
      if ($goAdv -match "^[yY]$") { $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot"; return }
     }
    } elseif ($fbChoice -eq "" -and -not $isNonBootUsb) {
     $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup"
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
