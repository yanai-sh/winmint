using System.Text;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

public class WinPeApplyPlanTests
{
    [Fact]
    public void Plan_emits_oobe_unattend_stages_without_windowsPE()
    {
        Profile profile = ParseProfile();
        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.DoesNotContain("windowsPE", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.DoesNotContain("<Key>/IMAGE/INDEX</Key>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("oobeSystem", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains(BuildPlan.IrelandSetupLocale, artifacts.Unattend.Xml, StringComparison.Ordinal);

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
            artifacts.Stages.Stages.Select(s => s.Opcode).ToArray());
    }

    [Fact]
    public void Apply_materializes_winpe_opcode_params()
    {
        Profile profile = ParseProfile();
        Result<BuildArtifacts, PlanFailure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);

        string work = NewTempDir();
        try
        {
            RecordingElevatedPlanRunner runner = new();
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: Path.Combine(work, "out.iso"),
                WimIndex: 3);
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, ServicingFailure> result = ImageServicing.Apply(
                planned.Value,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.StageOobeUnattend
                    && s.Parameters.TryGetValue(StageParams.UnattendPath, out string? unattend)
                    && !string.IsNullOrWhiteSpace(unattend)
                    && s.Parameters.TryGetValue(StageParams.MountDir, out string? mount)
                    && mount == ImageServicing.HostMountDir);
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.MountInstallWim
                    && s.Parameters.TryGetValue(StageParams.WimIndex, out string? sourceIndex)
                    && sourceIndex == "3");
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.PatchBootWimApply
                    && !s.Parameters.ContainsKey(StageParams.WimIndex)
                    && s.Parameters.TryGetValue(StageParams.MediaDir, out string? media)
                    && media.EndsWith("media", StringComparison.OrdinalIgnoreCase));
            string written = File.ReadAllText(Path.Combine(work, "unattend.xml"));
            Assert.DoesNotContain("windowsPE", written, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public void PatchBootWimApply_script_contains_apply_lane_steps_not_legacy_setup()
    {
        string script = File.ReadAllText(FindPatchBootScript());
        Assert.Contains("$bootWim = Join-Path $mediaDir", script, StringComparison.Ordinal);
        Assert.Contains("$applyWimIndex = 1", script, StringComparison.Ordinal);
        Assert.Contains("/Index:$applyWimIndex", script, StringComparison.Ordinal);
        Assert.DoesNotContain("/Index:$wimIndex", script, StringComparison.Ordinal);
        Assert.DoesNotContain("$wimIndex = [int]$Parameters['wimIndex']", script, StringComparison.Ordinal);
        Assert.Contains("LaunchApply.cmd", script, StringComparison.Ordinal);
        Assert.Contains("diskpart", script, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Apply-Image", script, StringComparison.Ordinal);
        Assert.Contains("bcdboot", script, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("wpeutil reboot", script, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("LabConfig", script, StringComparison.Ordinal);
        Assert.DoesNotContain("setup.exe", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("/legacy", script, StringComparison.Ordinal);
        // Skip path must verify LaunchApply content — marker alone hid Index:3 after code fix.
        Assert.Contains("Test-LaunchApplyPatched", script, StringComparison.Ordinal);
        Assert.Contains("LaunchApply Index:1 verified", script, StringComparison.Ordinal);
        Assert.Contains(".winmint-boot-legacy", script, StringComparison.Ordinal);
    }

    [Fact]
    public void BuildIso_script_refreshes_outputIso_digest_in_evidence()
    {
        string script = File.ReadAllText(FindServicingScript("Build-Iso.ps1"));
        Assert.Contains("outputIso.sha256", script, StringComparison.Ordinal);
        Assert.Contains("evidence.json", script, StringComparison.Ordinal);
        Assert.Contains("Get-FileHash", script, StringComparison.Ordinal);
        Assert.Contains("failure.json", script, StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_emits_winpe_stages_only()
    {
        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(ParseProfile());
        Assert.True(result.IsOk);
        Assert.Contains(result.Value.Stages.Stages, s => s.Opcode == ServicingOpcode.StageOobeUnattend);
        Assert.Contains(result.Value.Stages.Stages, s => s.Opcode == ServicingOpcode.PatchBootWimApply);
    }

    private static Profile ParseProfile()
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
        return parsed.Value;
    }

    private static string FindPatchBootScript() => FindServicingScript("Patch-BootWimApply.ps1");

    private static string FindServicingScript(string fileName)
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "WinMint.slnx")))
        {
            dir = dir.Parent;
        }

        Assert.NotNull(dir);
        return Path.Combine(dir.FullName, "servicing", fileName);
    }

    private static string NewTempDir()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-s2-winpe-" + Guid.NewGuid().ToString("N"));
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
