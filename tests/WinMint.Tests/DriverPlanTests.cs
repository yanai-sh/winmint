using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Issue 63 — Surface Catalog driver injection at S1 (BuildPlan).</summary>
public class DriverPlanTests
{
    [Fact]
    public void Plan_absent_drivers_emits_no_InjectDrivers_stage()
    {
        Profile profile = Parse(MinimalJson());

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        Assert.DoesNotContain(result.Value.Stages.Stages, s => s.Opcode == ServicingOpcode.InjectDrivers);
    }

    [Fact]
    public void Plan_unknown_deviceId_fails()
    {
        Profile profile = Parse(MinimalJson(deviceId: "not-a-real-device"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("drivers.deviceId.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_unknown_deviceId_outside_catalog_fails()
    {
        Profile profile = Parse(MinimalJson(deviceId: "surface-pro-11-snapdragon"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("drivers.deviceId.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_unknown_source_fails()
    {
        Profile profile = Parse(MinimalJson(source: "customMsi", deviceId: "surface-laptop-7"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("drivers.source.unsupported", result.Error.Code);
    }

    [Fact]
    public void Plan_surface_laptop_7_emits_StampOfflinePolicies_before_InjectDrivers()
    {
        Profile profile = Parse(MinimalJson(deviceId: "surface-laptop-7"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        ServicingStage inject = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.InjectDrivers);
        Assert.Equal("surface-laptop-7", inject.Parameters[StageParams.DeviceId]);
        Assert.Equal(
            "https://www.microsoft.com/en-us/download/details.aspx?id=106120",
            inject.Parameters[StageParams.DetailsUrl]);
        Assert.DoesNotContain(".ps1", string.Join('\0', inject.Parameters.Values), StringComparison.OrdinalIgnoreCase);

        IReadOnlyList<ServicingOpcode> opcodes = result.Value.Stages.Stages.Select(s => s.Opcode).ToArray();
        int mountAt = opcodes.ToList().IndexOf(ServicingOpcode.MountInstallWim);
        int injectAt = opcodes.ToList().IndexOf(ServicingOpcode.InjectDrivers);
        int policiesAt = opcodes.ToList().IndexOf(ServicingOpcode.StampOfflinePolicies);
        int payloadAt = opcodes.ToList().IndexOf(ServicingOpcode.StagePayload);
        Assert.True(mountAt >= 0 && policiesAt > mountAt && policiesAt < injectAt && injectAt < payloadAt);
    }

    [Fact]
    public void Plan_architecture_mismatch_fails_when_run_context_set()
    {
        Profile profile = Parse(MinimalJson(deviceId: "surface-laptop-7"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { ImageArchitecture = "amd64" });

        Assert.False(result.IsOk);
        Assert.Equal("drivers.architecture.mismatch", result.Error.Code);
    }

    [Fact]
    public void Plan_windows_build_too_low_fails_when_run_context_set()
    {
        Profile profile = Parse(MinimalJson(deviceId: "surface-laptop-7"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(
            profile,
            new RunOptions { WindowsBuild = 22631 });

        Assert.False(result.IsOk);
        Assert.Equal("drivers.windowsBuild.tooLow", result.Error.Code);
    }

    [Fact]
    public void Plan_with_drivers_includes_DisableCoInstallers_in_policy_specs()
    {
        Profile profile = Parse(MinimalJson(deviceId: "surface-laptop-7"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        ServicingStage policies = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.StampOfflinePolicies);
        Assert.Contains("DisableCoInstallers", policies.Parameters[StageParams.PolicySpecs], StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_without_drivers_omits_DisableCoInstallers()
    {
        Profile profile = Parse(MinimalJson());

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        ServicingStage policies = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.StampOfflinePolicies);
        Assert.DoesNotContain("DisableCoInstallers", policies.Parameters[StageParams.PolicySpecs], StringComparison.Ordinal);
    }

    private static string MinimalJson(string? source = null, string? deviceId = null)
    {
        string drivers = "";
        if (deviceId is not null)
        {
            string src = source ?? "surfaceCatalog";
            drivers = $$"""
                  ,
                  "drivers": {
                    "source": "{{src}}",
                    "deviceId": "{{deviceId}}"
                  }
                """;
        }

        return $$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
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
              }{{drivers}}
            }
            """;
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
