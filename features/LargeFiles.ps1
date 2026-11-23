# Largest files: finds big files in the user's own folders (not AppData) and lets them
# open the folder or move a file to the Recycle Bin.

Add-Strings @{
    'Largest files'                                                         = 'Største filer'
    'Find big files in your own folders and decide what to delete.'         = 'Finn store filer i dine egne mapper og bestem hva du vil slette.'
    'Big files in your own folders. Deleted files go to the Recycle Bin.'   = 'Store filer i dine egne mapper. Filer du sletter havner i papirkurven.'
    'Looking for big files...'                                              = 'Leter etter store filer...'
    'This can take a minute or two.'                                        = 'Dette kan ta et minutt eller to.'
    'Where your space goes'                                                 = 'Hva som tar plass'
    'Total size of each folder in your user folder.'                        = 'Total størrelse på hver mappe i brukermappen din.'
    'Files of 50 MB or more'                                                = 'Filer på 50 MB eller mer'
    '{0} files of 50 MB or more'                                            = '{0} filer på 50 MB eller mer'
    '1 file of 50 MB or more'                                               = '1 fil på 50 MB eller mer'
    'Showing the biggest {0}.'                                              = 'Viser de {0} største.'
    'No files of 50 MB or more'                                             = 'Ingen filer på 50 MB eller mer'
    'Your own folders have no big files. Nice and tidy!'                    = 'Det er ingen store filer i mappene dine. Ryddig og fint!'
    "Couldn't scan your folders"                                            = 'Klarte ikke å gå gjennom mappene dine'
    'Show in folder'                                                        = 'Vis i mappe'
    'Delete'                                                                = 'Slett'
    'Cancel'                                                                = 'Avbryt'
    'Scan again'                                                            = 'Søk på nytt'
    'Deleted files go to the Recycle Bin, so you can still get them back.'  = 'Filer du sletter havner i papirkurven, så du kan fortsatt få dem tilbake.'
    'Downloaded long ago. Do you still need it?'                            = 'Lastet ned for lenge siden. Trenger du den fortsatt?'
    'Move this file to the Recycle Bin?'                                    = 'Flytte denne filen til papirkurven?'
    "{0}`n{1}`n`nYou can get it back from the Recycle Bin until you empty it." = "{0}`n{1}`n`nDu kan hente den tilbake fra papirkurven helt til du tømmer den."
    'Moved {0} ({1}) to the Recycle Bin'                                    = 'Flyttet {0} ({1}) til papirkurven'
    "Couldn't delete the file. It may be open in another app.`n`n{0}"        = "Klarte ikke å slette filen. Den er kanskje åpen i en annen app.`n`n{0}"
    'The file no longer exists.'                                            = 'Filen finnes ikke lenger.'
    'Other files'                                                           = 'Andre filer'
    '{0} days ago'                                                          = 'for {0} dager siden'
    '1 month ago'                                                           = 'for 1 måned siden'
    '{0} months ago'                                                        = 'for {0} måneder siden'
    '1 year ago'                                                            = 'for 1 år siden'
    '{0} years ago'                                                         = 'for {0} år siden'
    'Changed {0}'                                                           = 'Endret {0}'
}

function Format-Ago([datetime]$When) {
    $days = ((Get-Date).Date - $When.Date).TotalDays
    if ($days -lt 1) { return (T 'Today').ToLower() }
    if ($days -lt 2) { return (T 'Yesterday').ToLower() }
    if ($days -lt 31) { return (T '{0} days ago') -f [int]$days }
    $months = [int][math]::Floor($days / 30.4)
    if ($months -lt 12) { if ($months -le 1) { return T '1 month ago' }; return (T '{0} months ago') -f $months }
    $years = [int][math]::Floor($days / 365.25)
    if ($years -le 1) { return T '1 year ago' }
    (T '{0} years ago') -f $years
}

Register-Feature @{
    Name    = 'LargeFiles'
    Section = 'tidy'
    Order   = 30
    Glyph   = 'E8B7'
    Title   = 'Largest files'
    Desc    = 'Find big files in your own folders and decide what to delete.'
    Panel   = 'PanelLargeFiles'
    Open    = { Open-LargeFiles }
    Init    = {
        $ui.BtnBigRescan.Add_Click({ Start-LargeFileScan })
    }
    Engine  = {
        # Walks the profile without following junctions/symlinks, skips AppData and OneDrive
        # online-only files (they use no disk space). Returns the top files and per-folder totals.
        function Find-LargeFiles {
            param([string]$Root, [long]$MinSize = 50MB, [int]$Top = 100)
            $skip = 0x400 -bor 0x1000 -bor 0x400000 -bor 0x40000   # ReparsePoint, Offline, RecallOnDataAccess, RecallOnOpen
            $big = New-Object System.Collections.Generic.List[object]
            $folders = @{}
            $scanned = 0
            $downloads = Join-Path $Root 'Downloads'
            $rootInfo = New-Object IO.DirectoryInfo $Root
            $topEntries = @()
            try { $topEntries = @($rootInfo.EnumerateFileSystemInfos()) } catch {}

            foreach ($topEntry in $topEntries) {
                if ($topEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($topEntry -is [IO.FileInfo]) {
                    if ([int]$topEntry.Attributes -band $skip) { continue }
                    $folders['*'] = [long]$folders['*'] + $topEntry.Length
                    continue
                }
                if ($topEntry.Name -eq 'AppData' -or $topEntry.Name.StartsWith('.')) { continue }
                $name = $topEntry.Name
                $sum = [long]0
                $stack = New-Object System.Collections.Generic.Stack[IO.DirectoryInfo]
                $stack.Push($topEntry)
                while ($stack.Count) {
                    $d = $stack.Pop()
                    try {
                        foreach ($e in $d.EnumerateFileSystemInfos()) {
                            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                            if ($e -is [IO.DirectoryInfo]) { $stack.Push($e); continue }
                            if ([int]$e.Attributes -band $skip) { continue }
                            $len = $e.Length
                            $sum += $len
                            $scanned++
                            if ($scanned % 2000 -eq 0) { SetStatus ((T 'Looking for big files...') + " ($scanned)") }
                            if ($len -ge $MinSize) {
                                $big.Add([pscustomobject]@{
                                    Path        = $e.FullName
                                    Name        = $e.Name
                                    Dir         = $e.DirectoryName
                                    Size        = $len
                                    Modified    = $e.LastWriteTime
                                    InDownloads = $e.FullName.StartsWith($downloads + '\', [StringComparison]::OrdinalIgnoreCase)
                                })
                            }
                        }
                    } catch {}
                }
                if ($sum -gt 0) { $folders[$name] = $sum }
            }

            [pscustomobject]@{
                Files   = @($big | Sort-Object Size -Descending | Select-Object -First $Top)
                Count   = $big.Count
                Folders = @($folders.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { [pscustomobject]@{ Name = $_.Key; Size = [long]$_.Value } })
                Scanned = $scanned
            }
        }
    }
    Xaml    = @"
          <DockPanel x:Name="PanelLargeFiles" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnBigRescan" DockPanel.Dock="Right" Margin="16,0,0,0">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE72C;" VerticalAlignment="Center"/>
                    <TextBlock Text="$(X 'Scan again')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
                <TextBlock Style="{StaticResource MutedText}" VerticalAlignment="Center" Text="$(X 'Deleted files go to the Recycle Bin, so you can still get them back.')"/>
              </DockPanel>
            </Border>
            <Grid>
              <StackPanel x:Name="BigLoading" VerticalAlignment="Center" HorizontalAlignment="Center" MaxWidth="520">
                <TextBlock x:Name="TxtBigLoading" Text="$(X 'Looking for big files...')" FontSize="16" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
                <ProgressBar x:Name="BigLoadingBar" IsIndeterminate="True" Width="260" Margin="0,14,0,0"/>
                <TextBlock x:Name="TxtBigLoadingSub" Text="$(X 'This can take a minute or two.')" Style="{StaticResource MutedText}" HorizontalAlignment="Center" TextAlignment="Center" Margin="0,10,0,0"/>
              </StackPanel>
              <ScrollViewer x:Name="BigContent" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="24,8,24,24">
                  <Border Style="{StaticResource Card}" Margin="0,0,0,16">
                    <StackPanel>
                      <TextBlock Text="$(X 'Where your space goes')" Style="{StaticResource CardTitle}"/>
                      <TextBlock Text="$(X 'Total size of each folder in your user folder.')" Style="{StaticResource MutedText}" FontSize="13"/>
                      <StackPanel x:Name="BigFolders" Margin="0,10,0,0"/>
                    </StackPanel>
                  </Border>
                  <TextBlock x:Name="TxtBigSummary" Style="{StaticResource CardTitle}"/>
                  <TextBlock x:Name="TxtBigSummarySub" Style="{StaticResource MutedText}" FontSize="13" Margin="0,0,0,10"/>
                  <Border x:Name="BigListCard" Style="{StaticResource Card}" Padding="0">
                    <StackPanel x:Name="BigList"/>
                  </Border>
                </StackPanel>
              </ScrollViewer>
            </Grid>
          </DockPanel>
"@
}

$script:BigScanning = $false
$script:BigResult = $null

function Open-LargeFiles {
    Show-Page 'PanelLargeFiles' (T 'Largest files') (T 'Big files in your own folders. Deleted files go to the Recycle Bin.')
    if (-not $script:BigResult -and -not $script:BigScanning) { Start-LargeFileScan }
}

function Start-LargeFileScan {
    if ($script:BigScanning) { return }
    $script:BigScanning = $true
    $ui.BtnBigRescan.IsEnabled = $false
    $ui.BigContent.Visibility = 'Collapsed'
    $ui.BigLoading.Visibility = 'Visible'
    $ui.BigLoadingBar.Visibility = 'Visible'
    $ui.TxtBigLoading.Text = T 'Looking for big files...'
    $ui.TxtBigLoadingSub.Text = T 'This can take a minute or two.'
    Start-Worker -ArgumentList $env:USERPROFILE -Work {
        param($root)
        Find-LargeFiles -Root $root
    } -OnDone {
        param($r, $err)
        $script:BigScanning = $false
        $ui.BtnBigRescan.IsEnabled = $true
        if ($err -or -not $r) {
            $ui.BigLoadingBar.Visibility = 'Collapsed'
            $ui.TxtBigLoading.Text = T "Couldn't scan your folders"
            $ui.TxtBigLoadingSub.Text = "$err"
            return
        }
        $script:BigResult = $r
        Show-LargeFiles $r
    }
}

function Show-LargeFiles($r) {
    $ui.BigLoading.Visibility = 'Collapsed'
    $ui.BigContent.Visibility = 'Visible'

    # Folder bars (top 8, the rest folded into "Other files")
    $ui.BigFolders.Children.Clear()
    $folders = @($r.Folders)
    # Named folders of 1 MB or more (top 8); loose files and everything else go into "Other files"
    $named = @($folders | Where-Object { $_.Name -ne '*' -and $_.Size -ge 1MB })
    $shown = @($named | Select-Object -First 8)
    $rest = [long](($folders | Measure-Object Size -Sum).Sum) - [long](($shown | Measure-Object Size -Sum).Sum)
    $max = [math]::Max([double]1, [double](($folders | Measure-Object Size -Maximum).Maximum))
    $rows = @($shown | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Size = $_.Size } })
    if ($rest -ge 1MB) { $rows += [pscustomobject]@{ Name = T 'Other files'; Size = $rest } }
    foreach ($f in $rows) {
        $pct = [int](100 * $f.Size / $max)
        $row = New-Xaml @"
<Grid Margin="0,5">
  <Grid.ColumnDefinitions><ColumnDefinition Width="200"/><ColumnDefinition Width="*"/><ColumnDefinition Width="100"/></Grid.ColumnDefinitions>
  <TextBlock Text="$(Esc $f.Name)" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,12,0"/>
  <ProgressBar Grid.Column="1" Height="8" Maximum="100" Value="$pct" VerticalAlignment="Center"/>
  <TextBlock Grid.Column="2" Text="$(Esc (Format-Bytes $f.Size))" TextAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource Muted}"/>
</Grid>
"@
        [void]$ui.BigFolders.Children.Add($row)
    }

    $script:BigCount = [int]$r.Count
    Update-LargeFilesSummary
    $ui.BigList.Children.Clear()
    foreach ($f in @($r.Files)) { Add-LargeFileRow $f }
    $ui.BigContent.ScrollToTop()
}

function Update-LargeFilesSummary {
    $n = $script:BigCount
    if ($n -le 0) {
        $ui.TxtBigSummary.Text = T 'No files of 50 MB or more'
        $ui.TxtBigSummarySub.Text = T 'Your own folders have no big files. Nice and tidy!'
        $ui.BigListCard.Visibility = 'Collapsed'
        return
    }
    $ui.BigListCard.Visibility = 'Visible'
    $ui.TxtBigSummary.Text = if ($n -eq 1) { T '1 file of 50 MB or more' } else { (T '{0} files of 50 MB or more') -f $n }
    $ui.TxtBigSummarySub.Text = if ($n -gt 100) { (T 'Showing the biggest {0}.') -f 100 } else { '' }
    $ui.TxtBigSummarySub.Visibility = if ($ui.TxtBigSummarySub.Text) { 'Visible' } else { 'Collapsed' }
}

function Add-LargeFileRow($f) {
    $rel = $f.Dir
    if ($rel.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($env:USERPROFILE.Length).TrimStart('\') }
    if (-not $rel) { $rel = '\' }
    $sub = '{0}  -  {1}' -f $rel, ((T 'Changed {0}') -f (Format-Ago $f.Modified))
    $old = $f.InDownloads -and $f.Modified -lt (Get-Date).AddDays(-90)
    $hint = if ($old) { "<TextBlock Text=`"$(X 'Downloaded long ago. Do you still need it?')`" Foreground=`"{DynamicResource Warn}`" FontSize=`"12`" Margin=`"0,2,0,0`"/>" } else { '' }
    $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="0,0,0,1" Padding="18,10">
  <DockPanel>
    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
      <TextBlock Text="$(Esc (Format-Bytes $f.Size))" FontWeight="SemiBold" Width="80" TextAlignment="Right" VerticalAlignment="Center" Margin="12,0,16,0"/>
      <Button Content="$(X 'Show in folder')" Padding="10,5"/>
      <Button Content="$(X 'Delete')" Padding="10,5" Margin="8,0,0,0"/>
    </StackPanel>
    <StackPanel>
      <TextBlock Text="$(Esc $f.Name)" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" ToolTip="$(Esc $f.Path)"/>
      <TextBlock Text="$(Esc $sub)" Foreground="{DynamicResource Muted}" FontSize="12" TextTrimming="CharacterEllipsis" ToolTip="$(Esc $f.Dir)"/>
      $hint
    </StackPanel>
  </DockPanel>
</Border>
"@
    $buttons = $row.Child.Children[0].Children
    $info = [pscustomobject]@{ Path = $f.Path; Name = $f.Name; Size = $f.Size; Row = $row }
    $buttons[1].Tag = $info
    $buttons[2].Tag = $info
    $buttons[1].Add_Click({ param($s, $e) Show-LargeFileInFolder $s.Tag.Path })
    $buttons[2].Add_Click({ param($s, $e) Remove-LargeFile $s.Tag })
    [void]$ui.BigList.Children.Add($row)
}

function Show-LargeFileInFolder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Show-Error (T 'The file no longer exists.'); return }
    Start-Process explorer.exe -ArgumentList "/select,`"$Path`""
}

function Remove-LargeFile($Info) {
    if (-not (Test-Path -LiteralPath $Info.Path)) {
        Show-Error (T 'The file no longer exists.')
        $ui.BigList.Children.Remove($Info.Row); $script:BigCount--; Update-LargeFilesSummary
        return
    }
    $size = Format-Bytes $Info.Size
    $d = Show-Dialog -Title (T 'Move this file to the Recycle Bin?') -Icon question `
        -Message ((T "{0}`n{1}`n`nYou can get it back from the Recycle Bin until you empty it.") -f $Info.Name, $size) `
        -Buttons 'Delete', 'Cancel'
    if ($d.Button -ne 'Delete') { return }
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Info.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } catch {
        Show-Error ((T "Couldn't delete the file. It may be open in another app.`n`n{0}") -f $_.Exception.Message)
        return
    }
    if (Test-Path -LiteralPath $Info.Path) { return }   # the user cancelled a Windows prompt
    $ui.BigList.Children.Remove($Info.Row)
    $script:BigCount--
    Update-LargeFilesSummary
    Add-History -Title (T 'Largest files') -State ok -Detail ((T 'Moved {0} ({1}) to the Recycle Bin') -f $Info.Name, $size)
}
