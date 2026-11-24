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
