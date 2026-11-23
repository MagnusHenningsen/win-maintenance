// "PC Maintenance.exe": a tiny launcher so non-technical users get a normal double-clickable
// program with an icon. It starts MaintainGui.ps1 (next to the exe) in Windows PowerShell with
// no console window. All the real logic lives in the script, so the exe rarely needs rebuilding:
// the script updates itself with git pull, the exe stays the same.
//
// Build with build.ps1 (uses the C# compiler that ships with Windows, no SDK needed).
//
// Arguments:
//   --elevated   started by "Run as administrator" (skip the update check)
//   --no-update  restarted after an update (skip the update check)
//   --auto       run by the scheduled task: automatic maintenance without a window
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("PC Maintenance")]
[assembly: AssemblyProduct("PC Maintenance")]
[assembly: AssemblyDescription("Keeps this PC up to date and tidy")]
[assembly: AssemblyVersion("2.2.0.0")]
[assembly: AssemblyFileVersion("2.2.0.0")]

static class Launcher
{
    const string Title = "PC Maintenance";

    [STAThread]
    static int Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "MaintainGui.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show(
                "MaintainGui.ps1 was not found next to this program.\n\n" +
                "Keep \"PC Maintenance.exe\" in the same folder as the other maintenance files.",
                Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        string extra = "";
        foreach (string a in args)
        {
            if (a == "--elevated" || a == "--no-update") extra += " -NoUpdate";
            if (a == "--auto") extra += " -Auto -NoUpdate";   // scheduled automatic maintenance, no window
        }

        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                 @"WindowsPowerShell\v1.0\powershell.exe");
        var psi = new ProcessStartInfo(ps,
            "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\"" + extra);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = dir;
        psi.EnvironmentVariables["MAINT_LAUNCHER"] = Application.ExecutablePath;

        try
        {
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start Windows PowerShell:\n\n" + ex.Message, Title,
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        return 0;
    }
}
