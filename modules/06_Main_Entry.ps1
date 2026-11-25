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
    $diskLbl = if ($null -ne $rep.BootDisk) { "Disk " + $rep.BootDisk } else { $env:SystemDrive }
    $regYn = (Read-Host ((U "\uD604\uC7AC OS SSD(") + $diskLbl + (U ")\uB97C UEFI NVRAM 1\uC21C\uC704\uB85C \uB4F1\uB85D(bcdboot)\uD560\uAE4C\uC694? (Y/N)"))).Trim()
    if ($regYn -match "^[yY]$") {
     $bbRes = Invoke-NativeOem "bcdboot.exe" ('"' + $env:SystemRoot + '" /f UEFI')
     $bbRes.Lines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
     if ($bbRes.ExitCode -eq 0) {
      Write-Host (U " [\uC131\uACF5] UEFI NVRAM \uBD80\uD305 \uD56D\uBAA9 \uB4F1\uB85D(bcdboot) \uC644\uB8CC!") -ForegroundColor Green
     } else {
      Write-Host ((U " [\uACBD\uACE0] bcdboot \uB4F1\uB85D \uC2E4\uD328 (ExitCode=") + $bbRes.ExitCode + ")") -ForegroundColor Red
     }
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
  if ($env:SID_TOOL_STAGED -eq "1" -or ($env:SELF_PATH -and $env:SELF_PATH.StartsWith("\\"))) {
   Write-Host (U " [\uC548\uB0B4] \uACF5\uC720\uD3F4\uB354/\uB124\uD2B8\uC6CC\uD06C \uACBD\uB85C\uC5D0\uC11C \uC2E4\uD589\uB428 -> \uB85C\uCEEC \uBA54\uBAA8\uB9AC \uB85C\uB4DC \uC644\uB8CC (\uC6D0\uBCF8 \uBB34\uBCC0\uACBD)") -ForegroundColor DarkGray
  }
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
