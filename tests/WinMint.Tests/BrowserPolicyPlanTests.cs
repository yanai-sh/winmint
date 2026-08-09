using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class BrowserPolicyPlanTests
{
    [Fact]
    public void Plan_always_emits_edge_policy_stage_and_product_jobs()
    {
        Profile profile = Lab();

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);
        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");

        ServicingStage policies = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.StampOfflinePolicies);
        string specs = policies.Parameters[StageParams.PolicySpecs];
        Assert.Contains("HideFirstRunExperience", specs, StringComparison.Ordinal);
        Assert.Contains("DisableFileSyncNGSC", specs, StringComparison.Ordinal);
        Assert.Contains("PreventDeviceMetadataFromNetwork", specs, StringComparison.Ordinal);
        Assert.Contains("DisableWpbtExecution", specs, StringComparison.Ordinal);
        Assert.DoesNotContain("HubsSidebarEnabled", specs, StringComparison.Ordinal);
        Assert.DoesNotContain("TurnOffWindowsCopilot", specs, StringComparison.Ordinal);
        Assert.DoesNotContain("BraveRewardsDisabled", specs, StringComparison.Ordinal);

        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == "onedrive.uninstall");
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == "reservedStorage.disable");
        Assert.DoesNotContain(result.Value.Jobs.Jobs, j => j.Kind == "doh.set");

        Assert.Equal(
            [
                ServicingOpcode.MountInstallWim,
                ServicingOpcode.StampOfflinePolicies,
                ServicingOpcode.StagePayload,
                ServicingOpcode.StageOobeUnattend,
                ServicingOpcode.StampOfflineShell,
                ServicingOpcode.PatchBootWimApply,
                ServicingOpcode.ExportWim,
                ServicingOpcode.BuildIso,
            ],
            result.Value.Stages.Stages.Select(s => s.Opcode).ToArray());
    }

    [Fact]
    public void Plan_brave_winget_adds_brave_debloat_rows()
    {
        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(Lab(winget: ["Brave.Brave"]));
        Assert.True(result.IsOk);
        string specs = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.StampOfflinePolicies).Parameters[StageParams.PolicySpecs];
        Assert.Contains("BraveRewardsDisabled", specs, StringComparison.Ordinal);
        Assert.Contains("BraveAIChatEnabled", specs, StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_doh_provider_emits_doh_job_with_resolved_params()
    {
        Result<BuildArtifacts, PlanFailure> result =
            BuildPlan.Plan(Lab(policies: new PoliciesProfile(DohProvider: "cloudflare")));
        Assert.True(result.IsOk);
        JobDescriptor job = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == "doh.set");
        Assert.Equal("cloudflare", job.PackageId);
        Assert.Equal("1.1.1.1", job.DohPrimary);
        Assert.Equal("1.0.0.1", job.DohSecondary);
        Assert.Equal("https://cloudflare-dns.com/dns-query", job.DohTemplate);

        using JsonDocument doc = JsonDocument.Parse(BuildPlan.SerializeJobsDump(result.Value.Jobs));
        JsonElement dumped = Assert.Single(
            doc.RootElement.GetProperty("jobs").EnumerateArray(),
            e => e.GetProperty("kind").GetString() == "doh.set");
        Assert.Equal("1.1.1.1", dumped.GetProperty("dohPrimary").GetString());
        Assert.Equal("1.0.0.1", dumped.GetProperty("dohSecondary").GetString());
        Assert.Equal("https://cloudflare-dns.com/dns-query", dumped.GetProperty("dohTemplate").GetString());
    }

    [Fact]
    public void Serialize_doh_round_trips_without_keep_copilot()
    {
        Profile profile = Lab(policies: new PoliciesProfile(DohProvider: "quad9"));
        byte[] utf8 = BuildPlan.SerializeProfile(profile);
        using JsonDocument doc = JsonDocument.Parse(utf8);
        Assert.Equal("quad9", doc.RootElement.GetProperty("policies").GetProperty("dohProvider").GetString());
        Assert.False(doc.RootElement.GetProperty("policies").TryGetProperty("keepCopilot", out _));

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk);
        Assert.Equal("quad9", parsed.Value.EffectivePolicies.DohProvider);
    }

    [Fact]
    public void Parse_ignores_legacy_keep_copilot_json()
    {
        byte[] utf8 = """
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "localAutoLogon",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              },
              "policies": {
                "keepCopilot": true,
                "dohProvider": "google"
              }
            }
            """u8.ToArray();

        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(utf8);
        Assert.True(parsed.IsOk, parsed.IsOk ? null : parsed.Error.Issues[0].Message);
        Assert.Equal("google", parsed.Value.EffectivePolicies.DohProvider);
    }

    [Fact]
    public void Catalog_accepts_copilot_id()
    {
        Assert.Contains("Microsoft.Copilot", ProvisionedAppxCatalog.Ids);
    }

    [Fact]
    public void Pwsh_store_path_detected()
    {
        Assert.True(PwshHostGuard.IsStoreMsixPwsh(
            @"C:\Program Files\WindowsApps\Microsoft.PowerShell_7.4.0.0_arm64__8wekyb3d8bbwe\pwsh.exe"));
        Assert.False(PwshHostGuard.IsStoreMsixPwsh(
            @"C:\Program Files\PowerShell\7\pwsh.exe"));
    }

    private static Profile Lab(
        IReadOnlyList<string>? winget = null,
        PoliciesProfile? policies = null) =>
        new(
            new AccountProfile("winmint", "lab-only", RequireWifiDuringOobe: false),
            new DmaProfile(true, new DmaSettleTarget("en-GB", 242, "GMT Standard Time", true)),
            DebloatMode.Online,
            [],
            winget ?? [],
            [],
            [],
            [],
            [],
            [],
            [],
            [],
            policies);
}
