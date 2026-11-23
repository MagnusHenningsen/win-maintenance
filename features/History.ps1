# History: what the app has done on this PC (from %LOCALAPPDATA%\PCMaintenance\history.jsonl).

Add-Strings @{
    'History'                                                     = 'Historikk'
    'See what this app has done on your PC, and when.'            = 'Se hva appen har gjort på PC-en din, og når.'
    'Everything this app has done on your PC, newest first.'      = 'Alt appen har gjort på PC-en din, nyeste først.'
    'Nothing here yet'                                            = 'Ingenting her ennå'
    'When you update, clean up or fix something, it shows up here.' = 'Når du oppdaterer, rydder eller fikser noe, dukker det opp her.'
    'Today'                                                       = 'I dag'
    'Yesterday'                                                   = 'I går'
    'Automatic'                                                   = 'Automatisk'
    'Done automatically by scheduled maintenance'                 = 'Gjort automatisk av planlagt vedlikehold'
    'Open log folder'                                             = 'Åpne loggmappen'
    'Clear history'                                               = 'Tøm historikken'
    'Clear the history?'                                          = 'Tømme historikken?'
    'This removes the list of what the app has done. It does not undo anything on your PC.' = 'Dette fjerner listen over hva appen har gjort. Ingenting blir endret på PC-en din.'
    'Clear'                                                       = 'Tøm'
    'Cancel'                                                      = 'Avbryt'
}

Register-Feature @{
    Name    = 'History'
    Section = 'info'
    Order   = 20
    Glyph   = 'E81C'
    Title   = 'History'
    Desc    = 'See what this app has done on your PC, and when.'
    Panel   = 'PanelHistory'
    Open    = { Open-History }
    Init    = {
        $ui.BtnHistFolder.Add_Click({
            if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force $DataDir | Out-Null }
            Start-Process explorer.exe -ArgumentList "`"$DataDir`""
        })
        $ui.BtnHistClear.Add_Click({ Clear-AppHistory })
    }
    Xaml    = @"
          <DockPanel x:Name="PanelHistory" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnHistClear" DockPanel.Dock="Right" Content="$(X 'Clear history')"/>
                <Button x:Name="BtnHistFolder" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE838;" VerticalAlignment="Center"/>
                    <TextBlock Text="$(X 'Open log folder')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <StackPanel x:Name="HistEmpty" HorizontalAlignment="Center" Margin="0,60,0,0" MaxWidth="480" Visibility="Collapsed">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE81C;" FontSize="44" Foreground="{DynamicResource Faint}" HorizontalAlignment="Center"/>
                  <TextBlock Text="$(X 'Nothing here yet')" FontSize="20" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,14,0,0"/>
                  <TextBlock Text="$(X 'When you update, clean up or fix something, it shows up here.')" Style="{StaticResource MutedText}" TextAlignment="Center" Margin="0,6,0,0"/>
                </StackPanel>
                <StackPanel x:Name="HistList"/>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>
"@
}

function Open-History {
    Show-Page 'PanelHistory' (T 'History') (T 'Everything this app has done on your PC, newest first.')
    Show-AppHistory
}

function Show-AppHistory {
    $ui.HistList.Children.Clear()
    $items = Get-History -Max 500   # already an array; @() around it would nest it
    if ($null -eq $items) { $items = @() }
    $ui.HistEmpty.Visibility = if ($items.Count) { 'Collapsed' } else { 'Visible' }
    $ui.BtnHistClear.IsEnabled = ($items.Count -gt 0)
    if (-not $items.Count) { return }

    $looks = @{
        ok    = @('E930', 'Good')
        warn  = @('E7BA', 'Warn')
        error = @('EA39', 'Bad')
        info  = @('E946', 'Accent')
    }
    $today = (Get-Date).Date
    foreach ($day in @($items | Group-Object { $_.Time.Date.ToString('yyyy-MM-dd') })) {
        $date = $day.Group[0].Time.Date
        $label = if ($date -eq $today) { T 'Today' }
                 elseif ($date -eq $today.AddDays(-1)) { T 'Yesterday' }
                 elseif ($Lang -eq 'nb') { $date.ToString('dddd d. MMMM yyyy', $Culture) }
                 else { $date.ToString('dddd d MMMM yyyy', $Culture) }
        if ($label.Length) { $label = $label.Substring(0, 1).ToUpper($Culture) + $label.Substring(1) }
        $first = ($ui.HistList.Children.Count -eq 0)
        [void]$ui.HistList.Children.Add((New-Xaml "<TextBlock Text=`"$(Esc $label)`" FontSize=`"16`" FontWeight=`"SemiBold`" Margin=`"0,$(if ($first) { 4 } else { 18 }),0,8`"/>"))

        $card = New-Xaml '<Border Style="{StaticResource Card}" Padding="18,2"><StackPanel/></Border>'
        $n = 0
        foreach ($h in $day.Group) {
            $look = $looks[[string]$h.State]
            if (-not $look) { $look = $looks.info }
            $border = if ($n -eq 0) { '0' } else { '0,1,0,0' }
            $n++
            $badge = if ($h.Source -eq 'auto') {
                "<Border Background=`"{DynamicResource AccentLight}`" CornerRadius=`"8`" Padding=`"8,1`" Margin=`"10,0,0,0`" VerticalAlignment=`"Center`" ToolTip=`"$(X 'Done automatically by scheduled maintenance')`"><TextBlock Text=`"$(X 'Automatic')`" FontSize=`"11`" Foreground=`"{DynamicResource Accent}`"/></Border>"
            } else { '' }
            $detail = if ($h.Detail) { "<TextBlock Text=`"$(Esc $h.Detail)`" Foreground=`"{DynamicResource Muted}`" FontSize=`"13`" TextWrapping=`"Wrap`" Margin=`"0,3,0,0`"/>" } else { '' }
            $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="$border" Padding="0,11">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="32"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <TextBlock FontFamily="{StaticResource Icons}" Text="&#x$($look[0]);" FontSize="16" Foreground="{DynamicResource $($look[1])}" VerticalAlignment="Top" Margin="0,2,0,0"/>
    <StackPanel Grid.Column="1">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="$(Esc $h.Title)" FontWeight="SemiBold" VerticalAlignment="Center"/>
        $badge
      </StackPanel>
      $detail
    </StackPanel>
    <TextBlock Grid.Column="2" Text="$(Esc $h.Time.ToString('HH:mm', $Culture))" Foreground="{DynamicResource Muted}" FontSize="12" Margin="16,2,0,0" VerticalAlignment="Top"/>
  </Grid>
</Border>
"@
            [void]$card.Child.Children.Add($row)
        }
        [void]$ui.HistList.Children.Add($card)
    }
}

function Clear-AppHistory {
    $d = Show-Dialog -Title (T 'Clear the history?') -Icon question `
        -Message (T 'This removes the list of what the app has done. It does not undo anything on your PC.') `
        -Buttons 'Clear', 'Cancel'
    if ($d.Button -ne 'Clear') { return }
    Remove-Item -LiteralPath $HistoryFile -Force -ErrorAction SilentlyContinue
    Show-AppHistory
}
