using System.Text;
using System.Text.Json;

using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static partial class BuildPlan
{
    private static Result<PackagePlanSlice, Failure> PlanPackages(
        Profile profile,
        PackageCatalog catalog,
        string imageArchitecture,
        bool auditStrict)
    {
        Failure? failure = ValidateNeedsRebootSubset(
            profile.WingetPackages,
            profile.WingetNeedsReboot,
            "packages.wingetNeedsReboot.unknown",
            "wingetNeedsReboot",
            "packages.winget");
        if (failure is not null)
        {
            return Result.Fail<PackagePlanSlice, Failure>(failure.Value);
        }

        failure = ValidateNeedsRebootSubset(
            profile.ScoopPackages,
            profile.ScoopNeedsReboot,
            "packages.scoopNeedsReboot.unknown",
            "scoopNeedsReboot",
            "packages.scoop");
        if (failure is not null)
        {
            return Result.Fail<PackagePlanSlice, Failure>(failure.Value);
        }

        failure = ValidateNeedsRebootSubset(
            profile.WslDistros,
            profile.WslNeedsReboot,
            "packages.wslNeedsReboot.unknown",
            "wslNeedsReboot",
            "packages.wsl");
        if (failure is not null)
        {
            return Result.Fail<PackagePlanSlice, Failure>(failure.Value);
        }

        string imageArch = PackageCatalog.NormalizeArch(imageArchitecture);
        HashSet<string> wingetNeedsReboot = new(profile.WingetNeedsReboot, StringComparer.OrdinalIgnoreCase);
        HashSet<string> scoopNeedsReboot = new(profile.ScoopNeedsReboot, StringComparer.OrdinalIgnoreCase);
        HashSet<string> wslNeedsReboot = new(profile.WslNeedsReboot, StringComparer.OrdinalIgnoreCase);
        List<EffectivePackageFact> facts = [];
        List<string> auditTargets = [];

        IReadOnlyList<string> effectiveWingetIds = ProductPosture.MergeWinget(profile.WingetPackages);
        List<PackageToolEntry> wingetTools = [];
        List<bool> wingetReboot = [];
        foreach (string authoredInstallId in effectiveWingetIds)
        {
            if (!catalog.TryGetToolByInstallId(authoredInstallId, out PackageToolEntry? tool)
                || tool.Source is not (PackageToolSource.Winget or PackageToolSource.Store))
            {
                return Result.Fail<PackagePlanSlice, Failure>(
                    new Failure(
                        "packages.catalog.unknown",
                        $"packages.winget id '{authoredInstallId}' is not in the shipped package catalog."));
            }

            if (!SupportsArchitecture(tool.Architectures, imageArch))
            {
                return Result.Fail<PackagePlanSlice, Failure>(
                    new Failure(
                        "packages.catalog.unsupportedArch",
                        $"{tool.DisplayName} ({authoredInstallId}) does not support {imageArch} in the package catalog."));
            }

            bool needsReboot = wingetNeedsReboot.Contains(authoredInstallId);
            wingetTools.Add(tool);
            wingetReboot.Add(needsReboot);
            facts.Add(new EffectivePackageFact(
                tool.Source == PackageToolSource.Store ? EffectivePackageSource.Store : EffectivePackageSource.Winget,
                tool.InstallId,
                ProductPosture.WingetIdSet.Contains(tool.InstallId)
                    ? EffectivePackageOrigin.ProductPosture
                    : EffectivePackageOrigin.Profile,
                needsReboot));
            auditTargets.Add(tool.InstallId);
        }

        IReadOnlyList<string> effectiveScoopIds = ProductPosture.MergeScoop(profile.ScoopPackages);
        List<PackageToolEntry> scoopTools = [];
        List<bool> scoopReboot = [];
        foreach (string authoredInstallId in effectiveScoopIds)
        {
            if (!catalog.TryGetToolByInstallId(authoredInstallId, out PackageToolEntry? tool)
                || tool.Source is not PackageToolSource.Scoop)
            {
                return Result.Fail<PackagePlanSlice, Failure>(
                    new Failure(
                        "packages.catalog.unknown",
                        $"packages.scoop id '{authoredInstallId}' is not in the shipped package catalog."));
            }

            if (!SupportsArchitecture(tool.Architectures, imageArch))
            {
                return Result.Fail<PackagePlanSlice, Failure>(
                    new Failure(
                        "packages.catalog.unsupportedArch",
                        $"{tool.DisplayName} ({authoredInstallId}) does not support {imageArch} in the package catalog."));
            }

            bool needsReboot = scoopNeedsReboot.Contains(authoredInstallId);
            scoopTools.Add(tool);
            scoopReboot.Add(needsReboot);
            facts.Add(new EffectivePackageFact(
                EffectivePackageSource.Scoop,
                tool.InstallId,
                ProductPosture.ScoopIdSet.Contains(tool.InstallId)
                    ? EffectivePackageOrigin.ProductPosture
                    : EffectivePackageOrigin.Profile,
                needsReboot));
        }

        List<WslDistroEntry> wslEntries = [];
        List<bool> wslReboot = [];
        Dictionary<string, int> wslIndexByInstallId = new(StringComparer.OrdinalIgnoreCase);
        int wslFactStart = facts.Count;
        foreach (string token in profile.WslDistros)
        {
            if (!catalog.TryGetWslByProfileToken(token, out WslDistroEntry? entry))
            {
                return Result.Fail<PackagePlanSlice, Failure>(
                    new Failure(
                        "packages.catalog.unknown",
                        $"packages.wsl token '{token}' is not in the shipped WSL catalog."));
            }

            if (!SupportsArchitecture(entry.Architectures, imageArch))
            {
                return Result.Fail<PackagePlanSlice, Failure>(
                    new Failure(
                        "packages.catalog.unsupportedArch",
                        $"{entry.DisplayName} ({token}) does not support {imageArch} in the WSL catalog."));
            }

            bool needsReboot = wslNeedsReboot.Contains(token);
            if (wslIndexByInstallId.TryGetValue(entry.InstallId, out int existingIndex))
            {
                if (needsReboot && !wslReboot[existingIndex])
                {
                    wslReboot[existingIndex] = true;
                    facts[wslFactStart + existingIndex] = facts[wslFactStart + existingIndex] with
                    {
                        NeedsReboot = true,
                    };
                }

                continue;
            }

            wslIndexByInstallId.Add(entry.InstallId, wslEntries.Count);
            wslEntries.Add(entry);
            wslReboot.Add(needsReboot);
            facts.Add(new EffectivePackageFact(
                EffectivePackageSource.Wsl,
                entry.InstallId,
                EffectivePackageOrigin.Profile,
                needsReboot));
        }

        byte[]? wingetImportJson = null;
        List<ProvisionJob> jobs = [];
        if (imageArch == "arm64")
        {
            wingetImportJson = BuildWingetImportUtf8Json(wingetTools, imageArch);
            if (wingetImportJson.Length > 0)
            {
                jobs.Add(new ProvisionJob(
                    "winget.import",
                    ProvisionJobKind.WingetImport,
                    PackageId: "winget-import.json",
                    NeedsReboot: wingetReboot.Contains(true)));
            }
        }
        else
        {
            for (int i = 0; i < wingetTools.Count; i++)
            {
                PackageToolEntry tool = wingetTools[i];
                jobs.Add(new ProvisionJob(
                    $"winget.{tool.InstallId}",
                    ProvisionJobKind.Winget,
                    PackageId: tool.InstallId,
                    NeedsReboot: wingetReboot[i],
                    WingetArchitecture: PackageCatalog.ResolveWingetArchitectureFlag(tool, imageArch)));
            }
        }

        if (scoopTools.Count > 0)
        {
            string[] scoopIds = [.. scoopTools.Select(tool => tool.InstallId)];
            IReadOnlySet<string> scoopBuckets = catalog.ScoopBucketsForInstallIds(scoopIds);
            jobs.Add(new ProvisionJob(
                "scoop.batch",
                ProvisionJobKind.ScoopBatch,
                PackageId: string.Join(';', scoopIds),
                NeedsReboot: scoopReboot.Contains(true),
                ScoopBuckets: [.. scoopBuckets.OrderBy(b => b, StringComparer.OrdinalIgnoreCase)]));
        }

        jobs.Add(new ProvisionJob("shell.stamp", ProvisionJobKind.ShellStamp));

        if (wslEntries.Count > 0)
        {
            jobs.Add(new ProvisionJob("wsl.platform", ProvisionJobKind.WslPlatform));
        }

        for (int i = 0; i < wslEntries.Count; i++)
        {
            WslDistroEntry entry = wslEntries[i];
            IReadOnlyList<string>? assetNames = entry.FromFileAssetNamesFor(imageArch);
            jobs.Add(new ProvisionJob(
                $"wsl.{entry.InstallId}",
                ProvisionJobKind.Wsl,
                PackageId: entry.InstallId,
                NeedsReboot: wslReboot[i],
                WslInstallKind: entry.InstallKind,
                WslFromFileRepo: entry.FromFileRepo,
                WslFromFileAssetNames: assetNames is { Count: > 0 } ? assetNames : null));
        }

        if (auditStrict && auditTargets.Count > 0 && imageArch == "arm64")
        {
            jobs.Add(new ProvisionJob(
                "package.auditNative",
                ProvisionJobKind.PackageAuditNative,
                PackageId: string.Join(';', auditTargets),
                AuditStrict: true));
        }

        return Result.Ok<PackagePlanSlice, Failure>(
            new PackagePlanSlice([.. facts], [.. jobs], wingetImportJson));
    }

    private static bool SupportsArchitecture(IReadOnlyList<string> architectures, string imageArchitecture) =>
        architectures.Any(
            architecture => string.Equals(
                PackageCatalog.NormalizeArch(architecture),
                imageArchitecture,
                StringComparison.OrdinalIgnoreCase));

    private static byte[] BuildWingetImportUtf8Json(
        IReadOnlyList<PackageToolEntry> wingetTools,
        string imageArchitecture)
    {
        const string schema = "https://aka.ms/winget-packages.schema.2.0.json";
        List<WingetImportPackageFile> packages = [];
        foreach (PackageToolEntry tool in wingetTools)
        {
            string? archFlag = PackageCatalog.ResolveWingetArchitectureFlag(tool, imageArchitecture);
            packages.Add(new WingetImportPackageFile(
                tool.InstallId,
                string.IsNullOrWhiteSpace(archFlag) ? null : $"--architecture {archFlag}"));
        }

        if (packages.Count == 0)
        {
            return [];
        }

        WingetImportFile file = new(
            schema,
            DateTimeOffset.UnixEpoch,
            [
                new WingetImportSourceFile(
                    new WingetSourceDetailsFile(
                        "winget",
                        "Microsoft.Winget.Source_8wekyb3d8bbwe",
                        "https://cdn.winget.microsoft.com/cache",
                        "Microsoft.PreIndexed.Package"),
                    packages),
            ]);

        return JsonSerializer.SerializeToUtf8Bytes(file, WingetImportJsonContext.Default.WingetImportFile);
    }

    /// <summary>
    /// Packages-only WinGet Configuration YAML from import JSON package ids (schema 0.2).
    /// Null when import is absent/empty or has no package identifiers.
    /// </summary>
    internal static string? BuildWingetConfigurationYaml(byte[]? wingetImportJson)
    {
        if (wingetImportJson is not { Length: > 0 })
        {
            return null;
        }

        WingetImportFile? file = JsonSerializer.Deserialize(
            wingetImportJson,
            WingetImportJsonContext.Default.WingetImportFile);
        if (file?.Sources is null || file.Sources.Length == 0)
        {
            return null;
        }

        List<string> ids = [];
        foreach (WingetImportSourceFile source in file.Sources)
        {
            if (source.Packages is null)
            {
                continue;
            }

            foreach (WingetImportPackageFile package in source.Packages)
            {
                if (!string.IsNullOrWhiteSpace(package.PackageIdentifier))
                {
                    ids.Add(package.PackageIdentifier);
                }
            }
        }

        if (ids.Count == 0)
        {
            return null;
        }

        StringBuilder yaml = new();
        yaml.AppendLine("# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2");
        yaml.AppendLine("properties:");
        yaml.AppendLine("  resources:");
        foreach (string id in ids)
        {
            yaml.AppendLine("    - resource: Microsoft.WinGet.DSC/WinGetPackage");
            yaml.AppendLine("      directives:");
            yaml.Append("        description: Install ").AppendLine(id);
            yaml.AppendLine("      settings:");
            yaml.Append("        id: ").AppendLine(id);
            yaml.AppendLine("        source: winget");
        }

        yaml.AppendLine("  configurationVersion: 0.2.0");
        return yaml.ToString();
    }
}

internal sealed record PackagePlanSlice(
    IReadOnlyList<EffectivePackageFact> EffectivePackages,
    IReadOnlyList<ProvisionJob> Jobs,
    byte[]? WingetImportJson);
