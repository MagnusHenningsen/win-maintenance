# Builds "PC Maintenance.exe" (the launcher for MaintainGui.ps1) and its icon.
# Only needed when launcher\Launcher.cs or the icon changes; the GUI script itself needs no build.
# Uses the C# compiler that ships with Windows (.NET Framework 4), so no SDK is required.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Add-Type -AssemblyName System.Drawing

#--- Icon: white wrench on a rounded blue square, several sizes in one .ico ---
function New-IconPng([int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear([System.Drawing.Color]::Transparent)

    $r = [math]::Max(2, [int]($Size * 0.22))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $w = $Size - 1
    $path.AddArc(0, 0, $r * 2, $r * 2, 180, 90)
    $path.AddArc($w - $r * 2, 0, $r * 2, $r * 2, 270, 90)
    $path.AddArc($w - $r * 2, $w - $r * 2, $r * 2, $r * 2, 0, 90)
    $path.AddArc(0, $w - $r * 2, $r * 2, $r * 2, 90, 90)
    $path.CloseFigure()
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (
        (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point $Size, $Size),
        [System.Drawing.Color]::FromArgb(255, 15, 108, 189), [System.Drawing.Color]::FromArgb(255, 58, 142, 224))
    $g.FillPath($brush, $path)

    $font = New-Object System.Drawing.Font 'Segoe MDL2 Assets', ([single]($Size * 0.52)), ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $rect = New-Object System.Drawing.RectangleF 0, ([single]($Size * 0.03)), $Size, $Size
    $g.DrawString([string][char]0xE90F, $font, [System.Drawing.Brushes]::White, $rect, $fmt)
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    , $ms.ToArray()
}

$sizes = 16, 24, 32, 48, 64, 256
$pngs = @($sizes | ForEach-Object { , (New-IconPng $_) })
$ico = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter $ico
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]
    $bw.Write([byte]($s % 256)); $bw.Write([byte]($s % 256))   # 256 is stored as 0
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw.Write($p) }
$bw.Flush()
New-Item -ItemType Directory -Force (Join-Path $root 'assets') | Out-Null
$icoPath = Join-Path $root 'assets\app.ico'
[IO.File]::WriteAllBytes($icoPath, $ico.ToArray())
Write-Host "Icon:     $icoPath"

#--- Launcher exe ---
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$exe = Join-Path $root 'PC Maintenance.exe'
& $csc /nologo /target:winexe /optimize+ /platform:anycpu "/win32icon:$icoPath" `
    /reference:System.Windows.Forms.dll "/out:$exe" (Join-Path $root 'launcher\Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw "csc failed ($LASTEXITCODE)" }
Write-Host "Launcher: $exe"
