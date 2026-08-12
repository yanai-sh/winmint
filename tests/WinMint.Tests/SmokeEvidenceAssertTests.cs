using System.Diagnostics;
using System.Text.Json.Nodes;

namespace WinMint.Tests;

/// <summary>S4 seam: harness evidence assert (no Hyper-V). Excluded from just check.</summary>
public class SmokeEvidenceAssertTests
{
    [Fact]
    [Trait("Category", "S4")]
    public void Assert_smoke_evidence_returns_splash_before_explorer_marker()
    {
        string repo = TestRepo.Root;
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
            Assert.Contains("winmint.smoke.acceptance/v1", json, StringComparison.Ordinal);
            Assert.Contains("\"splashBeforeExplorer\": true", json, StringComparison.Ordinal);
            Assert.Contains("\"lane\": \"Test\"", json, StringComparison.Ordinal);
            Assert.Contains("\"outcome\": \"Complete\"", json, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "S4")]
    public void Assert_smoke_evidence_fails_without_pinned_keepflag_digests()
    {
        string repo = TestRepo.Root;
        string fixture = Path.Combine(repo, "tests", "fixtures", "smoke-evidence");
        string work = Path.Combine(Path.GetTempPath(), "winmint-s4-nokeep-" + Guid.NewGuid().ToString("N"));
        try
        {
            CopyTree(fixture, work);
            File.WriteAllText(
                Path.Combine(work, "apply", "evidence.json"),
                """{"schemaVersion":"winmint.image.evidence/v1","lane":"Test","digests":{}}""");
            string acceptancePath = Path.Combine(work, "acceptance.json");
            if (File.Exists(acceptancePath))
            {
                File.Delete(acceptancePath);
            }

            // Empty Assert defaults skip keep-flag — pass pins explicitly.
            int exit = RunAssert(
                repo,
                work,
                out _,
                out string stderr,
                "-PinnedRemoveAppx", "Microsoft.BingNews");
            Assert.NotEqual(0, exit);
            Assert.Contains("keep-flag digest missing", stderr, StringComparison.OrdinalIgnoreCase);
            Assert.False(File.Exists(acceptancePath));
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
        string repo = TestRepo.Root;
        string fixture = Path.Combine(repo, "tests", "fixtures", "smoke-evidence");
        string work = Path.Combine(Path.GetTempPath(), "winmint-s4-bad-" + Guid.NewGuid().ToString("N"));
        try
        {
            CopyTree(fixture, work);
            string guestPath = Directory.GetFiles(Path.Combine(work, "guest"), "evidence-*.json")[0];
            JsonNode doc = JsonNode.Parse(File.ReadAllText(guestPath))
                ?? throw new InvalidOperationException("guest evidence parse failed");
            doc["phases"] = new JsonArray("settle.begin", "settle.ok", "jobs.ok");
            File.WriteAllText(guestPath, doc.ToJsonString());

            int exit = RunAssert(repo, work, out _, out _);
            Assert.NotEqual(0, exit);
            Assert.False(File.Exists(Path.Combine(work, "acceptance.json")));
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static int RunAssert(
        string repo,
        string evidenceDir,
        out string stdout,
        out string stderr,
        params string[] extraArgs)
    {
        // Call Assert script directly (pins need to reach Assert; empty defaults skip keep-flag).
        string script = Path.Combine(repo, "tools", "vm", "Assert-SmokeEvidence.ps1");
        Assert.True(File.Exists(script), script);
        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList = { "-NoProfile", "-File", script, "-EvidenceDir", evidenceDir },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (string arg in extraArgs)
        {
            psi.ArgumentList.Add(arg);
        }

        using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
        stdout = p.StandardOutput.ReadToEnd();
        stderr = p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(60_000), "SmokeEvidenceAssert.ps1 timed out");
        return p.ExitCode;
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
