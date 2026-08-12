using System.Diagnostics;

namespace WinMint.Tests;

/// <summary>
/// Issue 108 — Invoke-ServicingPlan must fail closed. Elevated runs cannot redirect stdout
/// (UAC needs UseShellExecute), so failure.json is the only channel back to C#, and
/// apply-status.txt is what the Wizard polls and <c>just watch-apply</c> tails. A throw
/// outside the kernel call used to skip both and report stage=done.
/// </summary>
public class ServicingPlanFailClosedTests
{
    [Fact]
    public void Unknown_opcode_writes_failure_json_and_never_reports_done()
    {
        string work = NewWork("failclosed");
        try
        {
            File.WriteAllText(
                Path.Combine(work, "stages.json"),
                """{"stages":[{"opcode":"Nope","parameters":{}}]}""");

            (int exitCode, string output) = RunPlan(work);

            Assert.True(exitCode == 1, $"expected exit 1, got {exitCode}\n{output}");

            string failurePath = Path.Combine(work, "failure.json");
            Assert.True(File.Exists(failurePath), $"expected failure.json\n{output}");
            Assert.Contains("Nope", File.ReadAllText(failurePath), StringComparison.Ordinal);

            string status = File.ReadAllText(Path.Combine(work, "apply-status.txt"));
            Assert.DoesNotContain("stage=done", status, StringComparison.Ordinal);
            Assert.Contains("stage=failed:Nope", status, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    /// <summary>
    /// The evidence tail throws too. A half-written logs/digests.json (a kernel that died mid-write)
    /// fails ConvertFrom-Json after the stage loop has already completed.
    /// </summary>
    [Fact]
    public void Throw_after_the_last_stage_still_fails_closed()
    {
        string work = NewWork("tail");
        try
        {
            Directory.CreateDirectory(Path.Combine(work, "logs"));
            File.WriteAllText(Path.Combine(work, "stages.json"), """{"stages":[]}""");
            File.WriteAllText(Path.Combine(work, "logs", "digests.json"), "{ this is not json");

            (int exitCode, string output) = RunPlan(work);

            Assert.True(exitCode == 1, $"expected exit 1, got {exitCode}\n{output}");
            Assert.True(File.Exists(Path.Combine(work, "failure.json")), $"expected failure.json\n{output}");
            Assert.False(File.Exists(Path.Combine(work, "evidence.json")), "no evidence on a failed plan");

            string status = File.ReadAllText(Path.Combine(work, "apply-status.txt"));
            Assert.DoesNotContain("stage=done", status, StringComparison.Ordinal);
            Assert.Contains("stage=failed:evidence", status, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static string NewWork(string tag)
    {
        string work = Path.Combine(Path.GetTempPath(), $"winmint-plan-{tag}-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        return work;
    }

    private static (int ExitCode, string Output) RunPlan(string work)
    {
        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList =
            {
                "-NoProfile",
                "-File",
                Path.Combine(TestRepo.Root, "servicing", "Invoke-ServicingPlan.ps1"),
                "-WorkDirectory",
                work,
            },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        // These runs fail on purpose, so the plan's Clear-LeftoverMount fires. Point ProgramData at
        // scratch: an elevated `just check` must not discard a real Apply's live DISM mount.
        psi.Environment["ProgramData"] = Path.Combine(work, "programdata");

        using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
        string stdout = p.StandardOutput.ReadToEnd();
        string stderr = p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(60_000), "Invoke-ServicingPlan timed out");
        return (p.ExitCode, $"stdout={stdout}\nstderr={stderr}");
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
            // ponytail: temp cleanup best-effort
        }
    }
}
