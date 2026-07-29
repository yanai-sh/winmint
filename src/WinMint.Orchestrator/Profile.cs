namespace WinMint.Orchestrator;

/// <summary>Parsed Profile document (winmint.profile/v1). Field names frozen in ticket 01.</summary>
public sealed record Profile(
    AccountProfile Account,
    DmaProfile Dma);

public sealed record AccountProfile(
    AccountMode Mode,
    string Username,
    string? Password);

public enum AccountMode
{
    LocalAutoLogon,
}

public sealed record DmaProfile(
    bool Enabled,
    DmaSettleTarget Settle);

public sealed record DmaSettleTarget(
    string Locale,
    int GeoId,
    string TimeZoneId,
    bool LocationServicesEnabled);
