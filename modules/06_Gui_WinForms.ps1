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
 $tabs.ItemSize = New-Object System.Drawing.Size(168, 32)

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
 & $addTab (U "1. BIOS \uAD50\uCC28 \uAC80\uC99D") $biosText
 & $addTab (U "2. UEFI NVRAM \uC6D0\uBCF8") $nvramText
 & $addTab (U "3. \uB514\uC2A4\uD06C \uAD6C\uC131") $diskText
 & $addTab (U "4. \uC791\uC5C5 \uB85C\uADF8") $safeLog
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
 Add-AsanGridColumn $dgvUsb "Kind"   (U "\uAD6C\uBD84") 88 $false 82
 Add-AsanGridColumn $dgvUsb "Match"  (U "\uC77C\uCE58 \uC218\uC900") 110 $false 104
 Add-AsanGridColumn $dgvUsb "Name"   (U "USB \uB610\uB294 \uBD80\uD305 \uD56D\uBAA9 \uC774\uB984") 282 $false 180
 Add-AsanGridColumn $dgvUsb "Device" (U "\uC5F0\uACB0 \uC815\uBCF4") 180 $false 140
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
 Add-AsanGridColumn $dgvPrinters "Share"  (U "\uACF5\uC720 \uACBD\uB85C") 216 $false 130
 Add-AsanGridColumn $dgvPrinters "Port"   (U "\uD3EC\uD2B8") 114 $false 90
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
  $hasValidSid = ($null -ne $st.PostStatus -and [string]$st.PostStatus.MachineSid -match '^S-1-5-21-')
  $sidBtnTip = if ($busy) { $busyTip } else { U "\uD604\uC7AC PC\uC758 Machine SID\uB97C \uD655\uC778\uD560 \uC218 \uC5C6\uC5B4 \uBCF5\uC0AC\uD560 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4." }
  $sidBtnVar = if ($ui.BtnCopySid.Text -eq (U "\uBCF5\uC0AC\uB428")) { "SoftTeal" } else { "Secondary" }
  Set-AsanButtonState $ui.BtnCopySid ($hasValidSid -and -not $busy) $sidBtnTip $ui $sidBtnVar

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
  $hasBootableSel = ($null -ne $selUsbTag -and ($selUsbTag.Kind -in @("NVRAM", "DIRECT_EFI_READY", "PHYSICAL_UNVERIFIED")) -and (-not $snap.BiosDiag.IsConfirmedBlocked))
  $canUsbReboot = ($canStep2Act -and $hasBootableSel)

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
  } elseif ($snap -and $snap.BiosDiag -and $snap.BiosDiag.IsConfirmedBlocked) {
   U "BIOS\uC5D0\uC11C USB \uBD80\uD305\uC774 \uCC28\uB2E8\uB418\uC5B4 \uC788\uC2B5\uB2C8\uB2E4. BIOS \uC124\uC815 \uC5F4\uAE30\uB85C \uBA3C\uC800 \uD5C8\uC6A9\uD574 \uC8FC\uC138\uC694."
  } elseif (-not $snap -or $snap.UsbInfo.PhysicalUsbList.Count -eq 0) {
   U "WinPE USB\uB97C PC\uC5D0 \uC5F0\uACB0\uD55C \uB4A4 USB \uB2E4\uC2DC \uCC3E\uAE30\uB97C \uB20C\uB7EC \uC8FC\uC138\uC694."
  } else {
   U "\uC704 \uBAA9\uB85D\uC5D0\uC11C \uBD80\uD305 \uB300\uC0C1 USB \uD589\uC744 \uC120\uD0DD\uD574 \uC8FC\uC138\uC694."
  }

  $recAct = if ($st.PreGuidance) { $st.PreGuidance.RecommendedAction } else { "" }
  $isUnverifiedOnly = ($null -ne $selUsbTag -and $selUsbTag.Kind -eq "PHYSICAL_UNVERIFIED")
  $vUsb  = if ($canUsbReboot -and -not $isUnverifiedOnly -and $recAct -eq "USB_REBOOT" -and -not $canAutoFix) { "Primary" } elseif ($canUsbReboot) { "SoftTeal" } else { "Secondary" }
  $vAdv  = if ($canStep2Act -and ($recAct -eq "ADV_BOOT" -or $isUnverifiedOnly) -and -not $canAutoFix) { "Primary" } else { "Secondary" }
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
   $snap = Get-PreSidStep2Snapshot $st.SysInfo $efiRep.ClassifiedDisks
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
   if (-not $d.BootMode.IsUefi -and $d.BootMode.Mode -eq "Legacy") {
    $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uD574\uB2F9 \uC5C6\uC74C"
    $u.LblPillSec.BackColor = $t.MetaBarBg; $u.LblPillSec.ForeColor = $t.InkMuted
   } else {
    switch ($d.SecureBootState) {
     "On"       { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uCF1C\uC9D0";      $u.LblPillSec.BackColor = $t.AsanOrangeTint; $u.LblPillSec.ForeColor = $t.AsanOrangeText }
     "Conflict" { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uD655\uC778 \uD544\uC694"; $u.LblPillSec.BackColor = $t.DangerRedTint;  $u.LblPillSec.ForeColor = $t.DangerRedDeep }
     "Off"      { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uAEBC\uC9D0";      $u.LblPillSec.BackColor = $t.AsanMint;       $u.LblPillSec.ForeColor = $t.AsanDeep }
     default    { $u.LblPillSec.Text = U "\uBCF4\uC548 \uBD80\uD305 \uBBF8\uD655\uC778";    $u.LblPillSec.BackColor = $t.AsanOrangeTint; $u.LblPillSec.ForeColor = $t.AsanOrangeText }
    }
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
   } elseif ($d.UsbBootConfidence -eq "NvramObserved") {
    $u.LblPillUsb.Text = U "USB \uBD80\uD305 \uBAA9\uB85D \uD655\uC778"
    $u.LblPillUsb.BackColor = $t.InfoTint; $u.LblPillUsb.ForeColor = $t.AsanLight
   } elseif ($d.UsbBootState -eq "SuspectedDisabled") {
    if ($snap.UsbInfo -and $snap.UsbInfo.PSObject.Properties["AnyDirectBootUsb"] -and [bool]$snap.UsbInfo.AnyDirectBootUsb) {
     $u.LblPillUsb.Text = U "USB \uBD80\uD305 BIOS \uD655\uC778"
     $u.LblPillUsb.BackColor = $t.MetaBarBg; $u.LblPillUsb.ForeColor = $t.InkSecondary
    } else {
     $u.LblPillUsb.Text = U "USB \uBD80\uD305 \uBBF8\uB4F1\uB85D"
     $u.LblPillUsb.BackColor = $t.AsanOrangeTint; $u.LblPillUsb.ForeColor = $t.AsanOrangeText
    }
   } else {
    $u.LblPillUsb.Text = U "USB \uBD80\uD305 BIOS \uD655\uC778"
    $u.LblPillUsb.BackColor = $t.MetaBarBg; $u.LblPillUsb.ForeColor = $t.InkSecondary
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

   # 3. Populate Unified USB Selection DataGridView (combines NVRAM matches AND Direct-EFI physical USBs so no connected WinPE USB is ever hidden!)
   $u.DgvUsb.Rows.Clear()
   $matched = @($snap.MatchedEntries)
   $firstBootRowIdx = -1
   $selfPrefRowIdx = -1
   $coveredDiskNums = @{}

   if ($matched.Count -gt 0) {
    for ($i = 0; $i -lt $matched.Count; $i++) {
     $m = $matched[$i]
     $devStr = if ($m.Device) { [string]$m.Device } else { U "UEFI \uD38C\uC6E8\uC5B4" }
     $ownerDisk = $null
     foreach ($pd in $physList) {
      $pdPats = if ($pd.PSObject.Properties["DevicePatterns"] -and $pd.DevicePatterns) {
       (@($pd.DevicePatterns | ForEach-Object { ConvertTo-SafeDeviceRegex ([string]$_) } | Where-Object { $_ }) | Select-Object -Unique) -join "|"
      } else { "" }
      if (($pdPats -and $m.Device -and ([string]$m.Device -match $pdPats)) -or
          ($m.IsExact -and $pd.Model -and ([string]$m.Description -match [regex]::Escape($pd.Model)))) {
       $ownerDisk = $pd
       if ($m.IsExact) { $coveredDiskNums[[int]$pd.DiskNumber] = $true }
       break
      }
     }
     $isSelfMatch = ($null -ne $ownerDisk -and $ownerDisk.PSObject.Properties["IsSelfHostUsb"] -and [bool]$ownerDisk.IsSelfHostUsb)
     $kindBadge = if ($isSelfMatch) { U "\uC2E4\uD589 USB" } else { U "\uBD80\uD305 \uB300\uC0C1" }
     $matchLvl = if ($m.IsExact) { U "\uC815\uD655 \uC77C\uCE58" } else { U "\uBC94\uC6A9 \uD56D\uBAA9" }
     $guideTxt = if ($m.IsExact) { U "\uBC14\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4" } else { U "\uD56D\uBAA9 \uC774\uB984\uC744 \uD655\uC778\uD55C \uB4A4 \uC7AC\uBD80\uD305\uD574 \uC8FC\uC138\uC694" }
     $rIdx = $u.DgvUsb.Rows.Add($kindBadge, $matchLvl, [string]$m.Description, $devStr, $guideTxt)
     $row = $u.DgvUsb.Rows[$rIdx]
     $row.Tag = [PSCustomObject]@{ Kind = "NVRAM"; Entry = $m; Disk = $ownerDisk }
     Set-AsanCellSemanticStyle $row.Cells[0] "OK" $t $f $true
     Set-AsanCellSemanticStyle $row.Cells[1] $(if ($m.IsExact) { "OK" } else { "Warn" }) $t $f $true
     $tip = ([string]$m.MatchTag) + "`r`nGUID: " + $m.Identifier + "`r`n" + (U "\uC7A5\uCE58: ") + $devStr
     foreach ($cell in $row.Cells) { $cell.ToolTipText = $tip }
     if ($firstBootRowIdx -lt 0) { $firstBootRowIdx = $rIdx }
     if ($isSelfMatch -and $selfPrefRowIdx -lt 0) { $selfPrefRowIdx = $rIdx }
    }
   }

   if ($physList.Count -gt 0) {
    foreach ($ud in $physList) {
     if ($coveredDiskNums.ContainsKey([int]$ud.DiskNumber)) { continue }
     $isSelf = ($null -ne $ud.PSObject.Properties["IsSelfHostUsb"] -and [bool]$ud.IsSelfHostUsb)
     $roTag = if ($ud.IsReadOnly) { U " \u00B7 \uC77D\uAE30 \uC804\uC6A9" } else { "" }
     $efiPartHint = if ($ud.PSObject.Properties["BestBootPartDisplay"] -and $ud.BestBootPartDisplay -and $ud.IsEfiReady) { (U " \u00B7 EFI ") + $ud.BestBootPartDisplay } else { "" }
     $drvPrefix = if ($ud.PSObject.Properties["DriveSummary"] -and $ud.DriveSummary) { [string]$ud.DriveSummary + (U " \u00B7 ") } else { "" }
     $devStr = $drvPrefix + $ud.SizeGB + $efiPartHint + $roTag
     $dispName = if ($ud.PSObject.Properties["DisplayLabel"] -and $ud.DisplayLabel) { [string]$ud.DisplayLabel } else { [string]$ud.Model }

     if ($ud.IsEfiReady) {
      $kindBadge = if ($isSelf) { U "\uC2E4\uD589 USB" } else { U "\uBD80\uD305 \uB514\uC2A4\uD06C" }
      $hasResolvedEfi = ($ud.PSObject.Properties["BestEfiRelPath"] -and [bool]$ud.BestEfiRelPath)
      $matchBadge = if ($hasResolvedEfi) { U "EFI \uC9C1\uC811 \uBD80\uD305" } else { U "\uC228\uAE40 EFI \uBD80\uD305" }
      $guideTxt = if ($hasResolvedEfi) {
       U "EFI \uD655\uC778\uB428 \u00B7 \uBC14\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305 \uAC00\uB2A5"
      } else {
       U "\uC228\uAE40 \uBD80\uD305 \uC601\uC5ED \uAC10\uC9C0 \u00B7 1\uD68C\uC131 \uC7AC\uBD80\uD305 \uAC00\uB2A5"
      }
      $rIdx = $u.DgvUsb.Rows.Add($kindBadge, $matchBadge, $dispName, $devStr, $guideTxt)
      $row = $u.DgvUsb.Rows[$rIdx]
      $row.Tag = [PSCustomObject]@{ Kind = "DIRECT_EFI_READY"; Disk = $ud }
      Set-AsanCellSemanticStyle $row.Cells[0] "OK" $t $f $true
      Set-AsanCellSemanticStyle $row.Cells[1] $(if ($hasResolvedEfi) { "OK" } else { "Info" }) $t $f $true
      if ($firstBootRowIdx -lt 0) { $firstBootRowIdx = $rIdx }
      if ($isSelf -and $selfPrefRowIdx -lt 0) { $selfPrefRowIdx = $rIdx }
     } else {
      $kindBadge = if ($isSelf) { U "\uC2E4\uD589 USB" } else { U "\uC678\uC7A5 USB" }
      $guideTxt = U "\uC120\uD0DD \uC2DC \uC228\uAE40 \uD30C\uD2F0\uC158 \uD0D0\uC0C9 \uB610\uB294 \uACE0\uAE09 \uBD80\uD305\uC73C\uB85C \uC5F0\uACB0\uD569\uB2C8\uB2E4"
      $rIdx = $u.DgvUsb.Rows.Add($kindBadge, (U "\uBD80\uD305 \uC2DC\uB3C4 \uAC00\uB2A5"), $dispName, $devStr, $guideTxt)
      $row = $u.DgvUsb.Rows[$rIdx]
      $row.Tag = [PSCustomObject]@{ Kind = "PHYSICAL_UNVERIFIED"; Disk = $ud }
      Set-AsanCellSemanticStyle $row.Cells[1] "Warn" $t $f $true
      if ($firstBootRowIdx -lt 0) { $firstBootRowIdx = $rIdx }
     }
     $efiTip = if ($ud.PSObject.Properties["BestEfiRelPath"] -and $ud.BestEfiRelPath) { "`r`nEFI: " + $ud.BestBootPartDisplay + $ud.BestEfiRelPath } else { "" }
     $tip = "Disk " + $ud.DiskNumber + " | " + $dispName + "`r`n" + (U "\uD30C\uD2F0\uC158: ") + $(if ($ud.Partitions) { $ud.Partitions } else { "-" }) + $efiTip
     foreach ($cell in $row.Cells) { $cell.ToolTipText = $tip }
    }
   }

   if ($u.DgvUsb.Rows.Count -eq 0) {
    $rIdx = $u.DgvUsb.Rows.Add((U "\uC548\uB0B4"), (U "\uBBF8\uC5F0\uACB0"), (U "\uC5F0\uACB0\uB41C WinPE USB\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4"), "-", (U "USB\uB97C \uC5F0\uACB0\uD55C \uB4A4 USB \uB2E4\uC2DC \uCC3E\uAE30\uB97C \uB20C\uB7EC \uC8FC\uC138\uC694"))
    $row = $u.DgvUsb.Rows[$rIdx]
    $row.Tag = $null
    $row.DefaultCellStyle.ForeColor = $t.InkMuted
   }
   $u.DgvUsb.ClearSelection()
   $selTargetIdx = if ($selfPrefRowIdx -ge 0) { $selfPrefRowIdx } else { $firstBootRowIdx }
   if ($selTargetIdx -ge 0) { $u.DgvUsb.Rows[$selTargetIdx].Selected = $true }

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
   if (-not $u.Form.IsDisposed) {
    try { & $u.SyncButtonStates } catch {}
    $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default
   }
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
   if (-not $u.Form.IsDisposed) {
    try { & $u.SyncButtonStates } catch {}
    $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default
   }
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
  if (-not $sidStr -or ($sidStr -notmatch '^S-1-5-21-')) { return }
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
  if ($rowTag.Kind -in @("DIRECT_EFI_READY", "PHYSICAL_UNVERIFIED")) {
   $ud = $rowTag.Disk
   $dispLbl = if ($ud.PSObject.Properties["DisplayLabel"] -and $ud.DisplayLabel) { [string]$ud.DisplayLabel } else { [string]$ud.Model }
   if ($rowTag.Kind -eq "DIRECT_EFI_READY") {
    $efiInfo = if ($ud.PSObject.Properties["BestEfiRelPath"] -and $ud.BestEfiRelPath) {
     $ud.BestBootPartDisplay + $ud.BestEfiRelPath
    } elseif ($ud.PSObject.Properties["BestBootPartDisplay"] -and $ud.BestBootPartDisplay) {
     $ud.BestBootPartDisplay
    } else {
     "UEFI EFI"
    }
    $dMsg = (U "\uC544\uB798 WinPE USB\uC758 EFI \uBD80\uD305 \uC601\uC5ED\uC73C\uB85C 1\uD68C\uC131 \uC7AC\uBD80\uD305\uC744 \uC9C4\uD589\uD560\uAE4C\uC694?`r`n\uC774\uBC88 \uC7AC\uBD80\uD305\uC5D0\uB9CC \uC801\uC6A9\uB418\uBA70 \uB2E4\uC74C \uBD80\uD305\uBD80\uD130\uB294 \uC6D0\uB798 Windows\uB85C \uC2DC\uC791\uB429\uB2C8\uB2E4.`r`n`r`n") +
            (U "\uBD80\uD305 \uB514\uC2A4\uD06C: ") + $dispLbl + "  " + $ud.SizeGB + "`r`n" +
            (U "\uBD80\uD305 \uACBD\uB85C: ") + $efiInfo
   } else {
    $dMsg = (U "\uC120\uD0DD\uD55C USB\uC5D0\uC11C \uC228\uAE40 EFI \uBD80\uD305 \uC601\uC5ED\uC744 \uCC3E\uC544 1\uD68C\uC131 \uC7AC\uBD80\uD305\uC744 \uC2DC\uB3C4\uD560\uAE4C\uC694?`r`n\uBD80\uD305 \uD30C\uC77C\uC774 \uC5C6\uC73C\uBA74 Windows \uACE0\uAE09 \uBD80\uD305 \uD654\uBA74\uC73C\uB85C \uC548\uB0B4\uD569\uB2C8\uB2E4.`r`n`r`n") +
            (U "\uB300\uC0C1 USB: ") + $dispLbl + "  " + $ud.SizeGB
   }
   $drD = [System.Windows.Forms.MessageBox]::Show($ui.Form, $dMsg, (U "USB \uC7AC\uBD80\uD305 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
   if ($drD -ne [System.Windows.Forms.DialogResult]::Yes) { return }

   $dSet = Invoke-DirectUsbEfiBootSetup $ud
   if ($dSet.Success) {
    & $ui.AppendLog ((U "1\uD68C\uC131 EFI \uC9C1\uC811 \uBD80\uD305 \uB4F1\uB85D \uC644\uB8CC: ") + $dispLbl + "  " + $dSet.Device + $dSet.Path)
    $rbD = Invoke-SafeRebootCore "/r /f /t 0"
    if ($rbD.Success) { $ui.Form.Close(); return }
    $errD = "shutdown /r /f /t 0 ExitCode=" + $rbD.ExitCode + " " + $rbD.Output
    Invoke-GuiErrorReportPrompt $ui (U "\uC7AC\uBD80\uD305 \uC624\uB958") (U "\uC7AC\uBD80\uD305 \uBA85\uB839 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") $errD
    return
   }
   & $ui.AppendLog ((U "EFI \uC9C1\uC811 \uBD80\uD305 \uB4F1\uB85D \uC2E4\uD328: ") + $dSet.Error)
   $fbDirectMsg = (U "USB\uC758 EFI \uBD80\uD305 \uD56D\uBAA9\uC744 \uC9C1\uC811 \uB4F1\uB85D\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4.`r`n\uB300\uC2E0 Windows \uACE0\uAE09 \uBD80\uD305 \uD654\uBA74\uC73C\uB85C \uC774\uB3D9\uD574 \uC7A5\uCE58 \uC0AC\uC6A9 \uBA54\uB274\uC5D0\uC11C USB\uB97C \uC120\uD0DD\uD560\uAE4C\uC694?")
   $drFbD = [System.Windows.Forms.MessageBox]::Show($ui.Form, $fbDirectMsg, (U "\uACE0\uAE09 \uBD80\uD305 \uC804\uD658 \uC548\uB0B4"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
   if ($drFbD -eq [System.Windows.Forms.DialogResult]::Yes) {
    $rbHp = Invoke-SafeRebootCore "/r /o /f /t 0"
    if ($rbHp.Success) { $ui.Form.Close(); return }
    $errHp = "shutdown /r /o /f /t 0 ExitCode=" + $rbHp.ExitCode + " " + $rbHp.Output
    Invoke-GuiErrorReportPrompt $ui (U "\uC7AC\uBD80\uD305 \uC624\uB958") (U "\uACE0\uAE09 \uBD80\uD305 \uC7AC\uBD80\uD305\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") $errHp
   }
   return
  }
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
   Invoke-GuiErrorReportPrompt $ui (U "\uC7AC\uBD80\uD305 \uC624\uB958") (U "\uC7AC\uBD80\uD305 \uBA85\uB839 \uC2E4\uD328\uC5D0 \uC2E4\uD328\uD588\uC2B5\uB2C8\uB2E4.") $errDet
  } else {
   $bcdErr = ($setRes.Lines -join " ")
   & $ui.AppendLog ((U "NVRAM \uBD80\uD305 \uC21C\uC11C \uBCC0\uACBD \uC2E4\uD328: ") + $bcdErr)
   if ($rowTag.Disk -and $rowTag.Disk.IsEfiReady) {
    $healSet = Invoke-DirectUsbEfiBootSetup $rowTag.Disk
    if ($healSet.Success) {
     & $ui.AppendLog ((U "EFI \uC9C1\uC811 \uBD80\uD305 \uB300\uCCB4 \uB4F1\uB85D \uC644\uB8CC: ") + $healSet.Device + $healSet.Path)
     $rbHeal = Invoke-SafeRebootCore "/r /f /t 0"
     if ($rbHeal.Success) { $ui.Form.Close(); return }
    }
   }
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
 $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
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
  $firstActIdx = -1
  foreach ($it in $rep.Items) {
   $pStr = if ($it.TargetPart -gt 0) {
    if ($it.BootType -eq "GPT_EFI") { "EFI #" + $it.TargetPart } else { "MBR #" + $it.TargetPart }
   } else { "-" }
   $guiSt = Format-BootloaderGuiStatus $it
   $rIdx = $peUi.Dgv.Rows.Add(("Disk " + $it.DiskNumber), [string]$it.Model, ([string]$it.SizeGB + " GB"), [string]$it.PartitionStyle, $pStr, $guiSt.Text)
   $row = $peUi.Dgv.Rows[$rIdx]
   $row.Tag = $it
   if ($it.State -in @("ACTIVE","BOTH","MBR_OS_BLOCKED")) {
    $row.DefaultCellStyle.BackColor = $peUi.Theme.DangerRedTint
    $row.DefaultCellStyle.ForeColor = $peUi.Theme.DangerRedDeep
    $row.DefaultCellStyle.SelectionBackColor = $peUi.Theme.DangerRedTint
    $row.DefaultCellStyle.SelectionForeColor = $peUi.Theme.DangerRedDeep
    $row.Cells[5].Style.Font = $peUi.Fonts.Bold
   } else {
    Set-AsanCellSemanticStyle $row.Cells[5] $guiSt.Kind $peUi.Theme $peUi.Fonts ($guiSt.Kind -ne "Neutral")
   }
   if ($firstActIdx -lt 0 -and $it.State -in @("DISABLED","ACTIVE")) { $firstActIdx = $rIdx }
   foreach ($c in $row.Cells) { $c.ToolTipText = $guiSt.Tip }
  }
  $peUi.Dgv.ClearSelection()
  if ($firstActIdx -ge 0) { $peUi.Dgv.Rows[$firstActIdx].Selected = $true }
  & $peUi.SyncPeBtn
 }.GetNewClosure()

 $dgv.Add_SelectionChanged({ & $peUi.SyncPeBtn }.GetNewClosure())
 $dgv.Add_CellDoubleClick({
  param($sender, $e)
  if ($e.RowIndex -ge 0 -and $peUi.BtnTog.Enabled) { $peUi.BtnTog.PerformClick() }
 }.GetNewClosure())
 $btnClose.Add_Click({ $peUi.Form.Close() }.GetNewClosure())
 $btnRef.Add_Click({ & $peUi.LoadPe }.GetNewClosure())
 $btnPeReboot.Add_Click({
  $dr = [System.Windows.Forms.MessageBox]::Show($peUi.Form, (U "PC\uB97C \uC989\uC2DC \uC7AC\uBD80\uD305\uD560\uAE4C\uC694?"), (U "\uC7AC\uBD80\uD305 \uD655\uC778"), [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
  if ($dr -eq [System.Windows.Forms.DialogResult]::Yes) {
   $wpeRes = Invoke-NativeOem "wpeutil.exe" "reboot"
   if ($wpeRes.ExitCode -ne 0) { $null = Invoke-SafeRebootCore "/r /f /t 0" }
   $peUi.Form.Close()
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
