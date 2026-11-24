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
