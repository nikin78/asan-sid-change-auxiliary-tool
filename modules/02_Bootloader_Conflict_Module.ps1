# ==============================================================================
# Module 02: Internal Bootloader Conflict Guard (GPT EFI + MBR Active)
#            USB/WinPE Media Protection + WinPE diskpart Fallback
# ==============================================================================

# Parse 'diskpart -> list disk' output (English and Korean Windows/WinPE)
function Parse-DiskpartListDisk([array]$lines) {
 $disks = @()
 $gptColIdx = -1
 $reDiskWord = "(?:Disk|" + (U "\uB514\uC2A4\uD06C") + ")"
 $reOnline = "^(Online|" + (U "\uC628\uB77C\uC778") + ")$"

 foreach ($line in $lines) {
  $s = [string]$line
  if ($gptColIdx -lt 0 -and $s -match "\bGpt\b") {
   $gptColIdx = $s.IndexOf("Gpt")
  }
  if ($s -match ("^\s*" + $reDiskWord + "\s+(\d+)\s+(\S+)\s+(\d+\s*[KMGT]?B)\s+(\d+\s*[KMGT]?B)(.*)$")) {
   $diskNum = [int]$matches[1]
   $status = $matches[2].Trim()
   $sizeStr = $matches[3].Trim()
   $tail = $matches[5]
   $isGpt = $false
   if ($gptColIdx -ge 0 -and $s.Length -gt $gptColIdx) {
    $sliceStart = [Math]::Max(0, $gptColIdx - 2)
    if ($s.Substring($sliceStart) -match "\*") { $isGpt = $true }
   } elseif ($tail -match "\*") {
    $isGpt = $true
   }
   $sizeGB = 0.0
   if ($sizeStr -match "^(\d+)\s*([KMGT]?B)$") {
    $num = [double]$matches[1]
    switch ($matches[2].ToUpper()) {
     "TB" { $sizeGB = [math]::Round($num * 1024, 1) }
     "GB" { $sizeGB = [math]::Round($num, 1) }
     "MB" { $sizeGB = [math]::Round($num / 1024, 2) }
     default { $sizeGB = 0.0 }
    }
   }
   $disks += [PSCustomObject]@{
    Number = $diskNum
    Status = $status
    IsOnline = ($status -match $reOnline)
    SizeGB = $sizeGB
    Size = [int64]($sizeGB * 1GB)
    PartitionStyle = if ($isGpt) { "GPT" } else { "MBR" }
   }
  }
 }
 return $disks
}

# Parse 'diskpart -> detail disk' output
function Parse-DiskpartDetailDisk([array]$lines) {
 $model = "Disk"
 $busType = "Unknown"
 $partStyle = ""
 $isReadOnly = $false
 $reTypeLine = "^(Type|" + (U "\uC720\uD615") + ")\s*:\s*(.+)$"
 $reDiskIdLine = "^(Disk ID|" + (U "\uB514\uC2A4\uD06C") + "\s*ID)\s*:\s*(.+)$"
 $reRoLine = "^(Current Read-only State|Read-only|" + (U "\uD604\uC7AC \uC77D\uAE30 \uC804\uC6A9 \uC0C1\uD0DC") + "|" + (U "\uC77D\uAE30 \uC804\uC6A9") + ")\s*:\s*(Yes|" + (U "\uC608") + ")$"
 $reSkipHeader = "^(Microsoft DiskPart|Copyright|On computer|DISKPART>|Disk \d+ is now|\d+\s*" + (U "\uB514\uC2A4\uD06C") + "|" + (U "\uCEF4\uD4E8\uD130") + "|" + (U "\uB514\uC2A4\uD06C") + "\s+\d+)"
 $foundDiskId = $false

 foreach ($line in $lines) {
  $t = ([string]$line).Trim()
  if (-not $t) { continue }
  if ($t -match $reDiskIdLine) {
   $idVal = $matches[2].Trim()
   if ($idVal -match "^\{[0-9a-fA-F-]+\}$") { $partStyle = "GPT" }
   elseif ($idVal -match "^[0-9a-fA-F]{6,8}$") { $partStyle = "MBR" }
   $foundDiskId = $true
  } elseif ($t -match $reTypeLine) {
   $busType = $matches[2].Trim()
  } elseif ($t -match $reRoLine) {
   $isReadOnly = $true
  } elseif (-not $foundDiskId -and $model -eq "Disk") {
   if ($t -notmatch $reSkipHeader) {
    $model = $t
   }
  }
 }

 return [PSCustomObject]@{
  FriendlyName = $model
  BusType = $busType
  IsUsb = ($busType -match "USB|SD|MMC")
  IsReadOnly = $isReadOnly
  PartitionStyle = $partStyle
 }
}

# Parse 'diskpart -> list partition' output
function Parse-DiskpartListPartition([array]$lines) {
 $parts = @()
 $rePartWord = "(?:Partition|" + (U "\uD30C\uD2F0\uC158") + ")"
 $reSys = "^(System|" + (U "\uC2DC\uC2A4\uD15C") + ")$"
 $rePri = "^(Primary|" + (U "\uC8FC") + ")$"

 foreach ($line in $lines) {
  $s = [string]$line
  if ($s -match ("^\s*" + $rePartWord + "\s+(\d+)\s+(.+?)\s+(\d+\s*[KMGT]?B)\s+(\d+\s*[KMGT]?B)")) {
   $pNum = [int]$matches[1]
   $pType = $matches[2].Trim()
   $pSize = $matches[3].Trim()
   $sizeMB = 0.0
   if ($pSize -match "^(\d+)\s*([KMGT]?B)$") {
    $n = [double]$matches[1]
    switch ($matches[2].ToUpper()) {
     "TB" { $sizeMB = $n * 1024 * 1024 }
     "GB" { $sizeMB = $n * 1024 }
     "MB" { $sizeMB = $n }
     "KB" { $sizeMB = [math]::Round($n / 1024, 2) }
     default { $sizeMB = 0.0 }
    }
   }
   $parts += [PSCustomObject]@{
    PartitionNumber = $pNum
    TypeText = $pType
    IsEsp = ($pType -match $reSys)
    IsPrimary = ($pType -match $rePri)
    SizeMB = $sizeMB
    Size = [int64]($sizeMB * 1MB)
   }
  }
 }
 return $parts
}

# Parse 'diskpart -> detail partition' output
function Parse-DiskpartDetailPartition([array]$lines) {
 $isActive = $false
 $isEspGuid = $false
 $driveLetter = ""
 $ltrColIdx = -1
 $reActive = "^(Active|" + (U "\uD65C\uC131") + ")\s*:\s*(Yes|" + (U "\uC608") + ")$"
 $reVolLine = "^\*?\s*(Volume|" + (U "\uBCFC\uB968") + ")\s+\d+"
 $reLtrHdr = "\b(Ltr|" + (U "\uBB38\uC790") + ")\b"

 foreach ($line in $lines) {
  $s = [string]$line
  $t = $s.Trim()
  if ($t -match $reActive) { $isActive = $true }
  if ($t -match "c12a7328-f81f-11d2-ba4b-00a0c93ec93b") { $isEspGuid = $true }
  if ($ltrColIdx -lt 0 -and $s -match $reLtrHdr) {
   $ltrColIdx = $s.IndexOf($matches[1])
  }
  if ($s -match $reVolLine) {
   # Primary regex works reliably across both English and wide-char Korean volume rows
   if ($s -match ("^\*?\s*(?:Volume|" + (U "\uBCFC\uB968") + ")\s+\d+\s{1,6}([A-Z])\s{2,}")) {
    $driveLetter = $matches[1]
   } elseif ($ltrColIdx -ge 0 -and $s.Length -gt $ltrColIdx) {
    $seg = $s.Substring($ltrColIdx, [Math]::Min(3, $s.Length - $ltrColIdx)).Trim()
    if ($seg -match "^[A-Z]$") { $driveLetter = $seg }
   }
  }
 }

 return [PSCustomObject]@{
  IsActive = $isActive
  IsEspGuid = $isEspGuid
  DriveLetter = $driveLetter
 }
}

# Classify online disks into USB vs Internal (with WinPE diskpart fallback)
function Get-ClassifiedDisks([bool]$isWinPE) {
 $usbDisks = @()
 $internalDisks = @()

 if (Test-StorageCmdletsAvailable) {
  $allDisks = @(Get-Disk | Where-Object { ([string]$_.OperationalStatus) -match "\bOnline\b" })
  $usbDisks = @($allDisks | Where-Object {
   -not $_.IsBoot -and -not $_.IsSystem -and
   ($_.BusType -in @('USB','SD','MMC') -or $_.IsRemovable -or [string]$_.Path -match "USBSTOR|UASP")
  })
  $usbNums = @($usbDisks | Select-Object -ExpandProperty Number)
  $internalDisks = @($allDisks | Where-Object { $usbNums -notcontains $_.Number })
  return [PSCustomObject]@{
   UsedFallback = $false
   UsbDisks = $usbDisks
   InternalDisks = $internalDisks
  }
 }

 # Fallback for lightweight WinPE without Storage cmdlets
 $ldRes = Invoke-NativeOem "diskpart.exe" "" "list disk`r`nexit`r`n"
 $parsedDisks = @(Parse-DiskpartListDisk $ldRes.Lines | Where-Object { $_.IsOnline })
 foreach ($pd in $parsedDisks) {
  $ddRes = Invoke-NativeOem "diskpart.exe" "" ("select disk " + $pd.Number + "`r`ndetail disk`r`nexit`r`n")
  $det = Parse-DiskpartDetailDisk $ddRes.Lines
  $style = if ($det.PartitionStyle) { $det.PartitionStyle } else { $pd.PartitionStyle }
  $obj = [PSCustomObject]@{
   Number = $pd.Number
   FriendlyName = $det.FriendlyName
   Size = $pd.Size
   SizeGB = $pd.SizeGB
   PartitionStyle = $style
   BusType = $det.BusType
   IsBoot = $false
   IsSystem = $false
   IsRemovable = $det.IsUsb
   IsReadOnly = $det.IsReadOnly
   Path = ""
  }
  if ($det.IsUsb) { $usbDisks += $obj } else { $internalDisks += $obj }
 }

 return [PSCustomObject]@{
  UsedFallback = $true
  UsbDisks = $usbDisks
  InternalDisks = $internalDisks
 }
}

# Gather all drive letters in use (including mapped network drives across UAC split tokens)
function Get-BusyDriveLetters {
 $busy = @{}
 try {
  foreach ($di in [System.IO.DriveInfo]::GetDrives()) {
   if ($di.Name -match "^([A-Za-z]):") { $busy[$matches[1].ToUpper()] = $true }
  }
 } catch {}
 try {
  foreach ($pd in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
   if ($pd.Name -match "^[A-Za-z]$") { $busy[$pd.Name.ToUpper()] = $true }
  }
 } catch {}
 # Check HKCU and all loaded HKU hives for mapped network drives (e.g. Z:\ mapped in non-elevated session)
 try {
  if (Test-Path "HKCU:\Network") {
   foreach ($nk in @(Get-ChildItem "HKCU:\Network" -ErrorAction SilentlyContinue)) {
    if ($nk.PSChildName -match "^[A-Za-z]$") { $busy[$nk.PSChildName.ToUpper()] = $true }
   }
  }
 } catch {}
 try {
  foreach ($uh in @(Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue)) {
   $netPath = Join-Path $uh.PSPath "Network"
   if (Test-Path $netPath) {
    foreach ($nk in @(Get-ChildItem $netPath -ErrorAction SilentlyContinue)) {
     if ($nk.PSChildName -match "^[A-Za-z]$") { $busy[$nk.PSChildName.ToUpper()] = $true }
    }
   }
  }
 } catch {}
 try {
  foreach ($md in @(Get-CimInstance -ClassName Win32_MappedLogicalDisk -ErrorAction SilentlyContinue)) {
   if ($md.Name -match "^([A-Za-z]):") { $busy[$matches[1].ToUpper()] = $true }
  }
 } catch {}
 try {
  if (Test-StorageCmdletsAvailable) {
   foreach ($p in @(Get-Partition -ErrorAction SilentlyContinue)) {
    if ($p.DriveLetter -and ([string]$p.DriveLetter) -match "^[A-Za-z]$") {
     $busy[([string]$p.DriveLetter).ToUpper()] = $true
    }
   }
  }
 } catch {}
 return $busy
}

# Helper: Mount partition temporarily via diskpart, run scriptblock, always unmount safely
function Invoke-WithEspMount([int]$diskNum, [int]$partNum, [string]$existingLetter, [scriptblock]$action) {
 $workDrv = ""
 $tempMounted = $false
 if ($existingLetter) {
  # Never reassign/overwrite a partition that already has a drive letter
  if (Test-Path "$($existingLetter):\") {
   $workDrv = $existingLetter
  } else {
   return "MOUNT_FAIL"
  }
 } else {
  $busy = Get-BusyDriveLetters
  # Avoid Z: first since Z: is the most common mapped network drive letter
  $candidates = @("W","V","U","T","S","R","Q","P","O","N","M","Z")
  foreach ($l in $candidates) {
   if ($busy.ContainsKey($l) -or (Test-Path "$($l):\")) { continue }
   $dpScript = "select disk $diskNum`r`nselect part $partNum`r`nassign letter=$l`r`nexit`r`n"
   $dpAssign = Invoke-NativeOem "diskpart.exe" "" $dpScript
   if ($dpAssign.ExitCode -ne 0) { continue }
   $mountedOk = $false
   for ($w = 0; $w -lt 8; $w++) {
    if (Test-Path "$($l):\") { $mountedOk = $true; break }
    Start-Sleep -Milliseconds 150
   }
   if ($mountedOk) {
    $workDrv = $l
    $tempMounted = $true
    break
   } else {
    # Prevent leaking a temporary drive letter if volume is RAW/inaccessible
    $dpUndo = "select disk $diskNum`r`nselect part $partNum`r`nremove letter=$l`r`nexit`r`n"
    $null = Invoke-NativeOem "diskpart.exe" "" $dpUndo
    if (Test-Path "$($l):\") { $null = Invoke-NativeOem "mountvol.exe" "$($l): /d" }
   }
  }
 }
 if (-not $workDrv) { return "MOUNT_FAIL" }
 $res = $null
 try {
  $res = & $action $workDrv
 } finally {
  if ($tempMounted) {
   $dpClean = "select disk $diskNum`r`nselect part $partNum`r`nremove letter=$workDrv`r`nexit`r`n"
   $null = Invoke-NativeOem "diskpart.exe" "" $dpClean
   if (Test-Path "$($workDrv):\") {
    $null = Invoke-NativeOem "mountvol.exe" "$($workDrv): /d"
   }
  }
 }
 return $res
}

# Pure helper: Guard against modifying OS partitions or WinPE/installer media
function Test-PartitionMediaGuard([string]$rootPath) {
 $root = $rootPath.TrimEnd('\')
 $hasOs = Test-Path "$root\Windows\System32\ntoskrnl.exe"
 $hasWinPE = $false
 $reason = ""

 if ((Test-Path "$root\sources\boot.wim") -or (Test-Path "$root\sources\install.wim") -or (Test-Path "$root\sources\install.esd")) {
  $hasWinPE = $true
  $reason = "sources\boot.wim/install"
 } elseif ((Test-Path "$root\ventoy\ventoy.json") -or (Test-Path "$root\PhoenixPE.cfg") -or (Test-Path "$root\HBCD_PE.ini")) {
  $hasWinPE = $true
  $reason = "WinPE/Ventoy marker"
 } elseif ((Test-Path "$root\boot\boot.sdi") -and (Test-Path "$root\sources")) {
  $hasWinPE = $true
  $reason = "WinPE boot.sdi"
 } elseif (((Test-Path "$root\EFI\BOOT\BOOTX64.EFI") -or (Test-Path "$root\EFI\BOOT\BOOTAA64.EFI")) -and (-not (Test-Path "$root\EFI\Microsoft"))) {
  $hasWinPE = $true
  $reason = "EFI\BOOT without EFI\Microsoft"
 }

 return [PSCustomObject]@{
  HasOs = $hasOs
  HasWinPE = $hasWinPE
  Reason = $reason
 }
}

# Pure helper: Inspect mounted partition root for GPT EFI or MBR bootloader state
function Inspect-BootloaderPartition([string]$rootPath, [string]$bootType, [bool]$isActiveFlag) {
 $root = $rootPath.TrimEnd('\')
 $guard = Test-PartitionMediaGuard $root
 if ($guard.HasWinPE) { return "WINPE_BLOCKED" }

 if ($bootType -eq "GPT_EFI") {
  if ($guard.HasOs) { return "OS_BLOCKED" }
  $hasEfi = Test-Path "$root\EFI"
  $hasOld = Test-Path "$root\EFI_OLD"
  if ($hasEfi -and $hasOld) { return "BOTH" }
  elseif ($hasEfi) { return "ACTIVE" }
  elseif ($hasOld) { return "DISABLED" }
  else { return "EMPTY" }
 }

 if ($bootType -eq "MBR_ACTIVE") {
  $hasBootmgr = Test-Path "$root\bootmgr"
  $hasBootBcd = Test-Path "$root\Boot\BCD"
  $hasActiveFiles = $hasBootmgr -or $hasBootBcd
  $hasOldBootmgr = Test-Path "$root\bootmgr_OLD"
  $hasOldBootDir = Test-Path "$root\Boot_OLD"
  $hasOldFiles = $hasOldBootmgr -or $hasOldBootDir

  if ($guard.HasOs) {
   if ($isActiveFlag -and $hasActiveFiles) { return "MBR_OS_BLOCKED" }
   return "OS_BLOCKED"
  }
  if ($hasActiveFiles -and $hasOldFiles) { return "BOTH" }
  elseif ($hasActiveFiles -and $isActiveFlag) { return "ACTIVE" }
  elseif ($hasOldFiles) { return "DISABLED" }
  else { return "EMPTY" }
 }

 return "NO_BOOTLOADER"
}

function Clear-SpecialAttributes([string]$targetPath) {
 try {
  $item = Get-Item -LiteralPath $targetPath -Force -ErrorAction Stop
  $mask = [System.IO.FileAttributes]::ReadOnly -bor [System.IO.FileAttributes]::System -bor [System.IO.FileAttributes]::Hidden
  $item.Attributes = ($item.Attributes -band (-bnot $mask))
 } catch {}
}

# Pure helper: Perform non-destructive bootloader rename on a mounted root path
function Invoke-BootloaderRenameInRoot([string]$rootPath, [string]$bootType, [string]$mode) {
 $root = $rootPath.TrimEnd('\')
 $guard = Test-PartitionMediaGuard $root
 if ($guard.HasOs) { return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Error = "OS_BLOCKED" } }
 if ($guard.HasWinPE) { return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Error = "WINPE_BLOCKED" } }

 if ($bootType -eq "GPT_EFI") {
  try {
   if ($mode -eq "DISABLE") {
    if ((Test-Path "$root\EFI_OLD") -or -not (Test-Path "$root\EFI")) {
     return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Error = "TARGET_STATE_CONFLICT" }
    }
    Clear-SpecialAttributes "$root\EFI"
    Rename-Item -LiteralPath "$root\EFI" -NewName "EFI_OLD" -Force -ErrorAction Stop
   } else {
    if ((Test-Path "$root\EFI") -or -not (Test-Path "$root\EFI_OLD")) {
     return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Error = "TARGET_STATE_CONFLICT" }
    }
    Clear-SpecialAttributes "$root\EFI_OLD"
    Rename-Item -LiteralPath "$root\EFI_OLD" -NewName "EFI" -Force -ErrorAction Stop
   }
   return [PSCustomObject]@{ Success = $true; Status = "CHANGED"; Error = "" }
  } catch {
   return [PSCustomObject]@{ Success = $false; Status = "FAILED"; Error = $_.Exception.Message }
  }
 }

 if ($bootType -eq "MBR_ACTIVE") {
  $renamedBootmgr = $false
  try {
   if ($mode -eq "DISABLE") {
    if ((Test-Path "$root\bootmgr_OLD") -or (Test-Path "$root\Boot_OLD")) {
     return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Error = "TARGET_STATE_CONFLICT" }
    }
    if (Test-Path "$root\bootmgr") {
     Clear-SpecialAttributes "$root\bootmgr"
     Rename-Item -LiteralPath "$root\bootmgr" -NewName "bootmgr_OLD" -Force -ErrorAction Stop
     $renamedBootmgr = $true
    }
    if (Test-Path "$root\Boot\BCD") {
     Clear-SpecialAttributes "$root\Boot"
     Rename-Item -LiteralPath "$root\Boot" -NewName "Boot_OLD" -Force -ErrorAction Stop
    }
   } else {
    if ((Test-Path "$root\bootmgr") -or (Test-Path "$root\Boot\BCD")) {
     return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Error = "TARGET_STATE_CONFLICT" }
    }
    if (Test-Path "$root\bootmgr_OLD") {
     Clear-SpecialAttributes "$root\bootmgr_OLD"
     Rename-Item -LiteralPath "$root\bootmgr_OLD" -NewName "bootmgr" -Force -ErrorAction Stop
     $renamedBootmgr = $true
    }
    if (Test-Path "$root\Boot_OLD") {
     Clear-SpecialAttributes "$root\Boot_OLD"
     Rename-Item -LiteralPath "$root\Boot_OLD" -NewName "Boot" -Force -ErrorAction Stop
    }
   }
   return [PSCustomObject]@{ Success = $true; Status = "CHANGED"; Error = "" }
  } catch {
   # Roll back first rename if second rename failed
   if ($renamedBootmgr) {
    try {
     if ($mode -eq "DISABLE" -and (Test-Path "$root\bootmgr_OLD") -and -not (Test-Path "$root\bootmgr")) {
      Rename-Item -LiteralPath "$root\bootmgr_OLD" -NewName "bootmgr" -Force -ErrorAction SilentlyContinue
     } elseif ($mode -eq "RESTORE" -and (Test-Path "$root\bootmgr") -and -not (Test-Path "$root\bootmgr_OLD")) {
      Rename-Item -LiteralPath "$root\bootmgr" -NewName "bootmgr_OLD" -Force -ErrorAction SilentlyContinue
     }
    } catch {}
   }
   return [PSCustomObject]@{ Success = $false; Status = "FAILED"; Error = $_.Exception.Message }
  }
 }

 return [PSCustomObject]@{ Success = $false; Status = "SKIPPED"; Error = "UNSUPPORTED_TYPE" }
}

# Inspect partitions of an internal disk (Storage cmdlets or diskpart fallback)
function Get-DiskPartitionsNormalized([int]$diskNum, [bool]$useDiskpartFallback) {
 $out = @()
 if (-not $useDiskpartFallback) {
  $parts = @(Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue)
  foreach ($p in $parts) {
   $out += [PSCustomObject]@{
    PartitionNumber = $p.PartitionNumber
    DriveLetter = if ($p.DriveLetter) { [string]$p.DriveLetter } else { "" }
    GptType = [string]$p.GptType
    IsEsp = ($p.GptType -eq $gptEfiGuid)
    IsActive = [bool]$p.IsActive
    IsPrimary = ($null -ne $p.MbrType -and [int]$p.MbrType -gt 0 -and [int]$p.MbrType -ne 5 -and [int]$p.MbrType -ne 15)
    Size = [int64]$p.Size
   }
  }
  return $out
 }

 $lpRes = Invoke-NativeOem "diskpart.exe" "" ("select disk " + $diskNum + "`r`nlist partition`r`nexit`r`n")
 $parsedParts = @(Parse-DiskpartListPartition $lpRes.Lines)
 foreach ($pp in $parsedParts) {
  $dpRes = Invoke-NativeOem "diskpart.exe" "" ("select disk " + $diskNum + "`r`nselect partition " + $pp.PartitionNumber + "`r`ndetail partition`r`nexit`r`n")
  $det = Parse-DiskpartDetailPartition $dpRes.Lines
  $out += [PSCustomObject]@{
   PartitionNumber = $pp.PartitionNumber
   DriveLetter = $det.DriveLetter
   GptType = if ($det.IsEspGuid) { $gptEfiGuid } else { "" }
   IsEsp = ($pp.IsEsp -or $det.IsEspGuid)
   IsActive = $det.IsActive
   IsPrimary = $pp.IsPrimary
   Size = $pp.Size
  }
 }
 return $out
}

# Check mounted sibling partitions on a disk for WinPE/installer media markers
function Test-SiblingPartitionsForWinPE([array]$parts) {
 foreach ($p in $parts) {
  if ($p.DriveLetter -and (Test-Path "$($p.DriveLetter):\")) {
   $drv = "$($p.DriveLetter):"
   if ((Test-Path "$drv\sources\boot.wim") -or (Test-Path "$drv\sources\install.wim") -or (Test-Path "$drv\sources\install.esd") -or (Test-Path "$drv\ventoy\ventoy.json") -or (Test-Path "$drv\PhoenixPE.cfg") -or (Test-Path "$drv\HBCD_PE.ini") -or ((Test-Path "$drv\boot\boot.sdi") -and (Test-Path "$drv\sources"))) {
    return $true
   }
   try {
    $di = New-Object System.IO.DriveInfo ($p.DriveLetter)
    if ($di.IsReady -and $di.VolumeLabel -match "^(VTOYEFI|VENTOY|PHOENIXPE|WINPE|ESD-USB)$") {
     return $true
    }
   } catch {}
  }
 }
 return $false
}

# Scan all internal online disks for GPT EFI and MBR Active bootloader conflicts
function Get-InternalBootloaderReport([bool]$isWinPE) {
 $classified = Get-ClassifiedDisks $isWinPE
 $internalDisks = @($classified.InternalDisks)
 $useFallback = [bool]$classified.UsedFallback

 $bootDisk = $null
 $sysDisk = $null
 $protected = @()
 $sysDrvLetter = if ($env:SystemDrive -and $env:SystemDrive -match "^([A-Za-z]):") { $matches[1].ToUpper() } else { "C" }
 if (-not $isWinPE -and -not $useFallback) {
  $allParts = @(Get-Partition -ErrorAction SilentlyContinue)
  foreach ($p in $allParts) {
   if ($p.IsBoot) { $bootDisk = $p.DiskNumber; if ($protected -notcontains $p.DiskNumber) { $protected += $p.DiskNumber } }
   if ($p.IsSystem) { $sysDisk = $p.DiskNumber; if ($protected -notcontains $p.DiskNumber) { $protected += $p.DiskNumber } }
   if ($p.DriveLetter -and ([string]$p.DriveLetter).ToUpper() -eq $sysDrvLetter) {
    if ($null -eq $bootDisk) { $bootDisk = $p.DiskNumber }
    if ($protected -notcontains $p.DiskNumber) { $protected += $p.DiskNumber }
   }
  }
 }

 $diskPartsMap = @{}
 foreach ($d in $internalDisks) {
  $parts = @(Get-DiskPartitionsNormalized $d.Number $useFallback)
  $diskPartsMap[$d.Number] = $parts
  # Defense-in-depth: even in fallback mode on normal Windows, protect the SystemDrive disk
  if (-not $isWinPE -and ($protected -notcontains $d.Number)) {
   foreach ($p in $parts) {
    if ($p.DriveLetter -and $p.DriveLetter.ToUpper() -eq $sysDrvLetter) {
     if ($null -eq $bootDisk) { $bootDisk = $d.Number }
     $protected += $d.Number
     break
    }
   }
  }
 }

 $splitBoot = (-not $isWinPE -and $null -ne $bootDisk -and $null -ne $sysDisk -and $bootDisk -ne $sysDisk)
 $items = @()

 foreach ($d in $internalDisks) {
  $parts = @($diskPartsMap[$d.Number])
  $isProt = ($protected -contains $d.Number)
  $isDiskReadOnly = [bool]$d.IsReadOnly
  $isWinPEMediaDisk = (-not $isProt) -and (Test-SiblingPartitionsForWinPE $parts)
  $style = if ($d.PartitionStyle) { [string]$d.PartitionStyle } else { "Unknown" }

  $bootType = "NONE"
  $targetPartNum = 0
  $targetLtr = ""
  $state = "NO_BOOTLOADER"

  if ($isWinPEMediaDisk) {
   $state = "WINPE_MEDIA"
  } elseif ($isDiskReadOnly -and -not $isProt) {
   $state = "READONLY_PROTECTED"
  } else {
   $espParts = @($parts | Where-Object { $_.IsEsp })
   if ($espParts.Count -gt 0) {
    if ($isProt) {
     $bootType = "GPT_EFI"
     $targetPartNum = $espParts[0].PartitionNumber
     $targetLtr = $espParts[0].DriveLetter
     $state = "PROTECTED"
    } else {
     # Check all ESP partitions on the disk, prioritizing actionable conflicts over empty ESPs
     foreach ($ep in $espParts) {
      $probeState = Invoke-WithEspMount $d.Number $ep.PartitionNumber $ep.DriveLetter {
       param($drv)
       return (Inspect-BootloaderPartition "$($drv):\" "GPT_EFI" $false)
      }
      if ($targetPartNum -eq 0 -or $probeState -in @("ACTIVE","BOTH","WINPE_BLOCKED","OS_BLOCKED") -or ($state -eq "EMPTY" -and $probeState -eq "DISABLED")) {
       $bootType = "GPT_EFI"
       $targetPartNum = $ep.PartitionNumber
       $targetLtr = $ep.DriveLetter
       $state = $probeState
      }
      if ($state -in @("ACTIVE","BOTH","WINPE_BLOCKED")) { break }
     }
    }
   } elseif ($style -eq "MBR" -and -not $isProt) {
    # Check Active MBR partition first, or previously disabled (_OLD) small/mounted primary partitions
    $mbrCandidates = @($parts | Where-Object { $_.IsActive })
    if ($mbrCandidates.Count -eq 0) {
     $mbrCandidates = @($parts | Where-Object {
      $_.IsPrimary -and ($_.DriveLetter -or ($_.Size -gt 0 -and $_.Size -le 2GB))
     })
    }
    foreach ($mp in $mbrCandidates) {
     $probeState = Invoke-WithEspMount $d.Number $mp.PartitionNumber $mp.DriveLetter {
      param($drv)
      return (Inspect-BootloaderPartition "$($drv):\" "MBR_ACTIVE" $mp.IsActive)
     }
     if ($probeState -in @("ACTIVE","BOTH","DISABLED","MBR_OS_BLOCKED","WINPE_BLOCKED")) {
      $bootType = "MBR_ACTIVE"
      $targetPartNum = $mp.PartitionNumber
      $targetLtr = $mp.DriveLetter
      $state = $probeState
      break
     } elseif ($mp.IsActive -and $probeState -eq "EMPTY") {
      $bootType = "MBR_ACTIVE"
      $targetPartNum = $mp.PartitionNumber
      $targetLtr = $mp.DriveLetter
      $state = "EMPTY"
     }
    }
   } elseif ($isProt) {
    $state = "PROTECTED_OS"
   }
  }

  $sizeGB = if ($d.Size -gt 0) { [math]::Round($d.Size / 1GB, 1) } else { 0.0 }
  $items += [PSCustomObject]@{
   DiskNumber = $d.Number
   Model = $d.FriendlyName
   SizeGB = $sizeGB
   PartitionStyle = $style
   IsProtected = ($isProt -or $isWinPEMediaDisk -or $isDiskReadOnly)
   IsWinPEMedia = $isWinPEMediaDisk
   IsReadOnly = $isDiskReadOnly
   BootType = $bootType
   TargetPart = $targetPartNum
   TargetLetter = $targetLtr
   State = $state
  }
 }

 $actionable = @($items | Where-Object { $_.State -eq "ACTIVE" })
 $manualWarn = @($items | Where-Object { $_.State -in @("BOTH","MBR_OS_BLOCKED") })
 $allConflicts = @($items | Where-Object { $_.State -in @("ACTIVE","BOTH","MBR_OS_BLOCKED") })

 return [PSCustomObject]@{
  UsedFallback = $useFallback
  BootDisk = $bootDisk
  SysDisk = $sysDisk
  SplitBoot = $splitBoot
  Items = $items
  ActionableConflictItems = $actionable
  ManualWarningItems = $manualWarn
  ConflictItems = $allConflicts
  HasBlockingRisk = ($splitBoot -or $allConflicts.Count -gt 0)
 }
}

function Format-BootloaderStateText($item) {
 switch ($item.State) {
  "PROTECTED"          { return (U "[\uBCF4\uD638\uB428: \uD604\uC7AC OS/\uBD80\uD305 EFI]") }
  "PROTECTED_OS"       { return (U "[\uBCF4\uD638\uB428: \uD604\uC7AC OS \uB514\uC2A4\uD06C]") }
  "WINPE_MEDIA"        { return (U "[\uBCF4\uD638\uB428: WinPE/\uC124\uCE58 \uB9E4\uCCB4]") }
  "READONLY_PROTECTED" { return (U "[\uBCF4\uD638\uB428: \uC77D\uAE30 \uC804\uC6A9(\uC4F0\uAE30 \uAE08\uC9C0) \uB514\uC2A4\uD06C]") }
  "ACTIVE"         {
   if ($item.BootType -eq "MBR_ACTIVE") { return (U "[\uCDA9\uB3CC \uC704\uD5D8: MBR \uD65C\uC131 \uBD80\uD2B8\uB85C\uB354 \uBC1C\uACAC!]") }
   return (U "[\uCDA9\uB3CC \uC704\uD5D8: GPT \uD65C\uC131 EFI \uBC1C\uACAC!]")
  }
  "BOTH"           { return (U "[\uC8FC\uC758: \uD65C\uC131/\uBE44\uD65C\uC131 \uACF5\uC874 - \uC218\uB3D9 \uD655\uC778]") }
  "MBR_OS_BLOCKED" { return (U "[\uC8FC\uC758: \uAD6C\uD615 OS+MBR \uACF5\uC874 - \uC790\uB3D9 \uBCC0\uACBD \uCC28\uB2E8]") }
  "DISABLED"       {
   if ($item.BootType -eq "MBR_ACTIVE") { return (U "[\uC870\uCE58\uB428: MBR \uBD80\uD2B8\uB85C\uB354 \uBE44\uD65C\uC131(_OLD)]") }
   return (U "[\uC870\uCE58\uB428: GPT EFI \uBE44\uD65C\uC131(EFI_OLD)]")
  }
  "OS_BLOCKED"     { return (U "[\uCC28\uB2E8: OS \uD30C\uD2F0\uC158]") }
  "WINPE_BLOCKED"  { return (U "[\uCC28\uB2E8: WinPE/\uC124\uCE58 \uB9E4\uCCB4]") }
  "EMPTY"          { return (U "[\uC548\uC804: \uBE48 \uBD80\uD305 \uD30C\uD2F0\uC158]") }
  "NO_BOOTLOADER"  { return (U "[\uC548\uC804: \uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uC5C6\uC74C]") }
  "MOUNT_FAIL"     { return (U "[\uB9C8\uC6B4\uD2B8 \uC2E4\uD328]") }
  default          { return ("[" + $item.State + "]") }
 }
}

function Get-BootloaderStateColor($item) {
 if ($item.State -in @("ACTIVE","BOTH","MBR_OS_BLOCKED")) { return "Red" }
 if ($item.IsProtected) { return "Green" }
 if ($item.State -eq "DISABLED") { return "Cyan" }
 if ($item.State -in @("OS_BLOCKED","WINPE_BLOCKED","MOUNT_FAIL")) { return "Yellow" }
 return "Gray"
}

# Interactive non-destructive toggle for GPT EFI or MBR Active bootloader
# Returns: "CHANGED" | "CANCELLED" | "BLOCKED" | "SKIPPED" | "FAILED"
function Invoke-BootloaderToggle($item, [bool]$disableOnly) {
 if ($item.IsWinPEMedia) {
  Write-Host (" [" + (U "\uCC28\uB2E8") + "] Disk " + $item.DiskNumber + " : " + (U "WinPE/\uC124\uCE58 \uB9E4\uCCB4 \uB514\uC2A4\uD06C\uB85C \uAC10\uC9C0\uB418\uC5B4 \uBCF4\uD638\uB429\uB2C8\uB2E4.")) -ForegroundColor Red
  return "BLOCKED"
 }
 if ($item.IsReadOnly) {
  Write-Host (" [" + (U "\uCC28\uB2E8") + "] Disk " + $item.DiskNumber + " : " + (U "\uC77D\uAE30 \uC804\uC6A9(\uC4F0\uAE30 \uAE08\uC9C0) \uB514\uC2A4\uD06C\uB85C \uBCF4\uD638\uB429\uB2C8\uB2E4.")) -ForegroundColor Red
  return "BLOCKED"
 }
 if ($item.IsProtected) {
  Write-Host (" [" + (U "\uCC28\uB2E8") + "] Disk " + $item.DiskNumber + " (" + (U "\uD604\uC7AC OS/\uBD80\uD305 \uB514\uC2A4\uD06C") + ") " + (U "\uBCF4\uD638\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.")) -ForegroundColor Red
  return "BLOCKED"
 }
 if ($item.TargetPart -le 0 -or $item.BootType -eq "NONE") {
  Write-Host (" [" + (U "\uC548\uB0B4") + "] Disk " + $item.DiskNumber + " : " + (U "\uC870\uCE58 \uB300\uC0C1 \uBD80\uD2B8\uB85C\uB354 \uD30C\uD2F0\uC158\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.")) -ForegroundColor Yellow
  return "SKIPPED"
 }

 $toggleRes = Invoke-WithEspMount $item.DiskNumber $item.TargetPart $item.TargetLetter {
  param($drv)
  $root = "$($drv):\"
  $guard = Test-PartitionMediaGuard $root
  if ($guard.HasOs) {
   Write-Host (U " [\uCC28\uB2E8] OS \uD30C\uD2F0\uC158(ntoskrnl.exe)\uC774 \uAC10\uC9C0\uB418\uC5B4 \uC790\uB3D9 \uBCC0\uACBD\uC744 \uC911\uB2E8\uD569\uB2C8\uB2E4.") -ForegroundColor Red
   return "BLOCKED"
  }
  if ($guard.HasWinPE) {
   Write-Host (U " [\uCC28\uB2E8] WinPE/\uC124\uCE58 \uB9E4\uCCB4(boot.wim/\uC678\uC7A5 \uBD80\uD305 \uAD6C\uC870)\uAC00 \uAC10\uC9C0\uB418\uC5B4 \uC911\uB2E8\uD569\uB2C8\uB2E4.") -ForegroundColor Red
   return "BLOCKED"
  }

  Write-Host ("`n--- Disk " + $item.DiskNumber + " (" + $item.Model + ") | " + $item.BootType + " Part #" + $item.TargetPart + " (" + $drv + ":) ---") -ForegroundColor Cyan
  Get-ChildItem -Path $root -Force -ErrorAction SilentlyContinue | Format-Table Mode, LastWriteTime, Name -AutoSize | Out-String | Write-Host -ForegroundColor Gray

  if ($item.BootType -eq "GPT_EFI") {
   $hasEfi = Test-Path "$($drv):\EFI"
   $hasOld = Test-Path "$($drv):\EFI_OLD"
   if ($hasEfi -and $hasOld) {
    Write-Host (" [" + (U "\uC911\uB2E8") + "] Disk " + $item.DiskNumber + " : " + (U "\uD30C\uD2F0\uC158\uC5D0 \uD65C\uC131/\uBE44\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354\uAC00 \uACF5\uC874\uD569\uB2C8\uB2E4. \uC218\uB3D9 \uD655\uC778 \uD544\uC694.")) -ForegroundColor Yellow
    return "BLOCKED"
   }
   if ($hasEfi) {
    $yn = (Read-Host ("Disk " + $item.DiskNumber + " [EFI -> EFI_OLD] " + (U "\uBE44\uD65C\uC131\uD654\uD560\uAE4C\uC694? (Y/N)"))).Trim()
    if ($yn -match "^[yY]$") {
     $r = Invoke-BootloaderRenameInRoot $root "GPT_EFI" "DISABLE"
     if ($r.Success) {
      Write-Host (" [" + (U "\uC131\uACF5") + "] Disk " + $item.DiskNumber + " EFI -> EFI_OLD " + (U "\uBE44\uD65C\uC131\uD654 \uC644\uB8CC!")) -ForegroundColor Green
      return "CHANGED"
     } else {
      Write-Host ((U " [\uC2E4\uD328] \uC774\uB984 \uBCC0\uACBD \uC2E4\uD328: ") + $r.Error) -ForegroundColor Red
      return "FAILED"
     }
    } else {
     Write-Host (U " \uC791\uC5C5\uC744 \uCDE8\uC18C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Gray
     return "CANCELLED"
    }
   } elseif ($hasOld -and -not $disableOnly) {
    $yn = (Read-Host ("Disk " + $item.DiskNumber + " [EFI_OLD -> EFI] " + (U "\uBCF5\uAD6C\uD560\uAE4C\uC694? (Y/N)"))).Trim()
    if ($yn -match "^[yY]$") {
     $r = Invoke-BootloaderRenameInRoot $root "GPT_EFI" "RESTORE"
     if ($r.Success) {
      Write-Host (" [" + (U "\uC131\uACF5") + "] Disk " + $item.DiskNumber + " EFI_OLD -> EFI " + (U "\uBCF5\uAD6C \uC644\uB8CC!")) -ForegroundColor Green
      return "CHANGED"
     } else {
      Write-Host ((U " [\uC2E4\uD328] \uBCF5\uAD6C \uC2E4\uD328: ") + $r.Error) -ForegroundColor Red
      return "FAILED"
     }
    } else {
     Write-Host (U " \uC791\uC5C5\uC744 \uCDE8\uC18C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Gray
     return "CANCELLED"
    }
   }
   return "SKIPPED"
  }

  if ($item.BootType -eq "MBR_ACTIVE") {
   $hasActive = (Test-Path "$($drv):\bootmgr") -or (Test-Path "$($drv):\Boot\BCD")
   $hasOld = (Test-Path "$($drv):\bootmgr_OLD") -or (Test-Path "$($drv):\Boot_OLD")
   if ($hasActive -and $hasOld) {
    Write-Host (" [" + (U "\uC911\uB2E8") + "] Disk " + $item.DiskNumber + " : " + (U "\uD30C\uD2F0\uC158\uC5D0 \uD65C\uC131/\uBE44\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354\uAC00 \uACF5\uC874\uD569\uB2C8\uB2E4. \uC218\uB3D9 \uD655\uC778 \uD544\uC694.")) -ForegroundColor Yellow
    return "BLOCKED"
   }
   if ($hasActive) {
    $yn = (Read-Host ("Disk " + $item.DiskNumber + " " + (U "MBR \uD65C\uC131 \uBD80\uD2B8\uB85C\uB354(bootmgr/Boot)\uB97C \uBE44\uD65C\uC131\uD654(_OLD + inactive)\uD560\uAE4C\uC694? (Y/N)"))).Trim()
    if ($yn -match "^[yY]$") {
     $r = Invoke-BootloaderRenameInRoot $root "MBR_ACTIVE" "DISABLE"
     if ($r.Success) {
      $dpInact = Invoke-NativeOem "diskpart.exe" "" ("select disk " + $item.DiskNumber + "`r`nselect partition " + $item.TargetPart + "`r`ninactive`r`nexit`r`n")
      if ($dpInact.ExitCode -eq 0) {
       Write-Host (" [" + (U "\uC131\uACF5") + "] Disk " + $item.DiskNumber + " " + (U "MBR \uBD80\uD2B8\uB85C\uB354 \uBE44\uD65C\uC131\uD654 \uC644\uB8CC! (bootmgr/Boot -> _OLD, inactive)")) -ForegroundColor Green
      } else {
       Write-Host (U " [\uACBD\uACE0] \uD30C\uC77C \uC774\uB984 \uBCC0\uACBD\uC740 \uC644\uB8CC\uD588\uC73C\uB098 diskpart inactive \uC124\uC815\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
      }
      return "CHANGED"
     } else {
      Write-Host ((U " [\uC2E4\uD328] MBR \uBE44\uD65C\uC131\uD654 \uC2E4\uD328 (\uAD8C\uD55C/\uC7A0\uAE08 \uD655\uC778): ") + $r.Error) -ForegroundColor Red
      return "FAILED"
     }
    } else {
     Write-Host (U " \uC791\uC5C5\uC744 \uCDE8\uC18C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Gray
     return "CANCELLED"
    }
   } elseif ($hasOld -and -not $disableOnly) {
    $yn = (Read-Host ("Disk " + $item.DiskNumber + " " + (U "MBR \uBE44\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354(_OLD)\uB97C \uBCF5\uAD6C(+ active)\uD560\uAE4C\uC694? (Y/N)"))).Trim()
    if ($yn -match "^[yY]$") {
     $r = Invoke-BootloaderRenameInRoot $root "MBR_ACTIVE" "RESTORE"
     if ($r.Success) {
      $dpAct = Invoke-NativeOem "diskpart.exe" "" ("select disk " + $item.DiskNumber + "`r`nselect partition " + $item.TargetPart + "`r`nactive`r`nexit`r`n")
      if ($dpAct.ExitCode -eq 0) {
       Write-Host (" [" + (U "\uC131\uACF5") + "] Disk " + $item.DiskNumber + " " + (U "MBR \uBD80\uD2B8\uB85C\uB354 \uBCF5\uAD6C \uC644\uB8CC! (_OLD -> \uC6D0\uBCF5, active)")) -ForegroundColor Green
      } else {
       Write-Host (U " [\uACBD\uACE0] \uD30C\uC77C \uBCF5\uAD6C\uB294 \uC644\uB8CC\uD588\uC73C\uB098 diskpart active \uC124\uC815\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
      }
      return "CHANGED"
     } else {
      Write-Host ((U " [\uC2E4\uD328] MBR \uBCF5\uAD6C \uC2E4\uD328: ") + $r.Error) -ForegroundColor Red
      return "FAILED"
     }
    } else {
     Write-Host (U " \uC791\uC5C5\uC744 \uCDE8\uC18C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Gray
     return "CANCELLED"
    }
   }
   return "SKIPPED"
  }
  return "SKIPPED"
 }

 if ($toggleRes -eq "MOUNT_FAIL") {
  Write-Host (" [" + (U "\uC2E4\uD328") + "] Disk " + $item.DiskNumber + " " + (U "[\uB9C8\uC6B4\uD2B8 \uC2E4\uD328]")) -ForegroundColor Red
  return "FAILED"
 }
 return [string]$toggleRes
}

# Interactive Bootloader Manager (used in WinPE emergency mode or [E] menu)
function Show-BootloaderManager([bool]$isWinPE) {
 while ($true) {
  $rep = Get-InternalBootloaderReport $isWinPE
  Write-Host ("`n==================== [" + (U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC (GPT EFI / MBR)") + "] ====================") -ForegroundColor Cyan
  if ($rep.UsedFallback) {
   Write-Host (U " [\uC548\uB0B4] \uD604\uC7AC \uC2DC\uC2A4\uD15C\uC5D0 Storage \uBAA8\uB4C8\uC774 \uC5C6\uC5B4 diskpart \uD638\uD658 \uBAA8\uB4DC\uB85C \uC2A4\uCE94\uD569\uB2C8\uB2E4.") -ForegroundColor Yellow
  }
  foreach ($it in $rep.Items) {
   $stText = Format-BootloaderStateText $it
   $col = Get-BootloaderStateColor $it
   $partTag = if ($it.TargetPart -gt 0) { " | " + $it.BootType + " #" + $it.TargetPart } else { "" }
   Write-Host (" - Disk " + $it.DiskNumber + " : " + $it.Model + " [" + $it.SizeGB + " GB, " + $it.PartitionStyle + $partTag + "] -> " + $stText) -ForegroundColor $col
  }
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
  Write-Host (U " [\uB514\uC2A4\uD06C \uBC88\uD638] \uBD80\uD2B8\uB85C\uB354 \uBE44\uD65C\uC131\uD654/\uBCF5\uAD6C \uC804\uD658 | [R] \uC0C8\uB85C\uACE0\uCE68 | [Q/Enter] \uB3CC\uC544\uAC00\uAE30") -ForegroundColor White
  $c = (Read-Host (U "\uC120\uD0DD")).Trim()
  if ($c -match "^[rR]$") {
   continue
  } elseif ($c -match "^\d+$") {
   $target = $rep.Items | Where-Object { $_.DiskNumber -eq [int]$c } | Select-Object -First 1
   if ($target) { $null = Invoke-BootloaderToggle $target $false }
  } else {
   break
  }
 }
}
