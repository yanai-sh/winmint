namespace WinMint.Contracts;

/// <summary>
/// DMA settle intent shared by host Profile/contract and guest bundle.
/// Profile JSON keeps <c>dma.enabled</c> separate; materialize <see cref="Enabled"/> here for the guest.
/// Wire settle file omits Enabled (<c>dmaEnabled</c> is a sibling on the bundle).
/// </summary>
public sealed record DmaSettleTarget(
    bool Enabled,
    string? Locale,
    int? GeoId,
    string? TimeZoneId,
    bool? LocationServicesEnabled);
