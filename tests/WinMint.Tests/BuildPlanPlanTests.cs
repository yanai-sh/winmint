using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class BuildPlanPlanTests
{
    [Fact]
    public void Plan_local_autologon_without_password_fails()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
                "username": "winmint"
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("account.password.required", result.Error.Code);
    }

    [Fact]
    public void Plan_dma_on_latches_ireland_and_copies_settle_target()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Contains(BuildPlan.IrelandSetupLocale, artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains($"/d {BuildPlan.IrelandSetupGeoId} ", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.DoesNotContain("windowsPE", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("oobeSystem", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("<Name>winmint</Name>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("<HideOnlineAccountScreens>true</HideOnlineAccountScreens>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        // Default requireWifiDuringOobe=true → show Network page
        Assert.Contains("<HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.True(artifacts.Account.RequireWifiDuringOobe);
        Assert.True(artifacts.Dma.Enabled);
        Assert.NotNull(artifacts.Dma.Settle);
        Assert.Equal("en-GB", artifacts.Dma.Settle.Locale);
        Assert.Equal(242, artifacts.Dma.Settle.GeoId);
        Assert.Equal("GMT Standard Time", artifacts.Dma.Settle.TimeZoneId);
        Assert.True(artifacts.Dma.Settle.LocationServicesEnabled);
    }

    [Fact]
    public void Plan_require_wifi_false_hides_wireless_oobe()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
                "username": "winmint",
                "password": "lab-only",
                "requireWifiDuringOobe": false
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.False(artifacts.Account.RequireWifiDuringOobe);
        Assert.Contains("<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("<HideOnlineAccountScreens>true</HideOnlineAccountScreens>", artifacts.Unattend.Xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_default_emits_test_lane_opcodes_without_smoke_stubs()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Equal(ImageQualityLane.Test, artifacts.Manifest.ImageQuality);
        Assert.Equal(BuildPlan.JobsSchemaVersion, artifacts.Jobs.SchemaVersion);
        Assert.DoesNotContain(artifacts.Jobs.Jobs, j => j.Kind == "stub");
        Assert.NotEmpty(artifacts.Stages.Stages);
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
            artifacts.Stages.Stages.Select(s => s.Opcode).ToArray());
        Assert.Contains(artifacts.Jobs.Jobs, j => j.Kind == "onedrive.uninstall");
        Assert.Contains(artifacts.Jobs.Jobs, j => j.Kind == "reservedStorage.disable");
        Assert.All(
            artifacts.Stages.Stages,
            stage => Assert.DoesNotContain(".ps1", string.Join('\0', stage.Parameters.Values), StringComparison.OrdinalIgnoreCase));
        ServicingStage export = Assert.Single(
            artifacts.Stages.Stages,
            s => s.Opcode == ServicingOpcode.ExportWim);
        Assert.Equal("Test", export.Parameters[StageParams.Lane]);
        Assert.Equal("fast", export.Parameters[StageParams.Compression]);
        Assert.Equal("skip", export.Parameters[StageParams.Cleanup]);
    }

    [Fact]
    public void Plan_includeSmokeStubs_emits_stub_jobs()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { IncludeSmokeStubs = true });

        Assert.True(result.IsOk);
        Assert.Contains(result.Value.Jobs.Jobs, j => j is { Kind: "stub", Id: "smoke.stub.ready" });
        Assert.Contains(result.Value.Jobs.Jobs, j => j is { Kind: "stub", Id: "smoke.stub.complete" });
    }

    [Fact]
    public void Plan_release_lane_export_params_differ_from_test()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountModeWire.LocalAutoLogon}}",
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
              }
            }
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageQuality = ImageQualityLane.Release });

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Equal(ImageQualityLane.Release, artifacts.Manifest.ImageQuality);
        ServicingStage export = Assert.Single(
            artifacts.Stages.Stages,
            s => s.Opcode == ServicingOpcode.ExportWim);
        Assert.Equal("Release", export.Parameters[StageParams.Lane]);
        Assert.Equal("max", export.Parameters[StageParams.Compression]);
        Assert.Equal("full", export.Parameters[StageParams.Cleanup]);
    }

    private static Profile Parse(string json)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(string.Join("; ", parsed.Error.Select(i => $"{i.Code}: {i.Message}")));
        }

        return parsed.Value;
    }
}
