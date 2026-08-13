using System.Diagnostics;
using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 20 — capabilities / optional features at S1 + S2.</summary>
[Collection(ElevatedServicingPlanDefinition.Name)]
public class CapabilityPlanTests
{
    [Fact]
    public void Plan_unknown_capability_fails()
    {
        Profile profile = Parse(MinimalJson(capabilities: ["Not.A.Real.Capability~~~~0.0.1.0"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("debloat.removeCapabilities.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_unknown_optional_feature_fails()
    {
        Profile profile = Parse(MinimalJson(features: ["NotARealFeature"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("debloat.disableOptionalFeatures.unknown", result.Error.Code);
    }

    [Fact]
    public void Plan_known_capability_and_feature_emit_opcodes_before_payload()
    {
        Profile profile = Parse(MinimalJson(
            capabilities: ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
            features: ["WorkFolders-Client"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        ServicingStage caps = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.RemoveCapabilities);
        Assert.Empty(caps.Parameters);
        Assert.Equal(
            ["App.StepsRecorder~~~~0.0.1.0", "WMIC~~~~"],
            result.Value.RemoveCapabilities);
        ServicingStage feats = Assert.Single(
            result.Value.Stages.Stages,
            s => s.Opcode == ServicingOpcode.DisableOptionalFeatures);
        Assert.Empty(feats.Parameters);
        Assert.Equal(["WorkFolders-Client"], result.Value.DisableOptionalFeatures);

        IReadOnlyList<ServicingOpcode> opcodes = result.Value.Stages.Stages.Select(s => s.Opcode).ToArray();
        int mountAt = opcodes.ToList().IndexOf(ServicingOpcode.MountInstallWim);
        int capAt = opcodes.ToList().IndexOf(ServicingOpcode.RemoveCapabilities);
        int featAt = opcodes.ToList().IndexOf(ServicingOpcode.DisableOptionalFeatures);
        int payloadAt = opcodes.ToList().IndexOf(ServicingOpcode.StagePayload);
        Assert.True(mountAt >= 0 && capAt > mountAt && featAt > capAt && featAt < payloadAt);
    }

    [Fact]
    public async Task Apply_injects_mountDir_for_capability_and_feature_stages()
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

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
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
            Assert.Equal("capability", caps.Parameters[StageParams.Kind]);
            Assert.Equal(
                Path.Combine(work, ServicingWorkspace.PayloadDirectoryName, ServicingWorkspace.CapabilityNamesFileName),
                caps.Parameters[StageParams.NamesPath]);
            ServicingStage feats = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.DisableOptionalFeatures);
            Assert.Equal(ImageServicing.HostMountDir, feats.Parameters[StageParams.MountDir]);
            Assert.Equal("feature", feats.Parameters[StageParams.Kind]);
            Assert.Equal(
                Path.Combine(work, ServicingWorkspace.PayloadDirectoryName, ServicingWorkspace.FeatureNamesFileName),
                feats.Parameters[StageParams.NamesPath]);
            Assert.Equal(
                ["App.StepsRecorder~~~~0.0.1.0"],
                JsonSerializer.Deserialize<string[]>(
                    File.ReadAllBytes(caps.Parameters[StageParams.NamesPath]))!);
            Assert.Equal(
                ["WorkFolders-Client"],
                JsonSerializer.Deserialize<string[]>(
                    File.ReadAllBytes(feats.Parameters[StageParams.NamesPath]))!);
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

    [Fact]
    public void InvokeServicingPlan_merges_capability_and_feature_side_digests_into_evidence()
    {
        string work = Path.Combine(Path.GetTempPath(), "winmint-s2-cap-digests-" + Guid.NewGuid().ToString("N"));
        string logs = Path.Combine(work, "logs");
        Directory.CreateDirectory(logs);
        try
        {
            string runPlan = PrepareSuccessfulServicingFinalizer(work);
            File.WriteAllText(
                Path.Combine(logs, "digests.json"),
                """{"removed.capability.App.StepsRecorder~~~~0.0.1.0":"Absent","removed.capability.WMIC~~~~":"Absent","disabled.feature.WorkFolders-Client":"Disabled"}""");

            ProcessStartInfo psi = new()
            {
                FileName = "pwsh",
                ArgumentList = { "-NoProfile", "-File", runPlan, "-WorkDirectory", work },
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            psi.Environment["ProgramData"] = Path.Combine(work, "programdata");
            using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
            string stdout = p.StandardOutput.ReadToEnd();
            string stderr = p.StandardError.ReadToEnd();
            Assert.True(p.WaitForExit(60_000), "Invoke-ServicingPlan timed out");
            Assert.True(p.ExitCode == 0, $"exit={p.ExitCode}\nstdout={stdout}\nstderr={stderr}");

            string digestPath = Path.Combine(work, "logs", "digests.json");
            Assert.True(File.Exists(digestPath), "expected digests.json");
            string json = File.ReadAllText(digestPath);
            Assert.Contains("removed.capability.App.StepsRecorder~~~~0.0.1.0", json, StringComparison.Ordinal);
            Assert.Contains("removed.capability.WMIC~~~~", json, StringComparison.Ordinal);
            Assert.Contains("disabled.feature.WorkFolders-Client", json, StringComparison.Ordinal);
            Assert.Contains("\"Absent\"", json, StringComparison.Ordinal);
            Assert.Contains("\"Disabled\"", json, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }


    private static void TryDelete(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // ponytail: best-effort temp cleanup
        }
    }

    private static BuildArtifacts PlanWith(string[] capabilities, string[] features)
    {
        Profile profile = Parse(MinimalJson(capabilities, features));
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        return planned.Value;
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
              },
              "debloat": {
                {{debloatBody}}
                "removeProvisionedAppx": []
              }
            }
            """;
    }
}
