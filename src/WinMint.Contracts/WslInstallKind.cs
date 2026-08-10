namespace WinMint.Contracts;

public enum WslInstallKind
{
    FromFile,
    Store,
}

public static class WslInstallKindWire
{
    public const string FromFile = "fromFile";
    public const string Store = "store";

    public static bool TryParse(string? wire, out WslInstallKind kind)
    {
        if (string.IsNullOrWhiteSpace(wire))
        {
            kind = default;
            return false;
        }

        if (wire.Equals(FromFile, StringComparison.OrdinalIgnoreCase))
        {
            kind = WslInstallKind.FromFile;
            return true;
        }

        if (wire.Equals(Store, StringComparison.OrdinalIgnoreCase))
        {
            kind = WslInstallKind.Store;
            return true;
        }

        kind = default;
        return false;
    }

    public static string ToWire(this WslInstallKind kind) => kind switch
    {
        WslInstallKind.FromFile => FromFile,
        WslInstallKind.Store => Store,
        _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unknown WslInstallKind."),
    };
}
