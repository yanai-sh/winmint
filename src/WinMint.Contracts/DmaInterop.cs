namespace WinMint.Contracts;

/// <summary>
/// Sticky DMA setup-region literals (Ireland). Visible region comes from <see cref="DmaSettleTarget"/>.
/// <para>
/// <b>DMA here is the EU Digital Markets Act, not Direct Memory Access.</b> Windows Setup only offers the
/// DMA choice screens in an EEA region, so every <c>Dma*</c> type in WinMint is about Setup region, never
/// device memory or Kernel DMA Protection.
/// </para>
/// </summary>
public static class DmaInterop
{
    public const string IrelandLocale = "en-IE";

    /// <summary>Learn GeoID for Ireland (<c>0x44</c>).</summary>
    public const int IrelandGeoId = 68;

    /// <summary>ISO 3166-1 alpha-2 for Ireland (Geo <c>Name</c>).</summary>
    public const string IrelandGeoName = "IE";
}
