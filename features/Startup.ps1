# Slow startup: turn apps that start at sign-in on or off, the same way Task Manager does
# (StartupApproved registry values), so nothing is uninstalled or deleted.

Add-Strings @{
    'Slow startup'                                   = 'Treg oppstart'
    'Choose which apps start when you sign in.'      = 'Velg hvilke apper som starter når du logger på.'
    'Fewer apps at sign-in means your PC is ready sooner.' = 'Færre apper ved pålogging gjør at PC-en blir klar fortere.'
    'Finding apps that start with Windows...'        = 'Finner apper som starter med Windows ...'
    'Open startup settings'                          = 'Åpne oppstartsinnstillinger'
    'Refresh'                                        = 'Oppdater'
    '{0} of {1} apps start when you sign in'         = '{0} av {1} apper starter når du logger på'
    "Turning an app off doesn't uninstall it. It just won't open by itself anymore. Changes take effect the next time you sign in." = 'Å slå av en app avinstallerer den ikke. Den åpner seg bare ikke av seg selv lenger. Endringene gjelder fra neste gang du logger på.'
    "Apps from the Microsoft Store (like Teams or Spotify) may only be listed in Windows' startup settings." = 'Apper fra Microsoft Store (som Teams eller Spotify) vises kanskje bare i oppstartsinnstillingene i Windows.'
    'Some apps start for everyone on this PC. Run as administrator to change those.' = 'Noen apper starter for alle på denne PC-en. Kjør som administrator for å endre dem.'
    'No apps start automatically when you sign in.'  = 'Ingen apper starter automatisk når du logger på.'
    'Starts at sign-in'                              = 'Starter ved pålogging'
    'Off'                                            = 'Av'
    'Needs administrator'                            = 'Krever administrator'
    'For everyone on this PC'                        = 'For alle på denne PC-en'
    'Unknown publisher'                              = 'Ukjent utgiver'
    'Startup app turned off'                         = 'Oppstartsapp slått av'
    'Startup app turned on'                          = 'Oppstartsapp slått på'
    "Couldn't read the startup apps: {0}"            = 'Kunne ikke lese oppstartsappene: {0}'
    "Couldn't change {0}: {1}"                       = 'Kunne ikke endre {0}: {1}'
    'Changing apps that start for everyone'          = 'Å endre apper som starter for alle'
}

Register-Feature @{
    Name    = 'Startup'
    Section = 'fix'
    Order   = 40
    Glyph   = 'E945'
    Title   = 'Slow startup'
    Desc    = 'Choose which apps start when you sign in.'
    Panel   = 'PanelStartup'
    Open    = { Open-Startup }
    Init    = {
        $ui.SupBtnRefresh.Add_Click({ Update-Startup })
        $ui.SupBtnSettings.Add_Click({ Start-Process 'ms-settings:startupapps' })
    }
    Xaml    = @"
          <DockPanel x:Name="PanelStartup" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="SupBtnSettings" DockPanel.Dock="Right" Content="$(X 'Open startup settings')"/>
                <Button x:Name="SupBtnRefresh" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE72C;" VerticalAlignment="Center"/>
                    <TextBlock Text="$(X 'Refresh')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <StackPanel x:Name="SupLoading" Margin="0,24,0,0">
                  <TextBlock x:Name="SupLoadingText" Text="$(X 'Finding apps that start with Windows...')" Style="{StaticResource MutedText}"/>
                  <ProgressBar x:Name="SupLoadingBar" IsIndeterminate="True" Width="260" HorizontalAlignment="Left" Margin="0,12,0,0"/>
                </StackPanel>
                <StackPanel x:Name="SupContent" Visibility="Collapsed">
                  <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                    <StackPanel>
                      <TextBlock x:Name="SupSummary" Style="{StaticResource CardTitle}"/>
                      <TextBlock Style="{StaticResource MutedText}" Text="$(X "Turning an app off doesn't uninstall it. It just won't open by itself anymore. Changes take effect the next time you sign in.")"/>
                    </StackPanel>
                  </Border>
                  <Border Style="{StaticResource Card}" Padding="0">
                    <StackPanel x:Name="SupList"/>
                  </Border>
                  <TextBlock x:Name="SupAdminNote" Style="{StaticResource MutedText}" Margin="2,12,0,0" Visibility="Collapsed"
                             Text="$(X 'Some apps start for everyone on this PC. Run as administrator to change those.')"/>
                  <TextBlock Style="{StaticResource MutedText}" Margin="2,8,0,0"
                             Text="$(X "Apps from the Microsoft Store (like Teams or Spotify) may only be listed in Windows' startup settings.")"/>
                </StackPanel>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>
"@
    Engine  = {
        $SupApprovedBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

        # "C:\Program Files\x\app.exe" /arg  ->  C:\Program Files\x\app.exe
        function Get-SupExePath([string]$Command) {
            $c = [Environment]::ExpandEnvironmentVariables("$Command".Trim())
            if ($c -match '^"([^"]+)"') { return $Matches[1] }
            if ($c -match '^(.+?\.(exe|cmd|bat|com))(\s|$)') { return $Matches[1] }
            ($c -split '\s')[0]
        }

        # Task Manager: first byte even = enabled, odd = disabled; no value = enabled
        function Test-SupEnabled([string]$ApprovedKey, [string]$ValueName) {
            $v = (Get-ItemProperty -LiteralPath $ApprovedKey -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
            if (-not $v -or $v.Count -lt 1) { return $true }
            (($v[0] -band 1) -eq 0)
        }

        function Get-StartupItems {
            $shell = New-Object -ComObject WScript.Shell
            $sources = @(
                @{ Run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKCU:\$SupApprovedBase\Run"; AllUsers = $false }
                @{ Run = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$SupApprovedBase\Run"; AllUsers = $true }
                @{ Run = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$SupApprovedBase\Run32"; AllUsers = $true }
                @{ Folder = [Environment]::GetFolderPath('Startup'); Approved = "HKCU:\$SupApprovedBase\StartupFolder"; AllUsers = $false }
                @{ Folder = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$SupApprovedBase\StartupFolder"; AllUsers = $true }
            )
            $items = foreach ($src in $sources) {
                $entries = @()
                if ($src.Run) {
                    $key = Get-Item -LiteralPath $src.Run -ErrorAction SilentlyContinue
                    if ($key) {
                        $entries = @($key.GetValueNames() | Where-Object { $_ } | ForEach-Object {
                            @{ ValueName = $_; Label = $_; Command = "$($key.GetValue($_))" } })
                    }
                } elseif ($src.Folder -and (Test-Path -LiteralPath $src.Folder)) {
                    $entries = @(Get-ChildItem -LiteralPath $src.Folder -File -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
                            $cmd = $_.FullName
                            if ($_.Extension -eq '.lnk') { try { $t = $shell.CreateShortcut($_.FullName).TargetPath; if ($t) { $cmd = $t } } catch {} }
                            @{ ValueName = $_.Name; Label = $_.BaseName; Command = $cmd }
                        })
                }
                foreach ($e in $entries) {
                    $exe = Get-SupExePath $e.Command
                    $desc = $null; $company = $null
                    try {
                        if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) {
                            $vi = (Get-Item -LiteralPath $exe -ErrorAction Stop).VersionInfo
                            $desc = "$($vi.FileDescription)".Trim(); $company = "$($vi.CompanyName)".Trim()
                        }
                    } catch {}
                    [pscustomobject]@{
                        Name        = if ($desc) { $desc } else { $e.Label }
                        Publisher   = $company
                        Command     = $e.Command
                        ValueName   = $e.ValueName
                        ApprovedKey = $src.Approved
                        AllUsers    = $src.AllUsers
                        Enabled     = Test-SupEnabled $src.Approved $e.ValueName
                    }
                }
            }
            @($items | Sort-Object Name)
        }

        # Same 12-byte format as Task Manager: byte 0 = 2 (on) / 3 (off), bytes 4-11 = FILETIME when turned off
        function Set-StartupItemEnabled([string]$ApprovedKey, [string]$ValueName, [bool]$Enabled) {
            if (-not (Test-Path -LiteralPath $ApprovedKey)) { New-Item -Path $ApprovedKey -Force | Out-Null }
            $bytes = New-Object byte[] 12
            if ($Enabled) { $bytes[0] = 2 }
            else {
                $bytes[0] = 3
                [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()).CopyTo($bytes, 4)
            }
            Set-ItemProperty -LiteralPath $ApprovedKey -Name $ValueName -Value $bytes -Type Binary
        }
    }
}

function Open-Startup {
    Show-Page 'PanelStartup' (T 'Slow startup') (T 'Fewer apps at sign-in means your PC is ready sooner.')
    Update-Startup
}

function Update-Startup {
    $ui.SupLoading.Visibility = 'Visible'
    $ui.SupLoadingBar.Visibility = 'Visible'
    $ui.SupLoadingText.Text = T 'Finding apps that start with Windows...'
    $ui.SupContent.Visibility = 'Collapsed'
    Start-Worker -Work { [pscustomobject]@{ Items = @(Get-StartupItems) } } -OnDone { param($r, $err) Show-Startup $r $err }
}

function Show-Startup($r, $err) {
    if ($err -or -not $r) {
        $ui.SupLoadingBar.Visibility = 'Collapsed'
        $ui.SupLoadingText.Text = (T "Couldn't read the startup apps: {0}") -f $err
        return
    }
    $ui.SupLoading.Visibility = 'Collapsed'
    $ui.SupContent.Visibility = 'Visible'
    $ui.SupList.Children.Clear()
    $script:SupRows = @()
    $items = @($r.Items)
    $admin = Test-IsAdmin

    if (-not $items.Count) {
        [void]$ui.SupList.Children.Add((New-Xaml "<TextBlock Text=`"$(X 'No apps start automatically when you sign in.')`" Margin=`"18,14`" Foreground=`"{DynamicResource Muted}`"/>"))
    }
    $first = $true
    foreach ($it in $items) {
        $border = if ($first) { '0' } else { '0,1,0,0' }
        $first = $false
        $sub = if ($it.Publisher) { $it.Publisher } else { T 'Unknown publisher' }
        if ($it.AllUsers) { $sub += ' - ' + (T 'For everyone on this PC') }
        $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="$border" Padding="18,10">
  <CheckBox HorizontalContentAlignment="Stretch" VerticalContentAlignment="Center" ToolTipService.ShowOnDisabled="True">
    <DockPanel Margin="6,0,0,0">
      <TextBlock DockPanel.Dock="Right" VerticalAlignment="Center" Margin="16,0,0,0"/>
      <StackPanel>
        <TextBlock Text="$(Esc $it.Name)" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
        <TextBlock Text="$(Esc $sub)" Foreground="{DynamicResource Faint}" FontSize="12" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
    </DockPanel>
  </CheckBox>
</Border>
"@
        $cb = $row.Child
        $cb.IsChecked = [bool]$it.Enabled
        $cb.Tag = $it
        $cb.ToolTip = $it.Command
        if ($it.AllUsers -and -not $admin) {
            $cb.IsEnabled = $false
            $cb.ToolTip = (T 'Needs administrator') + "`n" + $it.Command
        }
        # Click (not Checked/Unchecked) so only real user clicks change anything
        $cb.Add_Click({ param($s, $e) Set-StartupRow $s })
        [void]$ui.SupList.Children.Add($row)
        $script:SupRows += $cb
        Update-StartupRowText $cb
    }
    $ui.SupAdminNote.Visibility = if (-not $admin -and @($items | Where-Object { $_.AllUsers }).Count) { 'Visible' } else { 'Collapsed' }
    Update-StartupSummary
}

function Update-StartupRowText($cb) {
    $label = $cb.Content.Children[0]
    if ($cb.IsChecked) { $label.Text = T 'Starts at sign-in'; Set-Themed $label Foreground Good }
    else { $label.Text = T 'Off'; Set-Themed $label Foreground Faint }
}

function Update-StartupSummary {
    $on = @($script:SupRows | Where-Object { $_.IsChecked }).Count
    $ui.SupSummary.Text = (T '{0} of {1} apps start when you sign in') -f $on, @($script:SupRows).Count
}

function Set-StartupRow($cb) {
    $it = $cb.Tag
    $enable = [bool]$cb.IsChecked
    if ($it.AllUsers -and -not (Confirm-Admin (T 'Changing apps that start for everyone'))) {
        $cb.IsChecked = -not $enable
        return
    }
    try {
        Set-StartupItemEnabled -ApprovedKey $it.ApprovedKey -ValueName $it.ValueName -Enabled $enable
        $it.Enabled = $enable
        Add-History -Title $(if ($enable) { T 'Startup app turned on' } else { T 'Startup app turned off' }) -State ok -Detail $it.Name
    } catch {
        $cb.IsChecked = -not $enable
        Show-Error ((T "Couldn't change {0}: {1}") -f $it.Name, $_.Exception.Message)
    }
    Update-StartupRowText $cb
    Update-StartupSummary
}
