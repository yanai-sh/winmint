namespace WinMint.Orchestrator;

/// <summary>
/// S4 harness summary written under the pulled evidence folder (`acceptance.json`).
/// </summary>
public sealed record SmokeAcceptanceDocument(
    string SchemaVersion,
    bool SplashBeforeExplorer,
    string DmaHardFields,
    bool Unlocked,
    string Outcome,
    string Lane,
    long? FirstPaintMs,
    bool FirstPaintWarn,
    string GuestEvidencePath,
    bool KeepFlagAppxAbsent = false,
    IReadOnlyList<string>? PinnedRemoveAppx = null)
{
    public const string SchemaId = "winmint.smoke.acceptance/v1";
}
