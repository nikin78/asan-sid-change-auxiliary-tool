# ==============================================================================
# Module 03: System Vendor Identification, Multi-Signal BIOS Cross-Verification
#            & Contextual Pre-SID Action Guidance Engine
# ==============================================================================

# Map Asan Hospital fleet asset codes & SMBIOS models (S4/S5/S8/S9, H0/H1/H2/H3/H4/HS/H6/H8, D1/D8)
function Resolve-HospitalModelProfile([string]$vendor, [string]$hintVendor, [string]$modelName, [string]$cpuName, [string]$compName) {
 $assetCode = ""
 if ($compName -and $compName -match "^(?i)C\d{6}([A-Z0-9]{2})$") {
  $assetCode = $matches[1].ToUpper()
 }
 $effVendor = if ($vendor -ne "Standard") { $vendor } elseif ($hintVendor -ne "Standard") { $hintVendor } else { "" }
 if (-not $effVendor -and $assetCode) {
  if ($assetCode -match "^S\d$") { $effVendor = "Samsung" }
  elseif ($assetCode -match "^H[0-9SBD]$") { $effVendor = "HP" }
  elseif ($assetCode -match "^D[0-9C]$") { $effVendor = "Dell" }
 }

 $genFamily = ""
 $resolvedModel = $modelName
 if ($effVendor -eq "Samsung") {
  if ($modelName -match "(?i)DB400T9A|DM500T9A" -or $assetCode -eq "S9" -or $cpuName -match "i[357]-9\d{3}") {
   $genFamily = "SAMSUNG_DB400T"
   if ($resolvedModel -eq "Desktop PC") { $resolvedModel = "Samsung DB400T9A (S9)" }
  } elseif ($modelName -match "(?i)DB400T8A|DB400T7B|DM500T8A" -or $assetCode -eq "S8" -or $cpuName -match "i[357]-8\d{3}") {
   $genFamily = "SAMSUNG_DB400T"
   if ($resolvedModel -eq "Desktop PC") { $resolvedModel = "Samsung DB400T8A (S8)" }
  } elseif ($assetCode -in @("S4","S5") -or $cpuName -match "i[357]-(650|2\d{3})") {
   $genFamily = "SAMSUNG_LEGACY"
   if ($resolvedModel -eq "Desktop PC") { $resolvedModel = "Samsung Desktop (" + $(if ($assetCode) { $assetCode } else { "Legacy" }) + ")" }
  } else {
   $genFamily = "SAMSUNG_DB400T"
  }
 } elseif ($effVendor -eq "HP") {
  if ($modelName -match "(?i)\bG(8|9|10|11)\b|Elite\s+Tower\s+[68]00|Pro\s+Tower\s+400" -or $assetCode -in @("H1","H2") -or $cpuName -match "i[3579]-1[1-4]\d{3}") {
   $genFamily = "HP_G8_G9"
   if ($resolvedModel -eq "Desktop PC") {
    $resolvedModel = if ($cpuName -match "i[3579]-1[2-4]\d{3}") { "HP Elite Tower 800 G9" } else { "HP EliteDesk 800 G8" }
   }
  } elseif ($modelName -match "(?i)ProDesk\s+600\s*G[1-5]|EliteDesk\s+800\s*G[1-5]|Compaq\s+(Pro\s+6300|Elite\s+8300)" -or $assetCode -in @("H3","H4","HS","H6","H7","H8")) {
   $genFamily = "HP_PRODESK_G1_G5"
   if ($resolvedModel -eq "Desktop PC") {
    $resolvedModel = switch ($assetCode) {
     "H8" { "HP ProDesk 600 G3" }
     "H6" { "HP ProDesk 600 G2" }
     "H4" { "HP ProDesk 600 G1" }
     "HS" { "HP ProDesk 600 G1" }
     "H3" { "HP Compaq Pro 6300" }
     default { "HP ProDesk Desktop" }
    }
   }
  }
 } elseif ($effVendor -eq "Dell") {
  if ($modelName -match "(?i)OptiPlex\s*(Tower|Plus|SFF|Micro)?\s*(7010|7020|5090|7090|3090|3080|5080|7080)|Dell\s+Pro\s+(Tower|Max|Slim)" -or $assetCode -eq "D8" -or $cpuName -match "i[3579]-1[2-4]\d{3}|Core\s+Ultra") {
   $genFamily = "DELL_MODERN"
   if ($resolvedModel -eq "Desktop PC") { $resolvedModel = "Dell OptiPlex / Pro Tower (D8)" }
  } elseif ($modelName -match "(?i)OptiPlex\s*(3070|5070|7070|3060|5060|7060|3050|5050|7050)" -or $assetCode -eq "D1" -or $cpuName -match "i[357]-9\d{3}") {
   $genFamily = "DELL_OPTIPLEX_70"
   if ($resolvedModel -eq "Desktop PC") { $resolvedModel = "Dell OptiPlex 3070/5070/7070 (D1)" }
  }
 }

 return [PSCustomObject]@{
  EffectiveVendor = $effVendor
  AssetCode = $assetCode
  GenFamily = $genFamily
  ModelName = $resolvedModel
 }
}

function Get-SystemInfo {
 $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
 $csp = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
 $bb = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction SilentlyContinue
 $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
 $cpuObj = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1

 $regSysMan = ""; $regSysProd = ""; $regSysFam = ""; $regBbProd = ""
 try {
  $rb = Get-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -ErrorAction Stop
  $regSysMan = [string]$rb.SystemManufacturer
  $regSysProd = [string]$rb.SystemProductName
  $regSysFam = [string]$rb.SystemFamily
  $regBbProd = [string]$rb.BaseBoardProduct
 } catch {}

 $csMan = if ($cs -and $cs.Manufacturer) { [string]$cs.Manufacturer } else { $regSysMan }
 $bbMan = [string]$bb.Manufacturer
 $biosMan = [string]$bios.Manufacturer
 $cspVen = if ($csp -and $csp.Vendor) { [string]$csp.Vendor } else { "" }
 $rawVendor = "$csMan $cspVen $bbMan $biosMan".Trim()

 $placeholderRe = "^(?i)(System Product Name|To be filled.*|Default string|All Series|Not Specified|None|OEM|Desktop|Standard PC.*)$"
 $modelCandidates = @(
  $(if ($cs) { [string]$cs.Model } else { "" }),
  $regSysProd,
  $(if ($csp) { [string]$csp.Name } else { "" }),
  $(if ($csp) { [string]$csp.Version } else { "" }),
  $(if ($cs) { [string]$cs.SystemFamily } else { $regSysFam }),
  $(if ($bb) { [string]$bb.Product } else { $regBbProd })
 )
 $modelName = "Desktop PC"
 foreach ($mc in $modelCandidates) {
  if ($mc -and $mc.Trim() -ne "" -and ($mc.Trim() -notmatch $placeholderRe)) {
   $modelName = $mc.Trim()
   break
  }
 }

 # Identify OEM vendor with priority on ComputerSystem -> Registry -> ComputerSystemProduct -> BaseBoard -> BIOS
 $vendor = "Standard"
 foreach ($src in @($csMan, $regSysMan, $cspVen, $bbMan, $biosMan, $modelName)) {
  if (-not $src) { continue }
  if ($src -match "(?i)Samsung|\bSEC\b|\bDB400T|\bDM500T") { $vendor = "Samsung"; break }
  if ($src -match "(?i)\bHP\b|Hewlett-Packard|HP Inc|\bProDesk\b|\bEliteDesk\b|\bElite\s+Tower\b") { $vendor = "HP"; break }
  if ($src -match "(?i)\bDell\b|\bOptiPlex\b") { $vendor = "Dell"; break }
 }

 $hintVendor = $vendor
 if ($vendor -eq "Standard") {
  if ($rawVendor -match "(?i)\bLenovo\b|ThinkCentre|ThinkPad") { $hintVendor = "Lenovo" }
  elseif ($rawVendor -match "(?i)\bLG\b|LG Electronics") { $hintVendor = "LG" }
  elseif ($rawVendor -match "(?i)ASUS|ASUSTeK") { $hintVendor = "ASUS" }
  elseif ($rawVendor -match "(?i)ASRock") { $hintVendor = "ASRock" }
  elseif ($rawVendor -match "(?i)Gigabyte") { $hintVendor = "Gigabyte" }
  elseif ($rawVendor -match "(?i)Micro-Star|\bMSI\b") { $hintVendor = "MSI" }
 }

 $cpuName = if ($cpuObj -and $cpuObj.Name) { ([string]$cpuObj.Name).Trim() } else { "" }
 $hospProf = Resolve-HospitalModelProfile $vendor $hintVendor $modelName $cpuName ([string]$env:COMPUTERNAME)
 if ($vendor -eq "Standard" -and $hospProf.EffectiveVendor -in @("Samsung","HP","Dell")) {
  $vendor = $hospProf.EffectiveVendor
  $hintVendor = $vendor
 }
 $modelName = $hospProf.ModelName

 $vendorBiosHint = switch ($hintVendor) {
  "HP" {
   if ($hospProf.GenFamily -eq "HP_G8_G9") {
    "HP BIOS (F10 / Boot Menu F9): Advanced -> Boot Options -> USB Storage Boot [Checked] & Fast Boot [Unchecked] / Security -> Secure Boot [Unchecked]"
   } elseif ($hospProf.GenFamily -eq "HP_PRODESK_G1_G5") {
    "HP BIOS (Esc,F10 / Boot Menu F9): Advanced -> Boot Options -> USB Storage Boot / Removable Media Boot [Enable] & Secure Boot [Disable]"
   } else {
    "HP BIOS (F10 / Boot Menu F9): Advanced -> Boot Options -> USB Storage Boot [Enable/Checked] / Fast Boot [Disable/Unchecked]"
   }
  }
  "Dell"     { "Dell BIOS (F2 / Boot Menu F12): Boot Configuration -> Enable USB Boot Support [ON] / Secure Boot [OFF] / Fastboot [Thorough]" }
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

 $displayVendor = if ($vendor -ne "Standard") {
  if ($modelName -match ("^(?i)" + [regex]::Escape($vendor) + "\b")) { "" } else { $vendor }
 } elseif ($hintVendor -ne "Standard") {
  if ($modelName -match ("^(?i)" + [regex]::Escape($hintVendor) + "\b")) { "" } else { $hintVendor }
 } else { "" }

 return [PSCustomObject]@{
  Vendor = $vendor
  HintVendor = $hintVendor
  DisplayVendor = $displayVendor
  ModelName = $modelName
  AssetCode = $hospProf.AssetCode
  GenFamily = $hospProf.GenFamily
  CpuName = $cpuName
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

# Pure helper: Parse HP WMI BIOS settings (G1~G9+: Checked/Unchecked, Enable/Disable, Available/Hidden, EN + KO names, compound SecureBoot priority)
function Resolve-HpBiosDiagnostics([array]$hpSettings, [array]$hpOrdered = @()) {
 $usbState = "Unknown"
 $usbDetail = ""
 $fastWarn = $false
 $fastDetail = ""
 $secWmi = "Unavailable"
 $secCompoundLocked = $false
 $portWarn = $false
 $portDetail = ""
 $evidence = New-Object System.Collections.ArrayList

 if ((-not $hpSettings -or $hpSettings.Count -eq 0) -and (-not $hpOrdered -or $hpOrdered.Count -eq 0)) {
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

 $reOnVal  = "^(?i)(Enable|Enabled|Yes|On|Checked|True|Available|Allow|Allowed)$|^(" + (U "\uD65C\uC131|\uD65C\uC131\uD654|\uC0AC\uC6A9|\uC0AC\uC6A9\uD568|\uC608|\uC120\uD0DD\uB428|\uCCB4\uD06C\uB428|\uCCB4\uD06C|\uD5C8\uC6A9") + ")$"
 $reOffVal = "^(?i)(Disable|Disabled|No|Off|Unchecked|False|Hidden|Deny|Denied|Block|Blocked)$|^(" + (U "\uBE44\uD65C\uC131|\uBE44\uD65C\uC131\uD654|\uC0AC\uC6A9\s*\uC548\s*\uD568|\uC544\uB2C8\uC624|\uC544\uB2C8\uC694|\uC120\uD0DD\s*\uC548\s*\uD568|\uCCB4\uD06C\s*\uD574\uC81C|\uCCB4\uD06C\uD574\uC81C\uB428|\uD574\uC81C\uB428|\uC228\uAE40|\uCC28\uB2E8") + ")$"

 $rePrimaryUsbName = "(?i)(USB\s*Storage\s*Boot|Removable\s*Media\s*Boot|USB\s*Device\s*Boot|UEFI\s*USB\s*Boot|USB\s*Flash\s*Media|Boot\s*from\s*USB|\bUSB\s*Boot\b|" + (U "USB\s*\uC800\uC7A5\uC18C\s*\uBD80\uD305|USB\s*\uC2A4\uD1A0\uB9AC\uC9C0\s*\uBD80\uD305|\uC774\uB3D9\uC2DD\s*\uBBF8\uB514\uC5B4\s*\uBD80\uD305|USB\s*\uC7A5\uCE58\s*\uBD80\uD305|USB\s*\uBD80\uD305") + ")"
 $rePrimaryExclude = "(?i)(Legacy|" + (U "\uB808\uAC70\uC2DC") + "|Charge|" + (U "\uCDA9\uC804") + "|Wake|" + (U "\uC808\uC804") + "|Security|Network|" + (U "\uB124\uD2B8\uC6CC\uD06C") + "|PXE|Optical|" + (U "\uAD11\uD559") + "|CD|DVD|Order|" + (U "\uC21C\uC11C") + ")"
 $rePortName       = "(?i)(Legacy.*USB|USB.*Legacy|USB\s*Ports?|External\s*USB|Front\s*USB|Rear\s*USB|" + (U "\uB808\uAC70\uC2DC.*USB|USB.*\uB808\uAC70\uC2DC|USB\s*\uD3EC\uD2B8|\uC678\uBD80\s*USB|\uC804\uBA74\s*USB|\uD6C4\uBA74\s*USB") + ")"
 $reFastBootName   = "^(?i)((HP\s+)?Fast\s*Boot(\s*\(.*\))?|" + (U "\uACE0\uC18D\s*\uBD80\uD305|\uBE60\uB978\s*\uBD80\uD305") + ")$"
 $reSecSimpleName  = "^(?i)(Secure\s*Boot|" + (U "\uBCF4\uC548\s*\uBD80\uD305") + ")$"
 $reSecCompName    = "^(?i)(Configure\s+Legacy\s+Support\s+and\s+Secure\s+Boot|" + (U "\uB808\uAC70\uC2DC\s*\uC9C0\uC6D0\s*\uBC0F\s*\uBCF4\uC548\s*\uBD80\uD305\s*\uAD6C\uC131") + ")$"

 $primaryEnabled = New-Object System.Collections.ArrayList
 $primaryDisabled = New-Object System.Collections.ArrayList
 $seenKeys = @{}

 foreach ($item in $hpSettings) {
  $name = if ($null -ne $item.Name) { ([string]$item.Name).Trim() } else { "" }
  if (-not $name) { continue }
  $dedupKey = $name.ToLower()
  if ($seenKeys.ContainsKey($dedupKey)) { continue }

  $curVal = if ($null -ne $item.CurrentValue) { ([string](@($item.CurrentValue) -join ",")).Trim() } else { "" }
  $valStr = if ($null -ne $item.Value) { ([string](@($item.Value) -join ",")).Trim() } else { "" }
  $activeVal = ""
  if ($curVal) {
   $activeVal = if ($curVal -match "\*([^,]+)") { $matches[1].Trim() } else { $curVal }
  } elseif ($valStr) {
   if ($valStr -match "\*([^,]+)") {
    $activeVal = $matches[1].Trim()
   } elseif ($valStr -notmatch ",") {
    $activeVal = $valStr
   }
  }
  if (-not $activeVal) { continue }
  $seenKeys[$dedupKey] = $true

  # 1) Primary UEFI USB Boot settings (supports Checked/Unchecked on G8/G9 + Enable/Disable on G1~G7 + KO BIOS)
  if (($name -match $rePrimaryUsbName) -and ($name -notmatch $rePrimaryExclude)) {
   [void]$evidence.Add(("HP Primary USB: " + $name + " = " + $activeVal))
   if ($activeVal -match $reOffVal) {
    [void]$primaryDisabled.Add(($name + "=" + $activeVal))
   } elseif ($activeVal -match $reOnVal) {
    [void]$primaryEnabled.Add(($name + "=" + $activeVal))
   }
  }
  # 2) Secondary Legacy USB / USB Port settings (Legacy Disable never overrides UEFI Enable!)
  elseif ($name -match $rePortName) {
   [void]$evidence.Add(("HP Secondary USB/Port: " + $name + " = " + $activeVal))
   if (($name -notmatch "(?i)Legacy|" + (U "\uB808\uAC70\uC2DC")) -and ($activeVal -match $reOffVal)) {
    $portWarn = $true
    $portDetail = "HP WMI: " + $name + " = " + $activeVal
   }
  }

  # 3) Fast Boot (exclude Memory/SATA Fast Boot)
  if (($name -match $reFastBootName) -and ($name -notmatch "(?i)Memory|SATA")) {
   [void]$evidence.Add(("HP Fast Boot: " + $name + " = " + $activeVal))
   if ($activeVal -match $reOnVal) {
    $fastWarn = $true
    $fastDetail = "HP WMI: " + $name + " = " + $activeVal
   }
  }

  # 4) Secure Boot WMI cross-check signal (Compound Legacy+SecureBoot on G1~G5 has strict priority over grayed-out standalone Secure Boot!)
  if ($name -match $reSecCompName) {
   [void]$evidence.Add(("HP Secure Boot (Compound): " + $name + " = " + $activeVal))
   if ($activeVal -match "(?i)Secure\s*Boot\s*Disable|Legacy\s*Support\s*Enable" -or $activeVal -match (U "\uBCF4\uC548\s*\uBD80\uD305\s*(\uBE44\uD65C\uC131|\uC0AC\uC6A9\s*\uC548\s*\uD568)")) {
    $secWmi = "Off"
    $secCompoundLocked = $true
   } elseif ($activeVal -match "(?i)Secure\s*Boot\s*Enable" -or $activeVal -match (U "\uBCF4\uC548\s*\uBD80\uD305\s*(\uD65C\uC131|\uC0AC\uC6A9)")) {
    $secWmi = "On"
    $secCompoundLocked = $true
   }
  } elseif (-not $secCompoundLocked -and ($name -match $reSecSimpleName)) {
   [void]$evidence.Add(("HP Secure Boot: " + $name + " = " + $activeVal))
   if ($activeVal -match $reOnVal -or $activeVal -match "(?i)Secure\s*Boot\s*Enable") { $secWmi = "On" }
   elseif ($activeVal -match $reOffVal -or $activeVal -match "(?i)Secure\s*Boot\s*Disable") { $secWmi = "Off" }
  }
 }

 # 5) Also inspect HP_BIOSOrderedList (UEFI Boot Order) when available for supplementary visibility
 $orderedHasUsb = $false
 foreach ($ol in $hpOrdered) {
  $oName = if ($null -ne $ol.Name) { ([string]$ol.Name).Trim() } else { "" }
  $oVal = if ($null -ne $ol.Value) { ([string](@($ol.Value) -join ",")).Trim() } else { "" }
  if ($oName -match "(?i)UEFI\s*Boot\s*Order|^Boot\s*Order$|" + (U "\uBD80\uD305\s*\uC21C\uC11C")) {
   [void]$evidence.Add(("HP Boot Order (" + $oName + "): " + $oVal))
   if ($oVal -match "(?i)\bUSB\b") { $orderedHasUsb = $true }
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
 } elseif ($orderedHasUsb) {
  $usbState = "Enabled"
  $usbDetail = "HP WMI UEFI Boot Order: USB included"
 } else {
  $usbState = "UnverifiableHP"
  $usbDetail = ((U "HP WMI \uC5F0\uACB0\uB428 / USB Boot \uD56D\uBAA9 \uBBF8\uBC1C\uACAC (") + $seenKeys.Count + (U "\uAC1C \uC124\uC815 \uC2A4\uCE94)"))
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

# Helper: Type-safe Dell CurrentValue / AttributeValue -> PossibleValuesDescription lookup
function Resolve-DellEnumValue($item) {
 $raw = ""
 if ($null -ne $item.CurrentValue) {
  $raw = (@($item.CurrentValue) -join ",").Trim()
 } elseif ($null -ne $item.AttributeValue) {
  $raw = (@($item.AttributeValue) -join ",").Trim()
 } elseif ($null -ne $item.Value) {
  $raw = (@($item.Value) -join ",").Trim()
 }
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

# Pure helper: Parse Dell WMI BIOS settings (OptiPlex D1 3070/5070/7070 & D8 7010/7020/Pro Tower, DCM + native biosattributes)
function Resolve-DellBiosDiagnostics([array]$dellSettings) {
 $usbState = "Unknown"
 $usbDetail = ""
 $fastWarn = $false
 $fastDetail = ""
 $fastMode = ""
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
   FastBootMode = ""
   SecureBootWmi = "Unavailable"
   PortWarn = $false
   PortDetail = ""
   Evidence = @($evidence)
  }
 }

 $primaryEnabled = New-Object System.Collections.ArrayList
 $primaryDisabled = New-Object System.Collections.ArrayList
 $seenAttrs = @{}

 foreach ($item in $dellSettings) {
  $name = if ($null -ne $item.AttributeName) { ([string]$item.AttributeName).Trim() } elseif ($null -ne $item.Name) { ([string]$item.Name).Trim() } else { "" }
  if (-not $name) { continue }
  $aKey = $name.ToLower()
  if ($seenAttrs.ContainsKey($aKey)) { continue }
  $val = Resolve-DellEnumValue $item
  if (-not $val) { continue }
  $seenAttrs[$aKey] = $true

  # 1) Primary USB Boot settings (supports EnableUsbBootSupport, UsbBoot, ExternalUsbBoot, EnableBootSupport; excludes Wake/PowerShare/Legacy)
  if (($name -match "(?i)^(EnableUsbBootSupport|UsbBootSupport|UsbBoot|BootUsb|ExternalUsbBoot|EnableExternalUsbBoot|UsbStorageBoot|UsbPortsBoot)$") -and
      ($name -notmatch "(?i)Wake|PowerShare|Legacy")) {
   [void]$evidence.Add(("Dell Primary USB: " + $name + " = " + $val))
   if ($val -match "(?i)^(Disable|Disabled|Off|None|No|False|DisableUsbBoot)$|Disable") {
    [void]$primaryDisabled.Add(($name + "=" + $val))
   } elseif ($val -match "(?i)^(Enable|Enabled|On|All|AllEnable|Yes|True|EnableUsbBoot)$|Enable") {
    [void]$primaryEnabled.Add(($name + "=" + $val))
   }
  }
  # 2) External USB Port controls (OnlyBackPortsOn is partial rear-only, not total block; AllDisable/Disabled/Off is PortWarn)
  elseif ($name -match "(?i)^(UsbPortsExternal|ExternalUsbPorts|ExternalUsb|FrontUsb|RearUsb|UsbPorts)$") {
   [void]$evidence.Add(("Dell USB Port: " + $name + " = " + $val))
   if (($name -notmatch "(?i)^FrontUsb") -and ($val -match "(?i)^(Disable|Disabled|Off|None|AllDisable|DisableAllPorts)$")) {
    $portWarn = $true
    $portDetail = "Dell WMI: " + $name + " = " + $val
   }
  }

  # 3) Fastboot (Minimal skips USB init during POST; Auto may skip USB init on warm reboot)
  if ($name -match "(?i)^Fastboot$") {
   [void]$evidence.Add(("Dell Fastboot: " + $name + " = " + $val))
   $fastMode = $val
   if ($val -match "(?i)Minimal") {
    $fastWarn = $true
    $fastDetail = "Dell WMI: Fastboot = " + $val
   }
  }

  # 4) SecureBoot WMI cross-check signal (SecureBoot / SecBoot / SecureBootEnable)
  if ($name -match "(?i)^(SecureBoot|SecBoot|SecureBootEnable)$") {
   [void]$evidence.Add(("Dell SecureBoot: " + $name + " = " + $val))
   if ($val -match "(?i)Enable|On|True") { $secWmi = "On" }
   elseif ($val -match "(?i)Disable|Off|False") { $secWmi = "Off" }
  }

  # 5) UEFI Boot Path Security (informational evidence on OptiPlex D1/D8)
  if ($name -match "(?i)^UefiBootPathSecurity$") {
   [void]$evidence.Add(("Dell BootPathSecurity: " + $name + " = " + $val))
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
  $usbDetail = ((U "Dell WMI \uC5F0\uACB0\uB428 / USB Boot \uD56D\uBAA9 \uBBF8\uBC1C\uACAC (") + $seenAttrs.Count + (U "\uAC1C \uC124\uC815 \uC2A4\uCE94)"))
 }

 return [PSCustomObject]@{
  UsbState = $usbState
  UsbDetail = $usbDetail
  FastBootWarn = $fastWarn
  FastBootDetail = $fastDetail
  FastBootMode = $fastMode
  SecureBootWmi = $secWmi
  PortWarn = $portWarn
  PortDetail = $portDetail
  Evidence = @($evidence)
 }
}

# Pure helper: Parse Lenovo WMI BIOS settings (root\WMI:Lenovo_BiosSetting, "Name,Value;...")
function Resolve-LenovoBiosDiagnostics([array]$lenovoSettings) {
 $usbState = "Unknown"
 $usbDetail = ""
 $fastWarn = $false
 $fastDetail = ""
 $secWmi = "Unavailable"
 $evidence = New-Object System.Collections.ArrayList
 $primaryEnabled = New-Object System.Collections.ArrayList
 $primaryDisabled = New-Object System.Collections.ArrayList

 foreach ($item in $lenovoSettings) {
  $cs = if ($null -ne $item.CurrentSetting) { ([string]$item.CurrentSetting).Trim() } else { "" }
  if (-not $cs -or $cs -notmatch "^([^,]+),([^,;]+)") { continue }
  $name = $matches[1].Trim()
  $val = $matches[2].Trim()
  if (-not $name -or -not $val) { continue }
  if ($name -match "(?i)^(USB\s*Boot|USB\s*Boot\s*Support|Boot\s*from\s*USB)$") {
   [void]$evidence.Add(("Lenovo USB: " + $name + " = " + $val))
   if ($val -match "(?i)^(Disable|Disabled|Off|No)$") { [void]$primaryDisabled.Add(($name + "=" + $val)) }
   elseif ($val -match "(?i)^(Enable|Enabled|On|Yes)$") { [void]$primaryEnabled.Add(($name + "=" + $val)) }
  } elseif ($name -match "(?i)^(Quick\s*Boot|Fast\s*Boot)$") {
   [void]$evidence.Add(("Lenovo FastBoot: " + $name + " = " + $val))
   if ($val -match "(?i)^(Enable|Enabled|On|Yes)$") { $fastWarn = $true; $fastDetail = "Lenovo WMI: " + $name + " = " + $val }
  } elseif ($name -match "(?i)^Secure\s*Boot$") {
   [void]$evidence.Add(("Lenovo SecureBoot: " + $name + " = " + $val))
   if ($val -match "(?i)^(Enable|Enabled|On|Yes)$") { $secWmi = "On" }
   elseif ($val -match "(?i)^(Disable|Disabled|Off|No)$") { $secWmi = "Off" }
  }
 }
 if ($primaryDisabled.Count -gt 0) { $usbState = "Disabled"; $usbDetail = "Lenovo WMI: " + ($primaryDisabled -join "; ") }
 elseif ($primaryEnabled.Count -gt 0) { $usbState = "Enabled"; $usbDetail = "Lenovo WMI: " + ($primaryEnabled -join "; ") }
 return [PSCustomObject]@{
  UsbState = $usbState; UsbDetail = $usbDetail; FastBootWarn = $fastWarn; FastBootDetail = $fastDetail; SecureBootWmi = $secWmi; Evidence = @($evidence)
 }
}

# Pure helper: Multi-signal Secure Boot cross-verification (UEFI API + Kernel Registry + DeviceGuard + Vendor WMI)
function Resolve-SecureBootCrossCheck([string]$apiSignal, [string]$regSignal, [string]$wmiSignal, [string]$dgSignal = "Unavailable", [bool]$isLegacyMode = $false) {
 $signals = New-Object System.Collections.ArrayList
 [void]$signals.Add(("Confirm-SecureBootUEFI = " + $apiSignal))
 [void]$signals.Add(("Registry UEFISecureBootEnabled = " + $regSignal))
 if ($dgSignal -and $dgSignal -ne "Unavailable") {
  [void]$signals.Add(("Win32_DeviceGuard SecureBoot = " + $dgSignal))
 }
 if ($wmiSignal -and $wmiSignal -ne "Unavailable") {
  [void]$signals.Add(("Vendor WMI SecureBoot = " + $wmiSignal))
 }

 $onCount = 0
 $offCount = 0
 foreach ($s in @($apiSignal, $regSignal, $dgSignal, $wmiSignal)) {
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
 } elseif ($isLegacyMode) {
  $state = "Off"
  $confidence = "LegacyNotSupported"
  [void]$signals.Add("Legacy MBR BootMode -> SecureBoot Not Applicable (Off)")
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
   if ($matchedNvramCount -gt 0 -or $nvramHasStrictUsb) {
    $finalState = "UnverifiableAMI"
    $confidence = "NvramObserved"
    $summary = U "Samsung/AMI WMI \uBBF8\uC9C0\uC6D0 (\uD655\uC778 \uBD88\uAC00) / NVRAM USB \uBD80\uD305 \uD56D\uBAA9 \uAD00\uCE21\uB428"
   } elseif ($physicalUsbCount -gt 0) {
    $finalState = "SuspectedDisabled"
    $confidence = "Suspected"
    $summary = U "Samsung/AMI USB \uC7A5\uCC29\uB428 / NVRAM \uBBF8\uB4F1\uB85D (Hot-Plug \uB610\uB294 Fast BIOS Mode / USB \uCC28\uB2E8 \uAC00\uB2A5)"
   } else {
    $finalState = "UnverifiableAMI"
    $confidence = "Unverifiable"
    $summary = U "Samsung/AMI BIOS WMI \uBBF8\uC9C0\uC6D0 - F2 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
   }
  } elseif ($wmiState -in @("UnverifiableHP","UnverifiableDell")) {
   $finalState = $wmiState
   if ($matchedNvramCount -gt 0 -or $nvramHasStrictUsb) {
    $confidence = "NvramObserved"
    $summary = $wmiDetail + (U " / NVRAM USB \uD56D\uBAA9 \uAD00\uCE21\uB428")
   } elseif ($physicalUsbCount -gt 0) {
    $finalState = "SuspectedDisabled"
    $confidence = "Suspected"
    $summary = $wmiDetail + (U " / USB \uC7A5\uCC29\uB428 \u00B7 NVRAM \uBBF8\uB4F1\uB85D")
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
 $excludeDescPattern = "(?i)(Windows Boot Manager|" + [regex]::Escape($koBootMgr) + "|Hard Drive \(SATA|Hard Drive \(NVMe|PXE|IPV4|IPV6|IP4|IP6|HTTPs?\s*Boot|Network|Onboard NIC|SupportAssist|Sure\s*Recover|BIOS\s*Connect|Firmware\s*Update)"

 # Build dynamic USB model hints from connected USB disks so enclosures like 'HSEN 10G-NVME' or 'JMicron Generic SATA' are never dropped!
 $connectedUsbHints = New-Object System.Collections.ArrayList
 foreach ($ud in $usbDisks) {
  if ($ud -and $ud.FriendlyName) {
   $cn = (([string]$ud.FriendlyName) -replace "(?i)\s+(SCSI|USB|SATA|NVMe|ATA)?\s*Disk\s+Device$", "").Trim()
   if ($cn.Length -ge 3) { [void]$connectedUsbHints.Add([regex]::Escape($cn)) }
  }
 }
 $usbHintRe = if ($connectedUsbHints.Count -gt 0) { ($connectedUsbHints | Select-Object -Unique) -join "|" } else { "" }

 # Strict NVRAM USB check (excludes internal SATA/NVMe unless explicitly USB or matching connected USB enclosure)
 $nvramUsbEntries = @(
  $bcdEntries | Where-Object {
   $desc = [string]$_.Description
   $matchesConnUsb = ($usbHintRe -and ($desc -match $usbHintRe))
   $isInternalBusOnly = (-not $matchesConnUsb) -and ($desc -match "(?i)\b(SATA\d*|NVMe\d*)\b") -and ($desc -notmatch "(?i)\bUSB\b|External|Removable")
   $_.Identifier -ne "{fwbootmgr}" -and $_.Identifier -ne "{bootmgr}" -and
   ($desc -notmatch $excludeDescPattern) -and
   (-not $isInternalBusOnly) -and
   ($matchesConnUsb -or ($desc -match "(?i)\bUSB\b|Removable|External|Flash|SanDisk|Ventoy|Phoenix|RTL9210|JMicron|HSEN|FireCuda|ADATA|Kingston|JetFlash|PMAP|UDisk"))
  }
 )
 $nvramHasStrictUsbEntry = ($nvramUsbEntries.Count -gt 0)
 $effectiveMatchCount = if ($matchedNvramCount -ge 0) { $matchedNvramCount } else { $nvramUsbEntries.Count }

 $bootModeDiag = Get-BootModeDiagnostics
 $evidence = New-Object System.Collections.ArrayList
 foreach ($bs in $bootModeDiag.Signals) { [void]$evidence.Add(("BootMode: " + $bs)) }

 # Query vendor WMI (HP: HP_BIOSSetting + HP_BIOSEnumeration + HPBIOS_BIOSEnumeration + HP_BIOSOrderedList | Dell: DCIM_BIOSEnumeration + biosattributes | Lenovo: Lenovo_BiosSetting)
 $wmiState = "Unknown"
 $wmiDetail = ""
 $fastBootWarn = $false
 $fastBootDetail = ""
 $secWmiSignal = "Unavailable"
 $portWarn = $false
 $portDetail = ""

 if ($vendor -eq "HP") {
  $hpRaw = @()
  $hpOrdered = @()
  foreach ($hpCls in @("HP_BIOSSetting", "HP_BIOSEnumeration", "HPBIOS_BIOSEnumeration")) {
   try {
    $resCls = @(Get-CimInstance -Namespace "root\HP\InstrumentedBIOS" -ClassName $hpCls -ErrorAction Stop)
    if ($resCls.Count -gt 0) { $hpRaw += $resCls }
   } catch {}
  }
  try {
   $hpOrdered = @(Get-CimInstance -Namespace "root\HP\InstrumentedBIOS" -ClassName "HP_BIOSOrderedList" -ErrorAction Stop)
  } catch {}

  if ($hpRaw.Count -gt 0 -or $hpOrdered.Count -gt 0) {
   $hpRes = Resolve-HpBiosDiagnostics $hpRaw $hpOrdered
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
   [void]$evidence.Add("HP WMI: root\HP\InstrumentedBIOS unavailable or access denied")
  }
 } elseif ($vendor -eq "Dell") {
  $dellRaw = @()
  try {
   $dellRaw += @(Get-CimInstance -Namespace "root\dcim\sysman" -ClassName "DCIM_BIOSEnumeration" -ErrorAction Stop)
  } catch {}
  try {
   $dellRaw += @(Get-CimInstance -Namespace "root\dcim\sysman\biosattributes" -ClassName "EnumerationAttribute" -ErrorAction Stop)
  } catch {}

  if ($dellRaw.Count -gt 0) {
   $dellRes = Resolve-DellBiosDiagnostics $dellRaw
   $wmiState = $dellRes.UsbState
   $wmiDetail = $dellRes.UsbDetail
   $fastBootWarn = $dellRes.FastBootWarn
   $fastBootDetail = $dellRes.FastBootDetail
   if (-not $fastBootWarn -and $dellRes.FastBootMode -match "(?i)^Auto$" -and $usbDisks.Count -gt 0 -and $effectiveMatchCount -eq 0) {
    $fastBootWarn = $true
    $fastBootDetail = "Dell WMI: Fastboot = Auto (Thorough recommended for USB POST init)"
   }
   $secWmiSignal = $dellRes.SecureBootWmi
   $portWarn = $dellRes.PortWarn
   $portDetail = $dellRes.PortDetail
   foreach ($ev in $dellRes.Evidence) { [void]$evidence.Add($ev) }
  } else {
   $wmiState = "UnverifiableDell"
   $wmiDetail = U "Dell WMI \uBBF8\uC9C0\uC6D0(DCM/BIOS WMI \uC5C6\uC74C) - F2 BIOS\uC5D0\uC11C \uC9C1\uC811 \uD655\uC778 \uD544\uC694"
   [void]$evidence.Add("Dell WMI: root\dcim\sysman and biosattributes unavailable")
  }
 } elseif ($sysInfo.HintVendor -eq "Lenovo") {
  $lenRaw = @()
  try {
   $lenRaw = @(Get-CimInstance -Namespace "root\WMI" -ClassName "Lenovo_BiosSetting" -ErrorAction Stop)
  } catch {}
  if ($lenRaw.Count -gt 0) {
   $lenRes = Resolve-LenovoBiosDiagnostics $lenRaw
   if ($lenRes.UsbState -ne "Unknown") { $wmiState = $lenRes.UsbState; $wmiDetail = $lenRes.UsbDetail }
   $fastBootWarn = $lenRes.FastBootWarn; $fastBootDetail = $lenRes.FastBootDetail; $secWmiSignal = $lenRes.SecureBootWmi
   foreach ($ev in $lenRes.Evidence) { [void]$evidence.Add($ev) }
  } else {
   [void]$evidence.Add("Vendor WMI: Lenovo_BiosSetting unavailable")
  }
 } else {
  [void]$evidence.Add(("Vendor WMI: " + $vendor + " (BIOS WMI unsupported - conservative mode)"))
 }

 # 4-signal Secure Boot cross-check (Confirm-SecureBootUEFI + Kernel Registry + Win32_DeviceGuard + Vendor WMI)
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
 $secDg = "Unavailable"
 if ($bootModeDiag.IsUefi) {
  try {
   $dg = Get-CimInstance -Namespace "root\Microsoft\Windows\DeviceGuard" -ClassName "Win32_DeviceGuard" -ErrorAction Stop | Select-Object -First 1
   if ($dg -and $dg.AvailableSecurityProperties) {
    $props = @($dg.AvailableSecurityProperties | ForEach-Object { [int]$_ })
    if ($props -contains 2) { $secDg = "On" }
    elseif ($props.Count -gt 0 -and ($props -notcontains 0)) { $secDg = "Off" }
   }
  } catch {}
 }

 $isLegMode = ($bootModeDiag.Mode -eq "Legacy")
 $secDiag = Resolve-SecureBootCrossCheck $secApi $secReg $secWmiSignal $secDg $isLegMode
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
 $codeSuffix = if ($sysInfo.PSObject.Properties["AssetCode"] -and $sysInfo.AssetCode) { " (Code: " + $sysInfo.AssetCode + ")" } else { "" }
 [void]$sb.AppendLine(("System       : [" + $sysInfo.Vendor + "] " + $sysInfo.ModelName + $codeSuffix))
 if ($sysInfo.PSObject.Properties["CpuName"] -and $sysInfo.CpuName) { [void]$sb.AppendLine(("CPU          : " + $sysInfo.CpuName)) }
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
 if ($diag.IsConfirmedBlocked) {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "BIOS\uC5D0\uC11C USB \uBD80\uD305\uC774 \uCC28\uB2E8\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4"
   Message = U "\uC544\uB798 BIOS \uC124\uC815 \uC5F4\uAE30\uB97C \uB20C\uB7EC USB \uBD80\uD305 \uC635\uC158\uC744 \uD5C8\uC6A9\uC73C\uB85C \uBCC0\uACBD\uD55C \uB4A4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694."
   RecommendedAction = "BIOS_SETUP"
  }
 }
 if (-not $usbInfo -or $usbInfo.PhysicalUsbList.Count -eq 0) {
  $sbExtra = if ($diag.SecureBootState -eq "On") { U " \uBE44\uC11C\uBA85 WinPE\uB97C \uC0AC\uC6A9\uD55C\uB2E4\uBA74 BIOS\uC5D0\uC11C \uBCF4\uC548 \uBD80\uD305\uB3C4 \uD568\uAED8 \uD655\uC778\uD574 \uC8FC\uC138\uC694." } else { "" }
  return [PSCustomObject]@{
   Level = "Info"
   Title = U "WinPE \uBD80\uD305 USB\uB97C \uC5F0\uACB0\uD574 \uC8FC\uC138\uC694"
   Message = (U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C \uC810\uAC80\uC744 \uD1B5\uACFC\uD588\uC2B5\uB2C8\uB2E4. WinPE USB\uB97C PC\uC5D0 \uAF42\uC740 \uB4A4 USB \uB2E4\uC2DC \uCC3E\uAE30\uB97C \uB20C\uB7EC \uC8FC\uC138\uC694.") + $sbExtra
   RecommendedAction = "PLUG_USB"
  }
 }
 if ($matchedEntries -and $matchedEntries.Count -gt 0) {
  $hasVentoyUsb = ($null -ne $usbInfo.PSObject.Properties["IsVentoy"] -and [bool]$usbInfo.IsVentoy) -or (($matchedEntries | Where-Object { [string]$_.Description -match "(?i)Ventoy" }).Count -gt 0)
  if ($diag.SecureBootState -eq "On" -and $hasVentoyUsb) {
   return [PSCustomObject]@{
    Level = "Warn"
    Title = U "Ventoy \uBD80\uD305 \uB514\uC2A4\uD06C\uB294 \uBCF4\uC548 \uBD80\uD305 \uD574\uC81C\uAC00 \uD544\uC694\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4"
    Message = U "\uBCF4\uC548 \uBD80\uD305\uC774 \uCF1C\uC838 \uC788\uC5B4 Ventoy \uBD80\uD305\uC774 \uCC28\uB2E8\uB420 \uC218 \uC788\uC2B5\uB2C8\uB2E4. BIOS \uC124\uC815 \uC5F4\uAE30\uB85C \uBCF4\uC548 \uBD80\uD305\uC744 \uB044\uAC70\uB098 \uC544\uB798 USB \uC7AC\uBD80\uD305\uC744 \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694."
    RecommendedAction = "BIOS_SETUP"
   }
  }
  if ($diag.SecureBootState -in @("On","Conflict")) {
   return [PSCustomObject]@{
    Level = "Warn"
    Title = U "WinPE USB \uBD80\uD305 \uC900\uBE44 \uC644\uB8CC \u00B7 \uBCF4\uC548 \uBD80\uD305 \uCF1C\uC9D0"
    Message = U "\uD45C\uC900 Windows PE\uB294 \uBC14\uB85C \uC120\uD0DD\uD55C USB\uB85C \uC7AC\uBD80\uD305\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uBE44\uC11C\uBA85 USB\uB77C \uBD80\uD305\uC774 \uCC28\uB2E8\uB420 \uB54C\uB9CC BIOS \uC124\uC815 \uC5F4\uAE30\uC5D0\uC11C \uBCF4\uC548 \uBD80\uD305\uC744 \uD574\uC81C\uD574 \uC8FC\uC138\uC694."
    RecommendedAction = "USB_REBOOT"
   }
  }
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
 $hasAnyEfiProp = ($null -ne $usbInfo.PSObject.Properties["AnyEfiReadyUsb"])
 $efiReadyUsb = if ($hasAnyEfiProp) { [bool]$usbInfo.AnyEfiReadyUsb } else { $true }
 if (-not $efiReadyUsb) {
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "\uC5F0\uACB0\uB41C USB\uC5D0\uC11C UEFI \uBD80\uD305 \uD30C\uC77C\uC774 \uD655\uC778\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4"
   Message = U "\uC77C\uBC18 \uB370\uC774\uD130 USB\uC774\uAC70\uB098 \uC228\uAE40 \uD30C\uD2F0\uC158\uC77C \uC218 \uC788\uC2B5\uB2C8\uB2E4. WinPE \uBD80\uD305 USB\uAC00 \uB9DE\uB2E4\uBA74 \uC544\uB798 \uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9\uC744 \uB20C\uB7EC \uC8FC\uC138\uC694."
   RecommendedAction = "ADV_BOOT"
  }
 }

 if ($diag.FastBootWarn) {
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "\uBE60\uB978 \uBD80\uD305 \uB610\uB294 Windows \uC2E4\uD589 \uC911 \uC5F0\uACB0\uB85C \uD38C\uC6E8\uC5B4 \uBAA9\uB85D \uAC31\uC2E0 \uC804\uC785\uB2C8\uB2E4"
   Message = U "\uBC29\uAE08 \uAF42\uC740 \uBD80\uD305 \uB514\uC2A4\uD06C\uB77C\uBA74 \uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9\uC744 \uB20C\uB7EC \uC8FC\uC138\uC694. \uB2E4\uC74C\uC5D0\uB3C4 \uC778\uC2DD\uB418\uC9C0 \uC54A\uC73C\uBA74 BIOS \uC124\uC815 \uC5F4\uAE30\uC5D0\uC11C \uBE60\uB978 \uBD80\uD305\uC744 \uD574\uC81C\uD574 \uC8FC\uC138\uC694."
   RecommendedAction = "ADV_BOOT"
  }
 }

 return [PSCustomObject]@{
  Level = "Info"
  Title = U "\uBD80\uD305 \uB514\uC2A4\uD06C\uAC00 \uC778\uC2DD\uB418\uC5C8\uC2B5\uB2C8\uB2E4 \u00B7 \uACE0\uAE09 \uBD80\uD305\uC5D0\uC11C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694"
  Message = U "Windows \uC2E4\uD589 \uC911 \uC5F0\uACB0\uB41C USB\uB294 \uD38C\uC6E8\uC5B4 \uBAA9\uB85D \uAC31\uC2E0 \uC804\uC774\uBBC0\uB85C \uC544\uB798 \uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9\uC744 \uB20C\uB7EC \uC7A5\uCE58 \uC0AC\uC6A9 \uBA54\uB274\uC5D0\uC11C USB\uB97C \uACE8\uB77C \uC8FC\uC138\uC694."
  RecommendedAction = "ADV_BOOT"
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
function Invoke-Gate1Check($diag, [array]$bcdOutput, [int]$matchedCount = 0, [bool]$isVentoy = $false) {
 if (-not ($diag.SecureBoot -or $diag.IsConfirmedBlocked)) {
  return "CONTINUE"
 }
 # Standard Microsoft-signed WinPE can boot with Secure Boot ON when USB is already matched in NVRAM (unless Ventoy)
 if (-not $diag.IsConfirmedBlocked -and $diag.SecureBootState -eq "On" -and $matchedCount -gt 0 -and -not $isVentoy) {
  Write-Host (U "`n [\uC548\uB0B4] Secure Boot\uAC00 \uCF1C\uC838 \uC788\uC73C\uB098 \uD45C\uC900 \uC11C\uBA85 WinPE\uB294 \uBC14\uB85C \uBD80\uD305\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4 (\uBE44\uC11C\uBA85 USB \uCC28\uB2E8 \uC2DC [B] BIOS \uC124\uC815 \uC0AC\uC6A9).") -ForegroundColor Yellow
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
