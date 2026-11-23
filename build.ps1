# Builds "PC Maintenance.exe" (the launcher for MaintainGui.ps1) and its icons, and optionally a release.
# Uses the C# compiler that ships with Windows (.NET Framework 4), so no SDK is required.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1               exe + icons
#   ... build.ps1 -Package                                                      also dist\PC-Maintenance-<version>.zip
#   ... build.ps1 -Release                                                      also publish the zip as GitHub release v<version> (needs gh)
#   ... build.ps1 -CertThumbprint <thumbprint>                                  sign the exe with a code-signing certificate
#
# Installed copies update themselves from the latest GitHub release, so publish one for every version
# people should get (bump $AppVersion in MaintainGui.ps1 first; the tag is v<that version>).
param([switch]$Package, [switch]$Release, [string]$CertThumbprint)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$version = [regex]::Match((Get-Content (Join-Path $root 'MaintainGui.ps1') -Raw), "\`$AppVersion = '([\d.]+)'").Groups[1].Value
if (-not $version) { throw 'Could not read $AppVersion from MaintainGui.ps1' }
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
function Write-IfChanged([string]$Path, [byte[]]$Bytes) {
    # Skip unchanged files: a running copy of the app may have them open
    if ((Test-Path $Path) -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -eq [Convert]::ToBase64String($Bytes)) { return }
    [IO.File]::WriteAllBytes($Path, $Bytes)
}
Write-IfChanged $icoPath $ico.ToArray()
Write-Host "Icon:     $icoPath"
# PNG for Windows notifications (registered as the app's notification icon)
Write-IfChanged (Join-Path $root 'assets\app.png') $pngs[-1]

#--- Launcher exe ---
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$exe = Join-Path $root 'PC Maintenance.exe'
& $csc /nologo /target:winexe /optimize+ /platform:anycpu "/win32icon:$icoPath" `
    /reference:System.Windows.Forms.dll "/out:$exe" (Join-Path $root 'launcher\Launcher.cs')
if ($LASTEXITCODE -ne 0) { throw "csc failed ($LASTEXITCODE)" }
Write-Host "Launcher: $exe"

#--- Optional code signing (stops the SmartScreen "unknown publisher" warning once the certificate is trusted) ---
if ($CertThumbprint) {
    $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $CertThumbprint } | Select-Object -First 1
    if (-not $cert) { throw "Certificate $CertThumbprint not found in the certificate store." }
    $sig = Set-AuthenticodeSignature -FilePath $exe -Certificate $cert -TimestampServer 'http://timestamp.digicert.com' -HashAlgorithm SHA256
    if ($sig.Status -ne 'Valid') { throw "Signing failed: $($sig.StatusMessage)" }
    Write-Host "Signed:   $exe"
}

#--- Release zip (what people download; installed copies update from it) ---
if ($Package -or $Release) {
    $dist = Join-Path $root 'dist'
    $stage = Join-Path $dist 'stage'
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $stage | Out-Null
    foreach ($n in 'PC Maintenance.exe', 'MaintainGui.ps1', 'Maintain.cmd', 'README.md', 'assets', 'features', 'lang') {
        $src = Join-Path $root $n
        if (Test-Path $src) { Copy-Item $src -Destination $stage -Recurse -Force }
    }
    $zip = Join-Path $dist "PC-Maintenance-$version.zip"
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    # Not Compress-Archive: in Windows PowerShell it writes '\' in entry names, which some unzip tools mishandle
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::Open($zip, 'Create')
    try {
        foreach ($file in Get-ChildItem $stage -Recurse -File) {
            $name = $file.FullName.Substring($stage.Length + 1).Replace('\', '/')
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $name, 'Optimal')
        }
    } finally { $archive.Dispose() }
    Remove-Item $stage -Recurse -Force
    Write-Host "Package:  $zip"
}

if ($Release) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is needed for -Release.' }
    $notes = "Download **PC-Maintenance-$version.zip**, unzip it and double-click **PC Maintenance.exe**. It offers to install itself and adds PC Maintenance to the Start menu.`n`nInstalled copies update to this version automatically."
    & gh release create "v$version" $zip --title "PC Maintenance $version" --notes $notes
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed ($LASTEXITCODE)" }
    Write-Host "Released: v$version"
}
