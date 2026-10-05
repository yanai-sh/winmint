using System.Text;
using System.Text.Json;

using WinMint.Contracts;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Issue #136 P0 — host curated defaults expand to Profile ids (no preset names).</summary>
public class CuratedDefaultsTests
{
    [Fact]
    public void TryCreate_expands_recommended_debloat_and_curated_packages()
    {
        Result<Profile, Failure> created = CuratedDefaults.TryCreate(
            new DmaSettleTarget("en-US", 244, "Pacific Standard Time", true),
            "bootstrap-secret");
        Assert.True(created.IsOk, created.IsOk ? null : $"{created.Error.Code}: {created.Error.Message}");

        Profile profile = created.Value;
        Assert.Equal(CuratedDefaults.BootstrapUsername, profile.Account.Username);
        Assert.Equal("bootstrap-secret", profile.Account.Password);
        Assert.Null(profile.Account.PasswordPath);

        Result<DebloatExpansion, Failure> recommended = DebloatPresets.TryExpand(DebloatPresets.Recommended);
        Assert.True(recommended.IsOk);
        Assert.Equal(recommended.Value.RemoveProvisionedAppx, profile.RemoveProvisionedAppx);
        Assert.Equal(recommended.Value.RemoveCapabilities, profile.RemoveCapabilities);
        Assert.Equal(recommended.Value.DisableOptionalFeatures, profile.DisableOptionalFeatures);

        Assert.Equal(["Anysphere.Cursor", "Zen-Team.Zen-Browser"], profile.WingetPackages);
        Assert.Equal(["FedoraLinux"], profile.WslDistros);
        Assert.Empty(profile.ScoopPackages);
    }

    [Fact]
    public void TryCreate_serialize_has_no_preset_name_and_plans()
    {
        Result<Profile, Failure> created = CuratedDefaults.TryCreate(
            new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true),
            "lab-only");
        Assert.True(created.IsOk);

        string json = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(created.Value));
        Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("recommended", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("C:\\Users", json, StringComparison.OrdinalIgnoreCase);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(created.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        Assert.Contains(planned.Value.EffectivePackages, p => p.ResolvedInstallId == "Anysphere.Cursor");
        Assert.Contains(planned.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.Wsl);
    }

    [Fact]
    public void TryCreate_with_password_path_omits_inline_password()
    {
        Result<Profile, Failure> created = CuratedDefaults.TryCreate(
            new DmaSettleTarget("en-US", 244, "UTC", true),
            "disk-secret",
            passwordPath: "bootstrap.password");
        Assert.True(created.IsOk);
        Assert.Null(created.Value.Account.Password);
        Assert.Equal("bootstrap.password", created.Value.Account.PasswordPath);

        using JsonDocument doc = JsonDocument.Parse(BuildPlan.SerializeProfile(created.Value));
        JsonElement account = doc.RootElement.GetProperty("account");
        Assert.False(account.TryGetProperty("password", out _));
        Assert.Equal("bootstrap.password", account.GetProperty("passwordPath").GetString());
    }

    [Fact]
    public void NewBootstrapPassword_is_non_empty_and_varies()
    {
        string a = CuratedDefaults.NewBootstrapPassword();
        string b = CuratedDefaults.NewBootstrapPassword();
        Assert.False(string.IsNullOrWhiteSpace(a));
        Assert.True(a.Length >= 20);
        Assert.NotEqual(a, b);
    }

    [Fact]
    public void TryEmit_writes_profile_and_password_without_preset_or_inline_secret()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-curated-emit-" + Guid.NewGuid().ToString("N"));
        try
        {
            Result<CuratedEmitResult, Failure> emitted = CuratedDefaults.TryEmit(
                dir,
                new DmaSettleTarget("en-US", 244, "UTC", true));
            Assert.True(emitted.IsOk, emitted.IsOk ? null : $"{emitted.Error.Code}: {emitted.Error.Message}");
            Assert.True(File.Exists(emitted.Value.ProfilePath));
            Assert.True(File.Exists(emitted.Value.PasswordPath));

            string json = File.ReadAllText(emitted.Value.ProfilePath);
            Assert.DoesNotContain("\"preset\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("recommended", json, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("\"password\"", json, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("bootstrap.password", json, StringComparison.Ordinal);
            Assert.Contains("Anysphere.Cursor", json, StringComparison.Ordinal);

            string secret = File.ReadAllText(emitted.Value.PasswordPath).Trim();
            Assert.False(string.IsNullOrEmpty(secret));
            Assert.DoesNotContain(secret, json, StringComparison.Ordinal);

            Result<Profile, IReadOnlyList<DocumentError>> loaded = ProfileFile.TryLoad(emitted.Value.ProfilePath);
            Assert.True(loaded.IsOk, loaded.IsOk ? null : string.Join("; ", loaded.Error.Select(i => i.Code)));
            Assert.Equal(secret, loaded.Value.Account.Password);
            Assert.Equal(CuratedDefaults.BootstrapUsername, loaded.Value.Account.Username);
        }
        finally
        {
            if (Directory.Exists(dir))
            {
                Directory.Delete(dir, recursive: true);
            }
        }
    }

    [Fact]
    public void SelectionLabels_name_windows_taskbar_and_curated_chips()
    {
        Assert.Equal(
            ["Windows taskbar", "Cursor", "Zen", "Fedora"],
            CuratedDefaults.SelectionLabels);
    }
}
