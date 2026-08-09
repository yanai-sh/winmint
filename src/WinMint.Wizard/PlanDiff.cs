using System.Globalization;
using System.Text;
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
        foreach (string id in artifacts.RemoveProvisionedAppx)
        {
            string label = IncludedReceipt.FriendlyRemoveNames([id])[0];
            bool always = ProductPosture.AppxIds.Contains(id, StringComparer.OrdinalIgnoreCase);
            Line(sb, $"{label} ({id})", always ? "always" : "you chose");
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
            string mark = JobAlways(job) ? "always" : "you chose";
            Line(sb, JobLabel(job), mark);
        }
    }

    private static bool JobAlways(JobDescriptor job) =>
        job.Kind is "onedrive.uninstall" or "reservedStorage.disable" or "winget.import"
        || (job.Kind == "winget" && ProductPosture.WingetIdSet.Contains(job.PackageId ?? ""));

    private static string JobLabel(JobDescriptor job) =>
        job.Kind switch
        {
            "onedrive.uninstall" => "OneDrive uninstall",
            "reservedStorage.disable" => "Reserved Storage off",
            "appx.safetyNet" => "AppX safety net",
            "doh.set" => $"DNS over HTTPS ({job.PackageId})",
            "winget.import" => "Winget import (MinGit, Nilesoft Shell, …)",
            "winget" => $"Winget {job.PackageId}",
            "scoop" => $"Scoop {job.PackageId}",
            "wsl" => $"WSL {job.PackageId}",
            _ => job.Kind,
        };

    private static void Line(StringBuilder sb, string label, string mark) =>
        sb.AppendLine(CultureInfo.InvariantCulture, $"· {label} — {mark}");
}
