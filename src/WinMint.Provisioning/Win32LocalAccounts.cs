using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Principal;
using Microsoft.Win32;

namespace WinMint.Provisioning;

/// <summary>
/// Deletes a local user + profile (OOBE <c>defaultuser0</c> leftover). SetupComplete/SYSTEM only.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed partial class Win32LocalAccounts : ILocalAccounts
{
    private const uint NerrSuccess = 0;
    private const uint NerrUserNotFound = 2221;
    private const string DeferredTaskName = @"WinMint\RemoveOobeTempUser";

    public void TryDeleteLocalUserAndProfile(string username)
    {
        if (string.IsNullOrWhiteSpace(username))
        {
            return;
        }

        string trimmed = username.Trim();
        string? sid = TryFindProfileSid(trimmed);
        uint result = NetUserDel(null, trimmed);
        if (result is not NerrSuccess and not NerrUserNotFound)
        {
            // ponytail: still attempt profile + deferred; account may appear after OOBE
        }

        if (sid is not null)
        {
            _ = DeleteProfileW(sid, null, null);
        }

        TryDeleteProfileDirectory(trimmed);
        EnsureDeferredSystemCleanup(trimmed);
    }

    private static string? TryFindProfileSid(string username)
    {
        using RegistryKey? list = Registry.LocalMachine.OpenSubKey(
            @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList");
        if (list is null)
        {
            return null;
        }

        foreach (string sid in list.GetSubKeyNames())
        {
            using RegistryKey? sub = list.OpenSubKey(sid);
            string? path = sub?.GetValue("ProfileImagePath") as string;
            if (path is null)
            {
                continue;
            }

            string expanded = Environment.ExpandEnvironmentVariables(path).TrimEnd('\\');
            if (expanded.EndsWith('\\' + username, StringComparison.OrdinalIgnoreCase)
                || expanded.EndsWith('/' + username, StringComparison.OrdinalIgnoreCase))
            {
                return sid;
            }
        }

        return null;
    }

    private static void TryDeleteProfileDirectory(string username)
    {
        string root = Environment.GetEnvironmentVariable("SystemDrive") ?? "C:";
        string dir = Path.Combine(root + Path.DirectorySeparatorChar, "Users", username);
        if (!Directory.Exists(dir))
        {
            return;
        }

        try
        {
            Directory.Delete(dir, recursive: true);
        }
        catch
        {
            // ponytail: profile lock / in-use — deferred task retries after logon
        }
    }

    /// <summary>
    /// SetupComplete can run before OOBE finishes creating defaultuser0. ONLOGON/SYSTEM retries once.
    /// </summary>
    private static void EnsureDeferredSystemCleanup(string username)
    {
        if (!WindowsIdentity.GetCurrent().IsSystem)
        {
            return;
        }

        // Literal OOBE name only from MachineSetup — no shell metacharacters.
        if (!username.All(static c => char.IsAsciiLetterOrDigit(c)))
        {
            return;
        }

        string tr =
            $"cmd.exe /c net user {username} /delete "
            + $"& if exist \"%SystemDrive%\\Users\\{username}\" rmdir /s /q \"%SystemDrive%\\Users\\{username}\" "
            + $"& schtasks /Delete /TN \"{DeferredTaskName}\" /F";

        try
        {
            using Process? proc = Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    "schtasks.exe"),
                ArgumentList =
                {
                    "/Create",
                    "/TN",
                    DeferredTaskName,
                    "/RU",
                    "SYSTEM",
                    "/RL",
                    "HIGHEST",
                    "/SC",
                    "ONLOGON",
                    "/F",
                    "/TR",
                    tr,
                },
                UseShellExecute = false,
                CreateNoWindow = true,
            });
            proc?.WaitForExit(15_000);
        }
        catch
        {
            // ponytail: immediate delete may still have worked
        }
    }

    [LibraryImport("netapi32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial uint NetUserDel(string? servername, string username);

    [LibraryImport("userenv.dll", StringMarshalling = StringMarshalling.Utf16, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeleteProfileW(
        string lpSidString,
        string? lpProfilePath,
        string? lpComputerName);
}
