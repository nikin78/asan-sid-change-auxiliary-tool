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
$script:ToolVersion = "2.2.0"
$script:BuildDate = "2026-11-26"
$script:BuildCommit = "ce38433"
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
  return [PSCustomObject]@{
   Mode = "Network"
   Label = (U "\uACF5\uC720\uD3F4\uB354 \uC2E4\uD589")
   Detail = (U "\uACF5\uC720\uD3F4\uB354\uC5D0\uC11C \uBA54\uBAA8\uB9AC\uB85C \uB85C\uB4DC\uB418\uC5C8\uC73C\uBA70 \uC6D0\uBCF8 \uD30C\uC77C\uC740 \uBCC0\uACBD\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.")
  }
 }
 if ($p) {
  try {
   $rt = [System.IO.Path]::GetPathRoot($p)
   if ($rt) {
    $di = New-Object System.IO.DriveInfo ($rt)
    if ($di.DriveType -eq "Network") {
     return [PSCustomObject]@{
      Mode = "Network"
      Label = (U "\uB124\uD2B8\uC6CC\uD06C \uC2E4\uD589")
      Detail = (U "\uB124\uD2B8\uC6CC\uD06C \uB4DC\uB77C\uC774\uBE0C\uC5D0\uC11C \uBA54\uBAA8\uB9AC\uB85C \uB85C\uB4DC\uB418\uC5C8\uC73C\uBA70 \uC6D0\uBCF8 \uD30C\uC77C\uC740 \uBCC0\uACBD\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4.")
     }
    } elseif ($di.DriveType -eq "Removable" -or $di.DriveType -eq "CDRom") {
     return [PSCustomObject]@{
      Mode = "USB"
      Label = (U "\uC678\uC7A5 USB \uC2E4\uD589")
      Detail = (U "\uC678\uC7A5 USB \uB610\uB294 \uC77D\uAE30 \uC804\uC6A9 \uB9E4\uCCB4\uC5D0 \uC4F0\uAE30 \uC791\uC5C5 \uC5C6\uC774 \uC2E4\uD589\uB429\uB2C8\uB2E4.")
     }
    }
   }
  } catch {}
 }
 return [PSCustomObject]@{
  Mode = "Local"
  Label = (U "\uB85C\uCEEC PC \uC2E4\uD589")
  Detail = (U "\uC774 PC\uC758 \uB85C\uCEEC \uB4DC\uB77C\uC774\uBE0C\uC5D0\uC11C \uC2E4\uD589 \uC911\uC785\uB2C8\uB2E4.")
 }
}

# Mask sensitive credentials/tokens in exported diagnostic reports
function ConvertTo-MaskedDiagnosticText([string]$raw) {
 if ([string]::IsNullOrEmpty($raw)) { return "" }
 $out = [regex]::Replace($raw, '(?i)(password|passwd|pwd|secret|token|apikey|credential)\s*([:=])\s*([^\r\n\s,;"'']+)', '$1$2[REDACTED]')
 $out = [regex]::Replace($out, '(?i)("?(?:password|passwd|secret|token)"?\s*:\s*")([^"\\]*(?:\\.[^"\\]*)*)(")', '$1[REDACTED]$3')
 return $out
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
  } | Sort-Object Number)
  $usbNums = @($usbDisks | Select-Object -ExpandProperty Number)
  $internalDisks = @($allDisks | Where-Object { $usbNums -notcontains $_.Number } | Sort-Object Number)
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
  UsbDisks = @($usbDisks | Sort-Object Number)
  InternalDisks = @($internalDisks | Sort-Object Number)
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
  $modelLabel = if ($d.FriendlyName -and $d.FriendlyName.Trim() -ne "") { $d.FriendlyName.Trim() } else { U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C" }
  $items += [PSCustomObject]@{
   DiskNumber = $d.Number
   Model = $modelLabel
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

# Clean commercial UX status text, semantic category, and hover tooltip for WinForms GUI
function Format-BootloaderGuiStatus($item) {
 switch ($item.State) {
  "PROTECTED"          { return [PSCustomObject]@{ Text = (U "\uD604\uC7AC Windows \uBCF4\uD638\uB428"); Kind = "OK"; Tip = (U "\uD604\uC7AC Windows\uAC00 \uC2E4\uD589 \uC911\uC778 \uB514\uC2A4\uD06C\uC774\uBBC0\uB85C \uBCC0\uACBD \uB300\uC0C1\uC5D0\uC11C \uC790\uB3D9 \uC81C\uC678\uB429\uB2C8\uB2E4.") } }
  "PROTECTED_OS"       { return [PSCustomObject]@{ Text = (U "\uD604\uC7AC Windows \uBCF4\uD638\uB428"); Kind = "OK"; Tip = (U "\uD604\uC7AC Windows\uAC00 \uC2E4\uD589 \uC911\uC778 \uB514\uC2A4\uD06C\uC774\uBBC0\uB85C \uBCC0\uACBD \uB300\uC0C1\uC5D0\uC11C \uC790\uB3D9 \uC81C\uC678\uB429\uB2C8\uB2E4.") } }
  "WINPE_MEDIA"        { return [PSCustomObject]@{ Text = (U "WinPE \uB9E4\uCCB4 \uBCF4\uD638\uB428"); Kind = "Info"; Tip = (U "WinPE \uB610\uB294 \uC124\uCE58 \uB9E4\uCCB4\uB85C \uAC10\uC9C0\uB418\uC5B4 \uC790\uB3D9\uC73C\uB85C \uBCF4\uD638\uB429\uB2C8\uB2E4.") } }
  "READONLY_PROTECTED" { return [PSCustomObject]@{ Text = (U "\uC77D\uAE30 \uC804\uC6A9 \uBCF4\uD638\uB428"); Kind = "Info"; Tip = (U "\uC4F0\uAE30 \uAE08\uC9C0 \uB514\uC2A4\uD06C\uC774\uBBC0\uB85C \uBCC0\uACBD \uB300\uC0C1\uC5D0\uC11C \uC790\uB3D9\uC73C\uB85C \uBCF4\uD638\uB429\uB2C8\uB2E4.") } }
  "ACTIVE"             {
   if ($item.BootType -eq "MBR_ACTIVE") {
    return [PSCustomObject]@{ Text = (U "\uCDA9\uB3CC \uC704\uD5D8 \u00B7 \uC794\uC874 MBR"); Kind = "Error"; Tip = (U "\uBCF4\uC870 \uB514\uC2A4\uD06C\uC5D0 \uD65C\uC131 MBR \uBD80\uD2B8\uB85C\uB354\uAC00 \uB0A8\uC544 \uC788\uC2B5\uB2C8\uB2E4. SID \uBCC0\uACBD \uD6C4 \uBD80\uD305 \uCDA9\uB3CC\uC744 \uB9C9\uAE30 \uC704\uD574 \uC815\uB9AC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.") }
   }
   return [PSCustomObject]@{ Text = (U "\uCDA9\uB3CC \uC704\uD5D8 \u00B7 \uC794\uC874 EFI"); Kind = "Error"; Tip = (U "\uBCF4\uC870 \uB514\uC2A4\uD06C\uC5D0 \uC794\uC874 EFI \uBD80\uD2B8\uB85C\uB354\uAC00 \uB0A8\uC544 \uC788\uC2B5\uB2C8\uB2E4. SID \uBCC0\uACBD \uD6C4 \uBD80\uD305 \uCDA9\uB3CC\uC744 \uB9C9\uAE30 \uC704\uD574 \uC815\uB9AC\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.") }
  }
  "BOTH"               { return [PSCustomObject]@{ Text = (U "\uC218\uB3D9 \uD655\uC778 \uD544\uC694"); Kind = "Warn"; Tip = (U "\uD65C\uC131 \uBD80\uD2B8\uB85C\uB354\uC640 \uBE44\uD65C\uC131 \uBC31\uC5C5 \uD3F4\uB354\uAC00 \uD568\uAED8 \uC788\uC5B4 \uC790\uB3D9 \uBCC0\uACBD\uC744 \uC911\uB2E8\uD588\uC2B5\uB2C8\uB2E4.") } }
  "MBR_OS_BLOCKED"     { return [PSCustomObject]@{ Text = (U "\uAD6C\uD615 OS \uACF5\uC874 \uC8FC\uC758"); Kind = "Warn"; Tip = (U "\uAD6C\uD615 Windows\uC640 \uBD80\uD2B8\uB85C\uB354\uAC00 \uAC19\uC740 \uD30C\uD2F0\uC158\uC5D0 \uD568\uAED8 \uC788\uC5B4 \uC790\uB3D9 \uBCC0\uACBD\uC744 \uCC28\uB2E8\uD588\uC2B5\uB2C8\uB2E4.") } }
  "DISABLED"           { return [PSCustomObject]@{ Text = (U "\uC815\uB9AC \uC644\uB8CC \u00B7 \uBCF5\uAD6C \uAC00\uB2A5"); Kind = "Info"; Tip = (U "\uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uAC00 \uBE44\uD30C\uAD34 \uBC29\uC2DD\uC73C\uB85C \uBE44\uD65C\uC131\uD654\uB418\uC5C8\uC2B5\uB2C8\uB2E4. \uD544\uC694 \uC2DC \uC5B8\uC81C\uB4E0 \uC6D0\uB798\uB300\uB85C \uBCF5\uAD6C\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.") } }
  "OS_BLOCKED"         { return [PSCustomObject]@{ Text = (U "OS \uD30C\uD2F0\uC158 \uBCF4\uD638\uB428"); Kind = "Info"; Tip = (U "Windows \uC2DC\uC2A4\uD15C \uD30C\uC77C\uC774 \uD655\uC778\uB418\uC5B4 \uBCC0\uACBD\uC744 \uCC28\uB2E8\uD588\uC2B5\uB2C8\uB2E4.") } }
  "WINPE_BLOCKED"      { return [PSCustomObject]@{ Text = (U "WinPE \uB9E4\uCCB4 \uBCF4\uD638\uB428"); Kind = "Info"; Tip = (U "WinPE \uB610\uB294 \uC124\uCE58 \uB9E4\uCCB4\uB85C \uAC10\uC9C0\uB418\uC5B4 \uBCC0\uACBD\uC744 \uCC28\uB2E8\uD588\uC2B5\uB2C8\uB2E4.") } }
  "EMPTY"              { return [PSCustomObject]@{ Text = (U "\uC774\uC0C1 \uC5C6\uC74C"); Kind = "Neutral"; Tip = (U "\uBE48 \uBD80\uD2B8 \uD30C\uD2F0\uC158\uC73C\uB85C \uBD80\uD305 \uCDA9\uB3CC \uC704\uD5D8\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.") } }
  "NO_BOOTLOADER"      { return [PSCustomObject]@{ Text = (U "\uC774\uC0C1 \uC5C6\uC74C"); Kind = "Neutral"; Tip = (U "\uCDA9\uB3CC\uC744 \uC77C\uC73C\uD0AC \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uAC00 \uBC1C\uACAC\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.") } }
  "MOUNT_FAIL"         { return [PSCustomObject]@{ Text = (U "\uC811\uADFC \uBD88\uAC00"); Kind = "Warn"; Tip = (U "\uBD80\uD2B8 \uD30C\uD2F0\uC158\uC5D0 \uC784\uC2DC\uB85C \uC811\uADFC\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. \uB514\uC2A4\uD06C \uC0C1\uD0DC\uB97C \uD655\uC778\uD574 \uC8FC\uC138\uC694.") } }
  default              { return [PSCustomObject]@{ Text = [string]$item.State; Kind = "Neutral"; Tip = "" } }
 }
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
   $ok = Test-TcpPortFast $srv 445 600
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

# Contextual UX guidance for Post-SID screen (plain commercial Korean, zero brackets/parentheses/jargon)
function Get-PostSidGuidance($st) {
 if (-not $st) {
  return [PSCustomObject]@{
   Level = "Info"
   Title = U "\uD504\uB9B0\uD130 \uD658\uACBD\uC744 \uD655\uC778\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4"
   Message = U "\uC7A0\uC2DC\uB9CC \uAE30\uB2E4\uB824 \uC8FC\uC138\uC694."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 if ($st.SpoolerStatus -ne "Running" -or $st.SpoolerStartMode -eq "Disabled") {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4\uAC00 \uC911\uC9C0\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4"
   Message = U "\uC544\uB798 \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uB20C\uB7EC \uC11C\uBE44\uC2A4\uB97C \uC790\uB3D9\uC73C\uB85C \uBCF5\uAD6C\uD574 \uC8FC\uC138\uC694. \uAE30\uC874 \uD504\uB9B0\uD130\uC640 \uACF5\uC720 \uC124\uC815\uC740 \uADF8\uB300\uB85C \uC720\uC9C0\uB429\uB2C8\uB2E4."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 if ($st.PrinterQueryError) {
  return [PSCustomObject]@{
   Level = "Error"
   Title = U "\uD504\uB9B0\uD130 \uBAA9\uB85D \uC751\uB2F5 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4"
   Message = U "SID \uBCC0\uACBD \uC9C1\uD6C4 \uC790\uC8FC \uBC1C\uC0DD\uD558\uB294 \uC77C\uC2DC\uC801 \uC624\uB958\uC785\uB2C8\uB2E4. \uC544\uB798 \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uD55C \uBC88 \uC2E4\uD589\uD574 \uC8FC\uC138\uC694."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 if ($st.Role -eq "Host") {
  if ($st.HasPublicProfile -or $st.FirewallInboundEnabled -eq 0) {
   return [PSCustomObject]@{
    Level = "Warn"
    Title = U "\uBA54\uC778 \uD504\uB9B0\uD130 PC\uC785\uB2C8\uB2E4 \u00B7 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uC640 \uACF5\uC720 \uC124\uC815\uC744 \uD655\uC778\uD574 \uC8FC\uC138\uC694"
    Message = U "\uBA3C\uC800 \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uC2E4\uD589\uD574 \uC8FC\uC138\uC694. \uACF5\uC6A9 \uB124\uD2B8\uC6CC\uD06C\uB098 \uBC29\uD654\uBCBD \uCC28\uB2E8\uC774 \uAC10\uC9C0\uB418\uC5C8\uC73C\uBBC0\uB85C \uC544\uB798 \uACF5\uC720 \uBCF4\uC548 \uC0C1\uD0DC\uB3C4 \uD568\uAED8 \uD655\uC778\uD574 \uC8FC\uC138\uC694."
    RecommendedAction = "SPOOLER_RESET"
   }
  }
  return [PSCustomObject]@{
   Level = "OK"
   Title = U "\uBA54\uC778 \uD504\uB9B0\uD130 PC\uB85C \uD655\uC778\uB418\uC5C8\uC2B5\uB2C8\uB2E4"
   Message = U "SID \uBCC0\uACBD\uC744 \uB9C8\uCE58\uC168\uB2E4\uBA74 \uC544\uB798 \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uD55C \uBC88 \uC2E4\uD589\uD574 \uC8FC\uC138\uC694. \uC774\uD6C4 \uAC01 \uD074\uB77C\uC774\uC5B8\uD2B8 PC\uC5D0\uC11C\uB3C4 \uD55C \uBC88\uC529 \uC2E4\uD589\uD558\uBA74 \uACF5\uC720 \uD504\uB9B0\uD130\uAC00 \uC815\uC0C1 \uC5F0\uACB0\uB429\uB2C8\uB2E4."
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 $unreachableHosts = @($st.RemoteHostChecks | Where-Object { -not $_.Reachable })
 if ($unreachableHosts.Count -gt 0) {
  $uNames = ($unreachableHosts | ForEach-Object { "\\" + $_.Server }) -join ", "
  return [PSCustomObject]@{
   Level = "Warn"
   Title = U "\uD074\uB77C\uC774\uC5B8\uD2B8 PC\uC785\uB2C8\uB2E4 \u00B7 \uBA54\uC778 PC \uC5F0\uACB0 \uC0C1\uD0DC\uB97C \uD655\uC778\uD574 \uC8FC\uC138\uC694"
   Message = ((U "\uC774 PC\uC5D0\uC11C \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uC2E4\uD589\uD574 \uC8FC\uC138\uC694. \uBA54\uC778 PC ") + $uNames + (U " \uC751\uB2F5\uC774 \uC5C6\uC73C\uBBC0\uB85C \uC804\uC6D0\uACFC \uB124\uD2B8\uC6CC\uD06C \uC5F0\uACB0\uB3C4 \uD568\uAED8 \uD655\uC778\uD574 \uC8FC\uC138\uC694."))
   RecommendedAction = "SPOOLER_RESET"
  }
 }
 return [PSCustomObject]@{
  Level = "Info"
  Title = U "\uD074\uB77C\uC774\uC5B8\uD2B8 PC\uB85C \uD655\uC778\uB418\uC5C8\uC2B5\uB2C8\uB2E4"
  Message = U "\uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uC774 PC\uC5D0\uC11C \uAC01\uAC01 \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uD55C \uBC88 \uC2E4\uD589\uD55C \uB4A4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB85C \uC5F0\uACB0\uC744 \uD655\uC778\uD574 \uC8FC\uC138\uC694."
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
# Module 06: WinForms Desktop GUI (Asan Desktop UI Design System)
#            Pure GAC Assemblies (Zero Temp DLLs / Zero csc.exe)
#            4-Zone Shell, GDI+ Vector Symbol, Dashed Disabled Buttons + Tooltips,
#            DataGridView, Unified USB Flow, Async Spooler Reset, Error Report
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

function Get-AsanTheme {
 return @{
  AsanGreen      = [System.Drawing.Color]::FromArgb(0, 103, 105)
  AsanDeep       = [System.Drawing.Color]::FromArgb(0, 77, 79)
  HeaderBg       = [System.Drawing.Color]::FromArgb(0, 86, 88)
  HeaderSubFg    = [System.Drawing.Color]::FromArgb(202, 232, 231)
  HeaderUtilBg   = [System.Drawing.Color]::FromArgb(16, 112, 114)
  HeaderUtilHov  = [System.Drawing.Color]::FromArgb(24, 132, 134)
  HeaderUtilBord = [System.Drawing.Color]::FromArgb(95, 170, 169)
  GridHeadBg     = [System.Drawing.Color]::FromArgb(11, 79, 81)
  GridHeadFg     = [System.Drawing.Color]::White
  AsanLight      = [System.Drawing.Color]::FromArgb(2, 128, 168)
  InfoTint       = [System.Drawing.Color]::FromArgb(226, 243, 249)
  InfoBord       = [System.Drawing.Color]::FromArgb(124, 192, 214)
  AsanMint       = [System.Drawing.Color]::FromArgb(228, 242, 241)
  AsanMintSoft   = [System.Drawing.Color]::FromArgb(217, 231, 230)
  AsanMintHover  = [System.Drawing.Color]::FromArgb(204, 229, 227)
  AsanMintBorder = [System.Drawing.Color]::FromArgb(95, 160, 158)
  MetaBarBg      = [System.Drawing.Color]::FromArgb(237, 243, 243)
  BadgeOnlineBg  = [System.Drawing.Color]::FromArgb(20, 138, 94)
  AsanOrange     = [System.Drawing.Color]::FromArgb(224, 112, 8)
  AsanOrangeDeep = [System.Drawing.Color]::FromArgb(191, 90, 4)
  AsanOrangeLine = [System.Drawing.Color]::FromArgb(246, 139, 31)
  AsanOrangeText = [System.Drawing.Color]::FromArgb(154, 71, 0)
  AsanOrangeTint = [System.Drawing.Color]::FromArgb(255, 241, 222)
  AsanOrangeBord = [System.Drawing.Color]::FromArgb(224, 156, 82)
  DangerRed      = [System.Drawing.Color]::FromArgb(192, 57, 43)
  DangerRedDeep  = [System.Drawing.Color]::FromArgb(158, 38, 28)
  DangerRedTint  = [System.Drawing.Color]::FromArgb(253, 236, 234)
  DangerRedBord  = [System.Drawing.Color]::FromArgb(217, 130, 121)
  SpecialPurple  = [System.Drawing.Color]::FromArgb(98, 36, 198)
  SpecialTint    = [System.Drawing.Color]::FromArgb(242, 236, 255)
  CanvasBg       = [System.Drawing.Color]::FromArgb(231, 238, 238)
  CardBg         = [System.Drawing.Color]::White
  RowAltBg       = [System.Drawing.Color]::FromArgb(244, 248, 248)
  Border         = [System.Drawing.Color]::FromArgb(198, 212, 211)
  GridLine       = [System.Drawing.Color]::FromArgb(211, 223, 223)
  BorderBtn      = [System.Drawing.Color]::FromArgb(142, 165, 164)
  InkPrimary     = [System.Drawing.Color]::FromArgb(20, 34, 35)
  InkSecondary   = [System.Drawing.Color]::FromArgb(47, 66, 68)
  InkMuted       = [System.Drawing.Color]::FromArgb(80, 99, 101)
  DisabledBg     = [System.Drawing.Color]::FromArgb(241, 243, 243)
  DisabledFg     = [System.Drawing.Color]::FromArgb(148, 160, 162)
  DisabledBorder = [System.Drawing.Color]::FromArgb(192, 204, 204)
  LogBg          = [System.Drawing.Color]::FromArgb(22, 34, 35)
  LogFg          = [System.Drawing.Color]::FromArgb(226, 236, 235)
 }
}

function New-AsanFontSet {
 return @{
  Base     = New-Object System.Drawing.Font("Malgun Gothic", 9, [System.Drawing.FontStyle]::Regular)
  Bold     = New-Object System.Drawing.Font("Malgun Gothic", 9, [System.Drawing.FontStyle]::Bold)
  Tab      = New-Object System.Drawing.Font("Malgun Gothic", 9.5, [System.Drawing.FontStyle]::Bold)
  TabIdle  = New-Object System.Drawing.Font("Malgun Gothic", 9.5, [System.Drawing.FontStyle]::Regular)
  Title    = New-Object System.Drawing.Font("Malgun Gothic", 12.5, [System.Drawing.FontStyle]::Bold)
  Subtitle = New-Object System.Drawing.Font("Malgun Gothic", 8.5, [System.Drawing.FontStyle]::Regular)
  Small    = New-Object System.Drawing.Font("Malgun Gothic", 8.5, [System.Drawing.FontStyle]::Regular)
  SmallB   = New-Object System.Drawing.Font("Malgun Gothic", 8.5, [System.Drawing.FontStyle]::Bold)
  Metric   = New-Object System.Drawing.Font("Malgun Gothic", 10, [System.Drawing.FontStyle]::Bold)
  Mono     = New-Object System.Drawing.Font("Consolas", 8.5, [System.Drawing.FontStyle]::Regular)
 }
}

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
 $d = $r * 2.0
 $path = New-Object System.Drawing.Drawing2D.GraphicsPath
 $path.AddArc($x, $y, $d, $d, 180, 90)
 $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
 $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
 $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
 $path.CloseFigure()
 return $path
}

# Custom GDI+ Vector Symbol (no copyrighted logos; clean disk/boot + orange check badge)
function New-SidToolSymbolBitmap([int]$size = 40) {
 $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
 $g = [System.Drawing.Graphics]::FromImage($bmp)
 try {
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)

  $s = [float]$size
  $pad = $s * 0.05
  $bgPath = New-RoundedRectPath $pad $pad ($s - $pad * 2) ($s - $pad * 2) ($s * 0.22)
  $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(16, 112, 114))
  $bgPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(95, 170, 169), [math]::Max(1.0, $s * 0.03))
  try {
   $g.FillPath($bgBrush, $bgPath)
   $g.DrawPath($bgPen, $bgPath)
  } finally {
   $bgPath.Dispose(); $bgBrush.Dispose(); $bgPen.Dispose()
  }

  # Crisp white drive / boot silhouette
  $wBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $tBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 86, 88))
  $wPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [math]::Max(1.5, $s * 0.055))
  $wPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $wPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $wPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  try {
   # Drive body
   $drvPath = New-RoundedRectPath ($s * 0.20) ($s * 0.50) ($s * 0.54) ($s * 0.24) ($s * 0.06)
   try { $g.FillPath($wBrush, $drvPath) } finally { $drvPath.Dispose() }
   # Drive LED dot
   $g.FillEllipse($tBrush, ($s * 0.27), ($s * 0.59), ($s * 0.07), ($s * 0.07))
   # Boot arrow rising above drive
   $g.DrawLine($wPen, ($s * 0.47), ($s * 0.44), ($s * 0.47), ($s * 0.22))
   $g.DrawLine($wPen, ($s * 0.34), ($s * 0.34), ($s * 0.47), ($s * 0.21))
   $g.DrawLine($wPen, ($s * 0.60), ($s * 0.34), ($s * 0.47), ($s * 0.21))
  } finally {
   $wBrush.Dispose(); $tBrush.Dispose(); $wPen.Dispose()
  }

  # Asan Orange status badge dot + white check
  $bSize = $s * 0.34
  $bx = $s - $bSize - ($s * 0.04)
  $by = $s - $bSize - ($s * 0.04)
  $oBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(246, 139, 31))
  $oPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0, 86, 88), [math]::Max(1.2, $s * 0.035))
  $cPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [math]::Max(1.5, $s * 0.05))
  $cPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $cPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $cPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
  try {
   $g.FillEllipse($oBrush, $bx, $by, $bSize, $bSize)
   $g.DrawEllipse($oPen, $bx, $by, $bSize, $bSize)
   $g.DrawLine($cPen, ($bx + $bSize * 0.26), ($by + $bSize * 0.52), ($bx + $bSize * 0.45), ($by + $bSize * 0.70))
   $g.DrawLine($cPen, ($bx + $bSize * 0.45), ($by + $bSize * 0.70), ($bx + $bSize * 0.74), ($by + $bSize * 0.34))
  } finally {
   $oBrush.Dispose(); $oPen.Dispose(); $cPen.Dispose()
  }
 } finally {
  $g.Dispose()
 }
 return $bmp
}

# PNG-in-ICO 22-byte header conversion (zero GetHicon() native handle leak)
function New-AsanIconFromBitmap([System.Drawing.Bitmap]$bmp) {
 $pngMs = New-Object System.IO.MemoryStream
 $icoMs = New-Object System.IO.MemoryStream
 try {
  $bmp.Save($pngMs, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngBytes = $pngMs.ToArray()
  $wByte = if ($bmp.Width -ge 256) { [byte]0 } else { [byte]$bmp.Width }
  $hByte = if ($bmp.Height -ge 256) { [byte]0 } else { [byte]$bmp.Height }
  $len = [int]$pngBytes.Length
  $hdr = [byte[]]@(
   0, 0, 1, 0, 1, 0,
   $wByte, $hByte, 0, 0, 1, 0, 32, 0,
   [byte]($len -band 0xFF),
   [byte](($len -shr 8) -band 0xFF),
   [byte](($len -shr 16) -band 0xFF),
   [byte](($len -shr 24) -band 0xFF),
   22, 0, 0, 0
  )
  $icoMs.Write($hdr, 0, $hdr.Length)
  $icoMs.Write($pngBytes, 0, $pngBytes.Length)
  $icoMs.Position = 0
  return (New-Object System.Drawing.Icon($icoMs))
 } finally {
  $pngMs.Dispose()
  $icoMs.Dispose()
 }
}

function Get-AsanButtonStyleSpec([string]$variant, $theme) {
 switch ($variant) {
  "Primary"       { return @{ Bg = $theme.AsanGreen;     Fg = [System.Drawing.Color]::White; Hover = $theme.AsanDeep;       Border = $theme.AsanDeep;       BorderSize = 1; Bold = $true } }
  "SoftTeal"      { return @{ Bg = $theme.AsanMint;      Fg = $theme.AsanDeep;               Hover = $theme.AsanMintHover;  Border = $theme.AsanMintBorder; BorderSize = 1; Bold = $true } }
  "Orange"        { return @{ Bg = $theme.AsanOrange;    Fg = [System.Drawing.Color]::White; Hover = $theme.AsanOrangeDeep; Border = $theme.AsanOrangeDeep; BorderSize = 1; Bold = $true } }
  "SoftOrange"    { return @{ Bg = $theme.AsanOrangeTint;Fg = $theme.AsanOrangeText;         Hover = $theme.AsanOrangeBord; Border = $theme.AsanOrangeBord; BorderSize = 1; Bold = $true } }
  "Danger"        { return @{ Bg = $theme.DangerRed;     Fg = [System.Drawing.Color]::White; Hover = $theme.DangerRedDeep;  Border = $theme.DangerRedDeep;  BorderSize = 1; Bold = $true } }
  "DangerOutline" { return @{ Bg = $theme.DangerRedTint; Fg = $theme.DangerRedDeep;          Hover = $theme.DangerRedBord;  Border = $theme.DangerRedBord;  BorderSize = 1; Bold = $true } }
  "HeaderUtil"    { return @{ Bg = $theme.HeaderUtilBg;  Fg = [System.Drawing.Color]::White; Hover = $theme.HeaderUtilHov;  Border = $theme.HeaderUtilBord; BorderSize = 1; Bold = $true } }
  default         { return @{ Bg = $theme.CardBg;        Fg = $theme.InkPrimary;             Hover = $theme.RowAltBg;       Border = $theme.BorderBtn;      BorderSize = 1; Bold = $true } }
 }
}

function Apply-AsanButtonVisual($btn, $uiCtx) {
 if (-not $btn -or $btn.IsDisposed -or -not $uiCtx) { return }
 if (-not $uiCtx.ButtonStyles.ContainsKey($btn)) { return }
 $st = $uiCtx.ButtonStyles[$btn]
 $t = $uiCtx.Theme
 if ($btn.Enabled) {
  $btn.BackColor = $st.Bg
  $btn.ForeColor = $st.Fg
  $btn.FlatAppearance.BorderSize = $st.BorderSize
  $btn.FlatAppearance.BorderColor = $st.Border
  $btn.FlatAppearance.MouseOverBackColor = $st.Hover
  $btn.FlatAppearance.MouseDownBackColor = $st.Hover
  $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
 } else {
  $btn.BackColor = $t.DisabledBg
  $btn.ForeColor = $t.DisabledFg
  $btn.FlatAppearance.BorderSize = 0
  $btn.FlatAppearance.BorderColor = $t.DisabledBorder
  $btn.FlatAppearance.MouseOverBackColor = $t.DisabledBg
  $btn.FlatAppearance.MouseDownBackColor = $t.DisabledBg
  $btn.Cursor = [System.Windows.Forms.Cursors]::Default
 }
 $btn.Invalidate()
}

function Set-AsanButtonVariant($btn, [string]$variant, $uiCtx) {
 if (-not $btn -or $btn.IsDisposed -or -not $uiCtx) { return }
 $uiCtx.ButtonStyles[$btn] = Get-AsanButtonStyleSpec $variant $uiCtx.Theme
 Apply-AsanButtonVisual $btn $uiCtx
}

function Set-AsanButtonState($btn, [bool]$enabled, [string]$disabledReason, $uiCtx, [string]$variant = "") {
 if (-not $btn -or $btn.IsDisposed -or -not $uiCtx) { return }
 if ($variant) {
  $uiCtx.ButtonStyles[$btn] = Get-AsanButtonStyleSpec $variant $uiCtx.Theme
 }
 if ($enabled) {
  if ($uiCtx.DisabledReasons.ContainsKey($btn)) { $uiCtx.DisabledReasons.Remove($btn) }
  if ($uiCtx.LastDisabledBtn -eq $btn -and $uiCtx.LastDisabledHost -and $uiCtx.ToolTip) {
   try { $uiCtx.ToolTip.Hide($uiCtx.LastDisabledHost) } catch {}
   $uiCtx.LastDisabledBtn = $null
   $uiCtx.LastDisabledHost = $null
  }
 } elseif (-not [string]::IsNullOrWhiteSpace($disabledReason)) {
  $uiCtx.DisabledReasons[$btn] = $disabledReason
 }
 if ($btn.Enabled -ne $enabled) { $btn.Enabled = $enabled }
 Apply-AsanButtonVisual $btn $uiCtx
}

function New-AsanButton([string]$text, [int]$width, [int]$height, [string]$variant, $uiCtx, [bool]$smallFont = $false) {
 $btn = New-Object System.Windows.Forms.Button
 $btn.Text = $text
 $btn.Size = New-Object System.Drawing.Size($width, $height)
 $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
 $btn.UseVisualStyleBackColor = $false
 $btn.TabStop = $true
 $btn.Font = if ($smallFont) { $uiCtx.Fonts.SmallB } else { $uiCtx.Fonts.Bold }
 $uiCtx.ButtonStyles[$btn] = Get-AsanButtonStyleSpec $variant $uiCtx.Theme
 Apply-AsanButtonVisual $btn $uiCtx

 $localCtx = $uiCtx
 $btn.Add_EnabledChanged({
  param($sender, $e)
  Apply-AsanButtonVisual $sender $localCtx
 }.GetNewClosure())

 # Custom dashed disabled button renderer (never relies on WinForms GrayText)
 $btn.Add_Paint({
  param($sender, $e)
  if ($sender.Enabled) { return }
  $t = $localCtx.Theme
  $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
  $bgBrush = New-Object System.Drawing.SolidBrush($t.DisabledBg)
  $dashPen = New-Object System.Drawing.Pen($t.DisabledBorder, 1)
  $dashPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
  try {
   $e.Graphics.FillRectangle($bgBrush, $rect)
   $e.Graphics.DrawRectangle($dashPen, 0, 0, ($sender.Width - 1), ($sender.Height - 1))
   $drawFont = if ($sender.Font.Size -lt 8.8) { $localCtx.Fonts.Small } else { $localCtx.Fonts.Base }
   $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
   [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $sender.Text, $drawFont, $rect, $t.DisabledFg, $flags)
  } finally {
   $bgBrush.Dispose()
   $dashPen.Dispose()
  }
 }.GetNewClosure())

 return $btn
}

# Route MouseMove/MouseLeave on parent containers so disabled buttons still show reason tooltips
function Register-AsanDisabledTooltipTree($root, $uiCtx) {
 if (-not $root -or $root.IsDisposed) { return }
 $hasChildBtn = $false
 foreach ($ch in $root.Controls) {
  if ($ch -is [System.Windows.Forms.Button]) { $hasChildBtn = $true }
  if ($ch.Controls.Count -gt 0) { Register-AsanDisabledTooltipTree $ch $uiCtx }
 }
 if ($hasChildBtn) {
  $localCtx = $uiCtx
  $root.Add_MouseMove({
   param($sender, $e)
   if (-not $localCtx.ToolTip) { return }
   $hit = $sender.GetChildAtPoint($e.Location)
   if ($hit -and ($hit -is [System.Windows.Forms.Button]) -and (-not $hit.Enabled)) {
    $reason = ""
    if ($localCtx.DisabledReasons.ContainsKey($hit)) {
     $reason = [string]$localCtx.DisabledReasons[$hit]
    } elseif ($localCtx.State -and $localCtx.State.IsBusy) {
     $reason = U "\uD604\uC7AC \uC791\uC5C5\uC774 \uC9C4\uD589 \uC911\uC785\uB2C8\uB2E4. \uC644\uB8CC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694."
    }
    if (-not [string]::IsNullOrWhiteSpace($reason)) {
     if ($localCtx.LastDisabledBtn -ne $hit) {
      if ($localCtx.LastDisabledHost) { try { $localCtx.ToolTip.Hide($localCtx.LastDisabledHost) } catch {} }
      try {
       $localCtx.ToolTip.Show($reason, $sender, ($hit.Left + 4), ($hit.Bottom + 4), 7000)
       $localCtx.LastDisabledBtn = $hit
       $localCtx.LastDisabledHost = $sender
      } catch {}
     }
     return
    }
   }
   if ($localCtx.LastDisabledBtn -and $localCtx.LastDisabledHost) {
    try { $localCtx.ToolTip.Hide($localCtx.LastDisabledHost) } catch {}
    $localCtx.LastDisabledBtn = $null
    $localCtx.LastDisabledHost = $null
   }
  }.GetNewClosure())

  $root.Add_MouseLeave({
   param($sender, $e)
   if ($localCtx.LastDisabledHost -eq $sender -and $localCtx.ToolTip) {
    try { $localCtx.ToolTip.Hide($sender) } catch {}
    $localCtx.LastDisabledBtn = $null
    $localCtx.LastDisabledHost = $null
   }
  }.GetNewClosure())
 }
}

# DPI-safe right-aligned flow strip (NEVER uses Anchor=Right!)
function New-RightFlowStrip([int]$padTop = 0, [int]$padRight = 0, [int]$padBottom = 0) {
 $flp = New-Object System.Windows.Forms.FlowLayoutPanel
 $flp.Dock = [System.Windows.Forms.DockStyle]::Right
 $flp.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
 $flp.WrapContents = $false
 $flp.AutoSize = $true
 $flp.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
 $flp.BackColor = [System.Drawing.Color]::Transparent
 $flp.Margin = New-Object System.Windows.Forms.Padding(0)
 $flp.Padding = New-Object System.Windows.Forms.Padding(0, $padTop, $padRight, $padBottom)
 return $flp
}

# Padded multiline TextBox wrapper so text never touches borders
function New-PaddedTextBoxPanel($backColor, $foreColor, $font, [int]$padX = 10, [int]$padY = 6, [bool]$readOnly = $true, [string]$initialText = "", [System.Windows.Forms.ScrollBars]$scrollBars = [System.Windows.Forms.ScrollBars]::Vertical, [bool]$wordWrap = $true) {
 $wrap = New-Object System.Windows.Forms.Panel
 $wrap.Dock = [System.Windows.Forms.DockStyle]::Fill
 $wrap.BackColor = $backColor
 $wrap.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
 $wrap.Padding = New-Object System.Windows.Forms.Padding($padX, $padY, ([math]::Max(4, $padX - 2)), $padY)

 $tb = New-Object System.Windows.Forms.TextBox
 $tb.Dock = [System.Windows.Forms.DockStyle]::Fill
 $tb.Multiline = $true
 $tb.ReadOnly = $readOnly
 $tb.WordWrap = $wordWrap
 $tb.ScrollBars = $scrollBars
 $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
 $tb.BackColor = $backColor
 $tb.ForeColor = $foreColor
 $tb.Font = $font
 if (-not [string]::IsNullOrEmpty($initialText)) { $tb.Text = $initialText }

 $wrap.Controls.Add($tb)
 return [PSCustomObject]@{ Panel = $wrap; TextBox = $tb }
}

# High-contrast Asan DataGridView factory (deep teal header, 32px rows, double-buffered)
function New-AsanGrid($theme, $fonts) {
 $dgv = New-Object System.Windows.Forms.DataGridView
 $dgv.Dock = [System.Windows.Forms.DockStyle]::Fill
 $dgv.BackgroundColor = $theme.CardBg
 $dgv.BorderStyle = [System.Windows.Forms.BorderStyle]::None
 $dgv.GridColor = $theme.GridLine
 $dgv.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
 $dgv.ColumnHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None
 $dgv.EnableHeadersVisualStyles = $false
 $dgv.RowHeadersVisible = $false
 $dgv.AllowUserToAddRows = $false
 $dgv.AllowUserToDeleteRows = $false
 $dgv.AllowUserToResizeRows = $false
 $dgv.AllowUserToOrderColumns = $false
 $dgv.ReadOnly = $true
 $dgv.MultiSelect = $false
 $dgv.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
 $dgv.ShowCellToolTips = $true
 $dgv.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
 $dgv.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
 $dgv.ColumnHeadersHeight = 34
 $dgv.RowTemplate.Height = 32

 $dgv.ColumnHeadersDefaultCellStyle.BackColor = $theme.GridHeadBg
 $dgv.ColumnHeadersDefaultCellStyle.ForeColor = $theme.GridHeadFg
 $dgv.ColumnHeadersDefaultCellStyle.Font = $fonts.Bold
 $dgv.ColumnHeadersDefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False
 $dgv.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 2)
 $dgv.ColumnHeadersDefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleLeft
 $dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = $theme.GridHeadBg
 $dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = $theme.GridHeadFg

 $dgv.DefaultCellStyle.BackColor = $theme.CardBg
 $dgv.DefaultCellStyle.ForeColor = $theme.InkPrimary
 $dgv.DefaultCellStyle.Font = $fonts.Base
 $dgv.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 2)
 $dgv.DefaultCellStyle.SelectionBackColor = $theme.AsanMint
 $dgv.DefaultCellStyle.SelectionForeColor = $theme.AsanDeep
 $dgv.AlternatingRowsDefaultCellStyle.BackColor = $theme.RowAltBg
 $dgv.AlternatingRowsDefaultCellStyle.ForeColor = $theme.InkPrimary

 try {
  $prop = [System.Windows.Forms.DataGridView].GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance,NonPublic")
  if ($prop) { $prop.SetValue($dgv, $true, $null) }
 } catch {}

 return $dgv
}

function Add-AsanGridColumn($dgv, [string]$name, [string]$headerText, [int]$width, [bool]$isFill = $false, [int]$minWidth = 54) {
 $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
 $col.Name = $name
 $col.HeaderText = $headerText
 $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
 $col.MinimumWidth = $minWidth
 if ($isFill) {
  $col.AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
 } else {
  $col.Width = $width
 }
 [void]$dgv.Columns.Add($col)
}

function Set-AsanCellSemanticStyle($cell, [string]$kind, $theme, $fonts, [bool]$bold = $true) {
 if (-not $cell) { return }
 if ($bold) { $cell.Style.Font = $fonts.Bold }
 switch ($kind) {
  "OK"      { $cell.Style.BackColor = $theme.AsanMint;       $cell.Style.ForeColor = $theme.AsanDeep }
  "Info"    { $cell.Style.BackColor = $theme.InfoTint;       $cell.Style.ForeColor = $theme.AsanLight }
  "Warn"    { $cell.Style.BackColor = $theme.AsanOrangeTint; $cell.Style.ForeColor = $theme.AsanOrangeText }
  "Error"   { $cell.Style.BackColor = $theme.DangerRedTint;  $cell.Style.ForeColor = $theme.DangerRedDeep }
  "Special" { $cell.Style.BackColor = $theme.SpecialTint;    $cell.Style.ForeColor = $theme.SpecialPurple }
  default   { $cell.Style.ForeColor = $theme.InkMuted; $cell.Style.Font = $fonts.Base }
 }
}

function Set-AsanGuidanceBannerVisual($panel, $accentBar, $lblTitle, $lblMsg, $guidance, $theme) {
 $bg = $theme.InfoTint; $fg = $theme.AsanLight; $ac = $theme.AsanLight
 switch ($guidance.Level) {
  "OK"    { $bg = $theme.AsanMint;       $fg = $theme.AsanDeep;       $ac = $theme.AsanGreen }
  "Warn"  { $bg = $theme.AsanOrangeTint; $fg = $theme.AsanOrangeText; $ac = $theme.AsanOrange }
  "Error" { $bg = $theme.DangerRedTint;  $fg = $theme.DangerRedDeep;  $ac = $theme.DangerRed }
 }
 $panel.BackColor = $bg
 $accentBar.BackColor = $ac
 $lblTitle.ForeColor = $fg
 $lblTitle.Text = [string]$guidance.Title
 $lblMsg.ForeColor = $theme.InkPrimary
 $lblMsg.Text = [string]$guidance.Message
}

# OwnerDrawFixed numbered tabs matching Asan Desktop UI
function Enable-AsanOwnerDrawTabs($tabControl, $theme, $fonts) {
 $tabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed
 $tabControl.SizeMode = [System.Windows.Forms.TabSizeMode]::Fixed
 $tabControl.ItemSize = New-Object System.Drawing.Size(220, 34)
 $tabControl.Padding = New-Object System.Drawing.Point(18, 6)

 $localTheme = $theme
 $localFonts = $fonts
 $tabControl.Add_DrawItem({
  param($sender, $e)
  $tp = $sender.TabPages[$e.Index]
  $rect = $e.Bounds
  $isSel = ($sender.SelectedIndex -eq $e.Index)
  $bgCol = if ($isSel) { $localTheme.CardBg } else { $localTheme.AsanMintSoft }
  $fgCol = if ($isSel) { $localTheme.AsanDeep } else { $localTheme.InkSecondary }
  $fnt = if ($isSel) { $localFonts.Tab } else { $localFonts.TabIdle }

  $bgBrush = New-Object System.Drawing.SolidBrush($bgCol)
  $barBrush = New-Object System.Drawing.SolidBrush($localTheme.AsanGreen)
  $borderPen = New-Object System.Drawing.Pen($localTheme.Border, 1)
  try {
   $e.Graphics.FillRectangle($bgBrush, $rect)
   if ($isSel) {
    $e.Graphics.FillRectangle($barBrush, $rect.X, $rect.Y, $rect.Width, 4)
   }
   $e.Graphics.DrawRectangle($borderPen, $rect.X, $rect.Y, ($rect.Width - 1), ($rect.Height - 1))
   $textRect = New-Object System.Drawing.Rectangle($rect.X, ($rect.Y + 2), $rect.Width, ($rect.Height - 2))
   $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis
   [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $tp.Text.Trim(), $fnt, $textRect, $fgCol, $flags)
  } finally {
   $bgBrush.Dispose()
   $barBrush.Dispose()
   $borderPen.Dispose()
  }
 }.GetNewClosure())
}

function Build-FullDiagnosticBundleText($sysInfo, $step2Snap, $postStatus, [string]$logText) {
 $sb = New-Object System.Text.StringBuilder
 $biosText = if ($step2Snap -and $step2Snap.BiosDiag) {
  Format-BiosCrossCheckReport $sysInfo $step2Snap.BiosDiag $step2Snap.UsbInfo $step2Snap.MatchedEntries
 } else {
  U "BIOS \uC9C4\uB2E8 \uC815\uBCF4\uAC00 \uC544\uC9C1 \uC218\uC9D1\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4."
 }
 $nvramText = if ($step2Snap -and $step2Snap.BcdOutput -and $step2Snap.BcdOutput.Count -gt 0) {
  ($step2Snap.BcdOutput -join "`r`n")
 } else {
  U "UEFI NVRAM \uCD9C\uB825\uC774 \uC5C6\uC2B5\uB2C8\uB2E4."
 }
 $diskText = Get-DiskDebugText

 [void]$sb.AppendLine($biosText)
 [void]$sb.AppendLine("")
 [void]$sb.AppendLine("=== UEFI NVRAM (bcdedit /enum firmware) ===")
 [void]$sb.AppendLine($nvramText)
 [void]$sb.AppendLine("")
 [void]$sb.AppendLine("=== Disk and Partition Layout ===")
 [void]$sb.AppendLine($diskText)
 if ($postStatus) {
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("=== Post-SID Printer Spooler Summary ===")
  [void]$sb.AppendLine(("ComputerName : " + $postStatus.ComputerName))
  [void]$sb.AppendLine(("MachineSID   : " + $postStatus.MachineSid))
  [void]$sb.AppendLine(("Role         : " + $postStatus.Role))
  [void]$sb.AppendLine(("Spooler      : " + $postStatus.SpoolerStatus + " / " + $postStatus.SpoolerStartMode))
  [void]$sb.AppendLine(("QueueFiles   : " + $postStatus.QueueTotalCount + " (SPL/SHD=" + $postStatus.QueueSplShdCount + ")"))
  [void]$sb.AppendLine(("Printers     : " + $postStatus.Printers.Count + " | Shared=" + $postStatus.SharedPrinters.Count + " | Network=" + $postStatus.NetworkPrinters.Count))
 }
 if (-not [string]::IsNullOrWhiteSpace($logText)) {
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("=== Session Log ===")
  [void]$sb.AppendLine($logText)
 }
 return (ConvertTo-MaskedDiagnosticText $sb.ToString())
}

# Save sanitized local diagnostic report (never writes to source USB/share folder)
function Save-LocalDiagnosticReportFile([string]$content) {
 $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
 $fileName = "SID_Aux_Diag_" + $env:COMPUTERNAME + "_" + $stamp + ".txt"
 $srcDir = ""
 if ($env:SELF_PATH) { try { $srcDir = Split-Path -Parent $env:SELF_PATH } catch {} }
 $candidates = @(
  ([Environment]::GetFolderPath("Desktop")),
  ([Environment]::GetFolderPath("MyDocuments")),
  $env:TEMP
 )
 foreach ($dir in $candidates) {
  if ([string]::IsNullOrWhiteSpace($dir)) { continue }
  if ($srcDir -and ($dir.TrimEnd('\') -ieq $srcDir.TrimEnd('\'))) { continue }
  try {
   if (-not (Test-Path -LiteralPath $dir)) { continue }
   $fullPath = Join-Path $dir $fileName
   $utf8Bom = New-Object System.Text.UTF8Encoding($true)
   [System.IO.File]::WriteAllText($fullPath, (ConvertTo-MaskedDiagnosticText $content), $utf8Bom)
   return [PSCustomObject]@{ Success = $true; Path = $fullPath; Folder = $dir; Error = "" }
  } catch {}
 }
 return [PSCustomObject]@{ Success = $false; Path = ""; Folder = ""; Error = (U "\uB85C\uCEEC \uD3F4\uB354\uC5D0 \uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8\uB97C \uC800\uC7A5\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.") }
}

# Build Diagnostic & Error Report Dialog (testable factory + modal wrapper)
function New-GuiDiagnosticsDialog($sysInfo, $step2Snap, $postStatus, [string]$logText, [string]$errorSummary = "") {
 Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
 Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
 $theme = Get-AsanTheme
 $fonts = New-AsanFontSet
 $dlgIconBmp = New-SidToolSymbolBitmap 64
 $dlgIcon = New-AsanIconFromBitmap $dlgIconBmp
 $dlgIconBmp.Dispose()
 $dlg = New-Object System.Windows.Forms.Form
 $dlg.Icon = $dlgIcon
 $dlg.Text = if ($errorSummary) { U "\uC624\uB958 \uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8 \uC800\uC7A5" } else { U "BIOS \uAD50\uCC28 \uAC80\uC99D \uBC0F \uC2DC\uC2A4\uD15C \uC9C4\uB2E8" }
 $dlg.Size = New-Object System.Drawing.Size(880, 620)
 $dlg.MinimumSize = New-Object System.Drawing.Size(720, 480)
 $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
 $dlg.BackColor = $theme.CanvasBg
 $dlg.Font = $fonts.Base
 $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font

 $dlgCtx = @{
  Theme = $theme; Fonts = $fonts; ToolTip = (New-Object System.Windows.Forms.ToolTip)
  ButtonStyles = @{}; DisabledReasons = @{}; LastDisabledBtn = $null; LastDisabledHost = $null; State = $null
 }

 # Header
 $hdr = New-Object System.Windows.Forms.Panel
 $hdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $hdr.Height = 52
 $hdr.BackColor = $theme.HeaderBg
 $hdr.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
 $lblT = New-Object System.Windows.Forms.Label
 $lblT.Text = if ($errorSummary) { U "\uC624\uB958 \uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8" } else { U "BIOS \uAD50\uCC28 \uAC80\uC99D \uBC0F \uC2DC\uC2A4\uD15C \uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8" }
 $lblT.Font = $fonts.Title
 $lblT.ForeColor = [System.Drawing.Color]::White
 $lblT.AutoSize = $true
 $lblT.Location = New-Object System.Drawing.Point(16, 6)
 $lblS = New-Object System.Windows.Forms.Label
 $lblS.Text = U "\uBBFC\uAC10\uD55C \uC790\uACA9 \uC99D\uBA85 \uC815\uBCF4\uB294 \uC790\uB3D9\uC73C\uB85C \uAC00\uB824\uC9D1\uB2C8\uB2E4. \uB2F4\uB2F9\uC790\uC5D0\uAC8C \uD30C\uC77C \uB610\uB294 \uBCF5\uC0AC \uB0B4\uC6A9\uC744 \uC804\uB2EC\uD574 \uC8FC\uC138\uC694."
 $lblS.Font = $fonts.Subtitle
 $lblS.ForeColor = $theme.HeaderSubFg
 $lblS.AutoSize = $true
 $lblS.Location = New-Object System.Drawing.Point(17, 30)
 $hdr.Controls.Add($lblT)
 $hdr.Controls.Add($lblS)

 $oLine = New-Object System.Windows.Forms.Panel
 $oLine.Dock = [System.Windows.Forms.DockStyle]::Top
 $oLine.Height = 2
 $oLine.BackColor = $theme.AsanOrangeLine

 $errBanner = New-Object System.Windows.Forms.Panel
 $errBanner.Dock = [System.Windows.Forms.DockStyle]::Top
 $errBanner.Height = 40
 $errBanner.BackColor = $theme.AsanOrangeTint
 $errBanner.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 8)
 $errBanner.Visible = (-not [string]::IsNullOrWhiteSpace($errorSummary))
 $lblErr = New-Object System.Windows.Forms.Label
 $lblErr.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblErr.ForeColor = $theme.AsanOrangeText
 $lblErr.Font = $fonts.Bold
 $lblErr.Text = (U "\uC624\uB958 \uC694\uC57D: ") + $errorSummary
 $errBanner.Controls.Add($lblErr)

 $biosText = if ($step2Snap -and $step2Snap.BiosDiag) {
  ConvertTo-MaskedDiagnosticText (Format-BiosCrossCheckReport $sysInfo $step2Snap.BiosDiag $step2Snap.UsbInfo $step2Snap.MatchedEntries)
 } else {
  U "BIOS \uC9C4\uB2E8 \uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4."
 }
 $nvramText = if ($step2Snap -and $step2Snap.BcdOutput -and $step2Snap.BcdOutput.Count -gt 0) {
  ConvertTo-MaskedDiagnosticText ($step2Snap.BcdOutput -join "`r`n")
 } else {
  U "UEFI NVRAM \uCD9C\uB825\uC774 \uC5C6\uC2B5\uB2C8\uB2E4."
 }
 $diskText = ConvertTo-MaskedDiagnosticText (Get-DiskDebugText)
 $safeLog = if ([string]::IsNullOrWhiteSpace($logText)) { U "\uAE30\uB85D\uB41C \uC791\uC5C5 \uB85C\uADF8\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4." } else { ConvertTo-MaskedDiagnosticText $logText }
 if ($errorSummary) { $safeLog = (U "\uBC1C\uC0DD \uC624\uB958: ") + $errorSummary + "`r`n`r`n" + $safeLog }
 $copyPayload = Build-FullDiagnosticBundleText $sysInfo $step2Snap $postStatus $safeLog

 $bodyWrap = New-Object System.Windows.Forms.Panel
 $bodyWrap.Dock = [System.Windows.Forms.DockStyle]::Fill
 $bodyWrap.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)

 $tabs = New-Object System.Windows.Forms.TabControl
 $tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
 Enable-AsanOwnerDrawTabs $tabs $theme $fonts
 $tabs.ItemSize = New-Object System.Drawing.Size(165, 32)

 $addTab = {
  param([string]$tName, [string]$tBody)
  $tp = New-Object System.Windows.Forms.TabPage
  $tp.Text = $tName
  $tp.BackColor = $theme.CardBg
  $tp.Padding = New-Object System.Windows.Forms.Padding(8)
  $pTb = New-PaddedTextBoxPanel $theme.CardBg $theme.InkPrimary $fonts.Mono 12 8 $true $tBody ([System.Windows.Forms.ScrollBars]::Both) $false
  $tp.Controls.Add($pTb.Panel)
  [void]$tabs.TabPages.Add($tp)
 }
 & $addTab (U "BIOS \uAD50\uCC28 \uAC80\uC99D") $biosText
 & $addTab (U "UEFI NVRAM \uC6D0\uBCF8") $nvramText
 & $addTab (U "\uB514\uC2A4\uD06C \uAD6C\uC131") $diskText
 & $addTab (U "\uC791\uC5C5 \uB85C\uADF8") $safeLog
 if ($errorSummary) { $tabs.SelectedIndex = 3 }
 $bodyWrap.Controls.Add($tabs)

 $footer = New-Object System.Windows.Forms.Panel
 $footer.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $footer.Height = 50
 $footer.BackColor = $theme.CardBg
 $footer.Padding = New-Object System.Windows.Forms.Padding(16, 9, 16, 9)

 $leftStrip = New-Object System.Windows.Forms.FlowLayoutPanel
 $leftStrip.Dock = [System.Windows.Forms.DockStyle]::Left
 $leftStrip.AutoSize = $true
 $leftStrip.WrapContents = $false

 $btnSave = New-AsanButton (U "\uB85C\uCEEC \uD3F4\uB354\uC5D0 \uC800\uC7A5") 150 32 "Primary" $dlgCtx $false
 $btnSave.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $btnCopy = New-AsanButton (U "\uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uBCF5\uC0AC") 138 32 "SoftTeal" $dlgCtx $false
 $btnCopy.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
 $lblFeedback = New-Object System.Windows.Forms.Label
 $lblFeedback.AutoSize = $true
 $lblFeedback.ForeColor = $theme.AsanDeep
 $lblFeedback.Font = $fonts.SmallB
 $lblFeedback.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
 $lblFeedback.Text = ""

 $leftStrip.Controls.Add($btnSave)
 $leftStrip.Controls.Add($btnCopy)
 $leftStrip.Controls.Add($lblFeedback)

 $rightStrip = New-RightFlowStrip 0 0 0
 $btnClose = New-AsanButton (U "\uB2EB\uAE30") 88 32 "Secondary" $dlgCtx $false
 $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
 $rightStrip.Controls.Add($btnClose)

 $footer.Controls.Add($leftStrip)
 $footer.Controls.Add($rightStrip)

 $btnCopy.Add_Click({
  try {
   [System.Windows.Forms.Clipboard]::SetText($copyPayload)
   $lblFeedback.ForeColor = $theme.AsanDeep
   $lblFeedback.Text = U "\uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8\uAC00 \uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uBCF5\uC0AC\uB418\uC5C8\uC2B5\uB2C8\uB2E4."
  } catch {
   $lblFeedback.ForeColor = $theme.DangerRedDeep
   $lblFeedback.Text = (U "\uD074\uB9BD\uBCF4\uB4DC \uBCF5\uC0AC\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4: ") + $_.Exception.Message
  }
 }.GetNewClosure())

 $btnSave.Add_Click({
  $saved = Save-LocalDiagnosticReportFile $copyPayload
  if ($saved.Success) {
   $lblFeedback.ForeColor = $theme.AsanDeep
   $lblFeedback.Text = (U "\uC800\uC7A5 \uC644\uB8CC: ") + [System.IO.Path]::GetFileName($saved.Path)
   $openQ = (U "\uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8\uB97C \uC800\uC7A5\uD588\uC2B5\uB2C8\uB2E4.`r`n") + $saved.Path + (U "`r`n`r`n\uC800\uC7A5\uB41C \uD3F4\uB354\uB97C \uBC14\uB85C \uC5F4\uC5B4 \uD655\uC778\uD560\uAE4C\uC694?")
   $dr = [System.Windows.Forms.MessageBox]::Show($dlg, $openQ, (U "\uB9AC\uD3EC\uD2B8 \uC800\uC7A5 \uC644\uB8CC"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
   if ($dr -eq [System.Windows.Forms.DialogResult]::Yes) {
    try { Start-Process "explorer.exe" -ArgumentList ('/select,"' + $saved.Path + '"') } catch {}
   }
  } else {
   $lblFeedback.ForeColor = $theme.DangerRedDeep
   $lblFeedback.Text = $saved.Error
  }
 }.GetNewClosure())

 $dlg.Controls.Add($bodyWrap)
 $dlg.Controls.Add($footer)
 $dlg.Controls.Add($errBanner)
 $dlg.Controls.Add($oLine)
 $dlg.Controls.Add($hdr)
 $dlg.CancelButton = $btnClose

 $dlgDisposables = @($dlgCtx.ToolTip, $dlgIcon) + @($fonts.Values)
 $dlg.Tag = $dlgDisposables
 $dlg.Add_FormClosed({
  param($sender, $e)
  $arr = if ($sender -and $sender.Tag) { $sender.Tag } else { $dlgDisposables }
  if ($arr) {
   foreach ($o in $arr) { if ($null -ne $o) { try { $o.Dispose() } catch {} } }
  }
 }.GetNewClosure())
 return $dlg
}

function Show-GuiDiagnosticsDialog($ownerForm, $sysInfo, $step2Snap, $postStatus, [string]$logText, [string]$errorSummary = "") {
 $dlg = New-GuiDiagnosticsDialog $sysInfo $step2Snap $postStatus $logText $errorSummary
 try {
  [void]$dlg.ShowDialog($ownerForm)
 } finally {
  try { $dlg.Dispose() } catch {}
 }
}

# Auto-report prompt on operational errors (Asan Desktop UI Section 6)
function Invoke-GuiErrorReportPrompt($uiCtx, [string]$title, [string]$message, [string]$detail) {
 $prompt = $message + "`r`n`r`n" + (U "\uC624\uB958 \uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8\uB97C \uC790\uB3D9\uC73C\uB85C \uAD6C\uC131\uD574 \uB85C\uCEEC \uD3F4\uB354\uC5D0 \uC800\uC7A5\uD558\uAC70\uB098 \uBCF5\uC0AC\uD560\uAE4C\uC694?`r`nPC \uD658\uACBD\uACFC \uC791\uC5C5 \uB85C\uADF8\uAC00 \uC790\uB3D9 \uCCA8\uBD80\uB418\uBA70 \uBBFC\uAC10 \uC815\uBCF4\uB294 \uC548\uC804\uD558\uAC8C \uAC00\uB824\uC9D1\uB2C8\uB2E4.")
 $ans = [System.Windows.Forms.MessageBox]::Show($uiCtx.Form, $prompt, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Error)
 if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
  Show-GuiDiagnosticsDialog $uiCtx.Form $uiCtx.State.SysInfo $uiCtx.State.Step2Snap $uiCtx.State.PostStatus $uiCtx.TbLog.Text $detail
 }
}

# Modal dialog: Require typing IGNORE to bypass STEP 1 blocking risk (DPI-safe Dock layout)
function Show-GuiIgnoreConfirmDialog($ownerForm) {
 $theme = Get-AsanTheme
 $fonts = New-AsanFontSet
 $dlg = New-Object System.Windows.Forms.Form
 if ($ownerForm -and $ownerForm.Icon) { $dlg.Icon = $ownerForm.Icon }
 $dlg.Text = U "1\uB2E8\uACC4 \uC704\uD5D8 \uD655\uC778 \uD6C4 \uAC74\uB108\uB6F0\uAE30"
 $dlg.Size = New-Object System.Drawing.Size(500, 260)
 $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
 $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
 $dlg.MaximizeBox = $false
 $dlg.MinimizeBox = $false
 $dlg.BackColor = $theme.CardBg
 $dlg.Font = $fonts.Base
 $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font

 $dlgCtx = @{
  Theme = $theme; Fonts = $fonts; ToolTip = (New-Object System.Windows.Forms.ToolTip)
  ButtonStyles = @{}; DisabledReasons = @{}; LastDisabledBtn = $null; LastDisabledHost = $null; State = $null
 }

 $hdr = New-Object System.Windows.Forms.Panel
 $hdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $hdr.Height = 44
 $hdr.BackColor = $theme.DangerRed
 $hdr.Padding = New-Object System.Windows.Forms.Padding(16, 11, 16, 8)
 $lblH = New-Object System.Windows.Forms.Label
 $lblH.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblH.ForeColor = [System.Drawing.Color]::White
 $lblH.Font = $fonts.Bold
 $lblH.Text = U "\uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uB97C \uC815\uB9AC\uD558\uC9C0 \uC54A\uACE0 \uC9C4\uD589\uD558\uBA74 \uBD80\uD305 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4"
 $hdr.Controls.Add($lblH)

 $body = New-Object System.Windows.Forms.Panel
 $body.Dock = [System.Windows.Forms.DockStyle]::Fill
 $body.Padding = New-Object System.Windows.Forms.Padding(16, 14, 16, 10)

 $lblDesc = New-Object System.Windows.Forms.Label
 $lblDesc.Dock = [System.Windows.Forms.DockStyle]::Top
 $lblDesc.Height = 56
 $lblDesc.ForeColor = $theme.InkPrimary
 $lblDesc.Text = U "\uBCF4\uC870 \uB514\uC2A4\uD06C\uC758 \uBD80\uD2B8\uB85C\uB354\uB97C \uADF8\uB300\uB85C \uB450\uACE0 USB \uBD80\uD305\uC744 \uC9C4\uD589\uD569\uB2C8\uB2E4.`r`n\uC704\uD5D8\uC744 \uD655\uC778\uD558\uC168\uB2E4\uBA74 \uC544\uB798 \uC785\uB825\uCE78\uC5D0 \uC601\uBB38 IGNORE \uB97C \uC785\uB825\uD574 \uC8FC\uC138\uC694."

 $tbWrap = New-Object System.Windows.Forms.Panel
 $tbWrap.Dock = [System.Windows.Forms.DockStyle]::Top
 $tbWrap.Height = 32
 $tbWrap.BackColor = $theme.CardBg
 $tbWrap.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
 $tbWrap.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)
 $tb = New-Object System.Windows.Forms.TextBox
 $tb.Dock = [System.Windows.Forms.DockStyle]::Fill
 $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
 $tb.Font = $fonts.Bold
 $tbWrap.Controls.Add($tb)

 $body.Controls.Add($tbWrap)
 $body.Controls.Add($lblDesc)

 $footer = New-Object System.Windows.Forms.Panel
 $footer.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $footer.Height = 50
 $footer.BackColor = $theme.MetaBarBg
 $footer.Padding = New-Object System.Windows.Forms.Padding(16, 9, 16, 9)

 $rightStrip = New-RightFlowStrip 0 0 0
 $btnCancel = New-AsanButton (U "\uCDE8\uC18C") 88 32 "Secondary" $dlgCtx $false
 $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
 $btnOk = New-AsanButton (U "\uC7A0\uAE08 \uD574\uC81C") 104 32 "Danger" $dlgCtx $false
 $btnOk.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
 Set-AsanButtonState $btnOk $false (U "\uC704 \uC785\uB825\uCE78\uC5D0 \uC601\uBB38 IGNORE\uB97C \uC785\uB825\uD558\uBA74 \uD65C\uC131\uD654\uB429\uB2C8\uB2E4.") $dlgCtx

 $rightStrip.Controls.Add($btnCancel)
 $rightStrip.Controls.Add($btnOk)
 $footer.Controls.Add($rightStrip)

 $tb.Add_TextChanged({
  $ready = ($tb.Text.Trim() -ieq "IGNORE")
  Set-AsanButtonState $btnOk $ready (U "\uC704 \uC785\uB825\uCE78\uC5D0 \uC601\uBB38 IGNORE\uB97C \uC785\uB825\uD558\uBA74 \uD65C\uC131\uD654\uB429\uB2C8\uB2E4.") $dlgCtx
 }.GetNewClosure())

 $dlg.Controls.Add($body)
 $dlg.Controls.Add($footer)
 $dlg.Controls.Add($hdr)
 $dlg.AcceptButton = $btnOk
 $dlg.CancelButton = $btnCancel
 Register-AsanDisabledTooltipTree $dlg $dlgCtx

 try {
  $dr = $dlg.ShowDialog($ownerForm)
  return ($dr -eq [System.Windows.Forms.DialogResult]::OK -and $tb.Text.Trim() -ieq "IGNORE")
 } finally {
  try { $dlgCtx.ToolTip.Dispose() } catch {}
  foreach ($f in $fonts.Values) { try { $f.Dispose() } catch {} }
  try { $dlg.Dispose() } catch {}
 }
}

# Build the main WinForms Form using Asan Desktop UI 4-Zone Fixed Shell
function New-SidAuxMainForm($sysInfo, [bool]$autoPopulate = $true) {
 Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
 Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
 [System.Windows.Forms.Application]::EnableVisualStyles()
 $theme = Get-AsanTheme
 $fonts = New-AsanFontSet
 $srcInfo = Get-ExecutionSourceInfo
 $verStr = [string]$script:ToolVersion
 $buildMeta = [string]$script:BuildDate
 $symbolBmp = New-SidToolSymbolBitmap 40
 $appIconBmp = New-SidToolSymbolBitmap 64
 $appIcon = New-AsanIconFromBitmap $appIconBmp
 $appIconBmp.Dispose()

 $state = @{
  SysInfo = $sysInfo
  EfiRep = $null
  Step2Snap = $null
  PostStatus = $null
  Step1Bypassed = $false
  Step1Collapsed = $false
  LogExpanded = $false
  IsBusy = $false
  AsyncPs = $null
  AsyncRs = $null
  AsyncHandle = $null
  AsyncQueue = $null
 }

 $form = New-Object System.Windows.Forms.Form
 $form.Text = (U "SID \uBCC0\uACBD \uBCF4\uC870 \uB3C4\uAD6C") + " v" + $verStr
 $form.Size = New-Object System.Drawing.Size(1040, 720)
 $form.MinimumSize = New-Object System.Drawing.Size(960, 640)
 $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
 $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
 $form.BackColor = $theme.CanvasBg
 $form.Font = $fonts.Base
 $form.KeyPreview = $true
 $form.Icon = $appIcon

 $toolTip = New-Object System.Windows.Forms.ToolTip
 $toolTip.AutoPopDelay = 12000
 $toolTip.InitialDelay = 250
 $toolTip.ReshowDelay = 150
 $toolTip.ShowAlways = $true

 $copyResetTimer = New-Object System.Windows.Forms.Timer
 $copyResetTimer.Interval = 1500
 $asyncPollTimer = New-Object System.Windows.Forms.Timer
 $asyncPollTimer.Interval = 180

 # Pre-declare shared UI context so all helpers/handlers reference the exact same object
 $ui = @{
  Form             = $form
  Theme            = $theme
  Fonts            = $fonts
  SrcInfo          = $srcInfo
  State            = $state
  ToolTip          = $toolTip
  ButtonStyles     = @{}
  DisabledReasons  = @{}
  LastDisabledBtn  = $null
  LastDisabledHost = $null
  CopyResetTimer   = $copyResetTimer
  AsyncPollTimer   = $asyncPollTimer
  Disposables      = @($toolTip, $copyResetTimer, $asyncPollTimer, $symbolBmp, $appIcon) + @($fonts.Values)
 }
 $form.Tag = $ui

 # ==============================================================================
 # ZONE 1: TOP 2-ROW BRAND HEADER (52px Brand + 2px Orange Line + 28px Meta Bar)
 # ==============================================================================
 $topShell = New-Object System.Windows.Forms.Panel
 $topShell.Dock = [System.Windows.Forms.DockStyle]::Top
 $topShell.Height = 82
 $topShell.BackColor = $theme.HeaderBg

 # Row 1: Brand Bar (52px)
 $brandBar = New-Object System.Windows.Forms.Panel
 $brandBar.Dock = [System.Windows.Forms.DockStyle]::Top
 $brandBar.Height = 52
 $brandBar.BackColor = $theme.HeaderBg
 $brandBar.Padding = New-Object System.Windows.Forms.Padding(16, 6, 16, 6)

 $brandRight = New-RightFlowStrip 4 0 0
 $btnTopDiag = New-AsanButton (U "\uC9C4\uB2E8 \uB9AC\uD3EC\uD2B8") 96 30 "HeaderUtil" $ui $true
 $btnTopDiag.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
 $toolTip.SetToolTip($btnTopDiag, (U "BIOS \uAD50\uCC28 \uAC80\uC99D, NVRAM, \uB514\uC2A4\uD06C \uBC0F \uC791\uC5C5 \uB85C\uADF8\uB97C \uD655\uC778\uD558\uACE0 \uC800\uC7A5\uD569\uB2C8\uB2E4."))

 $btnTopRefresh = New-AsanButton (U "\uC0C8\uB85C\uACE0\uCE68") 82 30 "HeaderUtil" $ui $true
 $btnTopRefresh.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
 $toolTip.SetToolTip($btnTopRefresh, (U "\uB514\uC2A4\uD06C, USB, \uD504\uB9B0\uD130 \uC0C1\uD0DC\uB97C \uB2E4\uC2DC \uBD88\uB7EC\uC635\uB2C8\uB2E4. \uB2E8\uCD95\uD0A4 F5"))

 $lblExecBadge = New-Object System.Windows.Forms.Label
 $lblExecBadge.AutoSize = $true
 $lblExecBadge.Font = $fonts.SmallB
 $lblExecBadge.ForeColor = [System.Drawing.Color]::White
 $lblExecBadge.BackColor = if ($srcInfo.Mode -eq "Network") { $theme.AsanLight } elseif ($srcInfo.Mode -eq "USB") { $theme.AsanGreen } else { $theme.BadgeOnlineBg }
 $lblExecBadge.Padding = New-Object System.Windows.Forms.Padding(9, 5, 9, 5)
 $lblExecBadge.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
 $lblExecBadge.Text = $srcInfo.Label
 $toolTip.SetToolTip($lblExecBadge, $srcInfo.Detail)

 # RightToLeft order: first added is rightmost
 $brandRight.Controls.Add($btnTopDiag)
 $brandRight.Controls.Add($btnTopRefresh)
 $brandRight.Controls.Add($lblExecBadge)

 $brandLeft = New-Object System.Windows.Forms.Panel
 $brandLeft.Dock = [System.Windows.Forms.DockStyle]::Fill
 $brandLeft.BackColor = [System.Drawing.Color]::Transparent

 $picLogo = New-Object System.Windows.Forms.PictureBox
 $picLogo.Image = $symbolBmp
 $picLogo.Size = New-Object System.Drawing.Size(40, 40)
 $picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
 $picLogo.Location = New-Object System.Drawing.Point(0, 0)

 $lblAppTitle = New-Object System.Windows.Forms.Label
 $lblAppTitle.Text = U "SID \uBCC0\uACBD \uBCF4\uC870 \uB3C4\uAD6C"
 $lblAppTitle.Font = $fonts.Title
 $lblAppTitle.ForeColor = [System.Drawing.Color]::White
 $lblAppTitle.AutoSize = $true
 $lblAppTitle.Location = New-Object System.Drawing.Point(50, 0)

 $lblAppSub = New-Object System.Windows.Forms.Label
 $lblAppSub.Text = (U "WinPE \uBD80\uD305 \uC900\uBE44\uC640 \uD504\uB9B0\uD130 \uBCF5\uAD6C\uB97C \uC548\uB0B4\uD569\uB2C8\uB2E4 \u00B7 v") + $verStr
 $lblAppSub.Font = $fonts.Subtitle
 $lblAppSub.ForeColor = $theme.HeaderSubFg
 $lblAppSub.AutoSize = $true
 $lblAppSub.Location = New-Object System.Drawing.Point(51, 24)
 $toolTip.SetToolTip($lblAppSub, ("Build " + $buildMeta + " / " + $script:BuildCommit))

 $brandLeft.Controls.Add($picLogo)
 $brandLeft.Controls.Add($lblAppTitle)
 $brandLeft.Controls.Add($lblAppSub)
 $brandBar.Controls.Add($brandLeft)
 $brandBar.Controls.Add($brandRight)

 # 2px Orange Accent Line
 $orangeLine = New-Object System.Windows.Forms.Panel
 $orangeLine.Dock = [System.Windows.Forms.DockStyle]::Top
 $orangeLine.Height = 2
 $orangeLine.BackColor = $theme.AsanOrangeLine

 # Row 2: Meta Summary Bar (28px)
 $metaBar = New-Object System.Windows.Forms.Panel
 $metaBar.Dock = [System.Windows.Forms.DockStyle]::Top
 $metaBar.Height = 28
 $metaBar.BackColor = $theme.MetaBarBg
 $metaBar.Padding = New-Object System.Windows.Forms.Padding(16, 3, 16, 3)

 $metaRight = New-RightFlowStrip 0 0 0
 $btnCopySid = New-AsanButton (U "SID \uBCF5\uC0AC") 68 22 "Secondary" $ui $true
 $btnCopySid.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
 $toolTip.SetToolTip($btnCopySid, (U "\uD604\uC7AC PC\uC758 Machine SID\uB97C \uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uBCF5\uC0AC\uD569\uB2C8\uB2E4."))

 $lblMetaSid = New-Object System.Windows.Forms.Label
 $lblMetaSid.AutoSize = $true
 $lblMetaSid.Font = $fonts.Small
 $lblMetaSid.ForeColor = $theme.InkMuted
 $lblMetaSid.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
 $lblMetaSid.Text = U "SID \uD655\uC778 \uC911"

 $metaRight.Controls.Add($btnCopySid)
 $metaRight.Controls.Add($lblMetaSid)

 $lblMetaLeft = New-Object System.Windows.Forms.Label
 $lblMetaLeft.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblMetaLeft.Font = $fonts.Small
 $lblMetaLeft.ForeColor = $theme.InkSecondary
 $lblMetaLeft.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
 $lblMetaLeft.AutoEllipsis = $true
 $osTxt = if ($sysInfo.OsSummary) { $sysInfo.OsSummary } else { "Windows" }
 $initDot = [string][char]0x00B7
 $dispModel = if ($sysInfo.DisplayVendor) { $sysInfo.DisplayVendor + " " + $sysInfo.ModelName } else { [string]$sysInfo.ModelName }
 $lblMetaLeft.Text = ($env:COMPUTERNAME + "  " + $initDot + "  " + $dispModel + "  " + $initDot + "  " + $osTxt)

 $metaBar.Controls.Add($lblMetaLeft)
 $metaBar.Controls.Add($metaRight)

 # Dock Top stacking: add bottom-most first so Top order is brandBar -> orangeLine -> metaBar
 $topShell.Controls.Add($metaBar)
 $topShell.Controls.Add($orangeLine)
 $topShell.Controls.Add($brandBar)

 # ==============================================================================
 # ZONE 2: CONDITIONAL CRITICAL WARNING BANNER (36px, default hidden)
 # ==============================================================================
 $critBanner = New-Object System.Windows.Forms.Panel
 $critBanner.Dock = [System.Windows.Forms.DockStyle]::Top
 $critBanner.Height = 36
 $critBanner.BackColor = $theme.DangerRed
 $critBanner.Padding = New-Object System.Windows.Forms.Padding(16, 4, 16, 4)
 $critBanner.Visible = $false

 $critRight = New-RightFlowStrip 1 0 0
 $btnCritDetail = New-AsanButton (U "\uC9C4\uB2E8 \uC0C1\uC138 \uBCF4\uAE30") 104 26 "Secondary" $ui $true
 $btnCritDetail.Margin = New-Object System.Windows.Forms.Padding(0)
 $critRight.Controls.Add($btnCritDetail)

 $lblCritMsg = New-Object System.Windows.Forms.Label
 $lblCritMsg.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblCritMsg.Font = $fonts.Bold
 $lblCritMsg.ForeColor = [System.Drawing.Color]::White
 $lblCritMsg.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
 $lblCritMsg.AutoEllipsis = $true

 $critBanner.Controls.Add($lblCritMsg)
 $critBanner.Controls.Add($critRight)

 # ==============================================================================
 # ZONE 4: BOTTOM SLIM STATUS BAR + COLLAPSIBLE LOG CONSOLE (38px <-> 114px)
 # ==============================================================================
 $bottomDock = New-Object System.Windows.Forms.Panel
 $bottomDock.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $bottomDock.Height = 38
 $bottomDock.BackColor = $theme.CardBg

 $bottomSep = New-Object System.Windows.Forms.Panel
 $bottomSep.Dock = [System.Windows.Forms.DockStyle]::Top
 $bottomSep.Height = 1
 $bottomSep.BackColor = $theme.Border

 $statusStrip = New-Object System.Windows.Forms.Panel
 $statusStrip.Dock = [System.Windows.Forms.DockStyle]::Top
 $statusStrip.Height = 37
 $statusStrip.BackColor = $theme.CardBg
 $statusStrip.Padding = New-Object System.Windows.Forms.Padding(16, 5, 16, 5)

 $statusRight = New-RightFlowStrip 0 0 0
 $btnToggleLog = New-AsanButton (U "\uC0C1\uC138 \uB85C\uADF8 \uBCF4\uAE30") 108 26 "Secondary" $ui $true
 $btnToggleLog.Margin = New-Object System.Windows.Forms.Padding(0)
 $statusRight.Controls.Add($btnToggleLog)

 $lblStatusText = New-Object System.Windows.Forms.Label
 $lblStatusText.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblStatusText.Font = $fonts.SmallB
 $lblStatusText.ForeColor = $theme.InkSecondary
 $lblStatusText.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
 $lblStatusText.AutoEllipsis = $true
 $lblStatusText.Text = U "\uC900\uBE44 \uC644\uB8CC"

 $statusStrip.Controls.Add($lblStatusText)
 $statusStrip.Controls.Add($statusRight)

 $logDrawerWrap = New-Object System.Windows.Forms.Panel
 $logDrawerWrap.Dock = [System.Windows.Forms.DockStyle]::Fill
 $logDrawerWrap.Padding = New-Object System.Windows.Forms.Padding(16, 0, 16, 6)
 $logDrawerWrap.BackColor = $theme.CardBg
 $logDrawerWrap.Visible = $false

 $logBoxObj = New-PaddedTextBoxPanel $theme.LogBg $theme.LogFg $fonts.Mono 10 5 $true "" ([System.Windows.Forms.ScrollBars]::Vertical) $true
 $logDrawerWrap.Controls.Add($logBoxObj.Panel)

 $bottomDock.Controls.Add($logDrawerWrap)
 $bottomDock.Controls.Add($statusStrip)
 $bottomDock.Controls.Add($bottomSep)

 # ==============================================================================
 # ZONE 3: MAIN WORKSPACE (CanvasBg, Padding 12, OwnerDrawFixed Numbered Tabs)
 # ==============================================================================
 $mainCanvas = New-Object System.Windows.Forms.Panel
 $mainCanvas.Dock = [System.Windows.Forms.DockStyle]::Fill
 $mainCanvas.BackColor = $theme.CanvasBg
 $mainCanvas.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)

 $tabControl = New-Object System.Windows.Forms.TabControl
 $tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
 Enable-AsanOwnerDrawTabs $tabControl $theme $fonts

 $tabPre = New-Object System.Windows.Forms.TabPage
 $tabPre.Text = U "1. SID \uBCC0\uACBD \uC804 \uC900\uBE44"
 $tabPre.BackColor = $theme.CanvasBg
 $tabPre.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
 $tabPre.Font = $fonts.Base

 $tabPost = New-Object System.Windows.Forms.TabPage
 $tabPost.Text = U "2. SID \uBCC0\uACBD \uD6C4 \uD504\uB9B0\uD130 \uBCF5\uAD6C"
 $tabPost.BackColor = $theme.CanvasBg
 $tabPost.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
 $tabPost.Font = $fonts.Base

 [void]$tabControl.TabPages.Add($tabPre)
 [void]$tabControl.TabPages.Add($tabPost)
 $mainCanvas.Controls.Add($tabControl)

 # ------------------------------------------------------------------------------
 # TAB 1: PRE-SID (Guidance Banner -> 1?? Bootloader Card -> 2?? USB Card)
 # ------------------------------------------------------------------------------
 $preRoot = New-Object System.Windows.Forms.TableLayoutPanel
 $preRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
 $preRoot.ColumnCount = 1
 $preRoot.RowCount = 3
 $preRoot.BackColor = $theme.CanvasBg
 [void]$preRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
 [void]$preRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
 [void]$preRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 38)))
 [void]$preRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 62)))
 $tabPre.Controls.Add($preRoot)

 # Tab 1 Top Guidance Banner (height 50px + 6px bottom margin = 56px)
 $preBanner = New-Object System.Windows.Forms.Panel
 $preBanner.Dock = [System.Windows.Forms.DockStyle]::Fill
 $preBanner.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
 $preBanner.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

 $preAccent = New-Object System.Windows.Forms.Panel
 $preAccent.Dock = [System.Windows.Forms.DockStyle]::Left
 $preAccent.Width = 4

 $preBannerBody = New-Object System.Windows.Forms.Panel
 $preBannerBody.Dock = [System.Windows.Forms.DockStyle]::Fill
 $preBannerBody.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 5)

 $lblPreBanTitle = New-Object System.Windows.Forms.Label
 $lblPreBanTitle.Dock = [System.Windows.Forms.DockStyle]::Top
 $lblPreBanTitle.Height = 20
 $lblPreBanTitle.Font = $fonts.Bold
 $lblPreBanTitle.AutoEllipsis = $true

 $lblPreBanMsg = New-Object System.Windows.Forms.Label
 $lblPreBanMsg.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPreBanMsg.Font = $fonts.Small
 $lblPreBanMsg.AutoEllipsis = $true

 $preBannerBody.Controls.Add($lblPreBanMsg)
 $preBannerBody.Controls.Add($lblPreBanTitle)
 $preBanner.Controls.Add($preBannerBody)
 $preBanner.Controls.Add($preAccent)
 $preRoot.Controls.Add($preBanner, 0, 0)

 # Card 1: Step 1 Internal Disk Bootloader Check
 $cardStep1 = New-Object System.Windows.Forms.Panel
 $cardStep1.Dock = [System.Windows.Forms.DockStyle]::Fill
 $cardStep1.BackColor = $theme.CardBg
 $cardStep1.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
 $cardStep1.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

 $step1Hdr = New-Object System.Windows.Forms.Panel
 $step1Hdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $step1Hdr.Height = 36
 $step1Hdr.BackColor = $theme.CardBg
 $step1Hdr.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)

 $step1Left = New-Object System.Windows.Forms.FlowLayoutPanel
 $step1Left.Dock = [System.Windows.Forms.DockStyle]::Left
 $step1Left.AutoSize = $true
 $step1Left.WrapContents = $false
 $step1Left.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)

 $lblBadge1 = New-Object System.Windows.Forms.Label
 $lblBadge1.AutoSize = $true
 $lblBadge1.BackColor = $theme.AsanGreen
 $lblBadge1.ForeColor = [System.Drawing.Color]::White
 $lblBadge1.Font = $fonts.SmallB
 $lblBadge1.Padding = New-Object System.Windows.Forms.Padding(7, 2, 7, 2)
 $lblBadge1.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $lblBadge1.Text = U "1\uB2E8\uACC4"

 $lblStep1Title = New-Object System.Windows.Forms.Label
 $lblStep1Title.AutoSize = $true
 $lblStep1Title.Font = $fonts.Bold
 $lblStep1Title.ForeColor = $theme.InkPrimary
 $lblStep1Title.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 0)
 $lblStep1Title.Text = U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354 \uC810\uAC80"

 $lblStep1Chip = New-Object System.Windows.Forms.Label
 $lblStep1Chip.AutoSize = $true
 $lblStep1Chip.Font = $fonts.SmallB
 $lblStep1Chip.Padding = New-Object System.Windows.Forms.Padding(7, 2, 7, 2)
 $lblStep1Chip.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
 $lblStep1Chip.Text = U "\uD655\uC778 \uC911"

 $step1Left.Controls.Add($lblBadge1)
 $step1Left.Controls.Add($lblStep1Title)
 $step1Left.Controls.Add($lblStep1Chip)

 $step1Right = New-RightFlowStrip 1 0 0
 $btnStep1Fold = New-AsanButton (U "\uC811\uAE30") 56 26 "Secondary" $ui $true
 $btnStep1Fold.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)

 $btnIgnoreStep1 = New-AsanButton (U "\uC704\uD5D8 \uD655\uC778 \uAC74\uB108\uB6F0\uAE30") 126 26 "SoftOrange" $ui $true
 $btnIgnoreStep1.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
 $btnIgnoreStep1.Visible = $false

 $btnToggleDisk = New-AsanButton (U "\uC120\uD0DD \uB514\uC2A4\uD06C \uC804\uD658") 116 26 "Secondary" $ui $true
 $btnToggleDisk.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)

 $btnOneStop = New-AsanButton (U "\uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uC815\uB9AC") 138 26 "Orange" $ui $true
 $btnOneStop.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)

 # RightToLeft order
 $step1Right.Controls.Add($btnStep1Fold)
 $step1Right.Controls.Add($btnIgnoreStep1)
 $step1Right.Controls.Add($btnToggleDisk)
 $step1Right.Controls.Add($btnOneStop)

 $step1Hdr.Controls.Add($step1Left)
 $step1Hdr.Controls.Add($step1Right)

 $dgvDisks = New-AsanGrid $theme $fonts
 Add-AsanGridColumn $dgvDisks "Disk"      (U "\uB514\uC2A4\uD06C") 68 $false 64
 Add-AsanGridColumn $dgvDisks "Model"     (U "\uBAA8\uB378\uBA85") 220 $false 140
 Add-AsanGridColumn $dgvDisks "Size"      (U "\uC6A9\uB7C9") 78 $false 68
 Add-AsanGridColumn $dgvDisks "Style"     (U "\uBC29\uC2DD") 60 $false 54
 Add-AsanGridColumn $dgvDisks "BootPart"  (U "\uBD80\uD2B8 \uC601\uC5ED") 100 $false 86
 Add-AsanGridColumn $dgvDisks "Status"    (U "\uC810\uAC80 \uC0C1\uD0DC") 180 $true 150

 $cardStep1.Controls.Add($dgvDisks)
 $cardStep1.Controls.Add($step1Hdr)
 $preRoot.Controls.Add($cardStep1, 0, 1)

 # Card 2: Step 2 BIOS Summary + Unified USB Selection & Reboot
 $cardStep2 = New-Object System.Windows.Forms.Panel
 $cardStep2.Dock = [System.Windows.Forms.DockStyle]::Fill
 $cardStep2.BackColor = $theme.CardBg
 $cardStep2.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

 $step2Hdr = New-Object System.Windows.Forms.Panel
 $step2Hdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $step2Hdr.Height = 36
 $step2Hdr.BackColor = $theme.CardBg
 $step2Hdr.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)

 $step2Left = New-Object System.Windows.Forms.FlowLayoutPanel
 $step2Left.Dock = [System.Windows.Forms.DockStyle]::Left
 $step2Left.AutoSize = $true
 $step2Left.WrapContents = $false
 $step2Left.Padding = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)

 $lblBadge2 = New-Object System.Windows.Forms.Label
 $lblBadge2.AutoSize = $true
 $lblBadge2.BackColor = $theme.AsanGreen
 $lblBadge2.ForeColor = [System.Drawing.Color]::White
 $lblBadge2.Font = $fonts.SmallB
 $lblBadge2.Padding = New-Object System.Windows.Forms.Padding(7, 2, 7, 2)
 $lblBadge2.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $lblBadge2.Text = U "2\uB2E8\uACC4"

 $lblStep2Title = New-Object System.Windows.Forms.Label
 $lblStep2Title.AutoSize = $true
 $lblStep2Title.Font = $fonts.Bold
 $lblStep2Title.ForeColor = $theme.InkPrimary
 $lblStep2Title.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 0)
 $lblStep2Title.Text = U "WinPE USB \uC120\uD0DD \uBC0F \uC7AC\uBD80\uD305"

 $lblStep2LockChip = New-Object System.Windows.Forms.Label
 $lblStep2LockChip.AutoSize = $true
 $lblStep2LockChip.BackColor = $theme.DangerRedTint
 $lblStep2LockChip.ForeColor = $theme.DangerRedDeep
 $lblStep2LockChip.Font = $fonts.SmallB
 $lblStep2LockChip.Padding = New-Object System.Windows.Forms.Padding(7, 2, 7, 2)
 $lblStep2LockChip.Text = U "1\uB2E8\uACC4 \uC815\uB9AC \uD6C4 \uD65C\uC131\uD654"
 $lblStep2LockChip.Visible = $false

 $step2Left.Controls.Add($lblBadge2)
 $step2Left.Controls.Add($lblStep2Title)
 $step2Left.Controls.Add($lblStep2LockChip)

 $step2Right = New-RightFlowStrip 1 0 0
 $btnInlineDiag = New-AsanButton (U "BIOS \uC9C4\uB2E8 \uC0C1\uC138") 108 26 "Secondary" $ui $true
 $btnInlineDiag.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
 $btnRescanUsb = New-AsanButton (U "USB \uB2E4\uC2DC \uCC3E\uAE30") 104 26 "Secondary" $ui $true
 $btnRescanUsb.Margin = New-Object System.Windows.Forms.Padding(0)
 $step2Right.Controls.Add($btnInlineDiag)
 $step2Right.Controls.Add($btnRescanUsb)

 $step2Hdr.Controls.Add($step2Left)
 $step2Hdr.Controls.Add($step2Right)

 # Compact BIOS + Physical USB Status Strip (30px)
 $biosStrip = New-Object System.Windows.Forms.Panel
 $biosStrip.Dock = [System.Windows.Forms.DockStyle]::Top
 $biosStrip.Height = 30
 $biosStrip.BackColor = $theme.RowAltBg
 $biosStrip.Padding = New-Object System.Windows.Forms.Padding(10, 3, 10, 3)

 $biosPills = New-Object System.Windows.Forms.FlowLayoutPanel
 $biosPills.Dock = [System.Windows.Forms.DockStyle]::Left
 $biosPills.AutoSize = $true
 $biosPills.WrapContents = $false

 $lblPillSec = New-Object System.Windows.Forms.Label
 $lblPillSec.AutoSize = $true; $lblPillSec.Font = $fonts.SmallB
 $lblPillSec.Padding = New-Object System.Windows.Forms.Padding(7, 3, 7, 3)
 $lblPillSec.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 0)

 $lblPillUsb = New-Object System.Windows.Forms.Label
 $lblPillUsb.AutoSize = $true; $lblPillUsb.Font = $fonts.SmallB
 $lblPillUsb.Padding = New-Object System.Windows.Forms.Padding(7, 3, 7, 3)
 $lblPillUsb.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 0)

 $lblPillFast = New-Object System.Windows.Forms.Label
 $lblPillFast.AutoSize = $true; $lblPillFast.Font = $fonts.SmallB
 $lblPillFast.Padding = New-Object System.Windows.Forms.Padding(7, 3, 7, 3)
 $lblPillFast.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 0)

 $biosPills.Controls.Add($lblPillSec)
 $biosPills.Controls.Add($lblPillUsb)
 $biosPills.Controls.Add($lblPillFast)

 $lblPhysSummary = New-Object System.Windows.Forms.Label
 $lblPhysSummary.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPhysSummary.Font = $fonts.Small
 $lblPhysSummary.ForeColor = $theme.InkSecondary
 $lblPhysSummary.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
 $lblPhysSummary.AutoEllipsis = $true
 $lblPhysSummary.Text = U "\uC5F0\uACB0\uB41C USB \uD655\uC778 \uC911"

 $biosStrip.Controls.Add($lblPhysSummary)
 $biosStrip.Controls.Add($biosPills)

 # Unified USB Selection DataGridView
 $dgvUsb = New-AsanGrid $theme $fonts
 Add-AsanGridColumn $dgvUsb "Kind"   (U "\uAD6C\uBD84") 80 $false 74
 Add-AsanGridColumn $dgvUsb "Match"  (U "\uC77C\uCE58 \uC218\uC900") 126 $false 116
 Add-AsanGridColumn $dgvUsb "Name"   (U "USB \uB610\uB294 \uBD80\uD305 \uD56D\uBAA9 \uC774\uB984") 230 $false 155
 Add-AsanGridColumn $dgvUsb "Device" (U "\uC5F0\uACB0 \uC815\uBCF4") 135 $false 105
 Add-AsanGridColumn $dgvUsb "Guide"  (U "\uC0C1\uD0DC \uC548\uB0B4") 180 $true 150

 # Step 2 Bottom Action Bar (46px)
 $step2Bar = New-Object System.Windows.Forms.Panel
 $step2Bar.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $step2Bar.Height = 46
 $step2Bar.BackColor = $theme.CardBg
 $step2Bar.Padding = New-Object System.Windows.Forms.Padding(10, 7, 10, 7)

 $step2Actions = New-Object System.Windows.Forms.FlowLayoutPanel
 $step2Actions.Dock = [System.Windows.Forms.DockStyle]::Left
 $step2Actions.AutoSize = $true
 $step2Actions.WrapContents = $false
 $step2Actions.Margin = New-Object System.Windows.Forms.Padding(0)

 $btnUsbReboot = New-AsanButton (U "\uC120\uD0DD\uD55C USB\uB85C \uC7AC\uBD80\uD305") 166 32 "Primary" $ui $false
 $btnUsbReboot.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

 $btnAdvBoot = New-AsanButton (U "\uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9") 146 32 "Secondary" $ui $false
 $btnAdvBoot.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $toolTip.SetToolTip($btnAdvBoot, (U "Windows \uC7A5\uCE58 \uC0AC\uC6A9 \uBA54\uB274\uB85C \uC7AC\uBD80\uD305\uD574 \uC5F0\uACB0\uB41C USB\uB97C \uC9C1\uC811 \uACE8\uB77C \uBD80\uD305\uD569\uB2C8\uB2E4."))

 $btnBiosBoot = New-AsanButton (U "BIOS \uC124\uC815 \uC5F4\uAE30") 122 32 "Secondary" $ui $false
 $btnBiosBoot.Margin = New-Object System.Windows.Forms.Padding(0)
 $toolTip.SetToolTip($btnBiosBoot, $sysInfo.BiosHint)

 $step2Actions.Controls.Add($btnUsbReboot)
 $step2Actions.Controls.Add($btnAdvBoot)
 $step2Actions.Controls.Add($btnBiosBoot)

 $lblBiosCue = New-Object System.Windows.Forms.Label
 $lblBiosCue.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblBiosCue.Font = $fonts.Small
 $lblBiosCue.ForeColor = $theme.InkMuted
 $lblBiosCue.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
 $lblBiosCue.AutoEllipsis = $true
 $lblBiosCue.Text = if ($sysInfo.BiosGuideShort) { $sysInfo.BiosGuideShort } else { $sysInfo.BiosHint }
 $toolTip.SetToolTip($lblBiosCue, $sysInfo.BiosHint)

 $step2Bar.Controls.Add($lblBiosCue)
 $step2Bar.Controls.Add($step2Actions)

 # Dock order inside Card 2: Fill first, then Bottom, then Top (bottom-up: biosStrip then step2Hdr)
 $cardStep2.Controls.Add($dgvUsb)
 $cardStep2.Controls.Add($step2Bar)
 $cardStep2.Controls.Add($biosStrip)
 $cardStep2.Controls.Add($step2Hdr)
 $preRoot.Controls.Add($cardStep2, 0, 2)

 # ------------------------------------------------------------------------------
 # TAB 2: POST-SID (Guidance Banner -> 4 Metric Tiles -> Printers Grid -> Action)
 # ------------------------------------------------------------------------------
 $postRoot = New-Object System.Windows.Forms.TableLayoutPanel
 $postRoot.Dock = [System.Windows.Forms.DockStyle]::Fill
 $postRoot.ColumnCount = 1
 $postRoot.RowCount = 4
 $postRoot.BackColor = $theme.CanvasBg
 [void]$postRoot.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 76)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
 [void]$postRoot.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 56)))
 $tabPost.Controls.Add($postRoot)

 # Tab 2 Guidance Banner
 $postBanner = New-Object System.Windows.Forms.Panel
 $postBanner.Dock = [System.Windows.Forms.DockStyle]::Fill
 $postBanner.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
 $postBanner.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

 $postAccent = New-Object System.Windows.Forms.Panel
 $postAccent.Dock = [System.Windows.Forms.DockStyle]::Left
 $postAccent.Width = 4

 $postBannerBody = New-Object System.Windows.Forms.Panel
 $postBannerBody.Dock = [System.Windows.Forms.DockStyle]::Fill
 $postBannerBody.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 5)

 $lblPostBanTitle = New-Object System.Windows.Forms.Label
 $lblPostBanTitle.Dock = [System.Windows.Forms.DockStyle]::Top
 $lblPostBanTitle.Height = 20
 $lblPostBanTitle.Font = $fonts.Bold
 $lblPostBanTitle.AutoEllipsis = $true

 $lblPostBanMsg = New-Object System.Windows.Forms.Label
 $lblPostBanMsg.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPostBanMsg.Font = $fonts.Small
 $lblPostBanMsg.AutoEllipsis = $true

 $postBannerBody.Controls.Add($lblPostBanMsg)
 $postBannerBody.Controls.Add($lblPostBanTitle)
 $postBanner.Controls.Add($postBannerBody)
 $postBanner.Controls.Add($postAccent)
 $postRoot.Controls.Add($postBanner, 0, 0)

 # 4 Clean Horizontal Metric Tiles
 $tileGrid = New-Object System.Windows.Forms.TableLayoutPanel
 $tileGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
 $tileGrid.ColumnCount = 4
 $tileGrid.RowCount = 1
 $tileGrid.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
 for ($c = 0; $c -lt 4; $c++) {
  [void]$tileGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
 }
 [void]$tileGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

 $makeTile = {
  param([string]$cap, [int]$colIdx)
  $card = New-Object System.Windows.Forms.Panel
  $card.Dock = [System.Windows.Forms.DockStyle]::Fill
  $card.BackColor = $theme.CardBg
  $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $rightM = if ($colIdx -lt 3) { 6 } else { 0 }
  $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, $rightM, 0)
  $card.Padding = New-Object System.Windows.Forms.Padding(12, 7, 12, 6)

  $lCap = New-Object System.Windows.Forms.Label
  $lCap.Dock = [System.Windows.Forms.DockStyle]::Top
  $lCap.Height = 16
  $lCap.Font = $fonts.Small
  $lCap.ForeColor = $theme.InkMuted
  $lCap.Text = $cap

  $lVal = New-Object System.Windows.Forms.Label
  $lVal.Dock = [System.Windows.Forms.DockStyle]::Top
  $lVal.Height = 22
  $lVal.Font = $fonts.Metric
  $lVal.ForeColor = $theme.InkPrimary
  $lVal.AutoEllipsis = $true
  $lVal.Text = "-"

  $lSub = New-Object System.Windows.Forms.Label
  $lSub.Dock = [System.Windows.Forms.DockStyle]::Fill
  $lSub.Font = $fonts.Small
  $lSub.ForeColor = $theme.InkSecondary
  $lSub.AutoEllipsis = $true
  $lSub.Text = ""

  $card.Controls.Add($lSub)
  $card.Controls.Add($lVal)
  $card.Controls.Add($lCap)
  $tileGrid.Controls.Add($card, $colIdx, 0)
  return [PSCustomObject]@{ Card = $card; Caption = $lCap; Value = $lVal; Sub = $lSub }
 }

 $tileRole  = & $makeTile (U "PC \uC5ED\uD560") 0
 $tileSpool = & $makeTile (U "\uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4") 1
 $tileQueue = & $makeTile (U "\uC778\uC1C4 \uB300\uAE30\uC5F4") 2
 $tileShare = & $makeTile (U "\uACF5\uC720 \uC5F0\uACB0 \uC0C1\uD0DC") 3
 $postRoot.Controls.Add($tileGrid, 0, 1)

 # Printers Card
 $cardPrinters = New-Object System.Windows.Forms.Panel
 $cardPrinters.Dock = [System.Windows.Forms.DockStyle]::Fill
 $cardPrinters.BackColor = $theme.CardBg
 $cardPrinters.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
 $cardPrinters.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)

 $prHdr = New-Object System.Windows.Forms.Panel
 $prHdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $prHdr.Height = 32
 $prHdr.BackColor = $theme.CardBg
 $prHdr.Padding = New-Object System.Windows.Forms.Padding(12, 6, 12, 4)

 $lblPrTitle = New-Object System.Windows.Forms.Label
 $lblPrTitle.Dock = [System.Windows.Forms.DockStyle]::Left
 $lblPrTitle.AutoSize = $true
 $lblPrTitle.Font = $fonts.Bold
 $lblPrTitle.ForeColor = $theme.InkPrimary
 $lblPrTitle.Text = U "\uC124\uCE58\uB41C \uD504\uB9B0\uD130 \uBAA9\uB85D"

 $lblPrSafeNote = New-Object System.Windows.Forms.Label
 $lblPrSafeNote.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPrSafeNote.Font = $fonts.Small
 $lblPrSafeNote.ForeColor = $theme.InkMuted
 $lblPrSafeNote.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
 $lblPrSafeNote.AutoEllipsis = $true
 $lblPrSafeNote.Text = U "\uCD08\uAE30\uD654\uB97C \uC2E4\uD589\uD574\uB3C4 \uAE30\uC874 \uD504\uB9B0\uD130, \uB4DC\uB77C\uC774\uBC84, \uACF5\uC720 \uC124\uC815\uC740 \uC0AD\uC81C\uB418\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4."

 $prHdr.Controls.Add($lblPrSafeNote)
 $prHdr.Controls.Add($lblPrTitle)

 $dgvPrinters = New-AsanGrid $theme $fonts
 Add-AsanGridColumn $dgvPrinters "Type"   (U "\uAD6C\uBD84") 94 $false 84
 Add-AsanGridColumn $dgvPrinters "Name"   (U "\uD504\uB9B0\uD130 \uC774\uB984") 230 $false 150
 Add-AsanGridColumn $dgvPrinters "Share"  (U "\uACF5\uC720 \uACBD\uB85C") 190 $false 120
 Add-AsanGridColumn $dgvPrinters "Port"   (U "\uD3EC\uD2B8") 130 $false 90
 Add-AsanGridColumn $dgvPrinters "Driver" (U "\uB4DC\uB77C\uC774\uBC84") 160 $true 130

 $cardPrinters.Controls.Add($dgvPrinters)
 $cardPrinters.Controls.Add($prHdr)
 $postRoot.Controls.Add($cardPrinters, 0, 2)

 # Post-SID Bottom Action Card (56px)
 $cardPostAct = New-Object System.Windows.Forms.Panel
 $cardPostAct.Dock = [System.Windows.Forms.DockStyle]::Fill
 $cardPostAct.BackColor = $theme.CardBg
 $cardPostAct.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
 $cardPostAct.Margin = New-Object System.Windows.Forms.Padding(0)
 $cardPostAct.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)

 $postActLeft = New-Object System.Windows.Forms.FlowLayoutPanel
 $postActLeft.Dock = [System.Windows.Forms.DockStyle]::Left
 $postActLeft.AutoSize = $true
 $postActLeft.WrapContents = $false
 $postActLeft.Margin = New-Object System.Windows.Forms.Padding(0)

 $btnSpoolerReset = New-AsanButton (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654") 176 34 "Primary" $ui $false
 $btnSpoolerReset.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $toolTip.SetToolTip($btnSpoolerReset, (U "\uC778\uC1C4 \uB300\uAE30\uC5F4\uC744 \uBE44\uC6B0\uACE0 \uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4\uB97C \uC7AC\uC2DC\uC791\uD569\uB2C8\uB2E4."))

 $btnPostRefresh = New-AsanButton (U "\uC0C1\uD0DC \uB2E4\uC2DC \uD655\uC778") 116 34 "Secondary" $ui $false
 $btnPostRefresh.Margin = New-Object System.Windows.Forms.Padding(0)

 $postActLeft.Controls.Add($btnSpoolerReset)
 $postActLeft.Controls.Add($btnPostRefresh)

 $lblPostOrderTip = New-Object System.Windows.Forms.Label
 $lblPostOrderTip.Dock = [System.Windows.Forms.DockStyle]::Fill
 $lblPostOrderTip.Font = $fonts.Small
 $lblPostOrderTip.ForeColor = $theme.InkSecondary
 $lblPostOrderTip.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
 $lblPostOrderTip.AutoEllipsis = $true
 $lblPostOrderTip.Text = U "\uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uD074\uB77C\uC774\uC5B8\uD2B8 PC \uAC01\uAC01\uC5D0\uC11C \uD55C \uBC88\uC529 \uC2E4\uD589\uD574 \uC8FC\uC138\uC694."

 $cardPostAct.Controls.Add($lblPostOrderTip)
 $cardPostAct.Controls.Add($postActLeft)
 $postRoot.Controls.Add($cardPostAct, 0, 3)

 # Assemble 4-Zone Shell on Form (Fill first, then Bottom, then Top in reverse order!)
 $form.Controls.Add($mainCanvas)
 $form.Controls.Add($bottomDock)
 $form.Controls.Add($critBanner)
 $form.Controls.Add($topShell)

 # Populate UI references into single $ui context
 $ui.TabControl        = $tabControl
 $ui.PreRoot           = $preRoot
 $ui.LblMetaLeft       = $lblMetaLeft
 $ui.LblMetaSid        = $lblMetaSid
 $ui.BtnCopySid        = $btnCopySid
 $ui.BtnTopRefresh     = $btnTopRefresh
 $ui.BtnTopDiag        = $btnTopDiag
 $ui.CritBanner        = $critBanner
 $ui.LblCritMsg        = $lblCritMsg
 $ui.PreBanner         = $preBanner
 $ui.PreAccent         = $preAccent
 $ui.LblPreBanTitle    = $lblPreBanTitle
 $ui.LblPreBanMsg      = $lblPreBanMsg
 $ui.LblStep1Chip      = $lblStep1Chip
 $ui.BtnOneStop        = $btnOneStop
 $ui.BtnToggleDisk     = $btnToggleDisk
 $ui.BtnIgnoreStep1    = $btnIgnoreStep1
 $ui.BtnStep1Fold      = $btnStep1Fold
 $ui.DgvDisks          = $dgvDisks
 $ui.LblStep2LockChip  = $lblStep2LockChip
 $ui.BtnRescanUsb      = $btnRescanUsb
 $ui.BtnInlineDiag     = $btnInlineDiag
 $ui.LblPillSec        = $lblPillSec
 $ui.LblPillUsb        = $lblPillUsb
 $ui.LblPillFast       = $lblPillFast
 $ui.LblPhysSummary    = $lblPhysSummary
 $ui.DgvUsb            = $dgvUsb
 $ui.BtnUsbReboot      = $btnUsbReboot
 $ui.BtnAdvBoot        = $btnAdvBoot
 $ui.BtnBiosBoot       = $btnBiosBoot
 $ui.PostBanner        = $postBanner
 $ui.PostAccent        = $postAccent
 $ui.LblPostBanTitle   = $lblPostBanTitle
 $ui.LblPostBanMsg     = $lblPostBanMsg
 $ui.TileRole          = $tileRole
 $ui.TileSpool         = $tileSpool
 $ui.TileQueue         = $tileQueue
 $ui.TileShare         = $tileShare
 $ui.DgvPrinters       = $dgvPrinters
 $ui.BtnSpoolerReset   = $btnSpoolerReset
 $ui.BtnPostRefresh    = $btnPostRefresh
 $ui.BottomDock        = $bottomDock
 $ui.LogDrawerWrap     = $logDrawerWrap
 $ui.TbLog             = $logBoxObj.TextBox
 $ui.BtnToggleLog      = $btnToggleLog
 $ui.LblStatusText     = $lblStatusText

 # ==================== CORE UI HELPERS (CLOSURE-SAFE) ====================
 $ui.SetStatus = {
  param([string]$msg, [string]$kind = "Idle")
  if ($ui.Form.IsDisposed) { return }
  $ui.LblStatusText.Text = $msg
  switch ($kind) {
   "Busy"  { $ui.LblStatusText.ForeColor = $ui.Theme.AsanDeep }
   "OK"    { $ui.LblStatusText.ForeColor = $ui.Theme.AsanDeep }
   "Warn"  { $ui.LblStatusText.ForeColor = $ui.Theme.AsanOrangeText }
   "Error" { $ui.LblStatusText.ForeColor = $ui.Theme.DangerRedDeep }
   default { $ui.LblStatusText.ForeColor = $ui.Theme.InkSecondary }
  }
 }.GetNewClosure()

 $ui.AppendLog = {
  param([string]$line)
  if ($ui.Form.IsDisposed) { return }
  $ts = (Get-Date).ToString("HH:mm:ss")
  $entry = "[" + $ts + "] " + $line + "`r`n"
  $ui.TbLog.AppendText($entry)
 }.GetNewClosure()

 $ui.SetLogExpanded = {
  param([bool]$expand)
  $ui.State.LogExpanded = $expand
  $ui.LogDrawerWrap.Visible = $expand
  $ui.BottomDock.Height = if ($expand) { 114 } else { 38 }
  $ui.BtnToggleLog.Text = if ($expand) { U "\uC0C1\uC138 \uB85C\uADF8 \uC811\uAE30" } else { U "\uC0C1\uC138 \uB85C\uADF8 \uBCF4\uAE30" }
 }.GetNewClosure()

 $ui.ApplyStep1RowLayout = {
  $efiRep = $ui.State.EfiRep
  $hasRisk = ($null -ne $efiRep -and $efiRep.HasBlockingRisk)
  if ($hasRisk) {
   $ui.State.Step1Collapsed = $false
  }
  if ($ui.State.Step1Collapsed) {
   $ui.DgvDisks.Visible = $false
   $ui.PreRoot.RowStyles[1] = New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)
   $ui.PreRoot.RowStyles[2] = New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)
   $ui.BtnStep1Fold.Text = U "\uD3BC\uCE58\uAE30"
  } else {
   $ui.DgvDisks.Visible = $true
   $pct1 = if ($hasRisk) { 42 } else { 38 }
   $ui.PreRoot.RowStyles[1] = New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, $pct1)
   $ui.PreRoot.RowStyles[2] = New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, (100 - $pct1))
   $ui.BtnStep1Fold.Text = U "\uC811\uAE30"
  }
 }.GetNewClosure()

 # Centralized Button State & Disabled-Tooltip Synchronizer (Max 1 Primary per tab!)
 $ui.SyncButtonStates = {
  $st = $ui.State
  $busy = [bool]$st.IsBusy
  $busyTip = U "\uD604\uC7AC \uC791\uC5C5\uC774 \uC9C4\uD589 \uC911\uC785\uB2C8\uB2E4. \uC644\uB8CC \uD6C4 \uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694."

  Set-AsanButtonState $ui.BtnTopRefresh (-not $busy) $busyTip $ui "HeaderUtil"
  Set-AsanButtonState $ui.BtnRescanUsb  (-not $busy) $busyTip $ui "Secondary"
  Set-AsanButtonState $ui.BtnPostRefresh (-not $busy) $busyTip $ui "Secondary"
  Set-AsanButtonState $ui.BtnSpoolerReset (-not $busy) $busyTip $ui "Primary"

  $efiRep = $st.EfiRep
  $snap = $st.Step2Snap
  $hasRisk = ($null -ne $efiRep -and $efiRep.HasBlockingRisk)
  $isLocked = ($hasRisk -and -not $st.Step1Bypassed)
  $canAutoFix = ($null -ne $efiRep -and -not $efiRep.SplitBoot -and $efiRep.ActionableConflictItems.Count -gt 0)

  # Step 1 Fold button: hidden during active conflicts so header stays clean and risk cannot be hidden
  $ui.BtnStep1Fold.Visible = (-not $hasRisk)
  if ($ui.BtnStep1Fold.Visible) {
   Set-AsanButtonState $ui.BtnStep1Fold (-not $busy) $busyTip $ui "Secondary"
  }

  # Step 1 One-Stop Fix button
  $oneStopReason = if ($busy) {
   $busyTip
  } elseif ($efiRep -and $efiRep.SplitBoot) {
   U "Windows\uC640 \uBD80\uD305 EFI\uAC00 \uC11C\uB85C \uB2E4\uB978 \uB514\uC2A4\uD06C\uC5D0 \uBD84\uB9AC\uB418\uC5B4 \uC790\uB3D9 \uC815\uB9AC\uB97C \uCC28\uB2E8\uD588\uC2B5\uB2C8\uB2E4."
  } else {
   U "\uC790\uB3D9 \uC815\uB9AC\uAC00 \uD544\uC694\uD55C \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uAC00 \uBC1C\uACAC\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4."
  }
  $oneStopVar = if ($canAutoFix) { "Primary" } else { "Secondary" }
  Set-AsanButtonState $ui.BtnOneStop ($canAutoFix -and -not $busy) $oneStopReason $ui $oneStopVar

  # Step 1 Individual Disk Toggle button
  $canTog = $false
  $togReason = if ($busy) { $busyTip } else { U "\uC704 \uB514\uC2A4\uD06C \uBAA9\uB85D\uC5D0\uC11C \uC804\uD658\uD560 \uBCF4\uC870 \uB514\uC2A4\uD06C\uB97C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694." }
  if (-not $busy -and $ui.DgvDisks.SelectedRows.Count -gt 0 -and $null -ne $ui.DgvDisks.SelectedRows[0].Tag) {
   $selIt = $ui.DgvDisks.SelectedRows[0].Tag
   if ($selIt.IsProtected) {
    $togReason = U "\uD604\uC7AC Windows, WinPE \uB610\uB294 \uC77D\uAE30 \uC804\uC6A9 \uBCF4\uD638 \uB514\uC2A4\uD06C\uB294 \uBCC0\uACBD\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4."
   } elseif ($selIt.State -in @("ACTIVE","DISABLED")) {
    $canTog = $true
   } else {
    $togReason = U "\uC120\uD0DD\uD55C \uB514\uC2A4\uD06C\uC5D0\uB294 \uC804\uD658 \uAC00\uB2A5\uD55C \uBD80\uD2B8\uB85C\uB354\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4."
   }
  }
  Set-AsanButtonState $ui.BtnToggleDisk $canTog $togReason $ui $(if ($canTog) { "SoftTeal" } else { "Secondary" })

  # Step 1 Ignore button visibility
  $ui.BtnIgnoreStep1.Visible = ($hasRisk -and -not $st.Step1Bypassed)
  if ($ui.BtnIgnoreStep1.Visible) {
   Set-AsanButtonState $ui.BtnIgnoreStep1 (-not $busy) $busyTip $ui "SoftOrange"
  }

  # Step 2 buttons (Max 1 Primary on Tab 1: if Step 1 needs fix, Step 1 holds Primary; else Step 2 recommended button holds Primary!)
  $isUefi = ($null -ne $snap -and $null -ne $snap.BiosDiag -and [bool]$snap.BiosDiag.BootMode.IsUefi)
  $canStep2Act = (-not $busy -and $isUefi -and -not $isLocked)
  $selUsbTag = if ($ui.DgvUsb.SelectedRows.Count -gt 0) { $ui.DgvUsb.SelectedRows[0].Tag } else { $null }
  $hasMatchedSel = ($null -ne $selUsbTag -and $selUsbTag.Kind -eq "NVRAM")
  $canUsbReboot = ($canStep2Act -and $hasMatchedSel)

  $step2BlockTip = if ($busy) {
   $busyTip
  } elseif (-not $isUefi) {
   U "\uB808\uAC70\uC2DC \uBD80\uD305 \uD658\uACBD\uC5D0\uC11C\uB294 UEFI \uC790\uB3D9 \uC7AC\uBD80\uD305\uC744 \uC9C0\uC6D0\uD558\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4. \uBD80\uD305 \uBA54\uB274 \uB2E8\uCD95\uD0A4\uB97C \uC0AC\uC6A9\uD574 \uC8FC\uC138\uC694."
  } elseif ($isLocked) {
   U "1\uB2E8\uACC4\uC758 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uB97C \uBA3C\uC800 \uC815\uB9AC\uD558\uAC70\uB098 \uC704\uD5D8 \uD655\uC778 \uD6C4 \uAC74\uB108\uB6F0\uAE30\uB97C \uC9C4\uD589\uD574 \uC8FC\uC138\uC694."
  } else {
   ""
  }

  $usbRebootTip = if ($step2BlockTip) {
   $step2BlockTip
  } elseif (-not $snap -or $snap.UsbInfo.PhysicalUsbList.Count -eq 0) {
   U "WinPE USB\uB97C PC\uC5D0 \uC5F0\uACB0\uD55C \uB4A4 USB \uB2E4\uC2DC \uCC3E\uAE30\uB97C \uB20C\uB7EC \uC8FC\uC138\uC694."
  } elseif ($snap.MatchedEntries.Count -eq 0) {
   U "UEFI \uD38C\uC6E8\uC5B4 \uBAA9\uB85D\uC5D0 \uB4F1\uB85D\uB41C USB\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4. \uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9 \uB610\uB294 BIOS \uC124\uC815 \uC5F4\uAE30\uB97C \uC0AC\uC6A9\uD574 \uC8FC\uC138\uC694."
  } else {
   U "\uC704 \uBAA9\uB85D\uC5D0\uC11C \uBD80\uD305 \uB300\uC0C1 USB \uD589\uC744 \uC120\uD0DD\uD574 \uC8FC\uC138\uC694."
  }

  $recAct = if ($st.PreGuidance) { $st.PreGuidance.RecommendedAction } else { "" }
  $vUsb  = if ($canUsbReboot -and $recAct -eq "USB_REBOOT" -and -not $canAutoFix) { "Primary" } elseif ($canUsbReboot) { "SoftTeal" } else { "Secondary" }
  $vAdv  = if ($canStep2Act -and $recAct -eq "ADV_BOOT" -and -not $canAutoFix) { "Primary" } elseif ($canStep2Act -and $snap.MatchedEntries.Count -eq 0 -and $snap.UsbInfo.PhysicalUsbList.Count -gt 0) { "SoftTeal" } else { "Secondary" }
  $vBios = if ($canStep2Act -and $recAct -eq "BIOS_SETUP" -and -not $canAutoFix) { "Orange" } else { "Secondary" }

  Set-AsanButtonState $ui.BtnUsbReboot $canUsbReboot $usbRebootTip $ui $vUsb
  Set-AsanButtonState $ui.BtnAdvBoot   $canStep2Act  $step2BlockTip $ui $vAdv
  Set-AsanButtonState $ui.BtnBiosBoot  $canStep2Act  $step2BlockTip $ui $vBios
 }.GetNewClosure()

 # ==================== DATA REFRESH LOGIC ====================
 $ui.RefreshPreSid = {
  $u = $ui
  $t = $u.Theme
  $f = $u.Fonts
  $st = $u.State
  $u.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
  & $u.SetStatus (U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C\uC640 USB \uD658\uACBD\uC744 \uC810\uAC80\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4...") "Busy"
  try {
   $efiRep = Get-InternalBootloaderReport $false
   $snap = Get-PreSidStep2Snapshot $st.SysInfo
   $st.EfiRep = $efiRep
   $st.Step2Snap = $snap
   if (-not $efiRep.HasBlockingRisk) { $st.Step1Bypassed = $false }

   $bm = $snap.BiosDiag.BootMode
   $bmLabel = if ($bm.IsUefi) { U "UEFI \uBD80\uD305" } elseif ($bm.Mode -eq "Legacy") { U "\uB808\uAC70\uC2DC \uBD80\uD305" } else { U "\uBD80\uD305 \uBC29\uC2DD \uBBF8\uD655\uC778" }
   $osTxt = if ($st.SysInfo.OsSummary) { $st.SysInfo.OsSummary } else { "Windows" }
   $dispModel = if ($st.SysInfo.DisplayVendor) { $st.SysInfo.DisplayVendor + " " + $st.SysInfo.ModelName } else { [string]$st.SysInfo.ModelName }
   $dot = [string][char]0x00B7
   $u.LblMetaLeft.Text = ($env:COMPUTERNAME + "  " + $dot + "  " + $dispModel + "  " + $dot + "  " + $osTxt + "  " + $dot + "  " + $bmLabel)

   # Conditional Critical Banner (Legacy MBR or SplitBoot ? zero parentheses)
   if (-not $bm.IsUefi) {
    $u.LblCritMsg.Text = U "\uC774 PC\uB294 \uB808\uAC70\uC2DC \uBD80\uD305 \uBC29\uC2DD\uC785\uB2C8\uB2E4. USB \uC790\uB3D9 \uC7AC\uBD80\uD305 \uB300\uC2E0 \uBD80\uD305 \uBA54\uB274 \uB2E8\uCD95\uD0A4\uB97C \uC0AC\uC6A9\uD574 \uC8FC\uC138\uC694."
    $u.CritBanner.Visible = $true
   } elseif ($efiRep.SplitBoot) {
    $u.LblCritMsg.Text = (U "Windows \uB514\uC2A4\uD06C ") + $efiRep.BootDisk + (U "\uACFC \uBD80\uD305 EFI \uB514\uC2A4\uD06C ") + $efiRep.SysDisk + (U "\uC774 \uC11C\uB85C \uB2EC\uB77C \uC790\uB3D9 \uC815\uB9AC\uB97C \uCC28\uB2E8\uD588\uC2B5\uB2C8\uB2E4.")
    $u.CritBanner.Visible = $true
   } else {
    $u.CritBanner.Visible = $false
   }

   # 1. Populate STEP 1 Internal Disks DataGridView
   $u.DgvDisks.Rows.Clear()
   $firstConflictRowIdx = -1
   foreach ($it in $efiRep.Items) {
    $partStr = if ($it.TargetPart -gt 0) {
     if ($it.BootType -eq "GPT_EFI") { "EFI #" + $it.TargetPart } else { "MBR #" + $it.TargetPart }
    } else { "-" }
    $guiSt = Format-BootloaderGuiStatus $it
    $rIdx = $u.DgvDisks.Rows.Add(("Disk " + $it.DiskNumber), [string]$it.Model, ([string]$it.SizeGB + " GB"), [string]$it.PartitionStyle, $partStr, $guiSt.Text)
    $row = $u.DgvDisks.Rows[$rIdx]
    $row.Tag = $it
    # Status-cell-only tinting; full-row tint reserved strictly for blocking conflicts (preserved even when selected!)
    if ($it.State -in @("ACTIVE","BOTH","MBR_OS_BLOCKED")) {
     if ($firstConflictRowIdx -lt 0) { $firstConflictRowIdx = $rIdx }
     $row.DefaultCellStyle.BackColor = $t.DangerRedTint
     $row.DefaultCellStyle.ForeColor = $t.DangerRedDeep
     $row.DefaultCellStyle.SelectionBackColor = $t.DangerRedTint
     $row.DefaultCellStyle.SelectionForeColor = $t.DangerRedDeep
     $row.Cells[5].Style.Font = $f.Bold
    } else {
     Set-AsanCellSemanticStyle $row.Cells[5] $guiSt.Kind $t $f ($guiSt.Kind -ne "Neutral")
    }
    foreach ($cell in $row.Cells) { $cell.ToolTipText = $guiSt.Tip }
   }
   $u.DgvDisks.ClearSelection()
   if ($firstConflictRowIdx -ge 0) { $u.DgvDisks.Rows[$firstConflictRowIdx].Selected = $true }

   if ($efiRep.HasBlockingRisk) {
    $u.LblStep1Chip.BackColor = $t.DangerRedTint
    $u.LblStep1Chip.ForeColor = $t.DangerRedDeep
    $u.LblStep1Chip.Text = (U "\uCDA9\uB3CC \uC704\uD5D8 ") + $efiRep.ConflictItems.Count + (U "\uAC74 \uBC1C\uACAC")
   } else {
    $u.LblStep1Chip.BackColor = $t.AsanMint
    $u.LblStep1Chip.ForeColor = $t.AsanDeep
    $u.LblStep1Chip.Text = (U "\uC774\uC0C1 \uC5C6\uC74C \u00B7 ") + $efiRep.Items.Count + (U "\uB300 \uD655\uC778")
   }
   & $u.ApplyStep1RowLayout

   # 2. STEP 2 Lock indicator & BIOS Status Pills (plain Korean, zero brackets/parentheses)
   $isStep2Locked = ($efiRep.HasBlockingRisk -and -not $st.Step1Bypassed)
   $u.LblStep2LockChip.Visible = $isStep2Locked

   $d = $snap.BiosDiag
   switch ($d.SecureBootState) {
    "On"       { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uCF1C\uC9D0";      $u.LblPillSec.BackColor = $t.DangerRedTint;  $u.LblPillSec.ForeColor = $t.DangerRedDeep }
    "Conflict" { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uD655\uC778 \uD544\uC694"; $u.LblPillSec.BackColor = $t.DangerRedTint;  $u.LblPillSec.ForeColor = $t.DangerRedDeep }
    "Off"      { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uAEBC\uC9D0";      $u.LblPillSec.BackColor = $t.AsanMint;       $u.LblPillSec.ForeColor = $t.AsanDeep }
    default    { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uBBF8\uD655\uC778";    $u.LblPillSec.BackColor = $t.AsanOrangeTint; $u.LblPillSec.ForeColor = $t.AsanOrangeText }
   }

   if ($d.UsbBootState -eq "Enabled") {
    $u.LblPillUsb.Text = U "USB \uBD80\uD305 \uD5C8\uC6A9"
    $u.LblPillUsb.BackColor = $t.AsanMint; $u.LblPillUsb.ForeColor = $t.AsanDeep
   } elseif ($d.IsConfirmedBlocked) {
    $u.LblPillUsb.Text = U "USB \uBD80\uD305 \uCC28\uB2E8\uB428"
    $u.LblPillUsb.BackColor = $t.DangerRedTint; $u.LblPillUsb.ForeColor = $t.DangerRedDeep
   } elseif ($d.UsbBootState -eq "Conflict") {
    $u.LblPillUsb.Text = U "USB \uBD80\uD305 \uAD50\uCC28 \uD655\uC778"
    $u.LblPillUsb.BackColor = $t.AsanOrangeTint; $u.LblPillUsb.ForeColor = $t.AsanOrangeText
   } elseif ($d.UsbBootState -eq "SuspectedDisabled") {
    $u.LblPillUsb.Text = U "USB \uBD80\uD305 \uBBF8\uB4F1\uB85D"
    $u.LblPillUsb.BackColor = $t.AsanOrangeTint; $u.LblPillUsb.ForeColor = $t.AsanOrangeText
   } else {
    $u.LblPillUsb.Text = U "USB \uBD80\uD305 \uC9C1\uC811 \uD655\uC778"
    $u.LblPillUsb.BackColor = $t.AsanOrangeTint; $u.LblPillUsb.ForeColor = $t.AsanOrangeText
   }

   if ($d.FastBootWarn) {
    $u.LblPillFast.Text = U "\uBE60\uB978 \uBD80\uD305 \uCF1C\uC9D0"
    $u.LblPillFast.BackColor = $t.AsanOrangeTint; $u.LblPillFast.ForeColor = $t.AsanOrangeText
   } else {
    $u.LblPillFast.Text = U "\uBE60\uB978 \uBD80\uD305 \uC774\uC0C1 \uC5C6\uC74C"
    $u.LblPillFast.BackColor = $t.MetaBarBg; $u.LblPillFast.ForeColor = $t.InkMuted
   }

   $u.ToolTip.SetToolTip($u.LblPillSec, ($d.SecureBootSignals -join "`r`n"))
   $u.ToolTip.SetToolTip($u.LblPillUsb, ($d.UsbBootDetail + "`r`n" + (U "\uC2E0\uB8B0\uB3C4: ") + $d.UsbBootConfidence))
   $u.ToolTip.SetToolTip($u.LblPillFast, $(if ($d.FastBootDetail) { $d.FastBootDetail } else { U "\uBE60\uB978 \uBD80\uD305 \uCC28\uB2E8 \uACBD\uACE0\uAC00 \uAC10\uC9C0\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4." }))

   # Physical USB compact summary chip on right side of BIOS strip
   $physList = @($snap.UsbInfo.PhysicalUsbList)
   if ($physList.Count -eq 0) {
    $u.LblPhysSummary.Text = U "\uC5F0\uACB0\uB41C \uBB3C\uB9AC USB \uC5C6\uC74C"
    $u.LblPhysSummary.ForeColor = $t.InkMuted
    $u.ToolTip.SetToolTip($u.LblPhysSummary, (U "WinPE USB\uB97C \uC5F0\uACB0\uD55C \uB4A4 USB \uB2E4\uC2DC \uCC3E\uAE30\uB97C \uB20C\uB7EC \uC8FC\uC138\uC694."))
   } else {
    $firstU = $physList[0]
    $roTxt = if ($firstU.IsReadOnly) { U " \u00B7 \uC77D\uAE30 \uC804\uC6A9" } else { "" }
    $moreTxt = if ($physList.Count -gt 1) { (U " \uC678 ") + ($physList.Count - 1) + (U "\uB300") } else { "" }
    $u.LblPhysSummary.Text = (U "\uC5F0\uACB0\uB41C USB: ") + $firstU.Model + " " + $firstU.SizeGB + $roTxt + $moreTxt
    $u.LblPhysSummary.ForeColor = $t.AsanDeep
    $physTip = ($physList | ForEach-Object { "Disk " + $_.DiskNumber + " " + $_.Model + " " + $_.SizeGB + " | " + $_.Partitions }) -join "`r`n"
    $u.ToolTip.SetToolTip($u.LblPhysSummary, $physTip)
   }

   # 3. Populate Unified USB Selection DataGridView
   $u.DgvUsb.Rows.Clear()
   $matched = @($snap.MatchedEntries)
   if ($matched.Count -gt 0) {
    for ($i = 0; $i -lt $matched.Count; $i++) {
     $m = $matched[$i]
     $devStr = if ($m.Device) { [string]$m.Device } else { U "UEFI \uD38C\uC6E8\uC5B4" }
     $matchLvl = if ($m.IsExact) { U "\uC815\uD655 \uC77C\uCE58" } else { U "\uBC94\uC6A9 \uD56D\uBAA9" }
     $guideTxt = if ($m.IsExact) { U "\uBC14\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4" } else { U "\uD56D\uBAA9 \uC774\uB984\uC744 \uD655\uC778\uD55C \uB4A4 \uC7AC\uBD80\uD305\uD574 \uC8FC\uC138\uC694" }
     $rIdx = $u.DgvUsb.Rows.Add((U "\uBD80\uD305 \uB300\uC0C1"), $matchLvl, [string]$m.Description, $devStr, $guideTxt)
     $row = $u.DgvUsb.Rows[$rIdx]
     $row.Tag = [PSCustomObject]@{ Kind = "NVRAM"; Entry = $m }
     Set-AsanCellSemanticStyle $row.Cells[1] $(if ($m.IsExact) { "OK" } else { "Warn" }) $t $f $true
     $tip = ([string]$m.MatchTag) + "`r`nGUID: " + $m.Identifier + "`r`n" + (U "\uC7A5\uCE58: ") + $devStr
     foreach ($cell in $row.Cells) { $cell.ToolTipText = $tip }
    }
    $u.DgvUsb.Rows[0].Selected = $true
   } elseif ($physList.Count -gt 0) {
    foreach ($ud in $physList) {
     $roTag = if ($ud.IsReadOnly) { U " \u00B7 \uC77D\uAE30 \uC804\uC6A9" } else { "" }
     $devStr = $ud.SizeGB + $roTag
     $guideTxt = if ($ud.IsEfiReady) { U "\uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC774\uB3D9\uD574 \uC7A5\uCE58\uB97C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694" } else { U "EFI \uBD80\uD2B8 \uD30C\uD2F0\uC158\uC774 \uD655\uC778\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4" }
     $rIdx = $u.DgvUsb.Rows.Add((U "\uBB3C\uB9AC USB"), (U "NVRAM \uBBF8\uB4F1\uB85D"), [string]$ud.Model, $devStr, $guideTxt)
     $row = $u.DgvUsb.Rows[$rIdx]
     $row.Tag = [PSCustomObject]@{ Kind = "PHYSICAL_ONLY"; Disk = $ud }
     Set-AsanCellSemanticStyle $row.Cells[1] "Warn" $t $f $true
     $tip = "Disk " + $ud.DiskNumber + " | " + $ud.Model + "`r`n" + (U "\uD30C\uD2F0\uC158: ") + $(if ($ud.Partitions) { $ud.Partitions } else { "-" })
     foreach ($cell in $row.Cells) { $cell.ToolTipText = $tip }
    }
   } else {
    $rIdx = $u.DgvUsb.Rows.Add((U "\uC548\uB0B4"), (U "\uBBF8\uC5F0\uACB0"), (U "\uC5F0\uACB0\uB41C WinPE USB\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4"), "-", (U "USB\uB97C \uC5F0\uACB0\uD55C \uB4A4 USB \uB2E4\uC2DC \uCC3E\uAE30\uB97C \uB20C\uB7EC \uC8FC\uC138\uC694"))
    $row = $u.DgvUsb.Rows[$rIdx]
    $row.Tag = $null
    $row.DefaultCellStyle.ForeColor = $t.InkMuted
   }
   if ($matched.Count -eq 0) { $u.DgvUsb.ClearSelection() }

   # 4. Contextual Guidance Banner & Sync All Buttons
   $guid = Get-PreSidGuidance $st.SysInfo $efiRep $snap.BiosDiag $snap.UsbInfo $snap.MatchedEntries $st.Step1Bypassed
   $st.PreGuidance = $guid
   Set-AsanGuidanceBannerVisual $u.PreBanner $u.PreAccent $u.LblPreBanTitle $u.LblPreBanMsg $guid $t
   & $u.SyncButtonStates
   & $u.AppendLog ((U "\uC0AC\uC804 \uC810\uAC80 \uC644\uB8CC \u00B7 \uB0B4\uC7A5 \uB514\uC2A4\uD06C ") + $efiRep.Items.Count + (U "\uB300, \uBB3C\uB9AC USB ") + $physList.Count + (U "\uB300, \uBD80\uD305 \uB9E4\uCE6D ") + $matched.Count + (U "\uAC74"))
   & $u.SetStatus (U "\uC0AC\uC804 \uC810\uAC80 \uC644\uB8CC") "OK"
  } catch {
   & $u.AppendLog ((U "\uC0AC\uC804 \uC810\uAC80 \uC624\uB958: ") + $_.Exception.Message)
   & $u.SetStatus (U "\uC0AC\uC804 \uC810\uAC80 \uC911 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4") "Error"
  } finally {
   if (-not $u.Form.IsDisposed) { $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
  }
 }.GetNewClosure()

 $ui.RefreshPostSid = {
  $u = $ui
  $t = $u.Theme
  $f = $u.Fonts
  $u.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
  & $u.SetStatus (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uC0C1\uD0DC\uB97C \uD655\uC778\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4...") "Busy"
  try {
   $ps = Get-PostSidStatus
   $u.State.PostStatus = $ps
   $guid = Get-PostSidGuidance $ps
   Set-AsanGuidanceBannerVisual $u.PostBanner $u.PostAccent $u.LblPostBanTitle $u.LblPostBanMsg $guid $t

   # Update Meta Bar SID
   $sidVal = if ($ps.MachineSid) { [string]$ps.MachineSid } else { U "\uD655\uC778 \uBD88\uAC00" }
   $u.LblMetaSid.Text = "SID " + $sidVal
   $u.ToolTip.SetToolTip($u.LblMetaSid, ("Machine SID: " + $sidVal))

   # Tile 1: PC Role
   $roleTxt = switch ($ps.Role) {
    "Host"   { U "\uBA54\uC778 \uD504\uB9B0\uD130 PC" }
    "Client" { U "\uD074\uB77C\uC774\uC5B8\uD2B8 PC" }
    default  { U "\uD655\uC778 \uBCF4\uB958" }
   }
   $u.TileRole.Value.Text = $roleTxt
   $u.TileRole.Value.ForeColor = if ($ps.Role -eq "Host") { $t.AsanLight } elseif ($ps.Role -eq "Client") { $t.AsanDeep } else { $t.AsanOrangeText }
   $u.TileRole.Sub.Text = if ($ps.Role -eq "Host") {
    (U "\uACF5\uC720 \uD504\uB9B0\uD130 ") + $ps.SharedPrinters.Count + (U "\uB300 \uD638\uC2A4\uD305")
   } elseif ($ps.Role -eq "Client") {
    (U "\uB124\uD2B8\uC6CC\uD06C \uD504\uB9B0\uD130 ") + $ps.NetworkPrinters.Count + (U "\uB300 \uC5F0\uACB0")
   } else {
    U "\uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4 \uC911\uC9C0\uB428"
   }

   # Tile 2: Spooler Service
   $spOk = ($ps.SpoolerStatus -eq "Running" -and $ps.SpoolerStartMode -ne "Disabled" -and -not $ps.PrinterQueryError)
   $u.TileSpool.Value.Text = if ($ps.SpoolerStatus -eq "Running") {
    if ($ps.PrinterQueryError) { U "\uC751\uB2F5 \uC624\uB958" } else { U "\uC2E4\uD589 \uC911" }
   } elseif ($ps.SpoolerStatus -eq "Stopped") { U "\uC911\uC9C0\uB428" } else { [string]$ps.SpoolerStatus }
   $u.TileSpool.Value.ForeColor = if ($spOk) { $t.AsanDeep } else { $t.DangerRedDeep }
   $startKo = switch ($ps.SpoolerStartMode) {
    "Auto"     { U "\uC790\uB3D9 \uC2DC\uC791" }
    "Manual"   { U "\uC218\uB3D9 \uC2DC\uC791" }
    "Disabled" { U "\uC0AC\uC6A9 \uC548 \uD568" }
    default    { [string]$ps.SpoolerStartMode }
   }
   $u.TileSpool.Sub.Text = (U "\uC2DC\uC791 \uC720\uD615 ") + $startKo

   # Tile 3: Print Queue
   $u.TileQueue.Value.Text = [string]$ps.QueueTotalCount + (U "\uAC74")
   $u.TileQueue.Value.ForeColor = if ($ps.QueueTotalCount -gt 0) { $t.AsanOrangeText } else { $t.AsanDeep }
   $u.TileQueue.Sub.Text = if ($ps.QueueTotalCount -gt 0) {
    (U "\uC794\uC5EC \uC778\uC1C4 \uD30C\uC77C ") + $ps.QueueSplShdCount + (U "\uAC74 \uC815\uB9AC \uAC00\uB2A5")
   } else {
    U "\uC313\uC778 \uB300\uAE30\uC5F4 \uC5C6\uC74C"
   }

   # Tile 4: Role-specific Share Security or Remote Host Connectivity
   if ($ps.Role -eq "Host") {
    $u.TileShare.Caption.Text = U "\uACF5\uC720 \uBCF4\uC548 \uC0C1\uD0DC"
    $fwOk = ($ps.FirewallInboundEnabled -gt 0 -or $ps.FirewallInboundTotal -lt 0)
    if ($ps.HasPublicProfile) {
     $u.TileShare.Value.Text = U "\uACF5\uC6A9 \uB124\uD2B8\uC6CC\uD06C \uC8FC\uC758"
     $u.TileShare.Value.ForeColor = $t.DangerRedDeep
    } elseif (-not $fwOk) {
     $u.TileShare.Value.Text = U "\uBC29\uD654\uBCBD \uCC28\uB2E8 \uC8FC\uC758"
     $u.TileShare.Value.ForeColor = $t.DangerRedDeep
    } else {
     $u.TileShare.Value.Text = U "\uACF5\uC720 \uC124\uC815 \uC815\uC0C1"
     $u.TileShare.Value.ForeColor = $t.AsanDeep
    }
    $fwSub = if ($ps.FirewallInboundTotal -lt 0) { U "\uBC29\uD654\uBCBD \uBBF8\uD655\uC778" } else { (U "\uACF5\uC720 \uADDC\uCE59 ") + $ps.FirewallInboundEnabled + "/" + $ps.FirewallInboundTotal }
    $u.TileShare.Sub.Text = $fwSub
   } else {
    $u.TileShare.Caption.Text = U "\uBA54\uC778 PC \uC5F0\uACB0"
    if ($ps.RemoteHostChecks.Count -eq 0) {
     $u.TileShare.Value.Text = U "\uC5F0\uACB0 \uB300\uC0C1 \uC5C6\uC74C"
     $u.TileShare.Value.ForeColor = $t.InkMuted
     $u.TileShare.Sub.Text = U "\uB4F1\uB85D\uB41C \uC6D0\uACA9 \uD504\uB9B0\uD130 \uC5C6\uC74C"
    } else {
     $fails = @($ps.RemoteHostChecks | Where-Object { -not $_.Reachable })
     if ($fails.Count -gt 0) {
      $u.TileShare.Value.Text = U "\uC751\uB2F5 \uC5C6\uC74C"
      $u.TileShare.Value.ForeColor = $t.AsanOrangeText
      $u.TileShare.Sub.Text = ($fails | ForEach-Object { "\\" + $_.Server }) -join ", "
     } else {
      $u.TileShare.Value.Text = U "\uC5F0\uACB0 \uC815\uC0C1"
      $u.TileShare.Value.ForeColor = $t.AsanDeep
      $u.TileShare.Sub.Text = ($ps.RemoteHostChecks | ForEach-Object { "\\" + $_.Server }) -join ", "
     }
    }
   }

   # Populate Printers DataGridView
   $u.DgvPrinters.Rows.Clear()
   if ($ps.SpoolerStatus -ne "Running") {
    $rIdx = $u.DgvPrinters.Rows.Add((U "\uC548\uB0B4"), (U "\uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4\uAC00 \uC911\uC9C0\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4"), "-", "-", (U "\uC544\uB798 \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uC2E4\uD589\uD574 \uC8FC\uC138\uC694"))
    Set-AsanCellSemanticStyle $u.DgvPrinters.Rows[$rIdx].Cells[0] "Warn" $t $f $true
   } elseif ($ps.PrinterQueryError) {
    $rIdx = $u.DgvPrinters.Rows.Add((U "\uC624\uB958"), (U "\uD504\uB9B0\uD130 \uBAA9\uB85D \uC870\uD68C \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4"), "-", "-", (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uC2E4\uD589\uD574 \uC8FC\uC138\uC694"))
    Set-AsanCellSemanticStyle $u.DgvPrinters.Rows[$rIdx].Cells[0] "Error" $t $f $true
   } elseif ($ps.Printers.Count -eq 0) {
    $rIdx = $u.DgvPrinters.Rows.Add((U "\uC548\uB0B4"), (U "\uC124\uCE58\uB41C \uD504\uB9B0\uD130\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4"), "-", "-", "-")
    $u.DgvPrinters.Rows[$rIdx].DefaultCellStyle.ForeColor = $t.InkMuted
   } else {
    foreach ($pr in $ps.Printers) {
     $typeTxt = if ($pr.IsNetwork) { U "\uB124\uD2B8\uC6CC\uD06C" } elseif ($pr.Shared) { U "\uACF5\uC720 \uD638\uC2A4\uD2B8" } else { U "\uB85C\uCEEC" }
     $shareTxt = if ($pr.IsNetwork) { if ($pr.RemoteServer) { "\\" + $pr.RemoteServer } else { "-" } } elseif ($pr.Shared) { "\\" + $ps.ComputerName + "\" + $pr.ShareName } else { "-" }
     $rIdx = $u.DgvPrinters.Rows.Add($typeTxt, [string]$pr.Name, $shareTxt, [string]$pr.PortName, [string]$pr.DriverName)
     $row = $u.DgvPrinters.Rows[$rIdx]
     $knd = if ($pr.Shared -and -not $pr.IsNetwork) { "OK" } elseif ($pr.IsNetwork) { "Info" } else { "Neutral" }
     Set-AsanCellSemanticStyle $row.Cells[0] $knd $t $f ($knd -ne "Neutral")
     foreach ($cell in $row.Cells) { $cell.ToolTipText = ([string]$pr.Name + "`r`n" + (U "\uD3EC\uD2B8: ") + $pr.PortName + "`r`n" + (U "\uB4DC\uB77C\uC774\uBC84: ") + $pr.DriverName) }
    }
   }
   $u.DgvPrinters.ClearSelection()
   & $u.SyncButtonStates
   & $u.SetStatus (U "\uC900\uBE44 \uC644\uB8CC") "Idle"
  } catch {
   & $u.AppendLog ((U "\uC0AC\uD6C4 \uC810\uAC80 \uC624\uB958: ") + $_.Exception.Message)
   & $u.SetStatus (U "\uD504\uB9B0\uD130 \uC0C1\uD0DC \uC870\uD68C \uC911 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4") "Error"
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
 $btnTopDiag.Add_Click({ Show-GuiDiagnosticsDialog $ui.Form $ui.State.SysInfo $ui.State.Step2Snap $ui.State.PostStatus $ui.TbLog.Text "" }.GetNewClosure())
 $btnInlineDiag.Add_Click({ Show-GuiDiagnosticsDialog $ui.Form $ui.State.SysInfo $ui.State.Step2Snap $ui.State.PostStatus $ui.TbLog.Text "" }.GetNewClosure())
 $btnCritDetail.Add_Click({ Show-GuiDiagnosticsDialog $ui.Form $ui.State.SysInfo $ui.State.Step2Snap $ui.State.PostStatus $ui.TbLog.Text "" }.GetNewClosure())

 # Instant-feedback SID copy button (1.5s visual confirmation)
 $btnCopySid.Add_Click({
  $sidStr = if ($ui.State.PostStatus -and $ui.State.PostStatus.MachineSid) { [string]$ui.State.PostStatus.MachineSid } else { "" }
  if (-not $sidStr) { return }
  try {
   [System.Windows.Forms.Clipboard]::SetText($sidStr)
   $ui.BtnCopySid.Text = U "\uBCF5\uC0AC\uB428"
   Set-AsanButtonVariant $ui.BtnCopySid "SoftTeal" $ui
   & $ui.SetStatus ((U "Machine SID\uAC00 \uD074\uB9BD\uBCF4\uB4DC\uC5D0 \uBCF5\uC0AC\uB418\uC5C8\uC2B5\uB2C8\uB2E4: ") + $sidStr) "OK"
   $ui.CopyResetTimer.Stop()
   $ui.CopyResetTimer.Start()
  } catch {}
 }.GetNewClosure())

 $copyResetTimer.Add_Tick({
  $ui.CopyResetTimer.Stop()
  if (-not $ui.BtnCopySid.IsDisposed) {
   $ui.BtnCopySid.Text = U "SID \uBCF5\uC0AC"
   Set-AsanButtonVariant $ui.BtnCopySid "Secondary" $ui
  }
 }.GetNewClosure())

 # Collapsible Step 1 & Bottom Log Console
 $btnStep1Fold.Add_Click({
  $ui.State.Step1Collapsed = (-not $ui.State.Step1Collapsed)
  & $ui.ApplyStep1RowLayout
 }.GetNewClosure())

 $btnToggleLog.Add_Click({
  & $ui.SetLogExpanded (-not $ui.State.LogExpanded)
 }.GetNewClosure())

 # Keyboard shortcuts: F5 refresh, Alt+1 / Alt+2 tabs
 $form.Add_KeyDown({
  param($sender, $e)
  if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5 -and -not $ui.State.IsBusy) {
   $e.SuppressKeyPress = $true
   & $ui.RefreshAll
  } elseif ($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::D1) {
   $e.SuppressKeyPress = $true
   $ui.TabControl.SelectedIndex = 0
  } elseif ($e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::D2) {
   $e.SuppressKeyPress = $true
   $ui.TabControl.SelectedIndex = 1
  }
 }.GetNewClosure())

 # Selection synchronization & natural double-click defaults
 $dgvDisks.Add_SelectionChanged({ & $ui.SyncButtonStates }.GetNewClosure())
 $dgvUsb.Add_SelectionChanged({ & $ui.SyncButtonStates }.GetNewClosure())
 $dgvDisks.Add_CellDoubleClick({
  param($sender, $e)
  if ($e.RowIndex -ge 0 -and $ui.BtnToggleDisk.Enabled) { $ui.BtnToggleDisk.PerformClick() }
 }.GetNewClosure())
 $dgvUsb.Add_CellDoubleClick({
  param($sender, $e)
  if ($e.RowIndex -ge 0 -and $ui.BtnUsbReboot.Enabled) { $ui.BtnUsbReboot.PerformClick() }
 }.GetNewClosure())

 # STEP 1: One-Stop Fix
 $btnOneStop.Add_Click({
  $rep = $ui.State.EfiRep
  if (-not $rep -or $rep.SplitBoot -or $rep.ActionableConflictItems.Count -eq 0) { return }
  $targetsDesc = ($rep.ActionableConflictItems | ForEach-Object { "  Disk " + $_.DiskNumber + "  " + $_.Model + "  " + $_.BootType + " #" + $_.TargetPart }) -join "`r`n"
  $qMsg = (U "\uC544\uB798 \uBCF4\uC870 \uB514\uC2A4\uD06C\uC758 \uC794\uC874 \uBD80\uD2B8\uB85C\uB354\uB97C \uBE44\uD65C\uC131\uD654\uD560\uAE4C\uC694?`r`n\uD30C\uD2F0\uC158 \uC0AD\uC81C\uB098 \uD3EC\uB9F7 \uC5C6\uC774 \uC774\uB984\uB9CC \uBCC0\uACBD\uD558\uBBC0\uB85C \uC5B8\uC81C\uB4E0 \uC6D0\uB798\uB300\uB85C \uBCF5\uAD6C\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.`r`n`r`n") + $targetsDesc
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, $qMsg, (U "\uC794\uC874 \uBD80\uD2B8\uB85C\uB354 \uC815\uB9AC \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $changed = 0
  $failedMsgs = New-Object System.Collections.ArrayList
  $msgs = New-Object System.Collections.ArrayList
  foreach ($ci in $rep.ActionableConflictItems) {
   $r = Invoke-BootloaderAction $ci "DISABLE"
   [void]$msgs.Add($r.Message)
   & $ui.AppendLog $r.Message
   if ($r.Warning) { [void]$msgs.Add($r.Warning); & $ui.AppendLog $r.Warning }
   if ($r.Success) { $changed++ } else { [void]$failedMsgs.Add($r.Message) }
  }

  if ($changed -gt 0) {
   $diskLbl = if ($null -ne $rep.BootDisk) { "Disk " + $rep.BootDisk } else { $env:SystemDrive }
   $bbQ = ($msgs -join "`r`n") + "`r`n`r`n" + (U "\uD604\uC7AC Windows \uB514\uC2A4\uD06C ") + $diskLbl + (U "\uB97C UEFI \uBD80\uD305 1\uC21C\uC704\uB85C \uB4F1\uB85D\uD560\uAE4C\uC694?")
   $dr2 = [System.Windows.Forms.MessageBox]::Show($ui.Form, $bbQ, (U "UEFI \uBD80\uD305 \uD56D\uBAA9 \uB4F1\uB85D"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
   if ($dr2 -eq [System.Windows.Forms.DialogResult]::Yes) {
    $bbRes = Invoke-NativeOem "bcdboot.exe" ('"' + $env:SystemRoot + '" /f UEFI')
    if ($bbRes.ExitCode -eq 0) {
     & $ui.AppendLog (U "UEFI \uBD80\uD305 \uD56D\uBAA9 \uB4F1\uB85D\uC774 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4.")
     [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "UEFI \uBD80\uD305 \uD56D\uBAA9 \uB4F1\uB85D\uC774 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4."), (U "\uB4F1\uB85D \uC644\uB8CC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
     $errDet = "bcdboot ExitCode=" + $bbRes.ExitCode + " " + ($bbRes.Lines -join " ")
     & $ui.AppendLog $errDet
     Invoke-GuiErrorReportPrompt $ui (U "UEFI \uB4F1\uB85D \uC624\uB958") (U "UEFI \uBD80\uD305 \uD56D\uBAA9 \uB4F1\uB85D\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") $errDet
    }
   }
  } elseif ($failedMsgs.Count -gt 0) {
   Invoke-GuiErrorReportPrompt $ui (U "\uBD80\uD2B8\uB85C\uB354 \uC815\uB9AC \uC624\uB958") ($failedMsgs -join "`r`n") ($failedMsgs -join " | ")
  }
  & $ui.RefreshPreSid
 }.GetNewClosure())

 # STEP 1: Individual Disk Toggle
 $btnToggleDisk.Add_Click({
  if ($ui.DgvDisks.SelectedRows.Count -eq 0 -or $null -eq $ui.DgvDisks.SelectedRows[0].Tag) { return }
  $it = $ui.DgvDisks.SelectedRows[0].Tag
  if ($it.IsProtected) { return }
  $mode = if ($it.State -eq "ACTIVE") { "DISABLE" } elseif ($it.State -eq "DISABLED") { "RESTORE" } else { "" }
  if (-not $mode) { return }

  $preview = Get-PartitionPreviewListing $it
  $actLabel = if ($mode -eq "DISABLE") { U "\uBE44\uD65C\uC131\uD654" } else { U "\uC6D0\uC0C1 \uBCF5\uAD6C" }
  $confirmMsg = ("Disk " + $it.DiskNumber + "  " + $it.Model + "`r`n`r`n" + (U "\uD30C\uD2F0\uC158 \uB8E8\uD2B8 \uBBF8\uB9AC\uBCF4\uAE30") + "`r`n" + $preview + "`r`n`r`n" + (U "\uC774 \uB514\uC2A4\uD06C\uC758 \uBD80\uD2B8\uB85C\uB354\uB97C ") + $actLabel + (U "\uD560\uAE4C\uC694?"))
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, $confirmMsg, (U "\uBD80\uD2B8\uB85C\uB354 \uC804\uD658 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $r = Invoke-BootloaderAction $it $mode
  & $ui.AppendLog $r.Message
  if ($r.Success) {
   $body = $r.Message + $(if ($r.Warning) { "`r`n" + $r.Warning } else { "" })
   [System.Windows.Forms.MessageBox]::Show($ui.Form, $body, (U "\uC804\uD658 \uC644\uB8CC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
  } else {
   Invoke-GuiErrorReportPrompt $ui (U "\uBD80\uD2B8\uB85C\uB354 \uC804\uD658 \uC624\uB958") $r.Message $r.Message
  }
  & $ui.RefreshPreSid
 }.GetNewClosure())

 # STEP 1: Explicit IGNORE Bypass
 $btnIgnoreStep1.Add_Click({
  if (Show-GuiIgnoreConfirmDialog $ui.Form) {
   $ui.State.Step1Bypassed = $true
   & $ui.AppendLog (U "\uC0AC\uC6A9\uC790 \uD655\uC778\uC73C\uB85C 1\uB2E8\uACC4 \uACBD\uACE0\uB97C \uAC74\uB108\uB6F0\uACE0 2\uB2E8\uACC4 \uC7A0\uAE08\uC744 \uD574\uC81C\uD588\uC2B5\uB2C8\uB2E4.")
   & $ui.RefreshPreSid
  }
 }.GetNewClosure())

 # STEP 2: Confirmed 1-Time USB Reboot (Rule #3: ALWAYS confirm before reboot!)
 $btnUsbReboot.Add_Click({
  if ($ui.DgvUsb.SelectedRows.Count -eq 0 -or $null -eq $ui.DgvUsb.SelectedRows[0].Tag) { return }
  $rowTag = $ui.DgvUsb.SelectedRows[0].Tag
  if ($rowTag.Kind -ne "NVRAM") { return }
  $target = $rowTag.Entry
  $devStr = if ($target.Device) { $target.Device } else { U "UEFI \uD38C\uC6E8\uC5B4" }
  $cMsg = (U "\uC544\uB798 USB \uD56D\uBAA9\uC73C\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305\uC744 \uC9C4\uD589\uD560\uAE4C\uC694?`r`n\uC774\uBC88 \uC7AC\uBD80\uD305\uC5D0\uB9CC \uC801\uC6A9\uB418\uBA70 \uB2E4\uC74C \uBD80\uD305\uBD80\uD130\uB294 \uC6D0\uB798 Windows\uB85C \uC2DC\uC791\uB429\uB2C8\uB2E4.`r`n`r`n") +
          (U "\uBD80\uD305 \uD56D\uBAA9: ") + $target.Description + "`r`n" +
          (U "\uC77C\uCE58 \uC218\uC900: ") + $target.MatchTag + "`r`n" +
          (U "\uC5F0\uACB0 \uC815\uBCF4: ") + $devStr
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, $cMsg, (U "USB \uC7AC\uBD80\uD305 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $setRes = Invoke-NativeOem "bcdedit.exe" ("/set {fwbootmgr} bootsequence " + $target.Identifier)
  if ($setRes.ExitCode -eq 0) {
   & $ui.AppendLog ((U "1\uD68C\uC131 \uBD80\uD305 \uC21C\uC11C \uC9C0\uC815 \uC644\uB8CC: ") + $target.Description)
   $rb = Invoke-SafeRebootCore "/r /f /t 0"
   if ($rb.Success) { $ui.Form.Close(); return }
   $errDet = "shutdown /r /f /t 0 ExitCode=" + $rb.ExitCode + " " + $rb.Output
   Invoke-GuiErrorReportPrompt $ui (U "\uC7AC\uBD80\uD305 \uC624\uB958") (U "\uC7AC\uBD80\uD305 \uBA85\uB839 \uC2E4\uD589\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") $errDet
  } else {
   $bcdErr = ($setRes.Lines -join " ")
   & $ui.AppendLog ((U "NVRAM \uBD80\uD305 \uC21C\uC11C \uBCC0\uACBD \uC2E4\uD328: ") + $bcdErr)
   $fbMsg = (U "NVRAM \uBD80\uD305 \uC21C\uC11C\uB97C \uBCC0\uACBD\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.`r`n\uB300\uC2E0 Windows \uACE0\uAE09 \uBD80\uD305 \uD654\uBA74\uC73C\uB85C \uC774\uB3D9\uD574 \uC7A5\uCE58 \uC0AC\uC6A9 \uBA54\uB274\uC5D0\uC11C USB\uB97C \uC120\uD0DD\uD560\uAE4C\uC694?")
   $drFb = [System.Windows.Forms.MessageBox]::Show($ui.Form, $fbMsg, (U "\uACE0\uAE09 \uBD80\uD305 \uC804\uD658 \uC548\uB0B4"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
   if ($drFb -eq [System.Windows.Forms.DialogResult]::Yes) {
    $rb2 = Invoke-SafeRebootCore "/r /o /f /t 0"
    if ($rb2.Success) { $ui.Form.Close(); return }
    $errDet2 = "shutdown /r /o /f /t 0 ExitCode=" + $rb2.ExitCode + " " + $rb2.Output
    Invoke-GuiErrorReportPrompt $ui (U "\uC7AC\uBD80\uD305 \uC624\uB958") (U "\uACE0\uAE09 \uBD80\uD305 \uC7AC\uBD80\uD305\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") $errDet2
   }
  }
 }.GetNewClosure())

 # STEP 2: Windows Advanced Boot
 $btnAdvBoot.Add_Click({
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "Windows \uACE0\uAE09 \uBD80\uD305 \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?`r`n\uD30C\uB780 \uD654\uBA74\uC774 \uB098\uD0C0\uB098\uBA74 \uC7A5\uCE58 \uC0AC\uC6A9\uC744 \uC120\uD0DD\uD574 WinPE USB\uB85C \uBD80\uD305\uD574 \uC8FC\uC138\uC694."), (U "\uACE0\uAE09 \uBD80\uD305 \uC774\uB3D9 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $rb = Invoke-SafeRebootCore "/r /o /f /t 0"
  if ($rb.Success) { $ui.Form.Close(); return }
  Invoke-GuiErrorReportPrompt $ui (U "\uC7AC\uBD80\uD305 \uC624\uB958") (U "\uACE0\uAE09 \uBD80\uD305 \uC7AC\uBD80\uD305\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") ("shutdown /r /o ExitCode=" + $rb.ExitCode + " " + $rb.Output)
 }.GetNewClosure())

 # STEP 2: BIOS Setup Entry
 $btnBiosBoot.Add_Click({
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, ((U "UEFI BIOS \uC124\uC815 \uD654\uBA74\uC73C\uB85C \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?`r`n`r`n") + $ui.State.SysInfo.BiosHint), (U "BIOS \uC124\uC815 \uC5F4\uAE30 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $rb = Invoke-SafeRebootCore "/r /fw /f /t 0"
  if ($rb.Success) { $ui.Form.Close(); return }
  Invoke-GuiErrorReportPrompt $ui (U "\uC7AC\uBD80\uD305 \uC624\uB958") (U "BIOS \uC124\uC815 \uC7AC\uBD80\uD305\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") ("shutdown /r /fw ExitCode=" + $rb.ExitCode + " " + $rb.Output)
 }.GetNewClosure())

 # TAB 2: Async Non-Blocking Spooler Reset (Runspace + Timer -> UI never freezes!)
 $asyncPollTimer.Add_Tick({
  $st = $ui.State
  if ($st.AsyncQueue) {
   while ($st.AsyncQueue.Count -gt 0) {
    $ln = [string]$st.AsyncQueue.Dequeue()
    & $ui.AppendLog $ln
    & $ui.SetStatus $ln "Busy"
   }
  }
  if (-not $st.AsyncHandle -or -not $st.AsyncHandle.IsCompleted) { return }
  $ui.AsyncPollTimer.Stop()
  $res = $null
  $runErr = ""
  try {
   $out = $st.AsyncPs.EndInvoke($st.AsyncHandle)
   if ($out -and $out.Count -gt 0) { $res = $out[$out.Count - 1] }
   if (-not $res -and $st.AsyncPs.Streams.Error.Count -gt 0) {
    $runErr = $st.AsyncPs.Streams.Error[0].ToString()
   }
  } catch {
   $runErr = $_.Exception.Message
  } finally {
   if ($st.AsyncPs) { try { $st.AsyncPs.Dispose() } catch {} }
   if ($st.AsyncRs) { try { $st.AsyncRs.Dispose() } catch {} }
   $st.AsyncPs = $null; $st.AsyncRs = $null; $st.AsyncHandle = $null; $st.AsyncQueue = $null
   $st.IsBusy = $false
  }

  if ($runErr -or -not $res) {
   $eMsg = if ($runErr) { $runErr } else { U "\uC2A4\uD480\uB7EC \uCD08\uAE30\uD654 \uACB0\uACFC\uB97C \uBC1B\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4." }
   & $ui.AppendLog ((U "\uC2A4\uD480\uB7EC \uCD08\uAE30\uD654 \uC624\uB958: ") + $eMsg)
   & $ui.SetStatus (U "\uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4") "Error"
   & $ui.RefreshPostSid
   Invoke-GuiErrorReportPrompt $ui (U "\uC2A4\uD480\uB7EC \uCD08\uAE30\uD654 \uC624\uB958") (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654 \uC911 \uC624\uB958\uAC00 \uBC1C\uC0DD\uD588\uC2B5\uB2C8\uB2E4.") $eMsg
   return
  }

  if (-not $res.ServiceMissing) {
   $qRes = $res.QueueResult
   & $ui.AppendLog ((U "\uC815\uB9AC \uACB0\uACFC \u00B7 \uB300\uAE30\uC5F4 \uC0AD\uC81C ") + $qRes.DeletedCount + (U "\uAC74, \uC794\uC874 ") + $qRes.RemainingCount + (U "\uAC74, \uC2DC\uC791 \uC720\uD615 ") + $res.StartMode)
   if ($res.IsRunning) {
    & $ui.AppendLog (U "\uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uAC00 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4. \uBA54\uC778 PC\uC640 \uD074\uB77C\uC774\uC5B8\uD2B8 PC \uBAA8\uB450\uC5D0\uC11C \uC2E4\uD589\uD55C \uB4A4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB97C \uD655\uC778\uD574 \uC8FC\uC138\uC694.")
    & $ui.RefreshPostSid
    & $ui.SetStatus (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uAC00 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4") "OK"
    [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uAC00 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4.`r`n\uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uD074\uB77C\uC774\uC5B8\uD2B8 PC \uBAA8\uB450\uC5D0\uC11C \uD55C \uBC88\uC529 \uC2E4\uD589\uD55C \uB4A4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB97C \uD655\uC778\uD574 \uC8FC\uC138\uC694."), (U "\uCD08\uAE30\uD654 \uC644\uB8CC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
   } else {
    & $ui.RefreshPostSid
    & $ui.SetStatus (U "\uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4 \uC7AC\uC2DC\uC791\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4") "Error"
    Invoke-GuiErrorReportPrompt $ui (U "\uC2A4\uD480\uB7EC \uC7AC\uC2DC\uC791 \uC624\uB958") (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4\uB97C \uB2E4\uC2DC \uC2DC\uC791\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.") ([string]$res.StartError)
   }
  } else {
   & $ui.RefreshPostSid
   & $ui.SetStatus (U "\uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4\uB97C \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4") "Error"
   Invoke-GuiErrorReportPrompt $ui (U "\uC11C\uBE44\uC2A4 \uC5C6\uC74C") ([string]$res.StartError) ([string]$res.StartError)
  }
 }.GetNewClosure())

 $btnSpoolerReset.Add_Click({
  if ($ui.State.IsBusy) { return }
  $dr = [System.Windows.Forms.MessageBox]::Show($ui.Form, (U "\uC778\uC1C4 \uB300\uAE30\uC5F4\uC744 \uBE44\uC6B0\uACE0 \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uC11C\uBE44\uC2A4\uB97C \uC7AC\uC2DC\uC791\uD560\uAE4C\uC694?`r`n\uAE30\uC874 \uD504\uB9B0\uD130, \uB4DC\uB77C\uC774\uBC84, \uACF5\uC720 \uC124\uC815\uC740 \uC0AD\uC81C\uB418\uC9C0 \uC54A\uC2B5\uB2C8\uB2E4."), (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }

  $ui.State.IsBusy = $true
  & $ui.SyncButtonStates
  & $ui.SetLogExpanded $true
  & $ui.AppendLog (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uB97C \uC2DC\uC791\uD569\uB2C8\uB2E4.")
  & $ui.SetStatus (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC\uB97C \uCD08\uAE30\uD654\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4...") "Busy"

  try {
   $q = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
   $fnNames = @("U", "Get-SpoolerQueueDirectory", "Clear-SpoolerQueueDirectory", "Invoke-SpoolerResetCore")
   $defs = ($fnNames | ForEach-Object { "function $_ {`r`n" + (Get-Command $_ -CommandType Function).Definition + "`r`n}" }) -join "`r`n"
   $workerScript = "param(`$q)`r`n`$ErrorActionPreference = 'Continue'`r`n" + $defs + "`r`nInvoke-SpoolerResetCore ({ param(`$m) `$q.Enqueue([string]`$m) }.GetNewClosure())"
   $rs = [runspacefactory]::CreateRunspace()
   $rs.Open()
   $ps = [powershell]::Create()
   $ps.Runspace = $rs
   [void]$ps.AddScript($workerScript).AddArgument($q)
   $ui.State.AsyncRs = $rs
   $ui.State.AsyncPs = $ps
   $ui.State.AsyncQueue = $q
   $ui.State.AsyncHandle = $ps.BeginInvoke()
   $ui.AsyncPollTimer.Start()
  } catch {
   # Defensive synchronous fallback if Runspace creation fails
   try {
    $logRef = $ui.AppendLog
    $res = Invoke-SpoolerResetCore { param($m) & $logRef $m }.GetNewClosure()
    $ui.State.IsBusy = $false
    & $ui.RefreshPostSid
    if ($res.IsRunning) {
     & $ui.SetStatus (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uCD08\uAE30\uD654\uAC00 \uC644\uB8CC\uB418\uC5C8\uC2B5\uB2C8\uB2E4") "OK"
    } else {
     Invoke-GuiErrorReportPrompt $ui (U "\uC2A4\uD480\uB7EC \uCD08\uAE30\uD654 \uC624\uB958") ([string]$res.StartError) ([string]$res.StartError)
    }
   } finally {
    $ui.State.IsBusy = $false
    & $ui.SyncButtonStates
   }
  }
 }.GetNewClosure())

 # Safe FormClosing / FormClosed cleanup (NEVER blocks or throws on X button!)
 $form.Add_FormClosing({
  param($sender, $e)
  $ctx = if ($sender -and $sender.Tag) { $sender.Tag } else { $ui }
  if ($ctx -and $ctx.CopyResetTimer) { try { $ctx.CopyResetTimer.Stop() } catch {} }
  if ($ctx -and $ctx.AsyncPollTimer) { try { $ctx.AsyncPollTimer.Stop() } catch {} }
  if ($ctx -and $ctx.State -and $ctx.State.AsyncPs) {
   try { $ctx.State.AsyncPs.Stop() } catch {}
   try { $ctx.State.AsyncPs.Dispose() } catch {}
   $ctx.State.AsyncPs = $null
  }
  if ($ctx -and $ctx.State -and $ctx.State.AsyncRs) {
   try { $ctx.State.AsyncRs.Dispose() } catch {}
   $ctx.State.AsyncRs = $null
  }
 }.GetNewClosure())

 $form.Add_FormClosed({
  param($sender, $e)
  $ctx = if ($sender -and $sender.Tag) { $sender.Tag } else { $ui }
  if ($ctx -and $ctx.Disposables) {
   foreach ($obj in $ctx.Disposables) {
    if ($null -ne $obj) { try { $obj.Dispose() } catch {} }
   }
  }
 }.GetNewClosure())

 # Register parent-routed tooltips for all disabled buttons across the entire form
 Register-AsanDisabledTooltipTree $form $ui

 if ($autoPopulate) {
  & $ui.RefreshAll
  # Smart initial tab selection: if Spooler is broken/stopped on a clean Pre-SID PC, focus Tab 2
  $ps = $ui.State.PostStatus
  $efi = $ui.State.EfiRep
  if ($ps -and ($ps.SpoolerStatus -ne "Running" -or $ps.PrinterQueryError) -and (-not $efi -or -not $efi.HasBlockingRisk)) {
   $tabControl.SelectedIndex = 1
   & $ui.SetStatus (U "\uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uBCF5\uAD6C\uAC00 \uD544\uC694\uD574 \uC0AC\uD6C4 \uBCF5\uAD6C \uD0ED\uC744 \uBA3C\uC800 \uC5F4\uC5C8\uC2B5\uB2C8\uB2E4") "Warn"
  }
 }

 return [PSCustomObject]@{
  Form             = $form
  TabControl       = $tabControl
  DiskGrid         = $dgvDisks
  UsbGrid          = $dgvUsb
  PrinterGrid      = $dgvPrinters
  BtnTopRefresh    = $btnTopRefresh
  BtnRescanUsb     = $btnRescanUsb
  BtnPostRefresh   = $btnPostRefresh
  BtnToggleLog     = $btnToggleLog
  BtnStep1Fold     = $btnStep1Fold
  BtnOneStop       = $btnOneStop
  BtnToggleDisk    = $btnToggleDisk
  BtnUsbReboot     = $btnUsbReboot
  BtnAdvBoot       = $btnAdvBoot
  BtnBiosBoot      = $btnBiosBoot
  BtnSpoolerReset  = $btnSpoolerReset
  CritBanner       = $critBanner
  State            = $state
  RefreshAll       = $ui.RefreshAll
  UiContext        = $ui
 }
}

# Dedicated WinPE (X:) Emergency Mode GUI using Asan Desktop UI design system
function Show-WinPeEmergencyGui {
 Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
 Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
 [System.Windows.Forms.Application]::EnableVisualStyles()
 $theme = Get-AsanTheme
 $fonts = New-AsanFontSet
 $symbolBmp = New-SidToolSymbolBitmap 40
 $appIconBmp = New-SidToolSymbolBitmap 64
 $appIcon = New-AsanIconFromBitmap $appIconBmp
 $appIconBmp.Dispose()

 $form = New-Object System.Windows.Forms.Form
 $form.Text = (U "WinPE \uBE44\uC0C1 \uBCF5\uAD6C \u00B7 \uB0B4\uC7A5 \uB514\uC2A4\uD06C \uBD80\uD2B8\uB85C\uB354 \uAD00\uB9AC") + " v" + $script:ToolVersion
 $form.Size = New-Object System.Drawing.Size(920, 520)
 $form.MinimumSize = New-Object System.Drawing.Size(780, 440)
 $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
 $form.BackColor = $theme.CanvasBg
 $form.Font = $fonts.Base
 $form.Icon = $appIcon

 $toolTip = New-Object System.Windows.Forms.ToolTip
 $toolTip.ShowAlways = $true

 $peUi = @{
  Form = $form; Theme = $theme; Fonts = $fonts; ToolTip = $toolTip
  ButtonStyles = @{}; DisabledReasons = @{}; LastDisabledBtn = $null; LastDisabledHost = $null; State = $null
  Disposables = @($toolTip, $symbolBmp, $appIcon) + @($fonts.Values)
 }
 $form.Tag = $peUi

 $hdr = New-Object System.Windows.Forms.Panel
 $hdr.Dock = [System.Windows.Forms.DockStyle]::Top
 $hdr.Height = 56
 $hdr.BackColor = $theme.HeaderBg
 $hdr.Padding = New-Object System.Windows.Forms.Padding(16, 8, 16, 8)
 $pic = New-Object System.Windows.Forms.PictureBox
 $pic.Image = $symbolBmp; $pic.Size = New-Object System.Drawing.Size(40, 40); $pic.Location = New-Object System.Drawing.Point(16, 8)
 $lblT = New-Object System.Windows.Forms.Label
 $lblT.Text = U "WinPE \uBE44\uC0C1 \uBCF5\uAD6C \uBAA8\uB4DC"
 $lblT.Font = $fonts.Title; $lblT.ForeColor = [System.Drawing.Color]::White; $lblT.AutoSize = $true; $lblT.Location = New-Object System.Drawing.Point(66, 6)
 $lblS = New-Object System.Windows.Forms.Label
 $lblS.Text = U "\uB0B4\uC7A5 \uB514\uC2A4\uD06C\uC758 GPT EFI \uBC0F MBR \uBD80\uD2B8\uB85C\uB354\uB97C \uC548\uC804\uD558\uAC8C \uBE44\uD65C\uC131\uD654\uD558\uAC70\uB098 \uC6D0\uC0C1 \uBCF5\uAD6C\uD569\uB2C8\uB2E4."
 $lblS.Font = $fonts.Subtitle; $lblS.ForeColor = $theme.HeaderSubFg; $lblS.AutoSize = $true; $lblS.Location = New-Object System.Drawing.Point(67, 30)
 $hdr.Controls.Add($pic); $hdr.Controls.Add($lblT); $hdr.Controls.Add($lblS)

 $oLine = New-Object System.Windows.Forms.Panel
 $oLine.Dock = [System.Windows.Forms.DockStyle]::Top
 $oLine.Height = 2
 $oLine.BackColor = $theme.AsanOrangeLine

 $bodyWrap = New-Object System.Windows.Forms.Panel
 $bodyWrap.Dock = [System.Windows.Forms.DockStyle]::Fill
 $bodyWrap.Padding = New-Object System.Windows.Forms.Padding(12)

 $card = New-Object System.Windows.Forms.Panel
 $card.Dock = [System.Windows.Forms.DockStyle]::Fill
 $card.BackColor = $theme.CardBg
 $card.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

 $dgv = New-AsanGrid $theme $fonts
 Add-AsanGridColumn $dgv "Disk"  (U "\uB514\uC2A4\uD06C") 68 $false 64
 Add-AsanGridColumn $dgv "Model" (U "\uBAA8\uB378\uBA85") 220 $false 140
 Add-AsanGridColumn $dgv "Size"  (U "\uC6A9\uB7C9") 78 $false 68
 Add-AsanGridColumn $dgv "Style" (U "\uBC29\uC2DD") 64 $false 54
 Add-AsanGridColumn $dgv "Part"  (U "\uBD80\uD2B8 \uC601\uC5ED") 100 $false 84
 Add-AsanGridColumn $dgv "State" (U "\uC810\uAC80 \uC0C1\uD0DC") 180 $true 150
 $card.Controls.Add($dgv)
 $bodyWrap.Controls.Add($card)

 $bar = New-Object System.Windows.Forms.Panel
 $bar.Dock = [System.Windows.Forms.DockStyle]::Bottom
 $bar.Height = 52
 $bar.BackColor = $theme.CardBg
 $bar.Padding = New-Object System.Windows.Forms.Padding(16, 9, 16, 9)

 $leftStrip = New-Object System.Windows.Forms.FlowLayoutPanel
 $leftStrip.Dock = [System.Windows.Forms.DockStyle]::Left
 $leftStrip.AutoSize = $true
 $leftStrip.WrapContents = $false

 $btnTog = New-AsanButton (U "\uC120\uD0DD \uB514\uC2A4\uD06C \uC804\uD658") 138 34 "Primary" $peUi $false
 $btnTog.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $btnRef = New-AsanButton (U "\uC0C8\uB85C\uACE0\uCE68") 92 34 "Secondary" $peUi $false
 $leftStrip.Controls.Add($btnTog)
 $leftStrip.Controls.Add($btnRef)

 $rightStrip = New-RightFlowStrip 0 0 0
 $btnClose = New-AsanButton (U "\uB2EB\uAE30") 88 34 "Secondary" $peUi $false
 $btnPeReboot = New-AsanButton (U "PC \uC7AC\uBD80\uD305") 108 34 "Orange" $peUi $false
 $btnPeReboot.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
 $rightStrip.Controls.Add($btnClose)
 $rightStrip.Controls.Add($btnPeReboot)

 $bar.Controls.Add($leftStrip)
 $bar.Controls.Add($rightStrip)

 $peUi.Dgv = $dgv
 $peUi.BtnTog = $btnTog

 $peUi.SyncPeBtn = {
  $can = $false
  $reason = U "\uBAA9\uB85D\uC5D0\uC11C \uC804\uD658\uD560 \uB514\uC2A4\uD06C\uB97C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694."
  if ($peUi.Dgv.SelectedRows.Count -gt 0 -and $null -ne $peUi.Dgv.SelectedRows[0].Tag) {
   $it = $peUi.Dgv.SelectedRows[0].Tag
   if ($it.State -in @("ACTIVE","DISABLED")) { $can = $true }
   else { $reason = U "\uC120\uD0DD\uD55C \uB514\uC2A4\uD06C\uC5D0 \uC804\uD658 \uAC00\uB2A5\uD55C \uBD80\uD2B8\uB85C\uB354\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4." }
  }
  Set-AsanButtonState $peUi.BtnTog $can $reason $peUi "Primary"
 }.GetNewClosure()

 $peUi.LoadPe = {
  $rep = Get-InternalBootloaderReport $true
  $peUi.Dgv.Rows.Clear()
  foreach ($it in $rep.Items) {
   $pStr = if ($it.TargetPart -gt 0) { $it.BootType + " #" + $it.TargetPart } else { "-" }
   $guiSt = Format-BootloaderGuiStatus $it
   $rIdx = $peUi.Dgv.Rows.Add(("Disk " + $it.DiskNumber), [string]$it.Model, ([string]$it.SizeGB + " GB"), [string]$it.PartitionStyle, $pStr, $guiSt.Text)
   $row = $peUi.Dgv.Rows[$rIdx]
   $row.Tag = $it
   Set-AsanCellSemanticStyle $row.Cells[5] $guiSt.Kind $peUi.Theme $peUi.Fonts ($guiSt.Kind -ne "Neutral")
   foreach ($c in $row.Cells) { $c.ToolTipText = $guiSt.Tip }
  }
  & $peUi.SyncPeBtn
 }.GetNewClosure()

 $dgv.Add_SelectionChanged({ & $peUi.SyncPeBtn }.GetNewClosure())
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
  if ($peUi.Dgv.SelectedRows.Count -eq 0 -or $null -eq $peUi.Dgv.SelectedRows[0].Tag) { return }
  $it = $peUi.Dgv.SelectedRows[0].Tag
  $mode = if ($it.State -eq "ACTIVE") { "DISABLE" } elseif ($it.State -eq "DISABLED") { "RESTORE" } else { "" }
  if (-not $mode) { return }
  $preview = Get-PartitionPreviewListing $it
  $actLbl = if ($mode -eq "DISABLE") { U "\uBE44\uD65C\uC131\uD654" } else { U "\uC6D0\uC0C1 \uBCF5\uAD6C" }
  $cMsg = ("Disk " + $it.DiskNumber + "  " + $it.Model + "`r`n`r`n" + (U "\uD30C\uD2F0\uC158 \uB8E8\uD2B8 \uBBF8\uB9AC\uBCF4\uAE30") + "`r`n" + $preview + "`r`n`r`n" + $actLbl + (U "\uB97C \uC9C4\uD589\uD560\uAE4C\uC694?"))
  $dr = [System.Windows.Forms.MessageBox]::Show($peUi.Form, $cMsg, (U "\uBD80\uD2B8\uB85C\uB354 \uC804\uD658 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $r = Invoke-BootloaderAction $it $mode
  [System.Windows.Forms.MessageBox]::Show($peUi.Form, $r.Message, (U "\uC804\uD658 \uACB0\uACFC"), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
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

 $form.Controls.Add($bodyWrap)
 $form.Controls.Add($bar)
 $form.Controls.Add($oLine)
 $form.Controls.Add($hdr)
 Register-AsanDisabledTooltipTree $form $peUi
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
