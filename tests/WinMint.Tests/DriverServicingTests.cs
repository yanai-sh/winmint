using System.Diagnostics;
using System.Text;

using WinMint.Orchestrator;

using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

/// <summary>Issue 63 — Surface Catalog driver injection at S2 (ImageServicing Materialize / Apply).</summary>
[Collection(ElevatedServicingPlanDefinition.Name)]
public class DriverServicingTests
{
    [Fact]
    public async Task Apply_injects_mountDir_mediaDir_for_InjectDrivers_and_keeps_deviceId()
    {
        BuildArtifacts plan = PlanWithDrivers("surface-laptop-7");
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
            ServicingStage inject = Assert.Single(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.InjectDrivers);
            Assert.Equal("surface-laptop-7", inject.Parameters[StageParams.DeviceId]);
            Assert.Equal(ImageServicing.HostMountDir, inject.Parameters[StageParams.MountDir]);
            Assert.Equal(work, inject.Parameters[StageParams.WorkDirectory]);
            Assert.True(inject.Parameters.ContainsKey(StageParams.MediaDir));
            Assert.DoesNotContain(
                ".ps1",
                string.Join('\0', inject.Parameters.Values),
                StringComparison.OrdinalIgnoreCase);

            IReadOnlyList<ServicingOpcode> opcodes = [.. runner.Opcodes];
            int injectAt = opcodes.ToList().IndexOf(ServicingOpcode.InjectDrivers);
            int policiesAt = opcodes.ToList().IndexOf(ServicingOpcode.StampOfflinePolicies);
            int payloadAt = opcodes.ToList().IndexOf(ServicingOpcode.StagePayload);
            Assert.True(policiesAt >= 0 && policiesAt < injectAt && injectAt < payloadAt);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public void InvokeServicingPlan_merges_driver_side_digests_into_evidence()
    {
        string work = Path.Combine(Path.GetTempPath(), "winmint-s2-drv-digests-" + Guid.NewGuid().ToString("N"));
        string logs = Path.Combine(work, "logs");
        Directory.CreateDirectory(logs);
        try
        {
            string runPlan = PrepareSuccessfulServicingFinalizer(work);
            File.WriteAllText(
                Path.Combine(logs, "digests.json"),
                """{"drivers.deviceId":"surface-laptop-7","drivers.includedCount":"12","drivers.excludedCount":"8"}""");

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
            Assert.Contains("drivers.deviceId", json, StringComparison.Ordinal);
            Assert.Contains("surface-laptop-7", json, StringComparison.Ordinal);
            Assert.Contains("drivers.includedCount", json, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static BuildArtifacts PlanWithDrivers(string deviceId)
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
              },
              "drivers": {
                "source": "surfaceCatalog",
                "deviceId": "{{deviceId}}"
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
        string path = Path.Combine(Path.GetTempPath(), "winmint-s2-drv-" + Guid.NewGuid().ToString("N"));
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
