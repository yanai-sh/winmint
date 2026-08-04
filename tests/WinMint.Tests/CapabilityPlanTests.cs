using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Ticket 20 — capabilities / optional features at S1 + S2.</summary>
public class CapabilityPlanTests
{
    [Fact]
    public void Plan_unknown_capability_fails()
    {
        Profile profile = Parse(MinimalJson(capabilities: ["Not.A.Real.Capability~~~~0.0.1.0"]));

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("debloat.removeCapabilities.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_unknown_optional_feature_fails()
    {
        Profile profile = Parse(MinimalJson(features: ["NotARealFeature"]));

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("debloat.disableOptionalFeatures.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_known_capability_and_feature_emit_opcodes_before_payload()
    {
        Profile profile = Parse(MinimalJson(
            capabilities: ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
            features: ["WorkFolders-Client"]));

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        ServicingStage caps = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveCapabilities);
        Assert.Equal(
            "App.StepsRecorder~~~~0.0.1.0;WMIC~~~~",
            caps.Parameters[StageParams.CapabilityNames]);
        ServicingStage feats = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.DisableOptionalFeatures);
        Assert.Equal("WorkFolders-Client", feats.Parameters[StageParams.FeatureNames]);

        IReadOnlyList<ServicingOpcode> opcodes = result.Value.Stages.Stages.Select(s => s.Opcode).ToArray();
        int mountAt = opcodes.ToList().IndexOf(ServicingOpcode.MountInstallWim);
        int capAt = opcodes.ToList().IndexOf(ServicingOpcode.RemoveCapabilities);
        int featAt = opcodes.ToList().IndexOf(ServicingOpcode.DisableOptionalFeatures);
        int payloadAt = opcodes.ToList().IndexOf(ServicingOpcode.StagePayload);
        Assert.True(mountAt >= 0 && capAt > mountAt && featAt > capAt && featAt < payloadAt);
    }

    [Fact]
    public void Apply_injects_mountDir_for_capability_and_feature_stages()
    {
        BuildArtifacts plan = PlanWith(
            capabilities: ["App.StepsRecorder~~~~0.0.1.0"],
            features: ["WorkFolders-Client"]);
        string work = Path.Combine(Path.GetTempPath(), "winmint-s2-cap-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            RecordingElevatedPlanRunner runner = new();
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: Path.Combine(work, "out.iso"));
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, ServicingFailure> result = ImageServicing.Apply(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            ServicingStage caps = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.RemoveCapabilities);
            Assert.Equal(ImageServicing.HostMountDir, caps.Parameters[StageParams.MountDir]);
            Assert.Equal(work, caps.Parameters[StageParams.WorkDirectory]);
            ServicingStage feats = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.DisableOptionalFeatures);
            Assert.Equal(ImageServicing.HostMountDir, feats.Parameters[StageParams.MountDir]);
        }
        finally
        {
            try
            {
                if (Directory.Exists(work))
                {
                    Directory.Delete(work, recursive: true);
                }
            }
            catch
            {
                // ponytail: temp cleanup best-effort
            }
        }
    }

    private static BuildArtifacts PlanWith(string[] capabilities, string[] features)
    {
        Profile profile = Parse(MinimalJson(capabilities, features));
        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        return planned.Value;
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

    private static string MinimalJson(
        IReadOnlyList<string>? capabilities = null,
        IReadOnlyList<string>? features = null)
    {
        List<string> debloatFields = [];
        if (capabilities is not null)
        {
            debloatFields.Add(
                $"\"removeCapabilities\": [{string.Join(",", capabilities.Select(id => $"\"{id}\""))}]");
        }

        if (features is not null)
        {
            debloatFields.Add(
                $"\"disableOptionalFeatures\": [{string.Join(",", features.Select(id => $"\"{id}\""))}]");
        }

        string debloatBody = debloatFields.Count == 0
            ? ""
            : string.Join(",\n                ", debloatFields) + ",";

        return $$"""
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
              },
              "debloat": {
                {{debloatBody}}
                "removeProvisionedAppx": []
              }
            }
            """;
    }

    private sealed class RecordingElevatedPlanRunner : IElevatedPlanRunner
    {
        public List<ServicingStage> Stages { get; } = [];

        public Result<ImageEvidence, ServicingFailure> Execute(
            string workDirectory,
            IReadOnlyList<ServicingStage> stages,
            ServicingRun run,
            BuildArtifacts plan,
            CancellationToken ct)
        {
            Stages.AddRange(stages);
            string shellTarget = stages
                .First(s => s.Opcode == ServicingOpcode.StampOfflineShell)
                .Parameters[StageParams.ShellTarget];
            return Result.Ok<ImageEvidence, ServicingFailure>(
                new ImageEvidence(
                    run.OutputIsoPath ?? Path.Combine(workDirectory, "out.iso"),
                    plan.Manifest.ImageQuality,
                    shellTarget,
                    new Dictionary<string, string>(StringComparer.Ordinal)));
        }
    }
}
