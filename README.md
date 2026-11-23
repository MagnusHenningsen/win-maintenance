# PC Maintenance

Keeps a Windows PC up to date and tidy, in plain language, in English or Norwegian.

## Getting it

1. Download **PC-Maintenance-&lt;version&gt;.zip** from the latest [GitHub release](https://github.com/MagnusHenningsen/win-maintenance/releases/latest).
2. Unzip it and double-click **PC Maintenance.exe**.
3. Choose **Install**. It copies itself to `%LOCALAPPDATA%\Programs\PC Maintenance` (no administrator rights needed), adds **PC Maintenance** to the Start menu and to *Settings > Apps* (where it can be uninstalled).

Installed copies check GitHub for a newer release when they start, download it and offer to restart.
Git clones update with `git pull` instead and also get a Start menu entry.

The exe isn't code-signed yet, so Windows SmartScreen may warn the first time ("More info" > "Run anyway"). See *Signing* below.

## What it does

- **Update everything**: apps (winget), Windows Update and drivers, Microsoft Store apps, Defender, Office, WSL and PowerShell modules, with a restore point first.
- **PC checkup** on the home screen: disk space, restart, Windows updates, virus protection, firewall, drive encryption, battery, app updates, each with a fix button.
- **Fix a problem**: Internet problems, Printer problems, Camera and microphone, Slow startup (startup apps), Sleep and wake, Battery health.
- **Clean and update**: App updates, Free up space, Largest files.
- **Settings and safety**: Automatic maintenance (weekly scheduled run with a notification), Restore point, Lid and sign-in.
- **Information**: About this PC (copy the details for IT), History (everything the app did), Windows Update.

Light/dark mode follows Windows (toggle at the top); the language follows Windows (Norsk/English button at the top).
Some features need administrator rights: click **Run as administrator** at the top.

`Maintain.cmd` is the original keyboard-driven console version for power users.

## Development

| Path | What it is |
| --- | --- |
| `MaintainGui.ps1` | The WPF app (Windows PowerShell 5.1): engine, task page, core pages, install/update. `-StartPage <Name>` opens a page, `-Auto` runs automatic maintenance without a window, `-Uninstall` removes the installed copy. |
| `features\*.ps1` | One file per tool page. Each calls `Add-Strings` (Norwegian text) and `Register-Feature` (tile, page XAML, handlers, background functions). See the comment above `$Features` in `MaintainGui.ps1`. |
| `lang\nb.ps1` | Norwegian text for the core app, keyed by the English text. |
| `launcher\Launcher.cs` | Source of `PC Maintenance.exe`, which starts the script without a console window. |
| `build.ps1` | Builds the exe and icons with the C# compiler that ships with Windows. `-Package` makes the release zip in `dist\`, `-Release` publishes it with `gh`, `-CertThumbprint` signs the exe. |

Rules of thumb:

- Write UI text in English and wrap it: `T 'Text'` in code, `$(X 'Text')` in XAML. Add the Norwegian to `lang\nb.ps1` (or the feature's own `Add-Strings`).
- Save `.ps1` files as **UTF-8 with BOM**, or Windows PowerShell garbles æ, ø and å.
- Colors come from the theme (`{DynamicResource Text}`, `Set-Themed $el Foreground Good`), never hex values.

Testing a page without changing your settings: set `MAINT_TEST_LANG` (`en`/`nb`) and `MAINT_TEST_THEME` (`Light`/`Dark`) and run `MaintainGui.ps1 -NoUpdate -StartPage Printer`.

### Publishing a release

1. Bump `$AppVersion` in `MaintainGui.ps1` (and the version in `launcher\Launcher.cs` if the exe changed).
2. Commit and push.
3. `powershell -ExecutionPolicy Bypass -File build.ps1 -Release` builds `dist\PC-Maintenance-<version>.zip` and creates GitHub release `v<version>`. Installed copies pick it up the next time they start.

### Signing

A code-signing certificate (from the company or a CA) removes the SmartScreen warning: `build.ps1 -CertThumbprint <thumbprint>` signs the exe with a timestamp.
