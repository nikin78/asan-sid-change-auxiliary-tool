<# :
@echo off
set "SELF_PATH=%~f0"
cd /d "%SystemRoot%\System32"

net session >nul 2>&1
if %errorlevel% neq 0 (
 powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:SELF_PATH -Verb RunAs"
 exit /b
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$code = [System.IO.File]::ReadAllText($env:SELF_PATH); Invoke-Expression $code"
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
$mbrEfiFatTypes = @(11, 12, 14, 239)

# Resolve system OEM encoding (CP949 on Korean Windows, CP437 on EN-US, 65001 if UTF-8 beta)
function Get-SystemOemEncoding {
 try {
  $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
  if ($cp -gt 0) { return [System.Text.Encoding]::GetEncoding($cp) }
 } catch {}
 return [System.Text.Encoding]::Default
}

# Run native console commands (bcdedit, diskpart, bcdboot, netsh) safely with OEM decoding
function Invoke-NativeOem([string]$fileName, [string]$arguments = "", [string]$stdinText = $null) {
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

 $psi = New-Object System.Diagnostics.ProcessStartInfo
 $psi.FileName = $fileName
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
  $proc.WaitForExit()
  $outText = $outTask.Result
  $errText = $errTask.Result
  $exitCode = $proc.ExitCode
 } catch {
  $errText = $_.Exception.Message
  $exitCode = -1
 } finally {
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
