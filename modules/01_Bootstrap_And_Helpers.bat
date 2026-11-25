<# :
@echo off
set "SELF_PATH=%~f0"
cd /d "%SystemRoot%\System32"

if /i "%SystemDrive%"=="X:" goto :RUN_ELEVATED
net session >nul 2>&1
if %errorlevel% equ 0 goto :RUN_ELEVATED
fltmc >nul 2>&1
if %errorlevel% equ 0 goto :RUN_ELEVATED

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:SELF_PATH;$staged=$null;try{$isNet=$p.StartsWith('\\');if(-not $isNet){try{$rt=[IO.Path]::GetPathRoot($p);if($rt -and ([IO.DriveInfo]$rt).DriveType -eq 'Network'){$isNet=$true}}catch{}};$target=$p;if($isNet){$bytes=[IO.File]::ReadAllBytes($p);$dirs=@($env:TEMP,(Join-Path $env:LOCALAPPDATA 'Temp'),(Join-Path $env:PUBLIC 'Documents'))|Where-Object{$_ -and (Test-Path -LiteralPath $_)};foreach($d in $dirs){try{$rt2=[IO.Path]::GetPathRoot($d);if($rt2 -and ([IO.DriveInfo]$rt2).DriveType -eq 'Network'){continue};$cand=Join-Path $d ('SID_Aux_Stage_'+[guid]::NewGuid().ToString('N')+'.tmp');[IO.File]::WriteAllBytes($cand,$bytes);$staged=$cand;break}catch{}};if(-not $staged){throw 'Cannot stage script from network share to a local temp folder.'};$target=$staged};$q=[string][char]39;$eT=$target.Replace($q,$q+$q);$eO=$p.Replace($q,$q+$q);$stFlag=if($staged){'1'}else{'0'};$del=if($staged){'Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue'}else{''};$run='$p='+$q+$eT+$q+';$env:SELF_PATH='+$q+$eO+$q+';$env:SID_TOOL_STAGED='+$q+$stFlag+$q+';Set-Location (Join-Path $env:SystemRoot '+$q+'System32'+$q+');try{try{$c=[IO.File]::ReadAllText($p,[Text.Encoding]::ASCII)}finally{'+$del+'};Invoke-Expression $c}catch{Write-Host ('+$q+'[FATAL] '+$q+'+$_.Exception.Message) -ForegroundColor Red;Read-Host '+$q+'Press Enter to exit'+$q+'|Out-Null}';$b64=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($run));$psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$b64) -Verb RunAs}catch{if($staged){Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue};$ex=$_.Exception;$w32=if($ex -is [System.ComponentModel.Win32Exception]){$ex}elseif($ex.InnerException -is [System.ComponentModel.Win32Exception]){$ex.InnerException}else{$null};if($w32 -and $w32.NativeErrorCode -eq 1223){exit 0};Write-Host ('[UAC/LAUNCH ERROR] '+$ex.Message) -ForegroundColor Red;Read-Host 'Press Enter to exit'|Out-Null;exit 1}"
exit /b

:RUN_ELEVATED
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "try{$c=[System.IO.File]::ReadAllText($env:SELF_PATH,[System.Text.Encoding]::ASCII);Invoke-Expression $c}catch{Write-Host ('[FATAL] '+$_.Exception.Message) -ForegroundColor Red;Read-Host 'Press Enter to exit'|Out-Null;exit 1}"
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
$script:ToolVersion = "2.0"
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

# Safe reboot wrapper: checks exit code so reboot errors are never hidden
function Invoke-SafeReboot([string]$shutdownArgs, [string]$targetLabel = "") {
 $shExe = Join-Path $env:SystemRoot "System32\shutdown.exe"
 $res = Invoke-NativeOem $shExe $shutdownArgs
 if ($res.ExitCode -eq 0) {
  exit 0
 }
 $lbl = if ($targetLabel) { " (" + $targetLabel + ")" } else { "" }
 Write-Host ("`n [" + (U "\uC624\uB958") + "] " + (U "\uC7AC\uBD80\uD305 \uBA85\uB839 \uC2E4\uD589 \uC2E4\uD328") + $lbl + " (ExitCode=" + $res.ExitCode + ")") -ForegroundColor Red
 $detail = ($res.Lines | Where-Object { $_ -and $_.Trim() -ne "" }) -join " "
 if ($detail) { Write-Host (" - " + $detail) -ForegroundColor Yellow }
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
 return $false
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
 if (Test-StorageCmdletsAvailable) {
  Get-Disk | Format-Table Number, FriendlyName, BusType, PartitionStyle, OperationalStatus, IsBoot, IsSystem, IsRemovable, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
  Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, IsActive, GptType, MbrType, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
 } else {
  Write-Host (U "Storage \uBAA8\uB4C8(Get-Disk) \uBBF8\uC9C0\uC6D0 \uD658\uACBD - diskpart \uC9C4\uB2E8\uC73C\uB85C \uB300\uCCB4\uD569\uB2C8\uB2E4.") -ForegroundColor Yellow
  $dpRes = Invoke-NativeOem "diskpart.exe" "" "list disk`r`nlist volume`r`nexit`r`n"
  $dpRes.Lines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
 }
 Write-Host "==================================================================" -ForegroundColor DarkCyan
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}
