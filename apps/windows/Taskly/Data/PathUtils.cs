using System.Globalization;
using System.Runtime.InteropServices;

namespace Taskly.Data;

/// <summary>
/// App directory layout (shared contract): ~/.taskly/, tasks.db, config.ini.
/// Home resolution: USERPROFILE → HOME (Windows); HOME otherwise.
/// </summary>
public static class PathUtils
{
    public const string AppDirName = ".taskly";
    public const string DefaultDatabaseFileName = "tasks.db";
    public const string ConfigFileName = "config.ini";

    public static string GetAppDirectory()
    {
        var dir = Path.Combine(GetHomeDirectory(), AppDirName);
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }

        return dir;
    }

    public static string GetDefaultDatabasePath() =>
        Path.Combine(GetAppDirectory(), DefaultDatabaseFileName);

    public static string GetConfigPath() =>
        Path.Combine(GetAppDirectory(), ConfigFileName);

    public static string GetHomeDirectory()
    {
        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            var userProfile = Environment.GetEnvironmentVariable("USERPROFILE");
            if (!string.IsNullOrEmpty(userProfile))
            {
                return userProfile;
            }
        }

        var home = Environment.GetEnvironmentVariable("HOME");
        if (!string.IsNullOrEmpty(home))
        {
            return home;
        }

        return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    }
}
