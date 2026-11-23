# Camera and microphone: checks camera, microphone, speakers and privacy settings before a meeting.

Add-Strings @{
    'Camera and microphone'                                        = 'Kamera og mikrofon'
    'Check your camera, microphone and speakers before a meeting.' = 'Sjekk kamera, mikrofon og høyttalere før et møte.'
    'Make sure others can see and hear you, and that you can hear them.' = 'Sørg for at andre kan se og høre deg, og at du hører dem.'
    'Checking your camera, microphone and speakers...'             = 'Sjekker kamera, mikrofon og høyttalere ...'
    'Camera'                                                       = 'Kamera'
    'Microphone'                                                   = 'Mikrofon'
    'Speakers and headset'                                         = 'Høyttalere og hodesett'
    'Privacy settings'                                             = 'Personverninnstillinger'
    'Open Camera app'                                              = 'Åpne Kamera-appen'
    'Unmute'                                                       = 'Slå på lyden'
    'Play test sound'                                              = 'Spill av testlyd'
    'Allow'                                                        = 'Tillat'
    'Open privacy settings'                                        = 'Åpne personverninnstillinger'
    'Check again' = 'Sjekk igjen'
    'Open sound settings'                                          = 'Åpne lydinnstillinger'
    'Ready'                                                        = 'Klar'
    'No camera found'                                              = 'Fant ikke noe kamera'
    "If you use an external camera, check that it's plugged in."  = 'Hvis du bruker et eksternt kamera, sjekk at det er koblet til.'
    'The camera has a problem'                                     = 'Kameraet har et problem'
    'Try unplugging it and plugging it back in, or restart your PC.' = 'Prøv å koble det fra og til igjen, eller start PC-en på nytt.'
    'In use by {0}'                                                = 'I bruk av {0}'
    "Only one app can use the camera at a time. If your meeting app can't see the camera, close {0} first." = 'Bare én app kan bruke kameraet om gangen. Hvis møteappen ikke finner kameraet, lukk {0} først.'
    'No microphone found'                                          = 'Fant ikke noen mikrofon'
    'Plug in a headset or microphone, or check that it is turned on.' = 'Koble til et hodesett eller en mikrofon, eller sjekk at den er slått på.'
    'Muted'                                                        = 'Lyden er av'
    "Others won't hear you until you unmute it."                  = 'Andre hører deg ikke før du slår på lyden.'
    "You won't hear anything until you unmute it."                = 'Du hører ingenting før du slår på lyden.'
    'Volume is very low ({0}%)'                                    = 'Volumet er veldig lavt ({0} %)'
    'Others may not hear you. Turn it up in Sound settings.'       = 'Andre hører deg kanskje ikke. Skru opp i lydinnstillingene.'
    'You may not hear the others. Turn the volume up.'             = 'Du hører kanskje ikke de andre. Skru opp volumet.'
    '{0} - volume {1}%'                                            = '{0} - volum {1} %'
    'Also in use by {0}'                                           = 'Brukes også av {0}'
    'No speakers or headset found'                                 = 'Fant ingen høyttalere eller hodesett'
    'Plug in a headset or speakers, or check that they are turned on.' = 'Koble til et hodesett eller høyttalere, eller sjekk at de er slått på.'
    'Camera and microphone are allowed'                            = 'Kamera og mikrofon er tillatt'
    'Apps are allowed to use your camera and microphone.'          = 'Apper har lov til å bruke kameraet og mikrofonen.'
    'Access to {0} is blocked for the whole PC'                          = 'Tilgang til {0} er blokkert for hele PC-en'
    'Someone with administrator rights (or IT) has turned it off. Open the privacy settings or contact IT.' = 'Noen med administratorrettigheter (eller IT) har slått det av. Åpne personverninnstillingene eller kontakt IT.'
    'Apps are not allowed to use {0}'                          = 'Apper har ikke lov til å bruke {0}'
    "Meeting apps can't see or hear you until you allow it."      = 'Møteapper kan ikke se eller høre deg før du tillater det.'
    'Desktop apps are not allowed to use {0}'                  = 'Skrivebordsapper har ikke lov til å bruke {0}'
    'Apps like Teams, Zoom and your browser need this to see or hear you.' = 'Apper som Teams, Zoom og nettleseren trenger dette for å se eller høre deg.'
    'your camera'                                                       = 'kameraet'
    'your microphone'                                                   = 'mikrofonen'
    'your camera and microphone'                                        = 'kameraet og mikrofonen'
    'Microphone unmuted'                                           = 'Mikrofonlyd slått på'
    'Speakers unmuted'                                             = 'Høyttalerlyd slått på'
    'Camera and microphone access allowed'                         = 'Tilgang til kamera og mikrofon tillatt'
    "Couldn't check: {0}"                                          = 'Kunne ikke sjekke: {0}'
    "Couldn't find a test sound on this PC."                      = 'Fant ingen testlyd på denne PC-en.'
}

$MeetCardsXaml = (@(
        @{ P = 'Cam';  Glyph = 'E714'; Title = 'Camera';               Buttons = @(@{ N = 'MeetBtnCamApp'; T = 'Open Camera app' }) }
        @{ P = 'Mic';  Glyph = 'E720'; Title = 'Microphone';           Buttons = @(@{ N = 'MeetBtnMicUnmute'; T = 'Unmute'; Primary = $true }) }
        @{ P = 'Spk';  Glyph = 'E767'; Title = 'Speakers and headset'; Buttons = @(@{ N = 'MeetBtnSpkUnmute'; T = 'Unmute'; Primary = $true }, @{ N = 'MeetBtnSpkTest'; T = 'Play test sound' }) }
        @{ P = 'Priv'; Glyph = 'EA18'; Title = 'Privacy settings';     Buttons = @(@{ N = 'MeetBtnPrivAllow'; T = 'Allow'; Primary = $true }, @{ N = 'MeetBtnPrivSettings'; T = 'Open privacy settings' }) }
    ) | ForEach-Object {
        $btns = ($_.Buttons | ForEach-Object {
            $style = if ($_.Primary) { ' Style="{StaticResource Primary}"' } else { '' }
            "<Button x:Name=`"$($_.N)`"$style Content=`"$(X $_.T)`" Margin=`"0,0,8,0`" Padding=`"14,6`" Visibility=`"Collapsed`"/>"
        }) -join "`n"
@"
                  <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                    <DockPanel>
                      <Border DockPanel.Dock="Left" Width="40" Height="40" CornerRadius="8" Background="{DynamicResource AccentLight}" VerticalAlignment="Top" Margin="0,0,16,0">
                        <TextBlock FontFamily="{StaticResource Icons}" Text="&#x$($_.Glyph);" FontSize="19" Foreground="{DynamicResource Accent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                      <StackPanel>
                        <TextBlock Text="$(X $_.Title)" Foreground="{DynamicResource Muted}" FontSize="13"/>
                        <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                          <TextBlock x:Name="Meet$($_.P)Icon" FontFamily="{StaticResource Icons}" FontSize="16" VerticalAlignment="Center" Margin="0,0,8,0"/>
                          <TextBlock x:Name="Meet$($_.P)Status" FontSize="17" FontWeight="SemiBold" TextWrapping="Wrap"/>
                        </StackPanel>
                        <TextBlock x:Name="Meet$($_.P)Detail" Style="{StaticResource MutedText}" Margin="0,4,0,0"/>
                        <WrapPanel Margin="0,10,0,0">
                          $btns
                        </WrapPanel>
                      </StackPanel>
                    </DockPanel>
                  </Border>
"@
    }) -join "`n"

Register-Feature @{
    Name    = 'Meeting'
    Section = 'fix'
    Order   = 30
    Glyph   = 'E714'
    Title   = 'Camera and microphone'
    Desc    = 'Check your camera, microphone and speakers before a meeting.'
    Panel   = 'PanelMeeting'
    Open    = { Open-Meeting }
    Init    = {
        $ui.MeetBtnRefresh.Add_Click({ Update-Meeting })
        $ui.MeetBtnSound.Add_Click({ Start-Process 'ms-settings:sound' })
        $ui.MeetBtnCamApp.Add_Click({ try { Start-Process 'microsoft.windows.camera:' } catch { Show-Error $_ } })
        $ui.MeetBtnMicUnmute.Add_Click({ Set-MeetMute -Capture $true })
        $ui.MeetBtnSpkUnmute.Add_Click({ Set-MeetMute -Capture $false })
        $ui.MeetBtnSpkTest.Add_Click({ Invoke-MeetTestSound })
        $ui.MeetBtnPrivAllow.Add_Click({ Grant-MeetPrivacy })
        $ui.MeetBtnPrivSettings.Add_Click({
            $uri = if ($script:MeetPrivSettingsUri) { $script:MeetPrivSettingsUri } else { 'ms-settings:privacy-webcam' }
            Start-Process $uri
        })
    }
    Xaml    = @"
          <DockPanel x:Name="PanelMeeting" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="MeetBtnSound" DockPanel.Dock="Right" Content="$(X 'Open sound settings')"/>
                <Button x:Name="MeetBtnRefresh" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE72C;" VerticalAlignment="Center"/>
                    <TextBlock Text="$(X 'Check again')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <StackPanel x:Name="MeetLoading" Margin="0,24,0,0">
                  <TextBlock Text="$(X 'Checking your camera, microphone and speakers...')" Style="{StaticResource MutedText}"/>
                  <ProgressBar IsIndeterminate="True" Width="260" HorizontalAlignment="Left" Margin="0,12,0,0"/>
                </StackPanel>
                <StackPanel x:Name="MeetContent" Visibility="Collapsed">
$MeetCardsXaml
                </StackPanel>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>
"@
    Engine  = {
        function Initialize-MeetAudio {
            if ('MaintGui.Audio' -as [type]) { return }
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MaintGui {
    public class AudioDeviceInfo { public bool Found; public string Name; public bool Muted; public float Volume; }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorCom { }

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        [PreserveSig] int OpenPropertyStore(int access, out IPropertyStore store);
    }

    [StructLayout(LayoutKind.Sequential)] struct PropertyKey { public Guid fmtid; public int pid; }

    [StructLayout(LayoutKind.Explicit, Size = 24)]
    struct PropVariant { [FieldOffset(0)] public short vt; [FieldOffset(8)] public IntPtr p; }

    [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetAt(int index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
    }

    [Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioEndpointVolume {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
        [PreserveSig] int GetChannelCount(out uint count);
        [PreserveSig] int SetMasterVolumeLevel(float db, ref Guid ctx);
        [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid ctx);
        [PreserveSig] int GetMasterVolumeLevel(out float db);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
        [PreserveSig] int SetChannelVolumeLevel(uint channel, float db, ref Guid ctx);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid ctx);
        [PreserveSig] int GetChannelVolumeLevel(uint channel, out float db);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid ctx);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    public static class Audio {
        [DllImport("ole32.dll")] static extern int PropVariantClear(ref PropVariant pv);

        // capture: microphone (communications role, like meeting apps); otherwise speakers (console role)
        static IMMDevice GetDevice(bool capture) {
            var en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            IMMDevice dev;
            int hr = en.GetDefaultAudioEndpoint(capture ? 1 : 0, capture ? 2 : 0, out dev);
            return hr == 0 ? dev : null;
        }

        static IAudioEndpointVolume GetVolume(IMMDevice dev) {
            Guid iid = typeof(IAudioEndpointVolume).GUID;
            object o;
            if (dev.Activate(ref iid, 23, IntPtr.Zero, out o) != 0) return null;
            return (IAudioEndpointVolume)o;
        }

        public static AudioDeviceInfo GetDefault(bool capture) {
            var info = new AudioDeviceInfo();
            var dev = GetDevice(capture);
            if (dev == null) return info;
            info.Found = true;
            IPropertyStore store;
            if (dev.OpenPropertyStore(0, out store) == 0) {
                var key = new PropertyKey { fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"), pid = 14 };
                PropVariant pv;
                if (store.GetValue(ref key, out pv) == 0) {
                    if (pv.vt == 31) info.Name = Marshal.PtrToStringUni(pv.p);
                    PropVariantClear(ref pv);
                }
            }
            var vol = GetVolume(dev);
            if (vol != null) {
                bool m; float l;
                if (vol.GetMute(out m) == 0) info.Muted = m;
                if (vol.GetMasterVolumeLevelScalar(out l) == 0) info.Volume = l;
            }
            return info;
        }

        public static bool SetMute(bool capture, bool mute) {
            var dev = GetDevice(capture);
            if (dev == null) return false;
            var vol = GetVolume(dev);
            if (vol == null) return false;
            Guid ctx = Guid.Empty;
            return vol.SetMute(mute, ref ctx) == 0;
        }
    }
}
'@
        }

        $MeetConsentRoot = 'Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'

        # Apps using the camera/microphone right now (LastUsedTimeStop = 0 while in use)
        function Get-MeetInUse([string]$Capability) {
            $base = "HKCU:\$MeetConsentRoot\$Capability"
            $keys = @(Get-ChildItem $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'NonPackaged' }) +
                    @(Get-ChildItem "$base\NonPackaged" -ErrorAction SilentlyContinue)
            $names = foreach ($k in $keys) {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if (-not $p -or -not ($p.LastUsedTimeStart -gt 0) -or $p.LastUsedTimeStop -ne 0) { continue }
                $id = $k.PSChildName
                if ($k.PSParentPath -like '*NonPackaged') {
                    $path = $id -replace '#', '\'
                    $desc = $null
                    try { $desc = (Get-Item -LiteralPath $path -ErrorAction Stop).VersionInfo.FileDescription } catch {}
                    if ($desc) { $desc.Trim() } else { [IO.Path]::GetFileNameWithoutExtension($path) }
                } else {
                    $n = ($id -split '_')[0]
                    ($n -split '\.')[-1]
                }
            }
            @($names | Where-Object { $_ } | Select-Object -Unique)
        }

        # ok | pc (blocked by HKLM) | user (apps off) | desktop (desktop apps off)
        function Get-MeetPrivacy([string]$Capability) {
            $lm = (Get-ItemProperty "HKLM:\$MeetConsentRoot\$Capability" -Name Value -ErrorAction SilentlyContinue).Value
            $cu = (Get-ItemProperty "HKCU:\$MeetConsentRoot\$Capability" -Name Value -ErrorAction SilentlyContinue).Value
            $np = (Get-ItemProperty "HKCU:\$MeetConsentRoot\$Capability\NonPackaged" -Name Value -ErrorAction SilentlyContinue).Value
            if ($lm -eq 'Deny') { return 'pc' }
            if ($cu -eq 'Deny') { return 'user' }
            if ($np -eq 'Deny') { return 'desktop' }
            'ok'
        }

        function Get-MeetingState {
            $cams = @(Get-PnpDevice -Class Camera, Image -PresentOnly -ErrorAction SilentlyContinue |
                ForEach-Object { [pscustomobject]@{ Name = $_.FriendlyName; Ok = ($_.Status -eq 'OK') } })
            Initialize-MeetAudio
            [pscustomobject]@{
                Cameras  = $cams
                CamInUse = @(Get-MeetInUse 'webcam')
                Mic      = [MaintGui.Audio]::GetDefault($true)
                MicInUse = @(Get-MeetInUse 'microphone')
                Spk      = [MaintGui.Audio]::GetDefault($false)
                PrivCam  = Get-MeetPrivacy 'webcam'
                PrivMic  = Get-MeetPrivacy 'microphone'
            }
        }
    }
}

function Open-Meeting {
    Show-Page 'PanelMeeting' (T 'Camera and microphone') (T 'Make sure others can see and hear you, and that you can hear them.')
    Update-Meeting
}

function Update-Meeting {
    $ui.MeetLoading.Visibility = 'Visible'
    $ui.MeetContent.Visibility = 'Collapsed'
    Start-Worker -Work { Get-MeetingState } -OnDone { param($r, $err) Show-Meeting $r $err }
}

function Set-MeetStatus([string]$Prefix, [string]$State, [string]$Status, [string]$Detail) {
    $look = @{ ok = @(0xE930, 'Good'); warn = @(0xE7BA, 'Warn'); bad = @(0xEA39, 'Bad') }[$State]
    $ui["Meet${Prefix}Icon"].Text = [string][char]$look[0]
    Set-Themed $ui["Meet${Prefix}Icon"] Foreground $look[1]
    $ui["Meet${Prefix}Status"].Text = $Status
    $ui["Meet${Prefix}Detail"].Text = $Detail
    $ui["Meet${Prefix}Detail"].Visibility = if ($Detail) { 'Visible' } else { 'Collapsed' }
}

function Show-Meeting($r, $err) {
    $ui.MeetLoading.Visibility = 'Collapsed'
    $ui.MeetContent.Visibility = 'Visible'
    foreach ($b in 'MeetBtnCamApp', 'MeetBtnMicUnmute', 'MeetBtnSpkUnmute', 'MeetBtnSpkTest', 'MeetBtnPrivAllow', 'MeetBtnPrivSettings') { $ui[$b].Visibility = 'Collapsed' }
    if ($err -or -not $r) {
        foreach ($p in 'Cam', 'Mic', 'Spk', 'Priv') { Set-MeetStatus $p 'warn' ((T "Couldn't check: {0}") -f $err) '' }
        return
    }

    # Camera
    $cams = @($r.Cameras)
    $bad = @($cams | Where-Object { -not $_.Ok })
    $inUse = @($r.CamInUse)
    if (-not $cams.Count) {
        Set-MeetStatus 'Cam' 'bad' (T 'No camera found') (T "If you use an external camera, check that it's plugged in.")
    } elseif ($bad.Count -eq $cams.Count) {
        Set-MeetStatus 'Cam' 'bad' (T 'The camera has a problem') ("{0}. {1}" -f $bad[0].Name, (T 'Try unplugging it and plugging it back in, or restart your PC.'))
    } elseif ($inUse.Count) {
        $apps = $inUse -join ', '
        Set-MeetStatus 'Cam' 'warn' ((T 'In use by {0}') -f $apps) ((T "Only one app can use the camera at a time. If your meeting app can't see the camera, close {0} first.") -f $apps)
    } else {
        Set-MeetStatus 'Cam' 'ok' (T 'Ready') ((@($cams | Where-Object { $_.Ok } | ForEach-Object { $_.Name }) | Select-Object -Unique) -join ', ')
        $ui.MeetBtnCamApp.Visibility = 'Visible'
    }
    if ($cams.Count) { $ui.MeetBtnCamApp.Visibility = 'Visible' }

    # Microphone
    $m = $r.Mic
    if (-not $m -or -not $m.Found) {
        Set-MeetStatus 'Mic' 'bad' (T 'No microphone found') (T 'Plug in a headset or microphone, or check that it is turned on.')
    } else {
        $vol = [int][math]::Round($m.Volume * 100)
        $line = (T '{0} - volume {1}%') -f $m.Name, $vol
        if (@($r.MicInUse).Count) { $line += "`n" + ((T 'Also in use by {0}') -f (@($r.MicInUse) -join ', ')) }
        if ($m.Muted) {
            Set-MeetStatus 'Mic' 'bad' (T 'Muted') ("{0}`n{1}" -f (T "Others won't hear you until you unmute it."), $line)
            $ui.MeetBtnMicUnmute.Visibility = 'Visible'
        } elseif ($vol -lt 20) {
            Set-MeetStatus 'Mic' 'warn' ((T 'Volume is very low ({0}%)') -f $vol) ("{0}`n{1}" -f (T 'Others may not hear you. Turn it up in Sound settings.'), $m.Name)
        } else {
            Set-MeetStatus 'Mic' 'ok' (T 'Ready') $line
        }
    }

    # Speakers
    $s = $r.Spk
    if (-not $s -or -not $s.Found) {
        Set-MeetStatus 'Spk' 'bad' (T 'No speakers or headset found') (T 'Plug in a headset or speakers, or check that they are turned on.')
    } else {
        $vol = [int][math]::Round($s.Volume * 100)
        $line = (T '{0} - volume {1}%') -f $s.Name, $vol
        if ($s.Muted) {
            Set-MeetStatus 'Spk' 'bad' (T 'Muted') ("{0}`n{1}" -f (T "You won't hear anything until you unmute it."), $line)
            $ui.MeetBtnSpkUnmute.Visibility = 'Visible'
        } elseif ($vol -lt 10) {
            Set-MeetStatus 'Spk' 'warn' ((T 'Volume is very low ({0}%)') -f $vol) ("{0}`n{1}" -f (T 'You may not hear the others. Turn the volume up.'), $s.Name)
        } else {
            Set-MeetStatus 'Spk' 'ok' (T 'Ready') $line
        }
        $ui.MeetBtnSpkTest.Visibility = 'Visible'
    }

    # Privacy: worst of camera and microphone
    $rank = @{ ok = 0; desktop = 1; user = 2; pc = 3 }
    $worst = if ($rank[$r.PrivCam] -ge $rank[$r.PrivMic]) { $r.PrivCam } else { $r.PrivMic }
    $what = if ($r.PrivCam -eq $worst -and $r.PrivMic -eq $worst) { T 'your camera and microphone' } elseif ($r.PrivCam -eq $worst) { T 'your camera' } else { T 'your microphone' }
    $script:MeetPrivSettingsUri = if ($r.PrivCam -eq $worst) { 'ms-settings:privacy-webcam' } else { 'ms-settings:privacy-microphone' }
    switch ($worst) {
        'pc' {
            Set-MeetStatus 'Priv' 'bad' ((T 'Access to {0} is blocked for the whole PC') -f $what) (T 'Someone with administrator rights (or IT) has turned it off. Open the privacy settings or contact IT.')
            $ui.MeetBtnPrivSettings.Visibility = 'Visible'
        }
        'user' {
            Set-MeetStatus 'Priv' 'bad' ((T 'Apps are not allowed to use {0}') -f $what) (T "Meeting apps can't see or hear you until you allow it.")
            $ui.MeetBtnPrivAllow.Visibility = 'Visible'; $ui.MeetBtnPrivSettings.Visibility = 'Visible'
        }
        'desktop' {
            Set-MeetStatus 'Priv' 'warn' ((T 'Desktop apps are not allowed to use {0}') -f $what) (T 'Apps like Teams, Zoom and your browser need this to see or hear you.')
            $ui.MeetBtnPrivAllow.Visibility = 'Visible'; $ui.MeetBtnPrivSettings.Visibility = 'Visible'
        }
        default {
            Set-MeetStatus 'Priv' 'ok' (T 'Camera and microphone are allowed') (T 'Apps are allowed to use your camera and microphone.')
        }
    }
}

function Set-MeetMute([bool]$Capture) {
    Initialize-MeetAudio
    if ([MaintGui.Audio]::SetMute($Capture, $false)) {
        Add-History -Title $(if ($Capture) { T 'Microphone unmuted' } else { T 'Speakers unmuted' }) -State ok
    }
    Update-Meeting
}

function Invoke-MeetTestSound {
    $candidates = 'Windows Notify System Generic.wav', 'Windows Ding.wav', 'chimes.wav', 'tada.wav', 'notify.wav'
    $file = $candidates | ForEach-Object { Join-Path $env:windir "Media\$_" } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $file) { Show-Error (T "Couldn't find a test sound on this PC."); return }
    (New-Object System.Media.SoundPlayer $file).Play()
}

# Only the current user's settings are changed (HKLM blocks need IT / an administrator).
function Grant-MeetPrivacy {
    foreach ($cap in 'webcam', 'microphone') {
        foreach ($key in "HKCU:\$MeetConsentRoot\$cap", "HKCU:\$MeetConsentRoot\$cap\NonPackaged") {
            $v = (Get-ItemProperty $key -Name Value -ErrorAction SilentlyContinue).Value
            if ($v -eq 'Deny') { Set-ItemProperty $key -Name Value -Value 'Allow' }
        }
    }
    Add-History -Title (T 'Camera and microphone access allowed') -State ok
    Update-Meeting
}
