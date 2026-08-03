namespace WinMint.Orchestrator;

/// <summary>Parsed Profile document (winmint.profile/v1). Field names frozen in ticket 01; debloat in ticket 11.</summary>
public sealed record Profile(
    AccountProfile Account,
    DmaProfile Dma,
    IReadOnlyList<string> RemoveProvisionedAppx);

public sealed record AccountProfile(
    AccountMode Mode,
    string Username,
    string? Password);

public enum AccountMode
{
    LocalAutoLogon,
}

/// <summary>Wire form of <see cref="AccountMode"/> in profile JSON <c>account.mode</c>.</summary>
public static class AccountModeWire
{
    public const string LocalAutoLogon = "localAutoLogon";
}

public sealed record DmaProfile(
    bool Enabled,
    DmaSettleTarget Settle);

public sealed record DmaSettleTarget(
    string Locale,
    int GeoId,
    string TimeZoneId,
    bool LocationServicesEnabled);
