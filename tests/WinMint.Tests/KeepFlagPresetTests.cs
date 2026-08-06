using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Ticket 15 / 25 / issue 56 — host-side keep-flag presets expand to debloat lists (not in Profile JSON).</summary>
public class KeepFlagPresetTests
{
    [Fact]
    public void Expand_acceptance_returns_pinned_acceptance_ids()
    {
        Result<KeepFlagExpansion, PlanFailure> result = KeepFlagPresets.TryExpand("acceptance");

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Equal(
            ["Microsoft.BingNews", "Microsoft.BingWeather"],
            result.Value.RemoveProvisionedAppx);
        Assert.Equal(
            ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
            result.Value.RemoveCapabilities);
        Assert.Equal(["WorkFolders-Client"], result.Value.DisableOptionalFeatures);
    }

    [Fact]
    public void Expand_empty_returns_no_ids()
    {
        Result<KeepFlagExpansion, PlanFailure> result = KeepFlagPresets.TryExpand("empty");

        Assert.True(result.IsOk);
        Assert.Empty(result.Value.RemoveProvisionedAppx);
        Assert.Empty(result.Value.RemoveCapabilities);
        Assert.Empty(result.Value.DisableOptionalFeatures);
    }

    [Fact]
    public void Expand_unknown_preset_fails()
    {
        Result<KeepFlagExpansion, PlanFailure> result = KeepFlagPresets.TryExpand("not-a-preset");

        Assert.False(result.IsOk);
        Assert.Equal("keepflag.preset.unknown", result.Error.Code);
        Assert.Contains("not-a-preset", result.Error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Expand_recommended_returns_curated_ids()
    {
        Result<KeepFlagExpansion, PlanFailure> result = KeepFlagPresets.TryExpand(KeepFlagPresets.Recommended);

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Equal(
            [
                "Microsoft.BingNews",
                "Microsoft.BingWeather",
                "Microsoft.GetHelp",
                "Microsoft.Getstarted",
                "Microsoft.MicrosoftOfficeHub",
                "Microsoft.MicrosoftSolitaireCollection",
                "Microsoft.People",
                "Microsoft.PowerAutomateDesktop",
                "Microsoft.Todos",
                "Microsoft.WindowsAlarms",
                "Microsoft.WindowsFeedbackHub",
                "Microsoft.WindowsMaps",
                "Microsoft.YourPhone",
                "Microsoft.ZuneMusic",
                "Microsoft.ZuneVideo",
                "MicrosoftCorporationII.QuickAssist",
                "Microsoft.GamingApp",
                "Microsoft.Xbox.TCUI",
                "Microsoft.XboxGamingOverlay",
                "Microsoft.XboxSpeechToTextOverlay",
                "Microsoft.Copilot",
            ],
            result.Value.RemoveProvisionedAppx);
        Assert.Equal(
            [
                "App.StepsRecorder~~~~0.0.1.0",
                "WMIC~~~~",
                "VBSCRIPT~~~~",
                "Browser.InternetExplorer~~~~0.0.11.0",
                "Microsoft.Windows.PowerShell.ISE~~~~0.0.1.0",
                "Microsoft.Wallpapers.Extended~~~~0.0.1.0",
                "Media.WindowsMediaPlayer~~~~0.0.12.0",
            ],
            result.Value.RemoveCapabilities);
        Assert.Equal(
            [
                "WorkFolders-Client",
                "WindowsMediaPlayer",
                "TelnetClient",
                "TFTP",
                "SimpleTCP",
            ],
            result.Value.DisableOptionalFeatures);
        Assert.DoesNotContain("MathRecognizer~~~~0.0.1.0", result.Value.RemoveCapabilities);
        Assert.DoesNotContain("Print.Management.Console~~~~0.0.1.0", result.Value.RemoveCapabilities);
    }

    [Fact]
    public void Expand_recommended_keep_gaming_subtracts_xbox_ids()
    {
        Result<KeepFlagExpansion, PlanFailure> result =
            KeepFlagPresets.TryExpand(KeepFlagPresets.Recommended, keepGaming: true);

        Assert.True(result.IsOk);
        Assert.DoesNotContain("Microsoft.GamingApp", result.Value.RemoveProvisionedAppx);
        Assert.DoesNotContain("Microsoft.Xbox.TCUI", result.Value.RemoveProvisionedAppx);
        Assert.DoesNotContain("Microsoft.XboxGamingOverlay", result.Value.RemoveProvisionedAppx);
        Assert.DoesNotContain("Microsoft.XboxSpeechToTextOverlay", result.Value.RemoveProvisionedAppx);
        Assert.Contains("Microsoft.YourPhone", result.Value.RemoveProvisionedAppx);
        Assert.Contains("Microsoft.Todos", result.Value.RemoveProvisionedAppx);
    }

    [Fact]
    public void Expand_recommended_keep_copilot_drops_copilot_appx()
    {
        Result<KeepFlagExpansion, PlanFailure> baseExpand =
            KeepFlagPresets.TryExpand(KeepFlagPresets.Recommended);
        Result<KeepFlagExpansion, PlanFailure> withCopilot =
            KeepFlagPresets.TryExpand(KeepFlagPresets.Recommended, keepCopilot: true);

        Assert.True(baseExpand.IsOk);
        Assert.True(withCopilot.IsOk);
        Assert.Contains("Microsoft.Copilot", baseExpand.Value.RemoveProvisionedAppx);
        Assert.DoesNotContain("Microsoft.Copilot", withCopilot.Value.RemoveProvisionedAppx);
        Assert.Equal(baseExpand.Value.RemoveCapabilities, withCopilot.Value.RemoveCapabilities);
        Assert.Equal(baseExpand.Value.DisableOptionalFeatures, withCopilot.Value.DisableOptionalFeatures);
    }

    [Fact]
    public void Compose_acceptance_preset_parses_and_plans()
    {
        Result<KeepFlagExpansion, PlanFailure> expanded = KeepFlagPresets.TryExpand(KeepFlagPresets.Acceptance);
        Assert.True(expanded.IsOk);

        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            expanded.Value.RemoveProvisionedAppx,
            [],
            [],
            [],
            [],
            [],
            [],
            expanded.Value.RemoveCapabilities,
            expanded.Value.DisableOptionalFeatures);

        byte[] utf8 = BuildPlan.SerializeProfile(profile);

        // Preset name must not appear in Profile JSON (host expands only).
        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("acceptance", json, StringComparison.OrdinalIgnoreCase);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Issues.Select(i => i.Code)));
        Assert.Equal(["Microsoft.BingNews", "Microsoft.BingWeather"], parsed.Value.RemoveProvisionedAppx);
        Assert.Equal(
            ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
            parsed.Value.RemoveCapabilities);
        Assert.Equal(["WorkFolders-Client"], parsed.Value.DisableOptionalFeatures);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "appx.safetyNet");
        Assert.DoesNotContain(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveCapabilities);
        Assert.Contains(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.DisableOptionalFeatures);
    }

    [Fact]
    public void Compose_recommended_serialize_has_no_preset_name()
    {
        Result<KeepFlagExpansion, PlanFailure> expanded =
            KeepFlagPresets.TryExpand(KeepFlagPresets.Recommended);
        Assert.True(expanded.IsOk);

        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            expanded.Value.RemoveProvisionedAppx,
            [],
            [],
            [],
            [],
            [],
            [],
            expanded.Value.RemoveCapabilities,
            expanded.Value.DisableOptionalFeatures);

        string json = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(profile));
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("recommended", json, StringComparison.OrdinalIgnoreCase);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
    }

    [Fact]
    public void Compose_empty_preset_plans_without_remove_stage()
    {
        Result<KeepFlagExpansion, PlanFailure> expanded = KeepFlagPresets.TryExpand(KeepFlagPresets.Empty);
        Assert.True(expanded.IsOk);

        Profile profile = new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            expanded.Value.RemoveProvisionedAppx,
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            []);

        byte[] utf8 = BuildPlan.SerializeProfile(profile);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk);
        Assert.Empty(parsed.Value.RemoveProvisionedAppx);

        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk);
        Assert.DoesNotContain(
            planned.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
    }

    [Fact]
    public void Acceptance_sample_profile_debloat_matches_KeepFlagPresets_Acceptance()
    {
        Result<KeepFlagExpansion, PlanFailure> expanded = KeepFlagPresets.TryExpand(KeepFlagPresets.Acceptance);
        Assert.True(expanded.IsOk, expanded.IsOk ? null : $"{expanded.Error.Code}: {expanded.Error.Message}");

        string samplePath = Path.Combine(FindRepoRoot(), "samples", "acceptance.profile.json");
        byte[] utf8 = File.ReadAllBytes(samplePath);
        string json = Encoding.UTF8.GetString(utf8);
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Issues.Select(i => i.Code)));

        Assert.Equal(expanded.Value.RemoveProvisionedAppx, parsed.Value.RemoveProvisionedAppx);
        Assert.Equal(expanded.Value.RemoveCapabilities, parsed.Value.RemoveCapabilities);
        Assert.Equal(expanded.Value.DisableOptionalFeatures, parsed.Value.DisableOptionalFeatures);
    }

    [Fact]
    public void PasswordPath_resolves_and_serialize_omits_inline_password()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-pw-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string pwFile = Path.Combine(dir, "secret.txt");
            File.WriteAllText(pwFile, "from-path\n");

            string json = $$"""
                {
                  "schemaVersion": "winmint.profile/v1",
                  "account": {
                    "mode": "localAutoLogon",
                    "username": "yanai",
                    "passwordPath": {{JsonEscape(pwFile)}},
                    "requireWifiDuringOobe": false
                  },
                  "dma": {
                    "enabled": true,
                    "settle": {
                      "locale": "en-US",
                      "geoId": 117,
                      "timeZoneId": "Israel Standard Time",
                      "locationServicesEnabled": true
                    }
                  }
                }
                """;

            Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
            Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Issues.Select(i => i.Code)));
            Assert.Equal("from-path", parsed.Value.Account.Password);
            Assert.Equal(pwFile, parsed.Value.Account.PasswordPath);

            string roundTrip = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(parsed.Value));
            Assert.Contains("passwordPath", roundTrip, StringComparison.Ordinal);
            Assert.DoesNotContain("\"password\"", roundTrip, StringComparison.Ordinal);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void PasswordPath_missing_file_fails_closed()
    {
        string missing = Path.Combine(Path.GetTempPath(), "winmint-missing-" + Guid.NewGuid().ToString("N") + ".txt");
        string json = $$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "localAutoLogon",
                "username": "yanai",
                "passwordPath": {{JsonEscape(missing)}},
                "requireWifiDuringOobe": false
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-US",
                  "geoId": 117,
                  "timeZoneId": "Israel Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """;

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        Assert.False(parsed.IsOk);
        Assert.Contains(parsed.Error.Issues, i => i.Code == "account.passwordPath.unreadable");
    }

    [Fact]
    public void Sl7_sample_matches_recommended_and_plans_packages()
    {
        Result<KeepFlagExpansion, PlanFailure> expanded =
            KeepFlagPresets.TryExpand(KeepFlagPresets.Recommended);
        Assert.True(expanded.IsOk);

        string root = FindRepoRoot();
        string scratch = Path.Combine(root, ".scratch");
        Directory.CreateDirectory(scratch);
        string pwFile = Path.Combine(scratch, "sl7.password");
        File.WriteAllText(pwFile, "lab-only-sl7");

        string cwd = Directory.GetCurrentDirectory();
        try
        {
            Directory.SetCurrentDirectory(root);
            byte[] utf8 = File.ReadAllBytes(Path.Combine(root, "samples", "sl7.profile.json"));
            string json = Encoding.UTF8.GetString(utf8);
            Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"password\"", json, StringComparison.Ordinal);

            Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
            Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Issues.Select(i => i.Code)));
            Assert.Equal("yanai", parsed.Value.Account.Username);
            Assert.Equal(expanded.Value.RemoveProvisionedAppx, parsed.Value.RemoveProvisionedAppx);
            Assert.Equal(expanded.Value.RemoveCapabilities, parsed.Value.RemoveCapabilities);
            Assert.Equal(expanded.Value.DisableOptionalFeatures, parsed.Value.DisableOptionalFeatures);
            Assert.Equal(["Anysphere.Cursor", "Zen-Team.Zen-Browser"], parsed.Value.WingetPackages);
            Assert.Equal(["FedoraLinux"], parsed.Value.WslDistros);

            Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
            Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
            Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "winget.import");
            Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == "wsl");
        }
        finally
        {
            Directory.SetCurrentDirectory(cwd);
        }
    }

    private static string JsonEscape(string path) =>
        "\"" + path.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal) + "\"";

    private static string FindRepoRoot()
    {
        string? dir = AppContext.BaseDirectory;
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir, "Justfile"))
                && Directory.Exists(Path.Combine(dir, "samples")))
            {
                return dir;
            }

            dir = Directory.GetParent(dir)?.FullName;
        }

        throw new InvalidOperationException("Repo root not found from test BaseDirectory.");
    }
}
