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
 if ($rawVendor -match "Samsung|\bSEC\b") { $vendor = "Samsung" }
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
   $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup"
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
