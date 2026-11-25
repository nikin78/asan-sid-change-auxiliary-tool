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

function Invoke-SpoolerReset {
 Write-Host "`n==================================================================" -ForegroundColor Cyan
 Write-Host (U " [\uC9C4\uD589] \uD504\uB9B0\uD130 \uC2A4\uD480\uB7EC \uB9AC\uC14B\uC744 \uC2DC\uC791\uD569\uB2C8\uB2E4...") -ForegroundColor Cyan
 Write-Host "==================================================================" -ForegroundColor Cyan

 # 1. Stop dependent services and Spooler
 Write-Host (U " 1/4. Spooler \uC11C\uBE44\uC2A4 \uC911\uC9C0 \uC911...") -ForegroundColor White
 $runningDeps = @()
 $stopMode = "FAILED"
 try {
  $deps = @(Get-Service -Name "Spooler" -DependentServices -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Running" })
  foreach ($d in $deps) {
   $runningDeps += $d.Name
   Stop-Service -Name $d.Name -Force -ErrorAction SilentlyContinue
  }
 } catch {}

 $sp = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
 if (-not $sp) {
  Write-Host (U " [\uC624\uB958] \uC774 PC\uC5D0\uC11C Spooler \uC11C\uBE44\uC2A4\uB97C \uCC3E\uC744 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.") -ForegroundColor Red
  Read-Host (U "\uACC4\uC18D\uD558\uB824\uBA74 Enter\uB97C \uB204\uB974\uC138\uC694") | Out-Null
  return
 }
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
   Write-Host (U "      \uC911\uC9C0 \uD0C0\uC784\uC544\uC6C3 - spoolsv \uD504\uB85C\uC138\uC2A4\uB97C \uC548\uC804 \uC885\uB8CC\uD569\uB2C8\uB2E4...") -ForegroundColor Yellow
   Stop-Process -Name "spoolsv" -Force -ErrorAction SilentlyContinue
   for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Milliseconds 500
    $spNow = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue
    if ($spNow -and $spNow.Status -eq "Stopped") { $stopped = $true; break }
   }
   if ($stopped) { $stopMode = "FORCED" }
  }
 }

 # 2. Clear PRINTERS queue directory
 Write-Host (U " 2/4. \uB300\uAE30\uC5F4 \uD3F4\uB354(PRINTERS) \uC815\uB9AC \uC911...") -ForegroundColor White
 $queueDir = Get-SpoolerQueueDirectory
 $qRes = Clear-SpoolerQueueDirectory $queueDir

 # 3. Restore StartType if Disabled
 Write-Host (U " 3/4. Spooler \uC2DC\uC791 \uC720\uD615 \uC810\uAC80 \uC911...") -ForegroundColor White
 $startRestored = $false
 $spCim = Get-CimInstance -ClassName Win32_Service -Filter "Name='Spooler'" -ErrorAction SilentlyContinue
 $curStartMode = if ($spCim -and $spCim.StartMode) { [string]$spCim.StartMode } else { "Unknown" }
 if ($curStartMode -eq "Disabled") {
  try {
   Set-Service -Name "Spooler" -StartupType Automatic -ErrorAction Stop
   $startRestored = $true
   $curStartMode = "Auto"
   Write-Host (U "      \uC2DC\uC791 \uC720\uD615\uC774 Disabled \uC0C1\uD0DC\uC5EC\uC11C Automatic(\uC790\uB3D9)\uC73C\uB85C \uBCF5\uAD6C\uD588\uC2B5\uB2C8\uB2E4.") -ForegroundColor Green
  } catch {}
 }

 # 4. Start Spooler and restart previously running dependent services
 Write-Host (U " 4/4. Spooler \uC11C\uBE44\uC2A4 \uC7AC\uC2DC\uC791 \uC911...") -ForegroundColor White
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

 # Result report
 Write-Host ("`n-------------------- [" + (U "\uC2A4\uD480\uB7EC \uB9AC\uC14B \uACB0\uACFC \uB9AC\uD3EC\uD2B8") + "] --------------------") -ForegroundColor Cyan
 $stopText = switch ($stopMode) {
  "NORMAL" { U "\uC815\uC0C1 \uC911\uC9C0" }
  "FORCED" { U "\uD504\uB85C\uC138\uC2A4 \uAC15\uC81C \uC885\uB8CC \uD6C4 \uC911\uC9C0" }
  default  { U "\uC911\uC9C0 \uC2E4\uD328" }
 }
 Write-Host (" * " + (U "\uC11C\uBE44\uC2A4 \uC911\uC9C0") + "      : " + $stopText) -ForegroundColor $(if ($stopMode -eq "FAILED") { "Red" } else { "Green" })
 Write-Host (" * " + (U "\uB300\uAE30\uC5F4 \uD30C\uC77C \uC815\uB9AC") + " : " + $qRes.DeletedCount + (U "\uAC74 \uC0AD\uC81C \uC644\uB8CC") + " (SPL/SHD: " + $qRes.SplShdDeleted + ") | " + (U "\uC794\uC874 \uD30C\uC77C") + ": " + $qRes.RemainingCount + (U "\uAC74")) -ForegroundColor $(if ($qRes.RemainingCount -gt 0) { "Yellow" } else { "Green" })
 if ($qRes.FailedFiles.Count -gt 0) {
  Write-Host ("   - " + (U "\uC7A0\uAE40/\uC2E4\uD328") + ": " + ($qRes.FailedFiles -join ", ")) -ForegroundColor Yellow
 }
 $startTypeText = if ($startRestored) { U "Automatic\uC73C\uB85C \uBCF5\uAD6C\uB428" } else { $curStartMode + " (" + (U "\uC720\uC9C0") + ")" }
 Write-Host (" * " + (U "\uC2DC\uC791 \uC720\uD615") + "        : " + $startTypeText) -ForegroundColor $(if ($startRestored) { "Green" } else { "Gray" })
 if ($runningDeps.Count -gt 0) {
  Write-Host (" * " + (U "\uC758\uC874 \uC11C\uBE44\uC2A4 \uC911\uC9C0/\uC7AC\uC2DC\uC791") + " : " + $restartedDeps.Count + "/" + $runningDeps.Count + " " + (U "\uC7AC\uC2DC\uC791 \uC644\uB8CC")) -ForegroundColor Gray
 }
 if ($isRunning) {
  Write-Host (" * " + (U "\uCD5C\uC885 \uC11C\uBE44\uC2A4 \uC0C1\uD0DC") + " : " + (U "\uC815\uC0C1 \uC2E4\uD589 \uC911 (Running)")) -ForegroundColor Green
  Write-Host ("`n " + (U "\uC644\uB8CC! \uBA54\uC778 \uD504\uB9B0\uD130 PC\uC640 \uD074\uB77C\uC774\uC5B8\uD2B8 PC \uBAA8\uB450\uC5D0\uC11C \uC2E4\uD589\uD55C \uB4A4 \uD14C\uC2A4\uD2B8 \uC778\uC1C4\uB97C \uD655\uC778\uD558\uC138\uC694.")) -ForegroundColor Cyan
 } else {
  Write-Host (" * " + (U "\uCD5C\uC885 \uC11C\uBE44\uC2A4 \uC0C1\uD0DC") + " : " + (U "\uC2DC\uC791 \uC2E4\uD328") + $(if ($startErr) { " (" + $startErr + ")" } else { "" })) -ForegroundColor Red
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
