namespace WinMint.Contracts;

public enum PackageToolSource
{
    Winget,
    Scoop,
    Store,
}

public static class PackageToolSourceWire
{
    public const string Winget = "winget";
    public const string Scoop = "scoop";
    public const string Store = "store";

    public static bool TryParse(string? wire, out PackageToolSource source)
    {
        if (string.IsNullOrWhiteSpace(wire))
        {
            source = default;
            return false;
        }

        if (wire.Equals(Winget, StringComparison.OrdinalIgnoreCase))
        {
            source = PackageToolSource.Winget;
            return true;
        }

        if (wire.Equals(Scoop, StringComparison.OrdinalIgnoreCase))
        {
            source = PackageToolSource.Scoop;
            return true;
        }

        if (wire.Equals(Store, StringComparison.OrdinalIgnoreCase))
        {
            source = PackageToolSource.Store;
            return true;
        }

        source = default;
        return false;
    }

    public static string ToWire(this PackageToolSource source) => source switch
    {
        PackageToolSource.Winget => Winget,
        PackageToolSource.Scoop => Scoop,
        PackageToolSource.Store => Store,
        _ => throw new ArgumentOutOfRangeException(nameof(source), source, "Unknown PackageToolSource."),
    };
}
