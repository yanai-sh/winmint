using System.Globalization;
using System.Text;
using System.Text.Json;
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
            if (ProductPosture.MergeWinget(profile.WingetPackages)
                .Any(id => string.Equals(id, ProductPosture.BraveWingetId, StringComparison.OrdinalIgnoreCase)))
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

        foreach (JobDescriptor job in artifacts.Jobs.Jobs)
        {
            if (job.Kind is ProvisionJobKind.WingetImport)
            {
                AppendWingetImport(sb, artifacts, profile);
                continue;
            }

            if (job.Kind is ProvisionJobKind.ScoopBatch)
            {
                AppendScoopBatch(sb, job, profile);
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

    private static bool JobAlways(JobDescriptor job) =>
        job.Kind is ProvisionJobKind.OneDriveUninstall
            or ProvisionJobKind.ReservedStorageDisable
            or ProvisionJobKind.WorkstationQuiet
            or ProvisionJobKind.AppxSafetyNet
            or ProvisionJobKind.WingetImport
            or ProvisionJobKind.ShellStamp
        || (job.Kind is ProvisionJobKind.Winget && ProductPosture.WingetIdSet.Contains(job.PackageId ?? ""))
        || (job.Kind is ProvisionJobKind.Scoop && ProductPosture.ScoopIdSet.Contains(job.PackageId ?? ""));

    private static string JobLabel(JobDescriptor job) =>
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
            ProvisionJobKind.Scoop => $"Scoop {job.PackageId}",
            ProvisionJobKind.ScoopBatch => "Scoop batch",
            ProvisionJobKind.ShellStamp => "Shell skel stamp",
            ProvisionJobKind.Wsl => $"WSL {job.PackageId}",
            _ => job.Kind.ToWire(),
        };

    private static void AppendAppx(StringBuilder sb, IReadOnlyList<string> appx)
    {
        foreach (string id in appx)
        {
            string label = IncludedReceipt.FriendlyRemoveNames([id])[0];
            bool always = ProductPosture.AppxIds.Contains(id, StringComparer.OrdinalIgnoreCase);
            Line(sb, $"{label} ({id})", always ? "always" : "you chose");
        }
    }

    private static void AppendWingetImport(StringBuilder sb, BuildArtifacts artifacts, Profile profile)
    {
        foreach (string id in ImportPackageIds(artifacts.WingetImportJson)
            ?? ProductPosture.MergeWinget(profile.WingetPackages))
        {
            string mark = ProductPosture.WingetIdSet.Contains(id) ? "always" : "you chose";
            Line(sb, $"Winget {id}", mark);
        }
    }

    private static void AppendScoopBatch(StringBuilder sb, JobDescriptor job, Profile profile)
    {
        IEnumerable<string> ids = string.IsNullOrWhiteSpace(job.PackageId)
            ? ProductPosture.MergeScoop(profile.ScoopPackages)
            : job.PackageId.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        foreach (string id in ids)
        {
            string mark = ProductPosture.ScoopIdSet.Contains(id) ? "always" : "you chose";
            Line(sb, $"Scoop {id}", mark);
        }
    }

    private static string[]? ImportPackageIds(byte[]? json)
    {
        if (json is not { Length: > 0 })
        {
            return null;
        }

        using JsonDocument document = JsonDocument.Parse(json);
        return document.RootElement
            .GetProperty("Sources")[0]
            .GetProperty("Packages")
            .EnumerateArray()
            .Select(package => package.GetProperty("PackageIdentifier").GetString())
            .OfType<string>()
            .ToArray();
    }

    private static void Line(StringBuilder sb, string label, string mark) =>
        sb.AppendLine(CultureInfo.InvariantCulture, $"· {label} — {mark}");
}
