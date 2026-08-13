namespace WinMint.Contracts;

/// <summary>
/// DMA (EU <b>Digital Markets Act</b> — see <see cref="DmaInterop"/>) settle intent, shared by host
/// Profile/contract and guest bundle.
/// Enabled lives only on the outer DMA object (host <c>DmaProfile.Enabled</c> / bundle <c>dmaEnabled</c>).
/// </summary>
public sealed record DmaSettleTarget(
    string? Locale,
    int? GeoId,
    string? TimeZoneId,
    bool? LocationServicesEnabled);
