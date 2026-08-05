namespace WinMint.Orchestrator;

/// <summary>
/// Optional Profile <c>policies</c> object (winmint.profile/v1). Omit ⇒ product defaults.
/// OneDrive / EdgeDebloat / DeviceMetadata / WPBT / ReservedStorage are product constants ([ADR-009]), not fields here.
/// </summary>
public sealed record PoliciesProfile(
    /// <summary>When false (default), Plan stamps Copilot-kill Edge/Windows policies; host may add Copilot AppX.</summary>
    bool KeepCopilot = false,
    /// <summary>Optional DoH provider id (<c>cloudflare</c>, <c>google</c>, <c>quad9</c>). Null/omit ⇒ no DoH job.</summary>
    string? DohProvider = null)
{
    public static PoliciesProfile Defaults { get; } = new();
}
