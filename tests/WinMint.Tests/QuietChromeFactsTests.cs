using System.Diagnostics;
using System.Text.Json;

using WinMint.Contracts;

namespace WinMint.Tests;

/// <summary>Smoke S4 PS facts must mirror <see cref="QuietChromeFacts"/> (research Alt A adapter).</summary>
public class QuietChromeFactsTests
{
    [Fact]
    public void SmokeS4AcceptanceFacts_match_QuietChromeFacts()
    {
        string script = Path.Combine(TestRepo.Root, "tools", "vm", "SmokeS4AcceptanceFacts.ps1");
        Assert.True(File.Exists(script), script);

        string escaped = script.Replace("'", "''", StringComparison.Ordinal);
        string ps =
            ". '" + escaped + "'\n"
            + "$f = Get-WinMintSmokeS4AcceptanceFacts\n"
            + "$quiet = @()\n"
            + "foreach ($kv in $f.RequiredQuietDwords.GetEnumerator()) {\n"
            + "  $quiet += [pscustomobject]@{ Name = [string]$kv.Key; Value = [int]$kv.Value }\n"
            + "}\n"
            + "[pscustomobject]@{\n"
            + "  ExpectedWallpaperPath = [string]$f.ExpectedWallpaperPath\n"
            + "  ExpectedDevMode = [int]$f.ExpectedDevMode\n"
            + "  ExpectedSudo = [int]$f.ExpectedSudo\n"
            + "  ExpectedLongPaths = [int]$f.ExpectedLongPaths\n"
            + "  ExpectedSpotlightEnabledState = [int]$f.ExpectedSpotlightEnabledState\n"
            + "  RequiredStartPinIds = @($f.RequiredStartPinIds)\n"
            + "  RequiredTaskbarPinIds = @($f.RequiredTaskbarPinIds)\n"
            + "  RequiredQuietDwords = $quiet\n"
            + "} | ConvertTo-Json -Compress -Depth 5\n";

        using Process process = new()
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "pwsh",
                ArgumentList = { "-NoProfile", "-Command", ps },
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            },
        };
        _ = process.Start();
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(30_000), "pwsh timed out");
        Assert.True(process.ExitCode == 0, stderr + stdout);

        using JsonDocument doc = JsonDocument.Parse(stdout.Trim());
        JsonElement root = doc.RootElement;
        Assert.Equal(GuestChrome.BloomWallpaperPath, root.GetProperty("ExpectedWallpaperPath").GetString());
        Assert.Equal(QuietChromeFacts.ExpectedDevMode, root.GetProperty("ExpectedDevMode").GetInt32());
        Assert.Equal(QuietChromeFacts.ExpectedSudo, root.GetProperty("ExpectedSudo").GetInt32());
        Assert.Equal(QuietChromeFacts.ExpectedLongPaths, root.GetProperty("ExpectedLongPaths").GetInt32());
        Assert.Equal(
            QuietChromeFacts.SpotlightEnabledState,
            root.GetProperty("ExpectedSpotlightEnabledState").GetInt32());
        Assert.Equal(
            QuietChromeFacts.RequiredStartPinIds,
            [.. root.GetProperty("RequiredStartPinIds").EnumerateArray().Select(static e => e.GetString()!)]);
        Assert.Equal(
            QuietChromeFacts.RequiredTaskbarPinIds,
            [.. root.GetProperty("RequiredTaskbarPinIds").EnumerateArray().Select(static e => e.GetString()!)]);

        Dictionary<string, int> quiet = [];
        foreach (JsonElement row in root.GetProperty("RequiredQuietDwords").EnumerateArray())
        {
            quiet[row.GetProperty("Name").GetString()!] = row.GetProperty("Value").GetInt32();
        }

        Assert.Equal(QuietChromeFacts.RequiredQuietDwords.Count, quiet.Count);
        foreach ((string name, int value) in QuietChromeFacts.RequiredQuietDwords)
        {
            Assert.True(quiet.TryGetValue(name, out int got), name);
            Assert.Equal(value, got);
        }
    }
}
