using System.Runtime.Versioning;
using System.Security.AccessControl;
using Microsoft.Win32;

namespace WinMint.Provisioning;

[SupportedOSPlatform("windows")]
public sealed class Win32WinlogonRegistry : IWinlogonRegistry
{
    private const string WinlogonSubKey = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon";

    public void SetAutoLogon(string username, string password)
    {
        using RegistryKey key = OpenWritable();
        // Username/password before AutoAdminLogon — never leave defaultuser0 + AutoAdminLogon=1 mid-write.
        key.SetValue("DefaultUserName", username, RegistryValueKind.String);
        key.SetValue("DefaultPassword", password, RegistryValueKind.String);
        key.SetValue("DefaultDomainName", ".", RegistryValueKind.String);
        key.SetValue("AutoAdminLogon", "1", RegistryValueKind.String);
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
        using RegistryKey key = OpenWritable();
        key.SetValue("Shell", path, RegistryValueKind.String);
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
