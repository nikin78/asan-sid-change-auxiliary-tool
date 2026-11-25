# ==============================================================================
# Module 03: System Vendor Identification, Multi-Signal BIOS Cross-Verification
#            & Contextual Pre-SID Action Guidance Engine
# ==============================================================================

function Get-SystemInfo {
 $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
 $bb = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
 $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
 $csMan = [string]$cs.Manufacturer
 $bbMan = [string]$bb.Manufacturer
 $biosMan = [string]$bios.Manufacturer
 $rawVendor = "$csMan $bbMan $biosMan".Trim()
 $modelName = if ($cs.Model -and $cs.Model -notmatch "System Product Name|To be filled|Default string") {
  $cs.Model.Trim()
 } elseif ($bb.Product -and $bb.Product -notmatch "Default string|To be filled") {
  $bb.Product.Trim()
 } else {
  "Desktop PC"
 }

 # Identify OEM vendor with priority on ComputerSystem -> BaseBoard -> BIOS (word boundaries prevent false hits)
 $vendor = "Standard"
 foreach ($src in @($csMan, $bbMan, $biosMan)) {
  if (-not $src) { continue }
  if ($src -match "Samsung|\bSEC\b") { $vendor = "Samsung"; break }
  if ($src -match "\bHP\b|Hewlett-Packard|HP Inc") { $vendor = "HP"; break }
  if ($src -match "\bDell\b") { $vendor = "Dell"; break }
 }

 $hintVendor = $vendor
 if ($vendor -eq "Standard") {
  if ($rawVendor -match "\bLenovo\b") { $hintVendor = "Lenovo" }
  elseif ($rawVendor -match "\bLG\b|LG Electronics") { $hintVendor = "LG" }
  elseif ($rawVendor -match "ASUS|ASUSTeK") { $hintVendor = "ASUS" }
  elseif ($rawVendor -match "ASRock") { $hintVendor = "ASRock" }
  elseif ($rawVendor -match "Gigabyte") { $hintVendor = "Gigabyte" }
  elseif ($rawVendor -match "Micro-Star|\bMSI\b") { $hintVendor = "MSI" }
 }

 $vendorBiosHint = switch ($hintVendor) {
  "HP"       { "HP BIOS (F10 / Boot Menu F9): Advanced -> Boot Options -> USB Storage Boot [Enable] / Fast Boot [Disable]" }
  "Dell"     { "Dell BIOS (F2 / Boot Menu F12): Boot/USB Config -> Enable USB Boot Support [On] / Fastboot [Thorough]" }
  "Samsung"  { "Samsung BIOS (F2 / Boot Menu F10,F12): Boot -> Fast BIOS Mode [Disabled] / Secure Boot Control [Disabled]" }
  "Lenovo"   { "Lenovo BIOS (F1 / Boot Menu F12): Startup -> USB Boot [Enabled] / Security -> Secure Boot [Disabled]" }
  "LG"       { "LG BIOS (F2 / Boot Menu F10): Boot -> Fast Boot [Disabled] / Security -> Secure Boot [Disabled]" }
  "ASUS"     { "ASUS BIOS (Del,F2 / Boot Menu F8): Boot -> Fast Boot [Disabled] / Secure Boot -> Other OS" }
  "ASRock"   { "ASRock BIOS (Del,F2 / Boot Menu F11): Boot -> Fast Boot [Disabled] / Security -> Secure Boot [Disabled]" }
  "Gigabyte" { "Gigabyte BIOS (Del / Boot Menu F12): Boot -> Fast Boot [Disabled] / Secure Boot [Disabled]" }
  "MSI"      { "MSI BIOS (Del / Boot Menu F11): Settings -> Boot -> Fast Boot [Disabled] / Secure Boot [Disabled]" }
  default    { "BIOS Setup (F2/Del): USB Boot [Enabled] / Fast Boot [Disabled] / Secure Boot [Disabled]" }
 }

 $biosGuideShort = switch ($hintVendor) {
  "HP"       { U "HP \u00B7 BIOS F10 \u00B7 \uBD80\uD305 \uBA54\uB274 F9" }
  "Dell"     { U "Dell \u00B7 BIOS F2 \u00B7 \uBD80\uD305 \uBA54\uB274 F12" }
  "Samsung"  { U "\uC0BC\uC131 \u00B7 BIOS F2 \u00B7 \uBD80\uD305 \uBA54\uB274 F10 \uB610\uB294 F12" }
  "Lenovo"   { U "Lenovo \u00B7 BIOS F1 \u00B7 \uBD80\uD305 \uBA54\uB274 F12" }
  "LG"       { U "LG \u00B7 BIOS F2 \u00B7 \uBD80\uD305 \uBA54\uB274 F10" }
  "ASUS"     { U "ASUS \u00B7 BIOS F2/Del \u00B7 \uBD80\uD305 \uBA54\uB274 F8" }
  "ASRock"   { U "ASRock \u00B7 BIOS F2/Del \u00B7 \uBD80\uD305 \uBA54\uB274 F11" }
  "Gigabyte" { U "Gigabyte \u00B7 BIOS Del \u00B7 \uBD80\uD305 \uBA54\uB274 F12" }
  "MSI"      { U "MSI \u00B7 BIOS Del \u00B7 \uBD80\uD305 \uBA54\uB274 F11" }
  default    { U "BIOS F2 \uB610\uB294 Del \u00B7 \uBD80\uD305 \uBA54\uB274 \uB2E8\uCD95\uD0A4" }
 }

 $osSummary = "Windows"
 try {
  $osObj = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
  $cap = ([string]$osObj.Caption -replace "^Microsoft\s+", "").Trim()
  $dv = ""
  try {
   $dv = [string](Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "DisplayVersion" -ErrorAction Stop).DisplayVersion
  } catch {}
  if ($cap) {
   $osSummary = if ($dv) { $cap + " " + $dv } else { $cap }
  }
 } catch {}

 $displayVendor = if ($vendor -ne "Standard") { $vendor } elseif ($hintVendor -ne "Standard") { $hintVendor } else { "" }

 return [PSCustomObject]@{
  Vendor = $vendor
  HintVendor = $hintVendor
  DisplayVendor = $displayVendor
  ModelName = $modelName
  RawVendor = $rawVendor
  BiosVersion = [string]$bios.SMBIOSBIOSVersion
  BiosHint = $vendorBiosHint
  BiosGuideShort = $biosGuideShort
  OsSummary = $osSummary
 }
}

# Cross-verify UEFI vs Legacy boot mode using 3 independent sources:
# 1) bcdedit /enum {current} (winload.efi vs winload.exe)
# 2) Registry (PEFirmwareType in WinPE + SecureBoot\State key existence on UEFI Windows)
# 3) OS Boot Disk PartitionStyle (GPT = UEFI, MBR = Legacy; Windows strictly enforces this)
function Get-BootModeDiagnostics {
 $bcdSignal = "Unknown"
 $regSignal = "Unknown"
 $diskSignal = "Unknown"
 $signals = New-Object System.Collections.ArrayList

 $res = Invoke-NativeOem "bcdedit.exe" "/enum {current}"
 foreach ($line in $res.Lines) {
  $s = [string]$line
  if ($s -match "winload\.efi") { $bcdSignal = "UEFI"; break }
  if ($s -match "winload\.exe") { $bcdSignal = "Legacy"; break }
 }
 [void]$signals.Add(("bcdedit /enum {current} = " + $bcdSignal))

 $regSource = "none"
 try {
  $regVal = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "PEFirmwareType" -ErrorAction Stop).PEFirmwareType
  if ([int]$regVal -eq 2) { $regSignal = "UEFI"; $regSource = "PEFirmwareType=2" }
  elseif ([int]$regVal -eq 1) { $regSignal = "Legacy"; $regSource = "PEFirmwareType=1" }
 } catch {}
 if ($regSignal -eq "Unknown") {
  try {
   if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State") {
    $regSignal = "UEFI"
    $regSource = "SecureBoot\State exists"
   }
  } catch {}
 }
 [void]$signals.Add(("Registry Firmware = " + $regSignal + " (" + $regSource + ")"))

 try {
  if (Test-StorageCmdletsAvailable) {
   $bootDiskObj = Get-Disk -ErrorAction Stop | Where-Object { $_.IsBoot } | Select-Object -First 1
   if (-not $bootDiskObj) {
    $sysLtr = if ($env:SystemDrive -and $env:SystemDrive -match "^([A-Za-z]):") { $matches[1] } else { "C" }
    $sysPart = Get-Partition -DriveLetter $sysLtr -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($sysPart) {
     $bootDiskObj = Get-Disk -Number $sysPart.DiskNumber -ErrorAction SilentlyContinue
    }
   }
   if ($bootDiskObj) {
    $ps = [string]$bootDiskObj.PartitionStyle
    if ($ps -eq "GPT") { $diskSignal = "UEFI" }
    elseif ($ps -eq "MBR") { $diskSignal = "Legacy" }
   }
  }
 } catch {}
 [void]$signals.Add(("Boot Disk PartitionStyle = " + $diskSignal))

 $uefiCount = 0
 $legacyCount = 0
 foreach ($sig in @($bcdSignal, $regSignal, $diskSignal)) {
  if ($sig -eq "UEFI") { $uefiCount++ }
  elseif ($sig -eq "Legacy") { $legacyCount++ }
 }

 $mode = "Unknown"
 $confidence = "Unverifiable"
 if ($uefiCount -gt 0 -and $legacyCount -gt 0) {
  $mode = if ($bcdSignal -ne "Unknown") { $bcdSignal } elseif ($uefiCount -ge $legacyCount) { "UEFI" } else { "Legacy" }
  $confidence = "Conflict"
 } elseif ($uefiCount -gt 0) {
  $mode = "UEFI"
  $confidence = if ($uefiCount -ge 2) { "CrossConfirmed" } else { "SingleSource" }
 } elseif ($legacyCount -gt 0) {
  $mode = "Legacy"
  $confidence = if ($legacyCount -ge 2) { "CrossConfirmed" } else { "SingleSource" }
 }

 return [PSCustomObject]@{
  IsUefi = ($mode -eq "UEFI")
  Mode = $mode
  Confidence = $confidence
  BcdSignal = $bcdSignal
  RegSignal = $regSignal
  DiskSignal = $diskSignal
  Signals = @($signals)
 }
}

function Test-IsUefiBoot {
 return (Get-BootModeDiagnostics).IsUefi
}

# Pure helper: Parse HP WMI BIOS settings (separates Primary UEFI USB Boot vs Legacy/Port settings)
function Resolve-HpBiosDiagnostics([array]$hpSettings) {
 $usbState = "Unknown"
 $usbDetail = ""
 $fastWarn = $false
 $fastDetail = ""
 $secWmi = "Unavailable"
 $portWarn = $false
 $portDetail = ""
 $evidence = New-Object System.Collections.ArrayList

 if (-not $hpSettings -or $hpSettings.Count -eq 0) {
  return [PSCustomObject]@{
   UsbState = "UnverifiableHP"
   UsbDetail = U "HP WMI \uC124\uC815 \uBAA9\uB85D \uBE44\uC5B4 \uC788\uC74C"
   FastBootWarn = $false
   FastBootDetail = ""
   SecureBootWmi = "Unavailable"
   PortWarn = $false
   PortDetail = ""
   Evidence = @($evidence)
  }
 }

 $primaryEnabled = New-Object System.Collections.ArrayList
 $primaryDisabled = New-Object System.Collections.ArrayList

 foreach ($item in $hpSettings) {
  $name = [string]$item.Name
  if (-not $name) { continue }
  $rawVal = if ($item.CurrentValue) { [string]$item.CurrentValue } else { [string]$item.Value }
  $activeVal = if ($rawVal -match "\*([^,]+)") { $matches[1].Trim() } else { $rawVal.Trim() }
  if (-not $activeVal) { continue }

  # 1) Primary USB Boot settings (explicitly exclude Legacy-only, Charge, Wake, Security keys)
  if (($name -match "USB Storage Boot|USB Boot|Boot from USB|Removable Media Boot|USB Flash Media") -and
      ($name -notmatch "Legacy|Charge|Wake|Security|Network|PXE|Optical|CD|DVD")) {
   [void]$evidence.Add(("HP Primary USB: " + $name + " = " + $activeVal))
   if ($activeVal -match "^(Disable|Disabled|No|Off)$") {
    [void]$primaryDisabled.Add(($name + "=" + $activeVal))
   } elseif ($activeVal -match "^(Enable|Enabled|Yes|On)$") {
    [void]$primaryEnabled.Add(($name + "=" + $activeVal))
   }
  }
  # 2) Secondary Legacy USB / USB Port settings (recorded as evidence; Legacy Disable does NOT override UEFI Enable!)
  elseif ($name -match "Legacy.*USB|USB.*Legacy|USB Ports|External USB|Front USB|Rear USB") {
   [void]$evidence.Add(("HP Secondary USB/Port: " + $name + " = " + $activeVal))
   if ($name -notmatch "Legacy" -and $activeVal -match "^(Disable|Disabled|No|Off)$") {
    $portWarn = $true
    $portDetail = "HP WMI: " + $name + " = " + $activeVal
   }
  }

  # 3) Fast Boot (exclude Memory Fast Boot)
  if (($name -match "^(HP\s+)?Fast\s*Boot(\s*\(.*\))?$") -and ($name -notmatch "Memory|SATA")) {
   [void]$evidence.Add(("HP Fast Boot: " + $name + " = " + $activeVal))
   if ($activeVal -match "^(Enable|Enabled|Yes|On)$") {
    $fastWarn = $true
    $fastDetail = "HP WMI: " + $name + " = " + $activeVal
   }
  }

  # 4) Secure Boot WMI cross-check signal
  if ($name -match "^(Secure Boot|Configure Legacy Support and Secure Boot)$") {
   [void]$evidence.Add(("HP Secure Boot: " + $name + " = " + $activeVal))
   if ($activeVal -match "Secure Boot Enable|^(Enable|Enabled|On|Yes)$") { $secWmi = "On" }
   elseif ($activeVal -match "Secure Boot Disable|^(Disable|Disabled|Off|No)$") { $secWmi = "Off" }
  }
 }

 if ($primaryDisabled.Count -gt 0 -and $primaryEnabled.Count -gt 0) {
  $usbState = "Conflict"
  $usbDetail = "HP WMI Conflict: " + (($primaryDisabled + $primaryEnabled) -join "; ")
 } elseif ($primaryDisabled.Count -gt 0) {
  $usbState = "Disabled"
  $usbDetail = "HP WMI: " + ($primaryDisabled -join "; ")
 } elseif ($primaryEnabled.Count -gt 0) {
  $usbState = "Enabled"
  $usbDetail = "HP WMI: " + ($primaryEnabled -join "; ")
 } else {
  $usbState = "UnverifiableHP"
  $usbDetail = ((U "HP WMI \uC5F0\uACB0\uB428 / USB Boot \uD56D\uBAA9 \uBBF8\uBC1C\uACAC (") + $hpSettings.Count + (U "\uAC1C \uC124\uC815 \uC2A4\uCE94)"))
 }

 return [PSCustomObject]@{
  UsbState = $usbState
  UsbDetail = $usbDetail
  FastBootWarn = $fastWarn
  FastBootDetail = $fastDetail
  SecureBootWmi = $secWmi
  PortWarn = $portWarn
  PortDetail = $portDetail
  Evidence = @($evidence)
 }
}

# Helper: Type-safe Dell PossibleValues -> Description lookup
function Resolve-DellEnumValue($item) {
 $raw = if ($null -ne $item.CurrentValue) { (@($item.CurrentValue) -join ",").Trim() } else { "" }
 if (-not $raw) { return "" }
 if ($item.PossibleValues -and $item.PossibleValuesDescription) {
  $pVals = @($item.PossibleValues)
  $pDesc = @($item.PossibleValuesDescription)
  for ($i = 0; $i -lt $pVals.Count -and $i -lt $pDesc.Count; $i++) {
   if (([string]$pVals[$i]).Trim() -ieq $raw) {
    return ([string]$pDesc[$i]).Trim()
   }
  }
 }
 return $raw
}

# Pure helper: Parse Dell WMI BIOS settings (type-safe enum + primary/secondary separation)
function Resolve-DellBiosDiagnostics([array]$dellSettings) {
 $usbState = "Unknown"
 $usbDetail = ""
 $fastWarn = $false
 $fastDetail = ""
 $secWmi = "Unavailable"
 $portWarn = $false
 $portDetail = ""
 $evidence = New-Object System.Collections.ArrayList

 if (-not $dellSettings -or $dellSettings.Count -eq 0) {
  return [PSCustomObject]@{
   UsbState = "UnverifiableDell"
   UsbDetail = U "Dell WMI \uC124\uC815 \uBAA9\uB85D \uBE44\uC5B4 \uC788\uC74C"
   FastBootWarn = $false
   FastBootDetail = ""
   SecureBootWmi = "Unavailable"
   PortWarn = $false
   PortDetail = ""
   Evidence = @($evidence)
  }
 }

 $primaryEnabled = New-Object System.Collections.ArrayList
 $primaryDisabled = New-Object System.Collections.ArrayList

 foreach ($item in $dellSettings) {
  $name = [string]$item.AttributeName
  if (-not $name) { continue }
  $val = Resolve-DellEnumValue $item
  if (-not $val) { continue }

  # 1) Primary USB Boot settings (exclude Wake/PowerShare/Legacy-only)
  if (($name -match "EnableUsbBootSupport|UsbBootSupport|UsbBoot|BootUsb|UsbStorageBoot|UsbPortsBoot") -and
      ($name -notmatch "Wake|PowerShare|Legacy")) {
   [void]$evidence.Add(("Dell Primary USB: " + $name + " = " + $val))
   if ($val -match "^(Disable|Disabled|Off|None|No)$|Disable") {
    [void]$primaryDisabled.Add(($name + "=" + $val))
   } elseif ($val -match "^(Enable|Enabled|On|All|Yes)$|Enable") {
    [void]$primaryEnabled.Add(($name + "=" + $val))
   }
  }
  # 2) External USB Port controls
  elseif ($name -match "ExternalUsb|FrontUsb|RearUsb|UsbPorts") {
   [void]$evidence.Add(("Dell USB Port: " + $name + " = " + $val))
   if ($val -match "Disable|Off|None") {
    $portWarn = $true
    $portDetail = "Dell WMI: " + $name + " = " + $val
   }
  }

  # 3) Fastboot (Minimal skips USB init during POST; Auto may also skip)
  if ($name -match "^Fastboot$") {
   [void]$evidence.Add(("Dell Fastboot: " + $name + " = " + $val))
   if ($val -match "Minimal") {
    $fastWarn = $true
    $fastDetail = "Dell WMI: Fastboot = " + $val
   }
  }

  # 4) SecureBoot WMI cross-check signal
  if ($name -match "^SecureBoot$") {
   [void]$evidence.Add(("Dell SecureBoot: " + $name + " = " + $val))
   if ($val -match "Enable|On") { $secWmi = "On" }
   elseif ($val -match "Disable|Off") { $secWmi = "Off" }
  }
 }

 if ($primaryDisabled.Count -gt 0 -and $primaryEnabled.Count -gt 0) {
  $usbState = "Conflict"
  $usbDetail = "Dell WMI Conflict: " + (($primaryDisabled + $primaryEnabled) -join "; ")
 } elseif ($primaryDisabled.Count -gt 0) {
  $usbState = "Disabled"
  $usbDetail = "Dell WMI: " + ($primaryDisabled -join "; ")
 } elseif ($primaryEnabled.Count -gt 0) {
  $usbState = "Enabled"
  $usbDetail = "Dell WMI: " + ($primaryEnabled -join "; ")
 } else {
  $usbState = "UnverifiableDell"
  $usbDetail = ((U "Dell WMI \uC5F0\uACB0\uB428 / USB Boot \uD56D\uBAA9 \uBBF8\uBC1C\uACAC (") + $dellSettings.Count + (U "\uAC1C \uC124\uC815 \uC2A4\uCE94)"))
 }

 return [PSCustomObject]@{
  UsbState = $usbState
  UsbDetail = $usbDetail
  FastBootWarn = $fastWarn
  FastBootDetail = $fastDetail
  SecureBootWmi = $secWmi
  PortWarn = $portWarn
  PortDetail = $portDetail
  Evidence = @($evidence)
 }
}

# Pure helper: 3-signal Secure Boot cross-verification (UEFI API + Kernel Registry + Vendor WMI)
function Resolve-SecureBootCrossCheck([string]$apiSignal, [string]$regSignal, [string]$wmiSignal) {
 $signals = New-Object System.Collections.ArrayList
 [void]$signals.Add(("Confirm-SecureBootUEFI = " + $apiSignal))
 [void]$signals.Add(("Registry UEFISecureBootEnabled = " + $regSignal))
 if ($wmiSignal -and $wmiSignal -ne "Unavailable") {
  [void]$signals.Add(("Vendor WMI SecureBoot = " + $wmiSignal))
 }

 $onCount = 0
 $offCount = 0
 foreach ($s in @($apiSignal, $regSignal, $wmiSignal)) {
  if ($s -eq "On") { $onCount++ }
  elseif ($s -eq "Off") { $offCount++ }
 }

 $state = "Unknown"
 $confidence = "Unverifiable"
 if ($onCount -gt 0 -and $offCount -gt 0) {
  $state = "Conflict"
  $confidence = "Conflict"
 } elseif ($onCount -gt 0) {
  $state = "On"
  $confidence = if ($onCount -ge 2) { "CrossConfirmed" } else { "SingleSource" }
 } elseif ($offCount -gt 0) {
  $state = "Off"
  $confidence = if ($offCount -ge 2) { "CrossConfirmed" } else { "SingleSource" }
 }

 return [PSCustomObject]@{
  State = $state
  IsOnOrRisk = ($state -eq "On" -or $state -eq "Conflict")
  Confidence = $confidence
  Signals = @($signals)
 }
}

# Pure helper: Cross-check Vendor WMI vs NVRAM vs Physical USB to eliminate false positives
function Resolve-BiosCrossCheckVerdict(
 [string]$vendor,
 [string]$wmiState,
 [string]$wmiDetail,
 [bool]$fastBootWarn,
 [bool]$portWarn,
 [string]$portDetail,
 [bool]$nvramHasStrictUsb,
 [int]$physicalUsbCount,
 [int]$matchedNvramCount
) {
 $finalState = $wmiState
 $confidence = "Unverifiable"
 $summary = $wmiDetail
 $hasConflict = $false

 if ($wmiState -eq "Conflict") {
  $finalState = "Conflict"
  $confidence = "Conflict"
  $hasConflict = $true
 } elseif ($wmiState -eq "Enabled") {
  if ($portWarn) {
   $finalState = "PortBlocked"
   $confidence = "CrossChecked"
   $summary = $wmiDetail + " | " + $portDetail
  } elseif ($matchedNvramCount -gt 0 -or $nvramHasStrictUsb) {
   $finalState = "Enabled"
   $confidence = "CrossConfirmed"
  } else {
   $finalState = "Enabled"
   $confidence = "WmiOnly"
  }
 } elseif ($wmiState -eq "Disabled") {
  # Cross-check: If WMI claims Disabled, yet NVRAM actually enumerated a connected USB, flag Conflict instead of blind false-positive!
  if ($matchedNvramCount -gt 0 -or ($physicalUsbCount -gt 0 -and $nvramHasStrictUsb)) {
   $finalState = "Conflict"
   $confidence = "Conflict"
   $hasConflict = $true
   $summary = $wmiDetail + (U " / \uB2E8, UEFI NVRAM\uC5D0\uC11C USB \uBD80\uD305 \uD56D\uBAA9\uC774 \uC2E4\uC81C \uAC10\uC9C0\uB428 (\uAD50\uCC28 \uD655\uC778 \uD544\uC694)")
  } else {
   $finalState = "Disabled"
   $confidence = if ($physicalUsbCount -gt 0) { "CrossConfirmed" } else { "WmiOnly" }
  }
 } else {
  # Rule #5 strictly preserved: Never assume WMI-unsupported boards are ON
  if ($vendor -eq "Samsung") {
   $finalState = "UnverifiableAMI"
   if ($matchedNvramCount -gt 0 -or $nvramHasStrictUsb) {
    $confidence = "NvramObserved"
    $summary = U "Samsung/AMI WMI \uBBF8\uC9C0\uC6D0 (\uD655\uC778 \uBD88\uAC00) / NVRAM USB \uBD80\uD305 \uD56D\uBAA9 \uAD00\uCE21\uB428"
   } else {
    $confidence = "Unverifiable"
    $summary = U "Samsung/AMI BIOS WMI \uBBF8\uC9C0\uC6D0 - F2 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
   }
  } elseif ($wmiState -in @("UnverifiableHP","UnverifiableDell")) {
   $finalState = $wmiState
   if ($matchedNvramCount -gt 0 -or $nvramHasStrictUsb) {
    $confidence = "NvramObserved"
    $summary = $wmiDetail + (U " / NVRAM USB \uD56D\uBAA9 \uAD00\uCE21\uB428")
   } else {
    $confidence = "Unverifiable"
   }
  } elseif ($matchedNvramCount -gt 0 -or $nvramHasStrictUsb) {
   $finalState = "UnverifiableNVRAM"
   $confidence = "NvramObserved"
   $summary = U "WMI \uBBF8\uC9C0\uC6D0 (\uD655\uC778 \uBD88\uAC00) / NVRAM USB \uD56D\uBAA9 \uAC10\uC9C0\uB428"
  } elseif ($physicalUsbCount -gt 0) {
   $finalState = "SuspectedDisabled"
   $confidence = "Suspected"
   $summary = U "USB \uC7A5\uCC29\uB428 / NVRAM \uBBF8\uB4F1\uB85D (Hot-Plug \uB610\uB294 BIOS \uCC28\uB2E8 \uAC00\uB2A5)"
  } else {
   $finalState = "UnverifiableAMI"
   $confidence = "Unverifiable"
   $summary = U "WMI \uBBF8\uC9C0\uC6D0 - BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
  }
 }

 return [PSCustomObject]@{
  UsbBootState = $finalState
  UsbBootConfidence = $confidence
  UsbBootDetail = $summary
  HasSignalConflict = $hasConflict
  IsConfirmedBlocked = ($finalState -in @("Disabled","PortBlocked"))
 }
}

function Get-BiosDiagnostics($sysInfo, [array]$usbDisks, [array]$bcdEntries, [int]$matchedNvramCount = -1) {
 $vendor = $sysInfo.Vendor
 $koBootMgr = U "Windows \uBD80\uD305 \uAD00\uB9AC\uC790"
 $excludeDescPattern = "Windows Boot Manager|" + [regex]::Escape($koBootMgr) + "|SATA|NVMe|Hard Drive \(SATA|Hard Drive \(NVMe|PXE|IPV4|IPV6|Network|CD/DVD"

 # Strict NVRAM USB check (excludes internal SSD brands like Samsung/Crucial/Micron)
 $nvramUsbEntries = @(
  $bcdEntries | Where-Object {
   $_.Identifier -ne "{fwbootmgr}" -and $_.Identifier -ne "{bootmgr}" -and
   ([string]$_.Description -notmatch $excludeDescPattern) -and
   ([string]$_.Description -match "\bUSB\b|Removable|External|Flash|SanDisk|Ventoy|Phoenix")
  }
 )
 $nvramHasStrictUsbEntry = ($nvramUsbEntries.Count -gt 0)
 $effectiveMatchCount = if ($matchedNvramCount -ge 0) { $matchedNvramCount } else { $nvramUsbEntries.Count }

 $bootModeDiag = Get-BootModeDiagnostics
 $evidence = New-Object System.Collections.ArrayList
 foreach ($bs in $bootModeDiag.Signals) { [void]$evidence.Add(("BootMode: " + $bs)) }

 # Query vendor WMI (HP: HP_BIOSSetting + HP_BIOSEnumeration | Dell: DCIM_BIOSEnumeration + biosattributes)
 $wmiState = "Unknown"
 $wmiDetail = ""
 $fastBootWarn = $false
 $fastBootDetail = ""
 $secWmiSignal = "Unavailable"
 $portWarn = $false
 $portDetail = ""

 if ($vendor -eq "HP") {
  $hpRaw = @()
  try {
   $hpRaw = @(Get-CimInstance -Namespace "root\HP\InstrumentedBIOS" -ClassName "HP_BIOSSetting" -ErrorAction Stop)
  } catch {}
  if ($hpRaw.Count -eq 0) {
   try {
    $hpRaw = @(Get-CimInstance -Namespace "root\HP\InstrumentedBIOS" -ClassName "HP_BIOSEnumeration" -ErrorAction Stop)
   } catch {}
  }
  if ($hpRaw.Count -gt 0) {
   $hpRes = Resolve-HpBiosDiagnostics $hpRaw
   $wmiState = $hpRes.UsbState
   $wmiDetail = $hpRes.UsbDetail
   $fastBootWarn = $hpRes.FastBootWarn
   $fastBootDetail = $hpRes.FastBootDetail
   $secWmiSignal = $hpRes.SecureBootWmi
   $portWarn = $hpRes.PortWarn
   $portDetail = $hpRes.PortDetail
   foreach ($ev in $hpRes.Evidence) { [void]$evidence.Add($ev) }
  } else {
   $wmiState = "UnverifiableHP"
   $wmiDetail = U "HP WMI \uC870\uD68C \uC2E4\uD328 - F10 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
   [void]$evidence.Add("HP WMI: root\HP\InstrumentedBIOS unavailable")
  }
 } elseif ($vendor -eq "Dell") {
  $dellRaw = @()
  try {
   $dellRaw = @(Get-CimInstance -Namespace "root\dcim\sysman" -ClassName "DCIM_BIOSEnumeration" -ErrorAction Stop)
  } catch {}
  if ($dellRaw.Count -eq 0) {
   try {
    $dellRaw = @(Get-CimInstance -Namespace "root\dcim\sysman\biosattributes" -ClassName "EnumerationAttribute" -ErrorAction Stop)
   } catch {}
  }
  if ($dellRaw.Count -gt 0) {
   $dellRes = Resolve-DellBiosDiagnostics $dellRaw
   $wmiState = $dellRes.UsbState
   $wmiDetail = $dellRes.UsbDetail
   $fastBootWarn = $dellRes.FastBootWarn
   $fastBootDetail = $dellRes.FastBootDetail
   $secWmiSignal = $dellRes.SecureBootWmi
   $portWarn = $dellRes.PortWarn
   $portDetail = $dellRes.PortDetail
   foreach ($ev in $dellRes.Evidence) { [void]$evidence.Add($ev) }
  } else {
   $wmiState = "UnverifiableDell"
   $wmiDetail = U "Dell WMI \uBBF8\uC124\uCE58(DCM \uC5C6\uC74C) - F2 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
   [void]$evidence.Add("Dell WMI: root\dcim\sysman unavailable (DCM not installed)")
  }
 } else {
  [void]$evidence.Add(("Vendor WMI: " + $vendor + " (BIOS WMI unsupported - conservative mode)"))
 }

 # 3-signal Secure Boot cross-check (never silently defaults to OFF on error!)
 $secApi = "Unavailable"
 try {
  $sbVal = Confirm-SecureBootUEFI -ErrorAction Stop
  $secApi = if ($sbVal) { "On" } else { "Off" }
 } catch {
  $secApi = "Unavailable"
 }
 $secReg = "Unavailable"
 try {
  $regSb = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State" -Name "UEFISecureBootEnabled" -ErrorAction Stop).UEFISecureBootEnabled
  if ([int]$regSb -eq 1) { $secReg = "On" }
  elseif ([int]$regSb -eq 0) { $secReg = "Off" }
 } catch {}

 $secDiag = Resolve-SecureBootCrossCheck $secApi $secReg $secWmiSignal
 foreach ($ss in $secDiag.Signals) { [void]$evidence.Add(("SecureBoot: " + $ss)) }

 # Windows Fast Startup (informational cross-check)
 $winFastStartup = $null
 try {
  $hb = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -ErrorAction Stop).HiberbootEnabled
  $winFastStartup = ([int]$hb -eq 1)
  [void]$evidence.Add(("Windows Fast Startup (HiberbootEnabled) = " + $winFastStartup))
 } catch {}

 [void]$evidence.Add(("Physical USB Disks Online = " + $usbDisks.Count))
 [void]$evidence.Add(("UEFI NVRAM Total Entries = " + $bcdEntries.Count + " | Strict USB Entries = " + $nvramUsbEntries.Count))

 $verdict = Resolve-BiosCrossCheckVerdict `
  $vendor $wmiState $wmiDetail $fastBootWarn $portWarn $portDetail `
  $nvramHasStrictUsbEntry $usbDisks.Count $effectiveMatchCount

 return [PSCustomObject]@{
  BootMode = $bootModeDiag
  SecureBoot = $secDiag.IsOnOrRisk
  SecureBootState = $secDiag.State
  SecureBootConfidence = $secDiag.Confidence
  SecureBootSignals = $secDiag.Signals
  UsbBootState = $verdict.UsbBootState
  UsbBootConfidence = $verdict.UsbBootConfidence
  UsbBootDetail = $verdict.UsbBootDetail
  HasSignalConflict = ($verdict.HasSignalConflict -or $secDiag.State -eq "Conflict" -or $bootModeDiag.Confidence -eq "Conflict")
  IsConfirmedBlocked = $verdict.IsConfirmedBlocked
  FastBootWarn = $fastBootWarn
  FastBootDetail = $fastBootDetail
  PortWarn = $portWarn
  PortDetail = $portDetail
  WindowsFastStartup = $winFastStartup
  BiosHint = $sysInfo.BiosHint
  Evidence = @($evidence)
 }
}

# Format human-readable full BIOS Cross-Check report (for GUI Diagnostic Popup & Clipboard)
function Format-BiosCrossCheckReport($sysInfo, $diag, $usbInfo, [array]$matchedEntries) {
 $sb = New-Object System.Text.StringBuilder
 [void]$sb.AppendLine("==================================================================")
 [void]$sb.AppendLine((U " [BIOS \uAD50\uCC28 \uAC80\uC99D \uC0C1\uC138 \uBCF4\uACE0\uC11C]"))
 [void]$sb.AppendLine("==================================================================")
 [void]$sb.AppendLine(("Tool Version : v" + $script:ToolVersion + " (build " + $script:BuildDate + " / " + $script:BuildCommit + ")"))
 [void]$sb.AppendLine(("System       : [" + $sysInfo.Vendor + "] " + $sysInfo.ModelName))
 [void]$sb.AppendLine(("Raw Vendor   : " + $sysInfo.RawVendor))
 if ($sysInfo.BiosVersion) { [void]$sb.AppendLine(("BIOS Version : " + $sysInfo.BiosVersion)) }
 [void]$sb.AppendLine(("Boot Mode    : " + $diag.BootMode.Mode + " (" + $diag.BootMode.Confidence + ")"))
 [void]$sb.AppendLine(("Secure Boot  : " + $diag.SecureBootState + " (" + $diag.SecureBootConfidence + ")"))
 [void]$sb.AppendLine(("USB Boot     : " + $diag.UsbBootState + " (" + $diag.UsbBootConfidence + ") - " + $diag.UsbBootDetail))
 if ($diag.FastBootWarn) { [void]$sb.AppendLine(("Fast Boot    : WARNING - " + $diag.FastBootDetail)) }
 if ($diag.PortWarn) { [void]$sb.AppendLine(("USB Ports    : WARNING - " + $diag.PortDetail)) }
 [void]$sb.AppendLine(("BIOS Hint    : " + $diag.BiosHint))
 [void]$sb.AppendLine("")
 [void]$sb.AppendLine((U "--- [\uC218\uC9D1\uB41C \uAD50\uCC28 \uAC80\uC99D \uC2E0\uD638 (Raw Evidence)] ---"))
 foreach ($ev in $diag.Evidence) {
  [void]$sb.AppendLine((" * " + $ev))
 }
 [void]$sb.AppendLine("")
 [void]$sb.AppendLine((U "--- [\uBB3C\uB9AC USB \uBC0F NVRAM \uB9E4\uCE6D \uC694\uC57D] ---"))
 if ($usbInfo -and $usbInfo.PhysicalUsbList.Count -gt 0) {
  foreach ($u in $usbInfo.PhysicalUsbList) {
   $ro = if ($u.IsReadOnly) { " [ReadOnly]" } else { "" }
   [void]$sb.AppendLine((" * Disk " + $u.DiskNumber + ": " + $u.Model + " [" + $u.SizeGB + "]" + $ro + " | " + $u.Partitions + " | Ready=" + $u.IsEfiReady))
  }
 } else {
  [void]$sb.AppendLine(" * (No physical USB disk connected)")
 }
 if ($matchedEntries -and $matchedEntries.Count -gt 0) {
  foreach ($m in $matchedEntries) {
   [void]$sb.AppendLine((" -> MATCH [" + $m.MatchTag + "] " + $m.Description + " | Device=" + $m.Device + " | GUID=" + $m.Identifier))
  }
 } else {
  [void]$sb.AppendLine(" -> (0 NVRAM USB matches)")
 }
 return $sb.ToString()
}

# Contextual UX Guidance Engine for Pre-SID (plain commercial Korean, zero brackets/parentheses/jargon)
function Get-PreSidGuidance($sysInfo, $efiRep, $diag, $usbInfo, [array]$matchedEntries, [bool]$step1Bypassed) {
 if ($diag -and -not $diag.BootMode.IsUefi) {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "\uB808\uAC70\uC2DC \uBD80\uD305 \uBC29\uC2DD\uC774\uB77C \uC790\uB3D9 USB \uC7AC\uBD80\uD305\uC744 \uC9C0\uC6D0\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4"
   Message = U "\uC7AC\uBD80\uD305\uD560 \uB54C \uC81C\uC870\uC0AC \uBD80\uD305 \uBA54\uB274 \uB2E8\uCD95\uD0A4\uB85C WinPE USB\uB97C \uC9C1\uC811 \uC120\uD0DD\uD574 \uC8FC\uC138\uC694. \uC0AC\uD6C4 \uD504\uB9B0\uD130 \uBCF5\uAD6C \uD0ED\uC740 \uC774 PC\uC5D0\uC11C\uB3C4 \uC815\uC0C1 \uC0AC\uC6A9\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4."
   RecommendedAction = "LEGACY_INFO"
  }
 }
 if ($efiRep -and $efiRep.HasBlockingRisk -and -not $step1Bypassed) {
  if ($efiRep.SplitBoot) {
   return [PSCustomObject]@{
    Level = "Error"
    Title = U "Windows\uC640 \uBD80\uD305 \uD30C\uD2F0\uC158\uC774 \uC11C\uB85C \uB2E4\uB978 \uB514\uC2A4\uD06C\uC5D0 \uB098\uB258\uC5B4 \uC788\uC2B5\uB2C8\uB2E4"
    Message = ((U "Disk ") + $efiRep.BootDisk + (U "\uACFC Disk ") + $efiRep.SysDisk + (U "\uC5D0 \uBD80\uD305 \uAD6C\uC131\uC774 \uBD84\uB9AC\uB418\uC5B4 \uC790\uB3D9 \uC815\uB9AC\uB97C \uC911\uB2E8\uD588\uC2B5\uB2C8\uB2E4. \uB514\uC2A4\uD06C \uAD6C\uC131\uC744 \uBA3C\uC800 \uD655\uC778\uD574 \uC8FC\uC138\uC694."))
    RecommendedAction = "STEP1_SPLIT"
   }
  }
  $cList = ($efiRep.ConflictItems | ForEach-Object { "Disk " + $_.DiskNumber }) -join ", "
  if ($efiRep.ActionableConflictItems.Count -gt 0) {
   return [PSCustomObject]@{
    Level = "Error"
    Title = U "\uBA3C\uC800 \uBCF4\uC870 \uB514\uC2A4\uD06C\uC758 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uB97C \uC815\uB9AC\uD574 \uC8FC\uC138\uC694"
    Message = ($cList + (U "\uC5D0 \uC774\uC804 \uBD80\uD2B8\uB85C\uB354\uAC00 \uB0A8\uC544 \uC788\uC2B5\uB2C8\uB2E4. SID \uBCC0\uACBD \uD6C4 \uBD80\uD305 \uC624\uB958\uB97C \uB9C9\uAE30 \uC704\uD574 1\uB2E8\uACC4\uC758 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uC815\uB9AC\uB97C \uBA3C\uC800 \uC2E4\uD589\uD574 \uC8FC\uC138\uC694."))
    RecommendedAction = "STEP1_FIX"
   }
  }
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "\uBCF4\uC870 \uB514\uC2A4\uD06C\uC5D0 \uC9C1\uC811 \uD655\uC778\uC774 \uD544\uC694\uD55C \uD56D\uBAA9\uC774 \uC788\uC2B5\uB2C8\uB2E4"
   Message = ($cList + (U "\uC758 \uACBD\uACE0 \uC0C1\uD0DC\uB97C \uBA3C\uC800 \uD655\uC778\uD574 \uC8FC\uC138\uC694. \uC774\uC0C1\uC774 \uC5C6\uB2E4\uBA74 \uC704\uD5D8 \uD655\uC778 \uD6C4 \uAC74\uB108\uB6F0\uAE30\uB97C \uB20C\uB7EC 2\uB2E8\uACC4\uB85C \uC774\uB3D9\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4."))
   RecommendedAction = "STEP1_MANUAL"
  }
 }

 # STEP 1 passed or explicitly bypassed -> guide STEP 2 based on cross-checked BIOS + USB state
 if ($diag.SecureBootState -eq "On" -or $diag.SecureBootState -eq "Conflict") {
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "\uBCF4\uC548 \uBD80\uD305 \uC124\uC815\uC744 \uD655\uC778\uD574 \uC8FC\uC138\uC694"
   Message = U "\uBCF4\uC548 \uBD80\uD305\uC774 \uCF1C\uC838 \uC788\uC73C\uBA74 WinPE USB\uAC00 \uCC28\uB2E8\uB420 \uC218 \uC788\uC2B5\uB2C8\uB2E4. BIOS \uC124\uC815 \uC5F4\uAE30\uB85C \uD574\uC81C\uD558\uAC70\uB098, \uC11C\uBA85\uB41C WinPE\uB77C\uBA74 \uC544\uB798 USB\uB85C \uC9C4\uD589\uD574 \uC8FC\uC138\uC694."
   RecommendedAction = "BIOS_SETUP"
  }
 }
 if ($diag.IsConfirmedBlocked) {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "BIOS\uC5D0\uC11C USB \uBD80\uD305\uC774 \uCC28\uB2E8\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4"
   Message = U "\uC544\uB798 BIOS \uC124\uC815 \uC5F4\uAE30\uB97C \uB20C\uB7EC USB \uBD80\uD305 \uC635\uC158\uC744 \uD5C8\uC6A9\uC73C\uB85C \uBCC0\uACBD\uD55C \uB4A4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694."
   RecommendedAction = "BIOS_SETUP"
  }
 }
 if (-not $usbInfo -or $usbInfo.PhysicalUsbList.Count -eq 0) {
  return [PSCustomObject]@{
   Level = "Info"
   Title = U "WinPE \uBD80\uD305 USB\uB97C \uC5F0\uACB0\uD574 \uC8FC\uC138\uC694"
   Message = U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C \uC810\uAC80\uC744 \uD1B5\uACFC\uD588\uC2B5\uB2C8\uB2E4. WinPE USB\uB97C PC\uC5D0 \uAF42\uC740 \uB4A4 USB \uB2E4\uC2DC \uCC3E\uAE30\uB97C \uB20C\uB7EC \uC8FC\uC138\uC694."
   RecommendedAction = "PLUG_USB"
  }
 }
 if ($matchedEntries -and $matchedEntries.Count -gt 0) {
  if ($diag.HasSignalConflict) {
   return [PSCustomObject]@{
    Level = "Warn"
    Title = U "BIOS \uC124\uC815\uACFC \uD38C\uC6E8\uC5B4 \uBAA9\uB85D \uAC04 \uCC28\uC774\uAC00 \uAC10\uC9C0\uB418\uC5C8\uC2B5\uB2C8\uB2E4"
    Message = U "USB \uBD80\uD305 \uD56D\uBAA9\uC774 \uC2E4\uC81C \uBAA9\uB85D\uC5D0\uC11C \uD655\uC778\uB418\uC5C8\uC2B5\uB2C8\uB2E4. BIOS \uC9C4\uB2E8 \uC0C1\uC138\uB97C \uD655\uC778\uD558\uAC70\uB098 \uC544\uB798 \uC120\uD0DD\uD55C USB\uB85C \uC7AC\uBD80\uD305\uC744 \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694."
    RecommendedAction = "USB_REBOOT"
   }
  }
  return [PSCustomObject]@{
   Level = "OK"
   Title = U "WinPE USB\uB85C \uC7AC\uBD80\uD305\uD560 \uC900\uBE44\uAC00 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4"
   Message = U "2\uB2E8\uACC4 \uBAA9\uB85D\uC5D0\uC11C \uBD80\uD305\uD560 USB\uAC00 \uB9DE\uB294\uC9C0 \uD655\uC778\uD55C \uB4A4 \uC120\uD0DD\uD55C USB\uB85C \uC7AC\uBD80\uD305\uC744 \uB20C\uB7EC \uC8FC\uC138\uC694."
   RecommendedAction = "USB_REBOOT"
  }
 }

 # Physical USB plugged in, 0 NVRAM matches
 $isLikelyHotPlug = ($diag.UsbBootState -eq "Enabled" -and -not $diag.FastBootWarn)
 if ($isLikelyHotPlug) {
  return [PSCustomObject]@{
   Level = "Info"
   Title = U "\uACE0\uAE09 \uBD80\uD305\uC5D0\uC11C USB\uB97C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694"
   Message = U "Windows\uB97C \uCF1C \uB4A4 USB\uB97C \uC5F0\uACB0\uD574 \uD38C\uC6E8\uC5B4 \uBAA9\uB85D\uC5D0 \uC544\uC9C1 \uB098\uD0C0\uB098\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4. \uC544\uB798 \uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9\uC744 \uB20C\uB7EC \uC7A5\uCE58 \uC0AC\uC6A9 \uBA54\uB274\uC5D0\uC11C USB\uB97C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694."
   RecommendedAction = "ADV_BOOT"
  }
 }
 return [PSCustomObject]@{
  Level = "Warn"
  Title = U "USB\uB294 \uC5F0\uACB0\uB418\uC5C8\uC9C0\uB9CC \uBD80\uD305 \uBAA9\uB85D\uC5D0 \uB098\uD0C0\uB098\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4"
  Message = U "\uBC29\uAE08 \uAF42\uC740 USB\uB77C\uBA74 \uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9\uC744 \uB20C\uB7EC \uC8FC\uC138\uC694. \uBD80\uD305 \uC804\uBD80\uD130 \uAF42\uD600 \uC788\uC5C8\uB2E4\uBA74 BIOS \uC124\uC815 \uC5F4\uAE30\uC5D0\uC11C USB \uBD80\uD305\uACFC \uBE60\uB978 \uBD80\uD305 \uC635\uC158\uC744 \uD655\uC778\uD574 \uC8FC\uC138\uC694."
  RecommendedAction = "BIOS_SETUP"
 }
}

function Show-BiosStatusDashboard($diag, [bool]$step1Bypassed) {
 if ($step1Bypassed) {
  Write-Host (U " * STEP 1 \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80 : [\uC8FC\uC758 - \uC0AC\uC6A9\uC790 \uD655\uC778(IGNORE)\uC73C\uB85C \uAC74\uB108\uB700]") -ForegroundColor Yellow
 } else {
  Write-Host (U " * STEP 1 \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80 : [\uD1B5\uACFC - \uCDA9\uB3CC \uC5C6\uC74C]") -ForegroundColor Green
 }

 if ($diag.SecureBootState -eq "On") {
  Write-Host ((U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uD65C\uC131\uD654\uB428 - ON (\uACBD\uACE0)] [") + $diag.SecureBootConfidence + "]") -ForegroundColor Red
 } elseif ($diag.SecureBootState -eq "Conflict") {
  Write-Host (U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uC2E0\uD638 \uCDA9\uB3CC - \uD655\uC778 \uD544\uC694 (\uACBD\uACE0)]") -ForegroundColor Red
 } elseif ($diag.SecureBootState -eq "Off") {
  Write-Host ((U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uBE44\uD65C\uC131\uD654 - OFF (\uC815\uC0C1)] [") + $diag.SecureBootConfidence + "]") -ForegroundColor Green
 } else {
  Write-Host (U " * Secure Boot (\uBCF4\uC548 \uBD80\uD305) : [\uD655\uC778 \uBD88\uAC00 - BIOS \uD655\uC778 \uAD8C\uC7A5]") -ForegroundColor Yellow
 }

 if ($diag.UsbBootState -eq "Disabled" -or $diag.UsbBootState -eq "PortBlocked") {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uBE44\uD65C\uC131\uD654 - OFF (\uACBD\uACE0)] (") + $diag.UsbBootDetail + ")") -ForegroundColor Red
 } elseif ($diag.UsbBootState -eq "Conflict") {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uAD50\uCC28 \uAC80\uC99D \uCDA9\uB3CC - \uC8FC\uC758] (") + $diag.UsbBootDetail + ")") -ForegroundColor Yellow
 } elseif ($diag.UsbBootState -eq "SuspectedDisabled") {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uBE44\uD65C\uC131\uD654 \uC758\uC2EC - \uACBD\uACE0] (") + $diag.UsbBootDetail + ")") -ForegroundColor Red
 } elseif ($diag.UsbBootState -eq "Enabled") {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uD65C\uC131\uD654\uB428 - ON (\uC815\uC0C1)] [") + $diag.UsbBootConfidence + "] (" + $diag.UsbBootDetail + ")") -ForegroundColor Green
 } else {
  Write-Host ((U " * BIOS USB Boot \uC635\uC158 : [\uD655\uC778 \uBD88\uAC00] (") + $diag.UsbBootDetail + ")") -ForegroundColor Yellow
 }

 if ($diag.FastBootWarn) {
  Write-Host ((U " * BIOS Fast Boot \uC635\uC158 : [\uD65C\uC131\uD654\uB428 - \uC8FC\uC758] (") + $diag.FastBootDetail + ")") -ForegroundColor Yellow
 }
 Write-Host (" * BIOS Hint          : " + $diag.BiosHint) -ForegroundColor DarkGray
}

# Gate 1: Secure Boot / Confirmed Disabled USB Boot (Console TUI)
function Invoke-Gate1Check($diag, [array]$bcdOutput) {
 if (-not ($diag.SecureBoot -or $diag.IsConfirmedBlocked)) {
  return "CONTINUE"
 }

 while ($true) {
  Write-Host "`n==================================================================" -ForegroundColor Red
  Write-Host (U " [\uACBD\uACE0] BIOS \uBD80\uD305 \uCC28\uB2E8 \uC694\uC18C\uAC00 \uAC10\uC9C0\uB418\uC5C8\uC2B5\uB2C8\uB2E4!") -ForegroundColor Red
  if ($diag.SecureBoot) {
   Write-Host (U " - Secure Boot\uAC00 \uCF1C\uC838 \uC788\uAC70\uB098 \uC2E0\uD638 \uCDA9\uB3CC \uC0C1\uD0DC\uC785\uB2C8\uB2E4 (WinPE \uCC28\uB2E8 \uAC00\uB2A5).") -ForegroundColor Yellow
  }
  if ($diag.IsConfirmedBlocked) {
   Write-Host ((U " - BIOS\uC5D0\uC11C USB \uBD80\uD305/\uD3EC\uD2B8 \uC635\uC158\uC774 \uBE44\uD65C\uC131\uD654\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4: ") + $diag.UsbBootDetail) -ForegroundColor Yellow
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
