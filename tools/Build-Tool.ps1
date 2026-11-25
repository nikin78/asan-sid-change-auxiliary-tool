# ==============================================================================
# Build & Verification Script for SID_Change_Aux_Tool.bat
# Combines modules/ into a single 100% pure-ASCII CRLF hybrid .bat deliverable
# and runs strict static/syntax/safety checks.
# ==============================================================================
[CmdletBinding()]
param(
    [string]$OutputName = "SID_Change_Aux_Tool.bat",
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$modulesDir = Join-Path $repoRoot "modules"
$outputPath = Join-Path $repoRoot $OutputName

$moduleOrder = @(
    "01_Bootstrap_And_Helpers.bat",
    "02_Bootloader_Conflict_Module.ps1",
    "03_Vendor_Bios_Diagnostics.ps1",
    "04_Usb_Matching_And_Reboot.ps1",
    "05_PostSid_Spooler_Module.ps1",
    "06_Main_Entry.ps1"
)

function Test-PureAsciiBytes {
    param([byte[]]$Bytes, [string]$Label)
    $violations = @()
    $line = 1
    $col = 1
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        $b = $Bytes[$i]
        if ($b -gt 127) {
            $violations += "${Label}: line $line col $col has non-ASCII byte 0x$($b.ToString('X2'))"
            if ($violations.Count -ge 10) { break }
        }
        if ($b -eq 10) {
            $line++
            $col = 1
        } else {
            $col++
        }
    }
    return $violations
}

function Test-StrictCrlf {
    param([byte[]]$Bytes, [string]$Label)
    $violations = @()
    $line = 1
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        $b = $Bytes[$i]
        if ($b -eq 10) {
            if ($i -eq 0 -or $Bytes[$i - 1] -ne 13) {
                $violations += "${Label}: bare LF at line $line (offset $i)"
                if ($violations.Count -ge 10) { break }
            }
            $line++
        } elseif ($b -eq 13) {
            if (($i + 1) -ge $Bytes.Length -or $Bytes[$i + 1] -ne 10) {
                $violations += "${Label}: bare CR at line $line (offset $i)"
                if ($violations.Count -ge 10) { break }
            }
        }
    }
    return $violations
}

function Normalize-ToCrlf {
    param([string]$Text)
    $norm = $Text -replace "`r`n", "`n"
    $norm = $norm -replace "`r", "`n"
    $norm = $norm.TrimEnd("`n")
    return ($norm -replace "`n", "`r`n")
}

$allErrors = @()

if (-not $VerifyOnly) {
    $chunks = @()
    foreach ($modName in $moduleOrder) {
        $modPath = Join-Path $modulesDir $modName
        if (-not (Test-Path $modPath)) {
            throw "Missing required module: $modPath"
        }
        $rawBytes = [System.IO.File]::ReadAllBytes($modPath)
        if ($rawBytes.Length -ge 3 -and $rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) {
            $allErrors += "${modName}: UTF-8 BOM detected (must be pure ASCII without BOM)"
        }
        $allErrors += Test-PureAsciiBytes -Bytes $rawBytes -Label $modName

        $rawText = [System.Text.Encoding]::ASCII.GetString($rawBytes)
        $chunks += (Normalize-ToCrlf -Text $rawText)
    }

    $finalText = ($chunks -join "`r`n") + "`r`n"
    $asciiEnc = New-Object System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllText($outputPath, $finalText, $asciiEnc)
    Write-Host "[BUILD] Generated $outputPath ($($finalText.Length) chars)" -ForegroundColor Cyan
}

if (-not (Test-Path $outputPath)) {
    throw "Target file not found: $outputPath"
}

# 1. Byte-level pure ASCII & no BOM check
$outBytes = [System.IO.File]::ReadAllBytes($outputPath)
if ($outBytes.Length -ge 3 -and $outBytes[0] -eq 0xEF -and $outBytes[1] -eq 0xBB -and $outBytes[2] -eq 0xBF) {
    $allErrors += "${OutputName}: UTF-8 BOM detected"
}
$asciiErrs = Test-PureAsciiBytes -Bytes $outBytes -Label $OutputName
$allErrors += $asciiErrs

# 2. Strict CRLF line ending check
$crlfErrs = Test-StrictCrlf -Bytes $outBytes -Label $OutputName
$allErrors += $crlfErrs

# 3. Polyglot Batch Wrapper integrity check
$outText = [System.Text.Encoding]::ASCII.GetString($outBytes)
if (-not $outText.StartsWith("<# :`r`n@echo off`r`n")) {
    $allErrors += "${OutputName}: Missing polyglot header '<# :`r`n@echo off'"
}
if ($outText -notmatch 'set "SELF_PATH=%~f0"') {
    $allErrors += "${OutputName}: Missing SELF_PATH=%~f0 wrapper line"
}
if ($outText -notmatch 'cd /d "%SystemRoot%\\System32"') {
    $allErrors += "${OutputName}: Missing System32 working directory lock"
}
if ($outText -notmatch 'net session >nul 2>&1') {
    $allErrors += "${OutputName}: Missing UAC admin check"
}
if ($outText -notmatch '(?m)^#>\r?$') {
    $allErrors += "${OutputName}: Missing closing '#>' comment marker for batch header"
}

# 4. PowerShell AST Syntax Check
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($outText, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors -and $parseErrors.Count -gt 0) {
    foreach ($pe in $parseErrors) {
        $allErrors += "${OutputName} PS syntax error at line $($pe.Extent.StartLineNumber) col $($pe.Extent.StartColumnNumber): $($pe.Message)"
    }
}

# 5. Unicode escape check inside U "..." string literals
$uLiterals = [regex]::Matches($outText, '\bU\s+"([^"]+)"')
foreach ($um in $uLiterals) {
    $inner = $um.Groups[1].Value
    if ($inner -match '\\u(?![0-9a-fA-F]{4})') {
        $lineNum = ($outText.Substring(0, $um.Index) -split "`r`n").Count
        $allErrors += "${OutputName}: Malformed \u escape inside U(...) at line $lineNum"
    }
}

# 6. Safety rule checks (HANDOVER.md rule #4)
if ($outText -match '(?i)\bdelete\s+partition\b') {
    $allErrors += "${OutputName}: Forbidden destructive command 'delete partition' detected!"
}
if ($outText -match '(?i)\bformat\s+(fs=|quick|[a-z]:)') {
    $allErrors += "${OutputName}: Forbidden destructive command 'format' detected!"
}

$lineCount = ($outText -split "`r`n").Count
if ($allErrors.Count -gt 0) {
    Write-Host "`n[VERIFY FAILED] $($allErrors.Count) error(s) found:" -ForegroundColor Red
    foreach ($e in $allErrors) {
        Write-Host "  - $e" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "[VERIFY OK] ${OutputName}: $($outBytes.Length) bytes, $lineCount lines | Pure ASCII | Strict CRLF | PS AST OK | Safety Rules OK" -ForegroundColor Green
    exit 0
}
