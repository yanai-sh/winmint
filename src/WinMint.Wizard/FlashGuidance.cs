using System.Globalization;
using System.Text;

using WinMint.Orchestrator;

namespace WinMint.Wizard;

/// <summary>Post-build copy. The current Output ISO is unstable install media (ADR-018).</summary>
internal static class FlashGuidance
{
    public static string Format(
        string outputIsoPath,
        bool gateB,
        string? outputIsoSha256 = null) =>
        Format(outputIsoPath, gateB, ImageQualityLane.Test, packageStrict: false, outputIsoSha256);

    public static string Format(
        string outputIsoPath,
        HostReview review,
        string? outputIsoSha256 = null) =>
        Format(
            outputIsoPath,
            review.IsGateB,
            review.ImageQuality,
            review.PackageStrict,
            outputIsoSha256);

    public static string Format(
        string outputIsoPath,
        bool gateB,
        ImageQualityLane lane,
        bool packageStrict,
        string? outputIsoSha256 = null)
    {
        string iso = outputIsoPath.Trim();
        string? sha = string.IsNullOrWhiteSpace(outputIsoSha256) ? null : outputIsoSha256.Trim();

        StringBuilder sb = new();
        sb.AppendLine("Unstable. Do not write this ISO to USB. Do not boot it. Do not install from it.");
        sb.AppendLine("Live posture: post-install/Apply-LivePosture.ps1");
        sb.AppendLine(CultureInfo.InvariantCulture, $"Build: lane={lane}; packageStrict={packageStrict}; gateB={gateB}.");
        sb.AppendLine(CultureInfo.InvariantCulture, $"ISO: {iso}");
        if (!string.IsNullOrWhiteSpace(sha))
        {
            sb.Append(CultureInfo.InvariantCulture, $"SHA-256 (digests.outputIso.sha256): {sha}");
        }
        else
        {
            sb.Append("Check digests.outputIso.sha256 on ImageEvidence / evidence.json.");
        }

        return sb.ToString();
    }
}
