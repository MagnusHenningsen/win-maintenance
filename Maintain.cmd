<# : batch launcher - PowerShell sees this block as a comment
@echo off
rem Maintenance.cmd - single-file maintenance menu. Double-click to run.
rem Everything sits in one ( ) block: cmd parses the whole block up front, so git pull
rem rewriting this file mid-run can't make cmd read half-old, half-new lines.
rem Delayed expansion (!VAR!) is needed to read variables set inside the block.
setlocal EnableDelayedExpansion
(
    set "MAINT_SELF=%~f0"
    rem "elevated" = relaunched as admin by this script: already updated, don't pull or elevate again.
    if /i not "%~1"=="elevated" (
        where git >nul 2>&1 && (
            echo Checking for script updates...
            set "OLD=" & set "NEW="
            for /f %%h in ('git -C "%~dp0." -c safe.directory^=* rev-parse --short HEAD 2^>nul') do set "OLD=%%h"
            git -C "%~dp0." -c safe.directory=* pull --ff-only --quiet https://github.com/MagnusHenningsen/win-maintenance.git main || echo Update skipped ^(offline, no remote, or local changes^).
            for /f %%h in ('git -C "%~dp0." -c safe.directory^=* rev-parse --short HEAD 2^>nul') do set "NEW=%%h"
            if defined OLD if not "!OLD!"=="!NEW!" (
                echo.
                echo Script updated !OLD! -^> !NEW!:
                git -C "%~dp0." -c safe.directory=* log --oneline !OLD!..!NEW!
                echo.
                timeout /t 5
            )
        )
        rem Ask for admin once here, so installs don't each trigger their own UAC prompt.
        fltmc >nul 2>&1 || (
            echo Asking for administrator rights...
            powershell.exe -NoProfile -Command "Start-Process -FilePath $env:MAINT_SELF -ArgumentList 'elevated' -Verb RunAs" >nul 2>&1 && exit /b
            echo Admin declined - continuing without admin.
        )
    )
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText($env:MAINT_SELF))"
    if errorlevel 1 pause
    exit /b
)
#>

# Interactive maintenance menu: winget updates, system summary, disk cleanup,
# battery report, sleep diagnostics, lid close action, sign-in on wake.
# Works regardless of Windows display language (powercfg values parsed by hex, winget by column position).

$ErrorActionPreference = 'Stop'

#region ---------- General helpers ----------

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) { throw 'This needs admin. Use menu option A to relaunch elevated.' }
}

function Wait-Enter { Write-Host ''; [void](Read-Host 'Press Enter to continue') }

function Write-Section([string]$Title) {
    Write-Host ''
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Read-Choice {
    param([string]$Prompt, [string[]]$Valid)
    while ($true) {
        $a = (Read-Host $Prompt).Trim().ToUpper()
        if ($Valid -contains $a) { return $a }
        Write-Host "Invalid choice: '$a'" -ForegroundColor Yellow
    }
}

function Write-StatusLine([string]$Text) {
    $w = try { [Console]::WindowWidth - 1 } catch { 119 }
    if ($w -lt 20) { $w = 79 }
    if ($Text.Length -gt $w) { $Text = $Text.Substring(0, $w) }
    [Console]::Write("`r" + $Text.PadRight($w) + "`r")
}

# Runs a scriptblock in a background runspace while showing a live status line:
#   | Activity  42%  01:23  current item
# Inside the scriptblock you can call:
#   Log 'text'                 -> prints a permanent line above the status line
#   SetStatus 'text' [percent] -> updates the status text / percentage
# -Functions imports functions from this script into the background runspace.
function Invoke-WithSpinner {
    param(
        [Parameter(Mandatory)][string]$Activity,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [string[]]$Functions = @()
    )

    $sync = [hashtable]::Synchronized(@{
        Status  = ''
        Percent = -1
        Log     = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    })

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($f in $Functions) {
        $def = (Get-Command $f -CommandType Function).Definition
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry $f, $def))
    }
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry 'Sync', $sync, ''))

    $prelude = @'
$ErrorActionPreference = 'Stop'
function Log([string]$m) { $Sync.Log.Enqueue($m) }
function SetStatus([string]$s, [double]$p = -1) { $Sync.Status = $s; $Sync.Percent = $p }
'@

    $rs = [runspacefactory]::CreateRunspace($iss)
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($prelude + "`n& {`n" + $ScriptBlock.ToString() + "`n} @args")
    foreach ($a in $ArgumentList) { [void]$ps.AddArgument($a) }

    $frames = '|', '/', '-', '\'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $cursor = $null
    try { $cursor = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}

    $handle = $ps.BeginInvoke()
    $i = 0
    $msg = $null
    try {
        while ($true) {
            while ($sync.Log.TryDequeue([ref]$msg)) { Write-StatusLine ''; Write-Host $msg }
            if ($handle.IsCompleted) { break }
            $pct = if ($sync.Percent -ge 0) { ' ({0}%)' -f [int]$sync.Percent } else { '' }
            Write-StatusLine ("{0} {1} - still working, {2:mm\:ss} elapsed{3}  {4}" -f $frames[$i % 4], $Activity, $sw.Elapsed, $pct, $sync.Status)
            Start-Sleep -Milliseconds 150
            $i++
        }
        try { $out = $ps.EndInvoke($handle) }
        catch {
            $ex = $_.Exception
            while ($ex.InnerException) { $ex = $ex.InnerException }
            throw $ex.Message
        }
    } finally {
        if (-not $handle.IsCompleted) { $ps.Stop() }   # Ctrl+C
        Write-StatusLine ''
        if ($null -ne $cursor) { try { [Console]::CursorVisible = $cursor } catch {} }
        $ps.Dispose()
        $rs.Dispose()
    }
    Write-Host ("{0} - done ({1:mm\:ss})" -f $Activity, $sw.Elapsed) -ForegroundColor DarkGray
    foreach ($o in $out) { $o }
}

function Format-Bytes([double]$B) {
    if ($B -ge 1GB) { '{0:N2} GB' -f ($B / 1GB) }
    elseif ($B -ge 1MB) { '{0:N1} MB' -f ($B / 1MB) }
    elseif ($B -ge 1KB) { '{0:N0} KB' -f ($B / 1KB) }
    else { '{0:N0} B' -f $B }
}

function Get-DesktopPath([string]$FileName) {
    Join-Path ([Environment]::GetFolderPath('Desktop')) $FileName
}

# "1,3,5-7" -> 1,3,5,6,7 (bounded to 1..Max)
function ConvertFrom-Selection {
    param([string]$Text, [int]$Max)
    $set = New-Object 'System.Collections.Generic.SortedSet[int]'
    foreach ($part in ($Text -split '[,\s]+' | Where-Object { $_ })) {
        if ($part -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $a, $b = $b, $a }
            foreach ($n in $a..$b) { if ($n -ge 1 -and $n -le $Max) { [void]$set.Add($n) } }
        }
        elseif ($part -match '^\d+$') {
            $n = [int]$part
            if ($n -ge 1 -and $n -le $Max) { [void]$set.Add($n) }
        }
        else { throw "Invalid selection: '$part'" }
    }
    return , @($set)
}

#endregion

#region ---------- System info ----------

function Get-PendingRebootReasons {
    $r = @()
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        $r += 'Component servicing'
    }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
        $r += 'Windows Update'
    }
    $active  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction SilentlyContinue).ComputerName
    $pending = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -ErrorAction SilentlyContinue).ComputerName
    if ($active -and $pending -and $active -ne $pending) { $r += 'Computer rename' }

    $pfro = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($pfro -and $pfro.PendingFileRenameOperations) { $r += 'Pending file renames (often harmless)' }
    return , @($r)
}

function Write-PendingReboot {
    $r = Get-PendingRebootReasons
    if ($r.Count) { Write-Host ("Reboot pending: {0}" -f ($r -join ', ')) -ForegroundColor Yellow }
    else { Write-Host 'Reboot pending: No' -ForegroundColor Green }
}

function Get-BatteryInfo {
    $w = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $w) { return $null }

    $design = $null; $full = $null
    try { $design = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity } catch {}
    try { $full = (Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity } catch {}

    [pscustomobject]@{
        Charge = $w.EstimatedChargeRemaining
        OnAC   = ($w.BatteryStatus -in 2, 3, 6, 7, 8, 9)
        Design = $design
        Full   = $full
        Health = if ($design -and $full) { [math]::Round(100 * $full / $design, 0) } else { $null }
    }
}

function Write-BatteryLine {
    $b = Get-BatteryInfo
    if (-not $b) { Write-Host 'Battery    : none'; return }
    $src = if ($b.OnAC) { 'plugged in' } else { 'on battery' }
    $hl  = if ($null -ne $b.Health) { ", health {0}% ({1:N0} / {2:N0} mWh)" -f $b.Health, $b.Full, $b.Design } else { '' }
    Write-Host ("Battery    : {0}% {1}{2}" -f $b.Charge, $src, $hl)
}

function Show-SystemSummary {
    Clear-Host
    Write-Section 'System summary'

    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $up = (Get-Date) - $os.LastBootUpTime

    Write-Host ("Computer   : {0}" -f $env:COMPUTERNAME)
    Write-Host ("User       : {0}\{1}  (admin: {2})" -f $env:USERDOMAIN, $env:USERNAME, (Test-IsAdmin))
    Write-Host ("OS         : {0} {1} (build {2}.{3})" -f $os.Caption, $cv.DisplayVersion, $os.BuildNumber, $cv.UBR)
    Write-Host ("Last boot  : {0:yyyy-MM-dd HH:mm}  (uptime {1}d {2}h {3}m)" -f $os.LastBootUpTime, $up.Days, $up.Hours, $up.Minutes)
    Write-Host ("Memory     : {0} free of {1}" -f (Format-Bytes ($os.FreePhysicalMemory * 1KB)), (Format-Bytes ($os.TotalVisibleMemorySize * 1KB)))

    $scheme = (& powercfg /getactivescheme | Out-String)
    if ($scheme -match '\(([^)]+)\)') { Write-Host ("Power plan : {0}" -f $Matches[1]) }

    Write-BatteryLine
    Write-PendingReboot

    Write-Section 'Disks'
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
        $pct = if ($_.Size) { 100 * $_.FreeSpace / $_.Size } else { 0 }
        $color = if ($pct -lt 10) { 'Red' } elseif ($pct -lt 20) { 'Yellow' } else { 'Gray' }
        Write-Host ("{0}  {1,10} free of {2,10}  ({3,4:N0}%)" -f $_.DeviceID, (Format-Bytes $_.FreeSpace), (Format-Bytes $_.Size), $pct) -ForegroundColor $color
    }
}

#endregion

#region ---------- Battery & sleep ----------

function Show-BatteryReport {
    Clear-Host
    Write-Section 'Battery'
    if (-not (Get-BatteryInfo)) { Write-Host 'No battery found.'; return }
    Write-BatteryLine
    Write-Host '(health = full charge capacity vs design capacity)' -ForegroundColor DarkGray

    $path = Get-DesktopPath ("battery-report-{0:yyyyMMdd-HHmm}.html" -f (Get-Date))
    & powercfg /batteryreport /output $path | Out-Null
    if ($LASTEXITCODE -eq 0 -and (Test-Path $path)) {
        Write-Host "Full report saved: $path" -ForegroundColor Green
        if ((Read-Choice 'Open it? (Y/N)' @('Y', 'N')) -eq 'Y') { Invoke-Item $path }
    } else {
        Write-Host "powercfg /batteryreport failed (exit $LASTEXITCODE)." -ForegroundColor Yellow
    }
}

function Get-WakeArmedDevices {
    @(& powercfg /devicequery wake_armed | ForEach-Object { "$_".Trim() } |
        Where-Object { $_ -and $_ -notmatch '^(NONE|INGEN|Ingen)$' })
}

function Show-SleepDiagnostics {
    while ($true) {
        Clear-Host
        $admin = Test-IsAdmin

        Write-Section 'Last wake source'
        & powercfg /lastwake

        Write-Section 'Devices allowed to wake the PC'
        $devs = Get-WakeArmedDevices
        if ($devs.Count) { for ($i = 0; $i -lt $devs.Count; $i++) { Write-Host ("{0,3}. {1}" -f ($i + 1), $devs[$i]) } }
        else { Write-Host '(none)' }

        if ($admin) {
            Write-Section 'Wake timers'
            & powercfg /waketimers
            Write-Section 'Active power requests (what blocks sleep)'
            & powercfg /requests
        } else {
            Write-Host ''
            Write-Host 'Wake timers and power requests need admin (menu option A).' -ForegroundColor Yellow
        }

        Write-Host ''
        Write-Host 'D = stop a device from waking the PC (admin)'
        Write-Host 'S = generate sleep study report (Modern Standby, admin)'
        Write-Host 'R = refresh   B = back'
        $c = Read-Choice 'Choice' @('D', 'S', 'R', 'B', '')

        try {
            switch ($c) {
                'D' {
                    Assert-Admin
                    if (-not $devs.Count) { throw 'No wake-armed devices.' }
                    $n = Read-Host ("Device number (1-{0})" -f $devs.Count)
                    if ($n -notmatch '^\d+$' -or [int]$n -lt 1 -or [int]$n -gt $devs.Count) { throw "Invalid number: '$n'" }
                    $name = $devs[[int]$n - 1]
                    & powercfg /devicedisablewake "$name"
                    if ($LASTEXITCODE -ne 0) { throw "powercfg failed (exit $LASTEXITCODE)" }
                    Write-Host "Wake disabled for: $name" -ForegroundColor Green
                    Write-Host ("Undo with: powercfg /deviceenablewake `"{0}`"" -f $name) -ForegroundColor DarkGray
                    Wait-Enter
                }
                'S' {
                    Assert-Admin
                    $path = Get-DesktopPath ("sleepstudy-{0:yyyyMMdd-HHmm}.html" -f (Get-Date))
                    & powercfg /sleepstudy /output $path | Out-Null
                    if ($LASTEXITCODE -eq 0 -and (Test-Path $path)) {
                        Write-Host "Saved: $path" -ForegroundColor Green
                        Invoke-Item $path
                    } else {
                        Write-Host 'Sleep study failed. Only supported on Modern Standby (S0) devices.' -ForegroundColor Yellow
                    }
                    Wait-Enter
                }
                'R' { }
                default { return }
            }
        } catch {
            Write-Host $_.Exception.Message -ForegroundColor Yellow
            Wait-Enter
        }
    }
}

#endregion

#region ---------- Disk cleanup ----------

function Get-SystemDriveFree { ([IO.DriveInfo]::new($env:SystemDrive)).AvailableFreeSpace }

function Get-FolderSize([string]$Path) {
    [long](Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum
}

function Clear-Folder {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Host "$Label : not found"; return }
    $r = Invoke-WithSpinner -Activity "Cleaning $Label" -Functions 'Get-FolderSize' -ArgumentList $Path -ScriptBlock {
        param($p)
        SetStatus 'measuring'
        $before = Get-FolderSize $p
        $items = @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue)
        for ($i = 0; $i -lt $items.Count; $i++) {
            if ($i % 25 -eq 0) { SetStatus ("deleting {0}/{1}" -f $i, $items.Count) (100 * $i / $items.Count) }
            Remove-Item -LiteralPath $items[$i].FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        SetStatus 'measuring'
        [pscustomobject]@{ Before = $before; After = (Get-FolderSize $p) }
    }
    $before = $r.Before; $after = $r.After
    Write-Host ("{0,-16} freed {1,10}   ({2} left, in use)" -f $Label, (Format-Bytes ($before - $after)), (Format-Bytes $after))
}

function Clear-RecycleBinAll {
    if (-not ('Win32.RecycleBin' -as [type])) {
        Add-Type -Namespace Win32 -Name RecycleBin -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int SHEmptyRecycleBin(IntPtr hwnd, string pszRootPath, uint dwFlags);
'@
    }
    # 7 = no confirmation | no progress UI | no sound
    $hr = [Win32.RecycleBin]::SHEmptyRecycleBin([IntPtr]::Zero, $null, 7)
    if ($hr -eq 0) { Write-Host 'Recycle Bin      emptied' }
    else { Write-Host 'Recycle Bin      already empty' }
}

function Invoke-CleanupStep {
    param([scriptblock]$Action)
    $f0 = Get-SystemDriveFree
    try { & $Action } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow }
    $f1 = Get-SystemDriveFree
    Write-Host ''
    Write-Host ("{0} free: {1}  (+{2})" -f $env:SystemDrive, (Format-Bytes $f1), (Format-Bytes ([math]::Max(0, $f1 - $f0)))) -ForegroundColor Green
}

function Show-CleanupMenu {
    while ($true) {
        Clear-Host
        Write-Section 'Disk cleanup'
        Write-Host ("{0} free: {1}" -f $env:SystemDrive, (Format-Bytes (Get-SystemDriveFree))) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host ' 1. User temp (%TEMP%)'
        Write-Host ' 2. Windows temp (admin)'
        Write-Host ' 3. Empty Recycle Bin'
        Write-Host ' 4. Delivery Optimization cache (admin)'
        Write-Host ' 5. Component store cleanup - DISM (admin, slow)'
        Write-Host ' 6. Open Windows Disk Cleanup (cleanmgr)'
        Write-Host ' A. Quick: 1 + 2 + 3'
        Write-Host ' B. Back'
        $c = Read-Choice 'Choice' @('1', '2', '3', '4', '5', '6', 'A', 'B', '')

        switch ($c) {
            '1' { Invoke-CleanupStep { Clear-Folder $env:TEMP 'User temp' } }
            '2' { Invoke-CleanupStep { Assert-Admin; Clear-Folder (Join-Path $env:windir 'Temp') 'Windows temp' } }
            '3' { Invoke-CleanupStep { Clear-RecycleBinAll } }
            '4' {
                Invoke-CleanupStep {
                    Assert-Admin
                    if (-not (Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)) {
                        throw 'Delete-DeliveryOptimizationCache not available in this PowerShell. Try Windows PowerShell 5.1.'
                    }
                    Delete-DeliveryOptimizationCache -Force
                    Write-Host 'Delivery Optimization cache cleared.'
                }
            }
            '5' {
                Invoke-CleanupStep {
                    Assert-Admin
                    & Dism.exe /Online /Cleanup-Image /StartComponentCleanup
                    if ($LASTEXITCODE -ne 0) { throw "DISM exit code $LASTEXITCODE" }
                }
            }
            '6' { Start-Process cleanmgr.exe -ArgumentList "/d $($env:SystemDrive.TrimEnd(':'))" }
            'A' {
                Invoke-CleanupStep {
                    Clear-Folder $env:TEMP 'User temp'
                    if (Test-IsAdmin) { Clear-Folder (Join-Path $env:windir 'Temp') 'Windows temp' }
                    else { Write-Host 'Windows temp     skipped (needs admin)' -ForegroundColor Yellow }
                    Clear-RecycleBinAll
                }
            }
            default { return }
        }
        Wait-Enter
    }
}

#endregion

#region ---------- Power settings ----------

$LidMap = [ordered]@{ 0 = 'Do nothing'; 1 = 'Sleep'; 2 = 'Hibernate'; 3 = 'Shut down' }

function Get-PowerVal {
    param([string]$Sub, [string]$Setting)

    $raw  = & powercfg /qh SCHEME_CURRENT $Sub $Setting 2>&1 | Out-String
    $hits = [regex]::Matches($raw, ':\s*0x([0-9a-fA-F]+)\s*(\r?\n|$)')

    if ($hits.Count -lt 2) { return [pscustomobject]@{ OK = $false; Raw = $raw } }

    $ac = [Convert]::ToInt32($hits[$hits.Count - 2].Groups[1].Value, 16)
    $dc = [Convert]::ToInt32($hits[$hits.Count - 1].Groups[1].Value, 16)
    [pscustomobject]@{ OK = $true; AC = $ac; DC = $dc; Raw = $raw }
}

function Set-PowerVal {
    param([string]$Sub, [string]$Setting, [int]$Value, [switch]$AC, [switch]$DC)
    if ($AC) {
        & powercfg /setacvalueindex SCHEME_CURRENT $Sub $Setting $Value
        if ($LASTEXITCODE -ne 0) { throw "powercfg setacvalueindex failed ($LASTEXITCODE)" }
    }
    if ($DC) {
        & powercfg /setdcvalueindex SCHEME_CURRENT $Sub $Setting $Value
        if ($LASTEXITCODE -ne 0) { throw "powercfg setdcvalueindex failed ($LASTEXITCODE)" }
    }
    & powercfg /setactive SCHEME_CURRENT
}

function Test-HibernateEnabled {
    $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue
    return ($null -ne $v -and $v.HibernateEnabled -eq 1)
}

function Show-PowerStatus {
    Write-Section 'Lid close action'
    $lid = Get-PowerVal -Sub 'SUB_BUTTONS' -Setting 'LIDACTION'
    if ($lid.OK) {
        Write-Host ("Plugged in : {0}" -f $LidMap[$lid.AC])
        Write-Host ("On battery : {0}" -f $LidMap[$lid.DC])
    } else {
        Write-Host 'Could not parse. Raw powercfg output:' -ForegroundColor Yellow
        Write-Host $lid.Raw
    }

    Write-Section 'Require sign-in on wake'
    $lock = Get-PowerVal -Sub 'SUB_NONE' -Setting 'CONSOLELOCK'
    if ($lock.OK) {
        Write-Host ("Plugged in : {0}" -f [bool]$lock.AC)
        Write-Host ("On battery : {0}" -f [bool]$lock.DC)
    } else {
        Write-Host 'Could not parse. Raw powercfg output:' -ForegroundColor Yellow
        Write-Host $lock.Raw
    }

    # Modern Standby laptops often use this value instead
    $reg = Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name DelayLockInterval -ErrorAction SilentlyContinue
    if ($null -ne $reg) {
        $v = $reg.DelayLockInterval
        $txt = if ($v -eq 0) { 'Every time (immediately)' } elseif ($v -eq -1) { 'Never' } else { "After $v seconds" }
        Write-Host ("Settings app 'require sign-in' : {0}" -f $txt)
    }
}

function Set-LidAction {
    Clear-Host
    Show-PowerStatus
    Write-Section 'New lid close action'
    foreach ($k in $LidMap.Keys) { Write-Host (" {0}. {1}" -f $k, $LidMap[$k]) }
    Write-Host ' B. Back'
    $act = Read-Choice 'Action' @('0', '1', '2', '3', 'B')
    if ($act -eq 'B') { return }

    if ($act -eq '2' -and -not (Test-HibernateEnabled)) {
        Write-Host "Hibernate appears to be disabled. Enable it with 'powercfg /hibernate on' (admin)." -ForegroundColor Yellow
        if ((Read-Choice 'Continue anyway? (Y/N)' @('Y', 'N')) -eq 'N') { return }
    }

    Write-Host ''
    Write-Host ' 1. Plugged in'
    Write-Host ' 2. On battery'
    Write-Host ' 3. Both'
    $scope = Read-Choice 'Apply to' @('1', '2', '3', 'B')
    if ($scope -eq 'B') { return }

    Set-PowerVal -Sub 'SUB_BUTTONS' -Setting 'LIDACTION' -Value ([int]$act) `
        -AC:($scope -in '1', '3') -DC:($scope -in '2', '3')

    Write-Host ("Lid action set to '{0}'." -f $LidMap[[int]$act]) -ForegroundColor Green
    Show-PowerStatus
}

function Set-SignInOnWake {
    Clear-Host
    Show-PowerStatus
    Write-Section 'Require sign-in on wake'
    Write-Host ' 1. Require sign-in'
    Write-Host ' 2. Do not require sign-in'
    Write-Host ' B. Back'
    $c = Read-Choice 'Choice' @('1', '2', 'B')
    if ($c -eq 'B') { return }

    $require = ($c -eq '1')
    Set-PowerVal -Sub 'SUB_NONE' -Setting 'CONSOLELOCK' -Value ([int]$require) -AC -DC

    # Modern Standby: Settings app uses DelayLockInterval (0 = every time, -1 = never)
    $val = if ($require) { 0 } else { -1 }
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name DelayLockInterval -Value ([int]$val) -Type DWord

    Write-Host ("Sign-in on wake: {0}" -f $(if ($require) { 'required' } else { 'not required' })) -ForegroundColor Green
    Show-PowerStatus
}

#endregion

#region ---------- Restore point ----------

function Get-RestorePoints {
    @(Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction SilentlyContinue)
}

function Enable-SystemProtection {
    # Turns on System Protection (restore points) for the system drive. Returns $true on success.
    if ((Read-Choice ("System Protection looks off for {0}. Turn it on and retry? (Y/N)" -f $env:SystemDrive) @('Y', 'N')) -eq 'N') { return $false }
    try {
        $r = Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName Enable -Arguments @{ Drive = "$env:SystemDrive\" }
        if ($r.ReturnValue -ne 0) { throw "Enable returned $($r.ReturnValue)" }
        Write-Host ("System Protection enabled for {0}." -f $env:SystemDrive) -ForegroundColor Green
        return $true
    } catch {
        Write-Host ("Could not enable System Protection: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return $false
    }
}

function New-RestorePoint {
    param([string]$Description = 'Maintenance.ps1: before winget upgrade', [switch]$NoRetry)
    if (-not (Test-IsAdmin)) {
        Write-Host 'Restore point needs admin (menu option A).' -ForegroundColor Yellow
        return $false
    }

    try {
        $before = (Get-RestorePoints).Count
        $r = Invoke-WithSpinner -Activity 'Creating restore point' -ArgumentList $Description -ScriptBlock {
            param($d)
            Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments @{
                Description      = $d
                RestorePointType = [uint32]12   # MODIFY_SETTINGS
                EventType        = [uint32]100  # BEGIN_SYSTEM_CHANGE
            }
        }
        $points = Get-RestorePoints
    } catch {
        Write-Host ("Restore point failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        return $false
    }

    if ($r.ReturnValue -ne 0) {
        Write-Host ("Restore point failed (code {0})." -f $r.ReturnValue) -ForegroundColor Yellow
        if (-not $NoRetry -and (Enable-SystemProtection)) { return (New-RestorePoint -Description $Description -NoRetry) }
        return $false
    }
    if ($points.Count -gt $before) {
        Write-Host 'Restore point created.' -ForegroundColor Green
        return $true
    }

    # Windows throttles to one restore point per 24h by default
    $latest = $points | Sort-Object SequenceNumber | Select-Object -Last 1
    if ($latest) {
        $t = [Management.ManagementDateTimeConverter]::ToDateTime($latest.CreationTime)
        if ($t -gt (Get-Date).AddHours(-24)) {
            Write-Host ("Not created (24h throttle). Recent one exists: '{0}' at {1:yyyy-MM-dd HH:mm}." -f $latest.Description, $t) -ForegroundColor Yellow
            return $true
        }
    }
    Write-Host 'Restore point not created.' -ForegroundColor Yellow
    if (-not $NoRetry -and (Enable-SystemProtection)) { return (New-RestorePoint -Description $Description -NoRetry) }
    return $false
}

function Confirm-PreUpgradeRestorePoint {
    if ((Read-Choice 'Create a restore point first? (Y/N)' @('Y', 'N')) -eq 'N') { return $true }
    if (New-RestorePoint) { return $true }
    return ((Read-Choice 'Continue without restore point? (Y/N)' @('Y', 'N')) -eq 'Y')
}

#endregion

#region ---------- winget ----------

function Assert-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget not found. Install/update "App Installer" from Microsoft Store.'
    }
}

function Get-WingetUpgrades {
    param([switch]$IncludeUnknown)
    Assert-Winget

    $wgArgs = @('upgrade', '--accept-source-agreements')
    if ($IncludeUnknown) { $wgArgs += '--include-unknown' }

    $prevEnc = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    try {
        # Strip spinner/progress junk: keep only text after the last carriage return
        $lines = @(Invoke-WithSpinner -Activity 'Checking winget for updates' -ArgumentList (, $wgArgs) -ScriptBlock {
            param($a)
            & winget @a | ForEach-Object { ("$_" -split "`r")[-1] }
        })
    } finally {
        [Console]::OutputEncoding = $prevEnc
    }

    # Parse every table (normal + "require explicit targeting") by header column positions
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

function Invoke-WingetReinstall {
    # Uninstall + fresh install. Results go into $State (no pipeline output, so winget output stays visible).
    param([object]$Package, [hashtable]$State)
    $id  = $Package.Id
    $src = if ($Package.Source) { @('--source', $Package.Source) } else { @() }

    Write-Host ''
    Write-Host ">>> Uninstalling $id" -ForegroundColor Cyan
    & winget uninstall --id $id --exact --silent --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Uninstall failed (exit $LASTEXITCODE). Not reinstalling; app left as it was." -ForegroundColor Yellow
        $State.Failed += $Package
        return
    }

    for ($try = 1; $try -le 2; $try++) {
        Write-Host ">>> Installing $id (attempt $try)" -ForegroundColor Cyan
        & winget install --id $id --exact @src --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$id reinstalled." -ForegroundColor Green
            $State.Reinstalled += $id
            return
        }
        Write-Host "Install failed (exit $LASTEXITCODE)." -ForegroundColor Yellow
    }

    Write-Host "!! $id is now UNINSTALLED. Reinstall manually: winget install --id $id --exact" -ForegroundColor Red
    $State.Lost += $id
}

function Confirm-WingetReinstall {
    # Offers uninstall + reinstall for packages that failed to upgrade.
    param([object[]]$Packages, [switch]$IncludeUnknown, [hashtable]$State)
    if (-not $State) { $State = @{} }
    $State.Failed = @($Packages); $State.Reinstalled = @(); $State.Lost = @()
    if (-not $Packages.Count) { return }

    Write-Host ''
    Write-Host 'Not upgraded:' -ForegroundColor Yellow
    for ($n = 0; $n -lt $Packages.Count; $n++) {
        $p = $Packages[$n]
        Write-Host ("{0,3}. {1}  [{2}]  {3} -> {4}" -f ($n + 1), $p.Name, $p.Id, $p.Version, $p.Available)
    }
    Write-Host 'Reinstall = uninstall, then fresh install of the latest version.' -ForegroundColor DarkGray
    Write-Host 'Settings/data are usually kept, but not guaranteed. Close the apps first.' -ForegroundColor DarkGray
    $in = (Read-Host 'Reinstall which? (numbers, A = all, Enter = skip)').Trim()
    if (-not $in) { return }

    try {
        $sel = if ($in -match '^[Aa]$') { 1..$Packages.Count } else { ConvertFrom-Selection -Text $in -Max $Packages.Count }
    } catch { Write-Host $_.Exception.Message -ForegroundColor Yellow; return }

    $State.Failed = @($Packages | Where-Object { $sel -notcontains ([array]::IndexOf($Packages, $_) + 1) })
    $k = 0
    foreach ($n in $sel) {
        $k++
        Write-Host ''
        Write-Host ("=== Reinstall {0}/{1} ===" -f $k, @($sel).Count) -ForegroundColor Cyan
        Invoke-WingetReinstall -Package $Packages[$n - 1] -State $State
    }

    # Reinstalled but still listed = winget can't read the app's version correctly
    if ($State.Reinstalled.Count) {
        $still = @(Get-WingetUpgrades -IncludeUnknown:$IncludeUnknown | Where-Object { $State.Reinstalled -contains $_.Id })
        foreach ($p in $still) {
            Write-Host ("{0} still shows an update after reinstall (broken version reporting). Hide it with: winget pin add --id {0}" -f $p.Id) -ForegroundColor Yellow
        }
    }
}

function Invoke-WingetUpgrade {
    # Upgrades the given packages (or --all), retries leftovers one by one, then offers reinstall for failures.
    # Results in $State: Failed (package objects), Reinstalled (ids), Lost (ids uninstalled but not reinstalled).
    param([object[]]$Packages, [switch]$All, [switch]$IncludeUnknown, [hashtable]$State)
    Assert-Winget
    if (-not $State) { $State = @{} }
    # --silent: no installer wizards (Next / I agree / Install)
    $common = @('--silent', '--accept-package-agreements', '--accept-source-agreements')

    if ($All) {
        $a = @('upgrade', '--all') + $common
        if ($IncludeUnknown) { $a += '--include-unknown' }
        & winget @a
        # Leftovers: explicit-targeting packages, or ones that failed in the batch
        $Packages = @(Get-WingetUpgrades -IncludeUnknown:$IncludeUnknown)
        if ($Packages.Count) {
            Write-Host ''
            Write-Host ("{0} package(s) left after --all, trying one by one..." -f $Packages.Count) -ForegroundColor DarkGray
        }
    }

    for ($n = 0; $n -lt $Packages.Count; $n++) {
        $p = $Packages[$n]
        Write-Host ''
        Write-Host (">>> [{0}/{1}] Upgrading {2}" -f ($n + 1), $Packages.Count, $p.Id) -ForegroundColor Cyan
        & winget upgrade --id $p.Id --exact @common
    }

    # Judge success by what's still listed, not exit codes (some installers return non-zero on success)
    $failed = @()
    if ($Packages.Count) {
        $ids = @($Packages | ForEach-Object Id)
        $failed = @(Get-WingetUpgrades -IncludeUnknown:$IncludeUnknown | Where-Object { $ids -contains $_.Id })
    }

    Write-Host ''
    if ($failed.Count) {
        Confirm-WingetReinstall -Packages $failed -IncludeUnknown:$IncludeUnknown -State $State
    } else {
        $State.Failed = @(); $State.Reinstalled = @(); $State.Lost = @()
        Write-Host 'All packages upgraded.' -ForegroundColor Green
    }

    if ($State.Lost.Count) {
        Write-Host ''
        Write-Host ("UNINSTALLED and not reinstalled: {0}" -f ($State.Lost -join ', ')) -ForegroundColor Red
    }
    Write-Host ''
    Write-PendingReboot
}

function Show-UpdateMenu {
    $includeUnknown = $false
    while ($true) {
        Clear-Host
        Write-Section 'winget upgrades'
        Write-Host 'Checking for updates...' -ForegroundColor DarkGray
        $pkgs = @(Get-WingetUpgrades -IncludeUnknown:$includeUnknown)

        if ($pkgs.Count -eq 0) {
            Write-Host 'Everything is up to date.' -ForegroundColor Green
            Write-Host ("(include-unknown: {0})" -f $includeUnknown) -ForegroundColor DarkGray
            if ((Read-Choice 'U = toggle include-unknown, B = back' @('U', 'B')) -eq 'U') {
                $includeUnknown = -not $includeUnknown; continue
            }
            return
        }

        Write-Host ''
        Write-Host ("{0,3}  {1,-38} {2,-18} {3}" -f '#', 'Name', 'Installed', 'Available') -ForegroundColor DarkGray
        for ($n = 0; $n -lt $pkgs.Count; $n++) {
            $p = $pkgs[$n]
            $name = if ($p.Name.Length -gt 38) { $p.Name.Substring(0, 37) + '...' } else { $p.Name }
            Write-Host ("{0,3}. {1,-38} {2,-18} {3}" -f ($n + 1), $name, $p.Version, $p.Available)
        }

        Write-Host ''
        Write-Host 'Numbers (e.g. 1,3,5-7) = upgrade selected'
        Write-Host 'A = upgrade all   X = reinstall (uninstall + install)   R = refresh   B = back'
        Write-Host ("U = toggle include-unknown (now: {0})" -f $includeUnknown)
        $in = (Read-Host 'Choice').Trim()

        switch -Regex ($in) {
            '^[Bb]?$' { return }
            '^[Rr]$'  { break }
            '^[Uu]$'  { $includeUnknown = -not $includeUnknown; break }
            '^[Xx]$'  {
                if (Confirm-PreUpgradeRestorePoint) {
                    Confirm-WingetReinstall -Packages $pkgs -IncludeUnknown:$includeUnknown
                    Wait-Enter
                }
                break
            }
            '^[Aa]$'  {
                if ((Read-Choice ("Upgrade all {0} packages? (Y/N)" -f $pkgs.Count) @('Y', 'N')) -eq 'Y' -and
                    (Confirm-PreUpgradeRestorePoint)) {
                    Invoke-WingetUpgrade -All -IncludeUnknown:$includeUnknown
                    Wait-Enter
                }
                break
            }
            default {
                try {
                    $sel = ConvertFrom-Selection -Text $in -Max $pkgs.Count
                    if ($sel.Count -eq 0) { throw 'Nothing selected.' }
                    $chosen = @($sel | ForEach-Object { $pkgs[$_ - 1] })
                    Write-Host ''
                    Write-Host 'Will upgrade:' -ForegroundColor Cyan
                    $chosen | ForEach-Object { Write-Host "  $($_.Id)" }
                    if ((Read-Choice 'Proceed? (Y/N)' @('Y', 'N')) -eq 'Y' -and (Confirm-PreUpgradeRestorePoint)) {
                        Invoke-WingetUpgrade -Packages $chosen -IncludeUnknown:$includeUnknown
                        Wait-Enter
                    }
                } catch {
                    Write-Host $_.Exception.Message -ForegroundColor Yellow
                    Wait-Enter
                }
            }
        }
    }
}

#endregion

#region ---------- Update literally everything ----------

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action, [System.Collections.IDictionary]$Results, [switch]$NeedsAdmin)
    $script:StepNo++
    $pct = [int](100 * ($script:StepNo - 1) / $script:StepTotal)
    Write-Section ("[{0}/{1}] {2}   (overall {3}%)" -f $script:StepNo, $script:StepTotal, $Name, $pct)
    if ($NeedsAdmin -and -not (Test-IsAdmin)) {
        Write-Host 'Skipped (needs admin).' -ForegroundColor Yellow
        $Results[$Name] = 'Skipped (needs admin)'
        return
    }
    $ctx = @{ Status = 'OK' }
    try { & $Action $ctx }
    catch {
        $ctx.Status = "FAILED: $($_.Exception.Message)"
        Write-Host $ctx.Status -ForegroundColor Red
    }
    $Results[$Name] = $ctx.Status
}

function Update-WingetEverything {
    param($ctx)
    $st = @{}
    Invoke-WingetUpgrade -All -IncludeUnknown -State $st

    $parts = @()
    if ($st.Reinstalled.Count) { $parts += "reinstalled: $($st.Reinstalled -join ', ')" }
    if ($st.Failed.Count)      { $parts += "{0} failed: {1}" -f $st.Failed.Count, (($st.Failed | ForEach-Object Id) -join ', ') }
    if ($st.Lost.Count)        { $parts += "UNINSTALLED: $($st.Lost -join ', ')" }

    if ($st.Lost.Count) { throw ($parts -join '; ') }
    $ctx.Status = if ($parts.Count) { $parts -join '; ' } else { 'All up to date' }
}

function Update-StoreApps {
    param($ctx)
    $r = Get-CimInstance -Namespace 'root/cimv2/mdm/dmmap' -ClassName 'MDM_EnterpriseModernAppManagement_AppManagement01' |
        Invoke-CimMethod -MethodName UpdateScanMethod
    if ($r -and $r.ReturnValue -ne 0) { throw "UpdateScanMethod returned $($r.ReturnValue)" }
    $ctx.Status = 'Update scan triggered (Store installs in background)'
}

function Update-WindowsUpdate {
    param($ctx)
    # All COM work happens in the background runspace; progress is reported via Log/SetStatus.
    $r = Invoke-WithSpinner -Activity 'Windows Update' -ScriptBlock {
        SetStatus 'searching (incl. drivers), can take several minutes'
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found    = $searcher.Search("IsInstalled=0 and IsHidden=0")

        $list = @()
        foreach ($u in $found.Updates) {
            if ($u.InstallationBehavior.CanRequestUserInput) { Log "  skip (interactive): $($u.Title)"; continue }
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            Log "  found: $($u.Title)"
            $list += $u
        }
        $total = $list.Count
        if ($total -eq 0) { return [pscustomobject]@{ Total = 0 } }

        $codes = @{ 0 = 'Not started'; 1 = 'In progress'; 2 = 'Succeeded'; 3 = 'Succeeded with errors'; 4 = 'Failed'; 5 = 'Aborted' }
        $ok = 0; $failed = @(); $reboot = $false

        # Download, one update at a time so progress is visible
        for ($i = 0; $i -lt $total; $i++) {
            $u = $list[$i]
            SetStatus ("downloading {0}/{1}: {2}" -f ($i + 1), $total, $u.Title) (100 * $i / $total)
            if ($u.IsDownloaded) { continue }
            $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($u)
            $d = $session.CreateUpdateDownloader(); $d.Updates = $c
            try { [void]$d.Download() } catch { Log "  download failed: $($u.Title)" }
        }

        # Install, one update at a time
        for ($i = 0; $i -lt $total; $i++) {
            $u = $list[$i]
            SetStatus ("installing {0}/{1}: {2}" -f ($i + 1), $total, $u.Title) (100 * $i / $total)
            if (-not $u.IsDownloaded) { $failed += $u.Title; continue }
            $c = New-Object -ComObject Microsoft.Update.UpdateColl; [void]$c.Add($u)
            $inst = $session.CreateUpdateInstaller(); $inst.Updates = $c
            try {
                $res = $inst.Install()
                if ($res.RebootRequired) { $reboot = $true }
                if ([int]$res.ResultCode -in 2, 3) { $ok++; Log "  installed: $($u.Title)" }
                else { $failed += $u.Title; Log ("  {0}: {1}" -f $codes[[int]$res.ResultCode], $u.Title) }
            } catch {
                $failed += $u.Title; Log "  install error: $($u.Title)"
            }
        }
        SetStatus 'done' 100
        [pscustomobject]@{ Total = $total; Ok = $ok; Failed = $failed; Reboot = $reboot }
    }

    if ($r.Total -eq 0) { $ctx.Status = 'Up to date'; return }
    $ctx.Status = "{0}/{1} installed{2}{3}" -f $r.Ok, $r.Total,
        $(if ($r.Failed.Count) { ", $($r.Failed.Count) failed" } else { '' }),
        $(if ($r.Reboot) { ', reboot required' } else { '' })
    if ($r.Ok -eq 0) { throw $ctx.Status }
}

function Update-Defender {
    param($ctx)
    if (-not (Get-Command Update-MpSignature -ErrorAction SilentlyContinue)) { $ctx.Status = 'Not available'; return }
    Invoke-WithSpinner -Activity 'Updating Defender signatures' -ScriptBlock { Update-MpSignature }
}

function Update-Office {
    param($ctx)
    $c2r = Join-Path $env:CommonProgramFiles 'microsoft shared\ClickToRun\OfficeC2RClient.exe'
    if (-not (Test-Path $c2r)) { $ctx.Status = 'Not installed (Click-to-Run)'; return }
    Start-Process $c2r -ArgumentList '/update user updatepromptuser=false forceappshutdown=false displaylevel=true'
    $ctx.Status = 'Update started (Office updater runs in its own window)'
}

function Update-Wsl {
    param($ctx)
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue) -or
        -not (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss')) { $ctx.Status = 'Not installed'; return }
    $env:WSL_UTF8 = '1'
    & wsl.exe --update
    if ($LASTEXITCODE -ne 0) { throw "wsl --update exit $LASTEXITCODE" }
}

# AzureRM and the classic Azure modules are retired (replaced by Az) and can't be updated from PSGallery.
$RetiredModulePattern = '^(AzureRM(\..+)?|Azure|Azure\.Storage|Azure\.AnalysisServices)$'

function Update-PsModules {
    param($ctx)
    $all = @(Get-InstalledModule -ErrorAction SilentlyContinue)
    if (-not $all.Count) { $ctx.Status = 'None installed from PSGallery'; return }

    $retired = @($all | Where-Object { $_.Name -match $RetiredModulePattern })
    $mods    = @($all | Where-Object { $_.Name -notmatch $RetiredModulePattern })

    $r = Invoke-WithSpinner -Activity 'PowerShell modules' -ArgumentList (, $mods) -ScriptBlock {
        param($mods)
        $failed = @()
        for ($i = 0; $i -lt $mods.Count; $i++) {
            $m = $mods[$i]
            SetStatus ("{0}/{1}: {2}" -f ($i + 1), $mods.Count, $m.Name) (100 * $i / [math]::Max(1, $mods.Count))
            try { Update-Module -Name $m.Name -Force -ErrorAction Stop; Log "  $($m.Name) ok" }
            catch { $failed += [pscustomobject]@{ Name = $m.Name; Error = $_.Exception.Message }; Log "  $($m.Name) failed: $($_.Exception.Message)" }
        }
        [pscustomobject]@{ Failed = $failed }
    }

    $parts = @("$($mods.Count) checked")
    if ($r.Failed.Count) {
        $names = @($r.Failed | ForEach-Object Name)
        $shown = ($names | Select-Object -First 5) -join ', '
        if ($names.Count -gt 5) { $shown += ", +$($names.Count - 5) more" }
        $parts += "$($names.Count) failed: $shown"
    }

    if ($retired.Count) {
        Write-Host ''
        Write-Host ("{0} retired Azure/AzureRM module(s) found. They are no longer updated and conflict with Az." -f $retired.Count) -ForegroundColor Yellow
        if ((Read-Choice 'Uninstall them? (Y/N)' @('Y', 'N')) -eq 'Y') {
            $left = Remove-RetiredModules -Modules $retired
            $parts += if ($left.Count) { "retired: $($retired.Count - $left.Count) removed, $($left.Count) left" } else { "retired: $($retired.Count) removed" }
        } else {
            $parts += "$($retired.Count) retired AzureRM/Azure skipped"
        }
    }
    $ctx.Status = $parts -join '; '
}

function Remove-RetiredModules {
    param([object[]]$Modules)
    $names = @($Modules | ForEach-Object Name)
    $r = Invoke-WithSpinner -Activity 'Removing retired modules' -ArgumentList (, $names) -ScriptBlock {
        param($names)
        $left = @($names)
        # Several passes: dependencies block removal until their dependents are gone
        for ($pass = 1; $pass -le 3 -and $left.Count; $pass++) {
            $next = @()
            for ($i = 0; $i -lt $left.Count; $i++) {
                SetStatus ("pass {0}: {1}/{2} {3}" -f $pass, ($i + 1), $left.Count, $left[$i]) (100 * $i / $left.Count)
                try { Uninstall-Module -Name $left[$i] -AllVersions -Force -ErrorAction Stop; Log "  removed $($left[$i])" }
                catch { $next += $left[$i] }
            }
            $left = $next
        }
        , $left
    }
    $left = @($r)
    if ($left.Count) {
        Write-Host ("Could not remove: {0}" -f ($left -join ', ')) -ForegroundColor Yellow
        Write-Host 'Close other PowerShell windows (modules in use) and try again.' -ForegroundColor DarkGray
    }
    return , $left
}

function Invoke-UpdateEverything {
    Clear-Host
    Write-Section 'Update literally everything'
    Write-Host 'Restore point -> winget (all, incl. unknown + explicit) -> Microsoft Store -> Windows Update (incl. drivers)'
    Write-Host '-> Defender signatures -> Microsoft 365 -> WSL -> PowerShell modules'
    Write-Host ''

    if (-not (Test-IsAdmin)) {
        Write-Host 'Not admin: restore point, Store, Windows Update and Defender will be skipped.' -ForegroundColor Yellow
        $c = Read-Choice 'A = relaunch as admin, C = continue anyway, B = back' @('A', 'C', 'B')
        if ($c -eq 'A') { Restart-Elevated; return }
        if ($c -eq 'B') { return }
    } elseif ((Read-Choice 'Start? Apps may close/restart during updates. (Y/N)' @('Y', 'N')) -eq 'N') { return }

    $results = [ordered]@{}
    $t0 = Get-Date
    $script:StepNo = 0
    $script:StepTotal = 7

    Write-Section 'Restore point'
    if (Test-IsAdmin) {
        if (New-RestorePoint) { $results['Restore point'] = 'OK' }
        else {
            $results['Restore point'] = 'Not created'
            if ((Read-Choice 'Continue without restore point? (Y/N)' @('Y', 'N')) -eq 'N') { return }
        }
    } else { $results['Restore point'] = 'Skipped (needs admin)'; Write-Host 'Skipped (needs admin).' -ForegroundColor Yellow }

    Invoke-Step 'winget'                  ${function:Update-WingetEverything} $results
    Invoke-Step 'Microsoft Store'         ${function:Update-StoreApps}        $results -NeedsAdmin
    Invoke-Step 'Windows Update'          ${function:Update-WindowsUpdate}    $results -NeedsAdmin
    Invoke-Step 'Defender signatures'     ${function:Update-Defender}         $results -NeedsAdmin
    Invoke-Step 'Microsoft 365'           ${function:Update-Office}           $results
    Invoke-Step 'WSL'                     ${function:Update-Wsl}              $results
    Invoke-Step 'PowerShell modules'      ${function:Update-PsModules}        $results

    Write-Section ("Summary ({0:mm\:ss})" -f ((Get-Date) - $t0))
    foreach ($k in $results.Keys) {
        $v = $results[$k]
        $color = if ($v -like 'FAILED*') { 'Red' } elseif ($v -like 'Skipped*' -or $v -like '*left:*' -or $v -like 'Not created') { 'Yellow' } else { 'Green' }
        Write-Host ("{0,-20} {1}" -f $k, $v) -ForegroundColor $color
    }
    Write-Host ''
    Write-PendingReboot
    $rr = Get-PendingRebootReasons
    if (@($rr | Where-Object { $_ -notlike 'Pending file renames*' }).Count) {
        if ((Read-Choice 'Reboot now? (Y/N)' @('Y', 'N')) -eq 'Y') { Restart-Computer -Force }
    }
}

#endregion

#region ---------- Misc ----------

function Restart-Elevated {
    if (Test-IsAdmin) { Write-Host 'Already running as administrator.' -ForegroundColor Green; Wait-Enter; return }
    if (-not $env:MAINT_SELF) { Write-Host 'Launch via Maintenance.cmd to relaunch elevated.' -ForegroundColor Yellow; Wait-Enter; return }
    Start-Process -FilePath $env:MAINT_SELF -ArgumentList 'elevated' -Verb RunAs
    exit 0
}

#endregion

#region ---------- Main menu ----------

while ($true) {
    Clear-Host
    Write-Host '=== Maintenance ===' -ForegroundColor Cyan
    Write-Host ("Admin: {0}" -f $(if (Test-IsAdmin) { 'Yes' } else { 'No' })) -ForegroundColor DarkGray
    $pr = Get-PendingRebootReasons
    if ($pr.Count) { Write-Host ("Reboot pending: {0}" -f ($pr -join ', ')) -ForegroundColor Yellow }
    Write-Host ''
    Write-Host ' U. Update literally everything' -ForegroundColor Green
    Write-Host ' 1. Updates (winget)'
    Write-Host ' 2. System summary'
    Write-Host ' 3. Disk cleanup'
    Write-Host ' 4. Battery report'
    Write-Host ' 5. Sleep diagnostics'
    Write-Host ' 6. Show lid / sign-in settings'
    Write-Host ' 7. Change lid close action'
    Write-Host ' 8. Change sign-in on wake'
    Write-Host ' 9. Open Windows Update'
    Write-Host ' A. Relaunch as administrator'
    Write-Host ' Q. Quit'
    Write-Host ''
    $choice = Read-Choice 'Choice' @('U', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'Q')

    try {
        switch ($choice) {
            'U' { Invoke-UpdateEverything; Wait-Enter }
            '1' { Show-UpdateMenu }
            '2' { Show-SystemSummary; Wait-Enter }
            '3' { Show-CleanupMenu }
            '4' { Show-BatteryReport; Wait-Enter }
            '5' { Show-SleepDiagnostics }
            '6' { Clear-Host; Show-PowerStatus; Wait-Enter }
            '7' { Set-LidAction; Wait-Enter }
            '8' { Set-SignInOnWake; Wait-Enter }
            '9' { Start-Process 'ms-settings:windowsupdate' }
            'A' { Restart-Elevated }
            'Q' { exit 0 }
        }
    } catch {
        Write-Host ("Error: {0}" -f $_.Exception.Message) -ForegroundColor Red
        Wait-Enter
    }
}

#endregion