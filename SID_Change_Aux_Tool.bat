<# :
@echo off
set "SELF_PATH=%~f0"
set "SELF_ARG1=%~1"
cd /d "%SystemRoot%\System32"

if /i "%SystemDrive%"=="X:" goto :RUN_ELEVATED
net session >nul 2>&1
if %errorlevel% equ 0 goto :RUN_ELEVATED
fltmc >nul 2>&1
if %errorlevel% equ 0 goto :RUN_ELEVATED

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:SELF_PATH;$a1=[string]$env:SELF_ARG1;$staged=$null;try{$isNet=$p.StartsWith('\\');if(-not $isNet){try{$rt=[IO.Path]::GetPathRoot($p);if($rt -and ([IO.DriveInfo]$rt).DriveType -eq 'Network'){$isNet=$true}}catch{}};$target=$p;if($isNet){$bytes=[IO.File]::ReadAllBytes($p);$dirs=@($env:TEMP,(Join-Path $env:LOCALAPPDATA 'Temp'),(Join-Path $env:PUBLIC 'Documents'))|Where-Object{$_ -and (Test-Path -LiteralPath $_)};foreach($d in $dirs){try{$rt2=[IO.Path]::GetPathRoot($d);if($rt2 -and ([IO.DriveInfo]$rt2).DriveType -eq 'Network'){continue};$cand=Join-Path $d ('SID_Aux_Stage_'+[guid]::NewGuid().ToString('N')+'.tmp');[IO.File]::WriteAllBytes($cand,$bytes);$staged=$cand;break}catch{}};if(-not $staged){throw 'Cannot stage script from network share to a local temp folder.'};$target=$staged};$q=[string][char]39;$eT=$target.Replace($q,$q+$q);$eO=$p.Replace($q,$q+$q);$eA=$a1.Replace($q,$q+$q);$stFlag=if($staged){'1'}else{'0'};$del=if($staged){'Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue'}else{''};$run='$p='+$q+$eT+$q+';$env:SELF_PATH='+$q+$eO+$q+';$env:SELF_ARG1='+$q+$eA+$q+';$env:SID_TOOL_STAGED='+$q+$stFlag+$q+';Set-Location (Join-Path $env:SystemRoot '+$q+'System32'+$q+');try{try{$c=[IO.File]::ReadAllText($p,[Text.Encoding]::ASCII)}finally{'+$del+'};Invoke-Expression $c}catch{Write-Host ('+$q+'[FATAL] '+$q+'+$_.Exception.Message) -ForegroundColor Red;Read-Host '+$q+'Press Enter to exit'+$q+'|Out-Null}';$b64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($run));$psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';Start-Process -FilePath $psExe -ArgumentList @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$b64) -Verb RunAs}catch{if($staged){Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue};$ex=$_.Exception;$w32=if($ex -is [System.ComponentModel.Win32Exception]){$ex}elseif($ex.InnerException -is [System.ComponentModel.Win32Exception]){$ex.InnerException}else{$null};if($w32 -and $w32.NativeErrorCode -eq 1223){exit 0};Write-Host ('[UAC/LAUNCH ERROR] '+$ex.Message) -ForegroundColor Red;Read-Host 'Press Enter to exit'|Out-Null;exit 1}"
exit /b

:RUN_ELEVATED
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -NoProfile -ExecutionPolicy Bypass -Command "try{$c=[System.IO.File]::ReadAllText($env:SELF_PATH,[System.Text.Encoding]::ASCII);Invoke-Expression $c}catch{Write-Host ('[FATAL] '+$_.Exception.Message) -ForegroundColor Red;Read-Host 'Press Enter to exit'|Out-Null;exit 1}"
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
$script:ToolVersion = "2.1.1"
$script:BuildDate = "2026-11-26"
$script:BuildCommit = "c777d81"
$gptEfiGuid = "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
$gptRecoveryGuid = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
$gptMsrGuid = "{e3c9e316-0b5c-4db8-817d-f92df00215ae}"
$mbrEfiFatTypes = @(1, 4, 6, 11, 12, 14, 239)

# Resolve system OEM encoding (CP949 on Korean Windows, CP437 on EN-US, 65001 if UTF-8 beta)
function Get-SystemOemEncoding {
 try {
  $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
  if ($cp -gt 0) { return [System.Text.Encoding]::GetEncoding($cp) }
 } catch {}
 return [System.Text.Encoding]::Default
}

# Run native console commands (bcdedit, diskpart, bcdboot, shutdown) safely with OEM decoding & timeout
function Invoke-NativeOem([string]$fileName, [string]$arguments = "", [string]$stdinText = $null, [int]$timeoutMs = 30000) {
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

 $resolvedExe = $fileName
 if ($fileName -and ($fileName -notmatch "[\\/]")) {
  $sysCand = Join-Path (Join-Path $env:SystemRoot "System32") $fileName
  if (Test-Path -LiteralPath $sysCand) { $resolvedExe = $sysCand }
 }

 $psi = New-Object System.Diagnostics.ProcessStartInfo
 $psi.FileName = $resolvedExe
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
 $proc = $null
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
  if ($proc.WaitForExit($timeoutMs)) {
   $proc.WaitForExit()
   $outText = $outTask.Result
   $errText = $errTask.Result
   $exitCode = $proc.ExitCode
  } else {
   try { $proc.Kill() } catch {}
   $errText = "Command timed out after ${timeoutMs}ms: $fileName $arguments"
   $exitCode = -2
  }
 } catch {
  $errText = $_.Exception.Message
  $exitCode = -1
 } finally {
  if ($proc) { try { $proc.Dispose() } catch {} }
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

# Headless reboot helper (used by both GUI and Console)
function Invoke-SafeRebootCore([string]$shutdownArgs) {
 $shExe = Join-Path $env:SystemRoot "System32\shutdown.exe"
 $res = Invoke-NativeOem $shExe $shutdownArgs
 $detail = ($res.Lines | Where-Object { $_ -and $_.Trim() -ne "" }) -join " "
 return [PSCustomObject]@{
  Success = ($res.ExitCode -eq 0)
  ExitCode = $res.ExitCode
  Output = $detail
 }
}

# Safe reboot wrapper for Console TUI: checks exit code so reboot errors are never hidden
function Invoke-SafeReboot([string]$shutdownArgs, [string]$targetLabel = "") {
 $r = Invoke-SafeRebootCore $shutdownArgs
 if ($r.Success) {
  exit 0
 }
 $lbl = if ($targetLabel) { " (" + $targetLabel + ")" } else { "" }
 Write-Host ("`n [" + (U "\uC624\uB958") + "] " + (U "\uC7AC\uBD80\uD305 \uBA85\uB839 \uC2E4\uD589 \uC2E4\uD328") + $lbl + " (ExitCode=" + $r.ExitCode + ")") -ForegroundColor Red
 if ($r.Output) { Write-Host (" - " + $r.Output) -ForegroundColor Yellow }
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
 return $false
}

# Detect execution source label (Local / Read-Only USB / Shared Folder)
function Get-ExecutionSourceInfo {
 $p = [string]$env:SELF_PATH
 if ($env:SID_TOOL_STAGED -eq "1" -or ($p -and $p.StartsWith("\\"))) {
  return [PSCustomObject]@{ Mode = "Network"; Label = (U "\uACF5\uC720\uD3F4\uB354/\uB124\uD2B8\uC6CC\uD06C (\uBA54\uBAA8\uB9AC \uB85C\uB4DC, \uC6D0\uBCF8 \uBB34\uBCC0\uACBD)") }
 }
 if ($p) {
  try {
   $rt = [System.IO.Path]::GetPathRoot($p)
   if ($rt) {
    $di = New-Object System.IO.DriveInfo ($rt)
    if ($di.DriveType -eq "Network") {
     return [PSCustomObject]@{ Mode = "Network"; Label = (U "\uB124\uD2B8\uC6CC\uD06C \uB4DC\uB77C\uC774\uBE0C (\uBA54\uBAA8\uB9AC \uB85C\uB4DC, \uC6D0\uBCF8 \uBB34\uBCC0\uACBD)") }
    } elseif ($di.DriveType -eq "Removable" -or $di.DriveType -eq "CDRom") {
     return [PSCustomObject]@{ Mode = "USB"; Label = (U "\uC678\uC7A5 USB/\uC77D\uAE30 \uC804\uC6A9 \uB9E4\uCCB4 (\uC6D0\uBCF8 \uC4F0\uAE30 \uC5C6\uC74C)") }
    }
   }
  } catch {}
 }
 return [PSCustomObject]@{ Mode = "Local"; Label = (U "\uB85C\uCEEC \uB4DC\uB77C\uC774\uBE0C") }
}

function Get-DiskDebugText {
 $sb = New-Object System.Text.StringBuilder
 if (Test-StorageCmdletsAvailable) {
  $t1 = Get-Disk | Format-Table Number, FriendlyName, BusType, PartitionStyle, OperationalStatus, IsBoot, IsSystem, IsRemovable, IsReadOnly, Size -AutoSize | Out-String
  $t2 = Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, IsActive, GptType, MbrType, Size -AutoSize | Out-String
  [void]$sb.AppendLine($t1.TrimEnd())
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine($t2.TrimEnd())
 } else {
  [void]$sb.AppendLine((U "Storage \uBAA8\uB4C8(Get-Disk) \uBBF8\uC9C0\uC6D0 \uD658\uACBD - diskpart \uC9C4\uB2E8\uC73C\uB85C \uB300\uCCB4\uD569\uB2C8\uB2E4."))
  $dpRes = Invoke-NativeOem "diskpart.exe" "" "list disk`r`nlist volume`r`nexit`r`n"
  foreach ($ln in $dpRes.Lines) { [void]$sb.AppendLine([string]$ln) }
 }
 return $sb.ToString()
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
 Write-Host (Get-DiskDebugText) -ForegroundColor Gray
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

# Headless helper: Inspect root folder listing of target partition (for GUI confirmation preview)
function Get-PartitionPreviewListing($item) {
 if (-not $item -or $item.TargetPart -le 0 -or $item.BootType -eq "NONE") { return "" }
 $res = Invoke-WithEspMount $item.DiskNumber $item.TargetPart $item.TargetLetter {
  param($drv)
  $entries = @(Get-ChildItem -Path "$($drv):\" -Force -ErrorAction SilentlyContinue | Select-Object -First 12)
  if ($entries.Count -eq 0) { return "(empty)" }
  return (($entries | ForEach-Object {
   $tag = if ($_.PSIsContainer) { "[DIR] " } else { "      " }
   $tag + $_.Name
  }) -join "`r`n")
 }
 if ($res -eq "MOUNT_FAIL") { return (U "[\uB9C8\uC6B4\uD2B8 \uC2E4\uD328]") }
 return [string]$res
}

# Headless non-destructive bootloader action (used by both WinForms GUI and Console TUI)
# $mode: "DISABLE" | "RESTORE"
function Invoke-BootloaderAction($item, [string]$mode) {
 if (-not $item) {
  return [PSCustomObject]@{ Success = $false; Status = "SKIPPED"; Message = (U "\uB300\uC0C1 \uB514\uC2A4\uD06C \uC5C6\uC74C"); Warning = "" }
 }
 if ($item.IsWinPEMedia) {
  return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Message = ("Disk " + $item.DiskNumber + " : " + (U "WinPE/\uC124\uCE58 \uB9E4\uCCB4 \uB514\uC2A4\uD06C\uB85C \uAC10\uC9C0\uB418\uC5B4 \uBCF4\uD638\uB429\uB2C8\uB2E4.")); Warning = "" }
 }
 if ($item.IsReadOnly) {
  return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Message = ("Disk " + $item.DiskNumber + " : " + (U "\uC77D\uAE30 \uC804\uC6A9(\uC4F0\uAE30 \uAE08\uC9C0) \uB514\uC2A4\uD06C\uB85C \uBCF4\uD638\uB429\uB2C8\uB2E4.")); Warning = "" }
 }
 if ($item.IsProtected) {
  return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Message = ("Disk " + $item.DiskNumber + " (" + (U "\uD604\uC7AC OS/\uBD80\uD305 \uB514\uC2A4\uD06C") + ") " + (U "\uBCF4\uD638\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4.")); Warning = "" }
 }
 if ($item.TargetPart -le 0 -or $item.BootType -eq "NONE") {
  return [PSCustomObject]@{ Success = $false; Status = "SKIPPED"; Message = ("Disk " + $item.DiskNumber + " : " + (U "\uC870\uCE58 \uB300\uC0C1 \uBD80\uD2B8\uB85C\uB354 \uD30C\uD2F0\uC158\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.")); Warning = "" }
 }

 $actRes = Invoke-WithEspMount $item.DiskNumber $item.TargetPart $item.TargetLetter {
  param($drv)
  $root = "$($drv):\"
  $guard = Test-PartitionMediaGuard $root
  if ($guard.HasOs) {
   return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Message = (U "OS \uD30C\uD2F0\uC158(ntoskrnl.exe)\uC774 \uAC10\uC9C0\uB418\uC5B4 \uC790\uB3D9 \uBCC0\uACBD\uC744 \uC911\uB2E8\uD569\uB2C8\uB2E4."); Warning = "" }
  }
  if ($guard.HasWinPE) {
   return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Message = (U "WinPE/\uC124\uCE58 \uB9E4\uCCB4(boot.wim/\uC678\uC7A5 \uBD80\uD305 \uAD6C\uC870)\uAC00 \uAC10\uC9C0\uB418\uC5B4 \uC911\uB2E8\uD569\uB2C8\uB2E4."); Warning = "" }
  }

  if ($item.BootType -eq "GPT_EFI") {
   $hasEfi = Test-Path "$($drv):\EFI"
   $hasOld = Test-Path "$($drv):\EFI_OLD"
   if ($hasEfi -and $hasOld) {
    return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Message = ("Disk " + $item.DiskNumber + " : " + (U "\uD30C\uD2F0\uC158\uC5D0 \uD65C\uC131/\uBE44\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354\uAC00 \uACF5\uC874\uD569\uB2C8\uB2E4. \uC218\uB3D9 \uD655\uC778 \uD544\uC694.")); Warning = "" }
   }
   $r = Invoke-BootloaderRenameInRoot $root "GPT_EFI" $mode
   if ($r.Success) {
    $msg = if ($mode -eq "DISABLE") {
     "Disk " + $item.DiskNumber + " EFI -> EFI_OLD " + (U "\uBE44\uD65C\uC131\uD654 \uC644\uB8CC!")
    } else {
     "Disk " + $item.DiskNumber + " EFI_OLD -> EFI " + (U "\uBCF5\uAD6C \uC644\uB8CC!")
    }
    return [PSCustomObject]@{ Success = $true; Status = "CHANGED"; Message = $msg; Warning = "" }
   }
   return [PSCustomObject]@{ Success = $false; Status = $r.Status; Message = ((U "\uC774\uB984 \uBCC0\uACBD \uC2E4\uD328: ") + $r.Error); Warning = "" }
  }

  if ($item.BootType -eq "MBR_ACTIVE") {
   $hasActive = (Test-Path "$($drv):\bootmgr") -or (Test-Path "$($drv):\Boot\BCD")
   $hasOld = (Test-Path "$($drv):\bootmgr_OLD") -or (Test-Path "$($drv):\Boot_OLD")
   if ($hasActive -and $hasOld) {
    return [PSCustomObject]@{ Success = $false; Status = "BLOCKED"; Message = ("Disk " + $item.DiskNumber + " : " + (U "\uD30C\uD2F0\uC158\uC5D0 \uD65C\uC131/\uBE44\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354\uAC00 \uACF5\uC874\uD569\uB2C8\uB2E4. \uC218\uB3D9 \uD655\uC778 \uD544\uC694.")); Warning = "" }
   }
   $r = Invoke-BootloaderRenameInRoot $root "MBR_ACTIVE" $mode
   if ($r.Success) {
    $dpCmd = if ($mode -eq "DISABLE") { "inactive" } else { "active" }
    $dpRes = Invoke-NativeOem "diskpart.exe" "" ("select disk " + $item.DiskNumber + "`r`nselect partition " + $item.TargetPart + "`r`n" + $dpCmd + "`r`nexit`r`n")
    $warn = ""
    if ($dpRes.ExitCode -ne 0) {
     $warn = if ($mode -eq "DISABLE") {
      U "\uD30C\uC77C \uC774\uB984 \uBCC0\uACBD\uC740 \uC644\uB8CC\uD588\uC73C\uB098 diskpart inactive \uC124\uC815\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."
     } else {
      U "\uD30C\uC77C \uBCF5\uAD6C\uB294 \uC644\uB8CC\uD588\uC73C\uB098 diskpart active \uC124\uC815\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4."
     }
    }
    $msg = if ($mode -eq "DISABLE") {
     "Disk " + $item.DiskNumber + " " + (U "MBR \uBD80\uD2B8\uB85C\uB354 \uBE44\uD65C\uC131\uD654 \uC644\uB8CC! (bootmgr/Boot -> _OLD, inactive)")
    } else {
     "Disk " + $item.DiskNumber + " " + (U "MBR \uBD80\uD2B8\uB85C\uB354 \uBCF5\uAD6C \uC644\uB8CC! (_OLD -> \uC6D0\uBCF5, active)")
    }
    return [PSCustomObject]@{ Success = $true; Status = "CHANGED"; Message = $msg; Warning = $warn }
   }
   return [PSCustomObject]@{ Success = $false; Status = $r.Status; Message = ((U "MBR \uC870\uCE58 \uC2E4\uD328 (\uAD8C\uD55C/\uC7A0\uAE08 \uD655\uC778): ") + $r.Error); Warning = "" }
  }
  return [PSCustomObject]@{ Success = $false; Status = "SKIPPED"; Message = "UNSUPPORTED_TYPE"; Warning = "" }
 }

 if ($actRes -eq "MOUNT_FAIL") {
  return [PSCustomObject]@{ Success = $false; Status = "FAILED"; Message = ("Disk " + $item.DiskNumber + " " + (U "[\uB9C8\uC6B4\uD2B8 \uC2E4\uD328]")); Warning = "" }
 }
 return $actRes
}

# Interactive Console non-destructive toggle for GPT EFI or MBR Active bootloader
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

 $preview = Get-PartitionPreviewListing $item
 Write-Host ("`n--- Disk " + $item.DiskNumber + " (" + $item.Model + ") | " + $item.BootType + " Part #" + $item.TargetPart + " ---") -ForegroundColor Cyan
 if ($preview) { Write-Host $preview -ForegroundColor Gray }

 $mode = ""
 $promptText = ""
 if ($item.State -eq "ACTIVE") {
  $mode = "DISABLE"
  $promptText = if ($item.BootType -eq "MBR_ACTIVE") {
   "Disk " + $item.DiskNumber + " " + (U "MBR \uD65C\uC131 \uBD80\uD2B8\uB85C\uB354(bootmgr/Boot)\uB97C \uBE44\uD65C\uC131\uD654(_OLD + inactive)\uD560\uAE4C\uC694? (Y/N)")
  } else {
   "Disk " + $item.DiskNumber + " [EFI -> EFI_OLD] " + (U "\uBE44\uD65C\uC131\uD654\uD560\uAE4C\uC694? (Y/N)")
  }
 } elseif ($item.State -eq "DISABLED" -and -not $disableOnly) {
  $mode = "RESTORE"
  $promptText = if ($item.BootType -eq "MBR_ACTIVE") {
   "Disk " + $item.DiskNumber + " " + (U "MBR \uBE44\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354(_OLD)\uB97C \uBCF5\uAD6C(+ active)\uD560\uAE4C\uC694? (Y/N)")
  } else {
   "Disk " + $item.DiskNumber + " [EFI_OLD -> EFI] " + (U "\uBCF5\uAD6C\uD560\uAE4C\uC694? (Y/N)")
  }
 } elseif ($item.State -eq "BOTH") {
  Write-Host (" [" + (U "\uC911\uB2E8") + "] Disk " + $item.DiskNumber + " : " + (U "\uD30C\uD2F0\uC158\uC5D0 \uD65C\uC131/\uBE44\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354\uAC00 \uACF5\uC874\uD569\uB2C8\uB2E4. \uC218\uB3D9 \uD655\uC778 \uD544\uC694.")) -ForegroundColor Yellow
  return "BLOCKED"
 } else {
  return "SKIPPED"
 }

 $yn = (Read-Host $promptText).Trim()
 if ($yn -notmatch "^[yY]$") {
  Write-Host (U " \uC791\uC5C5\uC744 \uCDE8\uC18C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Gray
  return "CANCELLED"
 }

 $res = Invoke-BootloaderAction $item $mode
 if ($res.Success) {
  Write-Host (" [" + (U "\uC131\uACF5") + "] " + $res.Message) -ForegroundColor Green
  if ($res.Warning) { Write-Host (" [" + (U "\uACBD\uACE0") + "] " + $res.Warning) -ForegroundColor Yellow }
 } else {
  Write-Host (" [" + (U "\uC2E4\uD328") + "] " + $res.Message) -ForegroundColor Red
 }
 return [string]$res.Status
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

 return [PSCustomObject]@{
  Vendor = $vendor
  HintVendor = $hintVendor
  ModelName = $modelName
  RawVendor = $rawVendor
  BiosVersion = [string]$bios.SMBIOSBIOSVersion
  BiosHint = $vendorBiosHint
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

# Contextual UX Guidance Engine for Pre-SID (tells the user WHAT state this PC is in & WHICH button to click next!)
function Get-PreSidGuidance($sysInfo, $efiRep, $diag, $usbInfo, [array]$matchedEntries, [bool]$step1Bypassed) {
 if ($diag -and -not $diag.BootMode.IsUefi) {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "Legacy(MBR) \uBD80\uD305 \uD658\uACBD - USB \uC77C\uD68C\uC131 \uC790\uB3D9 \uBD80\uD305 \uBBF8\uC9C0\uC6D0"
   Message = U "\uD604\uC7AC PC\uB294 Legacy \uBAA8\uB4DC\uC785\uB2C8\uB2E4. \uC7AC\uBD80\uD305 \uC2DC \uC81C\uC870\uC0AC \uBD80\uD2B8 \uBA54\uB274 \uB2E8\uCD95\uD0A4(Samsung: F12/F10, HP: F9, Dell: F12)\uB97C \uC0AC\uC6A9\uD558\uC138\uC694. (\uC0AC\uD6C4 \uC791\uC5C5 \uD0ED\uC740 \uC815\uC0C1 \uC0AC\uC6A9 \uAC00\uB2A5)"
   RecommendedAction = "LEGACY_INFO"
  }
 }
 if ($efiRep -and $efiRep.HasBlockingRisk -and -not $step1Bypassed) {
  if ($efiRep.SplitBoot) {
   return [PSCustomObject]@{
    Level = "Error"
    Title = U "[STEP 1 \uC704\uD5D8] OS\uC640 \uBD80\uD305 EFI \uB514\uC2A4\uD06C\uAC00 \uBD84\uB9AC\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4!"
    Message = ((U "OS(Disk ") + $efiRep.BootDisk + (U ")\uC640 \uC2E4\uC81C \uBD80\uD305 EFI(Disk ") + $efiRep.SysDisk + (U ")\uAC00 \uBD84\uB9AC\uB418\uC5B4 \uC790\uB3D9 \uBE44\uD65C\uC131\uD654\uB97C \uCC28\uB2E8\uD588\uC2B5\uB2C8\uB2E4. \uB514\uC2A4\uD06C \uAD6C\uC131\uC744 \uBA3C\uC800 \uD655\uC778\uD558\uC138\uC694."))
    RecommendedAction = "STEP1_SPLIT"
   }
  }
  $cList = ($efiRep.ConflictItems | ForEach-Object { "Disk " + $_.DiskNumber }) -join ", "
  if ($efiRep.ActionableConflictItems.Count -gt 0) {
   return [PSCustomObject]@{
    Level = "Error"
    Title = U "[STEP 1 \uC120\uD589 \uD544\uC218] \uBCF4\uC870 \uB514\uC2A4\uD06C \uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uAC10\uC9C0!"
    Message = ($cList + (U "\uC5D0 \uAD6C\uD615 \uBD80\uD2B8\uB85C\uB354\uAC00 \uB0A8\uC544 \uC788\uC2B5\uB2C8\uB2E4. SID \uBCC0\uACBD \uD6C4 \uBD80\uD305 \uCDA9\uB3CC\uC744 \uB9C9\uAE30 \uC704\uD574 \uBA3C\uC800 [\uC6D0\uC2A4\uD1B1 \uC815\uB9AC] \uBC84\uD2BC\uC744 \uC2E4\uD589\uD558\uC138\uC694."))
    RecommendedAction = "STEP1_FIX"
   }
  }
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "[STEP 1 \uC218\uB3D9 \uD655\uC778 \uD544\uC694] \uBCF4\uC870 \uB514\uC2A4\uD06C \uACBD\uACE0 \uD56D\uBAA9 \uC874\uC7AC"
   Message = ($cList + (U "\uC5D0 \uC218\uB3D9 \uD655\uC778\uC774 \uD544\uC694\uD55C \uBD80\uD2B8\uB85C\uB354(\uACF5\uC874/\uAD6C\uD615 OS)\uAC00 \uC788\uC2B5\uB2C8\uB2E4. \uD655\uC778 \uD6C4 \uD544\uC694 \uC2DC [IGNORE \uC7A0\uAE08 \uD574\uC81C]\uB85C \uC9C4\uD589\uD558\uC138\uC694."))
   RecommendedAction = "STEP1_MANUAL"
  }
 }

 # STEP 1 passed or explicitly bypassed -> guide STEP 2 based on cross-checked BIOS + USB state
 if ($diag.SecureBootState -eq "On" -or $diag.SecureBootState -eq "Conflict") {
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "[BIOS \uC8FC\uC758] Secure Boot \uD65C\uC131\uD654/\uCDA9\uB3CC \uAC10\uC9C0 - BIOS \uD655\uC778 \uAD8C\uC7A5"
   Message = U "Secure Boot\uAC00 \uCF1C\uC838 \uC788\uC73C\uBA74 \uBBF8\uC11C\uBA85 WinPE USB\uAC00 \uCC28\uB2E8\uB420 \uC218 \uC788\uC2B5\uB2C8\uB2E4. [BIOS \uC124\uC815 \uC9C4\uC785]\uC73C\uB85C \uB044\uAC70\uB098, \uC11C\uBA85\uB41C WinPE\uB77C\uBA74 \uC544\uB798 USB\uB97C \uC120\uD0DD\uD558\uC138\uC694."
   RecommendedAction = "BIOS_SETUP"
  }
 }
 if ($diag.IsConfirmedBlocked) {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "[BIOS \uCC28\uB2E8 \uD655\uC815] BIOS\uC5D0\uC11C USB \uBD80\uD305 \uB610\uB294 \uD3EC\uD2B8\uAC00 \uBE44\uD65C\uC131\uD654\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4"
   Message = (U "[BIOS \uC124\uC815 \uC9C4\uC785] \uBC84\uD2BC\uC744 \uB20C\uB7EC USB \uBD80\uD305 \uC635\uC158\uC744 \uD65C\uC131\uD654\uD558\uC138\uC694. -> " + $diag.BiosHint)
   RecommendedAction = "BIOS_SETUP"
  }
 }
 if (-not $usbInfo -or $usbInfo.PhysicalUsbList.Count -eq 0) {
  return [PSCustomObject]@{
   Level = "Info"
   Title = U "[STEP 1 \uD1B5\uACFC] WinPE \uBD80\uD305 USB\uB97C \uC5F0\uACB0\uD558\uC138\uC694"
   Message = U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354\uB294 \uC815\uC0C1\uC785\uB2C8\uB2E4. WinPE USB\uB97C PC\uC5D0 \uAF42\uC740 \uB4A4 [\uC804\uCCB4 \uC0C8\uB85C\uACE0\uCE68] \uB610\uB294 [USB \uB2E4\uC2DC \uC2A4\uCE94]\uC744 \uB204\uB974\uC138\uC694."
   RecommendedAction = "PLUG_USB"
  }
 }
 if ($matchedEntries -and $matchedEntries.Count -gt 0) {
  if ($diag.HasSignalConflict) {
   return [PSCustomObject]@{
    Level = "Warn"
    Title = U "[\uAD50\uCC28 \uAC80\uC99D \uC8FC\uC758] WMI\uC640 NVRAM \uC2E0\uD638\uAC00 \uB2E4\uB985\uB2C8\uB2E4 - USB \uD56D\uBAA9 \uD655\uC778 \uD6C4 \uC9C4\uD589"
    Message = U "WMI\uB294 \uCC28\uB2E8\uC744 \uBCF4\uACE0\uD588\uC9C0\uB9CC UEFI NVRAM\uC5D0\uC11C USB\uAC00 \uC2E4\uC81C \uAC10\uC9C0\uB418\uC5C8\uC2B5\uB2C8\uB2E4. [\uAD50\uCC28 \uAC80\uC99D \uC0C1\uC138]\uB97C \uD655\uC778\uD558\uAC70\uB098 \uC544\uB798 USB\uB85C \uC7AC\uBD80\uD305\uC744 \uC2DC\uB3C4\uD558\uC138\uC694."
    RecommendedAction = "USB_REBOOT"
   }
  }
  return [PSCustomObject]@{
   Level = "OK"
   Title = U "[\uC900\uBE44 \uC644\uB8CC] \uC544\uB798 WinPE USB\uB97C \uD655\uC778\uD558\uACE0 1\uD68C\uC131 \uC7AC\uBD80\uD305\uD558\uC138\uC694"
   Message = U "\uBD80\uD2B8\uB85C\uB354 \uC0AC\uC804 \uC810\uAC80\uACFC NVRAM \uB9E4\uCE6D\uC774 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4. \uBAA9\uB85D\uC5D0\uC11C USB\uB97C \uC120\uD0DD\uD55C \uB4A4 [\uC120\uD0DD\uD55C USB\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305]\uC744 \uB204\uB974\uC138\uC694."
   RecommendedAction = "USB_REBOOT"
  }
 }

 # Physical USB plugged in, 0 NVRAM matches
 $isLikelyHotPlug = ($diag.UsbBootState -eq "Enabled" -and -not $diag.FastBootWarn)
 if ($isLikelyHotPlug) {
  return [PSCustomObject]@{
   Level = "Info"
   Title = U "[Hot-Plug \uCD94\uC815] Windows \uACE0\uAE09 \uBD80\uD305('\uC7A5\uCE58 \uC0AC\uC6A9') \uAD8C\uC7A5"
   Message = U "BIOS USB Boot\uB294 \uC815\uC0C1\uC774\uC9C0\uB9CC Windows \uBD80\uD305 \uD6C4 USB\uB97C \uAF42\uC544 NVRAM\uC5D0 \uC544\uC9C1 \uBBF8\uB4F1\uB85D \uC0C1\uD0DC\uC785\uB2C8\uB2E4. [\uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9)]\uC744 \uB204\uB974\uBA74 USB\uB97C \uACE8\uB77C \uBD80\uD305\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4."
   RecommendedAction = "ADV_BOOT"
  }
 }
 return [PSCustomObject]@{
  Level = "Warn"
  Title = U "[NVRAM \uBBF8\uB4F1\uB85D] BIOS \uC124\uC815 \uD655\uC778 \uB610\uB294 \uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9) \uC120\uD0DD"
  Message = U "\uBB3C\uB9AC USB\uB294 \uC778\uC2DD\uB410\uC9C0\uB9CC NVRAM \uBD80\uD305 \uBAA9\uB85D\uC5D0 \uC5C6\uC2B5\uB2C8\uB2E4. \uBC29\uAE08 USB\uB97C \uAF42\uC558\uB2E4\uBA74 [\uACE0\uAE09 \uBD80\uD305(\uC7A5\uCE58 \uC0AC\uC6A9)]\uC744, \uBD80\uD305 \uC804\uBD80\uD130 \uAF42\uD600 \uC788\uC5C8\uB2E4\uBA74 [BIOS \uC124\uC815 \uC9C4\uC785]\uC5D0\uC11C Fast Boot/USB Boot\uB97C \uD655\uC778\uD558\uC138\uC694."
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
# ==============================================================================
# Module 04: Physical USB Inspection, 4-Tier NVRAM Matching & Confirmed Reboot
# ==============================================================================

function Get-PhysicalUsbInfo([array]$usbDisks, [array]$internalDisks = @()) {
 $physicalUsbList = @()
 $usbDrivePatterns = @()
 $usbStrictModelPatterns = @()
 $usbPartPatterns = @()
 $anyEfiReadyUsb = $false

 # Collect words appearing in internal disk model names to prevent same-brand false matches (e.g. Samsung USB vs Samsung NVMe)
 $internalWords = @{}
 foreach ($idisk in $internalDisks) {
  if ($idisk -and $idisk.FriendlyName) {
   foreach ($iw in ($idisk.FriendlyName.Trim() -split "[\s_-]+")) {
    if ($iw.Length -ge 3) { $internalWords[$iw.ToLower()] = $true }
   }
  }
 }

 $hasStorage = Test-StorageCmdletsAvailable
 foreach ($disk in $usbDisks) {
  $sizeGB = [math]::Round($disk.Size / 1GB, 1)
  $parts = if ($hasStorage) { @(Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue) } else { @() }
  $drvLetters = @()
  $hasEfi = $false

  if ($disk.FriendlyName) {
   $cleanName = $disk.FriendlyName.Trim()
   $usbStrictModelPatterns += [regex]::Escape($cleanName)
   foreach ($word in ($cleanName -split "[\s_-]+")) {
    if ($word.Length -ge 3 -and
        $word -notmatch "^(USB|SSD|HDD|Disk|Drive|Device|General|Generic|Flash|Storage|Media|Mass|UFD|3\.0|2\.0|3\.2)$" -and
        (-not $internalWords.ContainsKey($word.ToLower()))) {
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
   IsReadOnly = [bool]$disk.IsReadOnly
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
  $descStr = [string]$_.Description
  $isInternalBusWithoutUsb = ($descStr -match "\b(SATA|NVMe)\b") -and ($descStr -notmatch "\bUSB\b|External|Removable")
  $_.Identifier -ne "{fwbootmgr}" -and
  $_.Identifier -ne "{bootmgr}" -and
  ($descStr -notmatch $excludeDesc) -and
  (-not $isInternalBusWithoutUsb) -and
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

# Shared snapshot collector for STEP 2 (used by both WinForms GUI and Console TUI)
function Get-PreSidStep2Snapshot($sysInfo) {
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

 $usbInfo = Get-PhysicalUsbInfo $usbDisks $internalDisks
 $matchedEntries = @()
 if ($usbDisks.Count -gt 0) {
  $matchedEntries = @(Find-MatchedUsbNvramEntries `
   $entries `
   $internalDriveLetters `
   $usbInfo.UsbDrivePatterns `
   $usbInfo.UsbStrictModelPatterns `
   $usbInfo.UsbPartPatterns `
   $usbInfo.AnyEfiReadyUsb)
 }

 $diag = Get-BiosDiagnostics $sysInfo $usbDisks $entries $matchedEntries.Count

 return [PSCustomObject]@{
  BcdOutput = $bcdOutput
  BcdEntries = $entries
  UsbDisks = $usbDisks
  InternalDisks = $internalDisks
  InternalDriveLetters = $internalDriveLetters
  UsbInfo = $usbInfo
  MatchedEntries = $matchedEntries
  BiosDiag = $diag
 }
}

function Invoke-PreSidUsbBootStep($sysInfo, [bool]$step1Bypassed) {
 $gate1Ignored = $false

 while ($true) {
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host (U " [\uC0AC\uC804 \uC791\uC5C5 - STEP 2/2] BIOS \uCC28\uB2E8 \uC694\uC18C \uC810\uAC80 \uBC0F WinPE USB \uBD80\uD305") -ForegroundColor Cyan
  Write-Host ("   System : [" + $sysInfo.Vendor + "] (" + $sysInfo.ModelName + ")") -ForegroundColor DarkCyan
  Write-Host "==================================================================" -ForegroundColor Cyan

  $snap = Get-PreSidStep2Snapshot $sysInfo
  $bcdOutput = $snap.BcdOutput
  $entries = $snap.BcdEntries
  $usbDisks = $snap.UsbDisks
  $internalDisks = $snap.InternalDisks
  $usbInfo = $snap.UsbInfo
  $matchedEntries = $snap.MatchedEntries
  $diag = $snap.BiosDiag

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
    elseif ($noUsbChoice -match "^[bB]$") { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
    elseif ($noUsbChoice -match "^[eE]$") { Show-BootloaderManager $false }
    elseif ($noUsbChoice -match "^[dD]$") { Show-BcdDebug $bcdOutput }
    elseif ($noUsbChoice -match "^[lL]$") { Show-DiskDebug }
    elseif ($noUsbChoice -eq "" -or $noUsbChoice -match "^[mMqQ]$") { return }
   }
   if ($rescanNow) { continue }
   return
  }

  # Display physical USB partitions
  Write-Host (U "`n[STEP 2-1] \uD604\uC7AC \uC5F0\uACB0\uB41C \uBB3C\uB9AC USB \uB514\uC2A4\uD06C \uBAA9\uB85D:") -ForegroundColor Cyan
  foreach ($u in $usbInfo.PhysicalUsbList) {
   $efiTag = if ($u.IsEfiReady) { U "UEFI \uBD80\uD305 \uAC00\uB2A5" } else { U "EFI \uD30C\uD2F0\uC158 \uBBF8\uD655\uC778" }
   $roTag = if ($u.IsReadOnly) { " [" + (U "\uC77D\uAE30 \uC804\uC6A9") + "]" } else { "" }
   Write-Host (" - Disk " + $u.DiskNumber + " : " + $u.Model + " [" + $u.SizeGB + "]" + $roTag + " | " + $u.Partitions + " -> (" + $efiTag + ")") -ForegroundColor White
  }

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
     if ($isLikelyHotPlug) { $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot" }
     else { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
    } elseif ($fbChoice -match "^[oO]$") { $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot" }
    elseif ($fbChoice -match "^[bB]$") { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
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
   elseif ($choice -match "^[oO]$") { $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot" }
   elseif ($choice -match "^[bB]$") { $null = Invoke-SafeReboot "/r /fw /f /t 0" "BIOS Setup" }
   elseif ($choice -match "^[mMqQ]$") { return }
  }

  if ($rescanNow) { continue }
  if (-not $selectedTarget) { return }

  # Set 1-time bootsequence and reboot
  $setRes = Invoke-NativeOem "bcdedit.exe" ("/set {fwbootmgr} bootsequence " + $selectedTarget.Identifier)
  if ($setRes.ExitCode -eq 0) {
   Write-Host ("`n-> [" + $selectedTarget.Description + (U "] \uBD80\uD305 \uC21C\uC11C \uC9C0\uC815 \uC644\uB8CC! \uC989\uC2DC \uC7AC\uBD80\uD305\uD569\uB2C8\uB2E4...")) -ForegroundColor Cyan
   $null = Invoke-SafeReboot "/r /f /t 0" "USB One-Time Boot"
   return
  } else {
   Write-Host (U "`n[\uC624\uB958] NVRAM \uBD80\uD305 \uC21C\uC11C \uBCC0\uACBD \uC2E4\uD328!") -ForegroundColor Red
   Write-Host ((U "\uC0C1\uC138 \uCD9C\uB825: ") + ($setRes.Lines -join " ")) -ForegroundColor Yellow
   Write-Host (U "[O] Windows \uC7A5\uCE58 \uC0AC\uC6A9 \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305 | [Enter/M] \uBA54\uC778 \uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uAE30") -ForegroundColor Cyan
   $errChoice = (Read-Host (U "\uC120\uD0DD")).Trim()
   if ($errChoice -match "^[oO]$") {
    $null = Invoke-SafeReboot "/r /o /f /t 0" "Advanced Boot"
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
 $iar = $null
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
  if ($iar -and $iar.AsyncWaitHandle) { try { $iar.AsyncWaitHandle.Close() } catch {} }
  if ($client) { try { $client.Close() } catch {} }
 }
}

function Get-SpoolerQueueDirectory {
 $defaultDir = Join-Path $env:SystemRoot "System32\spool\PRINTERS"
 try {
  $reg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers" -Name "DefaultSpoolDirectory" -ErrorAction Stop
  $custom = [string]$reg.DefaultSpoolDirectory
  if ($custom -and $custom.Trim() -ne "" -and (-not $custom.StartsWith("\\")) -and (Test-Path -LiteralPath $custom)) {
   return $custom.Trim()
  }
 } catch {}
 return $defaultDir
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
 $queueDir = Get-SpoolerQueueDirectory
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

 # Also check HKCU and all loaded HKU user hives for per-user network printers (works across Over-the-Shoulder UAC)
 $seenNetNames = @{}
 foreach ($p in $printers) {
  if ($p.IsNetwork) { $seenNetNames[$p.Name.ToLower()] = $true }
 }
 $connRegPaths = @("HKCU:\Printers\Connections")
 try {
  foreach ($uh in @(Get-ChildItem "Registry::HKEY_USERS" -ErrorAction SilentlyContinue)) {
   if ($uh.PSChildName -match "^S-1-5-21-\d+-\d+-\d+-\d+$") {
    $connRegPaths += (Join-Path $uh.PSPath "Printers\Connections")
   }
  }
 } catch {}
 foreach ($regPath in ($connRegPaths | Select-Object -Unique)) {
  try {
   if (Test-Path $regPath) {
    $connKeys = @(Get-ChildItem $regPath -ErrorAction SilentlyContinue)
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
 }

 $sharedPrinters = @($printers | Where-Object { $_.Shared -and -not $_.IsNetwork })
 $networkPrinters = @($printers | Where-Object { $_.IsNetwork })
 $role = if ($spStatus -ne "Running") { "Unknown" } elseif ($sharedPrinters.Count -gt 0) { "Host" } else { "Client" }

 # Host diagnostics: File & Printer Sharing firewall rules + Network profiles
 $fwTotal = -1
 $fwEnabled = -1
 $netProfiles = @()
 $hasPublicProfile = $false
 if ($role -eq "Host") {
  try {
   if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
    $fwRules = @(Get-NetFirewallRule -Group "@FirewallAPI.dll,-28502" -Direction Inbound -ErrorAction SilentlyContinue)
    if ($fwRules.Count -eq 0) {
     $koGroup = U "\uD30C\uC77C \uBC0F \uD504\uB9B0\uD130 \uACF5\uC720"
     $fwRules = @(Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Where-Object {
      $_.DisplayGroup -eq "File and Printer Sharing" -or $_.DisplayGroup -eq $koGroup
     })
    }
    $fwTotal = $fwRules.Count
    $fwEnabled = @($fwRules | Where-Object { [string]$_.Enabled -eq "True" }).Count
   }
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

# Contextual UX guidance for Post-SID screen (used by WinForms GUI and Console)
function Get-PostSidGuidance($st) {
 if (-not $st) {
  return [PSCustomObject]@{
   Level = "Info"
   Title = U "\uC0C1\uD0DC \uC870\uD68C \uC911"
   Message = U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uC0C1\uD0DC\uB97C \uD655\uC778\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 if ($st.SpoolerStatus -ne "Running" -or $st.SpoolerStartMode -eq "Disabled") {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "\uC989\uC2DC \uC870\uCE58 \uD544\uC694: Spooler \uC11C\uBE44\uC2A4 \uC911\uC9C0/\uBE44\uD65C\uC131\uD654"
   Message = U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4\uAC00 \uC2E4\uD589 \uC911\uC774 \uC544\uB2C8\uAC70\uB098 \uC0AC\uC6A9 \uC548 \uD568 \uC0C1\uD0DC\uC785\uB2C8\uB2E4. [\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589]\uC744 \uB20C\uB7EC \uC790\uB3D9 \uBCF5\uAD6C\uD558\uC138\uC694."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 if ($st.PrinterQueryError) {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "\uC989\uC2DC \uC870\uCE58 \uD544\uC694: Spooler RPC \uC751\uB2F5 \uC624\uB958"
   Message = U "Spooler\uB294 \uC2E4\uD589 \uC911\uC774\uC9C0\uB9CC \uD504\uB9B0\uD130 \uBAA9\uB85D \uC870\uD68C\uAC00 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4(SID \uBCC0\uACBD \uC9C1\uD6C4 \uD754\uD55C \uC99D\uC0C1). [\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589]\uC744 \uC9C4\uD589\uD558\uC138\uC694."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 if ($st.Role -eq "Host") {
  if ($st.HasPublicProfile -or $st.FirewallInboundEnabled -eq 0) {
   return [PSCustomObject]@{
    Level = "Warn"
    Title = U "[\uBA54\uC778 \uD504\uB9B0\uD130 PC] \uC2A4\uD480\uB7EC \uB9AC\uC14B + \uB124\uD2B8\uC6CC\uD06C/\uBC29\uD654\uBCBD \uD655\uC778 \uD544\uC694"
    Message = U "\uBA3C\uC800 [\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589]\uC744 \uB204\uB974\uC138\uC694. \uB610\uD55C \uACF5\uC6A9(Public) \uB124\uD2B8\uC6CC\uD06C\uB098 \uBC29\uD654\uBCBD \uCC28\uB2E8 \uACBD\uACE0\uAC00 \uC788\uC73C\uBBC0\uB85C \uC544\uB798 \uC9C4\uB2E8 \uACB0\uACFC\uB97C \uD568\uAED8 \uD655\uC778\uD558\uC138\uC694."
    RecommendedAction = "SPOOLER_RESET"
   }
  }
  return [PSCustomObject]@{
   Level = "OK"
   Title = U "[\uBA54\uC778 \uD504\uB9B0\uD130 PC(\uD638\uC2A4\uD2B8)] \uAD8C\uC7A5: \uC2A4\uD480\uB7EC \uB9AC\uC14B 1\uD68C \uC2E4\uD589"
   Message = U "SID \uBCC0\uACBD \uC9C1\uD6C4\uB77C\uBA74 [\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589]\uC744 1\uD68C \uC9C4\uD589\uD558\uC138\uC694. \uC774\uD6C4 \uAC01 \uD074\uB77C\uC774\uC5B8\uD2B8 PC\uC5D0\uC11C\uB3C4 1\uD68C \uC2E4\uD589\uD558\uBA74 \uACF5\uC720 \uD504\uB9B0\uD130\uAC00 \uC815\uC0C1 \uC5F0\uACB0\uB429\uB2C8\uB2E4."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 $unreachableHosts = @($st.RemoteHostChecks | Where-Object { -not $_.Reachable })
 if ($unreachableHosts.Count -gt 0) {
  $uNames = ($unreachableHosts | ForEach-Object { "\\" + $_.Server }) -join ", "
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "[\uD074\uB77C\uC774\uC5B8\uD2B8 PC] \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589 + \uBA54\uC778 PC \uC5F0\uACB0 \uD655\uC778 \uD544\uC694"
   Message = ((U "\uC774 PC\uC5D0\uC11C [\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589]\uC744 \uC9C4\uD589\uD558\uC138\uC694. \uB2E8, \uBA54\uC778 PC(") + $uNames + (U ")\uC758 SMB(445) \uC751\uB2F5\uC774 \uC5C6\uC5B4 \uBA54\uC778 PC \uC804\uC6D0/\uB124\uD2B8\uC6CC\uD06C\uB3C4 \uD655\uC778\uD558\uC138\uC694."))
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 return [PSCustomObject]@{
  Level = "Info"
  Title = U "[\uD074\uB77C\uC774\uC5B8\uD2B8 PC] \uAD8C\uC7A5: \uC2A4\uD480\uB7EC \uB9AC\uC14B 1\uD68C \uC2E4\uD589 \uD6C4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4"
  Message = U "\uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uC774 PC\uC5D0\uC11C \uAC01\uAC01 [\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589]\uC744 1\uD68C \uC9C4\uD589\uD55C \uB4A4 \uACF5\uC720 \uD504\uB9B0\uD130 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB97C \uD655\uC778\uD558\uC138\uC694."
  RecommendedAction = "SPOOLER_RESET"
 }
}

# Headless Spooler Reset engine (shared by WinForms GUI and Console TUI)
function Invoke-SpoolerResetCore([scriptblock]$onProgress = $null) {
 $logs = New-Object System.Collections.ArrayList
 $emit = {
  param([string]$msg)
  [void]$logs.Add($msg)
  if ($onProgress) { & $onProgress $msg }
 }

 $sp = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
 if (-not $sp) {
  $errMsg = U "\uC774 PC\uC5D0\uC11C Spooler \uC11C\uBE44\uC2A4\uB97C \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."
  & $emit ("[" + (U "\uC624\uB958") + "] " + $errMsg)
  return [PSCustomObject]@{
   Success = $false
   ServiceMissing = $true
   StopMode = "FAILED"
   QueueResult = $null
   StartRestored = $false
   StartMode = "NotFound"
   RunningDeps = @()
   RestartedDeps = @()
   IsRunning = $false
   StartError = $errMsg
   LogLines = @($logs)
  }
 }

 & $emit (U "1/4. Spooler \uC11C\uBE44\uC2A4 \uC911\uC9C0 \uC911...")
 $runningDeps = @()
 $stopMode = "FAILED"
 try {
  $deps = @(Get-Service -Name "Spooler" -DependentServices -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" })
  foreach ($d in $deps) {
   $runningDeps += $d.Name
   Stop-Service -Name $d.Name -Force -ErrorAction SilentlyContinue
  }
 } catch {}

 if ($sp.Status -eq "Stopped") {
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
   & $emit (U "     \uC911\uC9C0 \uD0C0\uC784\uC544\uC6C3 - spoolsv \uD504\uB85C\uC138\uC2A4\uB97C \uC548\uC804 \uC885\uB8CC\uD569\uB2C8\uB2E4...")
   Stop-Process -Name "spoolsv" -Force -ErrorAction SilentlyContinue
   for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 500
    $spNow = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
    if ($spNow -and $spNow.Status -eq "Stopped") { $stopped = $true; break }
   }
   if ($stopped) { $stopMode = "FORCED" }
  }
 }

 & $emit (U "2/4. \uB300\uAE30\uC5F4 \uD3F4\uB354(PRINTERS) \uC815\uB9AC \uC911...")
 $queueDir = Get-SpoolerQueueDirectory
 $qRes = Clear-SpoolerQueueDirectory $queueDir

 & $emit (U "3/4. Spooler \uC2DC\uC791 \uC720\uD615 \uC810\uAC80 \uC911...")
 $startRestored = $false
 $spCim = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue
 $curStartMode = if ($spCim -and $spCim.StartMode) { [string]$spCim.StartMode } else { "Unknown" }
 if ($curStartMode -eq "Disabled") {
  try {
   Set-Service -Name "Spooler" -StartupType Automatic -ErrorAction Stop
   $startRestored = $true
   $curStartMode = "Auto"
   & $emit (U "     \uC2DC\uC791 \uC720\uD615\uC774 Disabled \uC0C1\uD0DC\uC5EC\uC11C Automatic(\uC790\uB3D9)\uC73C\uB85C \uBCF5\uAD6C\uD588\uC2B5\uB2C8\uB2E4.")
  } catch {}
 }

 & $emit (U "4/4. Spooler \uC11C\uBE44\uC2A4 \uC7AC\uC2DC\uC791 \uC911...")
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

 return [PSCustomObject]@{
  Success = $isRunning
  ServiceMissing = $false
  StopMode = $stopMode
  QueueResult = $qRes
  StartRestored = $startRestored
  StartMode = $curStartMode
  RunningDeps = $runningDeps
  RestartedDeps = $restartedDeps
  IsRunning = $isRunning
  StartError = $startErr
  LogLines = @($logs)
 }
}

function Invoke-SpoolerReset {
 Write-Host "`n==================================================================" -ForegroundColor Cyan
 Write-Host (U " [\uC9C4\uD589] \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B\uC744 \uC2DC\uC791\uD569\uB2C8\uB2E4...") -ForegroundColor Cyan
 Write-Host "==================================================================" -ForegroundColor Cyan

 $res = Invoke-SpoolerResetCore {
  param($msg)
  Write-Host (" " + $msg) -ForegroundColor White
 }

 if ($res.ServiceMissing) {
  Read-Host (U "\uACC4\uC18D\uD558\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
  return
 }

 $qRes = $res.QueueResult
 Write-Host ("`n-------------------- [" + (U "\uC2A4\uD480\uB7EC \uB9AC\uC14B \uACB0\uACFC \uB9AC\uD3EC\uD2B8") + "] --------------------") -ForegroundColor Cyan
 $stopText = switch ($res.StopMode) {
  "NORMAL" { U "\uC815\uC0C1 \uC911\uC9C0" }
  "FORCED" { U "\uD504\uB85C\uC138\uC2A4 \uAC15\uC81C \uC885\uB8CC \uD6C4 \uC911\uC9C0" }
  default  { U "\uC911\uC9C0 \uC2E4\uD328" }
 }
 Write-Host (" * " + (U "\uC11C\uBE44\uC2A4 \uC911\uC9C0") + "      : " + $stopText) -ForegroundColor $(if ($res.StopMode -eq "FAILED") { "Red" } else { "Green" })
 Write-Host (" * " + (U "\uB300\uAE30\uC5F4 \uD30C\uC77C \uC815\uB9AC") + " : " + $qRes.DeletedCount + (U "\uAC74 \uC0AD\uC81C \uC644\uB8CC") + " (SPL/SHD: " + $qRes.SplShdDeleted + ") | " + (U "\uC794\uC874 \uD30C\uC77C") + ": " + $qRes.RemainingCount + (U "\uAC74")) -ForegroundColor $(if ($qRes.RemainingCount -gt 0) { "Yellow" } else { "Green" })
 if ($qRes.FailedFiles.Count -gt 0) {
  Write-Host ("   - " + (U "\uC7A0\uAE40/\uC2E4\uD328") + ": " + ($qRes.FailedFiles -join ", ")) -ForegroundColor Yellow
 }
 $startTypeText = if ($res.StartRestored) { U "Automatic\uC73C\uB85C \uBCF5\uAD6C\uB428" } else { $res.StartMode + " (" + (U "\uC720\uC9C0") + ")" }
 Write-Host (" * " + (U "\uC2DC\uC791 \uC720\uD615") + "        : " + $startTypeText) -ForegroundColor $(if ($res.StartRestored) { "Green" } else { "Gray" })
 if ($res.RunningDeps.Count -gt 0) {
  Write-Host (" * " + (U "\uC758\uC874 \uC11C\uBE44\uC2A4 \uC911\uC9C0/\uC7AC\uC2DC\uC791") + " : " + $res.RestartedDeps.Count + "/" + $res.RunningDeps.Count + " " + (U "\uC7AC\uC2DC\uC791 \uC644\uB8CC")) -ForegroundColor Gray
 }
 if ($res.IsRunning) {
  Write-Host (" * " + (U "\uCD5C\uC885 \uC11C\uBE44\uC2A4 \uC0C1\uD0DC") + " : " + (U "\uC815\uC0C1 \uC2E4\uD589 \uC911 (Running)")) -ForegroundColor Green
  Write-Host ("`n " + (U "\uC644\uB8CC! \uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uD074\uB77C\uC774\uC5B8\uD2B8 PC \uBAA8\uB450\uC5D0\uC11C \uC2E4\uD589\uD55C \uB4A4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB97C \uD655\uC778\uD558\uC138\uC694.")) -ForegroundColor Cyan
 } else {
  Write-Host (" * " + (U "\uCD5C\uC885 \uC11C\uBE44\uC2A4 \uC0C1\uD0DC") + " : " + (U "\uC2DC\uC791 \uC2E4\uD328") + $(if ($res.StartError) { " (" + $res.StartError + ")" } else { "" })) -ForegroundColor Red
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

 $roleLabel = switch ($st.Role) {
  "Host"    { U "[\uD638\uC2A4\uD2B8(\uBA54\uC778 \uD504\uB9B0\uD130 PC)]" }
  "Client"  { U "[\uD074\uB77C\uC774\uC5B8\uD2B8]" }
  default   { U "[\uD310\uBCC4 \uBCF4\uB958 (Spooler \uC911\uC9C0\uB428)]" }
 }
 $roleColor = switch ($st.Role) {
  "Host"   { "Cyan" }
  "Client" { "Green" }
  default  { "Yellow" }
 }
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
 } elseif ($st.PrinterQueryError) {
  Write-Host (" - " + (U "[\uACBD\uACE0] \uD504\uB9B0\uD130 \uBAA9\uB85D \uC870\uD68C \uC624\uB958 - Spooler RPC \uBE44\uC815\uC0C1 \uC0C1\uD0DC\uC785\uB2C8\uB2E4. \uC2A4\uD480\uB7EC \uB9AC\uC14B\uC744 \uC2E4\uD589\uD558\uC138\uC694!")) -ForegroundColor Red
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
# Module 06: WinForms Desktop GUI (Pure GAC Assemblies, Zero Temp DLLs)
#            Guided UX, Intuitive USB List, BIOS Cross-Check Viewer, Post-SID
# ==============================================================================

function Test-WinFormsAvailable {
 try {
  if (-not [Environment]::UserInteractive) { return $false }
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
  Add-Type -AssemblyName System.Drawing -ErrorAction Stop
  return $true
 } catch {
  return $false
 }
}

function Get-GuiPalette {
 return @{
  AppBg       = [System.Drawing.Color]::FromArgb(245, 247, 250)
  CardBg      = [System.Drawing.Color]::White
  HeaderBg    = [System.Drawing.Color]::FromArgb(30, 41, 59)
  HeaderFg    = [System.Drawing.Color]::White
  HeaderSub   = [System.Drawing.Color]::FromArgb(203, 213, 225)
  Border      = [System.Drawing.Color]::FromArgb(220, 226, 234)
  TextDark    = [System.Drawing.Color]::FromArgb(15, 23, 42)
  TextMuted   = [System.Drawing.Color]::FromArgb(71, 85, 105)
  OkBg        = [System.Drawing.Color]::FromArgb(232, 247, 238)
  OkFg        = [System.Drawing.Color]::FromArgb(19, 115, 51)
  OkAccent    = [System.Drawing.Color]::FromArgb(22, 163, 74)
  InfoBg      = [System.Drawing.Color]::FromArgb(232, 240, 254)
  InfoFg      = [System.Drawing.Color]::FromArgb(25, 103, 210)
  InfoAccent  = [System.Drawing.Color]::FromArgb(37, 99, 235)
  WarnBg      = [System.Drawing.Color]::FromArgb(254, 247, 224)
  WarnFg      = [System.Drawing.Color]::FromArgb(161, 83, 0)
  WarnAccent  = [System.Drawing.Color]::FromArgb(217, 119, 6)
  ErrBg       = [System.Drawing.Color]::FromArgb(252, 232, 230)
  ErrFg       = [System.Drawing.Color]::FromArgb(180, 35, 24)
  ErrAccent   = [System.Drawing.Color]::FromArgb(220, 38, 38)
  BtnNeutral  = [System.Drawing.Color]::FromArgb(241, 245, 249)
  BtnDisabled = [System.Drawing.Color]::FromArgb(226, 232, 240)
  RowAlt      = [System.Drawing.Color]::FromArgb(248, 250, 252)
 }
}

function Set-GuiButtonStyle($btn, [string]$kind, $pal) {
 $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
 $btn.FlatAppearance.BorderSize = 1
 $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
 switch ($kind) {
  "PrimaryGreen" {
   $btn.BackColor = $pal.OkAccent
   $btn.ForeColor = [System.Drawing.Color]::White
   $btn.FlatAppearance.BorderColor = $pal.OkFg
  }
  "PrimaryBlue" {
   $btn.BackColor = $pal.InfoAccent
   $btn.ForeColor = [System.Drawing.Color]::White
   $btn.FlatAppearance.BorderColor = $pal.InfoFg
  }
  "PrimaryAmber" {
   $btn.BackColor = $pal.WarnAccent
   $btn.ForeColor = [System.Drawing.Color]::White
   $btn.FlatAppearance.BorderColor = $pal.WarnFg
  }
  "PrimaryRed" {
   $btn.BackColor = $pal.ErrAccent
   $btn.ForeColor = [System.Drawing.Color]::White
   $btn.FlatAppearance.BorderColor = $pal.ErrFg
  }
  "Header" {
   $btn.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
   $btn.ForeColor = [System.Drawing.Color]::White
   $btn.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
  }
  "Disabled" {
   $btn.BackColor = $pal.BtnDisabled
   $btn.ForeColor = $pal.TextMuted
   $btn.FlatAppearance.BorderColor = $pal.Border
  }
  default {
   $btn.BackColor = $pal.BtnNeutral
   $btn.ForeColor = $pal.TextDark
   $btn.FlatAppearance.BorderColor = $pal.Border
  }
 }
}

function Set-BannerVisual($panel, $accentBar, $lblTitle, $lblMsg, $guidance, $pal) {
 $bg = $pal.InfoBg; $fg = $pal.InfoFg; $ac = $pal.InfoAccent
 switch ($guidance.Level) {
  "OK"    { $bg = $pal.OkBg;   $fg = $pal.OkFg;   $ac = $pal.OkAccent }
  "Warn"  { $bg = $pal.WarnBg; $fg = $pal.WarnFg; $ac = $pal.WarnAccent }
  "Error" { $bg = $pal.ErrBg;  $fg = $pal.ErrFg;  $ac = $pal.ErrAccent }
 }
 $panel.BackColor = $bg
 $accentBar.BackColor = $ac
 $lblTitle.ForeColor = $fg
 $lblTitle.Text = [string]$guidance.Title
 $lblMsg.ForeColor = $pal.TextDark
 $lblMsg.Text = [string]$guidance.Message
}

# Modal dialog: Require typing IGNORE to bypass STEP 1 blocking risk
function Show-GuiIgnoreConfirmDialog($ownerForm, $pal) {
 $dlg = New-Object System.Windows.Forms.Form
 $dlg.Text = U "STEP 1 \uC704\uD5D8 \uD655\uC778 (IGNORE)"
 $dlg.Size = New-Object System.Drawing.Size(470, 230)
 $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
 $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
 $dlg.MaximizeBox = $false
 $dlg.MinimizeBox = $false
 $dlg.BackColor = $pal.CardBg
 $dlg.Font = New-Object System.Drawing.Font("Malgun Gothic", 9.5)

 $lbl = New-Object System.Windows.Forms.Label
 $lbl.Text = U "\uBCF4\uC870 \uB514\uC2A4\uD06C\uC758 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uB97C \uC815\uB9AC\uD558\uC9C0 \uC54A\uACE0 USB \uBD80\uD305\uC744 \uC9C4\uD589\uD558\uBA74 SID \uBCC0\uACBD \uD6C4 \uBD80\uD305 \uCDA9\uB3CC\uC774 \uBC1C\uC0DD\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.`r`n`r`n\uC704\uD5D8\uC744 \uC774\uD574\uD558\uACE0 STEP 2 \uC7A0\uAE08\uC744 \uD574\uC81C\uD558\uB824\uBA74 \uC544\uB798\uC5D0 \uC601\uBB38 IGNORE \uB97C \uC785\uB825\uD558\uC138\uC694."
 $lbl.Location = New-Object System.Drawing.Point(16, 16)
 $lbl.Size = New-Object System.Drawing.Size(425, 86)
 $lbl.ForeColor = $pal.ErrFg
 $dlg.Controls.Add($lbl)

 $tb = New-Object System.Windows.Forms.TextBox
 $tb.Location = New-Object System.Drawing.Point(16, 110)
 $tb.Size = New-Object System.Drawing.Size(422, 26)
 $dlg.Controls.Add($tb)

 $btnOk = New-Object System.Windows.Forms.Button
 $btnOk.Text = U "\uC7A0\uAE08 \uD574\uC81C"
 $btnOk.Location = New-Object System.Drawing.Point(258, 148)
 $btnOk.Size = New-Object System.Drawing.Size(88, 30)
 Set-GuiButtonStyle $btnOk "PrimaryRed" $pal
 $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
 $dlg.Controls.Add($btnOk)

 $btnCancel = New-Object System.Windows.Forms.Button
 $btnCancel.Text = U "\uCDE8\uC18C"
 $btnCancel.Location = New-Object System.Drawing.Point(354, 148)
 $btnCancel.Size = New-Object System.Drawing.Size(84, 30)
 Set-GuiButtonStyle $btnCancel "Neutral" $pal
 $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
 $dlg.Controls.Add($btnCancel)

 $dlg.AcceptButton = $btnOk
 $dlg.CancelButton = $btnCancel

 try {
  $dr = $dlg.ShowDialog($ownerForm)
  return ($dr -eq [System.Windows.Forms.DialogResult]::OK -and $tb.Text.Trim() -ieq "IGNORE")
 } finally {
  try { $dlg.Dispose() } catch {}
 }
}

# Modal dialog: Tabbed Diagnostic Viewer (BIOS Cross-Check / NVRAM Raw / Disk Table) + Copy to Clipboard
function Show-GuiDiagnosticsDialog($ownerForm, $sysInfo, $step2Snap, $pal) {
 $dlg = New-Object System.Windows.Forms.Form
 $dlg.Text = U "BIOS \uAD50\uCC28 \uAC80\uC99D \uBC0F \uC2DC\uC2A4\uD15C \uC9C4\uB2E8 \uC0C1\uC138"
 $dlg.Size = New-Object System.Drawing.Size(860, 600)
 $dlg.MinimumSize = New-Object System.Drawing.Size(680, 460)
 $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
 $dlg.BackColor = $pal.AppBg
 $dlg.Font = New-Object System.Drawing.Font("Malgun Gothic", 9.5)

 $monoFont = New-Object System.Drawing.Font("Consolas", 9)

 $biosText = if ($step2Snap -and $step2Snap.BiosDiag) {
  Format-BiosCrossCheckReport $sysInfo $step2Snap.BiosDiag $step2Snap.UsbInfo $step2Snap.MatchedEntries
 } else {
  "(BIOS diagnostics not available)"
 }
 $nvramText = if ($step2Snap -and $step2Snap.BcdOutput -and $step2Snap.BcdOutput.Count -gt 0) {
  ($step2Snap.BcdOutput -join "`r`n")
 } else {
  "(No bcdedit /enum firmware output)"
 }
 $diskText = Get-DiskDebugText

 $tabs = New-Object System.Windows.Forms.TabControl
 $tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
 $tabs.Padding = New-Object System.Drawing.Point(10, 5)

 $addLogTab = {
  param([string]$title, [string]$body)
  $tp = New-Object System.Windows.Forms.TabPage
  $tp.Text = $title
  $tp.Padding = New-Object System.Windows.Forms.Padding(6)
  $tb = New-Object System.Windows.Forms.TextBox
  $tb.Multiline = $true
  $tb.ReadOnly = $true
  $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
  $tb.WordWrap = $false
  $tb.Dock = [System.Windows.Forms.DockStyle]::Fill
  $tb.Font = $monoFont
  $tb.BackColor = [System.Drawing.Color]::White
  $tb.Text = $body
  $tp.Controls.Add($tb)
  [void]$tabs.TabPages.Add($tp)
 }

 & $addLogTab (U "BIOS \uAD50\uCC28 \uAC80\uC99D \uBCF4\uACE0\uC11C") $biosText
 & $addLogTab (U "UEFI NVRAM \uC6D0\uBCF8 (bcdedit)") $nvramText
 & $addLogTab (U "\uB514\uC2A4\uD06C/\uD30C\uD2F0\uC158 \uC9C4\uB2E8") $diskText

 $bottomBar = New-Object System.Windows.Forms.Panel
 $bottomBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $bottomBar.Height = 46
 $bottomBar.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
 $bottomBar.BackColor = $pal.CardBg

 $copyPayload = $biosText + "`r`n`r`n=== [bcdedit /enum firmware] ===`r`n" + $nvramText + "`r`n`r`n=== [Disk / Partition] ===`r`n" + $diskText
 $btnCopy = New-Object System.Windows.Forms.Button
 $btnCopy.Text = U "\uC804\uCCB4 \uC9C4\uB2E8 \uACB0\uACFC \uD074\uB9BD\uBCF4\uB4DC \uBCF5\uC0AC"
 $btnCopy.Size = New-Object System.Drawing.Size(210, 30)
 $btnCopy.Dock = [System.Windows.Forms.DockStyle]::Left
 Set-GuiButtonStyle $btnCopy "PrimaryBlue" $pal
 $btnCopy.Add_Click({
  try {
   [System.Windows.Forms.Clipboard]::SetText($copyPayload)
   [System.Windows.Forms.MessageBox]::Show($dlg, (U "\uC804\uCCB4 \uC9C4\uB2E8 \uBCF4\uACE0\uC11C\uAC00 \uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uBCF5\uC0AC\uB418\uC5C8\uC2B5\uB2C8\uB2E4."), (U "\uBCF5\uC0AC \uC644\uB8CC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  } catch {
   [System.Windows.Forms.MessageBox]::Show($dlg, $_.Exception.Message, (U "\uBCF5\uC0AC \uC2E4\uD328"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
  }
 }.GetNewClosure())

 $btnClose = New-Object System.Windows.Forms.Button
 $btnClose.Text = U "\uB2EB\uAE30"
 $btnClose.Size = New-Object System.Drawing.Size(90, 30)
 $btnClose.Dock = [System.Windows.Forms.DockStyle]::Right
 Set-GuiButtonStyle $btnClose "Neutral" $pal
 $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

 $bottomBar.Controls.Add($btnCopy)
 $bottomBar.Controls.Add($btnClose)
 $dlg.Controls.Add($tabs)
 $dlg.Controls.Add($bottomBar)
 $dlg.CancelButton = $btnClose

 try {
  [void]$dlg.ShowDialog($ownerForm)
 } finally {
  try { $monoFont.Dispose() } catch {}
  try { $dlg.Dispose() } catch {}
 }
}

# Build the main WinForms Form using a single $ui reference context + .GetNewClosure()
# so EVERY event handler and FormClosed disposal stays valid after New-SidAuxMainForm returns.
function New-SidAuxMainForm($sysInfo, [bool]$autoPopulate = $true) {
 [System.Windows.Forms.Application]::EnableVisualStyles()
 $pal = Get-GuiPalette
 $srcInfo = Get-ExecutionSourceInfo
 $verStr = [string]$script:ToolVersion
 $buildMeta = [string]$script:BuildDate

 $fontRegular = New-Object System.Drawing.Font("Malgun Gothic", 9.5)
 $fontBold    = New-Object System.Drawing.Font("Malgun Gothic", 9.5, [System.Drawing.FontStyle]::Bold)
 $fontTitle   = New-Object System.Drawing.Font("Malgun Gothic", 12.5, [System.Drawing.FontStyle]::Bold)
 $fontBannerT = New-Object System.Drawing.Font("Malgun Gothic", 10.5, [System.Drawing.FontStyle]::Bold)
 $fontSmall   = New-Object System.Drawing.Font("Malgun Gothic", 8.5)
 $fontMono    = New-Object System.Drawing.Font("Consolas", 9)

 $state = @{
  SysInfo = $sysInfo
  EfiRep = $null
  Step2Snap = $null
  PostStatus = $null
  Step1Bypassed = $false
  Palette = $pal
 }

 $form = New-Object System.Windows.Forms.Form
 $form.Text = (U "SID \uBCC0\uACBD \uC0AC\uC804\u00B7\uC0AC\uD6C4 \uBCF4\uC870 \uD234") + " v" + $verStr
 $form.Size = New-Object System.Drawing.Size(1060, 810)
 $form.MinimumSize = New-Object System.Drawing.Size(940, 710)
 $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
 $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
 $form.BackColor = $pal.AppBg
 $form.Font = $fontRegular

 $toolTip = New-Object System.Windows.Forms.ToolTip
 $toolTip.AutoPopDelay = 10000
 $toolTip.InitialDelay = 250
 $toolTip.ReshowDelay = 150
 $toolTip.ShowAlways = $true

 # ==================== TOP HEADER BAR ====================
 $header = New-Object System.Windows.Forms.Panel
 $header.Dock = [System.Windows.Forms.DockStyle]::Top
 $header.Height = 66
 $header.BackColor = $pal.HeaderBg
 $header.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)

 $headerRight = New-Object System.Windows.Forms.FlowLayoutPanel
 $headerRight.Dock = [System.Windows.Forms.DockStyle]::Right
 $headerRight.AutoSize = $true
 $headerRight.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
 $headerRight.WrapContents = $false
 $headerRight.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)

 $btnTopDiag = New-Object System.Windows.Forms.Button
 $btnTopDiag.Text = U "BIOS \uAD50\uCC28 \uAC80\uC99D / \uC9C4\uB2E8 \uC0C1\uC138"
 $btnTopDiag.Size = New-Object System.Drawing.Size(172, 32)
 Set-GuiButtonStyle $btnTopDiag "Header" $pal
 $btnTopDiag.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnTopRefresh = New-Object System.Windows.Forms.Button
 $btnTopRefresh.Text = U "\uC804\uCCB4 \uC0C8\uB85C\uACE0\uCE68"
 $btnTopRefresh.Size = New-Object System.Drawing.Size(106, 32)
 Set-GuiButtonStyle $btnTopRefresh "PrimaryBlue" $pal

 $headerRight.Controls.Add($btnTopDiag)
 $headerRight.Controls.Add($btnTopRefresh)

 $headerLeft = New-Object System.Windows.Forms.Panel
 $headerLeft.Dock = [System.Windows.Forms.DockStyle]::Fill

 $lblAppTitle = New-Object System.Windows.Forms.Label
 $lblAppTitle.Text = (U "SID \uBCC0\uACBD \uC0AC\uC804\u00B7\uC0AC\uD6C4 \uBCF4\uC870 \uD234") + "  v" + $verStr + " (" + $buildMeta + ")"
 $lblAppTitle.Font = $fontTitle
 $lblAppTitle.ForeColor = $pal.HeaderFg
 $lblAppTitle.AutoSize = $true
 $lblAppTitle.Location = New-Object System.Drawing.Point(0, 2)

 $lblSysSub = New-Object System.Windows.Forms.Label
 $lblSysSub.Text = ("[" + $sysInfo.Vendor + "] " + $sysInfo.ModelName + "  |  " + (U "\uC2E4\uD589 \uC704\uCE58: ") + $srcInfo.Label)
 $lblSysSub.Font = $fontSmall
 $lblSysSub.ForeColor = $pal.HeaderSub
 $lblSysSub.AutoSize = $true
 $lblSysSub.Location = New-Object System.Drawing.Point(2, 30)

 $headerLeft.Controls.Add($lblAppTitle)
 $headerLeft.Controls.Add($lblSysSub)
 $header.Controls.Add($headerLeft)
 $header.Controls.Add($headerRight)

 # ==================== MAIN 2-TAB CONTROL ====================
 $tabControl = New-Object System.Windows.Forms.TabControl
 $tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
 $tabControl.Padding = New-Object System.Drawing.Point(16, 7)
 $tabControl.Font = $fontBold

 $tabPre = New-Object System.Windows.Forms.TabPage
 $tabPre.Text = U "  1. SID \uBCC0\uACBD \uC0AC\uC804 \uC791\uC5C5 (\uBD80\uD2B8\uB85C\uB354 \uC815\uB9AC -> USB \uBD80\uD305)  "
 $tabPre.BackColor = $pal.AppBg
 $tabPre.Padding = New-Object System.Windows.Forms.Padding(12)
 $tabPre.Font = $fontRegular

 $tabPost = New-Object System.Windows.Forms.TabPage
 $tabPost.Text = U "  2. SID \uBCC0\uACBD \uC0AC\uD6C4 \uC791\uC5C5 (\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B)  "
 $tabPost.BackColor = $pal.AppBg
 $tabPost.Padding = New-Object System.Windows.Forms.Padding(12)
 $tabPost.Font = $fontRegular

 [void]$tabControl.TabPages.Add($tabPre)
 [void]$tabControl.TabPages.Add($tabPost)

 # ==============================================================================
 # TAB 1: PRE-SID (Guidance Banner -> STEP 1 Bootloader -> STEP 2 BIOS & USB)
 # ==============================================================================
 $preRoot = New-Object System.Windows.Forms.TableLayoutPanel
 $preRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
 $preRoot.ColumnCount = 1
 $preRoot.RowCount = 3
 [void]$preRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
 [void]$preRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 86)))
 [void]$preRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 35)))
 [void]$preRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 65)))
 $tabPre.Controls.Add($preRoot)

 # Pre-SID Contextual Guidance Banner
 $preBanner = New-Object System.Windows.Forms.Panel
 $preBanner.Dock = [System.Windows.Forms.DockStyle]::Fill
 $preBanner.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
 $preBanner.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

 $preAccent = New-Object System.Windows.Forms.Panel
 $preAccent.Dock = [System.Windows.Forms.DockStyle]::Left
 $preAccent.Width = 6

 $preBannerBody = New-Object System.Windows.Forms.Panel
 $preBannerBody.Dock = [System.Windows.Forms.DockStyle]::Fill
 $preBannerBody.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 6)

 $lblPreBanTitle = New-Object System.Windows.Forms.Label
 $lblPreBanTitle.Dock = [System.Windows.Forms.DockStyle]::Top
 $lblPreBanTitle.Height = 22
 $lblPreBanTitle.Font = $fontBannerT

 $lblPreBanMsg = New-Object System.Windows.Forms.Label
 $lblPreBanMsg.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPreBanMsg.Font = $fontRegular

 $preBannerBody.Controls.Add($lblPreBanMsg)
 $preBannerBody.Controls.Add($lblPreBanTitle)
 $preBanner.Controls.Add($preBannerBody)
 $preBanner.Controls.Add($preAccent)
 $preRoot.Controls.Add($preBanner, 0, 0)

 # STEP 1 GroupBox
 $gbStep1 = New-Object System.Windows.Forms.GroupBox
 $gbStep1.Text = U " STEP 1. C\uB4DC\uB77C\uC774\uBE0C \uC678 \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80 (\uD544\uC218 \uC120\uD589 \u00B7 \uC678\uC7A5 USB/WinPE \uC790\uB3D9 \uBCF4\uD638) "
 $gbStep1.Dock = [System.Windows.Forms.DockStyle]::Fill
 $gbStep1.BackColor = $pal.CardBg
 $gbStep1.Font = $fontBold
 $gbStep1.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 8)
 $gbStep1.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

 $lvDisks = New-Object System.Windows.Forms.ListView
 $lvDisks.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lvDisks.View = [System.Windows.Forms.View]::Details
 $lvDisks.FullRowSelect = $true
 $lvDisks.GridLines = $true
 $lvDisks.HideSelection = $false
 $lvDisks.MultiSelect = $false
 $lvDisks.Font = $fontRegular
 [void]$lvDisks.Columns.Add((U "\uB514\uC2A4\uD06C"), 64)
 [void]$lvDisks.Columns.Add((U "\uBAA8\uB378\uBA85"), 225)
 [void]$lvDisks.Columns.Add((U "\uC6A9\uB7C9"), 75)
 [void]$lvDisks.Columns.Add((U "\uD30C\uD2F0\uC158 \uBC29\uC2DD"), 85)
 [void]$lvDisks.Columns.Add((U "\uB300\uC0C1 \uD30C\uD2F0\uC158"), 120)
 [void]$lvDisks.Columns.Add((U "\uBD80\uD2B8\uB85C\uB354 \uC0C1\uD0DC"), 355)

 $step1Bar = New-Object System.Windows.Forms.FlowLayoutPanel
 $step1Bar.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $step1Bar.Height = 38
 $step1Bar.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
 $step1Bar.WrapContents = $false
 $step1Bar.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
 $step1Bar.Font = $fontRegular

 $btnOneStop = New-Object System.Windows.Forms.Button
 $btnOneStop.Text = U "\uC6D0\uC2A4\uD1B1 \uC815\uB9AC (\uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uBE44\uD65C\uC131\uD654 + SSD NVRAM \uB4F1\uB85D)"
 $btnOneStop.Size = New-Object System.Drawing.Size(340, 30)
 Set-GuiButtonStyle $btnOneStop "Disabled" $pal
 $btnOneStop.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnToggleDisk = New-Object System.Windows.Forms.Button
 $btnToggleDisk.Text = U "\uC120\uD0DD \uB514\uC2A4\uD06C \uAC1C\uBCC4 \uC804\uD658 (\uBE44\uD65C\uC131\uD654/\uBCF5\uAD6C)"
 $btnToggleDisk.Size = New-Object System.Drawing.Size(225, 30)
 Set-GuiButtonStyle $btnToggleDisk "Disabled" $pal
 $btnToggleDisk.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnIgnoreStep1 = New-Object System.Windows.Forms.Button
 $btnIgnoreStep1.Text = U "\uC704\uD5D8 \uBB34\uC2DC \uD6C4 STEP 2 \uC7A0\uAE08 \uD574\uC81C (IGNORE)"
 $btnIgnoreStep1.Size = New-Object System.Drawing.Size(250, 30)
 Set-GuiButtonStyle $btnIgnoreStep1 "PrimaryAmber" $pal
 $btnIgnoreStep1.Visible = $false

 $step1Bar.Controls.Add($btnOneStop)
 $step1Bar.Controls.Add($btnToggleDisk)
 $step1Bar.Controls.Add($btnIgnoreStep1)

 $gbStep1.Controls.Add($lvDisks)
 $gbStep1.Controls.Add($step1Bar)
 $preRoot.Controls.Add($gbStep1, 0, 1)

 # STEP 2 GroupBox
 $gbStep2 = New-Object System.Windows.Forms.GroupBox
 $gbStep2.Text = U " STEP 2. BIOS \uAD50\uCC28 \uC9C4\uB2E8 \uBC0F WinPE USB \uC120\uD0DD / 1\uD68C\uC131 \uBD80\uD305 "
 $gbStep2.Dock = [System.Windows.Forms.DockStyle]::Fill
 $gbStep2.BackColor = $pal.CardBg
 $gbStep2.Font = $fontBold
 $gbStep2.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 8)

 $step2Layout = New-Object System.Windows.Forms.TableLayoutPanel
 $step2Layout.Dock = [System.Windows.Forms.DockStyle]::Fill
 $step2Layout.ColumnCount = 1
 $step2Layout.RowCount = 6
 $step2Layout.Font = $fontRegular
 [void]$step2Layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
 [void]$step2Layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
 [void]$step2Layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 68)))
 [void]$step2Layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 22)))
 [void]$step2Layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 42)))
 [void]$step2Layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 58)))
 [void]$step2Layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))

 # Lock banner (visible when STEP 1 blocks STEP 2)
 $lblStep2Lock = New-Object System.Windows.Forms.Label
 $lblStep2Lock.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblStep2Lock.AutoSize = $true
 $lblStep2Lock.BackColor = $pal.ErrBg
 $lblStep2Lock.ForeColor = $pal.ErrFg
 $lblStep2Lock.Font = $fontBold
 $lblStep2Lock.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)
 $lblStep2Lock.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
 $lblStep2Lock.Text = U "[\uC7A0\uAE40] STEP 1\uC758 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uCDA9\uB3CC\uC744 \uBA3C\uC800 \uC815\uB9AC\uD558\uAC70\uB098 IGNORE \uD655\uC778 \uD6C4\uC5D0\uB9CC USB \uBD80\uD305\uC774 \uD65C\uC131\uD654\uB429\uB2C8\uB2E4."
 $lblStep2Lock.Visible = $false
 $step2Layout.Controls.Add($lblStep2Lock, 0, 0)

 # BIOS Cross-Check Strip
 $biosStrip = New-Object System.Windows.Forms.Panel
 $biosStrip.Dock = [System.Windows.Forms.DockStyle]::Fill
 $biosStrip.BackColor = $pal.RowAlt
 $biosStrip.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
 $biosStrip.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 4)
 $biosStrip.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)

 $biosPills = New-Object System.Windows.Forms.FlowLayoutPanel
 $biosPills.Dock = [System.Windows.Forms.DockStyle]::Top
 $biosPills.Height = 32
 $biosPills.WrapContents = $false

 $lblPillSec = New-Object System.Windows.Forms.Label
 $lblPillSec.AutoSize = $true
 $lblPillSec.Font = $fontBold
 $lblPillSec.Padding = New-Object System.Windows.Forms.Padding(7, 3, 7, 3)
 $lblPillSec.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $lblPillUsb = New-Object System.Windows.Forms.Label
 $lblPillUsb.AutoSize = $true
 $lblPillUsb.Font = $fontBold
 $lblPillUsb.Padding = New-Object System.Windows.Forms.Padding(7, 3, 7, 3)
 $lblPillUsb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $lblPillFast = New-Object System.Windows.Forms.Label
 $lblPillFast.AutoSize = $true
 $lblPillFast.Font = $fontBold
 $lblPillFast.Padding = New-Object System.Windows.Forms.Padding(7, 3, 7, 3)
 $lblPillFast.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnInlineDiag = New-Object System.Windows.Forms.Button
 $btnInlineDiag.Text = U "\uAD50\uCC28 \uAC80\uC99D \uC0C1\uC138"
 $btnInlineDiag.Size = New-Object System.Drawing.Size(102, 24)
 $btnInlineDiag.Font = $fontSmall
 Set-GuiButtonStyle $btnInlineDiag "Neutral" $pal
 $btnInlineDiag.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)

 $biosPills.Controls.Add($lblPillSec)
 $biosPills.Controls.Add($lblPillUsb)
 $biosPills.Controls.Add($lblPillFast)
 $biosPills.Controls.Add($btnInlineDiag)

 $lblBiosHint = New-Object System.Windows.Forms.Label
 $lblBiosHint.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $lblBiosHint.Height = 22
 $lblBiosHint.Font = $fontSmall
 $lblBiosHint.ForeColor = $pal.TextMuted
 $lblBiosHint.Text = ("BIOS Hint: " + $sysInfo.BiosHint)

 $biosStrip.Controls.Add($biosPills)
 $biosStrip.Controls.Add($lblBiosHint)
 $step2Layout.Controls.Add($biosStrip, 0, 1)

 # Sub-label for Physical USB
 $lblPhysHdr = New-Object System.Windows.Forms.Label
 $lblPhysHdr.Text = U "[2-1] \uD604\uC7AC \uC5F0\uACB0\uB41C \uBB3C\uB9AC USB \uB514\uC2A4\uD06C"
 $lblPhysHdr.Font = $fontBold
 $lblPhysHdr.ForeColor = $pal.TextDark
 $lblPhysHdr.Dock = [System.Windows.Forms.DockStyle]::Fill
 $step2Layout.Controls.Add($lblPhysHdr, 0, 2)

 # Physical USB ListView (columns sized to avoid horizontal scrollbar at default width)
 $lvPhysUsb = New-Object System.Windows.Forms.ListView
 $lvPhysUsb.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lvPhysUsb.View = [System.Windows.Forms.View]::Details
 $lvPhysUsb.FullRowSelect = $true
 $lvPhysUsb.GridLines = $true
 $lvPhysUsb.HideSelection = $false
 $lvPhysUsb.MultiSelect = $false
 $lvPhysUsb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
 [void]$lvPhysUsb.Columns.Add((U "\uB514\uC2A4\uD06C"), 62)
 [void]$lvPhysUsb.Columns.Add((U "USB \uBAA8\uB378\uBA85"), 220)
 [void]$lvPhysUsb.Columns.Add((U "\uC6A9\uB7C9"), 75)
 [void]$lvPhysUsb.Columns.Add((U "\uD30C\uD2F0\uC158 \uAD6C\uC131"), 315)
 [void]$lvPhysUsb.Columns.Add((U "\uC18D\uC131"), 82)
 [void]$lvPhysUsb.Columns.Add((U "UEFI \uBD80\uD305"), 125)
 $step2Layout.Controls.Add($lvPhysUsb, 0, 3)

 # NVRAM USB Panel (header + ListView)
 $nvramBox = New-Object System.Windows.Forms.Panel
 $nvramBox.Dock = [System.Windows.Forms.DockStyle]::Fill
 $nvramBox.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)

 $lblNvramHdr = New-Object System.Windows.Forms.Label
 $lblNvramHdr.Text = U "[2-2] \uBD80\uD305 \uAC00\uB2A5\uD55C UEFI USB \uB300\uC0C1 \uC120\uD0DD (NVRAM \uAD50\uCC28 \uB9E4\uCE6D \uACB0\uACFC)"
 $lblNvramHdr.Font = $fontBold
 $lblNvramHdr.ForeColor = $pal.TextDark
 $lblNvramHdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $lblNvramHdr.Height = 20

 $lvNvramUsb = New-Object System.Windows.Forms.ListView
 $lvNvramUsb.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lvNvramUsb.View = [System.Windows.Forms.View]::Details
 $lvNvramUsb.FullRowSelect = $true
 $lvNvramUsb.GridLines = $true
 $lvNvramUsb.HideSelection = $false
 $lvNvramUsb.MultiSelect = $false
 [void]$lvNvramUsb.Columns.Add((U "\uBC88\uD638"), 48)
 [void]$lvNvramUsb.Columns.Add((U "\uB9E4\uCE6D \uC2E0\uB8B0\uB3C4"), 145)
 [void]$lvNvramUsb.Columns.Add((U "\uBD80\uD305 \uD56D\uBAA9 \uC774\uB984 (Description)"), 325)
 [void]$lvNvramUsb.Columns.Add((U "\uC7A5\uCE58 (Device)"), 155)
 [void]$lvNvramUsb.Columns.Add("GUID", 235)

 $nvramBox.Controls.Add($lvNvramUsb)
 $nvramBox.Controls.Add($lblNvramHdr)
 $step2Layout.Controls.Add($nvramBox, 0, 4)

 # STEP 2 Bottom Action Buttons
 $step2Bar = New-Object System.Windows.Forms.FlowLayoutPanel
 $step2Bar.Dock = [System.Windows.Forms.DockStyle]::Fill
 $step2Bar.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
 $step2Bar.WrapContents = $false
 $step2Bar.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

 $btnUsbReboot = New-Object System.Windows.Forms.Button
 $btnUsbReboot.Text = U "\uC120\uD0DD\uD55C USB\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305"
 $btnUsbReboot.Size = New-Object System.Drawing.Size(220, 32)
 $btnUsbReboot.Font = $fontBold
 Set-GuiButtonStyle $btnUsbReboot "Disabled" $pal
 $btnUsbReboot.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnAdvBoot = New-Object System.Windows.Forms.Button
 $btnAdvBoot.Text = U "Windows \uACE0\uAE09 \uBD80\uD305('\uC7A5\uCE58 \uC0AC\uC6A9')"
 $btnAdvBoot.Size = New-Object System.Drawing.Size(220, 32)
 Set-GuiButtonStyle $btnAdvBoot "Disabled" $pal
 $btnAdvBoot.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnBiosBoot = New-Object System.Windows.Forms.Button
 $btnBiosBoot.Text = U "BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815 \uC9C4\uC785"
 $btnBiosBoot.Size = New-Object System.Drawing.Size(172, 32)
 Set-GuiButtonStyle $btnBiosBoot "Disabled" $pal
 $btnBiosBoot.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnRescanUsb = New-Object System.Windows.Forms.Button
 $btnRescanUsb.Text = U "USB \uB2E4\uC2DC \uC2A4\uCE94"
 $btnRescanUsb.Size = New-Object System.Drawing.Size(116, 32)
 Set-GuiButtonStyle $btnRescanUsb "Neutral" $pal

 $step2Bar.Controls.Add($btnUsbReboot)
 $step2Bar.Controls.Add($btnAdvBoot)
 $step2Bar.Controls.Add($btnBiosBoot)
 $step2Bar.Controls.Add($btnRescanUsb)
 $step2Layout.Controls.Add($step2Bar, 0, 5)

 $gbStep2.Controls.Add($step2Layout)
 $preRoot.Controls.Add($gbStep2, 0, 2)

 # ==============================================================================
 # TAB 2: POST-SID (Guidance Banner -> Status Card -> Printers -> Reset & Log)
 # ==============================================================================
 $postRoot = New-Object System.Windows.Forms.TableLayoutPanel
 $postRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
 $postRoot.ColumnCount = 1
 $postRoot.RowCount = 4
 [void]$postRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 86)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 134)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 52)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 48)))
 $tabPost.Controls.Add($postRoot)

 # Post-SID Contextual Guidance Banner
 $postBanner = New-Object System.Windows.Forms.Panel
 $postBanner.Dock = [System.Windows.Forms.DockStyle]::Fill
 $postBanner.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
 $postBanner.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

 $postAccent = New-Object System.Windows.Forms.Panel
 $postAccent.Dock = [System.Windows.Forms.DockStyle]::Left
 $postAccent.Width = 6

 $postBannerBody = New-Object System.Windows.Forms.Panel
 $postBannerBody.Dock = [System.Windows.Forms.DockStyle]::Fill
 $postBannerBody.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 6)

 $lblPostBanTitle = New-Object System.Windows.Forms.Label
 $lblPostBanTitle.Dock = [System.Windows.Forms.DockStyle]::Top
 $lblPostBanTitle.Height = 22
 $lblPostBanTitle.Font = $fontBannerT

 $lblPostBanMsg = New-Object System.Windows.Forms.Label
 $lblPostBanMsg.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPostBanMsg.Font = $fontRegular

 $postBannerBody.Controls.Add($lblPostBanMsg)
 $postBannerBody.Controls.Add($lblPostBanTitle)
 $postBanner.Controls.Add($postBannerBody)
 $postBanner.Controls.Add($postAccent)
 $postRoot.Controls.Add($postBanner, 0, 0)

 # Post-SID Status Summary Card
 $gbPostInfo = New-Object System.Windows.Forms.GroupBox
 $gbPostInfo.Text = U " PC \uC5ED\uD560 \uBC0F \uC2A4\uD480\uB7EC/\uB124\uD2B8\uC6CC\uD06C \uC0C1\uD0DC \uC9C4\uB2E8 "
 $gbPostInfo.Dock = [System.Windows.Forms.DockStyle]::Fill
 $gbPostInfo.BackColor = $pal.CardBg
 $gbPostInfo.Font = $fontBold
 $gbPostInfo.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 6)
 $gbPostInfo.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

 $postGrid = New-Object System.Windows.Forms.TableLayoutPanel
 $postGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
 $postGrid.ColumnCount = 2
 $postGrid.RowCount = 4
 $postGrid.Font = $fontRegular
 [void]$postGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
 [void]$postGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
 for ($r = 0; $r -lt 4; $r++) {
  [void]$postGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 25)))
 }

 $lblPostRole   = New-Object System.Windows.Forms.Label; $lblPostRole.Dock = [System.Windows.Forms.DockStyle]::Fill; $lblPostRole.Font = $fontBold
 $lblPostComp   = New-Object System.Windows.Forms.Label; $lblPostComp.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPostSpool  = New-Object System.Windows.Forms.Label; $lblPostSpool.Dock = [System.Windows.Forms.DockStyle]::Fill; $lblPostSpool.Font = $fontBold
 $lblPostQueue  = New-Object System.Windows.Forms.Label; $lblPostQueue.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPostSid    = New-Object System.Windows.Forms.Label; $lblPostSid.Dock = [System.Windows.Forms.DockStyle]::Fill; $lblPostSid.ForeColor = $pal.TextMuted
 $lblPostExtra1 = New-Object System.Windows.Forms.Label; $lblPostExtra1.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPostExtra2 = New-Object System.Windows.Forms.Label; $lblPostExtra2.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPostNote   = New-Object System.Windows.Forms.Label; $lblPostNote.Dock = [System.Windows.Forms.DockStyle]::Fill; $lblPostNote.ForeColor = $pal.TextMuted
 $lblPostNote.Text = U "\uC548\uB0B4: \uAE30\uC874 \uD504\uB9B0\uD130, \uB4DC\uB77C\uC774\uBC84, \uACF5\uC720 \uC124\uC815\uC740 \uC0AD\uC81C\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4."

 $postGrid.Controls.Add($lblPostRole, 0, 0)
 $postGrid.Controls.Add($lblPostComp, 1, 0)
 $postGrid.Controls.Add($lblPostSpool, 0, 1)
 $postGrid.Controls.Add($lblPostQueue, 1, 1)
 $postGrid.Controls.Add($lblPostExtra1, 0, 2)
 $postGrid.Controls.Add($lblPostExtra2, 1, 2)
 $postGrid.Controls.Add($lblPostSid, 0, 3)
 $postGrid.Controls.Add($lblPostNote, 1, 3)
 $gbPostInfo.Controls.Add($postGrid)
 $postRoot.Controls.Add($gbPostInfo, 0, 1)

 # Printers ListView
 $gbPrinters = New-Object System.Windows.Forms.GroupBox
 $gbPrinters.Text = U " \uC124\uCE58\uB41C \uD504\uB9B0\uD130 \uBC0F \uACF5\uC720/\uB124\uD2B8\uC6CC\uD06C \uC5F0\uACB0 \uBAA9\uB85D "
 $gbPrinters.Dock = [System.Windows.Forms.DockStyle]::Fill
 $gbPrinters.BackColor = $pal.CardBg
 $gbPrinters.Font = $fontBold
 $gbPrinters.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 8)
 $gbPrinters.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

 $lvPrinters = New-Object System.Windows.Forms.ListView
 $lvPrinters.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lvPrinters.View = [System.Windows.Forms.View]::Details
 $lvPrinters.FullRowSelect = $true
 $lvPrinters.GridLines = $true
 $lvPrinters.Font = $fontRegular
 [void]$lvPrinters.Columns.Add((U "\uD504\uB9B0\uD130 \uC774\uB984"), 265)
 [void]$lvPrinters.Columns.Add((U "\uC720\uD615"), 110)
 [void]$lvPrinters.Columns.Add((U "\uACF5\uC720 \uACBD\uB85C / \uC6D0\uACA9 \uD638\uC2A4\uD2B8"), 220)
 [void]$lvPrinters.Columns.Add((U "\uD3EC\uD2B8"), 155)
 [void]$lvPrinters.Columns.Add((U "\uBE44\uACE0"), 165)
 $gbPrinters.Controls.Add($lvPrinters)
 $postRoot.Controls.Add($gbPrinters, 0, 2)

 # Post-SID Action & Live Log Panel
 $gbReset = New-Object System.Windows.Forms.GroupBox
 $gbReset.Text = U " \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589 \uBC0F \uACB0\uACFC \uB85C\uADF8 "
 $gbReset.Dock = [System.Windows.Forms.DockStyle]::Fill
 $gbReset.BackColor = $pal.CardBg
 $gbReset.Font = $fontBold
 $gbReset.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 8)

 $resetBar = New-Object System.Windows.Forms.FlowLayoutPanel
 $resetBar.Dock = [System.Windows.Forms.DockStyle]::Top
 $resetBar.Height = 42
 $resetBar.WrapContents = $false
 $resetBar.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 6)
 $resetBar.Font = $fontRegular

 $btnSpoolerReset = New-Object System.Windows.Forms.Button
 $btnSpoolerReset.Text = U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589 (\uB300\uAE30\uC5F4 \uBE44\uC6B0\uAE30 + \uC11C\uBE44\uC2A4 \uC7AC\uC2DC\uC791)"
 $btnSpoolerReset.Size = New-Object System.Drawing.Size(390, 34)
 $btnSpoolerReset.Font = $fontBold
 Set-GuiButtonStyle $btnSpoolerReset "PrimaryGreen" $pal
 $btnSpoolerReset.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)

 $btnPostRefresh = New-Object System.Windows.Forms.Button
 $btnPostRefresh.Text = U "\uC0C1\uD0DC \uC0C8\uB85C\uACE0\uCE68"
 $btnPostRefresh.Size = New-Object System.Drawing.Size(120, 34)
 Set-GuiButtonStyle $btnPostRefresh "Neutral" $pal

 $resetBar.Controls.Add($btnSpoolerReset)
 $resetBar.Controls.Add($btnPostRefresh)

 $tbResetLog = New-Object System.Windows.Forms.TextBox
 $tbResetLog.Dock = [System.Windows.Forms.DockStyle]::Fill
 $tbResetLog.Multiline = $true
 $tbResetLog.ReadOnly = $true
 $tbResetLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
 $tbResetLog.Font = $fontMono
 $tbResetLog.BackColor = $pal.RowAlt
 $tbResetLog.Text = U "[\uB300\uAE30] \uC704 [\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC2E4\uD589] \uBC84\uD2BC\uC744 \uB204\uB974\uBA74 \uC9C4\uD589 \uACFC\uC815\uACFC \uACB0\uACFC\uAC00 \uC5EC\uAE30\uC5D0 \uD45C\uC2DC\uB429\uB2C8\uB2E4."

 $gbReset.Controls.Add($tbResetLog)
 $gbReset.Controls.Add($resetBar)
 $postRoot.Controls.Add($gbReset, 0, 3)

 $form.Controls.Add($tabControl)
 $form.Controls.Add($header)

 # ==================== SINGLE SHARED UI CONTEXT ($ui) ====================
 # Held by reference in $form.Tag and captured by .GetNewClosure() across all handlers
 $ui = @{
  Form            = $form
  Pal             = $pal
  SrcInfo         = $srcInfo
  State           = $state
  ToolTip         = $toolTip
  LblSysSub       = $lblSysSub
  PreBanner       = $preBanner
  PreAccent       = $preAccent
  LblPreBanTitle  = $lblPreBanTitle
  LblPreBanMsg    = $lblPreBanMsg
  LvDisks         = $lvDisks
  BtnOneStop      = $btnOneStop
  BtnToggleDisk   = $btnToggleDisk
  BtnIgnoreStep1  = $btnIgnoreStep1
  LblStep2Lock    = $lblStep2Lock
  LblPillSec      = $lblPillSec
  LblPillUsb      = $lblPillUsb
  LblPillFast     = $lblPillFast
  LvPhysUsb       = $lvPhysUsb
  LvNvramUsb      = $lvNvramUsb
  BtnUsbReboot    = $btnUsbReboot
  BtnAdvBoot      = $btnAdvBoot
  BtnBiosBoot     = $btnBiosBoot
  PostBanner      = $postBanner
  PostAccent      = $postAccent
  LblPostBanTitle = $lblPostBanTitle
  LblPostBanMsg   = $lblPostBanMsg
  LblPostRole     = $lblPostRole
  LblPostComp     = $lblPostComp
  LblPostSid      = $lblPostSid
  LblPostSpool    = $lblPostSpool
  LblPostQueue    = $lblPostQueue
  LblPostExtra1   = $lblPostExtra1
  LblPostExtra2   = $lblPostExtra2
  LvPrinters      = $lvPrinters
  BtnSpoolerReset = $btnSpoolerReset
  BtnPostRefresh  = $btnPostRefresh
  TbResetLog      = $tbResetLog
  Disposables     = @($toolTip, $fontRegular, $fontBold, $fontTitle, $fontBannerT, $fontSmall, $fontMono)
 }
 $form.Tag = $ui

 # ==================== REFRESH / RENDER LOGIC (CLOSURE-SAFE) ====================
 $ui.RefreshPreSid = {
  $u = $ui
  $p = $u.Pal
  $st = $u.State
  $u.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
  try {
   $efiRep = Get-InternalBootloaderReport $false
   $snap = Get-PreSidStep2Snapshot $st.SysInfo
   $st.EfiRep = $efiRep
   $st.Step2Snap = $snap
   if (-not $efiRep.HasBlockingRisk) { $st.Step1Bypassed = $false }

   $bootModeStr = $snap.BiosDiag.BootMode.Mode + " (" + $snap.BiosDiag.BootMode.Confidence + ")"
   $u.LblSysSub.Text = ("[" + $st.SysInfo.Vendor + "] " + $st.SysInfo.ModelName + "  |  " + (U "\uBD80\uD305 \uBAA8\uB4DC: ") + $bootModeStr + "  |  " + (U "\uC2E4\uD589 \uC704\uCE58: ") + $u.SrcInfo.Label)

   # 1. Populate STEP 1 Internal Disks ListView
   $u.LvDisks.BeginUpdate()
   $u.LvDisks.Items.Clear()
   foreach ($it in $efiRep.Items) {
    $partStr = if ($it.TargetPart -gt 0) { $it.BootType + " #" + $it.TargetPart } else { "-" }
    $stText = Format-BootloaderStateText $it
    $lvi = New-Object System.Windows.Forms.ListViewItem(("Disk " + $it.DiskNumber))
    [void]$lvi.SubItems.Add([string]$it.Model)
    [void]$lvi.SubItems.Add(([string]$it.SizeGB + " GB"))
    [void]$lvi.SubItems.Add([string]$it.PartitionStyle)
    [void]$lvi.SubItems.Add($partStr)
    [void]$lvi.SubItems.Add($stText)
    $lvi.Tag = $it
    if ($it.State -in @("ACTIVE","BOTH","MBR_OS_BLOCKED")) {
     $lvi.BackColor = $p.ErrBg; $lvi.ForeColor = $p.ErrFg
    } elseif ($it.IsProtected) {
     $lvi.BackColor = $p.OkBg; $lvi.ForeColor = $p.OkFg
    } elseif ($it.State -eq "DISABLED") {
     $lvi.BackColor = $p.InfoBg; $lvi.ForeColor = $p.InfoFg
    }
    [void]$u.LvDisks.Items.Add($lvi)
   }
   $u.LvDisks.EndUpdate()

   $canAutoFix = (-not $efiRep.SplitBoot) -and ($efiRep.ActionableConflictItems.Count -gt 0)
   $u.BtnOneStop.Enabled = $canAutoFix
   if ($canAutoFix) { Set-GuiButtonStyle $u.BtnOneStop "PrimaryRed" $p } else { Set-GuiButtonStyle $u.BtnOneStop "Disabled" $p }
   $u.BtnToggleDisk.Enabled = $false
   Set-GuiButtonStyle $u.BtnToggleDisk "Disabled" $p
   $u.BtnIgnoreStep1.Visible = ($efiRep.HasBlockingRisk -and -not $st.Step1Bypassed)

   # 2. STEP 2 Lock state & BIOS Pills
   $isStep2Locked = ($efiRep.HasBlockingRisk -and -not $st.Step1Bypassed)
   $isUefi = [bool]$snap.BiosDiag.BootMode.IsUefi
   $u.LblStep2Lock.Visible = $isStep2Locked

   $d = $snap.BiosDiag
   switch ($d.SecureBootState) {
    "On"       { $u.LblPillSec.Text = "Secure Boot: ON (" + $d.SecureBootConfidence + ")"; $u.LblPillSec.BackColor = $p.ErrBg; $u.LblPillSec.ForeColor = $p.ErrFg }
    "Conflict" { $u.LblPillSec.Text = (U "Secure Boot: \uC2E0\uD638 \uCDA9\uB3CC(\uACBD\uACE0)"); $u.LblPillSec.BackColor = $p.ErrBg; $u.LblPillSec.ForeColor = $p.ErrFg }
    "Off"      { $u.LblPillSec.Text = "Secure Boot: OFF (" + $d.SecureBootConfidence + ")"; $u.LblPillSec.BackColor = $p.OkBg; $u.LblPillSec.ForeColor = $p.OkFg }
    default    { $u.LblPillSec.Text = (U "Secure Boot: \uD655\uC778 \uBD88\uAC00"); $u.LblPillSec.BackColor = $p.WarnBg; $u.LblPillSec.ForeColor = $p.WarnFg }
   }

   if ($d.UsbBootState -eq "Enabled") {
    $u.LblPillUsb.Text = "BIOS USB Boot: ON (" + $d.UsbBootConfidence + ")"
    $u.LblPillUsb.BackColor = $p.OkBg; $u.LblPillUsb.ForeColor = $p.OkFg
   } elseif ($d.IsConfirmedBlocked) {
    $u.LblPillUsb.Text = "BIOS USB Boot: OFF (" + $d.UsbBootConfidence + ")"
    $u.LblPillUsb.BackColor = $p.ErrBg; $u.LblPillUsb.ForeColor = $p.ErrFg
   } elseif ($d.UsbBootState -eq "Conflict") {
    $u.LblPillUsb.Text = U "BIOS USB Boot: \uAD50\uCC28 \uAC80\uC99D \uCDA9\uB3CC(\uC0C1\uC138 \uD655\uC778)"
    $u.LblPillUsb.BackColor = $p.WarnBg; $u.LblPillUsb.ForeColor = $p.WarnFg
   } elseif ($d.UsbBootState -eq "SuspectedDisabled") {
    $u.LblPillUsb.Text = U "BIOS USB Boot: \uBBF8\uB4F1\uB85D(Hot-Plug/\uCC28\uB2E8 \uAC00\uB2A5)"
    $u.LblPillUsb.BackColor = $p.WarnBg; $u.LblPillUsb.ForeColor = $p.WarnFg
   } else {
    $u.LblPillUsb.Text = (U "BIOS USB Boot: \uD655\uC778 \uBD88\uAC00") + " (" + $d.UsbBootConfidence + ")"
    $u.LblPillUsb.BackColor = $p.WarnBg; $u.LblPillUsb.ForeColor = $p.WarnFg
   }

   if ($d.FastBootWarn) {
    $u.LblPillFast.Text = U "Fast Boot: \uC8FC\uC758(\uD65C\uC131)"
    $u.LblPillFast.BackColor = $p.WarnBg; $u.LblPillFast.ForeColor = $p.WarnFg
   } else {
    $u.LblPillFast.Text = U "Fast Boot: \uC815\uC0C1/\uBBF8\uAC10\uC9C0"
    $u.LblPillFast.BackColor = $p.BtnNeutral; $u.LblPillFast.ForeColor = $p.TextMuted
   }

   $u.ToolTip.SetToolTip($u.LblPillSec, ($d.SecureBootSignals -join "`r`n"))
   $u.ToolTip.SetToolTip($u.LblPillUsb, $d.UsbBootDetail)
   $u.ToolTip.SetToolTip($u.LblPillFast, $(if ($d.FastBootDetail) { $d.FastBootDetail } else { U "Fast Boot \uACBD\uACE0 \uC5C6\uC74C" }))

   # 3. Populate Physical USB ListView
   $u.LvPhysUsb.BeginUpdate()
   $u.LvPhysUsb.Items.Clear()
   if ($snap.UsbInfo.PhysicalUsbList.Count -eq 0) {
    $emptyItem = New-Object System.Windows.Forms.ListViewItem("-")
    [void]$emptyItem.SubItems.Add((U "\uD604\uC7AC \uC5F0\uACB0\uB41C \uC678\uC7A5 USB \uB514\uC2A4\uD06C\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4 (WinPE USB \uC5F0\uACB0 \uD6C4 \uB2E4\uC2DC \uC2A4\uCE94)"))
    [void]$emptyItem.SubItems.Add("-")
    [void]$emptyItem.SubItems.Add("-")
    [void]$emptyItem.SubItems.Add("-")
    [void]$emptyItem.SubItems.Add("-")
    $emptyItem.ForeColor = $p.TextMuted
    [void]$u.LvPhysUsb.Items.Add($emptyItem)
   } else {
    foreach ($ud in $snap.UsbInfo.PhysicalUsbList) {
     $roStr = if ($ud.IsReadOnly) { U "\uC77D\uAE30 \uC804\uC6A9" } else { U "\uC77C\uBC18" }
     $efiStr = if ($ud.IsEfiReady) { U "UEFI \uBD80\uD305 \uAC00\uB2A5" } else { U "EFI \uBBF8\uD655\uC778" }
     $lvi = New-Object System.Windows.Forms.ListViewItem(("Disk " + $ud.DiskNumber))
     [void]$lvi.SubItems.Add([string]$ud.Model)
     [void]$lvi.SubItems.Add([string]$ud.SizeGB)
     [void]$lvi.SubItems.Add($(if ($ud.Partitions) { [string]$ud.Partitions } else { "-" }))
     [void]$lvi.SubItems.Add($roStr)
     [void]$lvi.SubItems.Add($efiStr)
     if ($ud.IsEfiReady) { $lvi.BackColor = $p.OkBg; $lvi.ForeColor = $p.OkFg }
     else { $lvi.BackColor = $p.WarnBg; $lvi.ForeColor = $p.WarnFg }
     [void]$u.LvPhysUsb.Items.Add($lvi)
    }
   }
   $u.LvPhysUsb.EndUpdate()

   # 4. Populate NVRAM Matched USB ListView
   $u.LvNvramUsb.BeginUpdate()
   $u.LvNvramUsb.Items.Clear()
   if ($snap.MatchedEntries.Count -eq 0) {
    $noM = New-Object System.Windows.Forms.ListViewItem("-")
    [void]$noM.SubItems.Add((U "\uB9E4\uCE6D 0\uAC74"))
    $hintRow = if ($snap.UsbInfo.PhysicalUsbList.Count -eq 0) {
     U "USB\uB97C \uC5F0\uACB0\uD55C \uB4A4 [USB \uB2E4\uC2DC \uC2A4\uCE94] \uBC84\uD2BC\uC744 \uB204\uB974\uC138\uC694."
    } else {
     U "NVRAM \uBBF8\uB4F1\uB85D: \uC544\uB798 [Windows \uACE0\uAE09 \uBD80\uD305('\uC7A5\uCE58 \uC0AC\uC6A9')] \uB610\uB294 [BIOS \uC124\uC815 \uC9C4\uC785]\uC744 \uC0AC\uC6A9\uD558\uC138\uC694."
    }
    [void]$noM.SubItems.Add($hintRow)
    [void]$noM.SubItems.Add("-")
    [void]$noM.SubItems.Add("-")
    $noM.ForeColor = $p.TextMuted
    [void]$u.LvNvramUsb.Items.Add($noM)
   } else {
    for ($i = 0; $i -lt $snap.MatchedEntries.Count; $i++) {
     $m = $snap.MatchedEntries[$i]
     $devStr = if ($m.Device) { [string]$m.Device } else { "UEFI NVRAM" }
     $lvi = New-Object System.Windows.Forms.ListViewItem([string]($i + 1))
     [void]$lvi.SubItems.Add([string]$m.MatchTag)
     [void]$lvi.SubItems.Add([string]$m.Description)
     [void]$lvi.SubItems.Add($devStr)
     [void]$lvi.SubItems.Add([string]$m.Identifier)
     $lvi.Tag = $m
     if ($m.IsExact) { $lvi.BackColor = $p.OkBg; $lvi.ForeColor = $p.OkFg }
     else { $lvi.BackColor = $p.WarnBg; $lvi.ForeColor = $p.WarnFg }
     [void]$u.LvNvramUsb.Items.Add($lvi)
    }
    if ($u.LvNvramUsb.Items.Count -gt 0) { $u.LvNvramUsb.Items[0].Selected = $true }
   }
   $u.LvNvramUsb.EndUpdate()

   # 5. Update Contextual Recommendation Banner & Dynamic Primary Button Highlighting
   $guid = Get-PreSidGuidance $st.SysInfo $efiRep $snap.BiosDiag $snap.UsbInfo $snap.MatchedEntries $st.Step1Bypassed
   Set-BannerVisual $u.PreBanner $u.PreAccent $u.LblPreBanTitle $u.LblPreBanMsg $guid $p

   $canStep2Act = ($isUefi -and -not $isStep2Locked)
   $canUsbReboot = ($canStep2Act -and $snap.MatchedEntries.Count -gt 0)
   $u.BtnUsbReboot.Enabled = $canUsbReboot
   $u.BtnAdvBoot.Enabled = $canStep2Act
   $u.BtnBiosBoot.Enabled = $canStep2Act

   Set-GuiButtonStyle $u.BtnUsbReboot $(if ($canUsbReboot) { "Neutral" } else { "Disabled" }) $p
   Set-GuiButtonStyle $u.BtnAdvBoot $(if ($canStep2Act) { "Neutral" } else { "Disabled" }) $p
   Set-GuiButtonStyle $u.BtnBiosBoot $(if ($canStep2Act) { "Neutral" } else { "Disabled" }) $p
   if ($canStep2Act) {
    switch ($guid.RecommendedAction) {
     "USB_REBOOT" { if ($canUsbReboot) { Set-GuiButtonStyle $u.BtnUsbReboot "PrimaryGreen" $p } }
     "ADV_BOOT"   { Set-GuiButtonStyle $u.BtnAdvBoot "PrimaryBlue" $p }
     "BIOS_SETUP" { Set-GuiButtonStyle $u.BtnBiosBoot "PrimaryAmber" $p }
    }
   }
  } finally {
   if (-not $u.Form.IsDisposed) { $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
  }
 }.GetNewClosure()

 $ui.RefreshPostSid = {
  $u = $ui
  $p = $u.Pal
  $u.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
  try {
   $ps = Get-PostSidStatus
   $u.State.PostStatus = $ps
   $guid = Get-PostSidGuidance $ps
   Set-BannerVisual $u.PostBanner $u.PostAccent $u.LblPostBanTitle $u.LblPostBanMsg $guid $p

   $roleText = switch ($ps.Role) {
    "Host"   { U "[\uD638\uC2A4\uD2B8(\uBA54\uC778 \uD504\uB9B0\uD130 PC)]" }
    "Client" { U "[\uD074\uB77C\uC774\uC5B8\uD2B8 PC]" }
    default  { U "[\uD310\uBCC4 \uBCF4\uB958 (Spooler \uC911\uC9C0\uB428)]" }
   }
   $u.LblPostRole.Text = (U "PC \uC5ED\uD560: ") + $roleText
   $u.LblPostRole.ForeColor = if ($ps.Role -eq "Host") { $p.InfoFg } elseif ($ps.Role -eq "Client") { $p.OkFg } else { $p.WarnFg }
   $u.LblPostComp.Text = (U "\uCEF4\uD4E8\uD130 \uC774\uB984: ") + $ps.ComputerName
   $u.LblPostSid.Text  = "Machine SID: " + $ps.MachineSid

   $spTxt = $ps.SpoolerStatus + " / " + $ps.SpoolerStartMode
   $u.LblPostSpool.Text = (U "Spooler \uC11C\uBE44\uC2A4: ") + $spTxt
   $u.LblPostSpool.ForeColor = if ($ps.SpoolerStatus -eq "Running" -and $ps.SpoolerStartMode -ne "Disabled" -and -not $ps.PrinterQueryError) { $p.OkFg } else { $p.ErrFg }
   $u.LblPostQueue.Text = (U "\uB300\uAE30\uC5F4 \uD30C\uC77C(PRINTERS): ") + $ps.QueueTotalCount + (U "\uAC74") + " (SPL/SHD: " + $ps.QueueSplShdCount + (U "\uAC74") + ")"

   if ($ps.Role -eq "Host") {
    $fwStr = if ($ps.FirewallInboundTotal -lt 0) { U "\uC870\uD68C \uBD88\uAC00" } else { [string]$ps.FirewallInboundEnabled + "/" + [string]$ps.FirewallInboundTotal + (U " \uD65C\uC131\uD654") }
    $u.LblPostExtra1.Text = (U "\uACF5\uC720 \uBC29\uD654\uBCBD \uADDC\uCE59: ") + $fwStr
    $u.LblPostExtra1.ForeColor = if ($ps.FirewallInboundEnabled -eq 0) { $p.ErrFg } else { $p.OkFg }

    $profStr = if ($ps.NetworkProfiles.Count -gt 0) {
     (($ps.NetworkProfiles | ForEach-Object { $_.InterfaceAlias + "=" + $_.Category }) -join ", ")
    } else { "-" }
    $u.LblPostExtra2.Text = (U "\uB124\uD2B8\uC6CC\uD06C \uD504\uB85C\uD544: ") + $profStr
    $u.LblPostExtra2.ForeColor = if ($ps.HasPublicProfile) { $p.ErrFg } else { $p.OkFg }
   } else {
    $hostChecks = if ($ps.RemoteHostChecks.Count -gt 0) {
     (($ps.RemoteHostChecks | ForEach-Object { "\\" + $_.Server + " (" + $(if ($_.Reachable) { "SMB OK" } else { "NO RESPONSE" }) + ")" }) -join ", ")
    } else { U "\uC5F0\uACB0\uB41C \uC6D0\uACA9 \uD504\uB9B0\uD130 \uD638\uC2A4\uD2B8 \uC5C6\uC74C" }
    $u.LblPostExtra1.Text = (U "\uC6D0\uACA9 \uD638\uC2A4\uD2B8 \uC751\uB2F5(445): ") + $hostChecks
    $hasFail = @($ps.RemoteHostChecks | Where-Object { -not $_.Reachable }).Count -gt 0
    $u.LblPostExtra1.ForeColor = if ($hasFail) { $p.WarnFg } else { $p.TextDark }
    $u.LblPostExtra2.Text = (U "\uACF5\uC720 \uD504\uB9B0\uD130 \uC218: ") + $ps.SharedPrinters.Count + " / " + (U "\uB124\uD2B8\uC6CC\uD06C \uD504\uB9B0\uD130: ") + $ps.NetworkPrinters.Count
    $u.LblPostExtra2.ForeColor = $p.TextDark
   }

   # Populate Printers ListView
   $u.LvPrinters.BeginUpdate()
   $u.LvPrinters.Items.Clear()
   if ($ps.SpoolerStatus -ne "Running") {
    $li = New-Object System.Windows.Forms.ListViewItem((U "(Spooler \uC911\uC9C0 \uC0C1\uD0DC - \uC544\uB798 \uB9AC\uC14B \uC2E4\uD589 \uD6C4 \uD45C\uC2DC\uB429\uB2C8\uB2E4)"))
    $li.ForeColor = $p.WarnFg
    [void]$u.LvPrinters.Items.Add($li)
   } elseif ($ps.PrinterQueryError) {
    $li = New-Object System.Windows.Forms.ListViewItem((U "[\uACBD\uACE0] \uD504\uB9B0\uD130 \uBAA9\uB85D \uC870\uD68C \uC624\uB958(RPC) - \uC2A4\uD480\uB7EC \uB9AC\uC14B \uD544\uC694!"))
    $li.BackColor = $p.ErrBg; $li.ForeColor = $p.ErrFg
    [void]$u.LvPrinters.Items.Add($li)
   } elseif ($ps.Printers.Count -eq 0) {
    $li = New-Object System.Windows.Forms.ListViewItem((U "(\uC124\uCE58\uB41C \uD504\uB9B0\uD130 \uC5C6\uC74C)"))
    $li.ForeColor = $p.TextMuted
    [void]$u.LvPrinters.Items.Add($li)
   } else {
    foreach ($pr in $ps.Printers) {
     $typeTxt = if ($pr.IsNetwork) { U "\uB124\uD2B8\uC6CC\uD06C \uC5F0\uACB0" } elseif ($pr.Shared) { U "\uACF5\uC720 \uD638\uC2A4\uD2B8" } else { U "\uB85C\uCEEC" }
     $shareTxt = if ($pr.IsNetwork) { if ($pr.RemoteServer) { "\\" + $pr.RemoteServer } else { "-" } } elseif ($pr.Shared) { "\\" + $ps.ComputerName + "\" + $pr.ShareName } else { "-" }
     $li = New-Object System.Windows.Forms.ListViewItem([string]$pr.Name)
     [void]$li.SubItems.Add($typeTxt)
     [void]$li.SubItems.Add($shareTxt)
     [void]$li.SubItems.Add([string]$pr.PortName)
     [void]$li.SubItems.Add([string]$pr.DriverName)
     if ($pr.Shared -and -not $pr.IsNetwork) { $li.BackColor = $p.OkBg; $li.ForeColor = $p.OkFg }
     elseif ($pr.IsNetwork) { $li.BackColor = $p.InfoBg; $li.ForeColor = $p.InfoFg }
     [void]$u.LvPrinters.Items.Add($li)
    }
   }
   $u.LvPrinters.EndUpdate()
  } finally {
   if (-not $u.Form.IsDisposed) { $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
  }
 }.GetNewClosure()

 $ui.RefreshAll = {
  & $ui.RefreshPreSid
  & $ui.RefreshPostSid
 }.GetNewClosure()

 # ==================== EVENT HANDLERS (ALL CLOSURE-SAFE) ====================
 $btnTopRefresh.Add_Click({ & $ui.RefreshAll }.GetNewClosure())
 $btnRescanUsb.Add_Click({ & $ui.RefreshPreSid }.GetNewClosure())
 $btnPostRefresh.Add_Click({ & $ui.RefreshPostSid }.GetNewClosure())
 $btnTopDiag.Add_Click({ Show-GuiDiagnosticsDialog $ui.Form $ui.State.SysInfo $ui.State.Step2Snap $ui.Pal }.GetNewClosure())
 $btnInlineDiag.Add_Click({ Show-GuiDiagnosticsDialog $ui.Form $ui.State.SysInfo $ui.State.Step2Snap $ui.Pal }.GetNewClosure())

 # Dynamic button state when selecting a disk in STEP 1
 $lvDisks.Add_SelectedIndexChanged({
  $canTog = $false
  if ($ui.LvDisks.SelectedItems.Count -gt 0 -and $null -ne $ui.LvDisks.SelectedItems[0].Tag) {
   $selIt = $ui.LvDisks.SelectedItems[0].Tag
   if (-not $selIt.IsProtected -and ($selIt.State -in @("ACTIVE","DISABLED"))) { $canTog = $true }
  }
  $ui.BtnToggleDisk.Enabled = $canTog
  Set-GuiButtonStyle $ui.BtnToggleDisk $(if ($canTog) { "PrimaryBlue" } else { "Disabled" }) $ui.Pal
 }.GetNewClosure())
 $lvDisks.Add_DoubleClick({ if ($ui.BtnToggleDisk.Enabled) { $ui.BtnToggleDisk.PerformClick() } }.GetNewClosure())
 $lvNvramUsb.Add_DoubleClick({ if ($ui.BtnUsbReboot.Enabled) { $ui.BtnUsbReboot.PerformClick() } }.GetNewClosure())

 # STEP 1: One-Stop Fix
 $btnOneStop.Add_Click({
  $rep = $ui.State.EfiRep
  if (-not $rep -or $rep.SplitBoot -or $rep.ActionableConflictItems.Count -eq 0) { return }
  $targetsDesc = ($rep.ActionableConflictItems | ForEach-Object { " - Disk " + $_.DiskNumber + " (" + $_.Model + ", " + $_.BootType + " #" + $_.TargetPart + ")" }) -join "`r`n"
  $qMsg = (U "\uC544\uB798 \uBCF4\uC870 \uB514\uC2A4\uD06C\uC758 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uB97C \uBE44\uD30C\uAD34 \uBE44\uD65C\uC131\uD654(_OLD)\uD560\uAE4C\uC694?`r`n(\uD30C\uD2F0\uC158 \uC0AD\uC81C/\uD3EC\uB9F7 \uC5C6\uC74C \u00B7 \uC5B8\uC81C\uB4E0 \uBCF5\uAD6C \uAC00\uB2A5)`r`n`r`n") + $targetsDesc
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, $qMsg, (U "\uC6D0\uC2A4\uD1B1 \uC815\uB9AC \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $changed = 0
  $msgs = New-Object System.Collections.ArrayList
  foreach ($ci in $rep.ActionableConflictItems) {
   $r = Invoke-BootloaderAction $ci "DISABLE"
   [void]$msgs.Add($r.Message)
   if ($r.Warning) { [void]$msgs.Add(("  [WARN] " + $r.Warning)) }
   if ($r.Success) { $changed++ }
  }

  if ($changed -gt 0) {
   $diskLbl = if ($null -ne $rep.BootDisk) { "Disk " + $rep.BootDisk } else { $env:SystemDrive }
   $bbQ = ($msgs -join "`r`n") + "`r`n`r`n" + (U "\uD604\uC7AC OS SSD(") + $diskLbl + (U ")\uB97C UEFI NVRAM 1\uC21C\uC704\uB85C \uC815\uC2DD \uB4F1\uB85D(bcdboot)\uD560\uAE4C\uC694?")
   $dr2 = [System.Windows.Forms.MessageBox]::Show($ui.Form, $bbQ, (U "UEFI NVRAM \uB4F1\uB85D (bcdboot)"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
   if ($dr2 -eq [System.Windows.Forms.DialogResult]::Yes) {
    $bbRes = Invoke-NativeOem "bcdboot.exe" ('"' + $env:SystemRoot + '" /f UEFI')
    if ($bbRes.ExitCode -eq 0) {
     [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "UEFI NVRAM \uBD80\uD305 \uD56D\uBAA9 \uB4F1\uB85D(bcdboot) \uC644\uB8CC!"), (U "\uC644\uB8CC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
     [System.Windows.Forms.MessageBox]::Show($ui.Form, ((U "bcdboot \uB4F1\uB85D \uC2E4\uD328 (ExitCode=") + $bbRes.ExitCode + ")`r`n" + ($bbRes.Lines -join "`r`n")), (U "\uACBD\uACE0"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
   }
  } else {
   [System.Windows.Forms.MessageBox]::Show($ui.Form, ($msgs -join "`r`n"), (U "\uC870\uCE58 \uACB0\uACFC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
  }
  & $ui.RefreshPreSid
 }.GetNewClosure())

 # STEP 1: Individual Disk Toggle (Disable or Restore)
 $btnToggleDisk.Add_Click({
  if ($ui.LvDisks.SelectedItems.Count -eq 0) {
   [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "\uBA3C\uC800 \uC704 \uBAA9\uB85D\uC5D0\uC11C \uC804\uD658\uD560 \uB514\uC2A4\uD06C\uB97C \uC120\uD0DD\uD558\uC138\uC694."), (U "\uC548\uB0B4"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
   return
  }
  $it = $ui.LvDisks.SelectedItems[0].Tag
  if ($it.IsProtected) {
   [System.Windows.Forms.MessageBox]::Show($ui.Form, ("Disk " + $it.DiskNumber + " : " + (Format-BootloaderStateText $it) + "`r`n" + (U "\uBCF4\uD638 \uB300\uC0C1 \uB514\uC2A4\uD06C\uB294 \uBCC0\uACBD\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.")), (U "\uCC28\uB2E8"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
   return
  }
  $mode = if ($it.State -eq "ACTIVE") { "DISABLE" } elseif ($it.State -eq "DISABLED") { "RESTORE" } else { "" }
  if (-not $mode) {
   [System.Windows.Forms.MessageBox]::Show($ui.Form, ("Disk " + $it.DiskNumber + " : " + (Format-BootloaderStateText $it) + "`r`n" + (U "\uC790\uB3D9 \uC804\uD658 \uAC00\uB2A5\uD55C \uC0C1\uD0DC(ACTIVE/DISABLED)\uAC00 \uC544\uB2D9\uB2C8\uB2E4.")), (U "\uC548\uB0B4"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
   return
  }
  $preview = Get-PartitionPreviewListing $it
  $actLabel = if ($mode -eq "DISABLE") { U "\uBE44\uD65C\uC131\uD654(_OLD)" } else { U "\uC6D0\uC0C1 \uBCF5\uAD6C" }
  $confirmMsg = ("Disk " + $it.DiskNumber + " (" + $it.Model + ") | " + $it.BootType + " #" + $it.TargetPart + "`r`n`r`n" + (U "[\uD30C\uD2F0\uC158 \uB8E8\uD2B8 \uB0B4\uC6A9 \uBBF8\uB9AC\uBCF4\uAE30]") + "`r`n" + $preview + "`r`n`r`n" + (U "\uC774 \uB514\uC2A4\uD06C\uC758 \uBD80\uD2B8\uB85C\uB354\uB97C ") + $actLabel + (U "\uD560\uAE4C\uC694?"))
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, $confirmMsg, (U "\uBD80\uD2B8\uB85C\uB354 \uC804\uD658 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $r = Invoke-BootloaderAction $it $mode
  $icon = if ($r.Success) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Error }
  $body = $r.Message + $(if ($r.Warning) { "`r`n[" + (U "\uACBD\uACE0") + "] " + $r.Warning } else { "" })
  [System.Windows.Forms.MessageBox]::Show($ui.Form, $body, (U "\uC804\uD658 \uACB0\uACFC"), [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
  & $ui.RefreshPreSid
 }.GetNewClosure())

 # STEP 1: Explicit IGNORE Unlock
 $btnIgnoreStep1.Add_Click({
  if (Show-GuiIgnoreConfirmDialog $ui.Form $ui.Pal) {
   $ui.State.Step1Bypassed = $true
   & $ui.RefreshPreSid
  }
 }.GetNewClosure())

 # STEP 2: Confirmed 1-Time USB Reboot (Rule #3: ALWAYS confirm before reboot!)
 $btnUsbReboot.Add_Click({
  if ($ui.LvNvramUsb.SelectedItems.Count -eq 0 -or $null -eq $ui.LvNvramUsb.SelectedItems[0].Tag) {
   [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "\uBA3C\uC800 [2-2] \uBAA9\uB85D\uC5D0\uC11C \uBD80\uD305\uD560 UEFI USB \uD56D\uBAA9\uC744 \uC120\uD0DD\uD558\uC138\uC694."), (U "\uC548\uB0B4"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
   return
  }
  $target = $ui.LvNvramUsb.SelectedItems[0].Tag
  $devStr = if ($target.Device) { $target.Device } else { "UEFI NVRAM" }
  $cMsg = (U "\uC544\uB798 USB \uD56D\uBAA9\uC744 1\uD68C\uC131 \uBD80\uD305 \uC21C\uC11C(bootsequence)\uB85C \uC9C0\uC815\uD558\uACE0 \uC989\uC2DC \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?`r`n`r`n") +
          (U "\uD56D\uBAA9: ") + $target.Description + "`r`n" +
          (U "\uB9E4\uCE6D: ") + $target.MatchTag + "`r`n" +
          (U "\uC7A5\uCE58: ") + $devStr + "`r`n" +
          "GUID: " + $target.Identifier
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, $cMsg, (U "USB 1\uD68C\uC131 \uC7AC\uBD80\uD305 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $setRes = Invoke-NativeOem "bcdedit.exe" ("/set {fwbootmgr} bootsequence " + $target.Identifier)
  if ($setRes.ExitCode -eq 0) {
   $rb = Invoke-SafeRebootCore "/r /f /t 0"
   if ($rb.Success) { $ui.Form.Close(); return }
   [System.Windows.Forms.MessageBox]::Show($ui.Form, ((U "\uC7AC\uBD80\uD305 \uBA85\uB839 \uC2E4\uD328 (ExitCode=") + $rb.ExitCode + ")`r`n" + $rb.Output), (U "\uC624\uB958"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
  } else {
   $fbMsg = (U "NVRAM \uBD80\uD305 \uC21C\uC11C \uBCC0\uACBD\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.`r`n") + ($setRes.Lines -join " ") + (U "`r`n`r`n\uB300\uC2E0 Windows \uACE0\uAE09 \uBD80\uD305('\uC7A5\uCE58 \uC0AC\uC6A9') \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?")
   $drFb = [System.Windows.Forms.MessageBox]::Show($ui.Form, $fbMsg, (U "NVRAM \uBCC0\uACBD \uC2E4\uD328"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
   if ($drFb -eq [System.Windows.Forms.DialogResult]::Yes) {
    $rb2 = Invoke-SafeRebootCore "/r /o /f /t 0"
    if ($rb2.Success) { $ui.Form.Close(); return }
   }
  }
 }.GetNewClosure())

 # STEP 2: Windows Advanced Boot ('Use a device')
 $btnAdvBoot.Add_Click({
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "Windows \uACE0\uAE09 \uBD80\uD305('\uC7A5\uCE58 \uC0AC\uC6A9') \uBA54\uB274\uB85C \uC989\uC2DC \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?"), (U "\uACE0\uAE09 \uBD80\uD305 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $rb = Invoke-SafeRebootCore "/r /o /f /t 0"
  if ($rb.Success) { $ui.Form.Close(); return }
  [System.Windows.Forms.MessageBox]::Show($ui.Form, ((U "\uC7AC\uBD80\uD305 \uC2E4\uD328 (ExitCode=") + $rb.ExitCode + ")`r`n" + $rb.Output), (U "\uC624\uB958"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
 }.GetNewClosure())

 # STEP 2: BIOS Firmware Setup
 $btnBiosBoot.Add_Click({
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, ((U "UEFI BIOS \uD38C\uC6E8\uC5B4 \uC124\uC815 \uD654\uBA74\uC73C\uB85C \uC989\uC2DC \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?`r`n`r`n") + $ui.State.SysInfo.BiosHint), (U "BIOS \uC9C4\uC785 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $rb = Invoke-SafeRebootCore "/r /fw /f /t 0"
  if ($rb.Success) { $ui.Form.Close(); return }
  [System.Windows.Forms.MessageBox]::Show($ui.Form, ((U "BIOS \uC7AC\uBD80\uD305 \uC2E4\uD328 (ExitCode=") + $rb.ExitCode + ")`r`n" + $rb.Output), (U "\uC624\uB958"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
 }.GetNewClosure())

 # TAB 2: Spooler Reset Execution
 $btnSpoolerReset.Add_Click({
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC(Spooler)\uB97C \uC911\uC9C0\uD558\uACE0 \uB300\uAE30\uC5F4(PRINTERS)\uB97C \uBE44\uC6B4 \uB4A4 \uC7AC\uC2DC\uC791\uD560\uAE4C\uC694?`r`n(\uAE30\uC874 \uD504\uB9B0\uD130\u00B7\uB4DC\uB77C\uC774\uBC84\u00B7\uACF5\uC720 \uC124\uC815\uC740 \uC0AD\uC81C\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.)"), (U "\uC2A4\uD480\uB7EC \uB9AC\uC14B \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $ui.BtnSpoolerReset.Enabled = $false
  $ui.BtnPostRefresh.Enabled = $false
  $ui.TbResetLog.Text = (U "[\uC2DC\uC791] \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B \uC9C4\uD589 \uC911...") + "`r`n"
  [System.Windows.Forms.Application]::DoEvents()

  try {
   $logBox = $ui.TbResetLog
   $res = Invoke-SpoolerResetCore {
    param($msg)
    $logBox.AppendText((" " + $msg + "`r`n"))
    [System.Windows.Forms.Application]::DoEvents()
   }.GetNewClosure()

   if (-not $res.ServiceMissing) {
    $qRes = $res.QueueResult
    $summary = "`r`n--- [" + (U "\uACB0\uACFC \uC694\uC57D") + "] ---`r`n" +
               " * " + (U "\uC911\uC9C0 \uBC29\uC2DD") + " : " + $res.StopMode + "`r`n" +
               " * " + (U "\uB300\uAE30\uC5F4 \uC815\uB9AC") + " : " + $qRes.DeletedCount + (U "\uAC74 \uC0AD\uC81C") + " (SPL/SHD: " + $qRes.SplShdDeleted + ") | " + (U "\uC794\uC874") + ": " + $qRes.RemainingCount + (U "\uAC74") + "`r`n" +
               " * " + (U "\uC2DC\uC791 \uC720\uD615") + " : " + $res.StartMode + $(if ($res.StartRestored) { " (" + (U "Automatic\uC73C\uB85C \uBCF5\uAD6C\uB428") + ")" } else { "" }) + "`r`n" +
               " * " + (U "\uCD5C\uC885 \uC0C1\uD0DC") + " : " + $(if ($res.IsRunning) { U "\uC815\uC0C1 \uC2E4\uD589 \uC911 (Running)" } else { (U "\uC2DC\uC791 \uC2E4\uD328: ") + $res.StartError }) + "`r`n"
    $ui.TbResetLog.AppendText($summary)
    if ($res.IsRunning) {
     $ui.TbResetLog.AppendText(("`r`n" + (U "\uC644\uB8CC! \uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uD074\uB77C\uC774\uC5B8\uD2B8 PC \uBAA8\uB450\uC5D0\uC11C \uC2E4\uD589\uD55C \uB4A4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB97C \uD655\uC778\uD558\uC138\uC694.") + "`r`n"))
    }
   }
  } finally {
   $ui.BtnSpoolerReset.Enabled = $true
   $ui.BtnPostRefresh.Enabled = $true
  }
  & $ui.RefreshPostSid
 }.GetNewClosure())

 # Null-safe FormClosed cleanup (immune to scope loss; NEVER blocks window close)
 $form.Add_FormClosed({
  param($sender, $e)
  $ctx = if ($sender -and $sender.Tag) { $sender.Tag } else { $ui }
  if ($ctx -and $ctx.Disposables) {
   foreach ($obj in $ctx.Disposables) {
    if ($null -ne $obj) { try { $obj.Dispose() } catch {} }
   }
  }
 }.GetNewClosure())

 if ($autoPopulate) {
  & $ui.RefreshAll
 }

 return [PSCustomObject]@{
  Form             = $form
  TabControl       = $tabControl
  DiskListView     = $lvDisks
  PhysUsbListView  = $lvPhysUsb
  NvramUsbListView = $lvNvramUsb
  PrinterListView  = $lvPrinters
  BtnTopRefresh    = $btnTopRefresh
  BtnRescanUsb     = $btnRescanUsb
  BtnPostRefresh   = $btnPostRefresh
  State            = $state
  RefreshAll       = $ui.RefreshAll
  UiContext        = $ui
 }
}

# Dedicated compact WinForms GUI for WinPE (X:) Emergency Mode (falls back to Console if WinForms missing)
function Show-WinPeEmergencyGui {
 [System.Windows.Forms.Application]::EnableVisualStyles()
 $pal = Get-GuiPalette
 $fontRegular = New-Object System.Drawing.Font("Malgun Gothic", 9.5)
 $fontBold    = New-Object System.Drawing.Font("Malgun Gothic", 9.5, [System.Drawing.FontStyle]::Bold)

 $form = New-Object System.Windows.Forms.Form
 $form.Text = (U "[WinPE \uBE44\uC0C1 \uBAA8\uB4DC] \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80 \uBC0F \uBCF5\uAD6C") + " v" + $script:ToolVersion
 $form.Size = New-Object System.Drawing.Size(880, 480)
 $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
 $form.BackColor = $pal.AppBg
 $form.Font = $fontRegular

 $hdr = New-Object System.Windows.Forms.Label
 $hdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $hdr.Height = 46
 $hdr.BackColor = $pal.WarnBg
 $hdr.ForeColor = $pal.WarnFg
 $hdr.Font = $fontBold
 $hdr.Padding = New-Object System.Windows.Forms.Padding(14, 12, 14, 8)
 $hdr.Text = U "[WinPE \uBE44\uC0C1 \uBAA8\uB4DC] \uB0B4\uC7A5 \uB514\uC2A4\uD06C\uC758 GPT EFI / MBR \uBD80\uD2B8\uB85C\uB354\uB97C \uC548\uC804\uD558\uAC8C \uBE44\uD65C\uC131\uD654 \uB610\uB294 \uC6D0\uC0C1 \uBCF5\uAD6C\uD569\uB2C8\uB2E4."

 $lv = New-Object System.Windows.Forms.ListView
 $lv.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lv.View = [System.Windows.Forms.View]::Details
 $lv.FullRowSelect = $true
 $lv.GridLines = $true
 [void]$lv.Columns.Add((U "\uB514\uC2A4\uD06C"), 68)
 [void]$lv.Columns.Add((U "\uBAA8\uB378\uBA85"), 230)
 [void]$lv.Columns.Add((U "\uC6A9\uB7C9"), 80)
 [void]$lv.Columns.Add((U "\uBC29\uC2DD"), 80)
 [void]$lv.Columns.Add((U "\uB300\uC0C1"), 120)
 [void]$lv.Columns.Add((U "\uC0C1\uD0DC"), 255)

 $bar = New-Object System.Windows.Forms.FlowLayoutPanel
 $bar.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $bar.Height = 48
 $bar.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
 $bar.BackColor = $pal.CardBg

 $btnTog = New-Object System.Windows.Forms.Button
 $btnTog.Text = U "\uC120\uD0DD \uB514\uC2A4\uD06C \uBE44\uD65C\uC131\uD654 / \uBCF5\uAD6C \uC804\uD658"
 $btnTog.Size = New-Object System.Drawing.Size(230, 32)
 Set-GuiButtonStyle $btnTog "PrimaryBlue" $pal

 $btnRef = New-Object System.Windows.Forms.Button
 $btnRef.Text = U "\uC0C8\uB85C\uACE0\uCE68"
 $btnRef.Size = New-Object System.Drawing.Size(96, 32)
 Set-GuiButtonStyle $btnRef "Neutral" $pal

 $btnPeReboot = New-Object System.Windows.Forms.Button
 $btnPeReboot.Text = U "PC \uC7AC\uBD80\uD305"
 $btnPeReboot.Size = New-Object System.Drawing.Size(104, 32)
 Set-GuiButtonStyle $btnPeReboot "PrimaryAmber" $pal

 $btnClose = New-Object System.Windows.Forms.Button
 $btnClose.Text = U "\uB2EB\uAE30"
 $btnClose.Size = New-Object System.Drawing.Size(88, 32)
 Set-GuiButtonStyle $btnClose "Neutral" $pal

 $bar.Controls.Add($btnTog)
 $bar.Controls.Add($btnRef)
 $bar.Controls.Add($btnPeReboot)
 $bar.Controls.Add($btnClose)

 $peUi = @{
  Form = $form
  Lv = $lv
  Pal = $pal
  Disposables = @($fontRegular, $fontBold)
 }
 $form.Tag = $peUi

 $peUi.LoadPe = {
  $rep = Get-InternalBootloaderReport $true
  $peUi.Lv.BeginUpdate()
  $peUi.Lv.Items.Clear()
  foreach ($it in $rep.Items) {
   $pStr = if ($it.TargetPart -gt 0) { $it.BootType + " #" + $it.TargetPart } else { "-" }
   $lvi = New-Object System.Windows.Forms.ListViewItem(("Disk " + $it.DiskNumber))
   [void]$lvi.SubItems.Add([string]$it.Model)
   [void]$lvi.SubItems.Add(([string]$it.SizeGB + " GB"))
   [void]$lvi.SubItems.Add([string]$it.PartitionStyle)
   [void]$lvi.SubItems.Add($pStr)
   [void]$lvi.SubItems.Add((Format-BootloaderStateText $it))
   $lvi.Tag = $it
   if ($it.State -in @("ACTIVE","BOTH","MBR_OS_BLOCKED")) { $lvi.BackColor = $peUi.Pal.ErrBg; $lvi.ForeColor = $peUi.Pal.ErrFg }
   elseif ($it.State -eq "DISABLED") { $lvi.BackColor = $peUi.Pal.InfoBg; $lvi.ForeColor = $peUi.Pal.InfoFg }
   [void]$peUi.Lv.Items.Add($lvi)
  }
  $peUi.Lv.EndUpdate()
 }.GetNewClosure()

 $btnClose.Add_Click({ $peUi.Form.Close() }.GetNewClosure())
 $btnRef.Add_Click({ & $peUi.LoadPe }.GetNewClosure())
 $btnPeReboot.Add_Click({
  $dr = [System.Windows.Forms.MessageBox]::Show($peUi.Form, (U "PC\uB97C \uC989\uC2DC \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?"), (U "\uC7AC\uBD80\uD305 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -eq [System.Windows.Forms.DialogResult]::Yes) {
   $null = Invoke-NativeOem "wpeutil.exe" "reboot"
   $null = Invoke-SafeRebootCore "/r /f /t 0"
  }
 }.GetNewClosure())
 $btnTog.Add_Click({
  if ($peUi.Lv.SelectedItems.Count -eq 0) { return }
  $it = $peUi.Lv.SelectedItems[0].Tag
  $mode = if ($it.State -eq "ACTIVE") { "DISABLE" } elseif ($it.State -eq "DISABLED") { "RESTORE" } else { "" }
  if (-not $mode) {
   [System.Windows.Forms.MessageBox]::Show($peUi.Form, (Format-BootloaderStateText $it), (U "\uC548\uB0B4"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
   return
  }
  $preview = Get-PartitionPreviewListing $it
  $actLbl = if ($mode -eq "DISABLE") { U "\uBE44\uD65C\uC131\uD654(_OLD)" } else { U "\uC6D0\uC0C1 \uBCF5\uAD6C" }
  $cMsg = ("Disk " + $it.DiskNumber + " (" + $it.Model + ") | " + $it.BootType + " #" + $it.TargetPart + "`r`n`r`n" + (U "[\uD30C\uD2F0\uC158 \uB8E8\uD2B8 \uBBF8\uB9AC\uBCF4\uAE30]") + "`r`n" + $preview + "`r`n`r`n" + $actLbl + (U "\uB97C \uC9C4\uD589\uD560\uAE4C\uC694?"))
  $dr = [System.Windows.Forms.MessageBox]::Show($peUi.Form, $cMsg, (U "\uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $r = Invoke-BootloaderAction $it $mode
  [System.Windows.Forms.MessageBox]::Show($peUi.Form, $r.Message, (U "\uACB0\uACFC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  & $peUi.LoadPe
 }.GetNewClosure())

 $form.Add_FormClosed({
  param($sender, $e)
  $ctx = if ($sender -and $sender.Tag) { $sender.Tag } else { $peUi }
  if ($ctx -and $ctx.Disposables) {
   foreach ($obj in $ctx.Disposables) {
    if ($null -ne $obj) { try { $obj.Dispose() } catch {} }
   }
  }
 }.GetNewClosure())

 $form.Controls.Add($lv)
 $form.Controls.Add($bar)
 $form.Controls.Add($hdr)
 & $peUi.LoadPe
 try {
  [void]$form.ShowDialog()
 } finally {
  try { $form.Dispose() } catch {}
 }
}

function Start-ToolGui($sysInfo) {
 $bundle = New-SidAuxMainForm $sysInfo $true
 try {
  [void]$bundle.Form.ShowDialog()
 } finally {
  if ($bundle -and $bundle.Form) { try { $bundle.Form.Dispose() } catch {} }
 }
}
# ==============================================================================
# Module 07: Main Entrypoint (GUI-First with Automatic Console TUI Fallback,
#            WinPE Auto-Branch & Pre-SID STEP 1 -> STEP 2 UX)
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

function Start-ToolConsoleMain($sysInfo) {
 while ($true) {
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Cyan
  Write-Host (" " + (U "[SID \uBCC0\uACBD \uBCF4\uC870 \uD234") + " v" + $script:ToolVersion + "] " + (U "\uC2DC\uC2A4\uD15C :") + " [" + $sysInfo.Vendor + "] (" + $sysInfo.ModelName + ")") -ForegroundColor Cyan
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

function Start-ToolMain {
 $forceCli = ($env:SID_TOOL_CLI -eq "1") -or ($env:SELF_ARG1 -match "^(--cli|/cli|-cli)$")

 # WinPE (X:) Emergency Mode Auto-Detection
 if ($env:SystemDrive -eq "X:") {
  if (-not $forceCli -and (Test-WinFormsAvailable)) {
   try {
    Show-WinPeEmergencyGui
    exit 0
   } catch {}
  }
  Clear-Host
  Write-Host "==================================================================" -ForegroundColor Yellow
  Write-Host (U " [WinPE \uBE44\uC0C1 \uBAA8\uB4DC] \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354(EFI/MBR) \uC810\uAC80 \uBC0F \uBCF5\uAD6C") -ForegroundColor Yellow
  Write-Host "==================================================================" -ForegroundColor Yellow
  Show-BootloaderManager $true
  exit 0
 }

 # Normal Windows: Prefer WinForms GUI, automatically fall back to Console TUI if unavailable
 $sysInfo = Get-SystemInfo
 if (-not $forceCli -and (Test-WinFormsAvailable)) {
  try {
   try { [Console]::Title = "SID Change Auxiliary Tool v" + $script:ToolVersion } catch {}
   Start-ToolGui $sysInfo
   exit 0
  } catch {
   Write-Host ((U "`n[\uC548\uB0B4] GUI \uBAA8\uB4DC \uCD08\uAE30\uD654 \uC2E4\uD328 - \uCF58\uC194 \uBAA8\uB4DC\uB85C \uC790\uB3D9 \uC804\uD658\uD569\uB2C8\uB2E4: ") + $_.Exception.Message) -ForegroundColor Yellow
   Start-Sleep -Milliseconds 1200
  }
 }

 Start-ToolConsoleMain $sysInfo
}

if (-not $env:SID_TOOL_TEST_MODE) {
 Start-ToolMain
}
