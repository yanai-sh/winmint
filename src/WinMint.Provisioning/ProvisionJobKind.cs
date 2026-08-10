namespace WinMint.Provisioning;

/// <summary>Closed provisioning job kinds. Wire JSON uses dotted strings; parse once at <see cref="BundleLoader"/>.</summary>
public enum ProvisionJobKind
{
    AppxSafetyNet,
    OneDriveUninstall,
    ReservedStorageDisable,
    WorkstationQuiet,
    DohSet,
    PackageAuditNative,
    Stub,
    Winget,
    WingetImport,
    Scoop,
    ScoopBatch,
    WslPlatform,
    Wsl,
}

public static class ProvisionJobKindWire
{
    public const string AppxSafetyNet = "appx.safetyNet";
    public const string OneDriveUninstall = "onedrive.uninstall";
    public const string ReservedStorageDisable = "reservedStorage.disable";
    public const string WorkstationQuiet = "workstation.quiet";
    public const string DohSet = "doh.set";
    public const string PackageAuditNative = "package.auditNative";
    public const string Stub = "stub";
    public const string Winget = "winget";
    public const string WingetImport = "winget.import";
    public const string Scoop = "scoop";
    public const string ScoopBatch = "scoop.batch";
    public const string WslPlatform = "wsl.platform";
    public const string Wsl = "wsl";

    public static bool TryParse(string? wire, out ProvisionJobKind kind)
    {
        if (string.IsNullOrWhiteSpace(wire))
        {
            kind = default;
            return false;
        }

        if (wire.Equals(AppxSafetyNet, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.AppxSafetyNet;
            return true;
        }

        if (wire.Equals(OneDriveUninstall, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.OneDriveUninstall;
            return true;
        }

        if (wire.Equals(ReservedStorageDisable, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.ReservedStorageDisable;
            return true;
        }

        if (wire.Equals(WorkstationQuiet, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.WorkstationQuiet;
            return true;
        }

        if (wire.Equals(DohSet, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.DohSet;
            return true;
        }

        if (wire.Equals(PackageAuditNative, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.PackageAuditNative;
            return true;
        }

        if (wire.Equals(Stub, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.Stub;
            return true;
        }

        if (wire.Equals(Winget, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.Winget;
            return true;
        }

        if (wire.Equals(WingetImport, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.WingetImport;
            return true;
        }

        if (wire.Equals(Scoop, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.Scoop;
            return true;
        }

        if (wire.Equals(ScoopBatch, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.ScoopBatch;
            return true;
        }

        if (wire.Equals(WslPlatform, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.WslPlatform;
            return true;
        }

        if (wire.Equals(Wsl, StringComparison.OrdinalIgnoreCase))
        {
            kind = ProvisionJobKind.Wsl;
            return true;
        }

        kind = default;
        return false;
    }

    public static string ToWire(this ProvisionJobKind kind) => kind switch
    {
        ProvisionJobKind.AppxSafetyNet => AppxSafetyNet,
        ProvisionJobKind.OneDriveUninstall => OneDriveUninstall,
        ProvisionJobKind.ReservedStorageDisable => ReservedStorageDisable,
        ProvisionJobKind.WorkstationQuiet => WorkstationQuiet,
        ProvisionJobKind.DohSet => DohSet,
        ProvisionJobKind.PackageAuditNative => PackageAuditNative,
        ProvisionJobKind.Stub => Stub,
        ProvisionJobKind.Winget => Winget,
        ProvisionJobKind.WingetImport => WingetImport,
        ProvisionJobKind.Scoop => Scoop,
        ProvisionJobKind.ScoopBatch => ScoopBatch,
        ProvisionJobKind.WslPlatform => WslPlatform,
        ProvisionJobKind.Wsl => Wsl,
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unknown ProvisionJobKind."),
    };
}
