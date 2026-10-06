using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>
/// Plan-time WSL package wire for HostReview Gate B: job PackageIds ↔ effective facts ↔ store proof.
/// </summary>
internal static class HostPackageWire
{
    internal static IReadOnlyList<string> EffectiveWslInstallIds(
        IEnumerable<EffectivePackageFact> packages) =>
        [.. packages
            .Where(static package => package.Source == EffectivePackageSource.Wsl)
            .Select(static package => package.ResolvedInstallId)];

    /// <summary>
    /// True when every WSL job PackageId has a matching effective fact, and every store WSL
    /// installId is covered by <see cref="PackagesProof"/> prove-set (fromFile is catalog-only).
    /// </summary>
    internal static bool IsHonest(
        IReadOnlyList<ProvisionJob> jobs,
        IReadOnlyList<EffectivePackageFact> packages,
        PackageCatalog catalog,
        string architecture = PackagesProof.DefaultArchitecture)
    {
        HashSet<string> jobIds = JobPackageIds(jobs);
        HashSet<string> factIds = [.. EffectiveWslInstallIds(packages)];
        if (!jobIds.SetEquals(factIds))
        {
            return false;
        }

        if (jobIds.Count == 0)
        {
            return true;
        }

        HashSet<string> provenStore = ProvenStoreInstallIds(catalog, architecture);
        foreach (string id in jobIds)
        {
            if (!catalog.TryGetWslByInstallId(id, out WslDistroEntry? entry))
            {
                return false;
            }

            if (entry.InstallKind is WslInstallKind.Store && !provenStore.Contains(id))
            {
                return false;
            }
        }

        return true;
    }

    private static HashSet<string> JobPackageIds(IReadOnlyList<ProvisionJob> jobs) =>
        [.. jobs
            .Where(static job => job.Kind == ProvisionJobKind.Wsl)
            .Select(static job => job.PackageId)
            .Where(static id => !string.IsNullOrWhiteSpace(id))
            .Cast<string>()];

    private static HashSet<string> ProvenStoreInstallIds(PackageCatalog catalog, string architecture) =>
        [.. PackagesProof.BuildProveSet(catalog, architecture)
            .Where(static entry => entry.Source == "wsl")
            .Select(static entry => entry.Id)];
}
