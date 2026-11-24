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
