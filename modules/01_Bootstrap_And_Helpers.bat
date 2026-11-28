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
$script:ToolVersion = "__TOOL_VERSION__"
$script:BuildDate = "__BUILD_DATE__"
$script:BuildCommit = "__BUILD_COMMIT__"
$gptEfiGuid = "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
$gptRecoveryGuid = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
$gptMsrGuid = "{e3c9e316-0b5c-4db8-817d-f92df00215ae}"
$mbrEfiFatTypes = @(1, 4, 6, 11, 12, 14, 17, 18, 20, 22, 23, 27, 28, 30, 39, 239)
$script:DosDevQueryType = $null
$script:DosDevInitAttempted = $false

# Resolve actual Windows system OEM encoding (reads HKLM NLS OEMCP first so en-US regional format on KO Windows still decodes CP949!)
function Get-SystemOemEncoding {
 try {
  $nlsOem = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage" -Name "OEMCP" -ErrorAction Stop).OEMCP
  if ($nlsOem -and ([string]$nlsOem) -match "^\d+$" -and [int]$nlsOem -gt 0) {
   return [System.Text.Encoding]::GetEncoding([int]$nlsOem)
  }
 } catch {}
 try {
  $uiCp = [System.Globalization.CultureInfo]::InstalledUICulture.TextInfo.OEMCodePage
  if ($uiCp -gt 0) { return [System.Text.Encoding]::GetEncoding($uiCp) }
 } catch {}
 try {
  $cp = [System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
  if ($cp -gt 0) { return [System.Text.Encoding]::GetEncoding($cp) }
 } catch {}
 return [System.Text.Encoding]::Default
}

# Pure in-memory QueryDosDeviceW helper (zero csc.exe / zero temp DLLs on disk!)
# Maps "E:" or "Volume{GUID}" -> "\Device\HarddiskVolumeX" for exact hidden-ESP NVRAM matching
function Resolve-DosDeviceTarget([string]$dosDeviceName) {
 if ([string]::IsNullOrWhiteSpace($dosDeviceName)) { return "" }
 if (-not $script:DosDevInitAttempted) {
  $script:DosDevInitAttempted = $true
  try {
   $asmName = "SidAuxDosDevMapper_" + [guid]::NewGuid().ToString("N")
   $dynAsm = New-Object System.Reflection.AssemblyName($asmName)
   $asmBld = [AppDomain]::CurrentDomain.DefineDynamicAssembly($dynAsm, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
   $modBld = $asmBld.DefineDynamicModule("Main")
   $typBld = $modBld.DefineType("NativeDosMapper", "Public,Class")
   $mb = $typBld.DefinePInvokeMethod(
    "QueryDosDeviceW",
    "kernel32.dll",
    "Public,Static,PinvokeImpl",
    [System.Reflection.CallingConventions]::Standard,
    [uint32],
    @([string], [System.Text.StringBuilder], [uint32]),
    [System.Runtime.InteropServices.CallingConvention]::Winapi,
    [System.Runtime.InteropServices.CharSet]::Unicode
   )
   $mb.SetImplementationFlags($mb.GetMethodImplementationFlags() -bor [System.Reflection.MethodImplAttributes]::PreserveSig)
   $script:DosDevQueryType = $typBld.CreateType()
  } catch {
   $script:DosDevQueryType = $null
  }
 }
 if (-not $script:DosDevQueryType) { return "" }
 try {
  $clean = $dosDeviceName.Trim().TrimEnd('\')
  if ($clean -match '^\\\\\?\\(.+)$') { $clean = $matches[1] }
  foreach ($cap in @(512, 2048)) {
   $sb = New-Object System.Text.StringBuilder $cap
   $rc = $script:DosDevQueryType::QueryDosDeviceW($clean, $sb, [uint32]$cap)
   if ($rc -gt 0) {
    $val = $sb.ToString().Trim([char]0).Trim()
    if ($val -match '^(\\Device\\[^\x00\r\n]+)') { return $matches[1] }
    return $val
   }
  }
 } catch {}
 return ""
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

# Resolve drive letter and physical disk number hosting SELF_PATH (critical when running from data partition of a multi-partition WinPE USB!)
function Get-SelfHostLocationInfo {
 $p = [string]$env:SELF_PATH
 $drvLtr = ""
 $diskNum = -1
 $busType = ""
 if ($p -and (-not $p.StartsWith("\\")) -and ($env:SID_TOOL_STAGED -ne "1")) {
  try {
   $rt = [System.IO.Path]::GetPathRoot($p)
   if ($rt -and $rt -match "^([A-Za-z]):") {
    $drvLtr = $matches[1].ToUpper()
    if (Test-StorageCmdletsAvailable) {
     $sp = Get-Partition -DriveLetter $drvLtr -ErrorAction SilentlyContinue | Select-Object -First 1
     if ($sp -and $null -ne $sp.DiskNumber) {
      $diskNum = [int]$sp.DiskNumber
      $sd = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($sd) { $busType = [string]$sd.BusType }
     }
    }
   }
  } catch {}
 }
 return [PSCustomObject]@{
  SelfPath = $p
  DriveLetter = $drvLtr
  DiskNumber = $diskNum
  BusType = $busType
 }
}

# Detect execution source label (Local / External or Multi-Partition USB / Shared Folder)
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
    }
    $selfLoc = Get-SelfHostLocationInfo
    $isUsbBus = ($selfLoc.BusType -in @("USB", "SD", "MMC", "1394"))
    if (-not $isUsbBus -and $selfLoc.DiskNumber -ge 0 -and (Get-Command Get-UsbPnpDiskLookup -ErrorAction SilentlyContinue)) {
     try {
      $pm = Get-UsbPnpDiskLookup
      if ($pm.ContainsKey($selfLoc.DiskNumber) -and [bool]$pm[$selfLoc.DiskNumber].IsExternalUsb) { $isUsbBus = $true }
     } catch {}
    }
    if ($di.DriveType -eq "Removable" -or $di.DriveType -eq "CDRom" -or $isUsbBus) {
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

# Mask sensitive credentials/tokens in exported diagnostic reports (handles JSON, escaped JSON, quoted/unquoted key-values, and net use)
function ConvertTo-MaskedDiagnosticText([string]$raw) {
 if ([string]::IsNullOrEmpty($raw)) { return "" }
 $masked = [regex]::Replace($raw, '(?i)(\\?"?(?:password|passwd|pwd|secret|token|apikey|api_key|credential)\\?"?\s*:\s*\\?")([^"\\]*(?:\\.[^"\\]*)*)(\\?")', '$1[REDACTED]$3')
 $masked = [regex]::Replace($masked, '(?i)(\b(?:password|passwd|pwd|secret|token|apikey|api_key|credential)\s*[:=]\s*)(["''])([^"''\r\n]*)\2', '$1$2[REDACTED]$2')
 $masked = [regex]::Replace($masked, '(?i)(\b(?:password|passwd|pwd|secret|token|apikey|api_key|credential)\s*[:=]\s*)([^\r\n\s,;"'']+)', '$1[REDACTED]')
 $masked = [regex]::Replace($masked, '(?i)(\bnet\s+use\s+\S+\s+)([^\s/]+)(\s+/user:\S+)', '$1[REDACTED]$3')
 return $masked
}

function Get-DiskDebugText {
 $sb = New-Object System.Text.StringBuilder
 if (Test-StorageCmdletsAvailable) {
  $t1 = Get-Disk | Format-Table Number, FriendlyName, BusType, PartitionStyle, OperationalStatus, IsBoot, IsSystem, IsRemovable, IsReadOnly, Size -AutoSize | Out-String
  $t2 = Get-Partition | Format-Table DiskNumber, PartitionNumber, DriveLetter, IsActive, GptType, MbrType, Size -AutoSize | Out-String
  [void]$sb.AppendLine($t1.TrimEnd())
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine($t2.TrimEnd())
  try {
   $t3 = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop | Sort-Object Index | Format-Table Index, Model, InterfaceType, MediaType, PNPDeviceID -AutoSize | Out-String
   if ($t3) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($t3.TrimEnd())
   }
  } catch {}
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
 $reId   = "^(identifier|" + (U "\uC2DD\uBCC4\uC790") + ")(?:\s+|\s*:\s*)(\{[^\}]+\})"
 $reDesc = "^(description|" + (U "\uC124\uBA85") + ")(?:\s+|\s*:\s*)(.+)$"
 $rePath = "^(path|" + (U "\uACBD\uB85C") + ")(?:\s+|\s*:\s*)(.+)$"
 $reDev  = "^(device|" + (U "\uC7A5\uCE58") + ")(?:\s+|\s*:\s*)(.+)$"

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
