# Automatic maintenance: a scheduled task runs "PC Maintenance.exe --auto" (MaintainGui.ps1 -Auto),
# which updates apps / Windows and removes temporary files without a window, then shows a notification
# and writes a History entry. Settings live in HKCU:\Software\PCMaintenance (Auto*).

Add-Strings @{
    'Automatic maintenance' = 'Automatisk vedlikehold'
    'Keep this PC up to date by itself, once a week.' = 'Hold PC-en oppdatert av seg selv, én gang i uken.'
    'Let PC Maintenance look after this PC by itself. You get a notification when it has finished.' = 'La PC Maintenance ta vare på denne PC-en av seg selv. Du får et varsel når den er ferdig.'
    'Keep this PC up to date automatically' = 'Hold denne PC-en oppdatert automatisk'
    'Runs quietly in the background. You can keep working while it runs.' = 'Kjører stille i bakgrunnen. Du kan jobbe som vanlig imens.'
    'When' = 'Når'
    'If the PC is off or asleep at that time, it runs the next time you use it.' = 'Hvis PC-en er av eller i dvale da, kjøres det neste gang du bruker den.'
    'Every day' = 'Hver dag'
    'Every Monday' = 'Hver mandag'
    'Every Tuesday' = 'Hver tirsdag'
    'Every Wednesday' = 'Hver onsdag'
    'Every Thursday' = 'Hver torsdag'
    'Every Friday' = 'Hver fredag'
    'Every Saturday' = 'Hver lørdag'
    'Every Sunday' = 'Hver søndag'
    'What to do' = 'Hva som skal gjøres'
    'Update apps' = 'Oppdater apper'
    'Install Windows updates, drivers and virus definitions' = 'Installer Windows-oppdateringer, drivere og virusdefinisjoner'
    'Needs administrator rights when you save.' = 'Krever administratorrettigheter når du lagrer.'
    'Remove temporary files' = 'Fjern midlertidige filer'
    'Never restarts your PC by itself. If a restart is needed, the notification tells you.' = 'Starter aldri PC-en på nytt av seg selv. Hvis en omstart trengs, sier varselet fra.'
    'Run now' = 'Kjør nå'
    'Next run: {0}' = 'Neste kjøring: {0}'
    'Last run: {0}' = 'Siste kjøring: {0}'
    'Automatic maintenance is off.' = 'Automatisk vedlikehold er slått av.'
    'Not run yet.' = 'Ikke kjørt ennå.'
    'Windows updates need administrator rights' = 'Windows-oppdateringer krever administratorrettigheter'
    'To install Windows updates automatically, save this as administrator. Or continue with app updates and cleanup only.' = 'For å installere Windows-oppdateringer automatisk må du lagre som administrator. Eller fortsett med bare appoppdateringer og opprydding.'
    'Setting up automatic maintenance' = 'Å sette opp automatisk vedlikehold'
    'Automatic maintenance turned on' = 'Automatisk vedlikehold slått på'
    'Automatic maintenance turned off' = 'Automatisk vedlikehold slått av'
    '{0} at {1}' = '{0} kl. {1}'
    'Started. You get a notification when it has finished.' = 'Startet. Du får et varsel når det er ferdig.'
    "Couldn't save: {0}" = 'Kunne ikke lagre: {0}'
    'Apps: {0}' = 'Apper: {0}'
    'Windows: {0}' = 'Windows: {0}'
    'Virus protection: {0}' = 'Virusbeskyttelse: {0}'
    'Microsoft Store: {0}' = 'Microsoft Store: {0}'
    'Temporary files: freed {0}' = 'Midlertidige filer: frigjorde {0}'
    'Windows updates skipped (needs administrator)' = 'Windows-oppdateringer hoppet over (krever administrator)'
    'Nothing to do.' = 'Ingenting å gjøre.'
    'Your PC is up to date.' = 'PC-en din er oppdatert.'
    'Finished, but something needs your attention. Open PC Maintenance > History.' = 'Ferdig, men noe trenger oppmerksomheten din. Åpne PC Maintenance > Historikk.'
    'Restart your PC to finish installing updates.' = 'Start PC-en på nytt for å fullføre installasjonen av oppdateringer.'
    'Keep this PC up to date and tidy' = 'Hold denne PC-en oppdatert og ryddig'
    'Install PC Maintenance?' = 'Vil du installere PC Maintenance?'
    'Install it on this PC to add it to the Start menu and keep it up to date automatically. It only takes a moment, and no administrator rights are needed.' = 'Installer den på denne PC-en for å legge den til i Start-menyen og holde den oppdatert automatisk. Det tar et øyeblikk, og du trenger ikke administratorrettigheter.'
    'Install' = 'Installer'
    'Just run it this time' = 'Bare kjør den denne gangen'
    "Don't ask again" = 'Ikke spør igjen'
    'Installing failed: {0}' = 'Installasjonen mislyktes: {0}'
    'PC Maintenance installed' = 'PC Maintenance installert'
    'Remove PC Maintenance from this PC?' = 'Vil du fjerne PC Maintenance fra denne PC-en?'
    'PC Maintenance was removed.' = 'PC Maintenance er fjernet.'
    'Updated PC Maintenance to version {0}' = 'Oppdaterte PC Maintenance til versjon {0}'
    'PC Maintenance was updated to version {0}. Restart the app to start using it.' = 'PC Maintenance er oppdatert til versjon {0}. Start appen på nytt for å ta den i bruk.'
}

$AutoDays = 'Every day', 'Every Monday', 'Every Tuesday', 'Every Wednesday', 'Every Thursday', 'Every Friday', 'Every Saturday', 'Every Sunday'
$AutoTimes = '08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00', '22:00'

Register-Feature @{
    Name    = 'Auto'
    Section = 'settings'
    Order   = 10
    Glyph   = 'E787'
    Title   = 'Automatic maintenance'
    Desc    = 'Keep this PC up to date by itself, once a week.'
    Panel   = 'PanelAuto'
    Open    = { Open-Auto }
    Xaml    = @"
          <DockPanel x:Name="PanelAuto" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnAutoSave" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="$(X 'Save changes')"/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnAutoRunNow" Content="$(X 'Run now')"/>
                  <StackPanel x:Name="AutoSaved" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0" Visibility="Collapsed">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE73E;" Foreground="{DynamicResource Good}" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TxtAutoSaved" Text="$(X 'Saved')" Foreground="{DynamicResource Good}" FontWeight="SemiBold" Margin="8,0,0,0"/>
                  </StackPanel>
                </StackPanel>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24" MaxWidth="760" HorizontalAlignment="Left">
                <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                  <StackPanel>
                    <CheckBox x:Name="ChkAutoOn" FontSize="16" FontWeight="SemiBold" Content="$(X 'Keep this PC up to date automatically')"/>
                    <TextBlock Style="{StaticResource MutedText}" Margin="26,4,0,0" Text="$(X 'Runs quietly in the background. You can keep working while it runs.')"/>
                    <Border Background="{DynamicResource MonoBg}" CornerRadius="6" Padding="12,10" Margin="0,14,0,0">
                      <StackPanel>
                        <TextBlock x:Name="TxtAutoNext" FontWeight="SemiBold"/>
                        <TextBlock x:Name="TxtAutoLast" Style="{StaticResource MutedText}" Margin="0,4,0,0"/>
                      </StackPanel>
                    </Border>
                  </StackPanel>
                </Border>
                <StackPanel x:Name="AutoOptions">
                  <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                    <StackPanel>
                      <TextBlock Text="$(X 'When')" Style="{StaticResource CardTitle}"/>
                      <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                        <ComboBox x:Name="CmbAutoDay" Width="220"/>
                        <ComboBox x:Name="CmbAutoTime" Width="120" Margin="10,0,0,0"/>
                      </StackPanel>
                      <TextBlock Style="{StaticResource MutedText}" Margin="0,10,0,0" Text="$(X 'If the PC is off or asleep at that time, it runs the next time you use it.')"/>
                    </StackPanel>
                  </Border>
                  <Border Style="{StaticResource Card}">
                    <StackPanel>
                      <TextBlock Text="$(X 'What to do')" Style="{StaticResource CardTitle}"/>
                      <CheckBox x:Name="ChkAutoApps" Margin="0,6,0,0" Content="$(X 'Update apps')"/>
                      <CheckBox x:Name="ChkAutoWindows" Margin="0,10,0,0">
                        <StackPanel>
                          <TextBlock Text="$(X 'Install Windows updates, drivers and virus definitions')"/>
                          <TextBlock x:Name="TxtAutoWinNote" Style="{StaticResource MutedText}" FontSize="12" Text="$(X 'Needs administrator rights when you save.')"/>
                        </StackPanel>
                      </CheckBox>
                      <CheckBox x:Name="ChkAutoClean" Margin="0,10,0,0" Content="$(X 'Remove temporary files')"/>
                      <TextBlock Style="{StaticResource MutedText}" Margin="0,14,0,0" Text="$(X 'Never restarts your PC by itself. If a restart is needed, the notification tells you.')"/>
                    </StackPanel>
                  </Border>
                </StackPanel>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>
"@
    Init    = {
        foreach ($d in $AutoDays) { [void]$ui.CmbAutoDay.Items.Add((T $d)) }
        foreach ($t in $AutoTimes) { [void]$ui.CmbAutoTime.Items.Add($t) }
        $ui.BtnAutoSave.Add_Click({ Save-Auto })
        $ui.BtnAutoRunNow.Add_Click({ Start-AutoNow })
        $ui.ChkAutoOn.Add_Click({ Update-AutoEnabledState; $ui.AutoSaved.Visibility = 'Collapsed' })
        foreach ($c in 'ChkAutoApps', 'ChkAutoWindows', 'ChkAutoClean') { $ui[$c].Add_Click({ $ui.AutoSaved.Visibility = 'Collapsed' }) }
        foreach ($c in 'CmbAutoDay', 'CmbAutoTime') { $ui[$c].Add_SelectionChanged({ $ui.AutoSaved.Visibility = 'Collapsed' }) }
    }
}

function Get-AutoTask { Get-ScheduledTask -TaskName $AutoTaskName -ErrorAction SilentlyContinue }

function Open-Auto {
    Show-Page 'PanelAuto' (T 'Automatic maintenance') (T 'Let PC Maintenance look after this PC by itself. You get a notification when it has finished.')
    $task = Get-AutoTask
    $ui.ChkAutoOn.IsChecked = [bool]$task
    $ui.CmbAutoDay.SelectedIndex = [int](Get-AppSetting 'AutoDay' 3)
    $time = Get-AppSetting 'AutoTime' '12:00'
    $ui.CmbAutoTime.SelectedIndex = [math]::Max(0, [array]::IndexOf($AutoTimes, $time))
    $ui.ChkAutoApps.IsChecked = [bool](Get-AppSetting 'AutoApps' 1)
    $ui.ChkAutoWindows.IsChecked = [bool](Get-AppSetting 'AutoWindows' 1)
    $ui.ChkAutoClean.IsChecked = [bool](Get-AppSetting 'AutoClean' 1)
    $ui.TxtAutoWinNote.Visibility = if (Test-IsAdmin) { 'Collapsed' } else { 'Visible' }
    $ui.AutoSaved.Visibility = 'Collapsed'
    Update-AutoEnabledState
    Update-AutoStatus
}

function Update-AutoEnabledState {
    $on = [bool]$ui.ChkAutoOn.IsChecked
    $ui.AutoOptions.IsEnabled = $on   # controls dim themselves when disabled
}

function Update-AutoStatus {
    $task = Get-AutoTask
    $ui.BtnAutoRunNow.IsEnabled = [bool]$task
    if (-not $task) {
        $ui.TxtAutoNext.Text = T 'Automatic maintenance is off.'
    } else {
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $next = if ($info -and $info.NextRunTime) { $info.NextRunTime.ToString('dddd d. MMM HH:mm', $Culture) } else { '-' }
        $ui.TxtAutoNext.Text = (T 'Next run: {0}') -f $next
    }
    $hist = Get-History -Max 300   # returns the list as one array
    $last = $hist | Where-Object { $_.Source -eq 'auto' } | Select-Object -First 1
    $ui.TxtAutoLast.Text = if ($last) {
        (T 'Last run: {0}') -f ('{0} - {1}' -f $last.Time.ToString('dddd d. MMM HH:mm', $Culture), (($last.Detail -split "`n")[0]))
    } else { T 'Not run yet.' }
}

function Save-Auto {
    $ui.AutoSaved.Visibility = 'Collapsed'
    $on = [bool]$ui.ChkAutoOn.IsChecked
    $wantWindows = [bool]$ui.ChkAutoWindows.IsChecked
    $admin = Test-IsAdmin
    $existing = Get-AutoTask

    # An elevated task can only be changed by an administrator
    if ($existing -and $existing.Principal.RunLevel -eq 'Highest' -and -not $admin) {
        if (-not (Confirm-Admin (T 'Setting up automatic maintenance'))) { return }
    }
    if ($on -and $wantWindows -and -not $admin) {
        $d = Show-Dialog -Title (T 'Windows updates need administrator rights') -Icon shield `
            -Message (T 'To install Windows updates automatically, save this as administrator. Or continue with app updates and cleanup only.') `
            -Buttons 'Run as administrator', 'Continue without', 'Cancel'
        if ($d.Button -eq 'Run as administrator') { Restart-AsAdmin; return }
        if ($d.Button -ne 'Continue without') { return }
        $wantWindows = $false
        $ui.ChkAutoWindows.IsChecked = $false
    }

    $day = [math]::Max(0, $ui.CmbAutoDay.SelectedIndex)
    $time = $AutoTimes[[math]::Max(0, $ui.CmbAutoTime.SelectedIndex)]
    Set-AppSetting 'AutoDay' $day
    Set-AppSetting 'AutoTime' $time
    Set-AppSetting 'AutoApps' ([int][bool]$ui.ChkAutoApps.IsChecked)
    Set-AppSetting 'AutoWindows' ([int]$wantWindows)
    Set-AppSetting 'AutoClean' ([int][bool]$ui.ChkAutoClean.IsChecked)

    try {
        if ($on) {
            Register-AutoTask -Day $day -Time $time -Elevated:($admin -and $wantWindows)
            Add-History -Title (T 'Automatic maintenance turned on') -State info -Detail ((T '{0} at {1}') -f (T $AutoDays[$day]), $time)
        } elseif ($existing) {
            Unregister-ScheduledTask -TaskName $AutoTaskName -Confirm:$false
            Add-History -Title (T 'Automatic maintenance turned off') -State info
        }
    } catch {
        Show-Error ((T "Couldn't save: {0}") -f $_.Exception.Message)
        return
    }
    $ui.TxtAutoSaved.Text = T 'Saved'
    $ui.AutoSaved.Visibility = 'Visible'
    Update-AutoStatus
}

function Register-AutoTask([int]$Day, [string]$Time, [switch]$Elevated) {
    $exe = Join-Path $AppDir 'PC Maintenance.exe'
    $action = if (Test-Path -LiteralPath $exe) {
        New-ScheduledTaskAction -Execute $exe -Argument '--auto' -WorkingDirectory $AppDir
    } else {
        New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
            -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$SelfPath`" -Auto -NoUpdate" -WorkingDirectory $AppDir
    }
    $at = [datetime]::Today.Add([timespan]::Parse($Time))
    $trigger = if ($Day -eq 0) { New-ScheduledTaskTrigger -Daily -At $at }
               else { New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek ([DayOfWeek]($Day % 7)) -At $at }
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 4) -MultipleInstances IgnoreNew
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $(if ($Elevated) { 'Highest' } else { 'Limited' })
    Register-ScheduledTask -TaskName $AutoTaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
        -Description 'PC Maintenance: automatic updates and cleanup' -Force | Out-Null
}

function Start-AutoNow {
    Start-ScheduledTask -TaskName $AutoTaskName
    $ui.TxtAutoSaved.Text = T 'Started. You get a notification when it has finished.'
    $ui.AutoSaved.Visibility = 'Visible'
}

# Windows notification ("toast") under the app's own name and icon (registered by Register-AppIdentity)
function Show-Toast([string]$Title, [string]$Text) {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast><visual><binding template=`"ToastGeneric`"><text>$(Esc $Title)</text><text>$(Esc $Text)</text></binding></visual></toast>")
        $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('PCMaintenance').Show($toast)
    } catch {}
}

# -Auto: runs without a window (started by the scheduled task)
function Invoke-AutoMaintenance {
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force $DataDir | Out-Null }
    $logFile = Join-Path $DataDir 'auto-last.log'
    Set-Content -LiteralPath $logFile -Value ("Automatic maintenance {0:yyyy-MM-dd HH:mm}" -f (Get-Date)) -Encoding UTF8
    # Engine functions report through these; here they go to a log file
    function Log([string]$Message, [string]$Kind = 'info') { Add-Content -LiteralPath $logFile -Value $Message -Encoding UTF8 }
    function SetStatus { }
    function Step { }

    try { Register-AppIdentity } catch {}
    $admin = Test-IsAdmin
    $lines = @(); $state = 'ok'

    if ([int](Get-AppSetting 'AutoApps' 1)) {
        try {
            $pkgs = @(Get-WingetUpgrades)
            if ($pkgs.Count) {
                $failed = @(Invoke-WingetUpgradeSet -Packages $pkgs)
                $txt = (T '{0} of {1} updated, {2} could not be updated') -f ($pkgs.Count - $failed.Count), $pkgs.Count, $failed.Count
                if ($failed.Count) { $state = 'warn'; $txt += ' (' + (($failed | ForEach-Object { $_.Name }) -join ', ') + ')' }
                $lines += (T 'Apps: {0}') -f $txt
            } else { $lines += (T 'Apps: {0}') -f (T 'All apps are up to date') }
        } catch { $state = 'error'; $lines += (T 'Apps: {0}') -f $_.Exception.Message }
    }

    if ([int](Get-AppSetting 'AutoWindows' 1)) {
        if ($admin) {
            foreach ($s in @(
                    @{ Fn = 'Update-WindowsUpdate'; Label = 'Windows: {0}' }
                    @{ Fn = 'Update-Defender'; Label = 'Virus protection: {0}' }
                    @{ Fn = 'Update-StoreApps'; Label = 'Microsoft Store: {0}' })) {
                $ctx = @{ State = 'ok'; Text = ''; Out = @{} }
                try { & $s.Fn $ctx; if ($ctx.State -eq 'warn') { $state = 'warn' } }
                catch { $ctx.Text = $_.Exception.Message; if ($state -ne 'error') { $state = 'warn' } }
                $lines += (T $s.Label) -f $ctx.Text
            }
        } else {
            $lines += T 'Windows updates skipped (needs administrator)'
        }
    }

    if ([int](Get-AppSetting 'AutoClean' 1)) {
        try {
            $freed = Clear-FolderContents $env:TEMP
            if ($admin) { $freed += Clear-FolderContents (Join-Path $env:windir 'Temp') }
            $lines += (T 'Temporary files: freed {0}') -f (Format-Bytes $freed)
        } catch { $lines += $_.Exception.Message }
    }

    if (-not $lines.Count) { $lines += T 'Nothing to do.' }
    $reboot = $false
    try { $reboot = Test-RebootNeeded } catch {}
    Add-History -Title (T 'Automatic maintenance') -State $state -Detail ($lines -join "`n") -Source auto

    $headline = if ($state -eq 'ok') { T 'Your PC is up to date.' } else { T 'Finished, but something needs your attention. Open PC Maintenance > History.' }
    if ($reboot) { $headline += ' ' + (T 'Restart your PC to finish installing updates.') }
    Show-Toast (T 'Automatic maintenance') $headline
}
