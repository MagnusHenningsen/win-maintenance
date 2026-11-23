# Printer problems: list printers and waiting documents, clear a queue, or restart the print service.

Add-Strings @{
    'Printer problems'                                      = 'Skriverproblemer'
    'Clear stuck print jobs and restart printing.'          = 'Fjern utskrifter som henger, og start utskrift på nytt.'
    'See your printers and fix documents that are stuck.'   = 'Se skriverne dine og fiks dokumenter som henger.'
    'Looking for printers...'                               = 'Ser etter skrivere...'
    'Open printer settings'                                 = 'Åpne skriverinnstillinger'
    'Fix printing'                                          = 'Fiks utskrift'
    'Refresh'                                               = 'Oppdater'
    'Clear queue'                                           = 'Tøm køen'
    'Default printer'                                       = 'Standardskriver'
    'Built in, not a real printer'                          = 'Innebygd, ikke en ekte skriver'
    'Ready'                                                 = 'Klar'
    'Paused'                                                = 'Satt på pause'
    'Has an error'                                          = 'Har en feil'
    'Offline (turned off or not connected)'                 = 'Frakoblet (slått av eller ikke tilkoblet)'
    'Paper jam'                                             = 'Papirstopp'
    'Out of paper'                                          = 'Tomt for papir'
    'Paper problem'                                         = 'Papirproblem'
    'Toner is low'                                          = 'Lite toner'
    'Out of toner'                                          = 'Tomt for toner'
    'A door is open'                                        = 'En luke er åpen'
    'Printing'                                              = 'Skriver ut'
    'Sleeping (power save)'                                 = 'Hviler (strømsparing)'
    'Needs attention at the printer'                        = 'Trenger tilsyn ved skriveren'
    'Not available'                                         = 'Ikke tilgjengelig'
    'Warming up'                                            = 'Varmer opp'
    'Waiting'                                               = 'Venter'
    'No documents waiting'                                  = 'Ingen dokumenter venter'
    '1 document waiting'                                    = '1 dokument venter'
    '{0} documents waiting'                                 = '{0} dokumenter venter'
    'No printers are installed.'                            = 'Ingen skrivere er installert.'
    'The Windows print service is running.'                 = 'Utskriftstjenesten i Windows kjører.'
    'The Windows print service is stopped, so nothing can print. Fix printing starts it again.' = 'Utskriftstjenesten i Windows er stoppet, så ingenting kan skrives ut. «Fiks utskrift» starter den igjen.'
    'The Windows print service is missing on this PC. Contact IT.' = 'Utskriftstjenesten i Windows mangler på denne PC-en. Kontakt IT.'
    'If a document is stuck and nothing prints, Fix printing deletes all waiting documents and restarts the Windows print service. Send your documents to the printer again afterwards.' = 'Hvis et dokument henger og ingenting skrives ut, sletter «Fiks utskrift» alle ventende dokumenter og starter utskriftstjenesten i Windows på nytt. Send dokumentene til skriveren på nytt etterpå.'
    "Couldn't read the printers: {0}"                       = 'Klarte ikke å lese skriverne: {0}'
    'Fixing printing'                                       = 'Fikser utskrift'
    'Fix printing?'                                         = 'Fikse utskrift?'
    'This deletes all documents that are waiting to print and restarts the Windows print service. You can print them again afterwards.' = 'Dette sletter alle dokumenter som venter på utskrift, og starter utskriftstjenesten i Windows på nytt. Du kan skrive dem ut igjen etterpå.'
    'Cancel'                                                = 'Avbryt'
    'Stop the print service'                                = 'Stopp utskriftstjenesten'
    'Delete stuck print jobs'                               = 'Slett utskrifter som henger'
    'Start the print service'                               = 'Start utskriftstjenesten'
    'Check printers'                                        = 'Sjekk skriverne'
    'Stopping the print service'                            = 'Stopper utskriftstjenesten'
    'Deleting stuck print jobs'                             = 'Sletter utskrifter som henger'
    'Starting the print service'                            = 'Starter utskriftstjenesten'
    'Checking printers'                                     = 'Sjekker skriverne'
    'Stopped'                                               = 'Stoppet'
    'Started'                                               = 'Startet'
    'Nothing was stuck'                                     = 'Ingenting hang'
    'Deleted {0} print job(s)'                              = 'Slettet {0} utskrift(er)'
    '{0} could not be deleted'                              = '{0} kunne ikke slettes'
    '{0} printer(s) ready'                                  = '{0} skriver(e) klar(e)'
    'Still a problem: {0}'                                  = 'Fortsatt problem: {0}'
    'Not checked, the print service is not running'         = 'Ikke sjekket, utskriftstjenesten kjører ikke'
    'Printing should work again. Send your documents to the printer again.' = 'Utskrift skal virke igjen. Send dokumentene til skriveren på nytt.'
    'Clear the print queue?'                                = 'Tømme utskriftskøen?'
    'All documents waiting to print on "{0}" will be deleted.' = 'Alle dokumenter som venter på utskrift på «{0}», blir slettet.'
    'Some documents could not be removed'                   = 'Noen dokumenter kunne ikke fjernes'
    'Documents from other users need administrator rights. Fix printing (as administrator) removes them for sure.' = 'Dokumenter fra andre brukere krever administratorrettigheter. «Fiks utskrift» (som administrator) fjerner dem helt sikkert.'
    'Cleared print queue'                                   = 'Tømte utskriftskø'
    '{0}: removed {1} document(s)'                          = '{0}: fjernet {1} dokument(er)'
}

$PrinterXaml = @"
          <DockPanel x:Name="PanelPrinter" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnPrnFix" DockPanel.Dock="Right" Style="{StaticResource Primary}">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xEA18;" VerticalAlignment="Center"/>
                    <TextBlock Text="$(X 'Fix printing')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnPrnSettings" Content="$(X 'Open printer settings')"/>
                  <Button x:Name="BtnPrnRefresh" Margin="8,0,0,0">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE72C;" VerticalAlignment="Center"/>
                      <TextBlock Text="$(X 'Refresh')" Margin="8,0,0,0"/>
                    </StackPanel>
                  </Button>
                </StackPanel>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <TextBlock x:Name="TxtPrnLoading" Text="$(X 'Looking for printers...')" Style="{StaticResource MutedText}"/>
                <StackPanel x:Name="PrnContent" Visibility="Collapsed">
                  <Border x:Name="PrnSpooler" CornerRadius="8" Padding="16" BorderThickness="1" Margin="0,0,0,12">
                    <DockPanel>
                      <TextBlock x:Name="PrnSpoolerIcon" FontFamily="{StaticResource Icons}" FontSize="20" VerticalAlignment="Top" Margin="0,0,12,0"/>
                      <TextBlock x:Name="TxtPrnSpooler" TextWrapping="Wrap" VerticalAlignment="Center"/>
                    </DockPanel>
                  </Border>
                  <Border Style="{StaticResource Card}" Padding="18,4">
                    <StackPanel x:Name="PrnList"/>
                  </Border>
                  <TextBlock Style="{StaticResource MutedText}" Margin="2,14,0,0"
                             Text="$(X 'If a document is stuck and nothing prints, Fix printing deletes all waiting documents and restarts the Windows print service. Send your documents to the printer again afterwards.')"/>
                </StackPanel>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>
"@

Register-Feature @{
    Name    = 'Printer'
    Section = 'fix'
    Order   = 20
    Glyph   = 'E749'
    Title   = 'Printer problems'
    Desc    = 'Clear stuck print jobs and restart printing.'
    Open    = { Open-Printer }
    Panel   = 'PanelPrinter'
    Xaml    = $PrinterXaml
    Init    = {
        $ui.BtnPrnFix.Add_Click({ Start-PrinterFix })
        $ui.BtnPrnSettings.Add_Click({ Start-Process 'ms-settings:printers' })
        $ui.BtnPrnRefresh.Add_Click({ Update-PrinterList })
    }
    Engine  = {
        # Printer status in plain words (Get-Printer's PrinterStatus can combine several flags).
        function Get-PrinterStatusText([string]$Status) {
            $map = [ordered]@{
                'PaperJam' = 'Paper jam'; 'PaperOut' = 'Out of paper'; 'PaperProblem' = 'Paper problem'
                'NoToner' = 'Out of toner'; 'TonerLow' = 'Toner is low'; 'DoorOpen' = 'A door is open'
                'Offline' = 'Offline (turned off or not connected)'; 'Error' = 'Has an error'; 'Paused' = 'Paused'
                'UserIntervention' = 'Needs attention at the printer'; 'NotAvailable' = 'Not available'
                'Printing' = 'Printing'; 'Busy' = 'Printing'; 'Processing' = 'Printing'; 'IOActive' = 'Printing'
                'WarmingUp' = 'Warming up'; 'Waiting' = 'Waiting'; 'PowerSave' = 'Sleeping (power save)'
            }
            foreach ($k in $map.Keys) { if ($Status -match "\b$k\b") { return [pscustomobject]@{ Text = (T $map[$k]); Problem = ($k -notin 'Printing', 'Busy', 'Processing', 'IOActive', 'WarmingUp', 'Waiting', 'PowerSave') } } }
            [pscustomobject]@{ Text = (T 'Ready'); Problem = $false }
        }

        function Get-PrinterState {
            $sp = Get-Service Spooler -ErrorAction SilentlyContinue
            $spooler = if ($sp) { [string]$sp.Status } else { 'Missing' }
            $printers = @()
            if ($spooler -eq 'Running') {
                $default = (Get-CimInstance Win32_Printer -Filter 'Default=True' -ErrorAction SilentlyContinue | Select-Object -First 1).Name
                foreach ($p in @(Get-Printer -ErrorAction SilentlyContinue)) {
                    $jobs = @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue)
                    $st = Get-PrinterStatusText ([string]$p.PrinterStatus)
                    $virtual = ($p.PortName -in 'PORTPROMPT:', 'SHRFAX:', 'nul:', 'XPSPort:') -or
                               ($p.DriverName -match 'Microsoft Print To PDF|XPS Document Writer|Fax|OneNote')
                    $printers += [pscustomobject]@{
                        Name = $p.Name; Default = ($p.Name -eq $default); Status = $st.Text; Problem = $st.Problem
                        Jobs = $jobs.Count; Virtual = $virtual
                    }
                }
            }
            # Real printers first, the default one on top
            $printers = @($printers | Sort-Object @{ e = { $_.Virtual } }, @{ e = { -not $_.Default } }, Name)
            [pscustomobject]@{ Spooler = $spooler; Printers = $printers }
        }

        function Invoke-PrinterFix {
            $ErrorActionPreference = 'Stop'
            Step 'prn.stop' 'running'
            SetStatus (T 'Stopping the print service') 10
            try {
                Stop-Service Spooler -Force
                (Get-Service Spooler).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
                Step 'prn.stop' 'ok' (T 'Stopped')
            } catch { Step 'prn.stop' 'error' $_.Exception.Message; Log $_.Exception.Message 'error' }

            Step 'prn.clear' 'running'
            SetStatus (T 'Deleting stuck print jobs') 35
            $dir = Join-Path $env:windir 'System32\spool\PRINTERS'
            $files = @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue)
            $jobs = @($files | Where-Object { $_.Extension -eq '.SPL' }).Count
            $failed = 0
            foreach ($f in $files) {
                try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Log "Deleted $($f.Name)" 'detail' } catch { $failed++ }
            }
            if ($failed) { Step 'prn.clear' 'warn' ((T '{0} could not be deleted') -f $failed) }
            elseif ($jobs) { Step 'prn.clear' 'ok' ((T 'Deleted {0} print job(s)') -f $jobs) }
            else { Step 'prn.clear' 'ok' (T 'Nothing was stuck') }

            Step 'prn.start' 'running'
            SetStatus (T 'Starting the print service') 60
            try {
                Start-Service Spooler
                (Get-Service Spooler).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
                Step 'prn.start' 'ok' (T 'Started')
            } catch { Step 'prn.start' 'error' $_.Exception.Message; Log $_.Exception.Message 'error' }

            Step 'prn.check' 'running'
            SetStatus (T 'Checking printers') 85
            $st = Get-PrinterState
            if ($st.Spooler -ne 'Running') { Step 'prn.check' 'error' (T 'Not checked, the print service is not running'); return [pscustomobject]@{ Ok = $false } }
            $real = @($st.Printers | Where-Object { -not $_.Virtual })
            $bad = @($real | Where-Object { $_.Problem })
            if ($bad.Count) {
                Step 'prn.check' 'warn' ((T 'Still a problem: {0}') -f (($bad | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Status }) -join ', '))
            } else {
                Step 'prn.check' 'ok' ((T '{0} printer(s) ready') -f $real.Count)
            }
            [pscustomobject]@{ Ok = $true }
        }
    }
}

function Open-Printer {
    Show-Page 'PanelPrinter' (T 'Printer problems') (T 'See your printers and fix documents that are stuck.')
    Update-PrinterList
}

function Update-PrinterList {
    $ui.TxtPrnLoading.Text = T 'Looking for printers...'
    $ui.TxtPrnLoading.Visibility = 'Visible'
    $ui.PrnContent.Visibility = 'Collapsed'
    $ui.BtnPrnRefresh.IsEnabled = $false
    Start-Worker -Work { Get-PrinterState } -OnDone { param($r, $err) Show-PrinterList $r $err }
}

function Show-PrinterList($r, $err) {
    $ui.BtnPrnRefresh.IsEnabled = $true
    if ($err -or -not $r) { $ui.TxtPrnLoading.Text = (T "Couldn't read the printers: {0}") -f $err; return }
    $ui.TxtPrnLoading.Visibility = 'Collapsed'
    $ui.PrnContent.Visibility = 'Visible'

    $look = switch ($r.Spooler) {
        'Running' { @('E930', 'GoodBg', 'GoodLine', 'Good', (T 'The Windows print service is running.')) }
        'Missing' { @('EA39', 'BadBg', 'BadLine', 'Bad', (T 'The Windows print service is missing on this PC. Contact IT.')) }
        default   { @('EA39', 'BadBg', 'BadLine', 'Bad', (T 'The Windows print service is stopped, so nothing can print. Fix printing starts it again.')) }
    }
    $ui.PrnSpoolerIcon.Text = [string][char][Convert]::ToInt32($look[0], 16)
    Set-Themed $ui.PrnSpoolerIcon Foreground $look[3]
    Set-Themed $ui.PrnSpooler Background $look[1]
    Set-Themed $ui.PrnSpooler BorderBrush $look[2]
    $ui.TxtPrnSpooler.Text = $look[4]

    $ui.PrnList.Children.Clear()
    $list = @($r.Printers)
    if (-not $list.Count) {
        $msg = if ($r.Spooler -eq 'Running') { T 'No printers are installed.' } else { T 'The Windows print service is stopped, so nothing can print. Fix printing starts it again.' }
        [void]$ui.PrnList.Children.Add((New-Xaml "<TextBlock Text=`"$(Esc $msg)`" Foreground=`"{DynamicResource Muted}`" Margin=`"0,10`" TextWrapping=`"Wrap`"/>"))
        return
    }
    $first = $true
    foreach ($p in $list) {
        $border = if ($first) { '0' } else { '0,1,0,0' }
        $first = $false
        $jobsText = switch ($p.Jobs) { 0 { T 'No documents waiting' } 1 { T '1 document waiting' } default { (T '{0} documents waiting') -f $p.Jobs } }
        $sub = if ($p.Virtual) { T 'Built in, not a real printer' } else { '{0} - {1}' -f $p.Status, $jobsText }
        $iconKey = if ($p.Virtual) { 'Faint' } elseif ($p.Problem) { 'Warn' } else { 'Accent' }
        $subKey = if ($p.Problem -and -not $p.Virtual) { 'Warn' } else { 'Muted' }
        $badge = if ($p.Default) {
            "<Border Background=`"{DynamicResource AccentLight}`" CornerRadius=`"10`" Padding=`"8,1`" Margin=`"10,0,0,0`" VerticalAlignment=`"Center`"><TextBlock Text=`"$(X 'Default printer')`" FontSize=`"12`" Foreground=`"{DynamicResource Accent}`"/></Border>"
        } else { '' }
        $clearVis = if ($p.Jobs -gt 0) { 'Visible' } else { 'Collapsed' }
        $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="$border" Padding="0,12">
  <DockPanel>
    <Button DockPanel.Dock="Right" Content="$(X 'Clear queue')" Padding="12,5" VerticalAlignment="Center" Visibility="$clearVis"/>
    <TextBlock DockPanel.Dock="Left" FontFamily="Segoe MDL2 Assets" Text="&#xE749;" FontSize="20" Foreground="{DynamicResource $iconKey}" VerticalAlignment="Center" Margin="0,0,14,0"/>
    <StackPanel VerticalAlignment="Center">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="$(Esc $p.Name)" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
        $badge
      </StackPanel>
      <TextBlock Text="$(Esc $sub)" Foreground="{DynamicResource $subKey}" FontSize="13" Margin="0,2,0,0" TextWrapping="Wrap"/>
    </StackPanel>
  </DockPanel>
</Border>
"@
        $btn = $row.Child.Children[0]
        $btn.Tag = $p.Name
        $btn.Add_Click({ param($s, $e) Clear-PrinterQueue $s.Tag })
        [void]$ui.PrnList.Children.Add($row)
    }
}

function Clear-PrinterQueue([string]$Name) {
    $d = Show-Dialog -Title (T 'Clear the print queue?') -Message ((T 'All documents waiting to print on "{0}" will be deleted.') -f $Name) `
        -Buttons 'Clear queue', 'Cancel' -Icon question
    if ($d.Button -ne 'Clear queue') { return }
    Start-Worker -ArgumentList $Name -Work {
        param($n)
        $jobs = @(Get-PrintJob -PrinterName $n -ErrorAction SilentlyContinue)
        $failed = 0
        foreach ($j in $jobs) { try { Remove-PrintJob -InputObject $j -ErrorAction Stop } catch { $failed++ } }
        [pscustomobject]@{ Name = $n; Total = $jobs.Count; Failed = $failed }
    } -OnDone {
        param($r, $err)
        if ($err) { Show-Error $err }
        elseif ($r) {
            Add-History -Title (T 'Cleared print queue') -State $(if ($r.Failed) { 'warn' } else { 'ok' }) -Detail ((T '{0}: removed {1} document(s)') -f $r.Name, ($r.Total - $r.Failed))
            if ($r.Failed) {
                [void](Show-Dialog -Title (T 'Some documents could not be removed') -Icon warn `
                    -Message (T 'Documents from other users need administrator rights. Fix printing (as administrator) removes them for sure.'))
            }
        }
        Update-PrinterList
    }
}

function Start-PrinterFix {
    if (-not (Confirm-Admin (T 'Fixing printing'))) { return }
    $d = Show-Dialog -Title (T 'Fix printing?') -Icon question `
        -Message (T 'This deletes all documents that are waiting to print and restarts the Windows print service. You can print them again afterwards.') `
        -Buttons 'Fix printing', 'Cancel'
    if ($d.Button -ne 'Fix printing') { return }
    $script:Ctx = @{}
    Open-TaskPage (T 'Fixing printing') '' 'Printer'
    Add-TaskStep 'prn.stop' (T 'Stop the print service')
    Add-TaskStep 'prn.clear' (T 'Delete stuck print jobs')
    Add-TaskStep 'prn.start' (T 'Start the print service')
    Add-TaskStep 'prn.check' (T 'Check printers')
    Start-Flow @(
        {
            Start-TaskWork -Work { Invoke-PrinterFix } -OnDone {
                param($r, $err)
                if ($err) { Add-TaskLog "[X] $err" }
                if ($r -and $r.Ok) { $script:Ctx.Summary = T 'Printing should work again. Send your documents to the printer again.' }
                Invoke-NextStage
            }
        },
        { Complete-Task }
    )
}
