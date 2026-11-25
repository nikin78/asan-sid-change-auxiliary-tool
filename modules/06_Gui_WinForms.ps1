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
