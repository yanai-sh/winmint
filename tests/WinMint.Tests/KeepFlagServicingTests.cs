using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Ticket 12 — RemoveProvisionedAppx at S2 (ImageServicing Materialize / Apply).</summary>
public class KeepFlagServicingTests
{
    [Fact]
    public void Apply_injects_mountDir_for_RemoveProvisionedAppx_and_keeps_packageFamilyNames()
    {
        BuildArtifacts plan = PlanWithRemove(["Microsoft.BingNews", "Microsoft.GamingApp"]);
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
            ServicingStage remove = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
            Assert.Equal(
                "Microsoft.BingNews;Microsoft.GamingApp",
                remove.Parameters[StageParams.PackageFamilyNames]);
            Assert.Equal(
                Path.Combine(work, "mount"),
                remove.Parameters[StageParams.MountDir]);
            Assert.DoesNotContain(
                ".ps1",
                string.Join('\0', remove.Parameters.Values),
                StringComparison.OrdinalIgnoreCase);

            IReadOnlyList<ServicingOpcode> opcodes = runner.Opcodes.ToArray();
            int mountAt = opcodes.ToList().IndexOf(ServicingOpcode.MountInstallWim);
            int removeAt = opcodes.ToList().IndexOf(ServicingOpcode.RemoveProvisionedAppx);
            int payloadAt = opcodes.ToList().IndexOf(ServicingOpcode.StagePayload);
            Assert.True(mountAt >= 0 && removeAt > mountAt && removeAt < payloadAt);
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static BuildArtifacts PlanWithRemove(IReadOnlyList<string> ids)
    {
        string array = "[" + string.Join(",", ids.Select(id => $"\"{id}\"")) + "]";
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
              },
              "debloat": {
                "removeProvisionedAppx": {{array}}
              }
            }
            """));
        Assert.True(parsed.IsOk, string.Join("; ", parsed.IsOk ? [] : parsed.Error.Issues.Select(i => i.Message)));
        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        return planned.Value;
    }

    private static string NewTempDir()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-s2-kf-" + Guid.NewGuid().ToString("N"));
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
