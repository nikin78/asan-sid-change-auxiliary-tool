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
# USB Boot Helper + Multi-Disk EFI Conflict Guard (100% Pure ASCII)
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
function U([string]$str) { return [System.Text.RegularExpressions.Regex]::Unescape($str) }

$ErrorActionPreference = "Continue"
$gptEfiGuid = "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
$gptRecoveryGuid = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
$gptMsrGuid = "{e3c9e316-0b5c-4db8-817d-f92df00215ae}"
$mbrEfiFatTypes = @(11, 12, 14, 239)

function Show-BcdDebug([array]$rawLines) {
 Write-Host "`n==================== [bcdedit /enum firmware] ====================" -ForegroundColor DarkCyan
 if ($rawLines -and $rawLines.Count -gt 0) {
  $rawLines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
 } else {
  Write-Host "(No output from bcdedit /enum firmware)" -ForegroundColor DarkGray
 }
 Write-Host "==================================================================" -ForegroundColor DarkCyan
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}

function Show-DiskDebug {
 Write-Host "`n==================== [Get-Disk / Get-Partition] ================" -ForegroundColor DarkCyan
 Get-Disk | Format-Table Number, FriendlyName, BusType, OperationalStatus, IsBoot, IsSystem, IsRemovable, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
 Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, GptType, MbrType, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
 Write-Host "==================================================================" -ForegroundColor DarkCyan
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}

# Helper: Mount ESP temporarily via diskpart, run scriptblock, then restore letter state
function Invoke-WithEspMount([int]$diskNum, [int]$partNum, [string]$existingLetter, [scriptblock]$action) {
 $workDrv = ""
 $tempMounted = $false
 if ($existingLetter -and (Test-Path "$($existingLetter):\")) {
  $workDrv = $existingLetter
 } else {
  $candidates = @("Z","W","V","U","T","S","R","Q","P","O","N","M")
  foreach ($l in $candidates) {
   if (-not (Test-Path "$($l):\")) {
    $dpScript = "select disk $diskNum`r`nselect part $partNum`r`nassign letter=$l`r`n"
    $dpScript | diskpart | Out-Null
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
   $dpClean = "select disk $diskNum`r`nselect part $partNum`r`nremove letter=$workDrv`r`n"
   $dpClean | diskpart | Out-Null
   if (Test-Path "$($workDrv):\") { mountvol "$($workDrv):" /d 2>$null | Out-Null }
  }
 }
 return $res
}

# Helper: Scan all internal online disks for EFI conflicts
function Get-InternalEfiReport([array]$internalDisks, [bool]$isWinPE) {
 $bootDisk = $null
 $sysDisk = $null
 $protected = @()
 if (-not $isWinPE) {
  $allParts = @(Get-Partition -ErrorAction SilentlyContinue)
  foreach ($p in $allParts) {
   if ($p.IsBoot) { $bootDisk = $p.DiskNumber; if ($protected -notcontains $p.DiskNumber) { $protected += $p.DiskNumber } }
   if ($p.IsSystem) { $sysDisk = $p.DiskNumber; if ($protected -notcontains $p.DiskNumber) { $protected += $p.DiskNumber } }
  }
 }
 $splitBoot = (-not $isWinPE -and $null -ne $bootDisk -and $null -ne $sysDisk -and $bootDisk -ne $sysDisk)
 $items = @()

 foreach ($d in $internalDisks) {
  $parts = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)
  $espPart = $parts | Where-Object { $_.GptType -eq $gptEfiGuid } | Select-Object -First 1
  $isProt = ($protected -contains $d.Number)
  $efiState = "NO_ESP"
  $espNum = 0
  $espLtr = ""

  if ($espPart) {
   $espNum = $espPart.PartitionNumber
   if ($espPart.DriveLetter) { $espLtr = [string]$espPart.DriveLetter }
   if ($isProt) {
    $efiState = "PROTECTED"
   } else {
    $efiState = Invoke-WithEspMount $d.Number $espNum $espLtr {
     param($drv)
     if (Test-Path "$($drv):\Windows\System32\ntoskrnl.exe") { return "OS_BLOCKED" }
     $hasEfi = Test-Path "$($drv):\EFI"
     $hasOld = Test-Path "$($drv):\EFI_OLD"
     if ($hasEfi -and $hasOld) { return "BOTH" }
     elseif ($hasEfi) { return "ACTIVE" }
     elseif ($hasOld) { return "DISABLED" }
     else { return "EMPTY" }
    }
   }
  } elseif ($isProt) {
   $efiState = "PROTECTED_OS"
  }

  $items += [PSCustomObject]@{
   DiskNumber = $d.Number
   Model = $d.FriendlyName
   SizeGB = [math]::Round($d.Size / 1GB, 1)
   IsProtected = $isProt
   EspPart = $espNum
   EspLetter = $espLtr
   EfiState = $efiState
  }
 }

 return [PSCustomObject]@{
  BootDisk = $bootDisk
  SysDisk = $sysDisk
  SplitBoot = $splitBoot
  Items = $items
  ConflictItems = @($items | Where-Object { $_.EfiState -eq "ACTIVE" -or $_.EfiState -eq "BOTH" })
 }
}

# Helper: Toggle EFI <-> EFI_OLD on a specific disk
function Invoke-EspToggle($item, [bool]$disableOnly) {
 if ($item.IsProtected) {
  Write-Host (U " [\uCC28\uB2E8] Disk $($item.DiskNumber) (\uD604\uC7AC OS/\uBD80\uD305 \uB514\uC2A4\uD06C)\uB294 \uBCF4\uD638\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
  return $false
 }
 if ($item.EspPart -le 0) {
  Write-Host (U " [\uC548\uB0B4] Disk $($item.DiskNumber)\uC5D0 GPT EFI \uD30C\uD2F0\uC158\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
  return $false
 }

 return (Invoke-WithEspMount $item.DiskNumber $item.EspPart $item.EspLetter {
  param($drv)
  if (Test-Path "$($drv):\Windows\System32\ntoskrnl.exe") {
   Write-Host (U " [\uCC28\uB2E8] OS \uD30C\uD2F0\uC158\uC774 \uAC10\uC9C0\uB418\uC5B4 \uC911\uB2E8\uD569\uB2C8\uB2E4.") -ForegroundColor Red
   return $false
  }
  $hasEfi = Test-Path "$($drv):\EFI"
  $hasOld = Test-Path "$($drv):\EFI_OLD"
  if ($hasEfi -and $hasOld) {
   Write-Host (U " [\uC911\uB2E8] Disk $($item.DiskNumber) ESP\uC5D0 EFI\uC640 EFI_OLD\uAC00 \uACF5\uC874\uD569\uB2C8\uB2E4. \uC218\uB3D9 \uD655\uC778 \uD544\uC694.") -ForegroundColor Yellow
   return $false
  }
  Write-Host "`n--- Disk $($item.DiskNumber) ($($item.Model)) | ESP #$($item.EspPart) ($($drv):) ---" -ForegroundColor Cyan
  Get-ChildItem -Path "$($drv):\" -Force -ErrorAction SilentlyContinue | Format-Table Mode, LastWriteTime, Name -AutoSize | Out-String | Write-Host -ForegroundColor Gray

  if ($hasEfi) {
   $yn = Read-Host (U "Disk $($item.DiskNumber)\uC758 [EFI]\uB97C [EFI_OLD]\uB85C \uBE44\uD65C\uC131\uD654\uD560\uAE4C\uC694? (Y/N)")
   if ($yn -match "^[yY]$") {
    try {
     Rename-Item -Path "$($drv):\EFI" -NewName "EFI_OLD" -ErrorAction Stop
     Write-Host (U " [\uC131\uACF5] Disk $($item.DiskNumber) EFI -> EFI_OLD \uBE44\uD65C\uC131\uD654 \uC644\uB8CC!") -ForegroundColor Green
     return $true
    } catch {
     Write-Host (U " [\uC2E4\uD328] \uC774\uB984 \uBCC0\uACBD \uC2E4\uD328: $($_.Exception.Message)") -ForegroundColor Red
     return $false
    }
   } else {
    Write-Host (U " \uC791\uC5C5\uC744 \uCDE8\uC18C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Gray
    return $false
   }
  } elseif ($hasOld -and -not $disableOnly) {
   $yn = Read-Host (U "Disk $($item.DiskNumber)\uC758 [EFI_OLD]\uB97C [EFI]\uB85C \uBCF5\uAD6C\uD560\uAE4C\uC694? (Y/N)")
   if ($yn -match "^[yY]$") {
    try {
     Rename-Item -Path "$($drv):\EFI_OLD" -NewName "EFI" -ErrorAction Stop
     Write-Host (U " [\uC131\uACF5] Disk $($item.DiskNumber) EFI_OLD -> EFI \uBCF5\uAD6C \uC644\uB8CC!") -ForegroundColor Green
     return $true
    } catch {
     Write-Host (U " [\uC2E4\uD328] \uBCF5\uAD6C \uC2E4\uD328: $($_.Exception.Message)") -ForegroundColor Red
     return $false
    }
   }
  }
  return $false
 })
}

# Interactive EFI Manager (used in WinPE emergency mode or [E] menu)
function Show-EfiManager([array]$internalDisks, [bool]$isWinPE) {
 while ($true) {
  $rep = Get-InternalEfiReport $internalDisks $isWinPE
  Write-Host (U "`n==================== [EFI \uB514\uC2A4\uD06C \uAD00\uB9AC] ====================") -ForegroundColor Cyan
  foreach ($it in $rep.Items) {
   $stText = switch ($it.EfiState) {
    "PROTECTED"    { U "[\uBCF4\uD638\uB428: \uD604\uC7AC OS/\uBD80\uD305 EFI]" }
    "PROTECTED_OS" { U "[\uBCF4\uD638\uB428: \uD604\uC7AC OS \uB514\uC2A4\uD06C]" }
    "ACTIVE"       { U "[\uCDA9\uB3CC \uC704\uD5D8: \uD65C\uC131 EFI \uBC1C\uACAC!]" }
    "BOTH"         { U "[\uC8FC\uC758: EFI + EFI_OLD \uACF5\uC874]" }
    "DISABLED"     { U "[\uC870\uCE58\uB428: \uBE44\uD65C\uC131(EFI_OLD)]" }
    "EMPTY"        { U "[\uC548\uC804: \uBE48 ESP]" }
    "NO_ESP"       { U "[\uC548\uC804: ESP \uC5C6\uC74C]" }
    default        { "[$($it.EfiState)]" }
   }
   $col = if ($it.EfiState -eq "ACTIVE" -or $it.EfiState -eq "BOTH") { "Red" } elseif ($it.IsProtected) { "Green" } else { "Gray" }
   Write-Host " - Disk $($it.DiskNumber) : $($it.Model) [$($it.SizeGB) GB] -> $stText" -ForegroundColor $col
  }
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
  Write-Host (U " [\uB514\uC2A4\uD06C \uBC88\uD638] EFI <-> EFI_OLD \uBE44\uD65C\uC131\uD654/\uBCF5\uAD6C | [Q/Enter] \uB3CC\uC544\uAC00\uAE30") -ForegroundColor White
  $c = Read-Host (U "\uC120\uD0DD")
  if ($c -match "^\d+$") {
   $target = $rep.Items | Where-Object { $_.DiskNumber -eq [int]$c } | Select-Object -First 1
   if ($target) { Invoke-EspToggle $target $false | Out-Null }
  } else {
   break
  }
 }
}

Clear-Host

# ==============================================================================
# WinPE (X:) Emergency Mode Auto-Detection
# ==============================================================================
if ($env:SystemDrive -eq "X:") {
 Write-Host "==================================================================" -ForegroundColor Yellow
 Write-Host (U " [WinPE \uBE44\uC0C1 \uBAA8\uB4DC] \uB0B4\uC7A5 \uB514\uC2A4\uD06C EFI \uCDA9\uB3CC \uC810\uAC80 \uBC0F \uBE44\uD65C\uC131\uD654") -ForegroundColor Yellow
 Write-Host "==================================================================" -ForegroundColor Yellow
 $peInternal = @(Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' -and $_.BusType -ne 'USB' -and -not $_.IsRemovable })
 Show-EfiManager $peInternal $true
 exit 0
}

# 0. Identify PC Vendor (Samsung / HP / Dell / Standard)
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

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host (U " [USB \uBD80\uD305 \uB3C4\uC6B0\uBBF8] \uC2DC\uC2A4\uD15C : [$vendor] ($modelName)") -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Check UEFI vs Legacy BIOS Mode
$bcdBoot = bcdedit /enum "{current}" 2>&1
$isUefi = ($bcdBoot | Select-String -Pattern "winload\.efi" -Quiet)
if (-not $isUefi) {
 Write-Host (U "`n[\uC624\uB958] \uD604\uC7AC PC\uB294 UEFI\uAC00 \uC544\uB2CC Legacy(MBR) \uBAA8\uB4DC\uB85C \uBD80\uD305\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
 Write-Host (U "Legacy \uD658\uACBD\uC5D0\uC11C\uB294 \uC81C\uC870\uC0AC \uBD80\uD2B8 \uBA54\uB274 \uB2E8\uCD95\uD0A4(Samsung: F12/F10, HP: F9, Dell: F12)\uB97C \uC0AC\uC6A9\uD558\uC138\uC694.") -ForegroundColor Yellow
 pause
 exit 1
}

# 2. Pre-parse bcdedit /enum firmware safely
$bcdOutput = @(bcdedit /enum firmware 2>&1)
$entries = @()
$currentEntry = $null

foreach ($line in $bcdOutput) {
 $sLine = [string]$line
 if ($sLine -match "^-{5,}") {
  if ($currentEntry -and $currentEntry.Identifier) { $entries += $currentEntry }
  $currentEntry = @{ Identifier = ""; Description = ""; Path = ""; Device = "" }
 }
 elseif ($currentEntry) {
  if ($sLine -match "^\S+\s+(\{[a-fA-F0-9-]+\})") { $currentEntry.Identifier = $matches[1] }
  elseif ($sLine -match "^(description|\uC124\uBA85)\s+(.+)$") { $currentEntry.Description = $matches[2].Trim() }
  elseif ($sLine -match "^(path|\uACBD\uB85C)\s+(.+)$") { $currentEntry.Path = $matches[2].Trim() }
  elseif ($sLine -match "^(device|\uC7A5\uCE58)\s+(.+)$") { $currentEntry.Device = $matches[2].Trim() }
 }
}
if ($currentEntry -and $currentEntry.Identifier) { $entries += $currentEntry }

# 3. Classify disks (USB vs Internal) & Check Secure Boot / Vendor WMI
$allDisks = @(Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' })
$usbDisks = @($allDisks | Where-Object {
 -not $_.IsBoot -and -not $_.IsSystem -and
 ($_.BusType -eq 'USB' -or $_.IsRemovable -or [string]$_.Path -match "USBSTOR|UASP")
})
$usbDiskNums = @($usbDisks | Select-Object -ExpandProperty Number)
$internalDisks = @($allDisks | Where-Object { $usbDiskNums -notcontains $_.Number })
$internalDiskNums = @($internalDisks | Select-Object -ExpandProperty Number)
$internalDriveLetters = @()
if ($internalDiskNums.Count -gt 0) {
 $internalDriveLetters = @(Get-Partition -DiskNumber $internalDiskNums -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | ForEach-Object { "partition=$($_.DriveLetter):" })
}

# Strict NVRAM USB check (excludes internal SSD brands like Samsung/Crucial/Micron)
$nvramHasStrictUsbEntry = @(
 $entries | Where-Object {
  $_.Identifier -ne "{fwbootmgr}" -and $_.Identifier -ne "{bootmgr}" -and
  ([string]$_.Description -notmatch "Windows Boot Manager|SATA|NVMe|Hard Drive \(SATA|Hard Drive \(NVMe|PXE|IPV4|IPV6|Network|CD/DVD") -and
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
   }
   elseif ($usbBootState -ne "Disabled" -and $activeVal -match "^(Enable|Enabled|Yes|On)$") {
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
}
elseif ($vendor -eq "Dell") {
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
   }
   elseif ($usbBootState -ne "Disabled" -and $val -match "Enable|On|All") {
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

$vendorBiosHint = switch ($vendor) {
 "HP"      { "HP BIOS (F10): Advanced -> Boot Options -> USB Storage Boot [Enable] / Fast Boot [Disable]" }
 "Dell"    { "Dell BIOS (F2): Boot/USB Config -> Enable USB Boot Support [On] / Fastboot [Thorough]" }
 "Samsung" { "Samsung BIOS (F2): Boot -> Fast BIOS Mode [Disabled] / Secure Boot Control [Disabled]" }
 default   { "BIOS Setup: USB Boot [Enabled] / Fast Boot [Disabled] / Secure Boot [Disabled]" }
}

# 3.5. Pre-Flight Multi-Disk EFI Conflict Scan
$efiReport = Get-InternalEfiReport $internalDisks $false

if ($secBoot) {
 Write-Host (U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uD65C\uC131\uD654\uB428 - ON (\uACBD\uACE0)]") -ForegroundColor Red
} else {
 Write-Host (U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uBE44\uD65C\uC131\uD654 - OFF (\uC815\uC0C1)]") -ForegroundColor Green
}

if ($usbBootState -eq "Disabled") {
 Write-Host (U " * BIOS USB Boot \uC635\uC158 : [\uBE44\uD65C\uC131\uD654 - OFF (\uACBD\uACE0)] ($usbBootDetail)") -ForegroundColor Red
} elseif ($usbBootState -eq "SuspectedDisabled") {
 Write-Host (U " * BIOS USB Boot \uC635\uC158 : [\uBE44\uD65C\uC131\uD654 \uC758\uC2EC - \uACBD\uACE0] ($usbBootDetail)") -ForegroundColor Red
} elseif ($usbBootState -eq "Enabled") {
 Write-Host (U " * BIOS USB Boot \uC635\uC158 : [\uD65C\uC131\uD654\uB428 - ON (\uC815\uC0C1)] ($usbBootDetail)") -ForegroundColor Green
} else {
 Write-Host (U " * BIOS USB Boot \uC635\uC158 : [\uD655\uC778 \uBD88\uAC00] ($usbBootDetail)") -ForegroundColor Yellow
}

if ($fastBootWarn) {
 Write-Host (U " * BIOS Fast Boot \uC635\uC158 : [\uD65C\uC131\uD654\uB428 - \uC8FC\uC758] ($fastBootDetail)") -ForegroundColor Yellow
}
Write-Host " * BIOS Hint          : $vendorBiosHint" -ForegroundColor DarkGray

if ($efiReport.SplitBoot) {
 Write-Host (U " * \uB0B4\uC7A5 \uB514\uC2A4\uD06C EFI \uCDA9\uB3CC : [\uC704\uD5D8 - \uBD80\uD305 \uBD84\uB9AC\uB428!] (OS: Disk $($efiReport.BootDisk) / EFI: Disk $($efiReport.SysDisk))") -ForegroundColor Red
} elseif ($efiReport.ConflictItems.Count -gt 0) {
 $cNums = ($efiReport.ConflictItems | ForEach-Object { "Disk $($_.DiskNumber)" }) -join ", "
 Write-Host (U " * \uB0B4\uC7A5 \uB514\uC2A4\uD06C EFI \uCDA9\uB3CC : [\uACBD\uACE0 - \uBCF4\uC870 \uB514\uC2A4\uD06C \uAD6C\uD615 EFI \uBC1C\uACAC!] ($cNums)") -ForegroundColor Red
} else {
 Write-Host (U " * \uB0B4\uC7A5 \uB514\uC2A4\uD06C EFI \uCDA9\uB3CC : [\uC815\uC0C1 - \uB2E8\uC77C EFI]") -ForegroundColor Green
}

# Gate 0: Multi-Disk EFI Conflict Remediation (Before rebooting to WinPE!)
if ($efiReport.SplitBoot -or $efiReport.ConflictItems.Count -gt 0) {
 while ($true) {
  Write-Host "`n==================================================================" -ForegroundColor Red
  if ($efiReport.SplitBoot) {
   Write-Host (U " [\uC704\uD5D8] OS(Disk $($efiReport.BootDisk))\uC640 \uC2E4\uC81C \uBD80\uD305 EFI(Disk $($efiReport.SysDisk))\uAC00 \uBD84\uB9AC\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4!") -ForegroundColor Red
  } else {
   Write-Host (U " [\uACBD\uACE0] \uBCF4\uC870 \uB514\uC2A4\uD06C\uC5D0 \uAD6C\uD615 EFI\uAC00 \uC0B4\uC544 \uC788\uC2B5\uB2C8\uB2E4! (SID \uC791\uC5C5 \uD6C4 \uBD80\uD305 \uCDA9\uB3CC \uC704\uD5D8)") -ForegroundColor Red
   foreach ($ci in $efiReport.ConflictItems) {
    Write-Host " - Disk $($ci.DiskNumber) : $($ci.Model) [$($ci.SizeGB) GB] (ESP #$($ci.EspPart))" -ForegroundColor Yellow
   }
  }
  Write-Host "==================================================================" -ForegroundColor Red
  if (-not $efiReport.SplitBoot -and $efiReport.ConflictItems.Count -gt 0) {
   Write-Host (U " [Enter \uB610\uB294 A] \uC6D0\uC2A4\uD1B1 \uC870\uCE58 (\uAD6C\uD615 EFI \uBE44\uD65C\uC131\uD654 + \uD604\uC7AC SSD NVRAM \uB4F1\uB85D) (\uAD8C\uC7A5)") -ForegroundColor Green
  }
  Write-Host (U " [I] \uBB34\uC2DC\uD558\uACE0 USB \uBD80\uD305 \uC9C4\uD589 | [Q] \uC885\uB8CC") -ForegroundColor Gray
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
  $g0 = Read-Host (U "\uC120\uD0DD")
  if ((-not $efiReport.SplitBoot) -and ($g0 -eq "" -or $g0 -match "^[aA]$")) {
   foreach ($ci in $efiReport.ConflictItems) { Invoke-EspToggle $ci $true | Out-Null }
   $regYn = Read-Host (U "\uD604\uC7AC OS SSD(Disk $($efiReport.BootDisk))\uB97C UEFI NVRAM 1\uC21C\uC704\uB85C \uB4F1\uB85D(bcdboot)\uD560\uAE4C\uC694? (Y/N)")
   if ($regYn -match "^[yY]$") {
    bcdboot "$env:SystemRoot" /f UEFI
   }
   $efiReport = Get-InternalEfiReport $internalDisks $false
   if ($efiReport.ConflictItems.Count -eq 0) { break }
  } elseif ($g0 -match "^[iI]$") {
   break
  } else {
   exit 0
  }
 }
}

# Gate 1: Secure Boot / Confirmed Disabled USB Boot
if ($secBoot -or ($usbBootState -eq "Disabled")) {
 while ($true) {
  Write-Host "`n==================================================================" -ForegroundColor Red
  Write-Host (U " [\uACBD\uACE0] BIOS \uBD80\uD305 \uCC28\uB2E8 \uC694\uC18C\uAC00 \uAC10\uC9C0\uB418\uC5C8\uC2B5\uB2C8\uB2E4!") -ForegroundColor Red
  if ($secBoot) {
   Write-Host (U " - Secure Boot\uAC00 \uCF1C\uC838 \uC788\uC5B4 WinPE \uBD80\uD305 \uB514\uC2A4\uD06C\uAC00 \uCC28\uB2E8\uB420 \uC218 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
  }
  if ($usbBootState -eq "Disabled") {
   Write-Host (U " - BIOS\uC5D0\uC11C USB \uBD80\uD305 \uC635\uC158\uC774 \uBE44\uD65C\uC131\uD654(Disabled)\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
  }
  Write-Host " - $vendorBiosHint" -ForegroundColor DarkGray
  Write-Host "==================================================================" -ForegroundColor Red
  Write-Host (U " [Enter \uB610\uB294 B] \uC989\uC2DC BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305 (\uAD8C\uC7A5)") -ForegroundColor Cyan
  Write-Host (U " [I] \uACBD\uACE0\uB97C \uBB34\uC2DC\uD558\uACE0 USB \uBD80\uD305 \uBAA9\uB85D \uAC80\uC0C9 \uACC4\uC18D \uC9C4\uD589") -ForegroundColor White
  Write-Host (U " [E] \uB0B4\uC7A5 \uB514\uC2A4\uD06C EFI \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8") -ForegroundColor DarkCyan
  Write-Host (U " [Q] \uCDE8\uC18C \uBC0F \uC885\uB8CC") -ForegroundColor Gray
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
  $gateChoice = Read-Host (U "\uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694 (Enter=BIOS \uC9C4\uC785)")
  if ($gateChoice -eq "" -or $gateChoice -match "^[bB]$") {
   shutdown /r /fw /f /t 0
   exit 0
  } elseif ($gateChoice -match "^[eE]$") {
   Show-EfiManager $internalDisks $false
  } elseif ($gateChoice -match "^[dD]$") {
   Show-BcdDebug $bcdOutput
  } elseif ($gateChoice -match "^[lL]$") {
   Show-DiskDebug
  } elseif ($gateChoice -match "^[iI]$") {
   break
  } else {
   exit 0
  }
 }
}

# 4. Check physical USB connection
if ($usbDisks.Count -eq 0) {
 Write-Host (U "`n[\uC624\uB958] \uD604\uC7AC \uBB3C\uB9AC\uC801\uC73C\uB85C \uC5F0\uACB0\uB41C \uC678\uC7A5 USB \uC800\uC7A5\uC7A5\uCE58\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
 Write-Host (U "(\uB0B4\uC7A5 SSD/HDD \uBC0F NVRAM \uACFC\uAC70 \uC720\uB839 \uAE30\uB85D\uC740 \uC790\uB3D9 \uC81C\uC678\uB429\uB2C8\uB2E4.)") -ForegroundColor Gray
 while ($true) {
  Write-Host (U "`n[B] BIOS \uC124\uC815 | [E] \uB0B4\uC7A5 EFI \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [Enter/Q] \uC885\uB8CC") -ForegroundColor DarkGray
  $noUsbChoice = Read-Host (U "\uC120\uD0DD")
  if ($noUsbChoice -match "^[bB]$") { shutdown /r /fw /f /t 0; exit 0 }
  elseif ($noUsbChoice -match "^[eE]$") { Show-EfiManager $internalDisks $false }
  elseif ($noUsbChoice -match "^[dD]$") { Show-BcdDebug $bcdOutput }
  elseif ($noUsbChoice -match "^[lL]$") { Show-DiskDebug }
  else { exit 1 }
 }
}

# 5. Inspect physical USB partitions
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

Write-Host (U "`n[1] \uD604\uC7AC \uC5F0\uACB0\uB41C \uBB3C\uB9AC USB \uB514\uC2A4\uD06C \uBAA9\uB85D:") -ForegroundColor Cyan
foreach ($u in $physicalUsbList) {
 $efiTag = if ($u.IsEfiReady) { U "UEFI \uBD80\uD305 \uAC00\uB2A5" } else { U "EFI \uD30C\uD2F0\uC158 \uBBF8\uD655\uC778" }
 Write-Host " - Disk $($u.DiskNumber) : $($u.Model) [$($u.SizeGB)] | $($u.Partitions) -> ($efiTag)" -ForegroundColor White
}

# 6. Cross-verify NVRAM entries
$internalPattern = if ($internalDriveLetters.Count -gt 0) { ($internalDriveLetters | ForEach-Object { [regex]::Escape($_) }) -join "|" } else { "^$" }

$candidateEntries = @($entries | Where-Object {
 $_.Identifier -ne "{fwbootmgr}" -and
 $_.Identifier -ne "{bootmgr}" -and
 ([string]$_.Description -notmatch "Windows Boot Manager|PXE|IPV4|IPV6|Network|Hard Drive \(SATA|Hard Drive \(NVMe|CD/DVD|Onboard NIC|HTTP") -and
 ([string]$_.Device -notmatch $internalPattern)
})

$matchedEntries = @()
$seenIds = @{}

function Add-MatchedEntry($entryObj, [string]$tierTag, [bool]$isExact) {
 if ($entryObj -and $entryObj.Identifier -and -not $seenIds.ContainsKey($entryObj.Identifier)) {
  $seenIds[$entryObj.Identifier] = $true
  $script:matchedEntries += [PSCustomObject]@{
   Identifier = $entryObj.Identifier
   Description = $entryObj.Description
   Device = $entryObj.Device
   Path = $entryObj.Path
   MatchTag = $tierTag
   IsExact = $isExact
  }
 }
}

if ($usbDrivePatterns.Count -gt 0) {
 $drvRegex = ($usbDrivePatterns | Select-Object -Unique) -join "|"
 foreach ($c in $candidateEntries) {
  if ([string]$c.Device -match $drvRegex) {
   Add-MatchedEntry $c (U "\uC815\uD655 \uC77C\uCE58 - \uB4DC\uB77C\uC774\uBE0C") $true
  }
 }
}

if ($usbStrictModelPatterns.Count -gt 0) {
 $modelRegex = ($usbStrictModelPatterns | Select-Object -Unique) -join "|"
 foreach ($c in $candidateEntries) {
  if ([string]$c.Description -match $modelRegex) {
   Add-MatchedEntry $c (U "\uC815\uD655 \uC77C\uCE58 - \uBAA8\uB378\uBA85") $true
  }
 }
}

if ($matchedEntries.Count -eq 0 -and $usbPartPatterns.Count -gt 0) {
 $partRegex = ($usbPartPatterns | Select-Object -Unique) -join "|"
 foreach ($c in $candidateEntries) {
  if ([string]$c.Description -match $partRegex -and [string]$c.Description -match "UEFI|USB|Partition") {
   Add-MatchedEntry $c (U "\uD30C\uD2F0\uC158 \uC77C\uCE58") $true
  }
 }
}

if ($matchedEntries.Count -eq 0 -and $anyEfiReadyUsb) {
 $genericUsbRegex = "USB Hard Drive|USB Flash|USB Device|Removable Device|External|Mass Storage|\bUSB\b"
 foreach ($c in $candidateEntries) {
  if ([string]$c.Description -match $genericUsbRegex) {
   Add-MatchedEntry $c (U "\uBC94\uC6A9 UEFI USB \uD56D\uBAA9") $false
  }
 }
}

# 7. Gate 2
if ($matchedEntries.Count -eq 0) {
 $isLikelyHotPlug = ($usbBootState -eq "Enabled" -and -not $fastBootWarn)
 while ($true) {
  Write-Host "`n==================================================================" -ForegroundColor Yellow
  if ($isLikelyHotPlug) {
   Write-Host (U " [\uC548\uB0B4] \uBB3C\uB9AC USB\uB294 \uC778\uC2DD\uB418\uC5C8\uC73C\uB098 \uD604\uC7AC NVRAM \uBAA9\uB85D\uC5D0 \uB4F1\uB85D\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.") -ForegroundColor Yellow
   Write-Host (U " - BIOS USB Boot\uAC00 \uCF1C\uC838 \uC788\uC73C\uBBC0\uB85C Windows \uBD80\uD305 \uD6C4 USB\uB97C \uC5F0\uACB0(Hot-Plug)\uD55C \uC0C1\uD0DC\uC77C \uAC00\uB2A5\uC131\uC774 \uB192\uC2B5\uB2C8\uB2E4.") -ForegroundColor Cyan
   Write-Host "" -ForegroundColor Yellow
   Write-Host (U " [Enter \uB610\uB294 O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305 (\uAD8C\uC7A5)") -ForegroundColor Green
   Write-Host (U " [B] BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Cyan
  } else {
   Write-Host (U " [\uACBD\uACE0] \uBB3C\uB9AC\uC801 USB\uB294 \uC778\uC2DD\uB418\uC5C8\uC73C\uB098 BIOS(NVRAM) \uBD80\uD305 \uBAA9\uB85D\uC5D0 \uC5C6\uC2B5\uB2C8\uB2E4!") -ForegroundColor Red
   Write-Host " - $vendorBiosHint" -ForegroundColor Yellow
   Write-Host "" -ForegroundColor Yellow
   Write-Host (U " [Enter \uB610\uB294 B] \uC989\uC2DC BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305 (\uAD8C\uC7A5 - Fast Boot / USB Boot \uD655\uC778)") -ForegroundColor Cyan
   Write-Host (U " [O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305") -ForegroundColor Green
  }
  Write-Host (U " [E] \uB0B4\uC7A5 EFI \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8 | [Q] \uC885\uB8CC") -ForegroundColor Gray
  Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

  $defaultHint = if ($isLikelyHotPlug) { U "Enter=\uC7A5\uCE58 \uC0AC\uC6A9 \uBA54\uB274" } else { U "Enter=BIOS \uC9C4\uC785" }
  $fbChoice = Read-Host (U "\uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694 ($defaultHint)")

  if ($fbChoice -match "^[eE]$") { Show-EfiManager $internalDisks $false; continue }
  elseif ($fbChoice -match "^[dD]$") { Show-BcdDebug $bcdOutput; continue }
  elseif ($fbChoice -match "^[lL]$") { Show-DiskDebug; continue }
  elseif ($fbChoice -eq "") {
   if ($isLikelyHotPlug) { shutdown /r /o /f /t 0 } else { shutdown /r /fw /f /t 0 }
   exit 0
  } elseif ($fbChoice -match "^[oO]$") { shutdown /r /o /f /t 0; exit 0 }
  elseif ($fbChoice -match "^[bB]$") { shutdown /r /fw /f /t 0; exit 0 }
  else { exit 0 }
 }
}

# 8. Present verified USB targets for user confirmation
$selectedTarget = $null
while ($true) {
 Write-Host "`n==================================================================" -ForegroundColor Cyan
 Write-Host (U "[2] \uBD80\uD305 \uAC00\uB2A5\uD55C UEFI USB \uD56D\uBAA9\uC774 \uD655\uC778\uB418\uC5C8\uC2B5\uB2C8\uB2E4:") -ForegroundColor Green
 for ($i = 0; $i -lt $matchedEntries.Count; $i++) {
  $devInfo = if ($matchedEntries[$i].Device) { $matchedEntries[$i].Device } else { "UEFI NVRAM" }
  $tagColor = if ($matchedEntries[$i].IsExact) { "Green" } else { "Yellow" }
  Write-Host " [$($i+1)] [$($matchedEntries[$i].MatchTag)] $($matchedEntries[$i].Description)" -ForegroundColor $tagColor
  Write-Host " -> Device: $devInfo | GUID: $($matchedEntries[$i].Identifier)" -ForegroundColor DarkGray
 }

 Write-Host "`n------------------------------------------------------------------" -ForegroundColor DarkGray
 if ($matchedEntries.Count -eq 1) {
  Write-Host (U " [Enter \uB610\uB294 1] \uC704 [1]\uBC88 USB \uB514\uC2A4\uD06C\uAC00 \uB9DE\uC73C\uBA74 \uC989\uC2DC \uC7AC\uBD80\uD305") -ForegroundColor Green
 } else {
  Write-Host (U " [1~$($matchedEntries.Count)] \uBD80\uD305\uD560 USB \uBC88\uD638 \uC785\uB825 \uD6C4 \uC989\uC2DC \uC7AC\uBD80\uD305") -ForegroundColor Green
 }
 Write-Host (U " [O] Windows \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uBA54\uB274\uB85C \uC7AC\uBD80\uD305")
 Write-Host (U " [B] BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815\uC73C\uB85C \uC7AC\uBD80\uD305")
 Write-Host (U " [E] \uB0B4\uC7A5 EFI \uAD00\uB9AC | [D] NVRAM \uC6D0\uBCF8 | [L] \uB514\uC2A4\uD06C \uC9C4\uB2E8") -ForegroundColor DarkCyan
 Write-Host (U " [Q] \uCDE8\uC18C \uBC0F \uC885\uB8CC")
 Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray

 $choice = Read-Host (U "\uC2E4\uD589\uD560 \uC791\uC5C5\uC744 \uC120\uD0DD\uD558\uC138\uC694")

 if ($choice -match "^[eE]$") { Show-EfiManager $internalDisks $false; continue }
 elseif ($choice -match "^[dD]$") { Show-BcdDebug $bcdOutput; continue }
 elseif ($choice -match "^[lL]$") { Show-DiskDebug; continue }
 elseif ($choice -eq "" -and $matchedEntries.Count -eq 1) { $selectedTarget = $matchedEntries[0]; break }
 elseif ($choice -match "^\d+$" -and [int]$choice -ge 1 -and [int]$choice -le $matchedEntries.Count) { $selectedTarget = $matchedEntries[[int]$choice - 1]; break }
 elseif ($choice -match "^[oO]$") { shutdown /r /o /f /t 0; exit 0 }
 elseif ($choice -match "^[bB]$") { shutdown /r /fw /f /t 0; exit 0 }
 else { exit 0 }
}

# 9. Set 1-time bootsequence and reboot
$bcdSetResult = bcdedit /set "{fwbootmgr}" bootsequence "$($selectedTarget.Identifier)" 2>&1
if ($LASTEXITCODE -eq 0) {
 Write-Host (U "`n-> [$($selectedTarget.Description)] \uBD80\uD305 \uC21C\uC11C \uC9C0\uC815 \uC644\uB8CC! \uC989\uC2DC \uC7AC\uBD80\uD305\uD569\uB2C8\uB2E4...") -ForegroundColor Cyan
 shutdown /r /f /t 0
} else {
 Write-Host (U "`n[\uC624\uB958] NVRAM \uBD80\uD305 \uC21C\uC11C \uBCC0\uACBD \uC2E4\uD328!") -ForegroundColor Red
 Write-Host (U "\uC0C1\uC138 \uCD9C\uB825: $bcdSetResult") -ForegroundColor Yellow
 Write-Host (U "Windows \uC7A5\uCE58 \uC0AC\uC6A9 \uD654\uBA74\uC73C\uB85C \uC774\uB3D9\uD558\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694.") -ForegroundColor Cyan
 Read-Host | Out-Null
 shutdown /r /o /f /t 0
}
