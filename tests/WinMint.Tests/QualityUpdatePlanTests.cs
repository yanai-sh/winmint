using System.Text;

using WinMint.Orchestrator;

using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

public class QualityUpdatePlanTests
{
    [Theory]
    [InlineData(ImageQualityLane.Test)]
    [InlineData(ImageQualityLane.Release)]
    public void Plan_does_not_emit_AddQualityUpdates(ImageQualityLane lane)
    {
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(Parse(), new RunOptions { ImageQuality = lane });
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        IReadOnlyList<ServicingOpcode> stages = planned.Value.Stages;
        Assert.DoesNotContain(ServicingOpcode.AddQualityUpdates, stages);
        int shell = stages.ToList().IndexOf(ServicingOpcode.StampOfflineShell);
        int boot = stages.ToList().IndexOf(ServicingOpcode.PatchBootWimApply);
        int export = stages.ToList().IndexOf(ServicingOpcode.ExportWim);
        Assert.True(shell >= 0 && boot == shell + 1 && export == boot + 1);
    }

    [Fact]
    public async Task Apply_materializes_quality_cache_and_package_dir()
    {
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(Parse());
        Assert.True(planned.IsOk);
        string work = Path.Combine(Path.GetTempPath(), "winmint-quality-" + Guid.NewGuid().ToString("N"));
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
                planned.Value,
                run,
                runner,
                TestContext.Current.CancellationToken);
            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");

            List<ServicingOpcode> opcodes = [.. runner.Opcodes];
            int shell = opcodes.IndexOf(ServicingOpcode.StampOfflineShell);
            int quality = opcodes.IndexOf(ServicingOpcode.AddQualityUpdates);
            int bootAt = opcodes.IndexOf(ServicingOpcode.PatchBootWimApply);
            Assert.True(shell >= 0 && quality == shell + 1 && bootAt == quality + 1);

            ServicingStage add = Assert.Single(runner.Stages, s => s.Opcode == ServicingOpcode.AddQualityUpdates);
            Assert.Equal(ImageServicing.HostQualityCacheRoot, add.Parameters[StageParams.QualityCacheRoot]);
            Assert.Equal(
                Path.Combine(work, ServicingWorkspace.QualityPackagesDirectoryName),
                add.Parameters[StageParams.QualityPackageDir]);
            Assert.Equal(ImageServicing.HostMountDir, add.Parameters[StageParams.MountDir]);
            Assert.Equal(work, add.Parameters[StageParams.WorkDirectory]);

            ServicingStage boot = Assert.Single(runner.Stages, s => s.Opcode == ServicingOpcode.PatchBootWimApply);
            Assert.Equal(
                add.Parameters[StageParams.QualityPackageDir],
                boot.Parameters[StageParams.QualityPackageDir]);
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
                // ponytail: best-effort temp cleanup
            }
        }
    }

    private static Profile Parse()
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
        return parsed.Value;
    }
}
