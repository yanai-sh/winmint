using System.Globalization;
using System.Text;

namespace WinMint.Wizard;

/// <summary>Post-Build flash strip copy (Avalonia-free). Gate B = wipe media prep, not Primary install proven.</summary>
internal static class FlashGuidance
{
    public static string Format(
        string outputIsoPath,
        bool gateB,
        string? outputIsoSha256 = null)
    {
        string iso = outputIsoPath.Trim();
        string? sha = string.IsNullOrWhiteSpace(outputIsoSha256) ? null : outputIsoSha256.Trim();

        StringBuilder sb = new();
        if (gateB)
        {
            sb.AppendLine("Gate B wipe media ready (pre-wipe ISO evidence — not a completed Primary install).");
        }
        else
        {
            sb.AppendLine("Test ISO ready (not the wipe gate).");
        }

        sb.AppendLine(CultureInfo.InvariantCulture, $"ISO: {iso}");
        sb.AppendLine("Flash with Rufus in DD Image mode (not ISO mode).");
        if (!string.IsNullOrWhiteSpace(sha))
        {
            sb.AppendLine(CultureInfo.InvariantCulture, $"SHA-256 (digests.outputIso.sha256): {sha}");
        }
        else
        {
            sb.AppendLine("Check digests.outputIso.sha256 on ImageEvidence / evidence.json.");
        }

        sb.Append("Boot expects WinPE LaunchApply, not Setup.");
        return sb.ToString();
    }
}
