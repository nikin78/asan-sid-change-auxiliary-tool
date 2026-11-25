<# :
@echo off
set "SELF_PATH=%~f0"
cd /d "%SystemRoot%\System32"

net session >nul 2>&1
if %errorlevel% neq 0 (
 powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF_PATH -Verb RunAs"
 exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$code = [System.IO.File]::ReadAllText($env:SELF_PATH); Invoke-Expression $code"
exit /b
#>

# ==============================================================================
# SID Change Auxiliary Tool (Pre-SID Bootloader/USB + Post-SID Spooler Reset)
# 100% Pure ASCII Single Hybrid Batch/PowerShell Utility
# ==============================================================================
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

function U([string]$str) {
 if ($null -eq $str) { return "" }
 return [regex]::Replace($str, '\\u([0-9a-fA-F]{4})', {
  param($m)
  [char][Convert]::ToInt32($m.Groups[1].Value, 16)
 })
}

$ErrorActionPreference = "Continue"
$script:ToolVersion = "2.0"
$gptEfiGuid = "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
$gptRecoveryGuid = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
$gptMsrGuid = "{e3c9e316-0b5c-4db8-817d-f92df00215ae}"
$mbrEfiFatTypes = @(11, 12, 14, 239)

# Resolve system OEM encoding (CP949 on Korean Windows, CP437 on EN-US, 65001 if UTF-8 beta)
function Get-SystemOemEncoding {
 try {
  $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
  if ($cp -gt 0) { return [System.Text.Encoding]::GetEncoding($cp) }
 } catch {}
 return [System.Text.Encoding]::Default
}

# Run native console commands (bcdedit, diskpart, bcdboot, netsh) safely with OEM decoding
function Invoke-NativeOem([string]$fileName, [string]$arguments = "", [string]$stdinText = $null) {
 $oemEnc = Get-SystemOemEncoding
 $prevOutEnc = $null
 $changedEnc = $false
 try {
  $prevOutEnc = [Console]::OutputEncoding
  if ($prevOutEnc -and $prevOutEnc.CodePage -ne $oemEnc.CodePage) {
   [Console]::OutputEncoding = $oemEnc
   $changedEnc = $true
  }
 } catch {}

 $psi = New-Object System.Diagnostics.ProcessStartInfo
 $psi.FileName = $fileName
 $psi.Arguments = $arguments
 $psi.UseShellExecute = $false
 $psi.CreateNoWindow = $true
 $psi.RedirectStandardOutput = $true
 $psi.RedirectStandardError = $true
 $psi.StandardOutputEncoding = $oemEnc
 $psi.StandardErrorEncoding = $oemEnc
 if ($null -ne $stdinText) { $psi.RedirectStandardInput = $true }

 $outText = ""
 $errText = ""
 $exitCode = -1
 try {
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  [void]$proc.Start()
  if ($null -ne $stdinText) {
   $proc.StandardInput.Write($stdinText)
   $proc.StandardInput.Flush()
   $proc.StandardInput.Close()
  }
  $outTask = $proc.StandardOutput.ReadToEndAsync()
  $errTask = $proc.StandardError.ReadToEndAsync()
  $proc.WaitForExit()
  $outText = $outTask.Result
  $errText = $errTask.Result
  $exitCode = $proc.ExitCode
 } catch {
  $errText = $_.Exception.Message
  $exitCode = -1
 } finally {
  if ($changedEnc -and $null -ne $prevOutEnc) {
   try { [Console]::OutputEncoding = $prevOutEnc } catch {}
  }
 }

 $lines = @()
 if ($outText) { $lines += ($outText -split "`r?`n") }
 if ($errText) { $lines += ($errText -split "`r?`n") }
 return [PSCustomObject]@{
  ExitCode = $exitCode
  StdOut = $outText
  StdErr = $errText
  Lines = $lines
 }
}

# Parse bcdedit /enum firmware output (supports both English and Korean Windows)
function Parse-BcdFirmwareLines([array]$lines) {
 $entries = @()
 $currentEntry = $null
 $reId   = "^(identifier|" + (U "\uC2DD\uBCC4\uC790") + ")\s+(\{[^\}]+\})"
 $reDesc = "^(description|" + (U "\uC124\uBA85") + ")\s+(.+)$"
 $rePath = "^(path|" + (U "\uACBD\uB85C") + ")\s+(.+)$"
 $reDev  = "^(device|" + (U "\uC7A5\uCE58") + ")\s+(.+)$"

 foreach ($line in $lines) {
  $trimmed = ([string]$line).Trim()
  if ($trimmed -match "^-{5,}$") {
   if ($currentEntry -and $currentEntry.Identifier) { $entries += $currentEntry }
   $currentEntry = @{ Identifier = ""; Description = ""; Path = ""; Device = "" }
  } elseif ($currentEntry) {
   if ($trimmed -match $reId) { $currentEntry.Identifier = $matches[2].Trim() }
   elseif ($trimmed -match $reDesc) { $currentEntry.Description = $matches[2].Trim() }
   elseif ($trimmed -match $rePath) { $currentEntry.Path = $matches[2].Trim() }
   elseif ($trimmed -match $reDev) { $currentEntry.Device = $matches[2].Trim() }
  }
 }
 if ($currentEntry -and $currentEntry.Identifier) { $entries += $currentEntry }
 return $entries
}

function Test-StorageCmdletsAvailable {
 try {
  $cmdDisk = Get-Command Get-Disk -ErrorAction SilentlyContinue
  $cmdPart = Get-Command Get-Partition -ErrorAction SilentlyContinue
  if (-not $cmdDisk -or -not $cmdPart) { return $false }
  $null = Get-Disk -ErrorAction Stop
  return $true
 } catch {
  return $false
 }
}

function Show-BcdDebug([array]$rawLines) {
 Write-Host "`n==================== [bcdedit /enum firmware] ====================" -ForegroundColor DarkCyan
 if ($rawLines -and $rawLines.Count -gt 0) {
  $rawLines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
 } else {
  Write-Host (U "(\uCD9C\uB825 \uC5C6\uC74C: bcdedit /enum firmware)") -ForegroundColor DarkGray
 }
 Write-Host "==================================================================" -ForegroundColor DarkCyan
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}

function Show-DiskDebug {
 Write-Host "`n==================== [Get-Disk / Get-Partition] ================" -ForegroundColor DarkCyan
 if (Test-StorageCmdletsAvailable) {
  Get-Disk | Format-Table Number, FriendlyName, BusType, PartitionStyle, OperationalStatus, IsBoot, IsSystem, IsRemovable, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
  Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, IsActive, GptType, MbrType, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
 } else {
  Write-Host (U "Storage \uBAA8\uB4C8(Get-Disk) \uBBF8\uC9C0\uC6D0 \uD658\uACBD - diskpart \uC9C4\uB2E8\uC73C\uB85C \uB300\uCCB4\uD569\uB2C8\uB2E4.") -ForegroundColor Yellow
  $dpRes = Invoke-NativeOem "diskpart.exe" "" "list disk`r`nlist volume`r`nexit`r`n"
  $dpRes.Lines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
 }
 Write-Host "==================================================================" -ForegroundColor DarkCyan
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}
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
 $reTypeLine = "^(Type|" + (U "\uC720\uD615") + ")\s*:\s*(.+)$"
 $reDiskIdLine = "^(Disk ID|" + (U "\uB514\uC2A4\uD06C") + "\s*ID)\s*:\s*(.+)$"
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
  } elseif (-not $foundDiskId -and $model -eq "Disk") {
   if ($t -notmatch "^(Microsoft DiskPart|Copyright|On computer|DISKPART>|Disk \d+ is now|" + (U "\uCEF4\uD4E8\uD130") + "|" + (U "\uB514\uC2A4\uD06C") + "\s+\d+)") {
    $model = $t
   }
  }
 }

 return [PSCustomObject]@{
  FriendlyName = $model
  BusType = $busType
  IsUsb = ($busType -match "USB")
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
  if ($s -match ("^\s*" + $rePartWord + "\s+(\d+)\s+(\S+)\s+(\d+\s*[KMGT]?B)\s+(\d+\s*[KMGT]?B)")) {
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

 foreach ($line in $lines) {
  $s = [string]$line
  $t = $s.Trim()
  if ($t -match $reActive) { $isActive = $true }
  if ($t -match "c12a7328-f81f-11d2-ba4b-00a0c93ec93b") { $isEspGuid = $true }
  if ($ltrColIdx -lt 0 -and $s -match "\bLtr\b") {
   $ltrColIdx = $s.IndexOf("Ltr")
  }
  if ($s -match $reVolLine) {
   if ($ltrColIdx -ge 0 -and $s.Length -gt ($ltrColIdx + 1)) {
    $seg = $s.Substring($ltrColIdx, [Math]::Min(3, $s.Length - $ltrColIdx)).Trim()
    if ($seg -match "^[A-Z]$") { $driveLetter = $seg }
   } elseif ($s -match ("^\*?\s*(?:Volume|" + (U "\uBCFC\uB968") + ")\s+\d+\s+([A-Z])\s{2,}")) {
    $driveLetter = $matches[1]
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
  $allDisks = @(Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' })
  $usbDisks = @($allDisks | Where-Object {
   -not $_.IsBoot -and -not $_.IsSystem -and
   ($_.BusType -eq 'USB' -or $_.IsRemovable -or [string]$_.Path -match "USBSTOR|UASP")
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

# Helper: Mount partition temporarily via diskpart, run scriptblock, always unmount
function Invoke-WithEspMount([int]$diskNum, [int]$partNum, [string]$existingLetter, [scriptblock]$action) {
 $workDrv = ""
 $tempMounted = $false
 if ($existingLetter -and (Test-Path "$($existingLetter):\")) {
  $workDrv = $existingLetter
 } else {
  $candidates = @("Z","W","V","U","T","S","R","Q","P","O","N","M")
  foreach ($l in $candidates) {
   if (-not (Test-Path "$($l):\")) {
    $dpScript = "select disk $diskNum`r`nselect part $partNum`r`nassign letter=$l`r`nexit`r`n"
    $null = Invoke-NativeOem "diskpart.exe" "" $dpScript
    if (Test-Path "$($l):\") {
     $workDrv = $l
     $tempMounted = $true
     break
    }
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
 } elseif ((Test-Path "$root\ventoy\ventoy.json") -or (Test-Path "$root\PhoenixPE.cfg")) {
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
    Clear-SpecialAttributes "$root\EFI"
    Rename-Item -LiteralPath "$root\EFI" -NewName "EFI_OLD" -Force -ErrorAction Stop
   } else {
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
   if ((Test-Path "$drv\sources\boot.wim") -or (Test-Path "$drv\sources\install.wim") -or (Test-Path "$drv\sources\install.esd") -or (Test-Path "$drv\ventoy\ventoy.json") -or (Test-Path "$drv\PhoenixPE.cfg")) {
    return $true
   }
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
 if (-not $isWinPE -and -not $useFallback) {
  $allParts = @(Get-Partition -ErrorAction SilentlyContinue)
  foreach ($p in $allParts) {
   if ($p.IsBoot) { $bootDisk = $p.DiskNumber; if ($protected -notcontains $p.DiskNumber) { $protected += $p.DiskNumber } }
   if ($p.IsSystem) { $sysDisk = $p.DiskNumber; if ($protected -notcontains $p.DiskNumber) { $protected += $p.DiskNumber } }
  }
 }
 $splitBoot = (-not $isWinPE -and $null -ne $bootDisk -and $null -ne $sysDisk -and $bootDisk -ne $sysDisk)
 $items = @()

 foreach ($d in $internalDisks) {
  $parts = @(Get-DiskPartitionsNormalized $d.Number $useFallback)
  $isProt = ($protected -contains $d.Number)
  $isWinPEMediaDisk = (-not $isProt) -and (Test-SiblingPartitionsForWinPE $parts)
  $style = if ($d.PartitionStyle) { [string]$d.PartitionStyle } else { "Unknown" }

  $bootType = "NONE"
  $targetPartNum = 0
  $targetLtr = ""
  $state = "NO_BOOTLOADER"

  if ($isWinPEMediaDisk) {
   $state = "WINPE_MEDIA"
  } else {
   $espPart = $parts | Where-Object { $_.IsEsp } | Select-Object -First 1
   if ($espPart) {
    $bootType = "GPT_EFI"
    $targetPartNum = $espPart.PartitionNumber
    $targetLtr = $espPart.DriveLetter
    if ($isProt) {
     $state = "PROTECTED"
    } else {
     $state = Invoke-WithEspMount $d.Number $targetPartNum $targetLtr {
      param($drv)
      return (Inspect-BootloaderPartition "$($drv):\" "GPT_EFI" $false)
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
   IsProtected = ($isProt -or $isWinPEMediaDisk)
   IsWinPEMedia = $isWinPEMediaDisk
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
  "PROTECTED"      { return (U "[\uBCF4\uD638\uB428: \uD604\uC7AC OS/\uBD80\uD305 EFI]") }
  "PROTECTED_OS"   { return (U "[\uBCF4\uD638\uB428: \uD604\uC7AC OS \uB514\uC2A4\uD06C]") }
  "WINPE_MEDIA"    { return (U "[\uBCF4\uD638\uB428: WinPE/\uC124\uCE58 \uB9E4\uCCB4]") }
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
# ==============================================================================
# Module 03: System Vendor Identification & BIOS Diagnostics (Samsung/HP/Dell)
# ==============================================================================

function Get-SystemInfo {
 $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
 $bb = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
 $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
 $rawVendor = "$($cs.Manufacturer) $($bb.Manufacturer) $($bios.Manufacturer)"
 $modelName = if ($cs.Model -and $cs.Model -notmatch "System Product Name|To be filled") {
  $cs.Model.Trim()
 } elseif ($bb.Product) {
  $bb.Product.Trim()
 } else {
  "Desktop PC"
 }

 $vendor = "Standard"
 if ($rawVendor -match "Samsung|SEC") { $vendor = "Samsung" }
 elseif ($rawVendor -match "HP|Hewlett-Packard") { $vendor = "HP" }
 elseif ($rawVendor -match "Dell") { $vendor = "Dell" }

 $vendorBiosHint = switch ($vendor) {
  "HP"      { "HP BIOS (F10): Advanced -> Boot Options -> USB Storage Boot [Enable] / Fast Boot [Disable]" }
  "Dell"    { "Dell BIOS (F2): Boot/USB Config -> Enable USB Boot Support [On] / Fastboot [Thorough]" }
  "Samsung" { "Samsung BIOS (F2): Boot -> Fast BIOS Mode [Disabled] / Secure Boot Control [Disabled]" }
  default   { "BIOS Setup: USB Boot [Enabled] / Fast Boot [Disabled] / Secure Boot [Disabled]" }
 }

 return [PSCustomObject]@{
  Vendor = $vendor
  ModelName = $modelName
  RawVendor = $rawVendor
  BiosHint = $vendorBiosHint
 }
}

function Test-IsUefiBoot {
 $res = Invoke-NativeOem "bcdedit.exe" "/enum {current}"
 foreach ($line in $res.Lines) {
  if ([string]$line -match "winload\.efi") { return $true }
 }
 return $false
}

function Get-BiosDiagnostics($sysInfo, [array]$usbDisks, [array]$bcdEntries) {
 $vendor = $sysInfo.Vendor
 $koBootMgr = U "Windows \uBD80\uD305 \uAD00\uB9AC\uC790"
 $excludeDescPattern = "Windows Boot Manager|" + [regex]::Escape($koBootMgr) + "|SATA|NVMe|Hard Drive \(SATA|Hard Drive \(NVMe|PXE|IPV4|IPV6|Network|CD/DVD"

 # Strict NVRAM USB check (excludes internal SSD brands like Samsung/Crucial/Micron)
 $nvramHasStrictUsbEntry = @(
  $bcdEntries | Where-Object {
   $_.Identifier -ne "{fwbootmgr}" -and $_.Identifier -ne "{bootmgr}" -and
   ([string]$_.Description -notmatch $excludeDescPattern) -and
   ([string]$_.Description -match "\bUSB\b|Removable|External|Flash|SanDisk|Ventoy|Phoenix")
  }
 ).Count -gt 0

 $secBoot = $false
 try { $secBoot = Confirm-SecureBootUEFI -ErrorAction Stop } catch { $secBoot = $false }

 $usbBootState = "Unknown"
 $usbBootDetail = ""
 $fastBootWarn = $false
 $fastBootDetail = ""

 if ($vendor -eq "HP") {
  try {
   $hpSettings = Get-CimInstance -Namespace "root\HP\InstrumentedBIOS" -ClassName "HP_BIOSSetting" -ErrorAction Stop
   $hpUsb = $hpSettings | Where-Object {
    [string]$_.Name -match "USB Storage Boot|USB Boot|Boot from USB|Removable Media Boot|USB Flash Media"
   }
   foreach ($item in $hpUsb) {
    $rawVal = if ($item.CurrentValue) { [string]$item.CurrentValue } else { [string]$item.Value }
    $activeVal = if ($rawVal -match "\*([^,]+)") { $matches[1].Trim() } else { $rawVal.Trim() }
    if ($activeVal -match "^(Disable|Disabled|No|Off)$") {
     $usbBootState = "Disabled"
     $usbBootDetail = "HP WMI: $($item.Name) = $activeVal"
    } elseif ($usbBootState -ne "Disabled" -and $activeVal -match "^(Enable|Enabled|Yes|On)$") {
     $usbBootState = "Enabled"
     $usbBootDetail = "HP WMI: $($item.Name) = $activeVal"
    }
   }
   $hpFast = $hpSettings | Where-Object { [string]$_.Name -match "^Fast Boot$" } | Select-Object -First 1
   if ($hpFast) {
    $fRaw = if ($hpFast.CurrentValue) { [string]$hpFast.CurrentValue } else { [string]$hpFast.Value }
    $fVal = if ($fRaw -match "\*([^,]+)") { $matches[1].Trim() } else { $fRaw.Trim() }
    if ($fVal -match "^(Enable|Enabled|Yes|On)$") {
     $fastBootWarn = $true
     $fastBootDetail = "HP WMI: Fast Boot = $fVal"
    }
   }
  } catch {
   $usbBootState = "UnverifiableHP"
   $usbBootDetail = U "HP WMI \uC870\uD68C \uC2E4\uD328 - F10 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
  }
 } elseif ($vendor -eq "Dell") {
  try {
   $dellSettings = Get-CimInstance -Namespace "root\dcim\sysman" -ClassName "DCIM_BIOSEnumeration" -ErrorAction Stop
   $dellUsb = $dellSettings | Where-Object {
    [string]$_.AttributeName -match "EnableUsbBootSupport|UsbBootSupport|UsbBoot|BootUsb|ExternalUsb|UsbPortsBoot|UsbStorage"
   }
   foreach ($item in $dellUsb) {
    $val = ($item.CurrentValue -join ",").Trim()
    if ($item.PossibleValues -and $item.PossibleValuesDescription) {
     $idx = [Array]::IndexOf($item.PossibleValues, $val)
     if ($idx -ge 0 -and $idx -lt $item.PossibleValuesDescription.Count) {
      $val = [string]$item.PossibleValuesDescription[$idx]
     }
    }
    if ($val -match "Disable|Off|None") {
     $usbBootState = "Disabled"
     $usbBootDetail = "Dell WMI: $($item.AttributeName) = $val"
    } elseif ($usbBootState -ne "Disabled" -and $val -match "Enable|On|All") {
     $usbBootState = "Enabled"
     $usbBootDetail = "Dell WMI: $($item.AttributeName) = $val"
    }
   }
   $dellFast = $dellSettings | Where-Object { [string]$_.AttributeName -match "^Fastboot$" } | Select-Object -First 1
   if ($dellFast) {
    $dfVal = ($dellFast.CurrentValue -join ",").Trim()
    if ($dellFast.PossibleValues -and $dellFast.PossibleValuesDescription) {
     $idx = [Array]::IndexOf($dellFast.PossibleValues, $dfVal)
     if ($idx -ge 0 -and $idx -lt $dellFast.PossibleValuesDescription.Count) {
      $dfVal = [string]$dellFast.PossibleValuesDescription[$idx]
     }
    }
    if ($dfVal -match "Minimal") {
     $fastBootWarn = $true
     $fastBootDetail = "Dell WMI: Fastboot = $dfVal"
    }
   }
  } catch {
   $usbBootState = "UnverifiableDell"
   $usbBootDetail = U "Dell WMI \uBBF8\uC124\uCE58(DCM \uC5C6\uC74C) - F2 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
  }
 }

 if ($usbBootState -eq "Unknown") {
  if ($vendor -eq "Samsung") {
   $usbBootState = "UnverifiableAMI"
   $usbBootDetail = U "Samsung/AMI BIOS WMI \uBBF8\uC9C0\uC6D0 - F2 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
  } elseif ($nvramHasStrictUsbEntry) {
   $usbBootState = "UnverifiableNVRAM"
   $usbBootDetail = U "WMI \uBBF8\uC9C0\uC6D0 / NVRAM USB \uD56D\uBAA9 \uAC10\uC9C0\uB428"
  } elseif ($usbDisks.Count -gt 0) {
   $usbBootState = "SuspectedDisabled"
   $usbBootDetail = U "USB \uC7A5\uCC29\uB428 / NVRAM \uBBF8\uB4F1\uB85D (BIOS \uCC28\uB2E8 \uB610\uB294 \uBD80\uD305 \uD6C4 \uC5F0\uACB0)"
  } else {
   $usbBootState = "UnverifiableAMI"
   $usbBootDetail = U "WMI \uBBF8\uC9C0\uC6D0 - BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
  }
 }

 return [PSCustomObject]@{
  SecureBoot = $secBoot
  UsbBootState = $usbBootState
  UsbBootDetail = $usbBootDetail
  FastBootWarn = $fastBootWarn
  FastBootDetail = $fastBootDetail
  BiosHint = $sysInfo.BiosHint
 }
}

function Show-BiosStatusDashboard($diag, [bool]$step1Bypassed) {
 if ($step1Bypassed) {
  Write-Host (U " * STEP 1 \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80 : [\uC8FC\uC758 - \uC0AC\uC6A9\uC790 \uD655\uC778(IGNORE)\uC73C\uB85C \uAC74\uB108\uB700]") -ForegroundColor Yellow
 } else {
  Write-Host (U " * STEP 1 \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80 : [\uD1B5\uACFC - \uCDA9\uB3CC \uC5C6\uC74C]") -ForegroundColor Green
 }

 if ($diag.SecureBoot) {
  Write-Host (U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uD65C\uC131\uD654\uB428 - ON (\uACBD\uACE0)]") -ForegroundColor Red
 } else {
  Write-Host (U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uBE44\uD65C\uC131\uD654 - OFF (\uC815\uC0C1)]") -ForegroundColor Green
 }

 if ($diag.UsbBootState -eq "Disabled") {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uBE44\uD65C\uC131\uD654 - OFF (\uACBD\uACE0)] (") + $diag.UsbBootDetail + ")") -ForegroundColor Red
 } elseif ($diag.UsbBootState -eq "SuspectedDisabled") {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uBE44\uD65C\uC131\uD654 \uC758\uC2EC - \uACBD\uACE0] (") + $diag.UsbBootDetail + ")") -ForegroundColor Red
 } elseif ($diag.UsbBootState -eq "Enabled") {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uD65C\uC131\uD654\uB428 - ON (\uC815\uC0C1)] (") + $diag.UsbBootDetail + ")") -ForegroundColor Green
 } else {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uD655\uC778 \uBD88\uAC00] (") + $diag.UsbBootDetail + ")") -ForegroundColor Yellow
 }

 if ($diag.FastBootWarn) {
  Write-Host ((U " * BIOS Fast Boot \uC635\uC158 : [\uD65C\uC131\uD654\uB428 - \uC8FC\uC758] (") + $diag.FastBootDetail + ")") -ForegroundColor Yellow
 }
 Write-Host (" * BIOS Hint          : " + $diag.BiosHint) -ForegroundColor DarkGray
}

# Gate 1: Secure Boot / Confirmed Disabled USB Boot
function Invoke-Gate1Check($diag, [array]$bcdOutput) {
 if (-not ($diag.SecureBoot -or ($diag.UsbBootState -eq "Disabled"))) {
  return "CONTINUE"
 }

 while ($true) {
  Write-Host "`n==================================================================" -ForegroundColor Red
  Write-Host (U " [\uACBD\uACE0] BIOS \uBD80\uD305 \uCC28\uB2E8 \uC694\uC18C\uAC00 \uAC10\uC9C0\uB418\uC5C8\uC2B5\uB2C8\uB2E4!") -ForegroundColor Red
  if ($diag.SecureBoot) {
   Write-Host (U " - Secure Boot\uAC00 \uCF1C\uC838 \uC788\uC5B4 WinPE \uBD80\uD305 \uB514\uC2A4\uD06C\uAC00 \uCC28\uB2E8\uB420 \uC218 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
  }
  if ($diag.UsbBootState -eq "Disabled") {
   Write-Host (U " - BIOS\uC5D0\uC11C USB \uBD80\uD305 \uC635\uC158\uC774 \uBE44\uD65C\uC131\uD654(Disabled)\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
  }
  Write-Host (" - " + $diag.BiosHint) -ForegroundColor DarkGray
  Write-Host "==================================================================" -ForegroundColor Red
  Write-Host (U " [Enter \uB610\uB294 B] \uC989\uC2DC BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305 (\uAD8C\uC7A5)") -ForegroundColor Cyan
  Write-Host (U " [I] \uACBD\uACE0\uB97C \uBB34\uC2DC\uD558\uACE0 USB \uBD80\uD305 \uBAA9\uB85D \uAC80\uC0C9 \uACC4\uC18D \uC9C4\uD589") -ForegroundColor White
  Write-Host (U " [E] \uB0B4\uC7A5 \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8") -ForegroundColor DarkCyan
  Write-Host (U " [M] \uBA54\uC778 \uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uAE30") -ForegroundColor Gray
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
  $gateChoice = (Read-Host (U "\uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694 (Enter=BIOS \uC9C4\uC785)")).Trim()
  if ($gateChoice -eq "" -or $gateChoice -match "^[bB]$") {
   shutdown /r /fw /f /t 0
   exit 0
  } elseif ($gateChoice -match "^[eE]$") {
   Show-BootloaderManager $false
  } elseif ($gateChoice -match "^[dD]$") {
   Show-BcdDebug $bcdOutput
  } elseif ($gateChoice -match "^[lL]$") {
   Show-DiskDebug
  } elseif ($gateChoice -match "^[iI]$") {
   return "CONTINUE"
  } elseif ($gateChoice -match "^[mMqQ]$") {
   return "RETURN_MAIN"
  }
 }
}
# ==============================================================================
# Module 04: Physical USB Inspection, 4-Tier NVRAM Matching & Confirmed Reboot
# ==============================================================================

function Get-PhysicalUsbInfo([array]$usbDisks) {
 $physicalUsbList = @()
 $usbDrivePatterns = @()
 $usbStrictModelPatterns = @()
 $usbPartPatterns = @()
 $anyEfiReadyUsb = $false

 foreach ($disk in $usbDisks) {
  $sizeGB = [math]::Round($disk.Size / 1GB, 1)
  $parts = @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue)
  $drvLetters = @()
  $hasEfi = $false

  if ($disk.FriendlyName) {
   $cleanName = $disk.FriendlyName.Trim()
   $usbStrictModelPatterns += [regex]::Escape($cleanName)
   foreach ($word in ($cleanName -split "[\s_-]+")) {
    if ($word.Length -ge 3 -and $word -notmatch "^(USB|SSD|HDD|Disk|Drive|Device|General|Generic|Flash|Storage|Media|Mass|UFD|3\.0|2\.0|3\.2)$") {
     $usbStrictModelPatterns += [regex]::Escape($word)
    }
   }
  }

  foreach ($p in $parts) {
   if ($p.GptType -eq $gptRecoveryGuid -or $p.GptType -eq $gptMsrGuid) { continue }
   $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
   $fs = if ($vol -and $vol.FileSystem) { [string]$vol.FileSystem } else { "" }
   $isEfiGpt = ($p.GptType -eq $gptEfiGuid)
   $isEfiMbr = ($null -ne $p.MbrType -and ($mbrEfiFatTypes -contains [int]$p.MbrType))
   $isFatFs = ($fs -match "^(FAT|FAT32|exFAT)$")

   if ($p.DriveLetter) {
    $d = "$($p.DriveLetter):"
    $fsDisplay = if ($fs) { $fs } else { "RAW" }
    $drvLetters += "$d($fsDisplay)"
    $hasBootFile = (Test-Path "$d\EFI\BOOT\BOOTX64.EFI") -or (Test-Path "$d\EFI\Microsoft\Boot\BCD")
    if ($hasBootFile -or $isEfiGpt -or $isEfiMbr -or $isFatFs) {
     $hasEfi = $true
     $anyEfiReadyUsb = $true
     $usbDrivePatterns += [regex]::Escape("partition=$d")
     $usbPartPatterns += "Partition\s+$($p.PartitionNumber)\b"
    }
   } elseif ($isEfiGpt -or $isEfiMbr -or $isFatFs) {
    $partTag = if ($isEfiGpt) { "GPT-EFI" } elseif ($isEfiMbr) { "MBR-EFI/FAT" } else { "FAT" }
    $drvLetters += "Hidden-$partTag(Partition $($p.PartitionNumber))"
    $hasEfi = $true
    $anyEfiReadyUsb = $true
    $usbPartPatterns += "Partition\s+$($p.PartitionNumber)\b"
   }
  }

  $physicalUsbList += [PSCustomObject]@{
   DiskNumber = $disk.Number
   Model = $disk.FriendlyName
   SizeGB = "$sizeGB GB"
   Partitions = ($drvLetters -join ", ")
   IsEfiReady = $hasEfi
  }
 }

 return [PSCustomObject]@{
  PhysicalUsbList = $physicalUsbList
  UsbDrivePatterns = $usbDrivePatterns
  UsbStrictModelPatterns = $usbStrictModelPatterns
  UsbPartPatterns = $usbPartPatterns
  AnyEfiReadyUsb = $anyEfiReadyUsb
 }
}

function Find-MatchedUsbNvramEntries(
 [array]$bcdEntries,
 [array]$internalDriveLetters,
 [array]$usbDrivePatterns,
 [array]$usbStrictModelPatterns,
 [array]$usbPartPatterns,
 [bool]$anyEfiReadyUsb
) {
 $koBootMgr = U "Windows \uBD80\uD305 \uAD00\uB9AC\uC790"
 $excludeDesc = "Windows Boot Manager|" + [regex]::Escape($koBootMgr) + "|PXE|IPV4|IPV6|Network|Hard Drive \(SATA|Hard Drive \(NVMe|CD/DVD|Onboard NIC|HTTP"
 $internalPattern = if ($internalDriveLetters -and $internalDriveLetters.Count -gt 0) {
  ($internalDriveLetters | ForEach-Object { [regex]::Escape($_) }) -join "|"
 } else {
  ""
 }

 $candidateEntries = @($bcdEntries | Where-Object {
  $_.Identifier -ne "{fwbootmgr}" -and
  $_.Identifier -ne "{bootmgr}" -and
  ([string]$_.Description -notmatch $excludeDesc) -and
  ((-not $internalPattern) -or ([string]$_.Device -notmatch $internalPattern))
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

 # Tier 1: Exact drive letter match
 if ($usbDrivePatterns -and $usbDrivePatterns.Count -gt 0) {
  $drvRegex = ($usbDrivePatterns | Select-Object -Unique) -join "|"
  foreach ($c in $candidateEntries) {
   if ([string]$c.Device -match $drvRegex) {
    & $addMatch $c (U "\uC815\uD655 \uC77C\uCE58 - \uB4DC\uB77C\uC774\uBE0C") $true
   }
  }
 }

 # Tier 2: Exact disk model name match
 if ($usbStrictModelPatterns -and $usbStrictModelPatterns.Count -gt 0) {
  $modelRegex = ($usbStrictModelPatterns | Select-Object -Unique) -join "|"
  foreach ($c in $candidateEntries) {
   if ([string]$c.Description -match $modelRegex) {
    & $addMatch $c (U "\uC815\uD655 \uC77C\uCE58 - \uBAA8\uB378\uBA85") $true
   }
  }
 }

 # Tier 3: Partition number + UEFI/USB keyword match
 if ($matched.Count -eq 0 -and $usbPartPatterns -and $usbPartPatterns.Count -gt 0) {
  $partRegex = ($usbPartPatterns | Select-Object -Unique) -join "|"
  foreach ($c in $candidateEntries) {
   if ([string]$c.Description -match $partRegex -and [string]$c.Description -match "UEFI|USB|Partition") {
    & $addMatch $c (U "\uD30C\uD2F0\uC158 \uC77C\uCE58") $true
   }
  }
 }

 # Tier 4: Generic UEFI USB NVRAM entry fallback
 if ($matched.Count -eq 0 -and $anyEfiReadyUsb) {
  $genericUsbRegex = "USB Hard Drive|USB Flash|USB Device|Removable Device|External|Mass Storage|\bUSB\b"
  foreach ($c in $candidateEntries) {
   if ([string]$c.Description -match $genericUsbRegex) {
    & $addMatch $c (U "\uBC94\uC6A9 UEFI USB \uD56D\uBAA9") $false
   }
  }
 }

 return @($matched)
}

function Invoke-PreSidUsbBootStep($sysInfo, [bool]$step1Bypassed) {
 $gate1Ignored = $false

 while ($true) {
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host (U " [\uC0AC\uC804 \uC791\uC5C5 - STEP 2/2] BIOS \uCC28\uB2E8 \uC694\uC18C \uC810\uAC80 \uBC0F WinPE USB \uBD80\uD305") -ForegroundColor Cyan
  Write-Host ("   System : [" + $sysInfo.Vendor + "] (" + $sysInfo.ModelName + ")") -ForegroundColor DarkCyan
  Write-Host "==================================================================" -ForegroundColor Cyan

  $bcdRes = Invoke-NativeOem "bcdedit.exe" "/enum firmware"
  $bcdOutput = @($bcdRes.Lines)
  $entries = @(Parse-BcdFirmwareLines $bcdOutput)

  $diskSplit = Get-ClassifiedDisks $false
  $usbDisks = @($diskSplit.UsbDisks)
  $internalDisks = @($diskSplit.InternalDisks)
  $internalDriveLetters = @()
  $internalDiskNums = @($internalDisks | Select-Object -ExpandProperty Number)
  if ($internalDiskNums.Count -gt 0 -and (Test-StorageCmdletsAvailable)) {
   $internalDriveLetters = @(Get-Partition -DiskNumber $internalDiskNums -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { "partition=$($_.DriveLetter):" })
  }

  $diag = Get-BiosDiagnostics $sysInfo $usbDisks $entries
  Show-BiosStatusDashboard $diag $step1Bypassed

  if (-not $gate1Ignored) {
   $g1 = Invoke-Gate1Check $diag $bcdOutput
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
    elseif ($noUsbChoice -match "^[bB]$") { shutdown /r /fw /f /t 0; exit 0 }
    elseif ($noUsbChoice -match "^[eE]$") { Show-BootloaderManager $false }
    elseif ($noUsbChoice -match "^[dD]$") { Show-BcdDebug $bcdOutput }
    elseif ($noUsbChoice -match "^[lL]$") { Show-DiskDebug }
    elseif ($noUsbChoice -eq "" -or $noUsbChoice -match "^[mMqQ]$") { return }
   }
   if ($rescanNow) { continue }
   return
  }

  # Inspect physical USB partitions
  $usbInfo = Get-PhysicalUsbInfo $usbDisks
  Write-Host (U "`n[STEP 2-1] \uD604\uC7AC \uC5F0\uACB0\uB41C \uBB3C\uB9AC USB \uB514\uC2A4\uD06C \uBAA9\uB85D:") -ForegroundColor Cyan
  foreach ($u in $usbInfo.PhysicalUsbList) {
   $efiTag = if ($u.IsEfiReady) { U "UEFI \uBD80\uD305 \uAC00\uB2A5" } else { U "EFI \uD30C\uD2F0\uC158 \uBBF8\uD655\uC778" }
   Write-Host (" - Disk " + $u.DiskNumber + " : " + $u.Model + " [" + $u.SizeGB + "] | " + $u.Partitions + " -> (" + $efiTag + ")") -ForegroundColor White
  }

  $matchedEntries = @(Find-MatchedUsbNvramEntries `
   $entries `
   $internalDriveLetters `
   $usbInfo.UsbDrivePatterns `
   $usbInfo.UsbStrictModelPatterns `
   $usbInfo.UsbPartPatterns `
   $usbInfo.AnyEfiReadyUsb)

  # Gate 2: Physical USB found, but 0 matching NVRAM entries
  if ($matchedEntries.Count -eq 0) {
   $isLikelyHotPlug = ($diag.UsbBootState -eq "Enabled" -and -not $diag.FastBootWarn)
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
     if ($isLikelyHotPlug) { shutdown /r /o /f /t 0 } else { shutdown /r /fw /f /t 0 }
     exit 0
    } elseif ($fbChoice -match "^[oO]$") { shutdown /r /o /f /t 0; exit 0 }
    elseif ($fbChoice -match "^[bB]$") { shutdown /r /fw /f /t 0; exit 0 }
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
   elseif ($choice -match "^[oO]$") { shutdown /r /o /f /t 0; exit 0 }
   elseif ($choice -match "^[bB]$") { shutdown /r /fw /f /t 0; exit 0 }
   elseif ($choice -match "^[mMqQ]$") { return }
  }

  if ($rescanNow) { continue }
  if (-not $selectedTarget) { return }

  # Set 1-time bootsequence and reboot
  $setRes = Invoke-NativeOem "bcdedit.exe" ("/set {fwbootmgr} bootsequence " + $selectedTarget.Identifier)
  if ($setRes.ExitCode -eq 0) {
   Write-Host ("`n-> [" + $selectedTarget.Description + (U "] \uBD80\uD305 \uC21C\uC11C \uC9C0\uC815 \uC644\uB8CC! \uC989\uC2DC \uC7AC\uBD80\uD305\uD569\uB2C8\uB2E4...")) -ForegroundColor Cyan
   shutdown /r /f /t 0
   exit 0
  } else {
   Write-Host (U "`n[\uC624\uB958] NVRAM \uBD80\uD305 \uC21C\uC11C \uBCC0\uACBD \uC2E4\uD328!") -ForegroundColor Red
   Write-Host ((U "\uC0C1\uC138 \uCD9C\uB825: ") + ($setRes.Lines -join " ")) -ForegroundColor Yellow
   Write-Host (U "[O] Windows \uC7A5\uCE58 \uC0AC\uC6A9 \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305 | [Enter/M] \uBA54\uC778 \uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uAE30") -ForegroundColor Cyan
   $errChoice = (Read-Host (U "\uC120\uD0DD")).Trim()
   if ($errChoice -match "^[oO]$") {
    shutdown /r /o /f /t 0
    exit 0
   }
   return
  }
 }
}
# ==============================================================================
# Module 05: Post-SID Printer Spooler Reset & Host/Client Status Diagnostics
# ==============================================================================

function Get-LocalMachineSid {
 try {
  $accs = @(Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount=True" -ErrorAction Stop)
  foreach ($a in $accs) {
   if ([string]$a.SID -match "^(S-1-5-21-\d+-\d+-\d+)-\d+$") {
    return $matches[1]
   }
  }
 } catch {}
 try {
  if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
   $u = Get-LocalUser -ErrorAction Stop | Select-Object -First 1
   if ($u -and [string]$u.SID.Value -match "^(S-1-5-21-\d+-\d+-\d+)-\d+$") {
    return $matches[1]
   }
  }
 } catch {}
 return (U "\uD655\uC778 \uBD88\uAC00")
}

function Test-TcpPortFast([string]$targetHost, [int]$port = 445, [int]$timeoutMs = 1000) {
 if (-not $targetHost) { return $false }
 $client = $null
 try {
  $client = New-Object System.Net.Sockets.TcpClient
  $iar = $client.BeginConnect($targetHost, $port, $null, $null)
  if (-not $iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)) {
   return $false
  }
  $client.EndConnect($iar)
  return $true
 } catch {
  return $false
 } finally {
  if ($client) { try { $client.Close() } catch {} }
 }
}

function Parse-NetworkPrinterServer([string]$printerName, [string]$portName, [string]$serverName) {
 if ($serverName) {
  $s = $serverName.Trim().TrimStart('\')
  if ($s) { return $s }
 }
 if ($printerName -match "^\\\\([^\\]+)\\") { return $matches[1] }
 if ($portName -match "^\\\\([^\\]+)\\") { return $matches[1] }
 return ""
}

function Clear-SpoolerQueueDirectory([string]$queueDir) {
 $deleted = 0
 $splShdDeleted = 0
 $failed = @()
 $beforeTotal = 0

 if (Test-Path -LiteralPath $queueDir) {
  $files = @(Get-ChildItem -LiteralPath $queueDir -File -Force -ErrorAction SilentlyContinue)
  $beforeTotal = $files.Count
  foreach ($f in $files) {
   $isJob = ($f.Extension -match "^\.(SPL|SHD)$")
   try {
    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
    $deleted++
    if ($isJob) { $splShdDeleted++ }
   } catch {
    $failed += $f.Name
   }
  }
 }

 $remaining = 0
 if (Test-Path -LiteralPath $queueDir) {
  $remaining = @(Get-ChildItem -LiteralPath $queueDir -File -Force -ErrorAction SilentlyContinue).Count
 }

 return [PSCustomObject]@{
  QueueDir = $queueDir
  BeforeCount = $beforeTotal
  DeletedCount = $deleted
  SplShdDeleted = $splShdDeleted
  RemainingCount = $remaining
  FailedFiles = $failed
 }
}

function Get-PostSidStatus {
 $compName = $env:COMPUTERNAME
 $machineSid = Get-LocalMachineSid

 # Spooler service status & start mode
 $spSvc = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
 $spCim = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue
 $spStatus = if ($spSvc) { [string]$spSvc.Status } else { "NotFound" }
 $spStartMode = if ($spCim -and $spCim.StartMode) { [string]$spCim.StartMode } else { "Unknown" }

 # Queue directory file count
 $queueDir = Join-Path $env:SystemRoot "System32\spool\PRINTERS"
 $qTotal = 0
 $qSplShd = 0
 if (Test-Path -LiteralPath $queueDir) {
  $qFiles = @(Get-ChildItem -LiteralPath $queueDir -File -Force -ErrorAction SilentlyContinue)
  $qTotal = $qFiles.Count
  $qSplShd = @($qFiles | Where-Object { $_.Extension -match "^\.(SPL|SHD)$" }).Count
 }

 # Installed, shared, and network printers
 $printers = @()
 $printerQueryErr = $false
 if ($spStatus -eq "Running") {
  try {
   if (Get-Command Get-Printer -ErrorAction SilentlyContinue) {
    $rawPrinters = @(Get-Printer -ErrorAction Stop)
    foreach ($p in $rawPrinters) {
     $srv = Parse-NetworkPrinterServer ([string]$p.Name) ([string]$p.PortName) ""
     $isNet = ([string]$p.Type -eq "Connection") -or ([string]$p.Name -like "\\*") -or ([string]$p.PortName -like "\\*")
     $printers += [PSCustomObject]@{
      Name = [string]$p.Name
      Shared = [bool]$p.Shared
      ShareName = [string]$p.ShareName
      PortName = [string]$p.PortName
      DriverName = [string]$p.DriverName
      IsNetwork = $isNet
      RemoteServer = $srv
     }
    }
   } else {
    $rawPrinters = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)
    foreach ($p in $rawPrinters) {
     $srv = Parse-NetworkPrinterServer ([string]$p.Name) ([string]$p.PortName) ([string]$p.ServerName)
     $isNet = [bool]$p.Network -or ([string]$p.Name -like "\\*") -or ([string]$p.PortName -like "\\*")
     $printers += [PSCustomObject]@{
      Name = [string]$p.Name
      Shared = [bool]$p.Shared
      ShareName = [string]$p.ShareName
      PortName = [string]$p.PortName
      DriverName = [string]$p.DriverName
      IsNetwork = $isNet
      RemoteServer = $srv
     }
    }
   }
  } catch {
   $printerQueryErr = $true
  }
 }

 # Also check HKCU\Printers\Connections for user-session network printers
 $seenNetNames = @{}
 foreach ($p in $printers) {
  if ($p.IsNetwork) { $seenNetNames[$p.Name.ToLower()] = $true }
 }
 try {
  if (Test-Path "HKCU:\Printers\Connections") {
   $connKeys = @(Get-ChildItem "HKCU:\Printers\Connections" -ErrorAction SilentlyContinue)
   foreach ($ck in $connKeys) {
    if ($ck.PSChildName -match "^,,([^,]+),(.+)$") {
     $unc = "\\" + $matches[1] + "\" + $matches[2]
     if (-not $seenNetNames.ContainsKey($unc.ToLower())) {
      $seenNetNames[$unc.ToLower()] = $true
      $printers += [PSCustomObject]@{
       Name = $unc
       Shared = $false
       ShareName = ""
       PortName = $unc
       DriverName = ""
       IsNetwork = $true
       RemoteServer = $matches[1]
      }
     }
    }
   }
  }
 } catch {}

 $sharedPrinters = @($printers | Where-Object { $_.Shared -and -not $_.IsNetwork })
 $networkPrinters = @($printers | Where-Object { $_.IsNetwork })
 $role = if ($sharedPrinters.Count -gt 0) { "Host" } else { "Client" }

 # Host diagnostics: File & Printer Sharing firewall rules + Network profiles
 $fwTotal = -1
 $fwEnabled = -1
 $netProfiles = @()
 $hasPublicProfile = $false
 if ($role -eq "Host") {
  try {
   $fwRules = @(Get-NetFirewallRule -Group "@FirewallAPI.dll,-28502" -Direction Inbound -ErrorAction Stop)
   if ($fwRules.Count -eq 0) {
    $koGroup = U "\uD30C\uC77C \uBC0F \uD504\uB9B0\uD130 \uACF5\uC720"
    $fwRules = @(Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Where-Object {
     $_.DisplayGroup -eq "File and Printer Sharing" -or $_.DisplayGroup -eq $koGroup
    })
   }
   $fwTotal = $fwRules.Count
   $fwEnabled = @($fwRules | Where-Object { [string]$_.Enabled -eq "True" }).Count
  } catch {
   $fwTotal = -1
   $fwEnabled = -1
  }

  try {
   $rawProfiles = @(Get-NetConnectionProfile -ErrorAction Stop)
   foreach ($np in $rawProfiles) {
    $cat = [string]$np.NetworkCategory
    if ($cat -eq "Public") { $hasPublicProfile = $true }
    $netProfiles += [PSCustomObject]@{
     Name = [string]$np.Name
     InterfaceAlias = [string]$np.InterfaceAlias
     Category = $cat
    }
   }
  } catch {}
 }

 # Client diagnostics: check unique remote print hosts (never test self)
 $remoteHostChecks = @()
 $checkedHosts = @{}
 foreach ($np in $networkPrinters) {
  $srv = $np.RemoteServer
  if (-not $srv) { continue }
  $srvKey = $srv.ToLower()
  if ($srvKey -eq $compName.ToLower() -or $srvKey -eq "localhost" -or $srvKey -eq "127.0.0.1") { continue }
  if (-not $checkedHosts.ContainsKey($srvKey)) {
   $checkedHosts[$srvKey] = $true
   $ok = Test-TcpPortFast $srv 445 1000
   $remoteHostChecks += [PSCustomObject]@{
    Server = $srv
    Reachable = $ok
   }
  }
 }

 return [PSCustomObject]@{
  ComputerName = $compName
  MachineSid = $machineSid
  Role = $role
  SpoolerStatus = $spStatus
  SpoolerStartMode = $spStartMode
  QueueDir = $queueDir
  QueueTotalCount = $qTotal
  QueueSplShdCount = $qSplShd
  PrinterQueryError = $printerQueryErr
  Printers = $printers
  SharedPrinters = $sharedPrinters
  NetworkPrinters = $networkPrinters
  FirewallInboundTotal = $fwTotal
  FirewallInboundEnabled = $fwEnabled
  NetworkProfiles = $netProfiles
  HasPublicProfile = $hasPublicProfile
  RemoteHostChecks = $remoteHostChecks
 }
}

function Invoke-SpoolerReset {
 Write-Host "`n==================================================================" -ForegroundColor Cyan
 Write-Host (U " [\uC9C4\uD589] \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B\uC744 \uC2DC\uC791\uD569\uB2C8\uB2E4...") -ForegroundColor Cyan
 Write-Host "==================================================================" -ForegroundColor Cyan

 # 1. Stop dependent services and Spooler
 Write-Host (U " 1/4. Spooler \uC11C\uBE44\uC2A4 \uC911\uC9C0 \uC911...") -ForegroundColor White
 $runningDeps = @()
 $stopMode = "FAILED"
 try {
  $deps = @(Get-Service -Name "Spooler" -DependentServices -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" })
  foreach ($d in $deps) {
   $runningDeps += $d.Name
   Stop-Service -Name $d.Name -Force -ErrorAction SilentlyContinue
  }
 } catch {}

 $sp = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
 if ($sp -and $sp.Status -eq "Stopped") {
  $stopMode = "NORMAL"
 } else {
  Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
  $stopped = $false
  for ($i = 0; $i -lt 20; $i++) {
   Start-Sleep -Milliseconds 500
   $spNow = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
   if ($spNow -and $spNow.Status -eq "Stopped") { $stopped = $true; break }
  }
  if ($stopped) {
   $stopMode = "NORMAL"
  } else {
   Write-Host (U "      \uC911\uC9C0 \uD0C0\uC784\uC544\uC6C3 - spoolsv \uD504\uB85C\uC138\uC2A4\uB97C \uC548\uC804 \uC885\uB8CC\uD569\uB2C8\uB2E4...") -ForegroundColor Yellow
   Stop-Process -Name "spoolsv" -Force -ErrorAction SilentlyContinue
   for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 500
    $spNow = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
    if ($spNow -and $spNow.Status -eq "Stopped") { $stopped = $true; break }
   }
   if ($stopped) { $stopMode = "FORCED" }
  }
 }

 # 2. Clear PRINTERS queue directory
 Write-Host (U " 2/4. \uB300\uAE30\uC5F4 \uD3F4\uB354(PRINTERS) \uC815\uB9AC \uC911...") -ForegroundColor White
 $queueDir = Join-Path $env:SystemRoot "System32\spool\PRINTERS"
 $qRes = Clear-SpoolerQueueDirectory $queueDir

 # 3. Restore StartType if Disabled
 Write-Host (U " 3/4. Spooler \uC2DC\uC791 \uC720\uD615 \uC810\uAC80 \uC911...") -ForegroundColor White
 $startRestored = $false
 $spCim = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue
 $curStartMode = if ($spCim -and $spCim.StartMode) { [string]$spCim.StartMode } else { "Unknown" }
 if ($curStartMode -eq "Disabled") {
  try {
   Set-Service -Name "Spooler" -StartupType Automatic -ErrorAction Stop
   $startRestored = $true
   $curStartMode = "Auto"
   Write-Host (U "      \uC2DC\uC791 \uC720\uD615\uC774 Disabled \uC0C1\uD0DC\uC5EC\uC11C Automatic(\uC790\uB3D9)\uC73C\uB85C \uBCF5\uAD6C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Green
  } catch {}
 }

 # 4. Start Spooler and restart previously running dependent services
 Write-Host (U " 4/4. Spooler \uC11C\uBE44\uC2A4 \uC7AC\uC2DC\uC791 \uC911...") -ForegroundColor White
 $startErr = ""
 try {
  Start-Service -Name "Spooler" -ErrorAction Stop
 } catch {
  $startErr = $_.Exception.Message
 }
 $isRunning = $false
 for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  $spNow = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
  if ($spNow -and $spNow.Status -eq "Running") { $isRunning = $true; break }
 }

 $restartedDeps = @()
 if ($isRunning -and $runningDeps.Count -gt 0) {
  foreach ($dName in $runningDeps) {
   try {
    Start-Service -Name $dName -ErrorAction Stop
    $restartedDeps += $dName
   } catch {}
  }
 }

 # Result report
 Write-Host ("`n-------------------- [" + (U "\uC2A4\uD480\uB7EC \uB9AC\uC14B \uACB0\uACFC \uB9AC\uD3EC\uD2B8") + "] --------------------") -ForegroundColor Cyan
 $stopText = switch ($stopMode) {
  "NORMAL" { U "\uC815\uC0C1 \uC911\uC9C0" }
  "FORCED" { U "\uD504\uB85C\uC138\uC2A4 \uAC15\uC81C \uC885\uB8CC \uD6C4 \uC911\uC9C0" }
  default  { U "\uC911\uC9C0 \uC2E4\uD328" }
 }
 Write-Host (" * " + (U "\uC11C\uBE44\uC2A4 \uC911\uC9C0") + "      : " + $stopText) -ForegroundColor $(if ($stopMode -eq "FAILED") { "Red" } else { "Green" })
 Write-Host (" * " + (U "\uB300\uAE30\uC5F4 \uD30C\uC77C \uC815\uB9AC") + " : " + $qRes.DeletedCount + (U "\uAC74 \uC0AD\uC81C \uC644\uB8CC") + " (SPL/SHD: " + $qRes.SplShdDeleted + ") | " + (U "\uC794\uC874 \uD30C\uC77C") + ": " + $qRes.RemainingCount + (U "\uAC74")) -ForegroundColor $(if ($qRes.RemainingCount -gt 0) { "Yellow" } else { "Green" })
 if ($qRes.FailedFiles.Count -gt 0) {
  Write-Host ("   - " + (U "\uC7A0\uAE40/\uC2E4\uD328") + ": " + ($qRes.FailedFiles -join ", ")) -ForegroundColor Yellow
 }
 $startTypeText = if ($startRestored) { U "Automatic\uC73C\uB85C \uBCF5\uAD6C\uB428" } else { $curStartMode + " (" + (U "\uC720\uC9C0") + ")" }
 Write-Host (" * " + (U "\uC2DC\uC791 \uC720\uD615") + "        : " + $startTypeText) -ForegroundColor $(if ($startRestored) { "Green" } else { "Gray" })
 if ($runningDeps.Count -gt 0) {
  Write-Host (" * " + (U "\uC758\uC874 \uC11C\uBE44\uC2A4 \uC911\uC9C0/\uC7AC\uC2DC\uC791") + " : " + $restartedDeps.Count + "/" + $runningDeps.Count + " " + (U "\uC7AC\uC2DC\uC791 \uC644\uB8CC")) -ForegroundColor Gray
 }
 if ($isRunning) {
  Write-Host (" * " + (U "\uCD5C\uC885 \uC11C\uBE44\uC2A4 \uC0C1\uD0DC") + " : " + (U "\uC815\uC0C1 \uC2E4\uD589 \uC911 (Running)")) -ForegroundColor Green
  Write-Host ("`n " + (U "\uC644\uB8CC! \uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uD074\uB77C\uC774\uC5B8\uD2B8 PC \uBAA8\uB450\uC5D0\uC11C \uC2E4\uD589\uD55C \uB4A4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB97C \uD655\uC778\uD558\uC138\uC694.")) -ForegroundColor Cyan
 } else {
  Write-Host (" * " + (U "\uCD5C\uC885 \uC11C\uBE44\uC2A4 \uC0C1\uD0DC") + " : " + (U "\uC2DC\uC791 \uC2E4\uD328") + $(if ($startErr) { " (" + $startErr + ")" } else { "" })) -ForegroundColor Red
 }
 Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
 Read-Host (U "\uACC4\uC18D\uD558\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}

function Show-PostSidStatusScreen($st) {
 Clear-Host
 Write-Host "==================================================================" -ForegroundColor Cyan
 Write-Host (U " [SID \uBCC0\uACBD \uC0AC\uD6C4 \uC791\uC5C5] \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uBC0F \uACF5\uC720 \uC0C1\uD0DC \uC9C4\uB2E8") -ForegroundColor Cyan
 Write-Host "==================================================================" -ForegroundColor Cyan
 Write-Host (" " + (U "\uC548\uB0B4: SID \uBCC0\uACBD \uD6C4 \uACF5\uC720 \uD504\uB9B0\uD130 \uC815\uC0C1 \uC774\uC6A9\uC744 \uC704\uD574 [\uBA54\uC778 \uD504\uB9B0\uD130 PC]\uC640 [\uD074\uB77C\uC774\uC5B8\uD2B8 PC] \uAC01\uAC01\uC5D0\uC11C \uD55C \uBC88\uC529 \uC2E4\uD589\uD558\uC138\uC694.")) -ForegroundColor Yellow
 Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

 $roleLabel = if ($st.Role -eq "Host") { U "[\uD638\uC2A4\uD2B8(\uBA54\uC778 \uD504\uB9B0\uD130 PC)]" } else { U "[\uD074\uB77C\uC774\uC5B8\uD2B8]" }
 $roleColor = if ($st.Role -eq "Host") { "Cyan" } else { "Green" }
 Write-Host (" * " + (U "PC \uC5ED\uD560 \uD310\uBCC4") + "        : " + $roleLabel) -ForegroundColor $roleColor
 Write-Host (" * " + (U "\uCEF4\uD4E8\uD130 \uC774\uB984") + "        : " + $st.ComputerName) -ForegroundColor White
 Write-Host (" * " + (U "\uD604\uC7AC Machine SID") + "   : " + $st.MachineSid) -ForegroundColor DarkGray

 $svcStateText = if ($st.SpoolerStatus -eq "Running") { U "\uC2E4\uD589 \uC911 (Running)" } elseif ($st.SpoolerStatus -eq "Stopped") { U "\uC911\uC9C0\uB428 (Stopped)" } else { $st.SpoolerStatus }
 $svcStartText = switch ($st.SpoolerStartMode) {
  "Auto"     { U "\uC790\uB3D9 (Automatic)" }
  "Manual"   { U "\uC218\uB3D9 (Manual)" }
  "Disabled" { U "\uC0AC\uC6A9 \uC548 \uD568(\uACBD\uACE0)" }
  default    { $st.SpoolerStartMode }
 }
 $svcColor = if ($st.SpoolerStatus -eq "Running" -and $st.SpoolerStartMode -ne "Disabled") { "Green" } else { "Red" }
 Write-Host (" * " + (U "Spooler \uC11C\uBE44\uC2A4") + "      : " + $svcStateText + " | " + (U "\uC2DC\uC791 \uC720\uD615") + ": " + $svcStartText) -ForegroundColor $svcColor
 Write-Host (" * " + (U "\uB300\uAE30\uC5F4 \uD30C\uC77C(PRINTERS)") + ": " + $st.QueueTotalCount + (U "\uAC74") + " (SPL/SHD: " + $st.QueueSplShdCount + (U "\uAC74") + ")") -ForegroundColor $(if ($st.QueueTotalCount -gt 0) { "Yellow" } else { "Green" })

 # Installed printers
 Write-Host ("`n" + (U "[\uC124\uCE58\uB41C \uD504\uB9B0\uD130 \uBAA9\uB85D]")) -ForegroundColor Cyan
 if ($st.SpoolerStatus -ne "Running") {
  Write-Host (" - " + (U "(Spooler \uC911\uC9C0 \uC0C1\uD0DC - \uB9AC\uC14B \uD6C4 \uBAA9\uB85D\uC774 \uD45C\uC2DC\uB429\uB2C8\uB2E4)")) -ForegroundColor Yellow
 } elseif ($st.Printers.Count -eq 0) {
  Write-Host (" - " + (U "(\uC124\uCE58\uB41C \uD504\uB9B0\uD130 \uC5C6\uC74C)")) -ForegroundColor DarkGray
 } else {
  foreach ($p in $st.Printers) {
   $flags = @()
   if ($p.Shared) { $flags += ("Shared: " + $p.ShareName) }
   if ($p.IsNetwork) { $flags += "Network" }
   $flagStr = if ($flags.Count -gt 0) { " [" + ($flags -join ", ") + "]" } else { "" }
   Write-Host (" - " + $p.Name + " (" + $p.PortName + ")" + $flagStr) -ForegroundColor White
  }
 }

 # Host-specific diagnostics
 if ($st.Role -eq "Host") {
  Write-Host ("`n" + (U "[\uD638\uC2A4\uD2B8 \uC9C4\uB2E8 - \uACF5\uC720 \uD504\uB9B0\uD130 \uBC0F \uB124\uD2B8\uC6CC\uD06C/\uBC29\uD654\uBCBD]")) -ForegroundColor Cyan
  foreach ($spItem in $st.SharedPrinters) {
   Write-Host (" - " + (U "\uACF5\uC720 \uC911\uC778 \uD504\uB9B0\uD130") + " : " + $spItem.Name + " | " + (U "\uACF5\uC720 \uACBD\uB85C") + ": \\" + $st.ComputerName + "\" + $spItem.ShareName) -ForegroundColor Green
  }
  if ($st.FirewallInboundTotal -lt 0) {
   Write-Host (" - " + (U "\uD30C\uC77C \uBC0F \uD504\uB9B0\uD130 \uACF5\uC720 \uBC29\uD654\uBCBD") + " : " + (U "\uC870\uD68C \uBD88\uAC00")) -ForegroundColor Yellow
  } elseif ($st.FirewallInboundEnabled -eq 0) {
   Write-Host (" - " + (U "\uD30C\uC77C \uBC0F \uD504\uB9B0\uD130 \uACF5\uC720 \uBC29\uD654\uBCBD") + " : 0/" + $st.FirewallInboundTotal + " (" + (U "\uACBD\uACE0: \uD30C\uC77C \uBC0F \uD504\uB9B0\uD130 \uACF5\uC720 \uBC29\uD654\uBCBD \uADDC\uCE59\uC774 \uBAA8\uB450 \uBE44\uD65C\uC131\uD654\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4!") + ")") -ForegroundColor Red
  } else {
   Write-Host (" - " + (U "\uD30C\uC77C \uBC0F \uD504\uB9B0\uD130 \uACF5\uC720 \uBC29\uD654\uBCBD") + " : " + $st.FirewallInboundEnabled + "/" + $st.FirewallInboundTotal + " " + (U "\uC778\uBC14\uC6B4\uB4DC \uADDC\uCE59 \uD65C\uC131\uD654")) -ForegroundColor Green
  }
  if ($st.NetworkProfiles.Count -gt 0) {
   foreach ($np in $st.NetworkProfiles) {
    $catText = switch ($np.Category) {
     "Public"              { U "\uACF5\uC6A9(Public)" }
     "Private"             { U "\uAC1C\uC778(Private)" }
     "DomainAuthenticated" { U "\uB3C4\uBA54\uC778(Domain)" }
     default               { $np.Category }
    }
    $catCol = if ($np.Category -eq "Public") { "Red" } else { "Green" }
    Write-Host (" - " + (U "\uB124\uD2B8\uC6CC\uD06C \uD504\uB85C\uD544") + " : " + $np.InterfaceAlias + " (" + $np.Name + ") -> " + $catText) -ForegroundColor $catCol
   }
   if ($st.HasPublicProfile) {
    Write-Host ("   " + (U "[\uACBD\uACE0: \uACF5\uC6A9(Public) \uB124\uD2B8\uC6CC\uD06C - \uACF5\uC720 \uD504\uB9B0\uD130 \uC811\uC18D\uC774 \uCC28\uB2E8\uB420 \uC218 \uC788\uC2B5\uB2C8\uB2E4! \uAC1C\uC778(Private) \uAD8C\uC7A5]")) -ForegroundColor Yellow
   }
  }
 }

 # Client-specific diagnostics (shown for Client PCs, or Host PCs that also have remote network printers)
 if ($st.Role -eq "Client" -or $st.NetworkPrinters.Count -gt 0) {
  Write-Host ("`n" + (U "[\uD074\uB77C\uC774\uC5B8\uD2B8 \uC9C4\uB2E8 - \uC5F0\uACB0\uB41C \uB124\uD2B8\uC6CC\uD06C \uD504\uB9B0\uD130 \uBC0F \uD638\uC2A4\uD2B8 \uC751\uB2F5]")) -ForegroundColor Cyan
  if ($st.NetworkPrinters.Count -eq 0) {
   Write-Host (" - " + (U "\uC5F0\uACB0\uB41C \uB124\uD2B8\uC6CC\uD06C \uD504\uB9B0\uD130 \uC5C6\uC74C (\uC544\uC9C1 \uBBF8\uC5F0\uACB0 \uB610\uB294 \uB2E4\uB978 \uC0AC\uC6A9\uC790 \uC138\uC158\uC5D0 \uC5F0\uACB0\uB428)")) -ForegroundColor DarkGray
  } else {
   foreach ($netP in $st.NetworkPrinters) {
    Write-Host (" - " + $netP.Name) -ForegroundColor White
   }
   foreach ($hc in $st.RemoteHostChecks) {
    if ($hc.Reachable) {
     Write-Host ("   -> \\" + $hc.Server + " : " + (U "SMB(445) \uC751\uB2F5 \uC815\uC0C1")) -ForegroundColor Green
    } else {
     Write-Host ("   -> \\" + $hc.Server + " : " + (U "\uC751\uB2F5 \uC5C6\uC74C (\uBA54\uC778 PC \uC804\uC6D0/\uBC29\uD654\uBCBD/\uB124\uD2B8\uC6CC\uD06C \uD655\uC778)")) -ForegroundColor Yellow
    }
   }
  }
 }

 Write-Host "`n------------------------------------------------------------------" -ForegroundColor DarkGray
 Write-Host (U " [Enter \uB610\uB294 R] \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589 (\uB300\uAE30\uC5F4 \uBE44\uC6B0\uAE30 + \uC11C\uBE44\uC2A4 \uC7AC\uC2DC\uC791) (\uAD8C\uC7A5)") -ForegroundColor Green
 Write-Host (U " (\uAE30\uC874 \uD504\uB9B0\uD130, \uB4DC\uB77C\uC774\uBC84, \uACF5\uC720 \uC124\uC815\uC740 \uC0AD\uC81C\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.)") -ForegroundColor DarkGray
 Write-Host (U " [F] \uC0C1\uD0DC \uC0C8\uB85C\uACE0\uCE68 | [M] \uBA54\uC778 \uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uAE30") -ForegroundColor Gray
 Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
}

function Invoke-PostSidWorkflow($sysInfo) {
 while ($true) {
  $st = Get-PostSidStatus
  Show-PostSidStatusScreen $st
  $c = (Read-Host (U "\uC120\uD0DD")).Trim()
  if ($c -eq "" -or $c -match "^[rR]$") {
   Invoke-SpoolerReset
  } elseif ($c -match "^[fF]$") {
   continue
  } elseif ($c -match "^[mMqQ]$") {
   return
  }
 }
}
# ==============================================================================
# Module 06: Main Entrypoint, WinPE Auto-Branch & Pre-SID STEP 1 -> STEP 2 UX
# ==============================================================================

function Invoke-PreSidWorkflow($sysInfo) {
 # UEFI check is scoped to Pre-SID workflow (Post-SID works on Legacy too)
 if (-not (Test-IsUefiBoot)) {
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Yellow
  Write-Host (U " [\uC548\uB0B4] \uD604\uC7AC PC\uB294 UEFI\uAC00 \uC544\uB2CC Legacy(MBR) \uBAA8\uB4DC\uB85C \uBD80\uD305\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
  Write-Host "==================================================================" -ForegroundColor Yellow
  Write-Host (U " - Legacy \uD658\uACBD\uC5D0\uC11C\uB294 USB \uC77C\uD68C\uC131 NVRAM \uBD80\uD305\uC744 \uC0AC\uC6A9\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
  Write-Host (U " - \uC81C\uC870\uC0AC \uBD80\uD2B8 \uBA54\uB274 \uB2E8\uCD95\uD0A4(Samsung: F12/F10, HP: F9, Dell: F12)\uB97C \uC0AC\uC6A9\uD558\uC138\uC694.") -ForegroundColor Yellow
  Write-Host (U " - (\uCC38\uACE0: \uC0AC\uD6C4 \uC791\uC5C5 [2] \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B\uC740 Legacy \uD658\uACBD\uC5D0\uC11C\uB3C4 \uC815\uC0C1 \uB3D9\uC791\uD569\uB2C8\uB2E4.)") -ForegroundColor Cyan
  while ($true) {
   Write-Host (U "`n[E] \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [Enter/M] \uBA54\uC778 \uBA54\uB274") -ForegroundColor Gray
   $lc = (Read-Host (U "\uC120\uD0DD")).Trim()
   if ($lc -match "^[eE]$") { Show-BootloaderManager $false }
   elseif ($lc -match "^[lL]$") { Show-DiskDebug }
   elseif ($lc -eq "" -or $lc -match "^[mMqQ]$") { return }
  }
 }

 # STEP 1 (Mandatory preceding check): Detect & remediate residual bootloaders
 while ($true) {
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host (U " [\uC0AC\uC804 \uC791\uC5C5 - STEP 1/2] C\uB4DC\uB77C\uC774\uBE0C \uC678 \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80 (\uD544\uC218 \uC120\uD589)") -ForegroundColor Cyan
  Write-Host ("   System : [" + $sysInfo.Vendor + "] (" + $sysInfo.ModelName + ")") -ForegroundColor DarkCyan
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host (U " (\uC678\uC7A5 USB \uBC0F WinPE/\uC124\uCE58 \uB9E4\uCCB4\uB294 \uC790\uB3D9 \uBCF4\uD638\uB418\uBA70 \uBCC0\uACBD \uB300\uC0C1\uC5D0\uC11C \uC81C\uC678\uB429\uB2C8\uB2E4.)") -ForegroundColor DarkGray

  $rep = Get-InternalBootloaderReport $false

  if ($rep.SplitBoot) {
   Write-Host ("`n * " + (U "\uBD80\uD305 \uAD6C\uC131 \uC0C1\uD0DC") + " : " + (U "[\uC704\uD5D8 - \uBD80\uD305 \uBD84\uB9AC\uB428!]") + " (OS: Disk " + $rep.BootDisk + " / EFI: Disk " + $rep.SysDisk + ")") -ForegroundColor Red
  } else {
   Write-Host ("`n * " + (U "\uBD80\uD305 \uAD6C\uC131 \uC0C1\uD0DC") + " : " + (U "[\uC815\uC0C1 - \uB2E8\uC77C OS/\uBD80\uD305 \uB514\uC2A4\uD06C]")) -ForegroundColor Green
  }

  foreach ($it in $rep.Items) {
   $stText = Format-BootloaderStateText $it
   $col = Get-BootloaderStateColor $it
   $partTag = if ($it.TargetPart -gt 0) { " | " + $it.BootType + " #" + $it.TargetPart } else { "" }
   Write-Host (" - Disk " + $it.DiskNumber + " : " + $it.Model + " [" + $it.SizeGB + " GB, " + $it.PartitionStyle + $partTag + "] -> " + $stText) -ForegroundColor $col
  }

  # Case A: Clean STEP 1 -> direct progression to STEP 2
  if (-not $rep.HasBlockingRisk) {
   Write-Host "`n==================================================================" -ForegroundColor Green
   Write-Host (U " [\uC815\uC0C1] C\uB4DC\uB77C\uC774\uBE0C \uC678 \uB0B4\uC7A5 \uB514\uC2A4\uD06C\uC5D0\uC11C \uCDA9\uB3CC \uC704\uD5D8 \uBD80\uD2B8\uB85C\uB354\uAC00 \uBC1C\uACAC\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.") -ForegroundColor Green
   Write-Host "==================================================================" -ForegroundColor Green
   Write-Host (U " [Enter \uB610\uB294 2] STEP 2\uB85C \uC9C4\uD589 (BIOS \uC810\uAC80 \uBC0F WinPE USB \uBD80\uD305) (\uAD8C\uC7A5)") -ForegroundColor Green
   Write-Host (U " [E] \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [R] \uB2E4\uC2DC \uC2A4\uCE94 | [M] \uBA54\uC778 \uBA54\uB274") -ForegroundColor Gray
   Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
   $s1Choice = (Read-Host (U "\uC120\uD0DD")).Trim()
   if ($s1Choice -eq "" -or $s1Choice -eq "2") {
    Invoke-PreSidUsbBootStep $sysInfo $false
    return
   } elseif ($s1Choice -match "^[eE]$") {
    Show-BootloaderManager $false
   } elseif ($s1Choice -match "^[lL]$") {
    Show-DiskDebug
   } elseif ($s1Choice -match "^[rR]$") {
    continue
   } elseif ($s1Choice -match "^[mMqQ]$") {
    return
   }
   continue
  }

  # Case B: Blocking risk detected -> enforce STEP 1 remediation or explicit IGNORE
  Write-Host "`n==================================================================" -ForegroundColor Red
  if ($rep.SplitBoot) {
   Write-Host (" [" + (U "\uC704\uD5D8") + "] Disk " + $rep.BootDisk + " / Disk " + $rep.SysDisk + " : " + (U "OS\uC640 \uC2E4\uC81C \uBD80\uD305 EFI\uAC00 \uBD84\uB9AC\uB418\uC5B4 \uC788\uC5B4 \uC790\uB3D9 \uC870\uCE58\uB97C \uCC28\uB2E8\uD569\uB2C8\uB2E4!")) -ForegroundColor Red
  } else {
   Write-Host (U " [\uACBD\uACE0] \uBCF4\uC870 \uB514\uC2A4\uD06C\uC5D0 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uAC00 \uBC1C\uACAC\uB418\uC5C8\uC2B5\uB2C8\uB2E4! (SID \uC791\uC5C5 \uD6C4 \uBD80\uD305 \uCDA9\uB3CC/\uC790\uB3D9 \uBCF5\uAD6C \uC9C4\uC785 \uC704\uD5D8)") -ForegroundColor Red
  }
  Write-Host (" " + (U "STEP 1\uC744 \uD574\uACB0\uD558\uAE30 \uC804\uC5D0\uB294 STEP 2(USB \uBD80\uD305)\uB85C \uBC14\uB85C \uC774\uB3D9\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.")) -ForegroundColor Yellow
  Write-Host "==================================================================" -ForegroundColor Red

  $canAutoFix = (-not $rep.SplitBoot) -and ($rep.ActionableConflictItems.Count -gt 0)
  if ($canAutoFix) {
   Write-Host (U " [Enter \uB610\uB294 A] \uC6D0\uC2A4\uD1B1 \uC870\uCE58 (\uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uBE44\uD65C\uC131\uD654 + \uD604\uC7AC SSD NVRAM \uB4F1\uB85D) (\uAD8C\uC7A5)") -ForegroundColor Green
  } else {
   Write-Host (" " + (U "\uC218\uB3D9 \uD655\uC778\uC774 \uD544\uC694\uD55C \uD56D\uBAA9\uC774 \uB0A8\uC544 \uC788\uC2B5\uB2C8\uB2E4 ([E] \uAD00\uB9AC \uB610\uB294 \uD655\uC778 \uD6C4 \uC9C4\uD589).")) -ForegroundColor Yellow
  }
  Write-Host (U " [E] \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354 \uAC1C\uBCC4 \uAD00\uB9AC | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [R] \uB2E4\uC2DC \uC2A4\uCE94") -ForegroundColor DarkCyan
  Write-Host (U " [I] \uC704\uD5D8\uC744 \uC774\uD574\uD558\uACE0 STEP 2\uB85C \uAC15\uC81C \uC9C4\uD589 (\uD655\uC778 \uBB38\uAD6C \uC785\uB825 \uD544\uC694)") -ForegroundColor Yellow
  Write-Host (U " [M] \uBA54\uC778 \uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uAE30") -ForegroundColor Gray
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

  $g0 = (Read-Host (U "\uC120\uD0DD")).Trim()
  if ($canAutoFix -and ($g0 -eq "" -or $g0 -match "^[aA]$")) {
   $changedCount = 0
   foreach ($ci in $rep.ActionableConflictItems) {
    $res = Invoke-BootloaderToggle $ci $true
    if ($res -eq "CHANGED") { $changedCount++ }
   }
   if ($changedCount -gt 0) {
    $regYn = (Read-Host (U "\uD604\uC7AC OS SSD(Disk $($rep.BootDisk))\uB97C UEFI NVRAM 1\uC21C\uC704\uB85C \uB4F1\uB85D(bcdboot)\uD560\uAE4C\uC694? (Y/N)")).Trim()
    if ($regYn -match "^[yY]$") {
     $bbRes = Invoke-NativeOem "bcdboot.exe" ('"' + $env:SystemRoot + '" /f UEFI')
     $bbRes.Lines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    }
    $recheck = Get-InternalBootloaderReport $false
    if (-not $recheck.HasBlockingRisk) {
     Write-Host (U "`n [\uC644\uB8CC] \uBAA8\uB4E0 \uCDA9\uB3CC \uC704\uD5D8 \uBD80\uD2B8\uB85C\uB354\uAC00 \uC815\uB9AC\uB418\uC5C8\uC2B5\uB2C8\uB2E4! \uC774\uC81C STEP 2\uB85C \uC9C4\uD589\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Green
     Read-Host (U "\uACC4\uC18D\uD558\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
    }
   } else {
    Write-Host (U "`n [\uC548\uB0B4] \uBCC0\uACBD\uB41C \uD56D\uBAA9\uC774 \uC5C6\uC5B4 bcdboot \uB4F1\uB85D\uC744 \uAC74\uB108\uB701\uB2C8\uB2E4.") -ForegroundColor Gray
    Read-Host (U "\uACC4\uC18D\uD558\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
   }
  } elseif ($g0 -match "^[eE]$") {
   Show-BootloaderManager $false
  } elseif ($g0 -match "^[lL]$") {
   Show-DiskDebug
  } elseif ($g0 -match "^[rR]$") {
   continue
  } elseif ($g0 -match "^[iI]$") {
   Write-Host (U "`n [\uC704\uD5D8 \uD655\uC778] \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uB97C \uC815\uB9AC\uD558\uC9C0 \uC54A\uACE0 USB \uBD80\uD305\uC744 \uC9C4\uD589\uD558\uBA74 SID \uBCC0\uACBD \uD6C4 \uBD80\uD305 \uCDA9\uB3CC\uC774 \uBC1C\uC0DD\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
   $confirm = (Read-Host (U "\uC704\uD5D8\uC744 \uC774\uD574\uD558\uACE0 \uAC15\uC81C \uC9C4\uD589\uD558\uB824\uBA74 \uC601\uBB38\uC73C\uB85C IGNORE \uB97C \uC785\uB825\uD558\uC138\uC694 (\uCDE8\uC18C: Enter)")).Trim()
   if ($confirm -ieq "IGNORE") {
    Invoke-PreSidUsbBootStep $sysInfo $true
    return
   } else {
    Write-Host (U " \uAC15\uC81C \uC9C4\uD589\uC774 \uCDE8\uC18C\uB418\uC5C8\uC2B5\uB2C8\uB2E4. STEP 1\uC744 \uBA3C\uC800 \uD574\uACB0\uD558\uB294 \uAC83\uC744 \uAD8C\uC7A5\uD569\uB2C8\uB2E4.") -ForegroundColor Gray
    Read-Host (U "\uACC4\uC18D\uD558\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
   }
  } elseif ($g0 -match "^[mMqQ]$") {
   return
  }
 }
}

function Start-ToolMain {
 Clear-Host

 # WinPE (X:) Emergency Mode Auto-Detection
 if ($env:SystemDrive -eq "X:") {
  Write-Host "==================================================================" -ForegroundColor Yellow
  Write-Host (U " [WinPE \uBE44\uC0C1 \uBAA8\uB4DC] \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354(EFI/MBR) \uC810\uAC80 \uBC0F \uBCF5\uAD6C") -ForegroundColor Yellow
  Write-Host "==================================================================" -ForegroundColor Yellow
  Show-BootloaderManager $true
  exit 0
 }

 # Normal Windows Main Menu
 $sysInfo = Get-SystemInfo
 while ($true) {
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host (" " + (U "[SID \uBCC0\uACBD \uBCF4\uC870 \uD234] \uC2DC\uC2A4\uD15C :") + " [" + $sysInfo.Vendor + "] (" + $sysInfo.ModelName + ")") -ForegroundColor Cyan
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host ""
  Write-Host (U "  [1] SID \uBCC0\uACBD \uC0AC\uC804 \uC791\uC5C5   (\uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uD0D0\uC9C0/\uC81C\uAC70 -> USB \uBD80\uD305)") -ForegroundColor Green
  Write-Host (U "  [2] SID \uBCC0\uACBD \uC0AC\uD6C4 \uC791\uC5C5   (\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B)") -ForegroundColor Cyan
  Write-Host (U "  [Q] \uC885\uB8CC") -ForegroundColor Gray
  Write-Host ""
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
  $mainChoice = (Read-Host (U "\uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694")).Trim()

  if ($mainChoice -eq "1") {
   Invoke-PreSidWorkflow $sysInfo
  } elseif ($mainChoice -eq "2") {
   Invoke-PostSidWorkflow $sysInfo
  } elseif ($mainChoice -match "^[qQ]$") {
   Write-Host (U " \uC885\uB8CC\uD569\uB2C8\uB2E4.") -ForegroundColor Gray
   exit 0
  } else {
   Write-Host (U " [\uC798\uBABB\uB41C \uC785\uB825\uC785\uB2C8\uB2E4. 1, 2 \uB610\uB294 Q\uB97C \uC785\uB825\uD558\uC138\uC694.]") -ForegroundColor Yellow
   Start-Sleep -Milliseconds 900
  }
 }
}

if (-not $env:SID_TOOL_TEST_MODE) {
 Start-ToolMain
}
