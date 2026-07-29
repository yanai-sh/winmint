using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class BuildPlanPlanTests
{
    [Fact]
    public void Plan_local_autologon_without_password_fails()
    {
        Profile profile = Parse("""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "localAutoLogon",
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

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("account.password.required", result.Error.Code);
    }

    [Fact]
    public void Plan_dma_on_latches_ireland_and_copies_settle_target()
    {
        Profile profile = Parse("""
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
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Contains(BuildPlan.IrelandSetupLocale, artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains($"/d {BuildPlan.IrelandSetupGeoId} ", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.True(artifacts.Dma.Enabled);
        Assert.NotNull(artifacts.Dma.Settle);
        Assert.Equal("en-GB", artifacts.Dma.Settle.Locale);
        Assert.Equal(242, artifacts.Dma.Settle.GeoId);
        Assert.Equal("GMT Standard Time", artifacts.Dma.Settle.TimeZoneId);
        Assert.True(artifacts.Dma.Settle.LocationServicesEnabled);
    }

    [Fact]
    public void Plan_default_emits_test_lane_stub_jobs_and_opcodes()
    {
        Profile profile = Parse("""
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
              }
            }
            """);

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.Equal(ImageQualityLane.Test, artifacts.Manifest.ImageQuality);
        Assert.Equal(BuildPlan.JobsSchemaVersion, artifacts.Jobs.SchemaVersion);
        Assert.Contains(artifacts.Jobs.Jobs, j => j.Kind == "stub");
        Assert.NotEmpty(artifacts.Stages.Stages);
        Assert.Equal(
            [
                ServicingOpcode.MountInstallWim,
                ServicingOpcode.StagePayload,
                ServicingOpcode.InjectUnattend,
                ServicingOpcode.StampOfflineShell,
                ServicingOpcode.ExportWim,
                ServicingOpcode.BuildIso,
            ],
            artifacts.Stages.Stages.Select(s => s.Opcode).ToArray());
        Assert.All(
            artifacts.Stages.Stages,
            stage => Assert.DoesNotContain(".ps1", string.Join('\0', stage.Parameters.Values), StringComparison.OrdinalIgnoreCase));
    }

    private static Profile Parse(string json)
    {
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(string.Join("; ", parsed.Error.Issues.Select(i => $"{i.Code}: {i.Message}")));
        }

        return parsed.Value;
    }
}
