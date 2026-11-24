<#
  MaintainGui.ps1 - point-and-click version of Maintain.cmd for non-technical users.

  Normally started by "PC Maintenance.exe" (built by build.ps1), which runs:
    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File MaintainGui.ps1

  Structure:
    $EngineCode  - the actual maintenance work (winget, Windows Update, cleanup, powercfg...).
                   Runs inside background runspaces so the window never freezes.
                   Talks back with Log / SetStatus / Step (queued, drained by a UI timer).
    UI           - WPF window built from XAML below. Long jobs show on the "task" page with
                   a progress bar, one row per step, and a collapsible technical log.
  Questions (restore point failed? reinstall failed apps?) are asked between stages on the
  UI thread, never from inside a background job.
#>
param(
    [switch]$NoUpdate,     # skip the update check at startup (used after relaunching)
    [string]$StartPage,    # open a page directly: Apps, Clean, Battery, Sleep, Power, Info, Auto, or a feature name
    [switch]$Auto,         # scheduled automatic maintenance: no window, ends with a notification
    [switch]$Uninstall     # remove the installed copy, Start menu entry and scheduled task
)

$ErrorActionPreference = 'Stop'

# Bump on every deploy (commit + push to main). Shown in the header; releases are tagged v<version>.
$AppVersion = '2.2'
$AppDir     = $PSScriptRoot
$SelfPath   = $PSCommandPath
$RepoUrl    = 'https://github.com/MagnusHenningsen/win-maintenance.git'
$RepoApi    = 'https://api.github.com/repos/MagnusHenningsen/win-maintenance'

#region ---------- Settings and language ----------

$SettingsKey = 'HKCU:\Software\PCMaintenance'

function Get-AppSetting([string]$Name, $Default = $null) {
    $v = (Get-ItemProperty $SettingsKey -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $v) { $Default } else { $v }
}

function Set-AppSetting([string]$Name, $Value) {
    if (-not (Test-Path $SettingsKey)) { New-Item $SettingsKey -Force | Out-Null }
    Set-ItemProperty $SettingsKey -Name $Name -Value $Value
}

# 'en' or 'nb' (Norwegian Bokmål). Defaults to Norwegian when Windows is in Norwegian.
$Lang = Get-AppSetting 'Language'
if ($Lang -notin 'en', 'nb') {
    $Lang = if ((Get-UICulture).TwoLetterISOLanguageName -in 'nb', 'nn', 'no') { 'nb' } else { 'en' }
}
if ($env:MAINT_TEST_LANG -in 'en', 'nb') { $Lang = $env:MAINT_TEST_LANG }   # screenshots/tests without changing settings

# Norwegian translations, keyed by the English text. Filled by lang\nb.ps1 and each features\*.ps1.
$Strings = @{}
function Add-Strings([hashtable]$Map) { foreach ($k in $Map.Keys) { $Strings[$k] = $Map[$k] } }

#endregion

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

#region ---------- Engine (runs in background runspaces; also dot-sourced into the UI) ----------

$EngineCode = {
$ErrorActionPreference = 'Stop'

# Translate: returns the Norwegian text when the app runs in Norwegian, otherwise the English text.
# Always pass the English text and format afterwards:  (T 'Updating {0}') -f $name
function T([string]$Text) {
    if ($Lang -eq 'nb' -and $Strings) { $v = $Strings[$Text]; if ($v) { return $v } }
    $Text
}
$Culture = if ($Lang -eq 'nb') { [Globalization.CultureInfo]'nb-NO' } else { [Globalization.CultureInfo]'en-US' }

#--- History: one JSON object per line in %LOCALAPPDATA%\PCMaintenance\history.jsonl ---
$DataDir = Join-Path $env:LOCALAPPDATA 'PCMaintenance'
$HistoryFile = Join-Path $DataDir 'history.jsonl'

function Add-History {
    param(
        [string]$Title,
        [ValidateSet('ok', 'warn', 'error', 'info')][string]$State = 'ok',
        [string]$Detail = '',
        [ValidateSet('app', 'auto')][string]$Source = 'app'
    )
    try {
        if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Force $DataDir | Out-Null }
        $line = [pscustomobject]@{ Time = (Get-Date).ToString('o'); Title = $Title; State = $State; Detail = $Detail; Source = $Source } |
            ConvertTo-Json -Compress
        Add-Content -LiteralPath $HistoryFile -Value $line -Encoding UTF8
    } catch {}
}

# Files that make up the app (what the installer copies and a release zip contains)
$AppFiles = 'PC Maintenance.exe', 'MaintainGui.ps1', 'Maintain.cmd', 'README.md', 'assets', 'features', 'lang'

function Copy-AppFiles([string]$From, [string]$To) {
    New-Item -ItemType Directory -Force $To | Out-Null
    foreach ($n in $AppFiles) {
        $src = Join-Path $From $n
        if (-not (Test-Path -LiteralPath $src)) { continue }
        if (Test-Path -LiteralPath $src -PathType Container) {
            $dst = Join-Path $To $n
            New-Item -ItemType Directory -Force $dst | Out-Null
            Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force
        } else {
            Copy-Item -LiteralPath $src -Destination $To -Force
        }
    }
    # Files from a downloaded zip are marked as "from the internet"; clear that so they run without warnings
    Get-ChildItem -LiteralPath $To -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
}

# Newest first. Each entry: Time [datetime], Title, State (ok|warn|error|info), Detail, Source (app|auto).
function Get-History([int]$Max = 500) {
    if (-not (Test-Path -LiteralPath $HistoryFile)) { return , @() }
    $lines = @(Get-Content -LiteralPath $HistoryFile -Encoding UTF8 -Tail $Max)
    [array]::Reverse($lines)
    $out = foreach ($l in $lines) {
        try {
            $o = $l | ConvertFrom-Json
            [pscustomobject]@{ Time = [datetime]::Parse($o.Time, $null, 'RoundtripKind').ToLocalTime(); Title = $o.Title; State = $o.State; Detail = $o.Detail; Source = $o.Source }
        } catch {}
    }
    return , @($out)
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Bytes([double]$B) {
    if ($B -ge 1GB) { '{0:N1} GB' -f ($B / 1GB) }
    elseif ($B -ge 1MB) { '{0:N0} MB' -f ($B / 1MB) }
    elseif ($B -ge 1KB) { '{0:N0} KB' -f ($B / 1KB) }
    else { '{0:N0} bytes' -f $B }
}

function Get-DesktopPath([string]$FileName) { Join-Path ([Environment]::GetFolderPath('Desktop')) $FileName }

function Get-PendingRebootReasons {
    $r = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $r += 'Component servicing' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $r += 'Windows Update' }
    $active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).ComputerName
    $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
    if ($active -and $pending -and $active -ne $pending) { $r += 'Computer rename' }
    $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pfro -and $pfro.PendingFileRenameOperations) { $r += 'Pending file renames (often harmless)' }
    return , @($r)
}

# Pending file renames alone are common and harmless, so they don't count as "restart needed".
function Test-RebootNeeded { @(Get-PendingRebootReasons | Where-Object { $_ -notlike 'Pending file renames*' }).Count -gt 0 }

function Get-BatteryInfo {
    $w = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $w) { return $null }
    $design = $null; $full = $null
    try { $design = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity } catch {}
    try { $full = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity } catch {}
    if (-not ($design -and $full)) {
        # root/wmi needs admin; the battery report works for everyone (takes a second or two)
        $xmlPath = Join-Path $env:TEMP ('battery-{0}.xml' -f [guid]::NewGuid())
        try {
            $null = Get-NativeText powercfg @('/batteryreport', '/xml', '/output', $xmlPath)
            $bat = @(([xml](Get-Content -LiteralPath $xmlPath -Raw)).BatteryReport.Batteries.Battery)[0]
            if ($bat) { $design = [double]$bat.DesignCapacity; $full = [double]$bat.FullChargeCapacity }
        } catch {
        } finally { Remove-Item -LiteralPath $xmlPath -ErrorAction SilentlyContinue }
    }
    [pscustomobject]@{
        Charge = [int]$w.EstimatedChargeRemaining
        OnAC   = ($w.BatteryStatus -in 2, 3, 6, 7, 8, 9)
        Design = $design
        Full   = $full
        Health = if ($design -and $full) { [math]::Min(100, [math]::Round(100 * $full / $design, 0)) } else { $null }
    }
}

function Get-SystemDriveFree { ([IO.DriveInfo]::new($env:SystemDrive)).AvailableFreeSpace }
function Get-SystemDriveSize { ([IO.DriveInfo]::new($env:SystemDrive)).TotalSize }

function Get-FolderSize([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    [long](Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}

# winget draws download progress with full/shaded block characters
$ProgressBarChars = '[' + [char]0x2588 + [char]0x2592 + ']'

# Runs a console program, sends its output to the technical log, returns the exit code.
# Spinner characters and progress bars are dropped; "[===  42.0%  ===]" style lines update the progress bar.
function Invoke-Native {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @(), [switch]$Utf8)
    $ErrorActionPreference = 'Continue'   # PS 5.1 + 2>&1 + Stop would throw on the first stderr line
    $prev = $null
    if ($Utf8) { try { $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {} }
    try {
        & $FilePath @ArgumentList 2>&1 | ForEach-Object {
            $t = @("$_" -split "`r" | Where-Object { $_.Trim() }) | Select-Object -Last 1
            if (-not $t) { return }
            $t = $t.TrimEnd()
            if ($t -match '^\s*[-\\|/]\s*$' -or $t -match $ProgressBarChars) { return }
            if ($t -match '^\s*\[[=\s]*(\d+(?:[.,]\d+)?)%[=\s]*\]\s*$') {
                SetStatus $Sync.Status ([double]($Matches[1] -replace ',', '.')); return
            }
            Log $t 'detail'
        }
    } finally {
        if ($prev) { try { [Console]::OutputEncoding = $prev } catch {} }
    }
    return $LASTEXITCODE
}

function Get-NativeText([string]$FilePath, [string[]]$ArgumentList) {
    $ErrorActionPreference = 'Continue'
    ((& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }) -join "`n").Trim()
}

#--- PC checkup ---
# State: ok | warn | bad | info. Fix: key of the button action on the home screen (see $CheckupFixes).
function New-HealthCheck([string]$Key, [string]$State, [string]$Title, [string]$Detail, [string]$Fix, [string]$FixLabel) {
    [pscustomobject]@{ Key = $Key; State = $State; Title = $Title; Detail = $Detail; Fix = $Fix; FixLabel = $FixLabel }
}

function Get-HealthChecks {
    # Disk space
    $free = Get-SystemDriveFree; $size = Get-SystemDriveSize; $pct = 100 * $free / $size
    if ($pct -lt 5 -or $free -lt 5GB) {
        New-HealthCheck 'disk' 'bad' (T 'Disk space') ((T 'Only {0} left on drive {1}. Your PC can get slow or stop installing updates.') -f (Format-Bytes $free), $env:SystemDrive) 'clean' 'Free up space'
    } elseif ($pct -lt 15 -or $free -lt 15GB) {
        New-HealthCheck 'disk' 'warn' (T 'Disk space') ((T 'Drive {1} is getting full ({0} left).') -f (Format-Bytes $free), $env:SystemDrive) 'clean' 'Free up space'
    } else { New-HealthCheck 'disk' 'ok' (T 'Disk space') '' }

    # Restart
    $up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    if (Test-RebootNeeded) {
        New-HealthCheck 'restart' 'warn' (T 'Restart') (T 'A restart is needed to finish installing updates.') 'restart' 'Restart now'
    } elseif ($up.TotalDays -ge 7) {
        New-HealthCheck 'restart' 'warn' (T 'Restart') ((T 'Your PC has been on for {0} days. Restarting now and then keeps it fast and finishes updates.') -f [int][math]::Floor($up.TotalDays)) 'restart' 'Restart now'
    } else { New-HealthCheck 'restart' 'ok' (T 'Restart') '' }

    # Windows updates: when did Windows last install updates successfully?
    try {
        $last = (New-Object -ComObject Microsoft.Update.AutoUpdate).Results.LastInstallationSuccessDate
        if ($last -and ([datetime]$last).Year -gt 2000) {
            $days = [int]((Get-Date) - [datetime]$last).TotalDays
            if ($days -gt 35) {
                New-HealthCheck 'wu' 'warn' (T 'Windows updates') ((T "Windows hasn't installed updates for {0} days.") -f $days) 'update' 'Update everything'
            } else { New-HealthCheck 'wu' 'ok' (T 'Windows updates') '' }
        }
    } catch {}

    # Virus protection (any antivirus registered with Windows Security, not only Defender)
    try {
        $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)
        $on = @($av | Where-Object { ('{0:X6}' -f [int]$_.productState).Substring(2, 2) -in '10', '11' })
        if (-not $on.Count) {
            New-HealthCheck 'av' 'bad' (T 'Virus protection') (T 'Virus protection is turned off. Your PC is not protected against malware.') 'security' 'Open Windows Security'
        } elseif (-not @($on | Where-Object { ('{0:X6}' -f [int]$_.productState).Substring(4, 2) -eq '00' }).Count) {
            New-HealthCheck 'av' 'warn' (T 'Virus protection') ((T '{0} is on, but its virus definitions are out of date.') -f $on[0].displayName) 'update' 'Update everything'
        } else { New-HealthCheck 'av' 'ok' (T 'Virus protection') '' }
    } catch {}

    # Firewall (Windows Firewall, or another firewall registered with Windows Security)
    try {
        $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled })
        $other = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct -ErrorAction SilentlyContinue |
            Where-Object { ('{0:X6}' -f [int]$_.productState).Substring(2, 2) -in '10', '11' })
        if ($off.Count -and -not $other.Count) {
            New-HealthCheck 'fw' 'bad' (T 'Firewall') ((T 'The firewall is turned off for {0} networks.') -f (($off | ForEach-Object { $_.Name }) -join ', ')) 'firewall' 'Open Windows Security'
        } else { New-HealthCheck 'fw' 'ok' (T 'Firewall') '' }
    } catch {}

    # Drive encryption (BitLocker). Not available on Windows Home, then nothing is shown.
    try {
        $v = (New-Object -ComObject Shell.Application).NameSpace("$env:SystemDrive\").Self.ExtendedProperty('System.Volume.BitLockerProtection')
        switch ([int]$v) {
            2 { New-HealthCheck 'bitlocker' 'warn' (T 'Drive encryption') ((T "Drive {0} isn't encrypted. If your PC is lost or stolen, others can read your files. Ask IT if you're unsure.") -f $env:SystemDrive) 'bitlocker' 'Open BitLocker' }
            5 { New-HealthCheck 'bitlocker' 'warn' (T 'Drive encryption') (T 'BitLocker is paused, usually after a BIOS or Windows update. It normally resumes after a restart.') 'restart' 'Restart now' }
            { $_ -in 1, 3, 6 } { New-HealthCheck 'bitlocker' 'ok' (T 'Drive encryption') '' }
        }
    } catch {}

    # Battery
    try {
        $b = Get-BatteryInfo
        if ($b -and $null -ne $b.Health) {
            if ($b.Health -lt 70) {
                New-HealthCheck 'battery' 'warn' (T 'Battery') ((T 'The battery is worn: it holds {0}% of what it did when new.') -f $b.Health) 'battery' 'Show details'
            } else { New-HealthCheck 'battery' 'ok' (T 'Battery') '' }
        }
    } catch {}

    # Automatic maintenance (a gentle tip, not a problem)
    if (-not (Get-ScheduledTask -TaskName 'PC Maintenance automatic maintenance' -ErrorAction SilentlyContinue)) {
        New-HealthCheck 'auto' 'info' (T 'Automatic maintenance') (T 'Tip: let PC Maintenance keep this PC up to date by itself.') 'auto' 'Set up'
    } else { New-HealthCheck 'auto' 'ok' (T 'Automatic maintenance') '' }
}

function Get-SystemSnapshot {
    $os   = Get-CimInstance Win32_OperatingSystem
    $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS
    $plan = ''
    $s = Get-NativeText powercfg @('/getactivescheme')
    if ($s -match '\(([^)]+)\)') { $plan = $Matches[1] }
    [pscustomobject]@{
        Computer      = $env:COMPUTERNAME
        User          = "$env:USERDOMAIN\$env:USERNAME"
        IsAdmin       = Test-IsAdmin
        OS            = ('{0} {1}' -f $os.Caption, $cv.DisplayVersion).Trim()
        Build         = '{0}.{1}' -f $os.BuildNumber, $cv.UBR
        Model         = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
        Serial        = "$($bios.SerialNumber)".Trim()
        Cpu           = "$($cpu.Name)".Trim()
        MemTotal      = [double]$os.TotalVisibleMemorySize * 1KB
        MemFree       = [double]$os.FreePhysicalMemory * 1KB
        LastBoot      = $os.LastBootUpTime
        Uptime        = (Get-Date) - $os.LastBootUpTime
        PowerPlan     = $plan
        Battery       = Get-BatteryInfo
        RebootReasons = Get-PendingRebootReasons
        RebootNeeded  = Test-RebootNeeded
        Disks         = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
            [pscustomobject]@{ Drive = $_.DeviceID; Label = $_.VolumeName; Free = [double]$_.FreeSpace; Size = [double]$_.Size }
        })
    }
}

#--- Cleanup ---

function Initialize-RecycleBinApi {
    if ('MaintGui.RecycleBin' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MaintGui {
    public static class RecycleBin {
        [StructLayout(LayoutKind.Sequential)]
        public struct SHQUERYRBINFO { public int cbSize; public long i64Size; public long i64NumItems; }
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHQueryRecycleBin(string pszRootPath, ref SHQUERYRBINFO info);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        static extern int SHEmptyRecycleBin(IntPtr hwnd, string pszRootPath, uint flags);
        public static long[] Query() {
            var i = new SHQUERYRBINFO();
            i.cbSize = Marshal.SizeOf(typeof(SHQUERYRBINFO));
            if (SHQueryRecycleBin(null, ref i) != 0) return new long[] { -1, -1 };
            return new long[] { i.i64Size, i.i64NumItems };
        }
        // 7 = no confirmation | no progress UI | no sound
        public static int Empty() { return SHEmptyRecycleBin(IntPtr.Zero, null, 7); }
    }
}
'@
}

function Get-RecycleBinSize { Initialize-RecycleBinApi; [MaintGui.RecycleBin]::Query()[0] }
function Clear-RecycleBinAll { Initialize-RecycleBinApi; [void][MaintGui.RecycleBin]::Empty() }

# Deletes everything inside a folder (files in use are skipped). Returns bytes freed.
function Clear-FolderContents([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [long]0 }
    $before = Get-FolderSize $Path
    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    for ($i = 0; $i -lt $items.Count; $i++) {
        if ($i % 25 -eq 0) { SetStatus ((T 'Removing files ({0} of {1})') -f $i, $items.Count) (100 * $i / $items.Count) }
        try { Remove-Item -LiteralPath $items[$i].FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    }
    return [long][math]::Max(0, $before - (Get-FolderSize $Path))
}

$DeliveryCachePath = Join-Path $env:windir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'

#--- Power settings ---

function Get-PowerVal {
    param([string]$Sub, [string]$Setting)
    $raw  = Get-NativeText powercfg @('/qh', 'SCHEME_CURRENT', $Sub, $Setting)
    $hits = [regex]::Matches($raw, ':\s*0x([0-9a-fA-F]+)\s*(\r?\n|$)')
    if ($hits.Count -lt 2) { return [pscustomobject]@{ OK = $false; Raw = $raw } }
    [pscustomobject]@{
        OK  = $true
        AC  = [Convert]::ToInt32($hits[$hits.Count - 2].Groups[1].Value, 16)
        DC  = [Convert]::ToInt32($hits[$hits.Count - 1].Groups[1].Value, 16)
        Raw = $raw
    }
}

function Set-PowerVal {
    param([string]$Sub, [string]$Setting, [int]$Value, [switch]$AC, [switch]$DC)
    if ($AC) {
        & powercfg /setacvalueindex SCHEME_CURRENT $Sub $Setting $Value
        if ($LASTEXITCODE -ne 0) { throw ((T 'Could not change the setting (powercfg error {0}).') -f $LASTEXITCODE) }
    }
    if ($DC) {
        & powercfg /setdcvalueindex SCHEME_CURRENT $Sub $Setting $Value
        if ($LASTEXITCODE -ne 0) { throw ((T 'Could not change the setting (powercfg error {0}).') -f $LASTEXITCODE) }
    }
    & powercfg /setactive SCHEME_CURRENT
}

function Test-HibernateEnabled {
    $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue
    return ($null -ne $v -and $v.HibernateEnabled -eq 1)
}

function Get-WakeArmedDevices {
    @((Get-NativeText powercfg @('/devicequery', 'wake_armed')) -split "`n" | ForEach-Object { "$_".Trim() } |
        Where-Object { $_ -and $_ -notmatch '^(NONE|INGEN|Ingen)$' })
}

#--- Restore point ---

function Get-RestorePoints { @(Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction SilentlyContinue) }

function New-RestorePointCore {
    param([string]$Description = 'PC Maintenance')
    if (-not (Test-IsAdmin)) { return [pscustomobject]@{ Result = 'NeedsAdmin'; Detail = (T 'Needs administrator') } }
    $before = @(Get-RestorePoints).Count
    $r = Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments @{
        Description      = $Description
        RestorePointType = [uint32]12   # MODIFY_SETTINGS
        EventType        = [uint32]100  # BEGIN_SYSTEM_CHANGE
    }
    if ($r.ReturnValue -ne 0) { return [pscustomobject]@{ Result = 'Failed'; Detail = ((T 'Error code {0}') -f $r.ReturnValue) } }
    $points = @(Get-RestorePoints)
    if ($points.Count -gt $before) { return [pscustomobject]@{ Result = 'Created'; Detail = 'Created' } }

    # Windows only allows one restore point per 24 hours by default
    $latest = $points | Sort-Object SequenceNumber | Select-Object -Last 1
    if ($latest) {
        try {
            $t = [Management.ManagementDateTimeConverter]::ToDateTime($latest.CreationTime)
            if ($t -gt (Get-Date).AddHours(-24)) {
                return [pscustomobject]@{ Result = 'Recent'; Detail = [string]::Format($Culture, (T 'Using the one from {0:dd MMM HH:mm} (Windows allows one per day)'), $t) }
            }
        } catch {}
    }
    [pscustomobject]@{ Result = 'Failed'; Detail = (T 'Not created') }
}

function Enable-SystemProtectionCore {
    $r = Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName Enable -Arguments @{ Drive = "$env:SystemDrive\" }
    if ($r.ReturnValue -ne 0) { throw ((T 'Could not turn on System Protection (code {0}).') -f $r.ReturnValue) }
}

#--- winget ---

function Assert-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw (T 'The Windows package manager (winget) is missing. Install "App Installer" from the Microsoft Store.')
    }
}

function Get-WingetUpgrades {
    param([switch]$IncludeUnknown)
    Assert-Winget
    SetStatus (T 'Checking which apps have updates')
    $wgArgs = @('upgrade', '--accept-source-agreements')
    if ($IncludeUnknown) { $wgArgs += '--include-unknown' }

    $ErrorActionPreference = 'Continue'
    $prev = $null
    try { $prev = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
    try {
        # Keep only the text after the last carriage return (drops the spinner)
        $lines = @(& winget @wgArgs 2>$null | ForEach-Object { ("$_" -split "`r")[-1] })
    } finally {
        if ($prev) { try { [Console]::OutputEncoding = $prev } catch {} }
    }

    # Parse every table (normal + "require explicit targeting") by header column positions,
    # so this works whatever language Windows is in.
    $result = New-Object System.Collections.Generic.List[object]
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^-{10,}\s*$') { continue }
        $cols = @([regex]::Matches($lines[$i - 1], '\S+') | ForEach-Object { $_.Index })
        if ($cols.Count -lt 4) { continue }
        $j = $i + 1
        for (; $j -lt $lines.Count; $j++) {
            $row = $lines[$j]
            if ([string]::IsNullOrWhiteSpace($row) -or $row.Length -le $cols[3]) { break }
            $f = for ($k = 0; $k -lt $cols.Count; $k++) {
                $start = $cols[$k]
                $end = if ($k + 1 -lt $cols.Count) { [Math]::Min($cols[$k + 1], $row.Length) } else { $row.Length }
                if ($start -ge $row.Length) { '' } else { $row.Substring($start, $end - $start).Trim() }
            }
            if ($f[1] -notmatch '^\S+$') { break }
            $result.Add([pscustomobject]@{
                Name      = $f[0]
                Id        = $f[1]
                Version   = $f[2]
                Available = $f[3]
                Source    = if ($f.Count -gt 4) { $f[4] } else { '' }
            })
        }
        $i = $j
    }
    return @($result | Sort-Object Id -Unique | Sort-Object Name)
}

$WingetCommon = @('--silent', '--accept-package-agreements', '--accept-source-agreements')

# Upgrades packages one by one (Step per package Id). Returns the packages that still need an update.
function Invoke-WingetUpgradeSet {
    param([object[]]$Packages, [switch]$IncludeUnknown)
    Assert-Winget
    $n = $Packages.Count
    for ($i = 0; $i -lt $n; $i++) {
        $p = $Packages[$i]
        Step $p.Id 'running' (T 'Updating...')
        SetStatus ((T 'Updating {0} ({1} of {2})') -f $p.Name, ($i + 1), $n) (100 * $i / $n)
        Log ('Updating {0} [{1}] {2} -> {3}' -f $p.Name, $p.Id, $p.Version, $p.Available)
        [void](Invoke-Native winget (@('upgrade', '--id', $p.Id, '--exact') + $WingetCommon) -Utf8)
        Step $p.Id 'running' (T 'Checking...')
    }
    # Judge success by what's still listed, not exit codes (some installers return non-zero on success)
    SetStatus (T 'Checking the results') 100
    $still = @(Get-WingetUpgrades -IncludeUnknown:$IncludeUnknown | ForEach-Object { $_.Id })
    $failed = @()
    foreach ($p in $Packages) {
        if ($still -contains $p.Id) { $failed += $p; Step $p.Id 'error' (T 'Could not be updated') }
        else { Step $p.Id 'ok' ((T 'Updated to {0}') -f $p.Available) }
    }
    return , $failed
}

# Uninstall + fresh install. Step key is "re:<Id>".
function Invoke-WingetReinstallSet {
    param([object[]]$Packages)
    $lost = @(); $ok = 0
    $n = $Packages.Count
    for ($i = 0; $i -lt $n; $i++) {
        $p = $Packages[$i]; $key = 're:' + $p.Id
        $src = if ($p.Source) { @('--source', $p.Source) } else { @() }
        Step $key 'running' (T 'Removing...')
        SetStatus ((T 'Reinstalling {0} ({1} of {2})') -f $p.Name, ($i + 1), $n) (100 * $i / $n)
        Log "Uninstalling $($p.Id)"
        $code = Invoke-Native winget @('uninstall', '--id', $p.Id, '--exact', '--silent', '--accept-source-agreements') -Utf8
        if ($code -ne 0) { Step $key 'error' (T 'Could not remove it, so it was left as it was'); continue }

        $done = $false
        for ($try = 1; $try -le 2 -and -not $done; $try++) {
            Step $key 'running' (T 'Installing...')
            Log "Installing $($p.Id) (attempt $try)"
            $code = Invoke-Native winget (@('install', '--id', $p.Id, '--exact') + $src + $WingetCommon) -Utf8
            if ($code -eq 0) { $done = $true }
        }
        if ($done) { $ok++; Step $key 'ok' (T 'Reinstalled') }
        else {
            $lost += $p.Id
            Step $key 'error' ((T 'REMOVED and not reinstalled. Ask IT, or run: winget install --id {0}') -f $p.Id)
        }
    }
    [pscustomobject]@{ Ok = $ok; Lost = $lost }
}

#--- Update everything ---

$UpdateSteps = @(
    [pscustomobject]@{ Key = 'winget';   Label = (T 'Apps');                         Fn = 'Update-AllApps';       Admin = $false }
    [pscustomobject]@{ Key = 'store';    Label = (T 'Microsoft Store apps');         Fn = 'Update-StoreApps';     Admin = $true }
    [pscustomobject]@{ Key = 'wu';       Label = (T 'Windows Update and drivers');   Fn = 'Update-WindowsUpdate'; Admin = $true }
    [pscustomobject]@{ Key = 'defender'; Label = (T 'Virus protection (Defender)');  Fn = 'Update-Defender';      Admin = $true }
    [pscustomobject]@{ Key = 'office';   Label = (T 'Microsoft 365 / Office');       Fn = 'Update-Office';        Admin = $false }
    [pscustomobject]@{ Key = 'wsl';      Label = (T 'Windows Subsystem for Linux');  Fn = 'Update-Wsl';           Admin = $false }
    [pscustomobject]@{ Key = 'psmod';    Label = (T 'PowerShell modules');           Fn = 'Update-PsModules';     Admin = $false }
)

function Update-AllApps {
    param($ctx)
    $pkgs = @(Get-WingetUpgrades -IncludeUnknown)
    if (-not $pkgs.Count) { $ctx.Text = (T 'All apps are up to date'); return }
    Log ('{0} app update(s) found' -f $pkgs.Count)
    $failed = @(Invoke-WingetUpgradeSet -Packages $pkgs -IncludeUnknown)
    $ctx.Out.Failed = $failed
    if ($failed.Count) {
        $ctx.State = 'warn'
        $ctx.Text = (T '{0} of {1} updated, {2} could not be updated') -f ($pkgs.Count - $failed.Count), $pkgs.Count, $failed.Count
    } else {
        $ctx.Text = (T '{0} app(s) updated') -f $pkgs.Count
    }
}

function Update-StoreApps {
    param($ctx)
    SetStatus (T 'Asking the Microsoft Store to check for updates')
    $r = Get-CimInstance -Namespace 'root/cimv2/mdm/dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' |
        Invoke-CimMethod -MethodName UpdateScanMethod
    if ($r -and $r.ReturnValue -ne 0) { throw ((T 'The Store update check failed (code {0}).') -f $r.ReturnValue) }
    $ctx.Text = (T 'Started. The Store installs updates in the background')
}

function Update-WindowsUpdate {
    param($ctx)
    SetStatus (T 'Looking for Windows updates and drivers (this can take several minutes)')
    $session  = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $found    = $searcher.Search('IsInstalled=0 and IsHidden=0')

    $list = @()
    foreach ($u in $found.Updates) {
        if ($u.InstallationBehavior.CanRequestUserInput) { Log "Skipped (needs manual install): $($u.Title)" 'detail'; continue }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        Log "Found: $($u.Title)" 'detail'
        $list += $u
    }
    $total = $list.Count
    if ($total -eq 0) { $ctx.Text = (T 'Windows is up to date'); return }
    Log ('{0} Windows update(s) found' -f $total)

    $codes = @{ 0 = 'Not started'; 1 = 'In progress'; 2 = 'Succeeded'; 3 = 'Succeeded with errors'; 4 = 'Failed'; 5 = 'Aborted' }
    $ok = 0; $failed = @(); $reboot = $false

    for ($i = 0; $i -lt $total; $i++) {
        $u = $list[$i]
        SetStatus ((T 'Downloading Windows update {0} of {1}') -f ($i + 1), $total) (50 * $i / $total)
        if ($u.IsDownloaded) { continue }
        $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($u)
        $d = $session.CreateUpdateDownloader(); $d.Updates = $c
        try { [void]$d.Download() } catch { Log "Download failed: $($u.Title)" 'warn' }
    }
    for ($i = 0; $i -lt $total; $i++) {
        $u = $list[$i]
        SetStatus ((T 'Installing Windows update {0} of {1}') -f ($i + 1), $total) (50 + 50 * $i / $total)
        if (-not $u.IsDownloaded) { $failed += $u.Title; continue }
        $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($u)
        $inst = $session.CreateUpdateInstaller(); $inst.Updates = $c
        try {
            $res = $inst.Install()
            if ($res.RebootRequired) { $reboot = $true }
            if ([int]$res.ResultCode -in 2, 3) { $ok++; Log "Installed: $($u.Title)" 'detail' }
            else { $failed += $u.Title; Log ('{0}: {1}' -f $codes[[int]$res.ResultCode], $u.Title) 'warn' }
        } catch {
            $failed += $u.Title; Log "Install error: $($u.Title)" 'warn'
        }
    }
    $ctx.Text = (T '{0} of {1} installed') -f $ok, $total
    if ($failed.Count) { $ctx.State = 'warn'; $ctx.Text += ", $($failed.Count) failed" }
    if ($reboot) { $ctx.Text += (T ', restart needed') }
    if ($ok -eq 0) { throw $ctx.Text }
}

function Update-Defender {
    param($ctx)
    if (-not (Get-Command Update-MpSignature -ErrorAction SilentlyContinue)) { $ctx.State = 'skip'; $ctx.Text = (T 'Not available'); return }
    SetStatus (T 'Updating virus definitions')
    Update-MpSignature
    $ctx.Text = (T 'Up to date')
}

function Update-Office {
    param($ctx)
    $c2r = Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun\OfficeC2RClient.exe'
    if (-not (Test-Path $c2r)) { $ctx.State = 'skip'; $ctx.Text = (T 'Not installed'); return }
    Start-Process $c2r -ArgumentList '/update user updatepromptuser=false forceappshutdown=false displaylevel=true'
    $ctx.Text = (T 'Office updater started in its own window')
}

function Update-Wsl {
    param($ctx)
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue) -or
        -not (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss')) { $ctx.State = 'skip'; $ctx.Text = (T 'Not installed'); return }
    SetStatus (T 'Updating WSL')
    $env:WSL_UTF8 = '1'
    $code = Invoke-Native wsl.exe @('--update') -Utf8
    if ($code -ne 0) { throw ((T 'wsl --update failed (code {0})') -f $code) }
    $ctx.Text = (T 'Up to date')
}

# AzureRM and the classic Azure modules are retired (replaced by Az) and can't be updated from PSGallery.
$RetiredModulePattern = '^(AzureRM(\..+)?|Azure|Azure\.Storage|Azure\.AnalysisServices)$'

function Update-PsModules {
    param($ctx)
    SetStatus (T 'Looking for PowerShell modules')
    $all = @(Get-InstalledModule -ErrorAction SilentlyContinue)
    if (-not $all.Count) { $ctx.State = 'skip'; $ctx.Text = (T 'None installed'); return }
    $retired = @($all | Where-Object { $_.Name -match $RetiredModulePattern })
    $mods    = @($all | Where-Object { $_.Name -notmatch $RetiredModulePattern })
    $failed  = @()
    for ($i = 0; $i -lt $mods.Count; $i++) {
        $m = $mods[$i]
        SetStatus ((T 'PowerShell module {0} of {1}: {2}') -f ($i + 1), $mods.Count, $m.Name) (100 * $i / [math]::Max(1, $mods.Count))
        try { Update-Module -Name $m.Name -Force -ErrorAction Stop; Log "$($m.Name) ok" 'detail' }
        catch { $failed += $m.Name; Log "$($m.Name) failed: $($_.Exception.Message)" 'warn' }
    }
    $ctx.Text = (T '{0} checked') -f $mods.Count
    if ($failed.Count) {
        $ctx.State = 'warn'
        $shown = ($failed | Select-Object -First 3) -join ', '
        if ($failed.Count -gt 3) { $shown += ", +$($failed.Count - 3) more" }
        $ctx.Text += "; $($failed.Count) failed: $shown"
    }
    if ($retired.Count) {
        $ctx.Out.Retired = @($retired | ForEach-Object { $_.Name })
        $ctx.Text += "; $($retired.Count) retired Azure module(s) found"
    }
}

function Remove-RetiredModules {
    param([string[]]$Names)
    $left = @($Names)
    # Several passes: dependencies block removal until their dependents are gone
    for ($pass = 1; $pass -le 3 -and $left.Count; $pass++) {
        $next = @()
        for ($i = 0; $i -lt $left.Count; $i++) {
            SetStatus ((T 'Removing {0} ({1} of {2})') -f $left[$i], ($i + 1), $left.Count) (100 * $i / $left.Count)
            try { Uninstall-Module -Name $left[$i] -AllVersions -Force -ErrorAction Stop; Log "Removed $($left[$i])" 'detail' }
            catch { $next += $left[$i] }
        }
        $left = $next
    }
    return , $left
}
}

#endregion

#region ---------- Background workers ----------

# Every background job gets these, so engine code can report back to the window.
$WorkerPrelude = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
function Log([string]$Message, [string]$Kind = 'info') {
    $Sync.Queue.Enqueue([pscustomobject]@{ Type = 'log'; Text = $Message; Kind = $Kind })
}
function SetStatus([string]$Text, [double]$Percent = -1) {
    $Sync.Status = $Text
    if ($Percent -ge 0) { $Sync.Percent = $Sync.Base + [math]::Min(100, $Percent) * $Sync.Span / 100 }
    elseif ($Sync.Span -lt 100) { $Sync.Percent = $Sync.Base }
    else { $Sync.Percent = -1 }
}
function Step([string]$Key, [string]$State, [string]$Detail = '') {
    $Sync.Queue.Enqueue([pscustomobject]@{ Type = 'step'; Key = $Key; State = $State; Detail = $Detail })
}
'@

# UI-thread versions: engine helpers called directly from the window just do nothing with progress.
. $EngineCode
function Log { }
function SetStatus { }
function Step { }

$script:Workers = New-Object System.Collections.ArrayList
$script:Fg = $null           # the worker whose progress the task page shows
$script:DialogDepth = 0

function Start-Worker {
    param(
        [Parameter(Mandatory)][scriptblock]$Work,
        [object[]]$ArgumentList = @(),
        [scriptblock]$OnDone,
        [switch]$Foreground
    )
    $sync = [hashtable]::Synchronized(@{
        Queue   = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Status  = ''
        Percent = -1
        Base    = 0
        Span    = 100
    })
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry 'Sync', $sync, ''))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry 'Lang', $Lang, ''))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry 'Strings', $Strings, ''))
    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($WorkerPrelude + "`n" + $EngineCode.ToString() + "`n" + $script:FeatureEngine + "`n& {`n" + $Work.ToString() + "`n} @args")
    foreach ($a in $ArgumentList) { [void]$ps.AddArgument($a) }

    $w = [pscustomobject]@{ PS = $ps; RS = $rs; Handle = $null; Sync = $sync; OnDone = $OnDone; Foreground = [bool]$Foreground }
    $w.Handle = $ps.BeginInvoke()
    [void]$script:Workers.Add($w)
    if ($Foreground) { $script:Fg = $w }
}

# Called by a DispatcherTimer on the UI thread.
function Invoke-WorkerTick {
    foreach ($w in @($script:Workers)) {
        $item = $null
        while ($w.Sync.Queue.TryDequeue([ref]$item)) {
            if ($w.Foreground) { Receive-TaskMessage $item }
        }
        if ($w.Foreground -and $script:Fg -eq $w) { Update-TaskProgress $w }

        if (-not $w.Handle.IsCompleted) { continue }
        if ($script:DialogDepth -gt 0) { continue }   # don't chain into new dialogs while one is open

        $script:Workers.Remove($w)
        $result = $null; $err = $null
        try { $result = $w.PS.EndInvoke($w.Handle) }
        catch {
            $ex = $_.Exception
            while ($ex.InnerException) { $ex = $ex.InnerException }
            $err = $ex.Message
        }
        try { $w.PS.Dispose(); $w.RS.Dispose() } catch {}
        if ($script:Fg -eq $w) { $script:Fg = $null }

        if ($w.OnDone) {
            $r = $null
            if ($null -ne $result -and $result.Count -gt 0) { $r = $result[$result.Count - 1] }
            try { & $w.OnDone $r $err } catch { Show-Error $_ }
        }
    }
    if ($script:TaskBusy -and $script:TaskClock) {
        $ui.TxtTaskElapsed.Text = (T 'Time so far: {0:hh\:mm\:ss}') -f $script:TaskClock.Elapsed
    }
}

#endregion

#region ---------- XAML ----------

$ResourcesXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <!-- Color brushes (Bg, Surface, Text, Accent...) are added by Set-Theme -->
  <FontFamily x:Key="Icons">Segoe MDL2 Assets, Segoe UI Symbol</FontFamily>

  <Style x:Key="Card" TargetType="Border">
    <Setter Property="Background" Value="{DynamicResource Surface}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="CornerRadius" Value="8"/>
    <Setter Property="Padding" Value="18"/>
  </Style>

  <Style x:Key="Footer" TargetType="Border">
    <Setter Property="Background" Value="{DynamicResource Surface}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
    <Setter Property="BorderThickness" Value="0,1,0,0"/>
    <Setter Property="Padding" Value="24,12"/>
  </Style>

  <Style x:Key="MutedText" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource Muted}"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
  </Style>

  <Style x:Key="CardTitle" TargetType="TextBlock">
    <Setter Property="FontSize" Value="16"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Margin" Value="0,0,0,6"/>
  </Style>

  <Style x:Key="Mono" TargetType="TextBox">
    <Setter Property="FontFamily" Value="Consolas"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="IsReadOnly" Value="True"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Background" Value="{DynamicResource MonoBg}"/>
    <Setter Property="Padding" Value="10"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
    <Setter Property="Margin" Value="0,8,0,0"/>
  </Style>

  <Style x:Key="BtnBase" TargetType="Button">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Background" Value="{DynamicResource Surface}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource BtnLine}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="16,8"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="HorizontalContentAlignment" Value="Center"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6" Padding="{TemplateBinding Padding}"
                  SnapsToDevicePixels="True">
            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                              VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource Hover}"/></Trigger>
      <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{DynamicResource Pressed}"/></Trigger>
    </Style.Triggers>
  </Style>
  <Style TargetType="Button" BasedOn="{StaticResource BtnBase}"/>

  <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource BtnBase}">
    <Setter Property="Background" Value="{DynamicResource AccentFill}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource AccentFill}"/>
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource AccentFillHover}"/></Trigger>
      <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{DynamicResource AccentFillPressed}"/></Trigger>
    </Style.Triggers>
  </Style>

  <Style x:Key="Hero" TargetType="Button" BasedOn="{StaticResource BtnBase}">
    <Setter Property="Background" Value="White"/>
    <Setter Property="BorderBrush" Value="White"/>
    <Setter Property="Foreground" Value="#0F6CBD"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="15"/>
    <Setter Property="Padding" Value="22,12"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#EBF3FC"/></Trigger>
    </Style.Triggers>
  </Style>

  <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource BtnBase}">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderBrush" Value="Transparent"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{DynamicResource Hover}"/></Trigger>
    </Style.Triggers>
  </Style>

  <Style x:Key="Tile" TargetType="Button" BasedOn="{StaticResource BtnBase}">
    <Setter Property="Padding" Value="18,16"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
    <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
    <Setter Property="VerticalContentAlignment" Value="Top"/>
    <Setter Property="Margin" Value="0,0,12,12"/>
    <Style.Triggers>
      <Trigger Property="IsMouseOver" Value="True">
        <Setter Property="Background" Value="{DynamicResource TileHover}"/>
        <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
      </Trigger>
    </Style.Triggers>
  </Style>

  <Style TargetType="ProgressBar">
    <Setter Property="Height" Value="8"/>
    <Setter Property="Foreground" Value="{DynamicResource Accent}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ProgressBar">
          <Grid ClipToBounds="True">
            <Border x:Name="PART_Track" Background="{DynamicResource Track}" CornerRadius="4"/>
            <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="4" HorizontalAlignment="Left"/>
            <Border x:Name="Indet" Background="{TemplateBinding Foreground}" CornerRadius="4" Width="140"
                    HorizontalAlignment="Left" Visibility="Collapsed">
              <Border.RenderTransform><TranslateTransform X="-140"/></Border.RenderTransform>
            </Border>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsIndeterminate" Value="True">
              <Setter TargetName="PART_Indicator" Property="Visibility" Value="Collapsed"/>
              <Setter TargetName="Indet" Property="Visibility" Value="Visible"/>
              <Trigger.EnterActions>
                <BeginStoryboard x:Name="Sweep">
                  <Storyboard RepeatBehavior="Forever">
                    <DoubleAnimation Storyboard.TargetName="Indet"
                                     Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)"
                                     From="-140" To="1400" Duration="0:0:2.2"/>
                  </Storyboard>
                </BeginStoryboard>
              </Trigger.EnterActions>
              <Trigger.ExitActions><StopStoryboard BeginStoryboardName="Sweep"/></Trigger.ExitActions>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- The stock CheckBox / ComboBox / ScrollBar ignore our colors, so they get simple themed templates -->
  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Padding" Value="8,0,0,0"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Grid Background="Transparent">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border x:Name="box" Width="18" Height="18" CornerRadius="4" BorderThickness="1"
                    BorderBrush="{DynamicResource BtnLine}" Background="{DynamicResource Surface}"
                    VerticalAlignment="{TemplateBinding VerticalContentAlignment}">
              <TextBlock x:Name="mark" FontFamily="Segoe MDL2 Assets" Text="&#xE73E;" FontSize="12" Foreground="White"
                         HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
            </Border>
            <ContentPresenter Grid.Column="1" Margin="{TemplateBinding Padding}"
                              HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                              VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource Accent}"/></Trigger>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="box" Property="Background" Value="{DynamicResource AccentFill}"/>
              <Setter TargetName="box" Property="BorderBrush" Value="{DynamicResource AccentFill}"/>
              <Setter TargetName="mark" Property="Visibility" Value="Visible"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ComboBox">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Background" Value="{DynamicResource Surface}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource BtnLine}"/>
    <Setter Property="Padding" Value="10,6"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBox">
          <Grid>
            <ToggleButton Focusable="False" ClickMode="Press"
                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
              <ToggleButton.Template>
                <ControlTemplate TargetType="ToggleButton">
                  <Border x:Name="bd" CornerRadius="6" BorderThickness="1"
                          Background="{Binding Background, RelativeSource={RelativeSource AncestorType=ComboBox}}"
                          BorderBrush="{Binding BorderBrush, RelativeSource={RelativeSource AncestorType=ComboBox}}">
                    <TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE70D;" FontSize="10" Foreground="{DynamicResource Muted}"
                               HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"/>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
                    <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </ToggleButton.Template>
            </ToggleButton>
            <ContentPresenter IsHitTestVisible="False" Margin="{TemplateBinding Padding}" VerticalAlignment="Center" HorizontalAlignment="Left"
                              Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
            <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True"
                   Focusable="False" PopupAnimation="Fade">
              <Border Background="{DynamicResource Surface}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="6"
                      Margin="0,4,0,0" Padding="4" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                <ScrollViewer MaxHeight="300"><ItemsPresenter/></ScrollViewer>
              </Border>
            </Popup>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ComboBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="Padding" Value="10,7"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBoxItem">
          <Border x:Name="bd" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsSelected" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource AccentLight}"/></Trigger>
            <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="bd" Property="Background" Value="{DynamicResource Hover}"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <ControlTemplate x:Key="ThumbTemplate" TargetType="Thumb">
    <Border x:Name="t" Background="{DynamicResource ScrollThumb}" CornerRadius="3"/>
    <ControlTemplate.Triggers>
      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Background" Value="{DynamicResource Muted}"/></Trigger>
    </ControlTemplate.Triggers>
  </ControlTemplate>
  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="12"/>
    <Setter Property="MinWidth" Value="12"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Grid Background="Transparent">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb><Thumb Template="{StaticResource ThumbTemplate}" Margin="3,2"/></Track.Thumb>
            </Track>
          </Grid>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="Orientation" Value="Horizontal">
        <Setter Property="Width" Value="Auto"/>
        <Setter Property="MinWidth" Value="0"/>
        <Setter Property="Height" Value="12"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="ScrollBar">
              <Grid Background="Transparent">
                <Track x:Name="PART_Track">
                  <Track.Thumb><Thumb Template="{StaticResource ThumbTemplate}" Margin="2,3"/></Track.Thumb>
                </Track>
              </Grid>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Trigger>
    </Style.Triggers>
  </Style>

  <Style TargetType="ToolTip">
    <Setter Property="Background" Value="{DynamicResource Surface}"/>
    <Setter Property="Foreground" Value="{DynamicResource Text}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource Line}"/>
  </Style>
</ResourceDictionary>
'@

# Light and dark palettes. Every key becomes a SolidColorBrush in the app resources (see Set-Theme).
$Themes = @{
    Light = @{
        Bg = '#F5F5F7'; Surface = '#FFFFFF'; Line = '#E1E1E6'; LineSoft = '#F0F0F3'
        Text = '#1B1B1F'; Muted = '#5F5F6B'; Faint = '#8A8A94'
        Accent = '#0F6CBD'; AccentLight = '#EBF3FC'; AccentFill = '#0F6CBD'; AccentFillHover = '#0C5A9E'; AccentFillPressed = '#0A4A82'
        Hover = '#F0F0F3'; Pressed = '#E4E4E9'; BtnLine = '#CFCFD6'; TileHover = '#FAFCFF'
        MonoBg = '#F7F7F9'; Track = '#E1E1E6'; ScrollThumb = '#C2C2C8'
        Good = '#107C10'; Warn = '#9D5D00'; Bad = '#C42B1C'
        GoodBg = '#DFF6DD'; GoodLine = '#9FD89F'; WarnBg = '#FFF4CE'; WarnLine = '#F2D58A'
        BadBg = '#FDE7E9'; BadLine = '#F1BBBC'; InfoBg = '#EBF3FC'; InfoLine = '#B4D6FA'
    }
    Dark = @{
        Bg = '#1C1C1C'; Surface = '#2B2B2B'; Line = '#3B3B3B'; LineSoft = '#343434'
        Text = '#F3F3F3'; Muted = '#B5B5BD'; Faint = '#8C8C94'
        Accent = '#6CB8F5'; AccentLight = '#233A50'; AccentFill = '#1F74C7'; AccentFillHover = '#2A82D6'; AccentFillPressed = '#1964AE'
        Hover = '#363636'; Pressed = '#404040'; BtnLine = '#4A4A4A'; TileHover = '#2F343A'
        MonoBg = '#222222'; Track = '#3D3D3D'; ScrollThumb = '#5A5A5A'
        Good = '#6CCB5F'; Warn = '#F2C04C'; Bad = '#FF99A4'
        GoodBg = '#1F3520'; GoodLine = '#2F5A2F'; WarnBg = '#3D3118'; WarnLine = '#6B5420'
        BadBg = '#442726'; BadLine = '#6E3A3A'; InfoBg = '#1E3448'; InfoLine = '#2F5577'
    }
}

function Esc([string]$s) { ([Security.SecurityElement]::Escape([string]$s)) -replace "`r?`n", '&#10;' }
# Translated and XML-escaped, for use inside XAML: Text="$(X 'Free up space')"
function X([string]$s) { Esc (T $s) }

#--- Features: each tool page registers itself (core ones below, more in features\*.ps1) ---
#
# Register-Feature @{
#     Name    = 'Printer'                          # unique; tile is named "Tile<Name>", -StartPage <Name> opens it
#     Section = 'fix'                              # home section: fix | tidy | settings | info
#     Order   = 20                                 # position inside the section
#     Glyph   = 'E749'                             # Segoe MDL2 Assets code point
#     Title   = 'Printer problems'                 # English; translated with T
#     Desc    = 'Clear stuck print jobs ...'       # English; translated with T
#     Open    = { Open-Printer }                   # runs when the tile is clicked
#     Xaml    = '<DockPanel x:Name="PanelPrinter" Visibility="Collapsed">...</DockPanel>'   # optional page
#     Panel   = 'PanelPrinter'                     # x:Name of that page root
#     Init    = { $ui.BtnPrinterFix.Add_Click({ ... }) }                                  # optional, after the window exists
#     Engine  = { function Get-PrinterState { ... } }                                       # optional, functions for background jobs
# }
$Features = New-Object System.Collections.ArrayList
function Register-Feature([hashtable]$Feature) { [void]$Features.Add([pscustomobject]$Feature) }

$Sections = [ordered]@{
    fix      = 'Fix a problem'
    tidy     = 'Clean and update'
    settings = 'Settings and safety'
    info     = 'Information'
}

# Core Norwegian text first: page XAML below is translated when it is built
$LangFile = Join-Path $AppDir 'lang\nb.ps1'
if (Test-Path $LangFile) { . $LangFile }

Register-Feature @{ Name = 'Sleep';   Section = 'fix';      Order = 50; Glyph = 'E708'; Title = 'Sleep and wake';  Desc = "Find out why your PC wakes up by itself or won't sleep."; Open = { Open-Sleep } }
Register-Feature @{ Name = 'Battery'; Section = 'fix';      Order = 60; Glyph = 'E83F'; Title = 'Battery health';  Desc = (T 'Check how well your battery still holds a charge.'); Open = { Open-Battery } }
Register-Feature @{ Name = 'Apps';    Section = 'tidy';     Order = 10; Glyph = 'E71D'; Title = 'App updates';     Desc = (T 'See which apps have updates and choose what to install.'); Open = { Open-Apps } }
Register-Feature @{ Name = 'Clean';   Section = 'tidy';     Order = 20; Glyph = 'E74D'; Title = 'Free up space';   Desc = (T 'Remove temporary files and empty the Recycle Bin.'); Open = { Open-Clean } }
Register-Feature @{
    Name = 'Restore'; Section = 'settings'; Order = 20; Glyph = 'E777'; Title = 'Restore point'
    Desc = 'Take a safety snapshot so system changes can be undone.'
    Open = { Open-Restore }
    Panel = 'PanelRestore'
    Xaml = @"
          <ScrollViewer x:Name="PanelRestore" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
            <StackPanel Margin="24,8,24,24" MaxWidth="760" HorizontalAlignment="Left">
              <Border x:Name="RestoreBlocked" Background="{DynamicResource InfoBg}" BorderBrush="{DynamicResource InfoLine}" BorderThickness="1"
                      CornerRadius="8" Padding="16" Margin="0,0,0,12" Visibility="Collapsed">
                <DockPanel>
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE946;" FontSize="18" Foreground="{DynamicResource Accent}" Margin="0,0,12,0" VerticalAlignment="Top"/>
                  <TextBlock TextWrapping="Wrap" Text="$(X 'Your organization has turned off restore points on this PC, so PC Maintenance never creates or asks about them.')"/>
                </DockPanel>
              </Border>
              <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                <StackPanel>
                  <CheckBox x:Name="ChkRestoreBefore" FontWeight="SemiBold" Content="$(X 'Create a restore point before updates')"/>
                  <TextBlock Style="{StaticResource MutedText}" Margin="26,6,0,0"
                             Text="$(X 'Recommended on your own PC. Turn it off if restore points aren''t allowed, which is common on work PCs. Then PC Maintenance never creates or asks about them.')"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}">
                <StackPanel>
                  <TextBlock Text="$(X 'Create one now')" Style="{StaticResource CardTitle}"/>
                  <TextBlock Style="{StaticResource MutedText}" Text="$(X 'Useful before you change settings or install something yourself. Needs administrator rights.')"/>
                  <Button x:Name="BtnRestoreNow" HorizontalAlignment="Left" Margin="0,12,0,0" Content="$(X 'Create a restore point')"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </ScrollViewer>
"@
    Init = {
        $ui.ChkRestoreBefore.Add_Click({ Set-RestoreBefore })
        $ui.BtnRestoreNow.Add_Click({ Start-RestorePointTask })
    }
}
Register-Feature @{ Name = 'Power';   Section = 'settings'; Order = 30; Glyph = 'E7F8'; Title = 'Lid and sign-in'; Desc = (T 'Choose what closing the lid does and when a password is needed.'); Open = { Open-Power } }
Register-Feature @{ Name = 'Info';    Section = 'info';     Order = 10; Glyph = 'E7F4'; Title = 'About this PC';   Desc = (T 'Model, Windows version, memory and disks. Handy for IT support.'); Open = { Open-Info } }
Register-Feature @{ Name = 'WU';      Section = 'info';     Order = 90; Glyph = 'E713'; Title = 'Windows Update';  Desc = (T 'Open the Windows Update page in Settings.'); Open = { Start-Process 'ms-settings:windowsupdate' } }

# Feature files (each adds its own Norwegian strings and registers itself)
foreach ($f in @(Get-ChildItem (Join-Path $AppDir 'features') -Filter *.ps1 -ErrorAction SilentlyContinue | Sort-Object Name)) {
    . $f.FullName
}
foreach ($f in $Features) { if ($f.Engine) { . $f.Engine } }
$script:FeatureEngine = (@($Features | Where-Object { $_.Engine } | ForEach-Object { $_.Engine.ToString() }) -join "`n")

$TilesXaml = (@(foreach ($sec in $Sections.Keys) {
    $tiles = @($Features | Where-Object { $_.Section -eq $sec -and $_.Title } | Sort-Object Order)
    if (-not $tiles.Count) { continue }
@"
          <TextBlock Text="$(X $Sections[$sec])" FontSize="16" FontWeight="SemiBold" Margin="0,14,0,10"/>
          <UniformGrid Columns="3">
"@
    foreach ($t in $tiles) {
@"
            <Button x:Name="Tile$($t.Name)" Style="{StaticResource Tile}">
              <DockPanel>
                <Border DockPanel.Dock="Left" Width="40" Height="40" CornerRadius="8" Background="{DynamicResource AccentLight}" VerticalAlignment="Top">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#x$($t.Glyph);" FontSize="19" Foreground="{DynamicResource Accent}"
                             HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel Margin="14,0,0,0">
                  <TextBlock Text="$(X $t.Title)" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
                  <TextBlock Text="$(X $t.Desc)" Style="{StaticResource MutedText}" FontSize="13" Margin="0,3,0,0"/>
                </StackPanel>
              </DockPanel>
            </Button>
"@
    }
    '          </UniformGrid>'
}) -join "`n")

$FeaturePanelsXaml = (@($Features | Where-Object { $_.Xaml } | ForEach-Object { $_.Xaml }) -join "`n")

$CleanItems = @(
    [pscustomobject]@{ Key = 'usertemp'; Label = (T 'Temporary files');                 Admin = $false; Default = $true;  Desc = (T 'Leftovers from apps and installers. Safe to remove.') }
    [pscustomobject]@{ Key = 'wintemp';  Label = (T 'Windows temporary files');         Admin = $true;  Default = $true;  Desc = (T 'Leftovers from Windows itself and system installers.') }
    [pscustomobject]@{ Key = 'recycle';  Label = (T 'Recycle Bin');                     Admin = $false; Default = $false; Desc = (T "Files you have deleted. They can't be recovered afterwards.") }
    [pscustomobject]@{ Key = 'delivery'; Label = (T 'Update download cache');           Admin = $true;  Default = $true;  Desc = (T 'Copies of Windows updates that are already installed.') }
    [pscustomobject]@{ Key = 'dism';     Label = (T 'Old versions of Windows components'); Admin = $true; Default = $false; Desc = (T 'Frees more space, but is slow (often 10 to 30 minutes).') }
)
$CleanXaml = ($CleanItems | ForEach-Object {
@"
          <Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="0,0,0,1" Padding="18,14">
            <DockPanel>
              <TextBlock x:Name="TxtCleanSize_$($_.Key)" DockPanel.Dock="Right" VerticalAlignment="Center" FontWeight="SemiBold" Margin="16,0,0,0"/>
              <CheckBox x:Name="ChkClean_$($_.Key)" VerticalContentAlignment="Center">
                <StackPanel Margin="8,0,0,0">
                  <TextBlock Text="$(Esc $_.Label)" FontWeight="SemiBold"/>
                  <TextBlock x:Name="TxtCleanDesc_$($_.Key)" Text="$(Esc $_.Desc)" Style="{StaticResource MutedText}" FontSize="13"/>
                </StackPanel>
              </CheckBox>
            </DockPanel>
          </Border>
"@
}) -join "`n"

$MainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PC Maintenance" Width="1060" Height="780" MinWidth="880" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource Bg}"
        FontFamily="Segoe UI" FontSize="14" Foreground="{DynamicResource Text}"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Border Background="{DynamicResource Surface}" BorderBrush="{DynamicResource Line}" BorderThickness="0,0,0,1" Padding="24,12">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnLang" Style="{StaticResource Ghost}" Padding="10,8" Margin="0,0,4,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE774;" VerticalAlignment="Center"/>
              <TextBlock x:Name="TxtLang" Margin="8,0,0,0"/>
            </StackPanel>
          </Button>
          <Button x:Name="BtnTheme" Style="{StaticResource Ghost}" Padding="10,9" Margin="0,0,8,0">
            <TextBlock x:Name="ThemeIcon" FontFamily="{StaticResource Icons}" FontSize="16"/>
          </Button>
          <Border x:Name="AdminBadge" Background="{DynamicResource GoodBg}" CornerRadius="14" Padding="12,5" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock FontFamily="{StaticResource Icons}" Text="&#xEA18;" Foreground="{DynamicResource Good}" VerticalAlignment="Center"/>
              <TextBlock Text="$(X 'Administrator')" Foreground="{DynamicResource Good}" FontWeight="SemiBold" Margin="6,0,0,0" FontSize="13"/>
            </StackPanel>
          </Border>
          <Button x:Name="BtnElevate" Visibility="Collapsed" ToolTip="$(X 'Some features need administrator rights. You may be asked for permission.')">
            <StackPanel Orientation="Horizontal">
              <TextBlock FontFamily="{StaticResource Icons}" Text="&#xEA18;" Foreground="{DynamicResource Accent}" VerticalAlignment="Center"/>
              <TextBlock Text="$(X 'Run as administrator')" Margin="8,0,0,0"/>
            </StackPanel>
          </Button>
        </StackPanel>
        <StackPanel Orientation="Horizontal">
          <Border Width="38" Height="38" CornerRadius="9" Background="{DynamicResource AccentFill}">
            <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE90F;" FontSize="20" Foreground="White"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="$(X 'PC Maintenance')" FontSize="18" FontWeight="SemiBold"/>
            <TextBlock x:Name="TxtVersion" FontSize="12" Foreground="{DynamicResource Muted}"/>
          </StackPanel>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- "New version downloaded" banner -->
    <Border x:Name="Banner" Grid.Row="1" Visibility="Collapsed" Background="{DynamicResource InfoBg}" BorderBrush="{DynamicResource InfoLine}" BorderThickness="0,0,0,1" Padding="24,10">
      <DockPanel>
        <Button x:Name="BtnBanner" DockPanel.Dock="Right" Content="$(X 'Restart app')" Padding="14,6"/>
        <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE946;" Foreground="{DynamicResource Accent}" VerticalAlignment="Center" Margin="0,0,10,0"/>
        <TextBlock x:Name="TxtBanner" VerticalAlignment="Center" TextWrapping="Wrap"/>
      </DockPanel>
    </Border>

    <Grid Grid.Row="2">
      <!-- ===== Home ===== -->
      <ScrollViewer x:Name="PageHome" VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="24,20,12,16">
          <Border CornerRadius="10" Padding="26,22" Margin="0,0,12,0">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#0F6CBD" Offset="0"/>
                <GradientStop Color="#3A8EE0" Offset="1"/>
              </LinearGradientBrush>
            </Border.Background>
            <DockPanel>
              <Button x:Name="BtnUpdateAll" DockPanel.Dock="Right" Style="{StaticResource Hero}" VerticalAlignment="Center">
                <StackPanel Orientation="Horizontal">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE895;" VerticalAlignment="Center"/>
                  <TextBlock Text="$(X 'Update everything')" Margin="10,0,0,0"/>
                </StackPanel>
              </Button>
              <StackPanel Margin="0,0,24,0">
                <TextBlock Text="$(X 'Keep this PC up to date')" FontSize="22" FontWeight="SemiBold" Foreground="White"/>
                <TextBlock Foreground="#E6F0FA" TextWrapping="Wrap" Margin="0,6,0,0"
                           Text="$(X 'One click updates your apps, Windows and drivers, Microsoft Store apps, Office and virus protection.')"/>
              </StackPanel>
            </DockPanel>
          </Border>

          <!-- PC checkup: problems with a fix button each -->
          <Border x:Name="CheckupCard" Style="{StaticResource Card}" Margin="0,16,12,0">
            <StackPanel>
              <DockPanel>
                <TextBlock x:Name="CheckupIcon" FontFamily="{StaticResource Icons}" Text="&#xE9D9;" FontSize="24" Foreground="{DynamicResource Accent}"
                           VerticalAlignment="Center" Margin="0,0,14,0"/>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock x:Name="TxtCheckupTitle" FontSize="18" FontWeight="SemiBold" Text="$(X 'Checking your PC...')"/>
                  <TextBlock x:Name="TxtCheckupSub" Style="{StaticResource MutedText}" Text="$(X 'Looking at disk space, updates, security and more.')"/>
                </StackPanel>
              </DockPanel>
              <StackPanel x:Name="CheckupRows" Margin="0,6,0,0"/>
              <TextBlock x:Name="TxtCheckupPassed" Style="{StaticResource MutedText}" FontSize="13" Margin="0,10,0,0" Visibility="Collapsed"/>
            </StackPanel>
          </Border>

          <TextBlock Text="$(X 'Status')" FontSize="16" FontWeight="SemiBold" Margin="0,22,0,10"/>
          <UniformGrid Columns="4">
            <Border Style="{StaticResource Card}" Margin="0,0,12,12">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xEDA2;" Foreground="{DynamicResource Muted}" VerticalAlignment="Center"/>
                  <TextBlock Text="$(X 'Disk space')" Foreground="{DynamicResource Muted}" FontSize="13" Margin="8,0,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtDiskMain" Text="..." FontSize="20" FontWeight="SemiBold" Margin="0,10,0,8"/>
                <ProgressBar x:Name="DiskBar" Height="6" Maximum="100"/>
                <TextBlock x:Name="TxtDiskSub" Style="{StaticResource MutedText}" FontSize="13" Margin="0,8,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="0,0,12,12">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE83F;" Foreground="{DynamicResource Muted}" VerticalAlignment="Center"/>
                  <TextBlock Text="$(X 'Battery')" Foreground="{DynamicResource Muted}" FontSize="13" Margin="8,0,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtBatMain" Text="..." FontSize="20" FontWeight="SemiBold" Margin="0,10,0,0"/>
                <TextBlock x:Name="TxtBatSub" Style="{StaticResource MutedText}" FontSize="13" Margin="0,8,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="0,0,12,12">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE7E8;" Foreground="{DynamicResource Muted}" VerticalAlignment="Center"/>
                  <TextBlock Text="$(X 'Restart')" Foreground="{DynamicResource Muted}" FontSize="13" Margin="8,0,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtRebootMain" Text="..." FontSize="20" FontWeight="SemiBold" Margin="0,10,0,0"/>
                <TextBlock x:Name="TxtRebootSub" Style="{StaticResource MutedText}" FontSize="13" Margin="0,8,0,0"/>
                <Button x:Name="BtnRestartHome" Content="$(X 'Restart now')" HorizontalAlignment="Left" Padding="12,5" Margin="0,10,0,0" Visibility="Collapsed"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="0,0,12,12">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE823;" Foreground="{DynamicResource Muted}" VerticalAlignment="Center"/>
                  <TextBlock Text="$(X 'Running for')" Foreground="{DynamicResource Muted}" FontSize="13" Margin="8,0,0,0"/>
                </StackPanel>
                <TextBlock x:Name="TxtUpMain" Text="..." FontSize="20" FontWeight="SemiBold" Margin="0,10,0,0"/>
                <TextBlock x:Name="TxtUpSub" Style="{StaticResource MutedText}" FontSize="13" Margin="0,8,0,0"/>
              </StackPanel>
            </Border>
          </UniformGrid>

$TilesXaml
        </StackPanel>
      </ScrollViewer>

      <!-- ===== Sub pages ===== -->
      <DockPanel x:Name="PageSub" Visibility="Collapsed">
        <Border DockPanel.Dock="Top" Padding="14,14,24,8">
          <DockPanel>
            <Button x:Name="BtnBack" Style="{StaticResource Ghost}" VerticalAlignment="Top" Padding="10,9" Margin="0,0,8,0" ToolTip="$(X 'Back')">
              <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE72B;" FontSize="16"/>
            </Button>
            <StackPanel>
              <TextBlock x:Name="TxtPageTitle" FontSize="24" FontWeight="SemiBold"/>
              <TextBlock x:Name="TxtPageSub" Style="{StaticResource MutedText}" Margin="0,2,0,0"/>
            </StackPanel>
          </DockPanel>
        </Border>
        <Grid>

          <!-- App updates -->
          <DockPanel x:Name="PanelApps" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnAppsUpdate" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="$(X 'Update selected')"/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnAppsSelect" Content="$(X 'Select none')"/>
                  <Button x:Name="BtnAppsRefresh" Margin="8,0,0,0">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE72C;" VerticalAlignment="Center"/>
                      <TextBlock Text="$(X 'Check again')" Margin="8,0,0,0"/>
                    </StackPanel>
                  </Button>
                  <CheckBox x:Name="ChkAppsUnknown" VerticalAlignment="Center" Margin="16,0,0,0"
                            Content="$(X 'Include apps with an unknown version')"
                            ToolTip="$(X 'Some apps don''t report their version. They may show up as ''needs update'' every time.')"/>
                </StackPanel>
              </DockPanel>
            </Border>
            <Grid Margin="24,8,24,16">
              <StackPanel x:Name="AppsLoading" VerticalAlignment="Center" HorizontalAlignment="Center">
                <TextBlock Text="$(X 'Checking for app updates...')" FontSize="16" HorizontalAlignment="Center"/>
                <ProgressBar IsIndeterminate="True" Width="260" Margin="0,14,0,0"/>
              </StackPanel>
              <StackPanel x:Name="AppsEmpty" VerticalAlignment="Center" HorizontalAlignment="Center" Visibility="Collapsed" MaxWidth="520">
                <TextBlock x:Name="AppsEmptyIcon" FontFamily="{StaticResource Icons}" FontSize="44" HorizontalAlignment="Center"/>
                <TextBlock x:Name="AppsEmptyTitle" FontSize="20" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,14,0,0" TextAlignment="Center" TextWrapping="Wrap"/>
                <TextBlock x:Name="AppsEmptyText" Style="{StaticResource MutedText}" HorizontalAlignment="Center" TextAlignment="Center" Margin="0,6,0,0"/>
              </StackPanel>
              <Border x:Name="AppsCard" Style="{StaticResource Card}" Padding="0" Visibility="Collapsed">
                <DockPanel>
                  <Border DockPanel.Dock="Top" BorderBrush="{DynamicResource LineSoft}" BorderThickness="0,0,0,1" Padding="18,10">
                    <Grid TextElement.Foreground="{DynamicResource Muted}" TextElement.FontSize="12">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="30"/><ColumnDefinition Width="*"/><ColumnDefinition Width="170"/><ColumnDefinition Width="170"/>
                      </Grid.ColumnDefinitions>
                      <TextBlock Grid.Column="1" Text="$(X 'APP')"/>
                      <TextBlock Grid.Column="2" Text="$(X 'YOU HAVE')"/>
                      <TextBlock Grid.Column="3" Text="$(X 'NEW VERSION')"/>
                    </Grid>
                  </Border>
                  <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel x:Name="AppsList"/>
                  </ScrollViewer>
                </DockPanel>
              </Border>
            </Grid>
          </DockPanel>

          <!-- Free up space -->
          <DockPanel x:Name="PanelClean" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnCleanRun" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="$(X 'Clean up selected')"/>
                <Button x:Name="BtnCleanMgr" Content="$(X 'Open Windows Disk Cleanup')" HorizontalAlignment="Left"/>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                  <StackPanel>
                    <DockPanel>
                      <TextBlock x:Name="TxtCleanFree" DockPanel.Dock="Right" Foreground="{DynamicResource Muted}"/>
                      <TextBlock x:Name="TxtCleanDrive" FontWeight="SemiBold"/>
                    </DockPanel>
                    <ProgressBar x:Name="CleanBar" Height="10" Margin="0,10,0,0" Maximum="100"/>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Padding="0">
                  <StackPanel>
$CleanXaml
                  </StackPanel>
                </Border>
                <TextBlock x:Name="TxtCleanAdminNote" Style="{StaticResource MutedText}" Margin="2,12,0,0" Visibility="Collapsed"
                           Text="$(X 'Some items need administrator rights. Use ''Run as administrator'' at the top to include them.')"/>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>

          <!-- Battery -->
          <ScrollViewer x:Name="PanelBattery" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
            <StackPanel Margin="24,8,24,24" MaxWidth="900" HorizontalAlignment="Left">
              <TextBlock x:Name="TxtBatLoading" Text="$(X 'Reading battery information...')" Style="{StaticResource MutedText}"/>
              <StackPanel x:Name="BatContent" Visibility="Collapsed">
                <UniformGrid Columns="2">
                  <Border Style="{StaticResource Card}" Margin="0,0,12,12">
                    <StackPanel>
                      <TextBlock Text="$(X 'Charge right now')" Foreground="{DynamicResource Muted}" FontSize="13"/>
                      <TextBlock x:Name="TxtBatCharge" FontSize="40" FontWeight="SemiBold" Margin="0,4,0,8"/>
                      <ProgressBar x:Name="BatChargeBar" Height="10" Maximum="100"/>
                      <TextBlock x:Name="TxtBatSource" Style="{StaticResource MutedText}" Margin="0,10,0,0"/>
                    </StackPanel>
                  </Border>
                  <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                    <StackPanel>
                      <TextBlock Text="$(X 'Battery health')" Foreground="{DynamicResource Muted}" FontSize="13"/>
                      <TextBlock x:Name="TxtBatHealth" FontSize="40" FontWeight="SemiBold" Margin="0,4,0,8"/>
                      <ProgressBar x:Name="BatHealthBar" Height="10" Maximum="100"/>
                      <TextBlock x:Name="TxtBatCap" Style="{StaticResource MutedText}" Margin="0,10,0,0"/>
                    </StackPanel>
                  </Border>
                </UniformGrid>
                <Border x:Name="BatVerdict" CornerRadius="8" Padding="16" BorderThickness="1">
                  <DockPanel>
                    <TextBlock x:Name="BatVerdictIcon" FontFamily="{StaticResource Icons}" FontSize="20" VerticalAlignment="Top" Margin="0,0,12,0"/>
                    <TextBlock x:Name="TxtBatVerdict" TextWrapping="Wrap" VerticalAlignment="Center"/>
                  </DockPanel>
                </Border>
                <TextBlock Style="{StaticResource MutedText}" Margin="2,14,0,0"
                           Text="$(X 'Health compares how much energy the battery can hold today with how much it held when it was new. All batteries slowly wear out. Below about 80% you''ll notice it doesn''t last as long as it used to.')"/>
                <Button x:Name="BtnBatReport" HorizontalAlignment="Left" Margin="0,18,0,0">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE9F9;" VerticalAlignment="Center"/>
                    <TextBlock Text="$(X 'Create detailed battery report')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
              </StackPanel>
            </StackPanel>
          </ScrollViewer>

          <!-- Sleep and wake -->
          <DockPanel x:Name="PanelSleep" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnSleepStudy" DockPanel.Dock="Right" Content="$(X 'Create sleep report')"
                        ToolTip="$(X 'A detailed report of the last few days of sleep (Modern Standby PCs only). Needs administrator rights.')"/>
                <Button x:Name="BtnSleepRefresh" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE72C;" VerticalAlignment="Center"/>
                    <TextBlock Text="$(X 'Refresh')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <TextBlock x:Name="TxtSleepLoading" Text="$(X 'Reading sleep information...')" Style="{StaticResource MutedText}"/>
                <StackPanel x:Name="SleepContent" Visibility="Collapsed">
                  <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                    <StackPanel>
                      <TextBlock Text="$(X 'What woke your PC last time')" Style="{StaticResource CardTitle}"/>
                      <TextBox x:Name="TxtLastWake" Style="{StaticResource Mono}"/>
                    </StackPanel>
                  </Border>
                  <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                    <StackPanel>
                      <TextBlock Text="$(X 'Devices that can wake your PC')" Style="{StaticResource CardTitle}"/>
                      <TextBlock Style="{StaticResource MutedText}" Text="$(X 'A mouse, keyboard or network adapter can wake the PC from sleep. If your PC keeps waking up by itself, stop the device that woke it.')"/>
                      <StackPanel x:Name="WakeDevices" Margin="0,10,0,0"/>
                    </StackPanel>
                  </Border>
                  <StackPanel x:Name="SleepAdmin">
                    <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                      <StackPanel>
                        <TextBlock Text="$(X 'Scheduled wake-ups')" Style="{StaticResource CardTitle}"/>
                        <TextBlock Style="{StaticResource MutedText}" Text="$(X 'Programs or Windows tasks that have asked to wake the PC at a certain time.')"/>
                        <TextBox x:Name="TxtWakeTimers" Style="{StaticResource Mono}"/>
                      </StackPanel>
                    </Border>
                    <Border Style="{StaticResource Card}" Margin="0,0,0,12">
                      <StackPanel>
                        <TextBlock Text="$(X 'What''s keeping your PC awake right now')" Style="{StaticResource CardTitle}"/>
                        <TextBlock Style="{StaticResource MutedText}" Text="$(X 'Anything listed here (a video call, media playing, a download) can stop the PC from going to sleep.')"/>
                        <TextBox x:Name="TxtRequests" Style="{StaticResource Mono}"/>
                      </StackPanel>
                    </Border>
                  </StackPanel>
                  <TextBlock x:Name="TxtSleepAdminNote" Style="{StaticResource MutedText}" Margin="2,0,0,0"
                             Text="$(X 'Run as administrator to also see scheduled wake-ups and what''s keeping the PC awake, and to stop devices from waking it.')"/>
                </StackPanel>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>

          <!-- Lid and sign-in -->
          <DockPanel x:Name="PanelPower" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnPowerSave" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="$(X 'Save changes')"/>
                <StackPanel x:Name="PowerSaved" Orientation="Horizontal" VerticalAlignment="Center" Visibility="Collapsed">
                  <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE73E;" Foreground="{DynamicResource Good}" VerticalAlignment="Center"/>
                  <TextBlock Text="$(X 'Saved')" Foreground="{DynamicResource Good}" FontWeight="SemiBold" Margin="8,0,0,0"/>
                </StackPanel>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24" MaxWidth="760" HorizontalAlignment="Left">
                <Border x:Name="CardLid" Style="{StaticResource Card}" Margin="0,0,0,12">
                  <StackPanel>
                    <TextBlock Text="$(X 'When I close the lid')" Style="{StaticResource CardTitle}"/>
                    <TextBlock Style="{StaticResource MutedText}" Text="$(X '''Sleep'' is a good choice for most people: the PC wakes up quickly where you left off.')"/>
                    <Grid Margin="0,14,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="160"/><ColumnDefinition Width="240"/></Grid.ColumnDefinitions>
                      <Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                      <TextBlock Text="$(X 'Plugged in')" VerticalAlignment="Center"/>
                      <ComboBox x:Name="CmbLidAC" Grid.Column="1" Padding="8,6">
                        <ComboBoxItem Content="$(X 'Do nothing')"/><ComboBoxItem Content="$(X 'Sleep')"/><ComboBoxItem Content="$(X 'Hibernate')"/><ComboBoxItem Content="$(X 'Shut down')"/>
                      </ComboBox>
                      <TextBlock Grid.Row="1" Text="$(X 'On battery')" VerticalAlignment="Center" Margin="0,10,0,0"/>
                      <ComboBox x:Name="CmbLidDC" Grid.Row="1" Grid.Column="1" Padding="8,6" Margin="0,10,0,0">
                        <ComboBoxItem Content="$(X 'Do nothing')"/><ComboBoxItem Content="$(X 'Sleep')"/><ComboBoxItem Content="$(X 'Hibernate')"/><ComboBoxItem Content="$(X 'Shut down')"/>
                      </ComboBox>
                    </Grid>
                  </StackPanel>
                </Border>
                <Border x:Name="CardNoLid" Style="{StaticResource Card}" Margin="0,0,0,12" Visibility="Collapsed">
                  <TextBlock Style="{StaticResource MutedText}" Text="$(X 'This PC doesn''t have a lid setting (it''s probably a desktop PC).')"/>
                </Border>
                <Border Style="{StaticResource Card}">
                  <StackPanel>
                    <TextBlock Text="$(X 'Ask for my password after sleep')" Style="{StaticResource CardTitle}"/>
                    <TextBlock Style="{StaticResource MutedText}" Text="$(X 'When this is on, you have to sign in again when the PC wakes up. This keeps your files safe if someone else opens your PC.')"/>
                    <ComboBox x:Name="CmbSignIn" Width="240" HorizontalAlignment="Left" Margin="0,14,0,0" Padding="8,6">
                      <ComboBoxItem Content="$(X 'Yes, every time')"/><ComboBoxItem Content="$(X 'No, never')"/>
                    </ComboBox>
                    <TextBlock x:Name="TxtSignInNote" Style="{StaticResource MutedText}" FontSize="12" Margin="0,8,0,0"/>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>

          <!-- About this PC -->
          <DockPanel x:Name="PanelInfo" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnInfoCopy" DockPanel.Dock="Right" Style="{StaticResource Primary}">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock FontFamily="{StaticResource Icons}" Text="&#xE8C8;" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TxtInfoCopy" Text="$(X 'Copy details')" Margin="8,0,0,0"/>
                  </StackPanel>
                </Button>
                <TextBlock Style="{StaticResource MutedText}" VerticalAlignment="Center" Text="$(X 'Tip: paste the details into a message when you contact IT support.')"/>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <TextBlock x:Name="TxtInfoLoading" Text="$(X 'Reading PC information...')" Style="{StaticResource MutedText}"/>
                <Border x:Name="InfoCard" Style="{StaticResource Card}" Visibility="Collapsed" Padding="18,8">
                  <StackPanel x:Name="InfoRows"/>
                </Border>
                <TextBlock x:Name="InfoDisksTitle" Text="$(X 'Disks')" Style="{StaticResource CardTitle}" Margin="0,18,0,8" Visibility="Collapsed"/>
                <StackPanel x:Name="InfoDisks"/>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>

          <!-- Pages from features\*.ps1 -->
$FeaturePanelsXaml

          <!-- Running task -->
          <DockPanel x:Name="PanelTask" Visibility="Collapsed">
            <Border DockPanel.Dock="Bottom" Style="{StaticResource Footer}">
              <DockPanel>
                <Button x:Name="BtnTaskDone" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="$(X 'Done')" MinWidth="110"/>
                <TextBlock x:Name="TxtTaskHint" Style="{StaticResource MutedText}" VerticalAlignment="Center"
                           Text="$(X 'You can keep using your PC while this runs. Please keep this window open.')"/>
              </DockPanel>
            </Border>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="24,8,24,24">
                <Border x:Name="TaskResult" CornerRadius="8" Padding="18,16" Margin="0,0,0,12" BorderThickness="1" Visibility="Collapsed">
                  <DockPanel>
                    <Button x:Name="BtnTaskRestart" DockPanel.Dock="Right" Content="$(X 'Restart now')" VerticalAlignment="Center" Visibility="Collapsed" Margin="12,0,0,0"/>
                    <Button x:Name="BtnTaskAction" DockPanel.Dock="Right" Style="{StaticResource Primary}" VerticalAlignment="Center" Visibility="Collapsed" Margin="12,0,0,0"/>
                    <TextBlock x:Name="TaskResultIcon" FontFamily="{StaticResource Icons}" FontSize="24" VerticalAlignment="Top" Margin="0,2,14,0"/>
                    <StackPanel>
                      <TextBlock x:Name="TxtResultTitle" FontSize="17" FontWeight="SemiBold"/>
                      <TextBlock x:Name="TxtResultMsg" TextWrapping="Wrap" Margin="0,4,0,0"/>
                    </StackPanel>
                  </DockPanel>
                </Border>
                <Border x:Name="TaskProgressCard" Style="{StaticResource Card}">
                  <StackPanel>
                    <TextBlock x:Name="TxtTaskStatus" FontSize="16" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
                    <ProgressBar x:Name="TaskBar" Margin="0,14,0,10" Maximum="100"/>
                    <TextBlock x:Name="TxtTaskElapsed" Foreground="{DynamicResource Muted}" FontSize="12"/>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Margin="0,12,0,0" Padding="18,10">
                  <StackPanel x:Name="TaskSteps"/>
                </Border>
                <Button x:Name="BtnTaskLog" Style="{StaticResource Ghost}" HorizontalAlignment="Left" Margin="0,10,0,0" Padding="8,6">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock x:Name="TaskLogChevron" FontFamily="{StaticResource Icons}" Text="&#xE70D;" FontSize="11"
                               VerticalAlignment="Center" Foreground="{DynamicResource Muted}"/>
                    <TextBlock Text="$(X 'Show technical details')" Margin="8,0,0,0" Foreground="{DynamicResource Muted}"/>
                  </StackPanel>
                </Button>
                <TextBox x:Name="TxtTaskLog" Style="{StaticResource Mono}" Height="280" TextWrapping="NoWrap" Visibility="Collapsed"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Foreground="{DynamicResource Text}"/>
              </StackPanel>
            </ScrollViewer>
          </DockPanel>

        </Grid>
      </DockPanel>
    </Grid>
  </Grid>
</Window>
"@

#endregion

#region ---------- UI helpers ----------

# Points a property at a theme brush, so it follows light/dark switches. e.g. Set-Themed $tb Foreground Good
function Set-Themed($Element, [string]$Property, [string]$Key) {
    $dp = $Element.GetType().GetField("${Property}Property", [Reflection.BindingFlags]'Public,Static,FlattenHierarchy').GetValue($null)
    $Element.SetResourceReference($dp, $Key)
}

$Colors = @{ Accent = 'Accent'; Good = 'Good'; Warn = 'Warn'; Bad = 'Bad'; Muted = 'Muted'; Faint = 'Faint'; Text = 'Text' }

function New-Xaml([string]$Xml) {
    $Xml = $Xml -replace '^\s*<(\w+)', '<$1 xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"'
    [Windows.Markup.XamlReader]::Parse($Xml)
}

function Format-Duration([TimeSpan]$t) {
    if ($t.TotalDays -ge 1) { $n = [int][math]::Floor($t.TotalDays); $u = if ($n -eq 1) { '{0} day' } else { '{0} days' } }
    elseif ($t.TotalHours -ge 1) { $n = [int][math]::Floor($t.TotalHours); $u = if ($n -eq 1) { '{0} hour' } else { '{0} hours' } }
    else { $n = [int][math]::Floor($t.TotalMinutes); $u = if ($n -eq 1) { '{0} minute' } else { '{0} minutes' } }
    (T $u) -f $n
}

function Show-Dialog {
    param(
        [string]$Title,
        [string]$Message,
        [string[]]$Buttons = @('OK'),
        [ValidateSet('info', 'question', 'warn', 'error', 'shield', 'ok')][string]$Icon = 'info',
        [string]$CheckBox,
        [bool]$CheckBoxChecked = $true,
        [object[]]$Items,
        [scriptblock]$ItemLabel = { param($i) "$i" }
    )
    $look = @{
        info = @('E946', $Colors.Accent); question = @('E9CE', $Colors.Accent); warn = @('E7BA', $Colors.Warn)
        error = @('EA39', $Colors.Bad); shield = @('EA18', $Colors.Accent); ok = @('E930', $Colors.Good)
    }[$Icon]

    $dlg = New-Xaml @"
<Window Title="PC Maintenance" Width="500" SizeToContent="Height" WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        ShowInTaskbar="False" Background="{DynamicResource Surface}" FontFamily="Segoe UI" FontSize="14" Foreground="{DynamicResource Text}" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display">
  <DockPanel>
    <Border DockPanel.Dock="Bottom" Background="{DynamicResource Bg}" BorderBrush="{DynamicResource Line}" BorderThickness="0,1,0,0" Padding="20,14">
      <StackPanel Name="Btns" Orientation="Horizontal" HorizontalAlignment="Right"/>
    </Border>
    <Grid Margin="24,22,24,20">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <TextBlock FontFamily="Segoe MDL2 Assets" FontSize="28" Text="&#x$($look[0]);" Foreground="{DynamicResource $($look[1])}" Margin="0,2,16,0" VerticalAlignment="Top"/>
      <StackPanel Grid.Column="1" Name="Body">
        <TextBlock Text="$(Esc $Title)" FontSize="18" FontWeight="SemiBold" TextWrapping="Wrap"/>
        <TextBlock Text="$(Esc $Message)" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="{DynamicResource Text}"/>
      </StackPanel>
    </Grid>
  </DockPanel>
</Window>
"@
    $body = $dlg.FindName('Body')
    $btns = $dlg.FindName('Btns')

    $itemBoxes = @()
    if ($Items) {
        $panel = New-Object System.Windows.Controls.StackPanel
        foreach ($it in $Items) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = (& $ItemLabel $it); $cb.Tag = $it; $cb.IsChecked = $true; $cb.Margin = '0,6,0,0'
            [void]$panel.Children.Add($cb); $itemBoxes += $cb
        }
        $sv = New-Object System.Windows.Controls.ScrollViewer
        $sv.MaxHeight = 220; $sv.VerticalScrollBarVisibility = 'Auto'; $sv.Margin = '0,10,0,0'; $sv.Content = $panel
        [void]$body.Children.Add($sv)
    }
    $chk = $null
    if ($CheckBox) {
        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = New-Object System.Windows.Controls.TextBlock -Property @{ Text = (T $CheckBox); TextWrapping = 'Wrap' }
        $chk.IsChecked = $CheckBoxChecked; $chk.Margin = '0,14,0,0'
        [void]$body.Children.Add($chk)
    }
    for ($i = 0; $i -lt $Buttons.Count; $i++) {
        $b = New-Object System.Windows.Controls.Button
        # Shown translated, returned in English so callers can compare against the English label
        $b.Content = T $Buttons[$i]; $b.Tag = $Buttons[$i]; $b.MinWidth = 96; $b.Margin = '8,0,0,0'
        if ($i -eq 0) { $b.Style = $App.Resources['Primary']; $b.IsDefault = $true }
        if ($i -eq $Buttons.Count - 1 -and $Buttons.Count -gt 1) { $b.IsCancel = $true }
        $b.Add_Click({ param($s, $e) $script:DlgResult = $s.Tag; [System.Windows.Window]::GetWindow($s).Close() })
        [void]$btns.Children.Add($b)
    }

    if ($script:Window -and $script:Window.IsVisible) { $dlg.Owner = $script:Window } else { $dlg.WindowStartupLocation = 'CenterScreen' }
    $dlg.Add_SourceInitialized({ param($s, $e) Set-DarkTitleBar $s })
    $script:DlgResult = $null
    $script:DialogDepth++
    try { [void]$dlg.ShowDialog() } finally { $script:DialogDepth-- }
    $btn = if ($script:DlgResult) { $script:DlgResult } else { $Buttons[-1] }
    [pscustomobject]@{
        Button  = $btn
        Checked = ($chk -and $chk.IsChecked)
        Items   = @($itemBoxes | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    }
}

#--- Light / dark theme ---

$ThemeKey = 'HKCU:\Software\PCMaintenance'

# Saved choice from the header toggle; otherwise whatever Windows uses for apps.
function Get-StartTheme {
    if ($env:MAINT_TEST_THEME -in 'Light', 'Dark') { return $env:MAINT_TEST_THEME }
    $saved = (Get-ItemProperty $ThemeKey -Name Theme -ErrorAction SilentlyContinue).Theme
    if ($saved -in 'Light', 'Dark') { return $saved }
    $sys = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction SilentlyContinue
    if ($sys -and $sys.AppsUseLightTheme -eq 0) { return 'Dark' }
    'Light'
}

function Set-Theme([string]$Name) {
    $script:Theme = $Name
    $palette = $Themes[$Name]
    foreach ($k in $palette.Keys) {
        # ::new (not New-Object): a PSObject-wrapped brush in the dictionary is rejected by WPF
        $b = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.ColorConverter]::ConvertFromString($palette[$k]))
        $b.Freeze()
        $App.Resources[$k] = $b
    }
    if ($ui -and $ui.ThemeIcon) {
        # Show what clicking will switch to
        $ui.ThemeIcon.Text = if ($Name -eq 'Dark') { [string][char]0xE706 } else { [string][char]0xE708 }
        $ui.BtnTheme.ToolTip = if ($Name -eq 'Dark') { T 'Switch to light mode' } else { T 'Switch to dark mode' }
    }
    foreach ($w in @($App.Windows)) { Set-DarkTitleBar $w }
}

function Switch-Theme {
    $new = if ($script:Theme -eq 'Dark') { 'Light' } else { 'Dark' }
    Set-Theme $new
    try {
        if (-not (Test-Path $ThemeKey)) { New-Item $ThemeKey -Force | Out-Null }
        Set-ItemProperty $ThemeKey -Name Theme -Value $new
    } catch {}
}

# Dark title bar on Windows 10 20H1+ / 11. The C# helper is only compiled once dark mode is used.
function Set-DarkTitleBar($Win) {
    $dark = ($script:Theme -eq 'Dark')
    if (-not $dark -and -not ('MaintGui.Dwm' -as [type])) { return }
    if (-not ('MaintGui.Dwm' -as [type])) {
        Add-Type -Namespace MaintGui -Name Dwm -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
'@
    }
    $h = (New-Object System.Windows.Interop.WindowInteropHelper $Win).Handle
    if ($h -eq [IntPtr]::Zero) { return }
    $v = [int]$dark
    [void][MaintGui.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)   # DWMWA_USE_IMMERSIVE_DARK_MODE
}

function Show-Error($err) {
    $msg = if ($err -is [System.Management.Automation.ErrorRecord]) { $err.Exception.Message } else { "$err" }
    # Keep the details for troubleshooting
    try {
        $trace = if ($err -is [System.Management.Automation.ErrorRecord]) { $err.ScriptStackTrace }
                 elseif ($err -is [Exception] -and $err.ErrorRecord) { $err.ErrorRecord.ScriptStackTrace } else { '' }
        Add-Content -LiteralPath (Join-Path $env:TEMP 'PCMaintenance-error.log') -Value ("{0:s} {1}`n{2}`n" -f (Get-Date), $msg, $trace) -Encoding UTF8
    } catch {}
    [void](Show-Dialog -Title (T 'Something went wrong') -Message $msg -Icon error)
}

function Restart-AsAdmin {
    if ($script:TaskBusy) { return }
    try {
        if ($env:MAINT_LAUNCHER -and (Test-Path -LiteralPath $env:MAINT_LAUNCHER)) {
            Start-Process -FilePath $env:MAINT_LAUNCHER -ArgumentList '--elevated' -Verb RunAs
        } else {
            Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$SelfPath`"", '-NoUpdate')
        }
    } catch {
        return   # the user said No to the Windows permission prompt
    }
    $script:Window.Close()
}

function Restart-App {
    if ($script:TaskBusy) { return }
    if ($env:MAINT_LAUNCHER -and (Test-Path -LiteralPath $env:MAINT_LAUNCHER)) {
        Start-Process -FilePath $env:MAINT_LAUNCHER -ArgumentList '--no-update'
    } else {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$SelfPath`"", '-NoUpdate')
    }
    $script:Window.Close()
}

function Confirm-RestartComputer {
    $d = Show-Dialog -Title (T 'Restart your PC now?') -Message (T 'Save your work and close your apps first. Your PC will restart right away.') -Buttons 'Restart now', 'Cancel' -Icon warn
    if ($d.Button -eq 'Restart now') { Restart-Computer -Force }
}

# Offers to relaunch as admin. Returns $true if the app is already admin.
function Confirm-Admin([string]$What) {
    if (Test-IsAdmin) { return $true }
    $d = Show-Dialog -Title (T 'Administrator rights needed') -Message ((T '{0} needs administrator rights. The app will restart and Windows will ask for permission.') -f $What) -Buttons 'Run as administrator', 'Cancel' -Icon shield
    if ($d.Button -eq 'Run as administrator') { Restart-AsAdmin }
    return $false
}

#endregion

#region ---------- Navigation ----------

$Panels = @('PanelApps', 'PanelClean', 'PanelBattery', 'PanelSleep', 'PanelPower', 'PanelInfo', 'PanelTask') +
    @($Features | Where-Object { $_.Panel } | ForEach-Object { $_.Panel })

function Open-Feature([string]$Name) {
    $f = $Features | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if ($f -and $f.Open) { & $f.Open }
}

function Switch-Language {
    $new = if ($Lang -eq 'nb') { 'en' } else { 'nb' }
    Set-AppSetting 'Language' $new
    $msg = if ($new -eq 'nb') { 'Appen må starte på nytt for å bytte til norsk.' } else { 'The app needs to restart to switch to English.' }
    $btn = if ($new -eq 'nb') { 'Start på nytt' } else { 'Restart now' }
    $later = if ($new -eq 'nb') { 'Senere' } else { 'Later' }
    $d = Show-Dialog -Title $(if ($new -eq 'nb') { 'Bytt til norsk' } else { 'Switch to English' }) -Message $msg -Buttons $btn, $later -Icon info
    if ($d.Button -eq $btn) { Restart-App }
}
$script:BackTarget = 'Home'

function Show-Page([string]$Panel, [string]$Title, [string]$Subtitle, [string]$Back = 'Home') {
    if ($Panel -eq 'Home') {
        $ui.PageSub.Visibility = 'Collapsed'
        $ui.PageHome.Visibility = 'Visible'
        Update-Home
        return
    }
    $ui.PageHome.Visibility = 'Collapsed'
    $ui.PageSub.Visibility = 'Visible'
    foreach ($p in $Panels) { $ui[$p].Visibility = if ($p -eq $Panel) { 'Visible' } else { 'Collapsed' } }
    $ui.TxtPageTitle.Text = $Title
    $ui.TxtPageSub.Text = $Subtitle
    $ui.TxtPageSub.Visibility = if ($Subtitle) { 'Visible' } else { 'Collapsed' }
    $script:BackTarget = $Back
}

function Open-Target([string]$Target) {
    # 'Home', or a feature Name (its Open runs again, which also refreshes the page)
    if ($Target -and $Target -ne 'Home' -and ($Features | Where-Object { $_.Name -eq $Target })) { Open-Feature $Target }
    else { Show-Page 'Home' }
}

#endregion

#region ---------- Home ----------

function Update-Home {
    Start-Worker -Work { Get-SystemSnapshot } -OnDone {
        param($r, $err)
        if ($r) { $script:Snapshot = $r; Show-HomeStatus $r }
    }
    Update-Checkup
}

#--- PC checkup ---
# Fix keys from Get-HealthChecks -> what the button does
$CheckupFixes = @{
    clean     = { Open-Feature 'Clean' }
    restart   = { Confirm-RestartComputer }
    update    = { Start-UpdateEverything }
    apps      = { Open-Feature 'Apps' }
    security  = { Start-Process 'windowsdefender:' }
    firewall  = { Start-Process 'windowsdefender://network/' }
    bitlocker = { Start-Process control.exe -ArgumentList '/name Microsoft.BitLockerDriveEncryption' }
    battery   = { Open-Feature 'Battery' }
    auto      = { Open-Feature 'Auto' }
}

# Runs again when you come back to the home screen, at most once a minute (or after a task finished)
function Update-Checkup([switch]$Force) {
    if (-not $Force -and $script:CheckupAt -and ((Get-Date) - $script:CheckupAt).TotalSeconds -lt 60) { return }
    $script:CheckupAt = Get-Date
    $script:Checks = @{}
    Start-Worker -Work { [pscustomobject]@{ Checks = @(Get-HealthChecks) } } -OnDone {
        param($r, $err)
        if ($r) { foreach ($c in @($r.Checks)) { $script:Checks[$c.Key] = $c } }
        Show-Checkup
    }
    # winget is slow, so app updates are checked separately and added when ready
    Start-Worker -Work {
        $n = @(Get-WingetUpgrades).Count
        if ($n) { New-HealthCheck 'apps' 'warn' (T 'App updates') $(if ($n -eq 1) { T '1 app update is available' } else { (T '{0} app updates are available') -f $n }) 'apps' 'Show updates' }
        else { New-HealthCheck 'apps' 'ok' (T 'App updates') '' }
    } -OnDone {
        param($r, $err)
        if ($r) { $script:Checks['apps'] = $r; if ($script:Checks.Count -gt 1) { Show-Checkup } }
    }
}

function Show-Checkup {
    $checks = @($script:Checks.Values)
    $issues = @($checks | Where-Object { $_.State -in 'bad', 'warn', 'info' } | Sort-Object @{ e = { @{ bad = 0; warn = 1; info = 2 }[$_.State] } }, Title)
    $passed = @($checks | Where-Object { $_.State -eq 'ok' } | Sort-Object Title)
    $ui.CheckupRows.Children.Clear()

    $real = @($issues | Where-Object { $_.State -ne 'info' })
    if (-not $real.Count) {
        $ui.TxtCheckupTitle.Text = T 'Your PC looks good'
        $ui.TxtCheckupSub.Text = T 'Nothing needs your attention right now.'
        $ui.CheckupIcon.Text = [string][char]0xE930
        Set-Themed $ui.CheckupIcon Foreground 'Good'
    } else {
        $ui.TxtCheckupTitle.Text = if ($real.Count -eq 1) { T '1 thing needs your attention' } else { (T '{0} things need your attention') -f $real.Count }
        $ui.TxtCheckupSub.Text = T 'Click a button to fix it.'
        $ui.CheckupIcon.Text = [string][char]0xE7BA
        Set-Themed $ui.CheckupIcon Foreground $(if (@($real | Where-Object { $_.State -eq 'bad' }).Count) { 'Bad' } else { 'Warn' })
    }

    foreach ($c in $issues) {
        $glyph, $color = switch ($c.State) { 'bad' { 'EA39', 'Bad' } 'warn' { 'E7BA', 'Warn' } default { 'E946', 'Accent' } }
        $btn = if ($c.Fix) { "<Button DockPanel.Dock=`"Right`" Content=`"$(X $c.FixLabel)`" Padding=`"12,5`" VerticalAlignment=`"Center`" Margin=`"12,0,0,0`"/>" } else { '' }
        $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="0,1,0,0" Padding="0,10,0,0" Margin="0,10,0,0">
  <DockPanel>
    $btn
    <TextBlock DockPanel.Dock="Left" FontFamily="Segoe MDL2 Assets" Text="&#x$glyph;" Foreground="{DynamicResource $color}" FontSize="16" Margin="2,2,14,0" VerticalAlignment="Top"/>
    <StackPanel>
      <TextBlock Text="$(Esc $c.Title)" FontWeight="SemiBold" TextWrapping="Wrap"/>
      <TextBlock Text="$(Esc $c.Detail)" Foreground="{DynamicResource Muted}" TextWrapping="Wrap" Margin="0,2,0,0"/>
    </StackPanel>
  </DockPanel>
</Border>
"@
        if ($c.Fix) {
            $b = $row.Child.Children[0]
            $b.Tag = $c.Fix
            $b.Add_Click({ param($s, $e) & $CheckupFixes[$s.Tag] })
        }
        [void]$ui.CheckupRows.Children.Add($row)
    }

    if ($passed.Count) {
        $ui.TxtCheckupPassed.Text = ([string][char]0x2713) + ' ' + ((T 'OK: {0}') -f (($passed | ForEach-Object { $_.Title }) -join ', '))
        $ui.TxtCheckupPassed.Visibility = 'Visible'
    }
}

function Show-HomeStatus($s) {
    $c = @($s.Disks | Where-Object { $_.Drive -eq $env:SystemDrive }) | Select-Object -First 1
    if ($c -and $c.Size) {
        $freePct = 100 * $c.Free / $c.Size
        $ui.TxtDiskMain.Text = (T '{0} free') -f (Format-Bytes $c.Free)
        $ui.TxtDiskSub.Text = (T 'of {0} on drive {1}') -f (Format-Bytes $c.Size), $c.Drive
        $ui.DiskBar.Value = 100 - $freePct
        $color = if ($freePct -lt 10) { $Colors.Bad } elseif ($freePct -lt 20) { $Colors.Warn } else { $Colors.Accent }
        Set-Themed $ui.DiskBar Foreground $color
        if ($freePct -lt 10) { $ui.TxtDiskSub.Text += (T '. Running low: try Free up space.') }
    }

    $b = $s.Battery
    if ($b) {
        $ui.TxtBatMain.Text = '{0}%' -f $b.Charge
        $src = if ($b.OnAC) { T 'Plugged in' } else { T 'On battery' }
        $ui.TxtBatSub.Text = if ($null -ne $b.Health) { (T '{0} - health {1}%') -f $src, $b.Health } else { $src }
    } else {
        $ui.TxtBatMain.Text = (T 'No battery')
        $ui.TxtBatSub.Text = (T 'This PC runs on mains power.')
    }

    if ($s.RebootNeeded) {
        $ui.TxtRebootMain.Text = (T 'Needed')
        Set-Themed $ui.TxtRebootMain Foreground $Colors.Warn
        $ui.TxtRebootSub.Text = (T 'A restart is needed to finish installing updates.')
        $ui.BtnRestartHome.Visibility = 'Visible'
    } else {
        $ui.TxtRebootMain.Text = (T 'Not needed')
        Set-Themed $ui.TxtRebootMain Foreground $Colors.Good
        $ui.TxtRebootSub.Text = (T 'Everything installed is in use.')
        $ui.BtnRestartHome.Visibility = 'Collapsed'
    }

    $ui.TxtUpMain.Text = Format-Duration $s.Uptime
    $ui.TxtUpSub.Text = (T 'Since {0}') -f $s.LastBoot.ToString('dddd d MMM, HH:mm', $Culture)
    if ($s.Uptime.TotalDays -ge 7) { $ui.TxtUpSub.Text += (T '. Restarting now and then keeps your PC fast.') }
}

#endregion

#region ---------- Task page (progress for long jobs) ----------

$StepLook = @{
    pending = @([char]0xEA3A, $Colors.Faint, (T 'Waiting'))
    running = @([char]0xE895, $Colors.Accent, (T 'Working...'))
    ok      = @([char]0xE73E, $Colors.Good, (T 'Done'))
    warn    = @([char]0xE7BA, $Colors.Warn, '')
    error   = @([char]0xE711, $Colors.Bad, (T 'Failed'))
    skip    = @([char]0xE738, $Colors.Faint, (T 'Skipped'))
}
$script:StepRows = @{}
$script:StepOrder = New-Object System.Collections.ArrayList

function Open-TaskPage([string]$Title, [string]$Subtitle, [string]$Back = 'Home') {
    $script:TaskBusy = $true
    $script:StepRows = @{}
    $script:StepOrder.Clear()
    $ui.TaskSteps.Children.Clear()
    $ui.TxtTaskLog.Clear()
    $ui.TaskResult.Visibility = 'Collapsed'
    $ui.TaskProgressCard.Visibility = 'Visible'
    $ui.BtnTaskDone.Visibility = 'Collapsed'
    $ui.BtnTaskRestart.Visibility = 'Collapsed'
    $ui.TxtTaskHint.Visibility = 'Visible'
    $ui.TxtTaskStatus.Text = (T 'Getting started...')
    $ui.TaskBar.IsIndeterminate = $true
    $ui.TxtTaskElapsed.Text = ''
    $ui.BtnBack.IsEnabled = $false
    $ui.BtnElevate.IsEnabled = $false
    $script:TaskClock = [Diagnostics.Stopwatch]::StartNew()
    Show-Page 'PanelTask' $Title $Subtitle $Back
}

function Add-TaskStep([string]$Key, [string]$Label) {
    $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="0,0,0,1" Padding="0,10">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="34"/><ColumnDefinition Width="Auto" MinWidth="200"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock FontFamily="Segoe MDL2 Assets, Segoe UI Symbol" FontSize="16" VerticalAlignment="Center"/>
    <TextBlock Grid.Column="1" Text="$(Esc $Label)" FontWeight="SemiBold" VerticalAlignment="Center"/>
    <TextBlock Grid.Column="2" Margin="16,0,0,0" TextWrapping="Wrap" VerticalAlignment="Center" TextAlignment="Right"/>
  </Grid>
</Border>
"@
    [void]$ui.TaskSteps.Children.Add($row)
    $g = $row.Child
    $script:StepRows[$Key] = [pscustomobject]@{ Icon = $g.Children[0]; Label = $Label; Detail = $g.Children[2]; State = 'pending'; Text = '' }
    [void]$script:StepOrder.Add($Key)
    Set-StepState $Key 'pending'
}

function Set-StepState([string]$Key, [string]$State, [string]$Detail = '') {
    $r = $script:StepRows[$Key]
    if (-not $r) { return }
    $look = $StepLook[$State]
    if (-not $look) { return }
    $r.State = $State
    $r.Text = if ($Detail) { $Detail } else { $look[2] }
    $r.Icon.Text = [string]$look[0]
    Set-Themed $r.Icon Foreground $look[1]
    $r.Detail.Text = $r.Text
    Set-Themed $r.Detail Foreground $(if ($State -in 'warn', 'error') { $look[1] } else { $Colors.Muted })
}

function Add-TaskLog([string]$Text) {
    $box = $ui.TxtTaskLog
    if ($box.Text.Length -gt 400000) { $box.Text = $box.Text.Substring(200000) }
    $box.AppendText($Text + "`r`n")
    $box.ScrollToEnd()
}

function Receive-TaskMessage($m) {
    if ($m.Type -eq 'step') { Set-StepState $m.Key $m.State $m.Detail; return }
    $prefix = switch ($m.Kind) { 'detail' { '    ' } 'warn' { '[!] ' } 'error' { '[X] ' } default { '' } }
    Add-TaskLog ($prefix + $m.Text)
}

function Update-TaskProgress($w) {
    if ($w.Sync.Status) { $ui.TxtTaskStatus.Text = $w.Sync.Status }
    $p = [double]$w.Sync.Percent
    if ($p -lt 0) { $ui.TaskBar.IsIndeterminate = $true }
    else { $ui.TaskBar.IsIndeterminate = $false; $ui.TaskBar.Value = $p }
}

function Start-TaskWork {
    param([scriptblock]$Work, [object[]]$ArgumentList = @(), [scriptblock]$OnDone)
    $ui.TaskBar.IsIndeterminate = $true
    Start-Worker -Foreground -Work $Work -ArgumentList $ArgumentList -OnDone $OnDone
}

# A "flow" is a list of stages run one after another; a stage that starts background work
# calls Invoke-NextStage from its OnDone.
function Start-Flow([scriptblock[]]$Stages) {
    $script:Flow = New-Object System.Collections.Generic.List[scriptblock]
    foreach ($s in $Stages) { $script:Flow.Add($s) }
    Invoke-NextStage
}
function Invoke-NextStage {
    if (-not $script:Flow -or $script:Flow.Count -eq 0) { return }
    $s = $script:Flow[0]
    $script:Flow.RemoveAt(0)
    try { & $s } catch { Add-TaskLog "[X] $($_.Exception.Message)"; $script:Flow.Clear(); Complete-Task }
}

# Final banner, worked out from the step rows. $script:Ctx.Summary adds a sentence.
function Complete-Task {
    param([string]$ForceTitle, [string]$ForceMessage, [string]$ForceState)
    $script:TaskBusy = $false
    if ($script:TaskClock) { $script:TaskClock.Stop() }

    $rows   = @($script:StepOrder | ForEach-Object { $script:StepRows[$_] })
    $errors = @($rows | Where-Object { $_.State -eq 'error' })
    $warns  = @($rows | Where-Object { $_.State -eq 'warn' })

    if ($ForceState) { $state = $ForceState; $title = $ForceTitle; $msg = $ForceMessage }
    elseif ($errors.Count) {
        $state = 'error'; $title = (T 'Finished, but some things did not work')
        $msg = ((@($errors) + @($warns) | ForEach-Object { '{0}: {1}' -f $_.Label, $_.Text }) -join "`n")
    } elseif ($warns.Count) {
        $state = 'warn'; $title = (T 'Finished, with a few notes')
        $msg = (($warns | ForEach-Object { '{0}: {1}' -f $_.Label, $_.Text }) -join "`n")
    } else {
        $state = 'ok'; $title = (T 'All done'); $msg = (T 'Everything finished successfully.')
    }
    if ($script:Ctx -and $script:Ctx.Summary) { $msg = ($script:Ctx.Summary + "`n" + $msg).Trim() }

    $look = @{
        ok    = @('E930', 'GoodBg', 'GoodLine', $Colors.Good)
        warn  = @('E7BA', 'WarnBg', 'WarnLine', $Colors.Warn)
        error = @('EA39', 'BadBg', 'BadLine', $Colors.Bad)
    }[$state]
    $ui.TaskResultIcon.Text = [string][char][Convert]::ToInt32($look[0], 16)
    Set-Themed $ui.TaskResultIcon Foreground $look[3]
    Set-Themed $ui.TaskResult Background $look[1]
    Set-Themed $ui.TaskResult BorderBrush $look[2]
    $ui.TxtResultTitle.Text = $title

    $reboot = $false
    try { $reboot = Test-RebootNeeded } catch {}
    if ($reboot) { $msg += "`n" + (T 'Restart your PC to finish installing updates.') }
    $ui.TxtResultMsg.Text = $msg
    $ui.BtnTaskRestart.Visibility = if ($reboot) { 'Visible' } else { 'Collapsed' }

    # Optional extra button, e.g. $script:Ctx.Action = @{ Label = (T 'Try a quick fix'); Run = { Start-NetFix } }
    $script:TaskAction = $null
    if ($script:Ctx -and $script:Ctx.Action) {
        $script:TaskAction = $script:Ctx.Action.Run
        $ui.BtnTaskAction.Content = $script:Ctx.Action.Label
        $ui.BtnTaskAction.Visibility = 'Visible'
    } else {
        $ui.BtnTaskAction.Visibility = 'Collapsed'
    }

    $script:CheckupAt = $null   # something changed: re-check the home screen next time
    if (-not ($script:Ctx -and $script:Ctx.NoHistory)) {
        Add-History -Title $ui.TxtPageTitle.Text -State $state -Detail ("$title. $msg".Trim())
    }

    $ui.TaskResult.Visibility = 'Visible'
    $ui.TaskProgressCard.Visibility = 'Collapsed'
    $ui.BtnTaskDone.Visibility = 'Visible'
    $ui.TxtTaskHint.Visibility = 'Collapsed'
    $ui.BtnBack.IsEnabled = $true
    $ui.BtnElevate.IsEnabled = $true
    $ui.TaskBar.IsIndeterminate = $false
    Add-TaskLog ('--- Finished after {0:hh\:mm\:ss} ---' -f $script:TaskClock.Elapsed)
}

#--- Shared stages ---

function Invoke-RestoreStage {
    Set-StepState 'restore' 'running' 'Creating...'
    Start-TaskWork -Work { SetStatus (T 'Creating a safety restore point (usually under a minute)'); New-RestorePointCore 'PC Maintenance' } -OnDone {
        param($r, $err)
        if ($err) { $r = [pscustomobject]@{ Result = 'Failed'; Detail = $err } }
        if ($r.Result -in 'Created', 'Recent') {
            Set-StepState 'restore' 'ok' $r.Detail
            Invoke-NextStage
            return
        }
        Add-TaskLog "[!] Restore point: $($r.Detail)"
        $never = "Don't try to create restore points again (for example on a work PC where they aren't allowed)"
        if (-not $script:Ctx.RestoreRetried) {
            $d = Show-Dialog -Title (T "Couldn't create a restore point") -Icon warn `
                -Message (T 'A restore point lets you undo system changes if an update causes problems. System Protection may be turned off on this PC.') `
                -Buttons 'Turn it on and try again', 'Continue without', 'Stop' -CheckBox $never -CheckBoxChecked $false
        } else {
            $d = Show-Dialog -Title (T 'Still no restore point') -Icon warn `
                -Message (T 'Windows still could not create a restore point. You can continue without one or stop here.') `
                -Buttons 'Continue without', 'Stop' -CheckBox $never -CheckBoxChecked $false
        }
        if ($d.Checked -and $d.Button -ne 'Turn it on and try again') {
            Set-AppSetting 'SkipRestorePoint' 1
            Add-TaskLog (T 'Restore points are turned off. You can turn them back on under Restore point.')
        }
        switch ($d.Button) {
            'Turn it on and try again' {
                $script:Ctx.RestoreRetried = $true
                Start-TaskWork -Work { SetStatus (T 'Turning on System Protection'); Enable-SystemProtectionCore } -OnDone {
                    param($r2, $err2)
                    if ($err2) { Add-TaskLog "[!] $err2" }
                    Invoke-RestoreStage
                }
            }
            'Continue without' { Set-StepState 'restore' 'skip' (T 'Not created'); Invoke-NextStage }
            default {
                Set-StepState 'restore' 'skip' (T 'Not created')
                $script:Flow.Clear()
                Complete-Task -ForceState 'warn' -ForceTitle (T 'Stopped') -ForceMessage (T 'Nothing was changed.')
            }
        }
    }
}

function Invoke-ReinstallOfferStage {
    $failed = @($script:Ctx.Failed)
    if (-not $failed.Count) { Invoke-NextStage; return }
    $d = Show-Dialog -Title (T "Some apps couldn't be updated") -Icon warn `
        -Message (T 'Reinstalling usually fixes this: the app is removed and the newest version is installed fresh. Settings are normally kept, but close these apps first.') `
        -Items $failed -ItemLabel { param($p) (T '{0}  ({1} to {2})') -f $p.Name, $p.Version, $p.Available } `
        -Buttons 'Reinstall selected', 'Skip'
    if ($d.Button -ne 'Reinstall selected' -or -not $d.Items.Count) { Invoke-NextStage; return }
    foreach ($p in $d.Items) { Add-TaskStep ('re:' + $p.Id) ((T 'Reinstall {0}') -f $p.Name) }
    Start-TaskWork -ArgumentList (, @($d.Items)) -Work { param($pkgs) Invoke-WingetReinstallSet -Packages $pkgs } -OnDone {
        param($r, $err)
        if ($err) { Add-TaskLog "[X] $err" }
        Invoke-NextStage
    }
}

#endregion

#region ---------- Update everything ----------

function Start-UpdateEverything {
    $admin = Test-IsAdmin
    if (-not $admin) {
        $d = Show-Dialog -Title (T 'Run as administrator for a full update?') -Icon shield `
            -Message (T "Windows Update, drivers, Microsoft Store apps, virus protection and the safety restore point need administrator rights.`n`nWithout them, only your apps, Office, WSL and PowerShell modules are updated.") `
            -Buttons 'Run as administrator', 'Continue anyway', 'Cancel'
        if ($d.Button -eq 'Run as administrator') { Restart-AsAdmin; return }
        if ($d.Button -ne 'Continue anyway') { return }
    } else {
        $msg = if (Test-RestorePointsWanted) {
            T "This updates your apps, Windows (including drivers), Microsoft Store apps, Office and virus protection. A restore point is created first so system changes can be undone.`n`nSome apps may close while they update, so save your work first. This can take a while, but you can keep using your PC."
        } else {
            T "This updates your apps, Windows (including drivers), Microsoft Store apps, Office and virus protection.`n`nSome apps may close while they update, so save your work first. This can take a while, but you can keep using your PC."
        }
        $d = Show-Dialog -Title (T 'Update everything?') -Icon question -Message $msg -Buttons 'Start', 'Cancel'
        if ($d.Button -ne 'Start') { return }
    }

    $script:Ctx = @{ Failed = @(); Retired = @() }
    Open-TaskPage (T 'Updating everything') (T 'This can take 10 to 60 minutes. You can keep using your PC in the meantime.')
    $restore = Test-RestorePointsWanted   # off in settings or blocked by the organization: no step at all
    if ($restore) { Add-TaskStep 'restore' (T 'Safety restore point') }
    foreach ($s in $UpdateSteps) { Add-TaskStep $s.Key $s.Label }

    $stages = @()
    if ($restore) {
        if ($admin) { $stages += { Invoke-RestoreStage } } else { Set-StepState 'restore' 'skip' (T 'Needs administrator') }
    }
    $stages += { Invoke-UpdateAllStage }, { Invoke-ReinstallOfferStage }, { Invoke-RetiredModulesStage }, { Complete-Task }
    Start-Flow $stages
}

function Invoke-UpdateAllStage {
    Start-TaskWork -Work {
        $admin = Test-IsAdmin
        $out = @{ Failed = @(); Retired = @() }
        $n = $UpdateSteps.Count
        for ($i = 0; $i -lt $n; $i++) {
            $s = $UpdateSteps[$i]
            $Sync.Base = 100 * $i / $n; $Sync.Span = 100 / $n
            SetStatus $s.Label
            if ($s.Admin -and -not $admin) { Step $s.Key 'skip' (T 'Needs administrator'); continue }
            Step $s.Key 'running'
            Log "--- $($s.Label) ---"
            $ctx = @{ State = 'ok'; Text = 'Done'; Out = $out }
            try {
                & $s.Fn $ctx
                Step $s.Key $ctx.State $ctx.Text
            } catch {
                Step $s.Key 'error' $_.Exception.Message
                Log $_.Exception.Message 'error'
            }
        }
        $Sync.Base = 0; $Sync.Span = 100
        SetStatus (T 'Finishing up') 100
        [pscustomobject]@{ Failed = @($out.Failed); Retired = @($out.Retired) }
    } -OnDone {
        param($r, $err)
        if ($err) { Add-TaskLog "[X] $err" }
        if ($r) { $script:Ctx.Failed = @($r.Failed); $script:Ctx.Retired = @($r.Retired) }
        Invoke-NextStage
    }
}

function Invoke-RetiredModulesStage {
    $ret = @($script:Ctx.Retired | Where-Object { $_ })
    if (-not $ret.Count) { Invoke-NextStage; return }
    $d = Show-Dialog -Title (T 'Remove old Azure PowerShell modules?') -Icon question `
        -Message ((T '{0} retired Azure PowerShell module(s) were found (AzureRM / Azure). They no longer get updates and conflict with the newer Az modules.') -f $ret.Count) `
        -Buttons 'Remove them', 'Keep them'
    if ($d.Button -ne 'Remove them') { Invoke-NextStage; return }
    Add-TaskStep 'retired' (T 'Remove retired Azure modules')
    Start-TaskWork -ArgumentList (, $ret) -Work {
        param($names)
        Step 'retired' 'running'
        $left = @(Remove-RetiredModules $names)
        if ($left.Count) { Step 'retired' 'warn' ((T 'Could not remove {0}. Close other PowerShell windows and try again.') -f ($left -join ', ')) }
        else { Step 'retired' 'ok' ((T '{0} removed') -f $names.Count) }
    } -OnDone { param($r, $err) if ($err) { Add-TaskLog "[X] $err" }; Invoke-NextStage }
}

#endregion

#region ---------- App updates ----------

$script:AppRows = @()

function Open-Apps {
    Show-Page 'PanelApps' (T 'App updates') (T 'Pick the apps you want to update. Apps that are open may close for a moment while they update.')
    Update-AppList
}

function Update-AppList {
    $ui.AppsLoading.Visibility = 'Visible'
    $ui.AppsEmpty.Visibility = 'Collapsed'
    $ui.AppsCard.Visibility = 'Collapsed'
    $ui.BtnAppsUpdate.IsEnabled = $false
    $ui.BtnAppsSelect.IsEnabled = $false
    $ui.BtnAppsRefresh.IsEnabled = $false
    $inc = [bool]$ui.ChkAppsUnknown.IsChecked
    Start-Worker -ArgumentList $inc -Work {
        param($inc)
        [pscustomobject]@{ List = @(Get-WingetUpgrades -IncludeUnknown:$inc) }
    } -OnDone { param($r, $err) Show-AppList $r $err }
}

function Show-AppList($r, $err) {
    $ui.AppsLoading.Visibility = 'Collapsed'
    $ui.BtnAppsRefresh.IsEnabled = $true
    $ui.AppsList.Children.Clear()
    $script:AppRows = @()

    if ($err -or -not $r -or -not @($r.List).Count) {
        $ui.AppsEmpty.Visibility = 'Visible'
        if ($err) {
            $ui.AppsEmptyIcon.Text = [string][char]0xE7BA; Set-Themed $ui.AppsEmptyIcon Foreground $Colors.Warn
            $ui.AppsEmptyTitle.Text = T "Couldn't check for app updates"
            $ui.AppsEmptyText.Text = $err
        } else {
            $ui.AppsEmptyIcon.Text = [string][char]0xE930; Set-Themed $ui.AppsEmptyIcon Foreground $Colors.Good
            $ui.AppsEmptyTitle.Text = (T 'All your apps are up to date')
            $ui.AppsEmptyText.Text = (T 'Nothing to do here. Check again another day.')
        }
        return
    }

    foreach ($p in @($r.List)) {
        $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="0,0,0,1" Padding="18,10">
  <CheckBox IsChecked="True" HorizontalContentAlignment="Stretch" VerticalContentAlignment="Center" Cursor="Hand">
    <Grid Margin="8,0,0,0">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="170"/><ColumnDefinition Width="162"/></Grid.ColumnDefinitions>
      <StackPanel>
        <TextBlock Text="$(Esc $p.Name)" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
        <TextBlock Text="$(Esc $p.Id)" Foreground="{DynamicResource Faint}" FontSize="12" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
      <TextBlock Grid.Column="1" Text="$(Esc $p.Version)" Foreground="{DynamicResource Muted}" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      <TextBlock Grid.Column="2" Text="$(Esc $p.Available)" Foreground="{DynamicResource Good}" FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
    </Grid>
  </CheckBox>
</Border>
"@
        $cb = $row.Child
        $cb.Tag = $p
        $cb.Add_Checked({ Update-AppsButtons })
        $cb.Add_Unchecked({ Update-AppsButtons })
        [void]$ui.AppsList.Children.Add($row)
        $script:AppRows += $cb
    }
    $ui.AppsCard.Visibility = 'Visible'
    $ui.BtnAppsSelect.IsEnabled = $true
    Update-AppsButtons
}

function Update-AppsButtons {
    $n = @($script:AppRows | Where-Object { $_.IsChecked }).Count
    $ui.BtnAppsUpdate.IsEnabled = ($n -gt 0)
    $ui.BtnAppsUpdate.Content = if ($n -eq 1) { T 'Update 1 app' } else { (T 'Update {0} apps') -f $n }
    $ui.BtnAppsSelect.Content = if ($n -eq $script:AppRows.Count) { T 'Select none' } else { T 'Select all' }
}

function Start-AppUpdates {
    $pkgs = @($script:AppRows | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if (-not $pkgs.Count) { return }
    $admin = Test-IsAdmin
    $what = if ($pkgs.Count -eq 1) { $pkgs[0].Name } else { (T '{0} apps') -f $pkgs.Count }
    $msg = (T 'Apps that are open may close for a moment while they update, so save your work first.')
    if ($admin -and (Test-RestorePointsWanted)) {
        $d = Show-Dialog -Title ((T 'Update {0}?') -f $what) -Message $msg -Buttons 'Update', 'Cancel' -Icon question -CheckBox (T 'Create a restore point first (recommended)')
    } else {
        $d = Show-Dialog -Title ((T 'Update {0}?') -f $what) -Message $msg -Buttons 'Update', 'Cancel' -Icon question
    }
    if ($d.Button -ne 'Update') { return }

    $script:Ctx = @{ Pkgs = $pkgs; IncludeUnknown = [bool]$ui.ChkAppsUnknown.IsChecked; Failed = @() }
    Open-TaskPage (T 'Updating apps') (T 'Apps may close for a moment while they update.') 'Apps'
    $stages = @()
    if ($admin -and $d.Checked -and (Test-RestorePointsWanted)) { Add-TaskStep 'restore' (T 'Safety restore point'); $stages += { Invoke-RestoreStage } }
    foreach ($p in $pkgs) { Add-TaskStep $p.Id $p.Name }
    $stages += { Invoke-AppUpgradeStage }, { Invoke-ReinstallOfferStage }, { Complete-Task }
    Start-Flow $stages
}

function Invoke-AppUpgradeStage {
    Start-TaskWork -ArgumentList (@(, @($script:Ctx.Pkgs)) + @($script:Ctx.IncludeUnknown)) -Work {
        param($pkgs, $inc)
        [pscustomobject]@{ Failed = @(Invoke-WingetUpgradeSet -Packages $pkgs -IncludeUnknown:$inc) }
    } -OnDone {
        param($r, $err)
        if ($err) { Add-TaskLog "[X] $err"; foreach ($p in $script:Ctx.Pkgs) { if ($script:StepRows[$p.Id].State -ne 'ok') { Set-StepState $p.Id 'error' $err } } }
        if ($r) { $script:Ctx.Failed = @($r.Failed) }
        Invoke-NextStage
    }
}

#endregion

#region ---------- Free up space ----------

function Open-Clean {
    Show-Page 'PanelClean' (T 'Free up space') (T 'Choose what to remove. Your own documents, photos and other personal files are never touched.')
    $admin = Test-IsAdmin
    $ui.TxtCleanAdminNote.Visibility = if ($admin) { 'Collapsed' } else { 'Visible' }
    foreach ($it in $CleanItems) {
        $chk = $ui["ChkClean_$($it.Key)"]
        $size = $ui["TxtCleanSize_$($it.Key)"]
        if ($it.Admin -and -not $admin) {
            $chk.IsEnabled = $false; $chk.IsChecked = $false
            $size.Text = (T 'Needs administrator'); Set-Themed $size Foreground $Colors.Faint; $size.FontWeight = 'Normal'
        } else {
            $chk.IsEnabled = $true; $chk.IsChecked = $it.Default
            $size.Text = (T 'Measuring...'); Set-Themed $size Foreground $Colors.Faint; $size.FontWeight = 'Normal'
        }
    }
    Update-CleanDrive
    $ui.BtnCleanRun.IsEnabled = $true

    # One small job per item, so quick ones (Recycle Bin) don't wait for big folders
    foreach ($it in $CleanItems) {
        if ($it.Admin -and -not $admin) { continue }
        if ($it.Key -eq 'dism') { Set-CleanSize 'dism' -2; continue }
        Start-Worker -ArgumentList $it.Key -Work {
            param($key)
            $v = switch ($key) {
                'usertemp' { Get-FolderSize $env:TEMP }
                'wintemp'  { Get-FolderSize (Join-Path $env:windir 'Temp') }
                'recycle'  { Get-RecycleBinSize }
                'delivery' { Get-FolderSize $DeliveryCachePath }
            }
            [pscustomobject]@{ Key = $key; Size = $v }
        } -OnDone {
            param($r, $err)
            if ($r) { Set-CleanSize $r.Key $r.Size }
        }
    }
}

# -1 = unknown, -2 = varies
function Set-CleanSize([string]$Key, [double]$Bytes) {
    $size = $ui["TxtCleanSize_$Key"]
    if (-not $ui["ChkClean_$Key"].IsEnabled) { return }
    if ($Bytes -eq -2) { $size.Text = (T 'Varies') }
    elseif ($Bytes -lt 0) { $size.Text = '' }
    elseif ($Bytes -eq 0) { $size.Text = (T 'Empty') }
    else { $size.Text = Format-Bytes $Bytes; Set-Themed $size Foreground $Colors.Text; $size.FontWeight = 'SemiBold' }
}

function Update-CleanDrive {
    $free = Get-SystemDriveFree; $size = Get-SystemDriveSize
    $ui.TxtCleanDrive.Text = (T 'Drive {0}') -f $env:SystemDrive
    $ui.TxtCleanFree.Text = (T '{0} free of {1}') -f (Format-Bytes $free), (Format-Bytes $size)
    $freePct = 100 * $free / $size
    $ui.CleanBar.Value = 100 - $freePct
    Set-Themed $ui.CleanBar Foreground $(if ($freePct -lt 10) { $Colors.Bad } elseif ($freePct -lt 20) { $Colors.Warn } else { $Colors.Accent })
}

function Start-Cleanup {
    $sel = @($CleanItems | Where-Object { $ui["ChkClean_$($_.Key)"].IsChecked })
    if (-not $sel.Count) { [void](Show-Dialog -Title (T 'Nothing selected') -Message (T 'Tick at least one item to clean up.')); return }
    if ($sel.Key -contains 'recycle') {
        $d = Show-Dialog -Title (T 'Empty the Recycle Bin?') -Icon warn -Message (T "Files in the Recycle Bin will be deleted for good and can't be recovered afterwards.") -Buttons 'Clean up', 'Cancel'
        if ($d.Button -ne 'Clean up') { return }
    }
    $script:Ctx = @{ CleanKeys = @($sel | ForEach-Object { $_.Key }) }
    Open-TaskPage (T 'Freeing up space') '' 'Clean'
    foreach ($it in $sel) { Add-TaskStep $it.Key $it.Label }
    Start-Flow @({ Invoke-CleanStage }, { Complete-Task })
}

function Invoke-CleanStage {
    Start-TaskWork -ArgumentList (, @($script:Ctx.CleanKeys)) -Work {
        param($keys)
        $start = Get-SystemDriveFree
        $n = $keys.Count
        for ($i = 0; $i -lt $n; $i++) {
            $k = $keys[$i]
            $Sync.Base = 100 * $i / $n; $Sync.Span = 100 / $n
            Step $k 'running'
            $f0 = Get-SystemDriveFree
            try {
                $freed = $null
                switch ($k) {
                    'usertemp' { SetStatus (T 'Removing temporary files'); $freed = Clear-FolderContents $env:TEMP }
                    'wintemp'  { SetStatus (T 'Removing Windows temporary files'); $freed = Clear-FolderContents (Join-Path $env:windir 'Temp') }
                    'recycle'  { SetStatus (T 'Emptying the Recycle Bin'); Clear-RecycleBinAll }
                    'delivery' {
                        SetStatus (T 'Clearing the update download cache')
                        if (-not (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) { throw (T 'Not available on this PC') }
                        Delete-DeliveryOptimizationCache -Force
                    }
                    'dism' {
                        SetStatus (T 'Cleaning up old Windows components (this is slow)')
                        $code = Invoke-Native Dism.exe @('/Online', '/Cleanup-Image', '/StartComponentCleanup')
                        if ($code -ne 0) { throw ((T 'Windows component cleanup failed (code {0})') -f $code) }
                    }
                }
                if ($null -eq $freed) { $freed = [math]::Max(0, (Get-SystemDriveFree) - $f0) }
                Step $k 'ok' ((T 'Freed {0}') -f (Format-Bytes $freed))
                Log ('{0}: freed {1}' -f $k, (Format-Bytes $freed))
            } catch {
                Step $k 'error' $_.Exception.Message
                Log $_.Exception.Message 'error'
            }
        }
        $Sync.Base = 0; $Sync.Span = 100
        $end = Get-SystemDriveFree
        [pscustomobject]@{ Freed = [math]::Max(0, $end - $start); Free = $end }
    } -OnDone {
        param($r, $err)
        if ($err) { Add-TaskLog "[X] $err" }
        if ($r) { $script:Ctx.Summary = (T 'Freed {0} in total. Drive {1} now has {2} free.') -f (Format-Bytes $r.Freed), $env:SystemDrive, (Format-Bytes $r.Free) }
        Invoke-NextStage
    }
}

#endregion

#region ---------- Battery ----------

function Open-Battery {
    Show-Page 'PanelBattery' (T 'Battery health') (T 'How much charge your battery can still hold compared to when it was new.')
    $ui.TxtBatLoading.Text = (T 'Reading battery information...')
    $ui.TxtBatLoading.Visibility = 'Visible'
    $ui.BatContent.Visibility = 'Collapsed'
    Start-Worker -Work { [pscustomobject]@{ B = Get-BatteryInfo } } -OnDone { param($r, $err) Show-Battery $r.B $err }
}

function Show-Battery($b, $err) {
    if ($err) { $ui.TxtBatLoading.Text = (T "Couldn't read battery information: {0}") -f $err; return }
    if (-not $b) { $ui.TxtBatLoading.Text = T "This PC doesn't have a battery."; return }
    $ui.TxtBatLoading.Visibility = 'Collapsed'
    $ui.BatContent.Visibility = 'Visible'

    $ui.TxtBatCharge.Text = '{0}%' -f $b.Charge
    $ui.BatChargeBar.Value = $b.Charge
    $ui.TxtBatSource.Text = if ($b.OnAC) { T 'Plugged in' } else { T 'Running on battery' }

    if ($null -ne $b.Health) {
        $h = [int]$b.Health
        $ui.TxtBatHealth.Text = "$h%"
        $ui.BatHealthBar.Value = $h
        $ui.TxtBatCap.Text = (T 'Holds {0:N0} mWh today, compared to {1:N0} mWh when new.') -f $b.Full, $b.Design
        if ($h -ge 80) { $v = @('ok', (T 'Good. Your battery is in good shape.')) }
        elseif ($h -ge 60) { $v = @('warn', (T "Fair. The battery has worn a bit, so it won't last as long as when it was new.")) }
        else { $v = @('bad', (T 'Worn. The battery holds much less than when new. Consider asking IT about a replacement.')) }
    } else {
        $ui.TxtBatHealth.Text = '?'
        $ui.BatHealthBar.Value = 0
        $ui.TxtBatCap.Text = T "This PC doesn't report battery health."
        $v = @('info', (T "Health isn't available here. The detailed battery report below may have more information."))
    }
    $look = @{
        ok   = @('E930', 'GoodBg', 'GoodLine', $Colors.Good)
        warn = @('E7BA', 'WarnBg', 'WarnLine', $Colors.Warn)
        bad  = @('EA39', 'BadBg', 'BadLine', $Colors.Bad)
        info = @('E946', 'InfoBg', 'InfoLine', $Colors.Accent)
    }[$v[0]]
    Set-Themed $ui.BatHealthBar Foreground $look[3]
    Set-Themed $ui.BatVerdict Background $look[1]
    Set-Themed $ui.BatVerdict BorderBrush $look[2]
    $ui.BatVerdictIcon.Text = [string][char][Convert]::ToInt32($look[0], 16)
    Set-Themed $ui.BatVerdictIcon Foreground $look[3]
    $ui.TxtBatVerdict.Text = $v[1]
}

function New-BatteryReport {
    $ui.BtnBatReport.IsEnabled = $false
    $path = Get-DesktopPath ('battery-report-{0:yyyyMMdd-HHmm}.html' -f (Get-Date))
    Start-Worker -ArgumentList $path -Work {
        param($path)
        $ErrorActionPreference = 'Continue'
        & powercfg /batteryreport /output $path 2>&1 | Out-Null
        [pscustomobject]@{ Ok = (Test-Path $path); Path = $path }
    } -OnDone {
        param($r, $err)
        $ui.BtnBatReport.IsEnabled = $true
        if ($r -and $r.Ok) { Invoke-Item $r.Path; [void](Show-Dialog -Title (T 'Battery report created') -Icon ok -Message ((T "The report opened in your browser. It's also saved on your desktop:`n{0}") -f $r.Path)) }
        else { Show-Error ((T "Windows couldn't create the battery report. {0}") -f $err) }
    }
}

#endregion

#region ---------- Sleep and wake ----------

function Open-Sleep {
    Show-Page 'PanelSleep' (T 'Sleep and wake') (T 'Find out what wakes your PC up and what stops it from going to sleep.')
    Update-Sleep
}

function Update-Sleep {
    $ui.TxtSleepLoading.Visibility = 'Visible'
    $ui.SleepContent.Visibility = 'Collapsed'
    Start-Worker -ArgumentList (Test-IsAdmin) -Work {
        param($admin)
        [pscustomobject]@{
            Admin    = $admin
            LastWake = Get-NativeText powercfg @('/lastwake')
            Devices  = @(Get-WakeArmedDevices)
            Timers   = if ($admin) { Get-NativeText powercfg @('/waketimers') } else { '' }
            Requests = if ($admin) { Get-NativeText powercfg @('/requests') } else { '' }
        }
    } -OnDone { param($r, $err) Show-Sleep $r $err }
}

function Show-Sleep($r, $err) {
    if ($err) { $ui.TxtSleepLoading.Text = (T "Couldn't read sleep information: {0}") -f $err; return }
    $ui.TxtSleepLoading.Visibility = 'Collapsed'
    $ui.SleepContent.Visibility = 'Visible'
    $ui.TxtLastWake.Text = $r.LastWake
    $ui.WakeDevices.Children.Clear()
    if (-not @($r.Devices).Count) {
        [void]$ui.WakeDevices.Children.Add((New-Xaml "<TextBlock Text=`"$(X 'No devices are allowed to wake this PC.')`" Foreground=`"{DynamicResource Muted}`"/>"))
    }
    foreach ($dev in @($r.Devices)) {
        $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="0,1,0,0" Padding="0,8">
  <DockPanel>
    <Button DockPanel.Dock="Right" Content="$(X 'Stop it waking the PC')" Padding="12,5"/>
    <TextBlock Text="$(Esc $dev)" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,12,0"/>
  </DockPanel>
</Border>
"@
        $btn = $row.Child.Children[0]
        $btn.Tag = $dev
        $btn.Add_Click({ param($s, $e) Disable-WakeDevice $s.Tag })
        [void]$ui.WakeDevices.Children.Add($row)
    }
    $ui.SleepAdmin.Visibility = if ($r.Admin) { 'Visible' } else { 'Collapsed' }
    $ui.TxtSleepAdminNote.Visibility = if ($r.Admin) { 'Collapsed' } else { 'Visible' }
    $ui.TxtWakeTimers.Text = $r.Timers
    $ui.TxtRequests.Text = $r.Requests
}

function Disable-WakeDevice([string]$Name) {
    if (-not (Confirm-Admin (T 'Changing which devices can wake the PC'))) { return }
    $d = Show-Dialog -Title (T 'Stop this device from waking the PC?') -Icon question `
        -Message ("$Name`n`n" + (T "It will still work normally, it just can't wake the PC from sleep anymore. You can turn it back on in Device Manager.")) `
        -Buttons 'Stop it', 'Cancel'
    if ($d.Button -ne 'Stop it') { return }
    & powercfg /devicedisablewake "$Name"
    if ($LASTEXITCODE -ne 0) { Show-Error ((T "Windows couldn't change this device (powercfg error {0}).") -f $LASTEXITCODE) }
    Update-Sleep
}

function New-SleepStudy {
    if (-not (Confirm-Admin (T 'The sleep report'))) { return }
    $ui.BtnSleepStudy.IsEnabled = $false
    $path = Get-DesktopPath ('sleep-report-{0:yyyyMMdd-HHmm}.html' -f (Get-Date))
    Start-Worker -ArgumentList $path -Work {
        param($path)
        $ErrorActionPreference = 'Continue'
        & powercfg /sleepstudy /output $path 2>&1 | Out-Null
        [pscustomobject]@{ Ok = (Test-Path $path); Path = $path }
    } -OnDone {
        param($r, $err)
        $ui.BtnSleepStudy.IsEnabled = $true
        if ($r -and $r.Ok) { Invoke-Item $r.Path }
        else { Show-Error (T "Windows couldn't create a sleep report. It's only available on PCs with Modern Standby (most newer laptops).") }
    }
}

#endregion

#region ---------- Lid and sign-in ----------

function Open-Power {
    Show-Page 'PanelPower' (T 'Lid and sign-in') (T 'Choose what happens when you close the lid, and whether you need a password after sleep.')
    $ui.PowerSaved.Visibility = 'Collapsed'
    $script:Lid = Get-PowerVal -Sub 'SUB_BUTTONS' -Setting 'LIDACTION'
    if ($script:Lid.OK) {
        $ui.CardLid.Visibility = 'Visible'; $ui.CardNoLid.Visibility = 'Collapsed'
        $ui.CmbLidAC.SelectedIndex = [math]::Min(3, $script:Lid.AC)
        $ui.CmbLidDC.SelectedIndex = [math]::Min(3, $script:Lid.DC)
    } else {
        $ui.CardLid.Visibility = 'Collapsed'; $ui.CardNoLid.Visibility = 'Visible'
    }

    $lock = Get-PowerVal -Sub 'SUB_NONE' -Setting 'CONSOLELOCK'
    $require = if ($lock.OK) { [bool]$lock.AC } else { $true }
    $note = ''
    $reg = Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name DelayLockInterval -ErrorAction SilentlyContinue
    if ($null -ne $reg) {
        $v = [int]$reg.DelayLockInterval
        if ($v -eq 0) { $require = $true } elseif ($v -eq -1) { $require = $false } else { $note = (T 'Currently: after {0} seconds away.') -f $v }
    }
    $ui.CmbSignIn.SelectedIndex = if ($require) { 0 } else { 1 }
    $ui.TxtSignInNote.Text = $note
    $ui.TxtSignInNote.Visibility = if ($note) { 'Visible' } else { 'Collapsed' }
}

function Save-Power {
    $ui.PowerSaved.Visibility = 'Collapsed'
    if ($script:Lid.OK) {
        $ac = $ui.CmbLidAC.SelectedIndex; $dc = $ui.CmbLidDC.SelectedIndex
        if (($ac -eq 2 -or $dc -eq 2) -and -not (Test-HibernateEnabled)) {
            $d = Show-Dialog -Title (T 'Hibernate is turned off') -Icon warn `
                -Message (T "Hibernate is turned off on this PC, so choosing 'Hibernate' might not do anything. Save anyway?") -Buttons 'Save anyway', 'Cancel'
            if ($d.Button -ne 'Save anyway') { return }
        }
        Set-PowerVal -Sub 'SUB_BUTTONS' -Setting 'LIDACTION' -Value $ac -AC
        Set-PowerVal -Sub 'SUB_BUTTONS' -Setting 'LIDACTION' -Value $dc -DC
    }
    $require = ($ui.CmbSignIn.SelectedIndex -eq 0)
    Set-PowerVal -Sub 'SUB_NONE' -Setting 'CONSOLELOCK' -Value ([int]$require) -AC -DC
    # Modern Standby laptops use this instead (0 = every time, -1 = never)
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name DelayLockInterval -Value ([int]$(if ($require) { 0 } else { -1 })) -Type DWord
    $ui.TxtSignInNote.Visibility = 'Collapsed'
    $ui.PowerSaved.Visibility = 'Visible'
}

#endregion

#region ---------- About this PC ----------

function Open-Info {
    Show-Page 'PanelInfo' (T 'About this PC') (T 'The details IT support usually asks for.')
    $ui.TxtInfoLoading.Visibility = 'Visible'
    $ui.InfoCard.Visibility = 'Collapsed'
    $ui.InfoDisksTitle.Visibility = 'Collapsed'
    $ui.InfoDisks.Children.Clear()
    $ui.TxtInfoCopy.Text = (T 'Copy details')
    Start-Worker -Work { Get-SystemSnapshot } -OnDone { param($r, $err) Show-Info $r $err }
}

function Show-Info($s, $err) {
    if ($err -or -not $s) { $ui.TxtInfoLoading.Text = (T "Couldn't read PC information: {0}") -f $err; return }
    $ui.TxtInfoLoading.Visibility = 'Collapsed'
    $ui.InfoCard.Visibility = 'Visible'
    $ui.InfoRows.Children.Clear()

    $bat = if ($s.Battery) {
        $t = '{0}% ({1})' -f $s.Battery.Charge, $(if ($s.Battery.OnAC) { (T 'Plugged in').ToLower() } else { (T 'On battery').ToLower() })
        if ($null -ne $s.Battery.Health) { $t += (T ', health {0}%') -f $s.Battery.Health }
        $t
    } else { T 'None' }
    $reasons = @($s.RebootReasons | Where-Object { $_ -notlike 'Pending file renames*' })
    $rows = [ordered]@{
        'Computer name'   = $s.Computer
        'Signed in as'    = $s.User
        'Model'           = $s.Model
        'Serial number'   = $s.Serial
        'Windows'         = $s.OS
        'Windows build'   = $s.Build
        'Processor'       = $s.Cpu
        'Memory'          = '{0} ({1} free right now)' -f (Format-Bytes $s.MemTotal), (Format-Bytes $s.MemFree)
        'Power plan'      = $s.PowerPlan
        'Battery'         = $bat
        'Last restart'    = (T '{0:yyyy-MM-dd HH:mm} ({1} ago)') -f $s.LastBoot, (Format-Duration $s.Uptime)
        'Restart needed'  = if ($reasons.Count) { (T 'Yes: ') + (($reasons | ForEach-Object { T $_ }) -join ', ') } else { T 'No' }
        'Administrator'   = if ($s.IsAdmin) { T 'Yes' } else { T 'No' }
        'App version'     = "PC Maintenance $AppVersion"
    }
    $script:InfoText = ($rows.Keys | ForEach-Object { '{0,-22}: {1}' -f (T $_), $rows[$_] }) -join "`r`n"
    $first = $true
    foreach ($k in $rows.Keys) {
        $border = if ($first) { '0' } else { '0,1,0,0' }
        $first = $false
        $row = New-Xaml @"
<Border BorderBrush="{DynamicResource LineSoft}" BorderThickness="$border" Padding="0,9">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="180"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <TextBlock Text="$(X $k)" Foreground="{DynamicResource Muted}"/>
    <TextBlock Grid.Column="1" Text="$(Esc $rows[$k])" TextWrapping="Wrap"/>
  </Grid>
</Border>
"@
        [void]$ui.InfoRows.Children.Add($row)
    }

    $diskLines = @()
    foreach ($d in @($s.Disks)) {
        if (-not $d.Size) { continue }
        $freePct = 100 * $d.Free / $d.Size
        $color = if ($freePct -lt 10) { $Colors.Bad } elseif ($freePct -lt 20) { $Colors.Warn } else { $Colors.Accent }
        $name = if ($d.Label) { '{0} ({1})' -f $d.Drive, $d.Label } else { $d.Drive }
        $line = (T '{0} free of {1}') -f (Format-Bytes $d.Free), (Format-Bytes $d.Size)
        $diskLines += '{0,-22}: {1}' -f ((T 'Disk {0}') -f $d.Drive), $line
        $card = New-Xaml @"
<Border Background="{DynamicResource Surface}" BorderBrush="{DynamicResource Line}" BorderThickness="1" CornerRadius="8" Padding="18,14" Margin="0,0,0,10">
  <StackPanel>
    <DockPanel>
      <TextBlock DockPanel.Dock="Right" Text="$(Esc $line)" Foreground="{DynamicResource Muted}"/>
      <TextBlock Text="$(Esc $name)" FontWeight="SemiBold"/>
    </DockPanel>
    <ProgressBar Height="8" Maximum="100" Value="$([int](100 - $freePct))" Foreground="{DynamicResource $color}" Margin="0,10,0,0"/>
  </StackPanel>
</Border>
"@
        [void]$ui.InfoDisks.Children.Add($card)
    }
    if ($diskLines.Count) {
        $ui.InfoDisksTitle.Visibility = 'Visible'
        $script:InfoText += "`r`n" + ($diskLines -join "`r`n")
    }
}

#endregion

#region ---------- Restore point ----------

# Restore points are often blocked on work PCs (group policy), and creating one needs administrator rights.
function Test-RestorePolicyBlocked {
    $p = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore' -ErrorAction SilentlyContinue
    [bool]($p -and ($p.DisableSR -eq 1 -or $p.DisableConfig -eq 1))
}

# Should "Update everything" / app updates create (and ask about) a restore point?
function Test-RestorePointsWanted {
    if ([int](Get-AppSetting 'SkipRestorePoint' 0)) { return $false }
    -not (Test-RestorePolicyBlocked)
}

function Open-Restore {
    Show-Page 'PanelRestore' (T 'Restore point') (T 'A safety snapshot of Windows settings and system files, so system changes can be undone.')
    $blocked = Test-RestorePolicyBlocked
    $ui.ChkRestoreBefore.IsChecked = (-not [int](Get-AppSetting 'SkipRestorePoint' 0)) -and -not $blocked
    $ui.ChkRestoreBefore.IsEnabled = -not $blocked
    $ui.BtnRestoreNow.IsEnabled = -not $blocked
    $ui.RestoreBlocked.Visibility = if ($blocked) { 'Visible' } else { 'Collapsed' }
}

function Set-RestoreBefore {
    $on = [bool]$ui.ChkRestoreBefore.IsChecked
    Set-AppSetting 'SkipRestorePoint' ([int](-not $on))
    Add-History -Title $(if ($on) { T 'Restore points before updates turned on' } else { T 'Restore points before updates turned off' }) -State info
}

function Start-RestorePointTask {
    if (-not (Confirm-Admin (T 'Creating a restore point'))) { return }
    $d = Show-Dialog -Title (T 'Create a restore point?') -Icon question `
        -Message (T "A restore point is a snapshot of Windows settings and system files. If something goes wrong later, Windows can go back to it.`n`nYour personal files are not affected.") `
        -Buttons 'Create', 'Cancel'
    if ($d.Button -ne 'Create') { return }
    $script:Ctx = @{}
    Open-TaskPage (T 'Creating a restore point') '' 'Restore'
    Add-TaskStep 'restore' (T 'Restore point')
    Start-Flow @({ Invoke-RestoreStage }, { Complete-Task })
}

#endregion

#region ---------- Install, Start menu and updates ----------
#
# Three ways the app can be running:
#   Git copy      - a clone of the repository (developers): updates with git pull.
#   Installed     - %LOCALAPPDATA%\Programs\PC Maintenance, from a release zip: updates from GitHub Releases.
#   Unpacked zip  - e.g. in Downloads: offers to install itself (no admin needed) on first start.
# Git and installed copies get a Start menu entry; the installed copy also gets an entry in Settings > Apps.

$InstallDir   = Join-Path $env:LOCALAPPDATA 'Programs\PC Maintenance'
$IsGitCopy    = Test-Path (Join-Path $AppDir '.git')
$IsInstalled  = ($AppDir.TrimEnd('\') -eq $InstallDir.TrimEnd('\'))
$ShortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'PC Maintenance.lnk'
$AutoTaskName = 'PC Maintenance automatic maintenance'
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PCMaintenance'
$AumidKey     = 'HKCU:\Software\Classes\AppUserModelId\PCMaintenance'

function Set-StartMenuShortcut([string]$Dir = $AppDir) {
    $exe = Join-Path $Dir 'PC Maintenance.exe'
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($ShortcutPath)
    if (Test-Path -LiteralPath $exe) {
        $lnk.TargetPath = $exe
        $lnk.Arguments = ''
        $lnk.IconLocation = "$exe,0"
    } else {
        $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$(Join-Path $Dir 'MaintainGui.ps1')`""
        $lnk.IconLocation = Join-Path $Dir 'assets\app.ico'
    }
    $lnk.WorkingDirectory = $Dir
    $lnk.Description = T 'Keep this PC up to date and tidy'
    $lnk.Save()
}

# Name and icon for Windows notifications, and (installed copy) the Settings > Apps entry with Uninstall.
function Register-AppIdentity([string]$Dir = $AppDir, [switch]$Installed) {
    if (-not (Test-Path $AumidKey)) { New-Item $AumidKey -Force | Out-Null }
    Set-ItemProperty $AumidKey -Name DisplayName -Value 'PC Maintenance'
    $png = Join-Path $Dir 'assets\app.png'
    if (Test-Path $png) { Set-ItemProperty $AumidKey -Name IconUri -Value $png }

    if (-not $Installed) { return }
    if (-not (Test-Path $UninstallKey)) { New-Item $UninstallKey -Force | Out-Null }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $sizeKb = [int]((Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1KB)
    $values = @{
        DisplayName     = 'PC Maintenance'
        DisplayVersion  = $AppVersion
        Publisher       = 'PC Maintenance'
        DisplayIcon     = Join-Path $Dir 'PC Maintenance.exe'
        InstallLocation = $Dir
        UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $Dir 'MaintainGui.ps1')`" -Uninstall"
    }
    foreach ($k in $values.Keys) { Set-ItemProperty $UninstallKey -Name $k -Value $values[$k] }
    foreach ($k in 'NoModify', 'NoRepair') { Set-ItemProperty $UninstallKey -Name $k -Value 1 -Type DWord }
    Set-ItemProperty $UninstallKey -Name EstimatedSize -Value $sizeKb -Type DWord
}

function Install-App {
    Copy-AppFiles -From $AppDir -To $InstallDir
    Set-StartMenuShortcut $InstallDir
    Register-AppIdentity $InstallDir -Installed
    Add-History -Title (T 'PC Maintenance installed') -State ok -Detail ((T 'Version {0}') -f $AppVersion)
}

# Runs at startup. Returns $true when the app was just installed and the installed copy started
# (then this window should close).
function Initialize-Install {
    try {
        if ($IsGitCopy -or $IsInstalled) {
            Set-StartMenuShortcut
            Register-AppIdentity -Installed:$IsInstalled
            return $false
        }
        if (Get-AppSetting 'SkipInstallPrompt') { return $false }
        $d = Show-Dialog -Title (T 'Install PC Maintenance?') -Icon question `
            -Message (T 'Install it on this PC to add it to the Start menu and keep it up to date automatically. It only takes a moment, and no administrator rights are needed.') `
            -Buttons 'Install', 'Just run it this time' -CheckBox "Don't ask again"
        if ($d.Button -ne 'Install') {
            if ($d.Checked) { Set-AppSetting 'SkipInstallPrompt' 1 }
            return $false
        }
        Install-App
        Start-Process -FilePath (Join-Path $InstallDir 'PC Maintenance.exe') -ArgumentList '--no-update'
        return $true
    } catch {
        Show-Error ((T 'Installing failed: {0}') -f $_.Exception.Message)
        return $false
    }
}

# -Uninstall (from Settings > Apps): remove everything this app created, then the folder itself.
function Invoke-Uninstall {
    Add-Type -AssemblyName PresentationFramework
    $ok = [System.Windows.MessageBox]::Show((T 'Remove PC Maintenance from this PC?'), 'PC Maintenance', 'YesNo', 'Question')
    if ($ok -ne 'Yes') { return }
    try { Unregister-ScheduledTask -TaskName $AutoTaskName -Confirm:$false -ErrorAction Stop } catch {}
    foreach ($p in $ShortcutPath, $UninstallKey, $AumidKey, $SettingsKey) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    if ($IsInstalled) {
        # This script runs from the folder, so delete it a moment after we exit
        Start-Process cmd.exe -WindowStyle Hidden -WorkingDirectory $env:TEMP `
            -ArgumentList "/c ping -n 3 127.0.0.1 >nul & rmdir /s /q `"$InstallDir`""
    }
    [void][System.Windows.MessageBox]::Show((T 'PC Maintenance was removed.'), 'PC Maintenance', 'OK', 'Information')
}

function Start-SelfUpdateCheck {
    if ($NoUpdate) { return }
    if ($IsGitCopy) { Start-GitUpdate }
    elseif ($IsInstalled) { Start-ReleaseUpdate }
}

# Installed copies: download the newest GitHub release if it is newer than this version.
function Start-ReleaseUpdate {
    Start-Worker -ArgumentList $AppDir, $RepoApi, $AppVersion -Work {
        param($dir, $api, $ver)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $rel = Invoke-RestMethod "$api/releases/latest" -Headers @{ 'User-Agent' = 'PCMaintenance' } -TimeoutSec 20
        $tag = "$($rel.tag_name)" -replace '^v', ''
        if (-not $tag -or [version]$tag -le [version]$ver) { return [pscustomobject]@{ Status = 'current' } }
        $asset = @($rel.assets | Where-Object { $_.name -like '*.zip' }) | Select-Object -First 1
        if (-not $asset) { return [pscustomobject]@{ Status = 'noasset' } }

        $tmp = Join-Path $env:TEMP ('PCMaintenance-update-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Force $tmp | Out-Null
        try {
            $zip = Join-Path $tmp 'update.zip'
            Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'PCMaintenance' } -TimeoutSec 120
            $out = Join-Path $tmp 'files'
            Expand-Archive -LiteralPath $zip -DestinationPath $out -Force
            if (-not (Test-Path (Join-Path $out 'MaintainGui.ps1'))) { throw 'The update package is not valid.' }
            Copy-AppFiles -From $out -To $dir
        } finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
        [pscustomobject]@{ Status = 'updated'; Version = $tag; Notes = "$($rel.body)" }
    } -OnDone {
        param($r, $err)
        if (-not $r -or $r.Status -ne 'updated') { return }
        Add-History -Title ((T 'Updated PC Maintenance to version {0}') -f $r.Version) -State ok -Detail $r.Notes
        $ui.TxtBanner.Text = (T 'PC Maintenance was updated to version {0}. Restart the app to start using it.') -f $r.Version
        $ui.Banner.ToolTip = $r.Notes
        $ui.Banner.Visibility = 'Visible'
    }
}

function Start-GitUpdate {
    Start-Worker -ArgumentList $AppDir, $RepoUrl -Work {
        param($dir, $url)
        $ErrorActionPreference = 'Continue'
        if (-not (Get-Command git -ErrorAction SilentlyContinue) -or -not (Test-Path (Join-Path $dir '.git'))) {
            return [pscustomobject]@{ Status = 'skip' }
        }
        $env:GIT_TERMINAL_PROMPT = '0'
        $old = "$(& git -C $dir -c safe.directory=* rev-parse --short HEAD 2>$null)".Trim()
        $null = & git -C $dir -c safe.directory=* pull --ff-only --quiet $url main 2>&1
        $ok = ($LASTEXITCODE -eq 0)
        $new = "$(& git -C $dir -c safe.directory=* rev-parse --short HEAD 2>$null)".Trim()
        $log = @()
        if ($ok -and $old -and $new -and $old -ne $new) { $log = @(& git -C $dir -c safe.directory=* log --format=%s "$old..$new" 2>$null) }
        $status = if (-not $ok) { 'failed' } elseif ($old -ne $new) { 'updated' } else { 'current' }
        [pscustomobject]@{ Status = $status; Old = $old; New = $new; Log = $log }
    } -OnDone {
        param($r, $err)
        if (-not $r -or $r.Status -ne 'updated') { return }
        $n = @($r.Log).Count
        $ui.TxtBanner.Text = T 'A newer version of PC Maintenance was downloaded. Restart the app to start using it.'
        $ui.Banner.ToolTip = (@($r.Log) -join "`n")
        $ui.Banner.Visibility = 'Visible'
    }
}

#endregion

#region ---------- Start ----------

if ($Uninstall) { Invoke-Uninstall; [Environment]::Exit(0) }
if ($Auto) { Invoke-AutoMaintenance; [Environment]::Exit(0) }

try {
    $App = New-Object System.Windows.Application
    $App.ShutdownMode = 'OnMainWindowClose'
    $App.Resources = [Windows.Markup.XamlReader]::Parse($ResourcesXaml)
    $ui = $null
    Set-Theme (Get-StartTheme)
    $App.Add_DispatcherUnhandledException({
        param($s, $e)
        $e.Handled = $true
        try { Show-Error $e.Exception } catch {}
    })

    $script:Window = [Windows.Markup.XamlReader]::Parse($MainXaml)
    $ui = @{}
    foreach ($m in [regex]::Matches($MainXaml, 'x:Name="(\w+)"')) { $ui[$m.Groups[1].Value] = $script:Window.FindName($m.Groups[1].Value) }

    $iconPath = Join-Path $AppDir 'assets\app.ico'
    # Read into memory so the file isn't locked (updates replace it while the app runs)
    if (Test-Path $iconPath) {
        try {
            $ms = New-Object System.IO.MemoryStream (, [IO.File]::ReadAllBytes($iconPath))
            $script:Window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create($ms, 'None', 'OnLoad')
        } catch {}
    }

    $isAdmin = Test-IsAdmin
    $ui.TxtVersion.Text = (T 'Version {0}') -f $AppVersion
    $script:Window.Title = if ($isAdmin) { "PC Maintenance $AppVersion (" + (T 'Administrator') + ")" } else { "PC Maintenance $AppVersion" }
    $ui.AdminBadge.Visibility = if ($isAdmin) { 'Visible' } else { 'Collapsed' }
    $ui.BtnElevate.Visibility = if ($isAdmin) { 'Collapsed' } else { 'Visible' }

    # --- wire up events ---
    Set-Theme $script:Theme   # now that the header exists: set the toggle icon
    $script:Window.Add_SourceInitialized({ Set-DarkTitleBar $script:Window })
    $ui.BtnTheme.Add_Click({ Switch-Theme })
    $ui.BtnTaskLog.Add_Click({
        $show = $ui.TxtTaskLog.Visibility -ne 'Visible'
        $ui.TxtTaskLog.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
        $ui.TaskLogChevron.Text = if ($show) { [string][char]0xE70E } else { [string][char]0xE70D }
    })
    $ui.BtnElevate.Add_Click({ Restart-AsAdmin })
    $ui.BtnBanner.Add_Click({ Restart-App })
    $ui.BtnBack.Add_Click({ Open-Target $script:BackTarget })
    $ui.BtnUpdateAll.Add_Click({ Start-UpdateEverything })
    $ui.BtnRestartHome.Add_Click({ Confirm-RestartComputer })

    $ui.BtnLang.Add_Click({ Switch-Language })
    $ui.TxtLang.Text = if ($Lang -eq 'nb') { 'English' } else { 'Norsk' }
    $ui.BtnLang.ToolTip = if ($Lang -eq 'nb') { 'Switch to English' } else { 'Bytt til norsk' }

    foreach ($f in $Features) {
        $tile = $ui["Tile$($f.Name)"]
        if ($tile) {
            $tile.Tag = $f.Name
            $tile.Add_Click({ param($s, $e) Open-Feature $s.Tag })
        }
    }
    foreach ($f in $Features) { if ($f.Init) { & $f.Init } }

    $ui.BtnAppsUpdate.Add_Click({ Start-AppUpdates })
    $ui.BtnAppsRefresh.Add_Click({ Update-AppList })
    $ui.ChkAppsUnknown.Add_Click({ Update-AppList })
    $ui.BtnAppsSelect.Add_Click({
        $all = @($script:AppRows | Where-Object { $_.IsChecked }).Count -ne $script:AppRows.Count
        foreach ($cb in $script:AppRows) { $cb.IsChecked = $all }
    })

    $ui.BtnCleanRun.Add_Click({ Start-Cleanup })
    $ui.BtnCleanMgr.Add_Click({ Start-Process cleanmgr.exe -ArgumentList "/d $($env:SystemDrive.TrimEnd(':'))" })

    $ui.BtnBatReport.Add_Click({ New-BatteryReport })
    $ui.BtnSleepRefresh.Add_Click({ Update-Sleep })
    $ui.BtnSleepStudy.Add_Click({ New-SleepStudy })
    $ui.BtnPowerSave.Add_Click({ Save-Power })
    $ui.CmbLidAC.Add_SelectionChanged({ $ui.PowerSaved.Visibility = 'Collapsed' })
    $ui.CmbLidDC.Add_SelectionChanged({ $ui.PowerSaved.Visibility = 'Collapsed' })
    $ui.CmbSignIn.Add_SelectionChanged({ $ui.PowerSaved.Visibility = 'Collapsed' })
    $ui.BtnInfoCopy.Add_Click({
        if ($script:InfoText) { [System.Windows.Clipboard]::SetText($script:InfoText); $ui.TxtInfoCopy.Text = (T 'Copied!') }
    })

    $ui.BtnTaskDone.Add_Click({ Open-Target $script:BackTarget })
    $ui.BtnTaskRestart.Add_Click({ Confirm-RestartComputer })
    $ui.BtnTaskAction.Add_Click({ if ($script:TaskAction) { & $script:TaskAction } })

    $script:Window.Add_Closing({
        param($s, $e)
        if ($script:TaskBusy) {
            $d = Show-Dialog -Title (T 'A task is still running') -Icon warn `
                -Message (T 'If you close the app now, the current task is stopped and may be left half-finished. Close anyway?') `
                -Buttons 'Keep it running', 'Close anyway'
            if ($d.Button -ne 'Close anyway') { $e.Cancel = $true; return }
        }
        foreach ($w in @($script:Workers)) { try { [void]$w.PS.BeginStop($null, $null) } catch {} }
    })

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({ try { Invoke-WorkerTick } catch { try { Add-TaskLog "[X] $($_.Exception.Message)" } catch {} } })

    $script:Window.Add_ContentRendered({
        $timer.Start()
        if (-not $NoUpdate -and -not $env:MAINT_TEST_LANG -and -not $env:MAINT_TEST_THEME -and (Initialize-Install)) {
            $script:Window.Close(); return
        }
        Update-Home
        Start-SelfUpdateCheck
        if ($StartPage) { Open-Feature $StartPage }
    })

    [void]$App.Run($script:Window)
} catch {
    $msg = $_ | Out-String
    try { $msg | Set-Content -Encoding UTF8 (Join-Path $env:TEMP 'PCMaintenance-error.log') } catch {}
    [void][System.Windows.MessageBox]::Show("PC Maintenance could not start.`n`n$($_.Exception.Message)", 'PC Maintenance', 'OK', 'Error')
}
# Background jobs (e.g. a stuck Windows Update search) must not keep the process alive.
[Environment]::Exit(0)

#endregion
