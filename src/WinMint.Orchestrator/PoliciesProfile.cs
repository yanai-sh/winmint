namespace WinMint.Orchestrator;

/// <summary>
/// Optional Profile <c>policies</c> object (winmint.profile/v1). Omit ⇒ product defaults.
/// OneDrive / EdgeDebloat / DeviceMetadata / WPBT / ReservedStorage are product constants ([ADR-009]), not fields here.
/// </summary>
public sealed record PoliciesProfile(
    /// <summary>
    /// Obsolete for Edge Copilot: Edge Copilot is always kept; AppX Copilot removal is product-required
    /// through <see cref="ProductRequiredStrip"/>.
    /// </summary>
    bool KeepCopilot = false,
    /// <summary>Optional DoH provider id (<c>cloudflare</c>, <c>google</c>, <c>quad9</c>). Null/omit ⇒ no DoH job.</summary>
    string? DohProvider = null)
{
    public static PoliciesProfile Defaults { get; } = new();
}
