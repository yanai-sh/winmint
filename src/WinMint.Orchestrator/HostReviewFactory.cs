namespace WinMint.Orchestrator;

/// <summary>
/// HostReview projection from a frozen Profile + BuildArtifacts.
/// Password never appears in the review Profile or authored JSON.
/// Package id lists + wire honesty come from SoftwarePlan (via artifacts).
/// </summary>
internal static class HostReviewFactory
{
    internal static HostReview Create(
        Profile profile,
        BuildArtifacts artifacts,
        SourceMediaReview? media,
        string? work,
        string? output,
        string profileStem,
        IEnumerable<string>? authoredSelectionLabels)
    {
        Profile redacted = HostCompile.SnapshotProfile(profile) with
        {
            Account = profile.Account with { Password = null },
        };
        return new HostReview(
            redacted,
            System.Text.Encoding.UTF8.GetString(BuildPlan.SerializeProfile(redacted)),
            media,
            work,
            output,
            profileStem,
            artifacts.Manifest.ImageQuality,
            artifacts.PackageStrict,
            artifacts.Manifest.RequiresNetwork,
            HostCompile.ReadOnly(artifacts.RemoveProvisionedAppx),
            HostCompile.ReadOnly(artifacts.EffectivePackages),
            HostCompile.ReadOnly(artifacts.Jobs.Jobs.Select(HostCompile.SnapshotJob)),
            HostCompile.ReadOnly(artifacts.Stages),
            artifacts.BraveSelected,
            HostCompile.ReadOnly(artifacts.EffectiveWinget),
            HostCompile.ReadOnly(artifacts.EffectiveScoop),
            HostCompile.ReadOnly(artifacts.EffectiveWsl),
            HostCompile.ReadOnly(authoredSelectionLabels ?? []),
            artifacts.PackageWireHonest);
    }
}
