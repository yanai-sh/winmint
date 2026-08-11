using System.Globalization;
using System.Text;
using System.Text.Json;

namespace WinMint.Wizard;

/// <summary>Post-Build flash strip copy (Avalonia-free). Gate B = wipe media prep, not Primary install proven.</summary>
internal static class FlashGuidance
{
    public static string Format(
        string outputIsoPath,
        string workDirectory,
        bool gateB,
        string? outputIsoSha256 = null)
    {
        string iso = outputIsoPath.Trim();
        string work = workDirectory.Trim();
        string evidence = Path.Combine(work, "evidence.json");
        string? sha = string.IsNullOrWhiteSpace(outputIsoSha256)
            ? TryReadOutputIsoSha256(work)
            : outputIsoSha256.Trim();

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
            sb.AppendLine(CultureInfo.InvariantCulture, $"Check digests.outputIso.sha256 in: {evidence}");
        }

        sb.Append("Boot expects WinPE LaunchApply, not Setup.");
        return sb.ToString();
    }

    public static string? TryReadOutputIsoSha256(string workDirectory)
    {
        string evidencePath = Path.Combine(
            workDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            "evidence.json");
        if (!File.Exists(evidencePath))
        {
            return null;
        }

        try
        {
            using FileStream stream = File.OpenRead(evidencePath);
            using JsonDocument doc = JsonDocument.Parse(stream);
            if (!doc.RootElement.TryGetProperty("digests", out JsonElement digests))
            {
                return null;
            }

            if (!digests.TryGetProperty("outputIso.sha256", out JsonElement shaEl))
            {
                return null;
            }

            string? sha = shaEl.GetString();
            return string.IsNullOrWhiteSpace(sha) ? null : sha.Trim();
        }
        catch (JsonException)
        {
            return null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }
}
