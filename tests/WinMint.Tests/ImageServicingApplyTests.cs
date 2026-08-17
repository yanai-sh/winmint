using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

public class ImageServicingApplyTests
{
    [Fact]
    public async Task Apply_requires_output_iso_path()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            RecordingElevatedPlanRunner runner = new();
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: "");
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.False(result.IsOk);
            Assert.Equal("servicing.outputIso.missing", result.Error.Code);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_runs_stages_in_plan_order_with_shell_stamp_param()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
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
                runner.Opcodes.ToArray());
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.StampOfflinePolicies
                    && s.Parameters.TryGetValue(StageParams.PoliciesPath, out string? policiesPath)
                    && policiesPath == Path.Combine(work, ServicingWorkspace.PayloadDirectoryName, ServicingWorkspace.PoliciesFileName)
                    && s.Parameters.TryGetValue(StageParams.MountDir, out string? polMount)
                    && polMount == ImageServicing.HostMountDir
                    && s.Parameters.TryGetValue(StageParams.WorkDirectory, out string? polWork)
                    && polWork == work);
            string policiesJson = File.ReadAllText(
                Path.Combine(work, ServicingWorkspace.PayloadDirectoryName, ServicingWorkspace.PoliciesFileName));
            Assert.Contains("HideFirstRunExperience", policiesJson, StringComparison.Ordinal);
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.StampOfflineShell
                    && s.Parameters.TryGetValue(StageParams.ShellTarget, out string? target)
                    && !string.IsNullOrWhiteSpace(target));
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.ExportWim
                    && s.Parameters.TryGetValue(StageParams.Lane, out string? lane)
                    && lane == "Test"
                    && s.Parameters.TryGetValue(StageParams.Compression, out string? compression)
                    && compression == "fast"
                    && s.Parameters.TryGetValue(StageParams.Cleanup, out string? cleanup)
                    && cleanup == "skip");
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.MountInstallWim
                    && !s.Parameters.ContainsKey("reuseMedia")
                    && s.Parameters.TryGetValue(StageParams.WorkDirectory, out string? mountWork)
                    && mountWork == work);
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.ExportWim
                    && s.Parameters.TryGetValue(StageParams.WorkDirectory, out string? exportWork)
                    && exportWork == work);
            Assert.False(string.IsNullOrWhiteSpace(result.Value.ShellStampTargetPath));
            Assert.Equal(ImageQualityLane.Test, result.Value.Lane);
            Assert.Equal(ImageServicing.ShellStampGuestPath, result.Value.ShellStampTargetPath);
            Assert.Equal(new string('a', 64), result.Value.Digests["outputIso.sha256"]);
            Assert.True(File.Exists(Path.Combine(work, "payload", "SetupComplete.cmd")));
            string stagedSetup = File.ReadAllText(Path.Combine(work, "payload", "SetupComplete.cmd"));
            string repoSetup = File.ReadAllText(
                Path.Combine(TestRepo.Root, "payload", "scripts", "SetupComplete.cmd"));
            Assert.Equal(repoSetup, stagedSetup);
            Assert.DoesNotContain("dism.exe", stagedSetup, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("wscript", stagedSetup, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("powershell", stagedSetup, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("start /min", stagedSetup, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("Supervisor.exe", stagedSetup, StringComparison.Ordinal);
            Assert.Contains("--machine-setup", stagedSetup, StringComparison.Ordinal);
            Assert.True(File.Exists(Path.Combine(work, "payload", "bundle.json")));
            Assert.True(File.Exists(Path.Combine(work, "payload", "Supervisor.exe")));
            Assert.True(File.Exists(Path.Combine(work, "payload", "WinMintApply.exe")));
            string bundle = File.ReadAllText(Path.Combine(work, "payload", "bundle.json"));
            Assert.Contains(ImageServicing.BundleSchemaVersion, bundle, StringComparison.Ordinal);
            Assert.Contains("username", bundle, StringComparison.Ordinal);
            Assert.Contains("winmint", bundle, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_policy_payload_json_round_trips_semicolon_pipe_and_tilde_in_data()
    {
        const string data = "semi;pipe|tilde~~~~end";
        BuildArtifacts plan = MinimalPlan() with
        {
            OfflinePolicies =
            [
                new OfflinePolicyRow(
                    "SOFTWARE",
                    @"Policies\WinMint\Punctuation",
                    "Example",
                    "REG_SZ",
                    data,
                    "edge"),
            ],
        };
        string work = NewTempDir();
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
            string policiesPath = Path.Combine(
                work,
                ServicingWorkspace.PayloadDirectoryName,
                ServicingWorkspace.PoliciesFileName);
            Assert.True(File.Exists(policiesPath), "Materialize must write payload/policies.json");
            using JsonDocument doc = JsonDocument.Parse(File.ReadAllBytes(policiesPath));
            JsonElement row = Assert.Single(doc.RootElement.EnumerateArray());
            Assert.Equal(data, row.GetProperty("data").GetString());
            Assert.Equal("policy.edge.Example", row.GetProperty("digest").GetString());
            Assert.Equal("edge", row.GetProperty("family").GetString());
            ServicingStage stage = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.StampOfflinePolicies);
            Assert.Equal(policiesPath, stage.Parameters[StageParams.PoliciesPath]);
            Assert.False(stage.Parameters.ContainsKey("policySpecs"));
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_omits_reuseMedia_from_MountInstallWim()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
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
            ServicingStage mount = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.MountInstallWim);
            Assert.False(mount.Parameters.ContainsKey("reuseMedia"));
            Assert.False(typeof(ServicingRun).GetProperty("ReuseMedia") is not null);
            Assert.False(typeof(StageParams).GetField("ReuseMedia") is not null);
            Assert.True(mount.Parameters.ContainsKey(StageParams.SourceIsoSha256));
            Assert.True(mount.Parameters.ContainsKey(StageParams.SourceIsoLength));
            Assert.Equal(
                PreparedMediaIdentity.CurrentSchema.ToString(System.Globalization.CultureInfo.InvariantCulture),
                mount.Parameters[StageParams.CacheSchema]);
            Assert.Equal(PreparedMediaIdentity.Root, mount.Parameters[StageParams.CacheRoot]);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_keeps_prepared_media_fields_off_typed_evidence()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            string outputIso = Path.Combine(work, "out.iso");
            File.WriteAllText(
                Path.Combine(work, "prepared-media.json"),
                JsonSerializer.Serialize(new Dictionary<string, object?>
                {
                    ["schemaVersion"] = ImageServicing.PreparedMediaAuditSchemaVersion,
                    ["source.isoSha256"] = new string('b', 64),
                    ["mediaCache.outcome"] = "hit",
                    ["timings.mountMs"] = 4,
                    ["mediaCache.previousMedia"] = Path.Combine(work, "media.previous-x"),
                }));
            RecordingElevatedPlanRunner runner = new();
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: outputIso);
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            Assert.Equal(ImageQualityLane.Test, result.Value.Lane);
            Assert.False(result.Value.Digests.ContainsKey("source.isoSha256"));
            Assert.False(result.Value.Digests.ContainsKey("mediaCache.outcome"));
            using JsonDocument evidence = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(work, "evidence.json")));
            Assert.Equal("hit", evidence.RootElement.GetProperty("mediaCache.outcome").GetString());
            Assert.False(evidence.RootElement.TryGetProperty("mediaCache.previousMedia", out _));
            Assert.Equal(new string('a', 64), result.Value.Digests["outputIso.sha256"]);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_recreates_payload_before_writing_current_bundle()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            string leftover = Path.Combine(work, "payload", "from-run-a.txt");
            Directory.CreateDirectory(Path.GetDirectoryName(leftover)!);
            File.WriteAllText(leftover, "run-a-only");
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
            Assert.False(File.Exists(leftover));
            Assert.True(File.Exists(Path.Combine(work, "payload", "bundle.json")));
            Assert.True(File.Exists(Path.Combine(work, "payload", "jobs.json")));
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Theory]
    [InlineData(ImageQualityLane.Test, "Test", "fast", "skip")]
    [InlineData(ImageQualityLane.Release, "Release", "max", "full")]
    public async Task Apply_accepts_materialized_export_contract(
        ImageQualityLane quality,
        string lane,
        string compression,
        string cleanup)
    {
        BuildArtifacts plan = MinimalPlan(quality);
        string work = NewTempDir();
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
            ServicingStage export = Assert.Single(
                runner.Stages,
                stage => stage.Opcode == ServicingOpcode.ExportWim);
            Assert.Equal(lane, export.Parameters[StageParams.Lane]);
            Assert.Equal(compression, export.Parameters[StageParams.Compression]);
            Assert.Equal(cleanup, export.Parameters[StageParams.Cleanup]);
            Assert.Equal(quality, result.Value.Lane);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_preserves_workdir_on_runner_failure()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            FailingElevatedPlanRunner runner = new();
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

            Assert.False(result.IsOk);
            Assert.True(Directory.Exists(work));
            Assert.True(File.Exists(Path.Combine(work, "failure.json")));
            Assert.True(Directory.Exists(Path.Combine(work, "logs")));
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_rejects_successful_runner_without_output_iso()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: Path.Combine(work, "out.iso"));
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                plan,
                run,
                new SuccessfulElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.False(result.IsOk);
            Assert.Equal("servicing.evidence.outputIso.missing", result.Error.Code);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_rejects_successful_runner_without_digest_sidecar()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            string outputIso = Path.Combine(work, "out.iso");
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: outputIso);
            File.WriteAllText(run.SourceIsoPath, "iso-stub");
            File.WriteAllText(outputIso, "fake-iso");

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                plan,
                run,
                new SuccessfulElevatedPlanRunner(),
                TestContext.Current.CancellationToken);

            Assert.False(result.IsOk);
            Assert.Equal("servicing.evidence.digests.missing", result.Error.Code);
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static BuildArtifacts MinimalPlan(ImageQualityLane quality = ImageQualityLane.Test)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes($$"""
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
              }
            }
            """));
        Assert.True(parsed.IsOk);
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(
            parsed.Value,
            new RunOptions { ImageQuality = quality });
        Assert.True(planned.IsOk);
        return planned.Value;
    }

    private static string NewTempDir()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-s2-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
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
}
