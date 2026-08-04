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
        try
        {
            foreach (Package package in _manager.FindPackagesForUser(string.Empty))
            {
                AppxPackageInfo info = ToInfo(package);
                if (MatchesCatalogId(info, catalogId))
                {
                    hits.Add(info);
                }
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // Medium-IL Shell: treat as no registered hits
            return [];
        }

        return hits;
    }

    public IReadOnlyList<AppxPackageInfo> FindProvisionedByCatalogId(string catalogId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(catalogId);
        List<AppxPackageInfo> hits = [];
        try
        {
            foreach (Package package in _manager.FindProvisionedPackages())
            {
                AppxPackageInfo info = ToInfo(package);
                if (MatchesCatalogId(info, catalogId))
                {
                    hits.Add(info);
                }
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // ponytail: FindProvisionedPackages needs elevation; offline remove already handled provisioned
            return [];
        }

        return hits;
    }

    public void RemovePackage(string packageFullName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFullName);
        try
        {
            DeploymentResult result = _manager.RemovePackageAsync(packageFullName).AsTask().GetAwaiter().GetResult();
            if (!string.IsNullOrEmpty(result.ErrorText))
            {
                throw new InvalidOperationException($"RemovePackageAsync({packageFullName}): {result.ErrorText}");
            }
        }
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // Medium-IL may not remove; leave registered package for a future elevated pass
        }
    }

    public void DeprovisionPackageFamily(string packageFamilyName)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(packageFamilyName);
        try
        {
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
        catch (Exception ex) when (IsAccessDenied(ex))
        {
            // ponytail: DeprovisionPackageForAllUsers needs admin; offline DISM path owns this
        }
    }

    private static bool IsAccessDenied(Exception ex)
    {
        for (Exception? e = ex; e is not null; e = e.InnerException)
        {
            if (e is UnauthorizedAccessException)
            {
                return true;
            }

            if (e.Message.Contains("Access is denied", StringComparison.OrdinalIgnoreCase)
                || e.Message.Contains("0x80070005", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
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
