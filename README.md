# PC Maintenance

Keeps a Windows PC up to date and tidy.

## For everyone: `PC Maintenance.exe`

Double-click **PC Maintenance.exe**. It opens a window with:

- **Update everything**: apps (winget), Windows Update and drivers, Microsoft Store apps, Defender, Office, WSL and PowerShell modules, with a restore point first
- **App updates**: pick which apps to update; apps that fail can be reinstalled
- **Free up space**: temporary files, Recycle Bin, update cache, old Windows components
- **Battery health**, **Sleep and wake**, **Lid and sign-in**, **About this PC** (copy the details for IT support), **Restore point**

Some features need administrator rights. Click **Run as administrator** at the top when you need them.

The app checks for a newer version (`git pull`) when it starts and shows a banner when one was downloaded.
Keep the exe in this folder: it only starts `MaintainGui.ps1`, which holds all the logic.

## For power users: `Maintain.cmd`

The original keyboard-driven menu in a console window. Same features.

## Development

| File | What it is |
| --- | --- |
| `MaintainGui.ps1` | The WPF app (PowerShell 5.1). Run it directly with `powershell -STA -ExecutionPolicy Bypass -File MaintainGui.ps1`. `-StartPage Apps` (or `Clean`, `Battery`, `Sleep`, `Power`, `Info`) opens a page directly. |
| `launcher\Launcher.cs` | Source of `PC Maintenance.exe`: starts the script without a console window. |
| `build.ps1` | Rebuilds the exe and `assets\app.ico` with the C# compiler that ships with Windows. Only needed when the launcher or icon changes. |
| `Maintain.cmd` | The console version. |

Bump `$AppVersion` in `MaintainGui.ps1` when you deploy a change.
