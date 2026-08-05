using System.Text;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

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
                    ServicingOpcode.StampOfflinePolicies,
                    ServicingOpcode.StagePayload,
                    ServicingOpcode.InjectUnattend,
                    ServicingOpcode.StampOfflineShell,
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
                    && s.Parameters.TryGetValue(StageParams.ReuseMedia, out string? reuse)
                    && reuse == "false"
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
                Path.Combine(FindRepoRoot(), "payload", "scripts", "SetupComplete.cmd"));
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
    public void Apply_passes_reuseMedia_true_on_MountInstallWim_when_requested()
    {
        BuildArtifacts plan = MinimalPlan();
        string work = NewTempDir();
        try
        {
            RecordingElevatedPlanRunner runner = new();
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: Path.Combine(work, "out.iso"),
                ReuseMedia: true);
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, ServicingFailure> result = ImageServicing.Apply(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.MountInstallWim
                    && s.Parameters.TryGetValue(StageParams.ReuseMedia, out string? reuse)
                    && reuse == "true");
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
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes($$"""
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

    private static string FindRepoRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "WinMint.slnx")))
        {
            dir = dir.Parent;
        }

        Assert.NotNull(dir);
        return dir.FullName;
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
