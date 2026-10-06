using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>
/// HostReview projection from a frozen Profile + BuildArtifacts.
/// Password never appears in the review Profile or authored JSON.
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
        IReadOnlyList<ProvisionJob> jobs =
            HostCompile.ReadOnly(artifacts.Jobs.Jobs.Select(HostCompile.SnapshotJob));
        IReadOnlyList<EffectivePackageFact> packages =
            HostCompile.ReadOnly(artifacts.EffectivePackages);
        IReadOnlyList<string> effectiveWsl = HostCompile.ReadOnly(
            HostPackageWire.EffectiveWslInstallIds(packages));
        PackageCatalog catalog = PackageCatalog.Default;
        bool wireHonest = HostPackageWire.IsHonest(jobs, packages, catalog);
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
            packages,
            jobs,
            HostCompile.ReadOnly(artifacts.Stages),
            artifacts.BraveSelected,
            HostCompile.ReadOnly(artifacts.EffectivePackages
                .Where(static package =>
                    package.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store)
                .Select(static package => package.ResolvedInstallId)),
            HostCompile.ReadOnly(artifacts.EffectivePackages
                .Where(static package => package.Source == EffectivePackageSource.Scoop)
                .Select(static package => package.ResolvedInstallId)),
            effectiveWsl,
            HostCompile.ReadOnly(authoredSelectionLabels ?? []),
            wireHonest);
    }
}
