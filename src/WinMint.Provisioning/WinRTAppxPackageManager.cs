using System.Runtime.Versioning;
using Windows.ApplicationModel;
using Windows.Management.Deployment;

namespace WinMint.Provisioning;

/// <summary>Production PackageManager adapter for FirstLogon AppX safety net (ticket 13).</summary>
[SupportedOSPlatform("windows10.0.19041.0")]
public sealed class WinRTAppxPackageManager : IAppxPackageManager
{
    private readonly PackageManager _manager = new();

    public IReadOnlyList<AppxPackageInfo> FindRegisteredByCatalogId(string catalogId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(catalogId);
        List<AppxPackageInfo> hits = [];
        foreach (Package package in _manager.FindPackagesForUser(string.Empty))
        {
            AppxPackageInfo info = ToInfo(package);
            if (MatchesCatalogId(info, catalogId))
            {
                hits.Add(info);
            }
        }

        return hits;
    }

    public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(catalogId);
        List<AppxPackageInfo> hits = [];
        foreach (Package package in _manager.FindProvisionedPackages())
        {
            AppxPackageInfo info = ToInfo(package);
            if (MatchesCatalogId(info, catalogId))
            {
                hits.Add(info);
            }
        }

        return hits;
    }

    public void RemovePackage(string packageFullName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFullName);
        DeploymentResult result = _manager.RemovePackageAsync(packageFullName).AsTask().GetAwaiter().GetResult();
        if (!string.IsNullOrEmpty(result.ErrorText))
        {
            throw new InvalidOperationException($"RemovePackageAsync({packageFullName}): {result.ErrorText}");
        }
    }

    public void DeprovisionPackageFamily(string packageFamilyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);
        DeploymentResult result = _manager
            .DeprovisionPackageForAllUsersAsync(packageFamilyName)
            .AsTask()
            .GetAwaiter()
            .GetResult();
        if (!string.IsNullOrEmpty(result.ErrorText))
        {
            throw new InvalidOperationException(
                $"DeprovisionPackageForAllUsersAsync({packageFamilyName}): {result.ErrorText}");
        }
    }

    private static AppxPackageInfo ToInfo(Package package) =>
        new(
            package.Id.FullName,
            package.Id.FamilyName,
            string.IsNullOrWhiteSpace(package.Id.Name) ? package.DisplayName : package.Id.Name);

    internal static bool MatchesCatalogId(AppxPackageInfo package, string catalogId) =>
        string.Equals(package.DisplayName, catalogId, StringComparison.OrdinalIgnoreCase)
        || package.PackageFamilyName.StartsWith(catalogId + "_", StringComparison.OrdinalIgnoreCase)
        || package.PackageFullName.StartsWith(catalogId + "_", StringComparison.OrdinalIgnoreCase);
}
