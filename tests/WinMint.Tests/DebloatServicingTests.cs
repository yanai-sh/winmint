using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 12 — RemoveProvisionedAppx at S2 (ImageServicing Materialize / Apply).</summary>
public class DebloatServicingTests
{
    [Fact]
    public async Task Apply_injects_mountDir_for_RemoveProvisionedAppx_and_keeps_packageFamilyNames()
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

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            ServicingStage remove = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.RemoveProvisionedAppx);
            Assert.Equal(
                ProductPosture.UnionAppx(["Microsoft.BingNews", "Microsoft.GamingApp"]),
                JsonSerializer.Deserialize<string[]>(
                    File.ReadAllBytes(remove.Parameters[StageParams.PackageFamilyNamesPath]))!);
            Assert.Equal(
                Path.Combine(work, ServicingWorkspace.PayloadDirectoryName, ServicingWorkspace.PackageFamilyNamesFileName),
                remove.Parameters[StageParams.PackageFamilyNamesPath]);
            Assert.Equal(
                ImageServicing.HostMountDir,
                remove.Parameters[StageParams.MountDir]);
            Assert.Equal(work, remove.Parameters[StageParams.WorkDirectory]);
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
              },
              "debloat": {
                "mode": "offline",
                "removeProvisionedAppx": {{array}}
              }
            }
            """));
        Assert.True(parsed.IsOk, string.Join("; ", parsed.IsOk ? [] : parsed.Error.Select(i => i.Message)));
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value);
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
}
