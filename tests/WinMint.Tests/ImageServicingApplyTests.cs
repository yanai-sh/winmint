using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

public class ImageServicingApplyTests
{
    [Fact]
    public async Task Apply_resolves_default_output_iso_from_profile_stem()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            RecordingElevatedPlanRunner runner = new();
            string profilePath = Path.Combine(work, "sl7.profile.json");
            File.WriteAllText(profilePath, "{}");
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: null,
                ProfilePath: profilePath);
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            Assert.Contains("winmint_sl7_Test_", result.Value.OutputIsoPath, StringComparison.Ordinal);
            Assert.DoesNotContain("winmint_profile_", result.Value.OutputIsoPath, StringComparison.Ordinal);
            Assert.Equal(new string('a', 64), result.Value.Digests["outputIso.sha256"]);
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
                    && s.Parameters.TryGetValue(StageParams.PolicySpecs, out string? specs)
                    && specs.Contains("HideFirstRunExperience", StringComparison.Ordinal)
                    && s.Parameters.TryGetValue(StageParams.MountDir, out string? polMount)
                    && polMount == ImageServicing.HostMountDir
                    && s.Parameters.TryGetValue(StageParams.WorkDirectory, out string? polWork)
                    && polWork == work);
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
            Assert.True(File.Exists(Path.Combine(work, "payload", "SetupComplete.cmd")));
            string stagedSetup = File.ReadAllText(Path.Combine(work, "payload", "SetupComplete.cmd"));
            string repoSetup = File.ReadAllText(
                Path.Combine(TestRepo.Root, "payload", "scripts", "SetupComplete.cmd"));
            Assert.Equal(repoSetup, stagedSetup);
            Assert.True(File.Exists(Path.Combine(work, "payload", "bundle.json")));
            Assert.True(File.Exists(Path.Combine(work, "payload", "Supervisor.exe")));
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
                MediaCacheIdentity.CurrentSchema.ToString(System.Globalization.CultureInfo.InvariantCulture),
                mount.Parameters[StageParams.CacheSchema]);
            Assert.Equal(MediaCacheIdentity.Root, mount.Parameters[StageParams.CacheRoot]);
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
    public async Task Apply_rejects_successful_runner_without_evidence()
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
            Assert.Equal("servicing.evidence.missing", result.Error.Code);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Theory]
    [InlineData("missing-output", "servicing.evidence.outputIso.missing")]
    [InlineData("mismatch-output", "servicing.evidence.outputIso.mismatch")]
    [InlineData("missing-lane", "servicing.evidence.lane.missing")]
    [InlineData("mismatch-lane", "servicing.evidence.lane.mismatch")]
    [InlineData("missing-shell", "servicing.evidence.shellStamp.missing")]
    [InlineData("mismatch-shell", "servicing.evidence.shellStamp.mismatch")]
    [InlineData("host-normalized-shell", "servicing.evidence.shellStamp.mismatch")]
    [InlineData("missing-digests", "servicing.evidence.digests.missing")]
    [InlineData("malformed-digest", "servicing.evidence.outputIsoDigest.invalid")]
    [InlineData("malformed-json", "servicing.evidence.invalid")]
    public async Task Apply_rejects_incomplete_or_mismatched_evidence(string defect, string expectedCode)
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            string outputIso = Path.Combine(work, "out.iso");
            Dictionary<string, object?> evidence = new(StringComparer.Ordinal)
            {
                ["schemaVersion"] = ImageServicing.EvidenceSchemaVersion,
                ["outputIsoPath"] = outputIso,
                ["shellStampTargetPath"] = ImageServicing.ShellStampGuestPath,
                ["lane"] = "Test",
                ["packageStrict"] = false,
                ["digests"] = new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    ["outputIso.sha256"] = new string('a', 64),
                },
            };

            switch (defect)
            {
                case "missing-output":
                    evidence.Remove("outputIsoPath");
                    break;
                case "mismatch-output":
                    evidence["outputIsoPath"] = Path.Combine(work, "other.iso");
                    break;
                case "missing-lane":
                    evidence.Remove("lane");
                    break;
                case "mismatch-lane":
                    evidence["lane"] = "Release";
                    break;
                case "missing-shell":
                    evidence.Remove("shellStampTargetPath");
                    break;
                case "mismatch-shell":
                    evidence["shellStampTargetPath"] = @"C:\Windows\Explorer.exe";
                    break;
                case "host-normalized-shell":
                    evidence["shellStampTargetPath"] = "C:/Windows/WinMint/Supervisor.exe";
                    break;
                case "missing-digests":
                    evidence.Remove("digests");
                    break;
                case "malformed-digest":
                    evidence["digests"] = new Dictionary<string, string>(StringComparer.Ordinal)
                    {
                        ["outputIso.sha256"] = new string('A', 64),
                    };
                    break;
            }

            string evidenceJson = defect == "malformed-json" ? "{" : JsonSerializer.Serialize(evidence);
            EvidenceElevatedPlanRunner runner = new(evidenceJson);
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

            Assert.False(result.IsOk);
            Assert.Equal(expectedCode, result.Error.Code);
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
