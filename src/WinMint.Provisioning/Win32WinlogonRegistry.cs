using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;

using Microsoft.Win32;

using WinMint.Contracts;

namespace WinMint.Provisioning;

[SupportedOSPlatform("windows")]
public sealed class Win32WinlogonRegistry : IWinlogonRegistry
{
    private const string WinlogonSubKey = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";
    private const string ClearAutoLogonRunOnceName = "WinMintClearAutoLogon";
    private const string WinlogonRegPath = @"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";


    public void SetAutoLogon(string username, string password)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(username);
        ArgumentNullException.ThrowIfNull(password);
        using RegistryKey key = OpenWritable();
        // Username/password before AutoAdminLogon — never leave defaultuser0 + AutoAdminLogon=1 mid-write.
        key.SetValue("DefaultUserName", username, RegistryValueKind.String);
        key.SetValue("DefaultPassword", password, RegistryValueKind.String);
        key.SetValue("DefaultDomainName", ".", RegistryValueKind.String);
        key.SetValue("AutoAdminLogon", "1", RegistryValueKind.String);
    }

    internal static void ClearAutoLogon()
    {
        using RegistryKey key = OpenWritable();
        key.SetValue("AutoAdminLogon", "0", RegistryValueKind.String);
        try { key.DeleteValue("DefaultPassword", throwOnMissingValue: false); } catch { /* best-effort */ }
        try { key.DeleteValue("DefaultUserName", throwOnMissingValue: false); } catch { /* best-effort */ }
        try { key.DeleteValue("DefaultDomainName", throwOnMissingValue: false); } catch { /* best-effort */ }
    }

    /// <summary>
    /// Schedule Autologon clear + live chrome re-stamp on next interactive logon (HKCU RunOnce).
    /// Supervisor is Winlogon's Shell: exiting logs the session off. Clearing Autologon
    /// before that exit leaves LogonUI with Shell=explorer.exe and no explorer process.
    /// HKCU RunOnce survives in NTUSER across that logoff; Autologon re-enters, explorer
    /// starts as Shell, then RunOnce re-stamps bloom/search (explorer first-run race) and
    /// clears Autologon stamps (Users ACE on Winlogon from GrantShellUnlockAccess).
    /// </summary>
    internal static void ScheduleDeferredAutoLogonClear()
    {
        // ponytail: HKCU RunOnce; ceiling = stamps linger until next logon if Winlogon
        // never logs off (rare). Upgrade: breakaway delayed clear if that path shows up.
        string wallpaper = ShellChromeLayout.WallpaperPath;
        int searchMode = Win32WorkstationQuiet.SearchboxTaskbarMode;
        // Best-effort live-only Advanced re-stamp after Autologon (Chat/Task View/Copilot).
        // Widgets TaskbarDa is policy-owned (AllowNewsAndInterests); shell may delete the HKCU toggle.
        string advancedStamp = "";
        foreach (string name in QuietChromeFacts.LiveOnlyTaskbarExplorerAdvanced)
        {
            if (QuietChromeFacts.PolicyOwnedTaskbarExplorerAdvanced.Contains(name))
            {
                continue;
            }

            if (!QuietChromeFacts.ExplorerAdvancedDwords.TryGetValue(name, out int dword))
            {
                continue;
            }

            advancedStamp +=
                " & reg.exe add \"HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\"" +
                " /v " + name + " /t REG_DWORD /d " + dword + " /f";
        }

        // Match ApplyWallpaper: drop img19 TranscodedWallpaper cache, set style, then notify.
        // SPI_SETDESKWALLPAPER (Learn) is what Apply uses; RunOnce approximates via delete+reg+UpdatePerUser.
        // ponytail: delayed third stamp — explorer first-run can overwrite bloom/search after RunOnce;
        // ceiling = still races if first-run finishes after the timeout. Upgrade: logon task.
        const string themes = "%APPDATA%\\Microsoft\\Windows\\Themes";
        string stampChrome =
            "del /f /q \"" + themes + "\\TranscodedWallpaper\" 2>nul" +
            " & rd /s /q \"" + themes + "\\CachedFiles\" 2>nul" +
            " & reg.exe add \"HKCU\\Control Panel\\Desktop\" /v Wallpaper /t REG_SZ /d \"" + wallpaper + "\" /f" +
            " & reg.exe add \"HKCU\\Control Panel\\Desktop\" /v WallpaperStyle /t REG_SZ /d 10 /f" +
            " & reg.exe add \"HKCU\\Control Panel\\Desktop\" /v TileWallpaper /t REG_SZ /d 0 /f" +
            " & reg.exe add \"HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Wallpapers\" /v BackgroundType /t REG_DWORD /d 0 /f" +
            " & reg.exe add \"HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Search\" /v SearchboxTaskbarMode /t REG_DWORD /d " + searchMode + " /f" +
            " & reg.exe add \"HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DesktopSpotlight\\Settings\" /v EnabledState /t REG_DWORD /d 0 /f" +
            advancedStamp +
            " & rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True";
        string clearCmd =
            stampChrome +
            " & reg.exe add \"" + WinlogonRegPath + "\" /v AutoAdminLogon /t REG_SZ /d 0 /f" +
            " & reg.exe delete \"" + WinlogonRegPath + "\" /v DefaultPassword /f" +
            " & reg.exe delete \"" + WinlogonRegPath + "\" /v DefaultUserName /f" +
            " & reg.exe delete \"" + WinlogonRegPath + "\" /v DefaultDomainName /f" +
            " & " + stampChrome +
            " & timeout /t 10 /nobreak >nul" +
            " & " + stampChrome;
        using RegistryKey key = Registry.CurrentUser.CreateSubKey(
            @"Software\Microsoft\Windows\CurrentVersion\RunOnce")
            ?? throw new InvalidOperationException("Cannot open HKCU RunOnce for Autologon clear.");
        string value = "cmd.exe /c " + clearCmd;
        key.SetValue(ClearAutoLogonRunOnceName, value, RegistryValueKind.String);
        // Verify — silent arm failure left Autologon password stranded after mid-settle death.
        if (key.GetValue(ClearAutoLogonRunOnceName) is not string armed
            || !string.Equals(armed, value, StringComparison.Ordinal))
        {
            throw new InvalidOperationException(
                "HKCU RunOnce WinMintClearAutoLogon was not armed after SetValue.");
        }
    }

    public string? GetDefaultUserName()
    {
        using RegistryKey? key = Registry.LocalMachine.OpenSubKey(WinlogonSubKey, writable: false);
        return key?.GetValue("DefaultUserName") as string;
    }

    public bool GetAutoAdminLogon()
    {
        using RegistryKey? key = Registry.LocalMachine.OpenSubKey(WinlogonSubKey, writable: false);
        object? value = key?.GetValue("AutoAdminLogon");
        return value is string s && s == "1";
    }

    public string? GetShell()
    {
        using RegistryKey? key = Registry.LocalMachine.OpenSubKey(WinlogonSubKey, writable: false);
        return key?.GetValue("Shell") as string;
    }

    public void SetShell(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        using RegistryKey key = OpenWritable();
        key.SetValue("Shell", path, RegistryValueKind.String);
    }

    public void ReArmAutoLogonCount(int logonCount = 5)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(logonCount);
        using RegistryKey key = OpenWritable();
        key.SetValue("AutoAdminLogon", "1", RegistryValueKind.String);
        key.SetValue("AutoLogonCount", logonCount, RegistryValueKind.DWord);
    }

    /// <summary>
    /// Custom Shell runs at medium IL without HKLM admin write. Grant SetValue on Winlogon
    /// so Unlock (Shell → explorer.exe) can succeed.
    /// SetupComplete often runs before oobeSystem LocalAccounts exist — named-user ACE may
    /// fail to resolve; always grant BUILTIN\Users as the reliable medium-IL path.
    /// </summary>
    public void GrantShellUnlockAccess(string username)
    {
        using RegistryKey key = Registry.LocalMachine.OpenSubKey(
            WinlogonSubKey,
            RegistryKeyPermissionCheck.ReadWriteSubTree,
            RegistryRights.ChangePermissions | RegistryRights.ReadKey)
            ?? throw new InvalidOperationException($"Cannot open HKLM\\{WinlogonSubKey} for ACL.");

        RegistrySecurity security = key.GetAccessControl();
        AddSetValueAllow(security, new SecurityIdentifier(WellKnownSidType.BuiltinUsersSid, null));

        if (!string.IsNullOrWhiteSpace(username))
        {
            try
            {
                NTAccount account = username.Contains('\\', StringComparison.Ordinal)
                    ? new NTAccount(username)
                    : new NTAccount(".", username);
                AddSetValueAllow(security, account);
            }
            catch (IdentityNotMappedException)
            {
                // ponytail: user may not exist yet at SetupComplete; Users ACE still unlocks
            }
        }

        key.SetAccessControl(security);
    }

    private static void AddSetValueAllow(RegistrySecurity security, IdentityReference id)
    {
        security.AddAccessRule(new RegistryAccessRule(
            id,
            RegistryRights.SetValue | RegistryRights.QueryValues,
            InheritanceFlags.None,
            PropagationFlags.None,
            AccessControlType.Allow));
    }

    private static RegistryKey OpenWritable()
    {
        RegistryKey? key = Registry.LocalMachine.OpenSubKey(
            WinlogonSubKey,
            RegistryKeyPermissionCheck.ReadWriteSubTree,
            RegistryRights.SetValue | RegistryRights.QueryValues);
        if (key is null)
        {
            throw new InvalidOperationException($"Cannot open HKLM\\{WinlogonSubKey} for write.");
        }

        return key;
    }
}
