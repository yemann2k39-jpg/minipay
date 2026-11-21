# MiniPay app icon = the login-page logo: Material account_balance_wallet
# glyph (0xE041) in brand blue #0F4C81 on white. No text.
# Pixel-exact placement: the glyph's real ink bounds are measured once, and a
# FRESH GraphicsPath is built per image (a shared path gets double-transformed).
Add-Type -AssemblyName System.Drawing

$fontPath = 'C:\KuromiLab\flutter\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf'
$blue = [System.Drawing.Color]::FromArgb(255, 15, 76, 129)   # 0F4C81
$glyph = [char]0xE041

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile($fontPath)
$family = $pfc.Families[0]

# Measure the glyph's real ink bounds once (render huge for precision).
$measureSize = 4096
$measurePath = New-Object System.Drawing.Drawing2D.GraphicsPath
$fmt = New-Object System.Drawing.StringFormat
$measurePath.AddString($glyph, $family, 0, [float]$measureSize,
    (New-Object System.Drawing.Point(0, 0)), $fmt)
$bounds = $measurePath.GetBounds()
$inkW = $bounds.Width; $inkH = $bounds.Height
Write-Host ("ink bounds: {0:N0} x {1:N0}" -f $inkW, $inkH)
$measurePath.Dispose()

function New-Icon([string]$path, [bool]$whiteBg, [double]$fillRatio,
                  [double]$biasRightRatio, [double]$biasUpRatio) {
  $size = 1024
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'

  if ($whiteBg) { $g.Clear([System.Drawing.Color]::White) }
  else { $g.Clear([System.Drawing.Color]::Transparent) }

  # Target: glyph ink width = fillRatio * canvas (height-constrained too).
  $targetW = $size * $fillRatio
  $targetH = $size * $fillRatio * 0.85   # glyphs look oversized if square-fitted
  $s = [Math]::Min($targetW / $inkW, $targetH / $inkH)

  # Center the ink bounds, then apply user nudges (right / up).
  $cx = ($bounds.X + $inkW / 2) * $s
  $cy = ($bounds.Y + $inkH / 2) * $s
  $dx = $size / 2 - $cx + $size * $biasRightRatio
  $dy = $size / 2 - $cy - $size * $biasUpRatio

  # FRESH path every call — transforming a shared path compounds.
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.AddString($glyph, $family, 0, [float]$measureSize,
      (New-Object System.Drawing.Point(0, 0)), $fmt)

  # Scale first, THEN translate (Append order) — otherwise the offset gets
  # scaled and the glyph lands off-center.
  $m = New-Object System.Drawing.Drawing2D.Matrix
  $m.Scale($s, $s)
  $m.Translate($dx, $dy, [System.Drawing.Drawing2D.MatrixOrder]::Append)
  $gp.Transform($m)
  $g.FillPath((New-Object System.Drawing.SolidBrush($blue)), $gp)
  $gp.Dispose()

  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host ("wrote {0} (scale {1:N3}, dx {2:N0}px, dy {3:N0}px)" -f $path, $s, ($size * $biasRightRatio), (-$size * $biasUpRatio))
}

New-Item -ItemType Directory -Force -Path assets\icon | Out-Null
# Legacy full-square icon: white bg, whole logo dead-center.
New-Icon "assets\icon\icon.png" $true 0.80 0.0 0.0
# Adaptive foreground: TRANSPARENT bg, dead-center.
New-Icon "assets\icon\foreground.png" $false 0.66 0.0 0.0
