using System.Diagnostics;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>S4 seam: harness evidence assert (no Hyper-V). Excluded from just check.</summary>
public class SmokeEvidenceAssertTests
{
    [Fact]
    [Trait("Category", "S4")]
    public void Assert_smoke_evidence_returns_splash_before_explorer_marker()
    {
        string repo = FindRepoRoot();
        string fixture = Path.Combine(repo, "tests", "fixtures", "smoke-evidence");
        string work = Path.Combine(Path.GetTempPath(), "winmint-s4-" + Guid.NewGuid().ToString("N"));
        try
        {
            CopyTree(fixture, work);
            int exit = RunAssert(repo, work, out string stdout, out string stderr);
            Assert.True(exit == 0, $"exit={exit}\nstdout={stdout}\nstderr={stderr}");

            string acceptancePath = Path.Combine(work, "acceptance.json");
            Assert.True(File.Exists(acceptancePath), "expected acceptance.json splash-before-Explorer marker");
            string json = File.ReadAllText(acceptancePath);
            Assert.Contains("\"splashBeforeExplorer\": true", json, StringComparison.Ordinal);
            Assert.Contains("\"lane\": \"Test\"", json, StringComparison.Ordinal);
            Assert.Contains(SmokeAcceptanceDocument.SchemaId, json, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "S4")]
    public void Assert_smoke_evidence_fails_without_first_paint_phase()
    {
        string repo = FindRepoRoot();
        string work = Path.Combine(Path.GetTempPath(), "winmint-s4-bad-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(Path.Combine(work, "guest"));
            Directory.CreateDirectory(Path.Combine(work, "apply"));
            File.WriteAllText(
                Path.Combine(work, "guest", "evidence-bad.json"),
                """
                {
                  "schemaVersion": "winmint.provisioning.evidence/v1",
                  "outcome": "Complete",
                  "statusCode": "jobs.ok",
                  "statusMessage": "ok",
                  "phases": [ "settle.begin", "settle.ok", "jobs.ok" ],
                  "firstPaintMs": 100
                }
                """);
            File.WriteAllText(
                Path.Combine(work, "apply", "evidence.json"),
                """{"schemaVersion":"winmint.image.evidence/v1","lane":"Test","digests":{}}""");

            int exit = RunAssert(repo, work, out _, out _);
            Assert.NotEqual(0, exit);
            Assert.False(File.Exists(Path.Combine(work, "acceptance.json")));
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static int RunAssert(string repo, string evidenceDir, out string stdout, out string stderr)
    {
        // One harness entry: Invoke-Smoke.ps1 -AssertOnly
        string script = Path.Combine(repo, "tools", "vm", "Invoke-Smoke.ps1");
        Assert.True(File.Exists(script), script);
        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList = { "-NoProfile", "-File", script, "-AssertOnly", "-EvidenceDir", evidenceDir },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
        stdout = p.StandardOutput.ReadToEnd();
        stderr = p.StandardError.ReadToEnd();
        p.WaitForExit(60_000);
        return p.ExitCode;
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

    private static void CopyTree(string source, string dest)
    {
        foreach (string file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
        {
            string rel = Path.GetRelativePath(source, file);
            string target = Path.Combine(dest, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target, overwrite: true);
        }
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
