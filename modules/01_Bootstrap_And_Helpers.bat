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
# USB Boot Helper + Multi-Disk EFI Conflict Guard (100% Pure ASCII)
# ==============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
function U([string]$str) { return [System.Text.RegularExpressions.Regex]::Unescape($str) }

$ErrorActionPreference = "Continue"
$gptEfiGuid = "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
$gptRecoveryGuid = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
$gptMsrGuid = "{e3c9e316-0b5c-4db8-817d-f92df00215ae}"
$mbrEfiFatTypes = @(11, 12, 14, 239)

function Show-BcdDebug([array]$rawLines) {
 Write-Host "`n==================== [bcdedit /enum firmware] ====================" -ForegroundColor DarkCyan
 if ($rawLines -and $rawLines.Count -gt 0) {
  $rawLines | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
 } else {
  Write-Host "(No output from bcdedit /enum firmware)" -ForegroundColor DarkGray
 }
 Write-Host "==================================================================" -ForegroundColor DarkCyan
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}

function Show-DiskDebug {
 Write-Host "`n==================== [Get-Disk / Get-Partition] ================" -ForegroundColor DarkCyan
 Get-Disk | Format-Table Number, FriendlyName, BusType, OperationalStatus, IsBoot, IsSystem, IsRemovable, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
 Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, GptType, MbrType, Size -AutoSize | Out-String | Write-Host -ForegroundColor Gray
 Write-Host "==================================================================" -ForegroundColor DarkCyan
 Read-Host (U "\uBA54\uB274\uB85C \uB3CC\uC544\uAC00\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
}
