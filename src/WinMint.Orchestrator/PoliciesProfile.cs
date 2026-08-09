namespace WinMint.Orchestrator;

/// <summary>
/// Optional Profile <c>policies</c> object (winmint.profile/v1). Omit ⇒ product defaults.
/// AppX Copilot/gaming strip, OneDrive / EdgeDebloat / DeviceMetadata / WPBT / ReservedStorage /
/// MinGit / Nilesoft are product posture (<see cref="ProductPosture"/>), not fields here.
/// </summary>
public sealed record PoliciesProfile(
    /// <summary>Optional DoH provider id (<c>cloudflare</c>, <c>google</c>, <c>quad9</c>). Null/omit ⇒ no DoH job.</summary>
    string? DohProvider = null)
{
    public static PoliciesProfile Defaults { get; } = new();
}
