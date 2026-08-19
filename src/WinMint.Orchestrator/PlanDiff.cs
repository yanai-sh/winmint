using System.Globalization;
using System.Text;

using WinMint.Contracts;

namespace WinMint.Orchestrator;

/// <summary>Vanilla-to-WinMint diff text projected only from an approved, secret-free review.</summary>
internal static class PlanDiff
{
    private static readonly Dictionary<string, string> AppxLabels =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["Microsoft.BingNews"] = "Bing News",
            ["Microsoft.BingWeather"] = "Bing Weather",
            ["Microsoft.GetHelp"] = "Get Help",
            ["Microsoft.Getstarted"] = "Get Started",
            ["Microsoft.MicrosoftOfficeHub"] = "Office Hub",
            ["Microsoft.MicrosoftSolitaireCollection"] = "Solitaire",
            ["Microsoft.People"] = "People",
            ["Microsoft.PowerAutomateDesktop"] = "Power Automate",
            ["Microsoft.Todos"] = "To Do",
            ["Microsoft.WindowsAlarms"] = "Alarms",
            ["Microsoft.WindowsFeedbackHub"] = "Feedback Hub",
            ["Microsoft.WindowsMaps"] = "Maps",
            ["Microsoft.YourPhone"] = "Phone Link",
            ["Microsoft.ZuneMusic"] = "Zune Music",
            ["Microsoft.ZuneVideo"] = "Movies & TV",
            ["MicrosoftCorporationII.QuickAssist"] = "Quick Assist",
            ["Microsoft.GamingApp"] = "Xbox app",
            ["Microsoft.Xbox.TCUI"] = "Xbox TCUI",
            ["Microsoft.XboxGamingOverlay"] = "Game Bar",
            ["Microsoft.XboxSpeechToTextOverlay"] = "Xbox speech overlay",
            ["Microsoft.Copilot"] = "Copilot",
        };

    internal static string Format(HostReview review)
    {
        ArgumentNullException.ThrowIfNull(review);
        StringBuilder sb = new();
        sb.AppendLine("During image build");
        AppendOffline(sb, review);
        sb.AppendLine();
        sb.AppendLine("After first sign-in");
        AppendLive(sb, review);
        return sb.ToString().TrimEnd();
    }

    internal static IReadOnlyList<string> FriendlyRemoveNames(IEnumerable<string> appxFamilyIds) =>
        [.. appxFamilyIds.Select(FriendlyRemoveName)];

    private static void AppendOffline(StringBuilder sb, HostReview review)
    {
        Profile profile = review.AuthoredProfile;
        if (review.Stages.Contains(ServicingOpcode.RemoveProvisionedAppx))
        {
            AppendAppx(sb, review.RemoveProvisionedAppx);
        }

        foreach (string id in profile.RemoveCapabilities)
        {
            Line(sb, $"Capability {id}", "you chose");
        }

        foreach (string id in profile.DisableOptionalFeatures)
        {
            Line(sb, $"Optional feature {id}", "you chose");
        }

        if (review.Stages.Contains(ServicingOpcode.StampOfflinePolicies))
        {
            Line(sb, "Edge / OneDrive / device metadata / WPBT policies", "always");
            if (review.BraveSelected)
            {
                Line(sb, "Brave policies", "you chose");
            }
        }

        if (review.Stages.Contains(ServicingOpcode.InjectDrivers))
        {
            Line(sb, "Surface drivers", "you chose");
        }

        Line(sb, $"Export WIM ({review.ImageQuality} lane)", "you chose");
    }

    private static void AppendLive(StringBuilder sb, HostReview review)
    {
        Profile profile = review.AuthoredProfile;
        if (profile.Dma.Enabled)
        {
            Line(sb, $"DMA settle {profile.Dma.Settle.Locale} / {profile.Dma.Settle.TimeZoneId}", "you chose");
        }

        foreach (ProvisionJob job in review.Jobs)
        {
            if (job.Kind is ProvisionJobKind.WingetImport)
            {
                AppendPackages(
                    sb,
                    review.EffectivePackages.Where(static package =>
                        package.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store));
                continue;
            }

            if (job.Kind is ProvisionJobKind.ScoopBatch)
            {
                AppendPackages(
                    sb,
                    review.EffectivePackages.Where(static package =>
                        package.Source == EffectivePackageSource.Scoop));
                continue;
            }

            if (job.Kind is ProvisionJobKind.Winget or ProvisionJobKind.Wsl)
            {
                EffectivePackageSource source = job.Kind == ProvisionJobKind.Winget
                    ? EffectivePackageSource.Winget
                    : EffectivePackageSource.Wsl;
                EffectivePackageFact[] packages = [.. review.EffectivePackages.Where(
                    package => (package.Source == source
                            || (source == EffectivePackageSource.Winget
                                && package.Source == EffectivePackageSource.Store))
                        && string.Equals(
                            package.ResolvedInstallId,
                            job.PackageId,
                            StringComparison.OrdinalIgnoreCase))];
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

            Line(sb, JobLabel(job), JobAlways(job) ? "always" : "you chose");
            if (job.Kind is ProvisionJobKind.AppxSafetyNet)
            {
                AppendAppx(sb, review.RemoveProvisionedAppx);
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
            bool always = ProductPosture.AppxIds.Contains(id, StringComparer.OrdinalIgnoreCase);
            Line(sb, $"{FriendlyRemoveName(id)} ({id})", always ? "always" : "you chose");
        }
    }

    private static void AppendPackages(StringBuilder sb, IEnumerable<EffectivePackageFact> packages)
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

    private static string FriendlyRemoveName(string appxFamilyId)
    {
        if (AppxLabels.TryGetValue(appxFamilyId, out string? label))
        {
            return label;
        }

        int dot = appxFamilyId.LastIndexOf('.');
        return dot >= 0 && dot < appxFamilyId.Length - 1
            ? appxFamilyId[(dot + 1)..]
            : appxFamilyId;
    }

    private static void Line(StringBuilder sb, string label, string mark) =>
        sb.AppendLine(CultureInfo.InvariantCulture, $"· {label} — {mark}");
}
