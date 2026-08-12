using System.Globalization;
using System.Text;
using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Avalonia-free vanilla→WinMint diff text from Plan artifacts.</summary>
public static class PlanDiff
{
    public static string Format(BuildArtifacts artifacts, Profile profile)
    {
        StringBuilder sb = new();
        sb.AppendLine("During image build");
        AppendOffline(sb, artifacts, profile);
        sb.AppendLine();
        sb.AppendLine("After first sign-in");
        AppendLive(sb, artifacts, profile);
        return sb.ToString().TrimEnd();
    }

    private static void AppendOffline(StringBuilder sb, BuildArtifacts artifacts, Profile profile)
    {
        bool removesAppxOffline = artifacts.Stages.Stages
            .Any(s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
        if (removesAppxOffline)
        {
            AppendAppx(sb, artifacts.RemoveProvisionedAppx);
        }

        foreach (string id in profile.RemoveCapabilities)
        {
            Line(sb, $"Capability {id}", "you chose");
        }

        foreach (string id in profile.DisableOptionalFeatures)
        {
            Line(sb, $"Optional feature {id}", "you chose");
        }

        if (artifacts.Stages.Stages.Any(s => s.Opcode == ServicingOpcode.StampOfflinePolicies))
        {
            Line(sb, "Edge / OneDrive / device metadata / WPBT policies", "always");
            if (artifacts.EffectivePackages.Any(
                package => package.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store
                    && string.Equals(
                        package.ResolvedInstallId,
                        ProductPosture.BraveWingetId,
                        StringComparison.OrdinalIgnoreCase)))
            {
                Line(sb, "Brave policies", "you chose");
            }
        }

        if (artifacts.Stages.Stages.Any(s => s.Opcode == ServicingOpcode.InjectDrivers))
        {
            Line(sb, "Surface drivers", "you chose");
        }

        Line(sb, $"Export WIM ({artifacts.Manifest.ImageQuality} lane)", "you chose");
    }

    private static void AppendLive(StringBuilder sb, BuildArtifacts artifacts, Profile profile)
    {
        if (profile.Dma.Enabled)
        {
            Line(sb, $"DMA settle {profile.Dma.Settle.Locale} / {profile.Dma.Settle.TimeZoneId}", "you chose");
        }

        foreach (ProvisionJob job in artifacts.Jobs.Jobs)
        {
            if (job.Kind is ProvisionJobKind.WingetImport)
            {
                AppendPackages(
                    sb,
                    artifacts.EffectivePackages.Where(
                        package => package.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store));
                continue;
            }

            if (job.Kind is ProvisionJobKind.ScoopBatch)
            {
                AppendPackages(
                    sb,
                    artifacts.EffectivePackages.Where(package => package.Source == EffectivePackageSource.Scoop));
                continue;
            }

            if (job.Kind is ProvisionJobKind.Winget or ProvisionJobKind.Wsl)
            {
                EffectivePackageSource source = job.Kind switch
                {
                    ProvisionJobKind.Winget => EffectivePackageSource.Winget,
                    _ => EffectivePackageSource.Wsl,
                };
                EffectivePackageFact[] packages = artifacts.EffectivePackages.Where(
                    package => (package.Source == source
                            || (source == EffectivePackageSource.Winget
                                && package.Source == EffectivePackageSource.Store))
                        && string.Equals(
                            package.ResolvedInstallId,
                            job.PackageId,
                            StringComparison.OrdinalIgnoreCase)).ToArray();
                if (packages.Length == 0)
                {
                    Line(sb, JobLabel(job), JobAlways(job) ? "always" : "you chose");
                }
                else
                {
                    AppendPackages(sb, packages);
                }
                continue;
            }

            string mark = JobAlways(job) ? "always" : "you chose";
            Line(sb, JobLabel(job), mark);
            if (job.Kind is ProvisionJobKind.AppxSafetyNet)
            {
                AppendAppx(sb, artifacts.RemoveProvisionedAppx);
            }
        }
    }

    private static bool JobAlways(ProvisionJob job) =>
        job.Kind is ProvisionJobKind.OneDriveUninstall
            or ProvisionJobKind.ReservedStorageDisable
            or ProvisionJobKind.WorkstationQuiet
            or ProvisionJobKind.AppxSafetyNet
            or ProvisionJobKind.ShellStamp;

    private static string JobLabel(ProvisionJob job) =>
        job.Kind switch
        {
            ProvisionJobKind.OneDriveUninstall => "OneDrive uninstall",
            ProvisionJobKind.ReservedStorageDisable => "Reserved Storage off",
            ProvisionJobKind.WorkstationQuiet => "Dark theme / Do Not Disturb",
            ProvisionJobKind.WslPlatform => "WSL platform",
            ProvisionJobKind.AppxSafetyNet => "AppX safety net",
            ProvisionJobKind.DohSet => $"DNS over HTTPS ({job.PackageId})",
            ProvisionJobKind.WingetImport => "Winget import",
            ProvisionJobKind.Winget => $"Winget {job.PackageId}",
            ProvisionJobKind.ScoopBatch => "Scoop batch",
            ProvisionJobKind.ShellStamp => "Shell skel stamp",
            ProvisionJobKind.Wsl => $"WSL {job.PackageId}",
            _ => job.Kind.ToWire(),
        };

    private static void AppendAppx(StringBuilder sb, IReadOnlyList<string> appx)
    {
        foreach (string id in appx)
        {
            string label = IncludedSummary.FriendlyRemoveNames([id])[0];
            bool always = ProductPosture.AppxIds.Contains(id, StringComparer.OrdinalIgnoreCase);
            Line(sb, $"{label} ({id})", always ? "always" : "you chose");
        }
    }

    private static void AppendPackages(
        StringBuilder sb,
        IEnumerable<EffectivePackageFact> packages)
    {
        foreach (EffectivePackageFact package in packages)
        {
            string manager = package.Source switch
            {
                EffectivePackageSource.Winget or EffectivePackageSource.Store => "Winget",
                EffectivePackageSource.Scoop => "Scoop",
                EffectivePackageSource.Wsl => "WSL",
                _ => throw new InvalidOperationException($"Unknown package source '{package.Source}'."),
            };
            string mark = package.Origin == EffectivePackageOrigin.ProductPosture ? "always" : "you chose";
            Line(sb, $"{manager} {package.ResolvedInstallId}", mark);
        }
    }

    private static void Line(StringBuilder sb, string label, string mark) =>
        sb.AppendLine(CultureInfo.InvariantCulture, $"· {label} — {mark}");
}
