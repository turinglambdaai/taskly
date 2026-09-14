using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace Taskly.Cli;

/// <summary>
/// install-cli/uninstall-cli for Windows: copies the exe to
/// %LOCALAPPDATA%\Programs\Taskly, writes a taskly.cmd shim, adds the dir to
/// the user PATH (HKCU\Environment, REG_EXPAND_SZ) and broadcasts
/// WM_SETTINGCHANGE. Port of the proven 0.6.x CliInstaller.
/// </summary>
public static class CliInstaller
{
    private static string InstallDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Programs", "Taskly");

    private static string DestExe => Path.Combine(InstallDir, "taskly.exe");
    private static string DestCmd => Path.Combine(InstallDir, "taskly.cmd");

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint msg, UIntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);

    private const uint HwndBroadcast = 0xFFFF;
    private const uint WmSettingChange = 0x001A;
    private const uint SmtoAbortIfHung = 0x0002;

    public static int Install()
    {
        try
        {
            var sourceExe = Environment.ProcessPath;
            if (string.IsNullOrEmpty(sourceExe) || !File.Exists(sourceExe))
            {
                Console.Error.WriteLine("Cannot locate the running executable.");
                return 1;
            }

            Directory.CreateDirectory(InstallDir);
            File.Copy(sourceExe, DestExe, overwrite: true);
            File.WriteAllText(DestCmd, $"@echo off\r\n\"{DestExe}\" %*\r\n");

            AddToUserPath(InstallDir);

            Console.WriteLine($"taskly command installed: {DestCmd}");
            Console.WriteLine("Please open a new terminal window for the PATH change to take effect.");
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Install failed: {ex.Message}");
            return 1;
        }
    }

    public static int Uninstall()
    {
        try
        {
            RemoveFromUserPath(InstallDir);

            if (Directory.Exists(InstallDir))
            {
                Directory.Delete(InstallDir, recursive: true);
                Console.WriteLine("taskly command removed.");
                return 0;
            }

            Console.Error.WriteLine("taskly command was not installed (nothing to remove).");
            return 1;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Uninstall failed: {ex.Message}");
            return 1;
        }
    }

    private static void AddToUserPath(string directory)
    {
        using var key = Registry.CurrentUser.OpenSubKey("Environment", writable: true)
            ?? Registry.CurrentUser.CreateSubKey("Environment");

        var current = (key?.GetValue("Path", string.Empty) as string) ?? string.Empty;
        var entries = current.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (entries.Contains(directory, StringComparer.OrdinalIgnoreCase))
        {
            return;
        }

        var newValue = string.IsNullOrEmpty(current) ? directory : current.TrimEnd(';') + ";" + directory;
        key?.SetValue("Path", newValue, RegistryValueKind.ExpandString);
        BroadcastEnvironmentChange();
    }

    private static void RemoveFromUserPath(string directory)
    {
        using var key = Registry.CurrentUser.OpenSubKey("Environment", writable: true);
        if (key?.GetValue("Path") is not string current)
        {
            return;
        }

        var entries = current.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(e => !string.Equals(e, directory, StringComparison.OrdinalIgnoreCase));
        var newValue = string.Join(";", entries);
        if (newValue != current)
        {
            key.SetValue("Path", newValue, RegistryValueKind.ExpandString);
            BroadcastEnvironmentChange();
        }
    }

    private static void BroadcastEnvironmentChange()
    {
        SendMessageTimeout(
            (IntPtr)HwndBroadcast, WmSettingChange, UIntPtr.Zero, "Environment",
            SmtoAbortIfHung, 5000, out _);
    }
}
