using System.Text;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 09 — Test vs Release ExportWim params at S1/S2.</summary>
public class ExportLaneTests
{
    [Fact]
    public async Task Apply_release_lane_export_params_differ_from_test_and_manifest_lane_matches()
    {
        BuildArtifacts plan = Plan(ImageQualityLane.Release);
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
                s => s.Opcode == ServicingOpcode.ExportWim);
            Assert.Equal("Release", export.Parameters[StageParams.Lane]);
            Assert.Equal("max", export.Parameters[StageParams.Compression]);
            Assert.Equal("full", export.Parameters[StageParams.Cleanup]);
            Assert.Equal(ImageQualityLane.Release, result.Value.Lane);
            Assert.Equal(ImageQualityLane.Release, plan.Manifest.ImageQuality);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public async Task Apply_rejects_mismatched_export_params_for_release_lane()
    {
        BuildArtifacts good = Plan(ImageQualityLane.Release);
        // Corrupt ExportWim params after plan — Materialize must fail closed.
        ServicingStage badExport = new(
            ServicingOpcode.ExportWim,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                [StageParams.Lane] = "Release",
                [StageParams.Compression] = "fast",
                [StageParams.Cleanup] = "skip",
            });
        List<ServicingStage> stages = good.Stages.Stages
            .Select(s => s.Opcode == ServicingOpcode.ExportWim ? badExport : s)
            .ToList();
        BuildArtifacts corrupted = good with
        {
            Stages = new ServicingStageList(stages),
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
                corrupted,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.False(result.IsOk);
            Assert.Equal("servicing.export.lane_mismatch", result.Error.Code);
            Assert.Empty(runner.Stages);
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static BuildArtifacts Plan(ImageQualityLane lane)
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
            new RunOptions { ImageQuality = lane });
        Assert.True(planned.IsOk);
        return planned.Value;
    }

    private static string NewTempDir()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-lane-" + Guid.NewGuid().ToString("N"));
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
