# Generates a fake receipt PNG and POSTs it to /split/scan.
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(600, 800)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$font = New-Object System.Drawing.Font('Consolas', 22)
$brush = [System.Drawing.Brushes]::Black
$lines = @(
  'KOPITIAM RECEIPT',
  '----------------------',
  'Iced Coffee     3.50',
  'Cheesecake      7.00',
  'Chicken Rice    5.20',
  '----------------------',
  'TOTAL          15.70'
)
$y = 60
foreach ($line in $lines) { $g.DrawString($line, $font, $brush, 40, $y); $y += 60 }
$g.Dispose()
$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$b64 = [Convert]::ToBase64String($ms.ToArray())
"image bytes: $($ms.Length)"

$rich = Invoke-RestMethod -Method Post http://localhost:3000/auth/login -ContentType 'application/json' -Body (@{email='rich@minipay.test'; password='Passw0rd!23'} | ConvertTo-Json)
$h = @{Authorization = "Bearer $($rich.accessToken)"}
try {
  $res = Invoke-RestMethod -Method Post http://localhost:3000/split/scan -Headers $h -ContentType 'application/json' -Body (@{imageBase64=$b64; mimeType='image/png'} | ConvertTo-Json) -TimeoutSec 90
  $res.items | ForEach-Object { "item: $($_.name) = $($_.priceMinor)" }
} catch {
  "scan failed: $_"
}
