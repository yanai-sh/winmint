using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ImageServicingApplyTests
{
    [Fact]
    public void Apply_runs_stages_in_plan_order_with_shell_stamp_param()
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

            Result<ImageEvidence, ServicingFailure> result = ImageServicing.Apply(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            Assert.Equal(
                [
                    ServicingOpcode.MountInstallWim,
                    ServicingOpcode.StagePayload,
                    ServicingOpcode.InjectUnattend,
                    ServicingOpcode.StampOfflineShell,
                    ServicingOpcode.ExportWim,
                    ServicingOpcode.BuildIso,
                ],
                runner.Opcodes.ToArray());
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.StampOfflineShell
                    && s.Parameters.TryGetValue("shellTarget", out string? target)
                    && !string.IsNullOrWhiteSpace(target));
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.ExportWim
                    && s.Parameters.TryGetValue("lane", out string? lane)
                    && lane == "Test"
                    && s.Parameters.TryGetValue("compression", out string? compression)
                    && compression == "fast"
                    && s.Parameters.TryGetValue("cleanup", out string? cleanup)
                    && cleanup == "skip");
            Assert.False(string.IsNullOrWhiteSpace(result.Value.ShellStampTargetPath));
            Assert.Equal(ImageQualityLane.Test, result.Value.Lane);
            Assert.Equal(ImageServicing.ShellStampGuestPath, result.Value.ShellStampTargetPath);
            Assert.True(File.Exists(Path.Combine(work, "payload", "SetupComplete.cmd")));
            Assert.True(File.Exists(Path.Combine(work, "payload", "bundle.json")));
            Assert.True(File.Exists(Path.Combine(work, "payload", "Supervisor.exe")));
            string bundle = File.ReadAllText(Path.Combine(work, "payload", "bundle.json"));
            Assert.Contains(ImageServicing.BundleSchemaVersion, bundle, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public void Apply_preserves_workdir_on_runner_failure()
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

            Result<ImageEvidence, ServicingFailure> result = ImageServicing.Apply(
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

    private static BuildArtifacts MinimalPlan()
    {
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes("""
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
            """));
        Assert.True(parsed.IsOk);
        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
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

    private sealed class RecordingElevatedPlanRunner : IElevatedPlanRunner
    {
        public List<ServicingStage> Stages { get; } = [];
        public IEnumerable<ServicingOpcode> Opcodes => Stages.Select(s => s.Opcode);

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
                .Parameters["shellTarget"];
            return Result.Ok<ImageEvidence, ServicingFailure>(
                new ImageEvidence(
                    run.OutputIsoPath ?? Path.Combine(workDirectory, "out.iso"),
                    plan.Manifest.ImageQuality,
                    shellTarget,
                    new Dictionary<string, string>(StringComparer.Ordinal)));
        }
    }

    private sealed class FailingElevatedPlanRunner : IElevatedPlanRunner
    {
        public Result<ImageEvidence, ServicingFailure> Execute(
            string workDirectory,
            IReadOnlyList<ServicingStage> stages,
            ServicingRun run,
            BuildArtifacts plan,
            CancellationToken ct)
        {
            Directory.CreateDirectory(Path.Combine(workDirectory, "logs"));
            File.WriteAllText(
                Path.Combine(workDirectory, "failure.json"),
                """{"schemaVersion":"winmint.image.evidence/v1","failed":true}""");
            return Result.Fail<ImageEvidence, ServicingFailure>(
                new ServicingFailure("servicing.stage.failed", "InjectUnattend failed (test)."));
        }
    }
}
