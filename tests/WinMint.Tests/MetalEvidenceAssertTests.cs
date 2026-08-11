using System.Diagnostics;
using System.Text.Json.Nodes;

namespace WinMint.Tests;

/// <summary>S5 Metal seam: Apply workdir evidence assert (no Hyper-V, no install). Excluded from just check.</summary>
public class MetalEvidenceAssertTests
{
    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_passes_with_driver_inventory_and_digests()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            int exit = RunAssert(repo, work, expectDrivers: true, out string stdout, out string stderr);
            Assert.True(exit == 0, $"exit={exit}\nstdout={stdout}\nstderr={stderr}");

            string acceptancePath = Path.Combine(work, "metal-acceptance.json");
            Assert.True(File.Exists(acceptancePath), "expected metal-acceptance.json");
            string json = File.ReadAllText(acceptancePath);
            Assert.Contains("winmint.metal.acceptance/v1", json, StringComparison.Ordinal);
            Assert.Contains("\"preWipeOnly\": true", json, StringComparison.Ordinal);
            Assert.Contains("\"driverIncludedCount\": 12", json, StringComparison.Ordinal);
            Assert.Contains("\"firmwareExcluded\": true", json, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_fails_when_driver_digest_missing()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            string evidencePath = Path.Combine(work, "evidence.json");
            JsonNode doc = JsonNode.Parse(File.ReadAllText(evidencePath))
                ?? throw new InvalidOperationException("evidence parse failed");
            doc["digests"]!.AsObject().Remove("drivers.deviceId");
            File.WriteAllText(evidencePath, doc.ToJsonString());

            int exit = RunAssert(repo, work, expectDrivers: true, out _, out string stderr);
            Assert.NotEqual(0, exit);
            Assert.Contains("Driver digest missing", stderr, StringComparison.OrdinalIgnoreCase);
            Assert.False(File.Exists(Path.Combine(work, "metal-acceptance.json")));
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_fails_when_firmware_would_be_injected()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            string inventoryPath = Path.Combine(work, "logs", "WinMint-DriverInventory.json");
            JsonNode doc = JsonNode.Parse(File.ReadAllText(inventoryPath))
                ?? throw new InvalidOperationException("inventory parse failed");
            doc["records"]![1]!["decision"] = "includeOffline";
            File.WriteAllText(inventoryPath, doc.ToJsonString());

            int exit = RunAssert(repo, work, expectDrivers: true, out _, out string stderr);
            Assert.NotEqual(0, exit);
            Assert.Contains("firmware", stderr, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_fails_when_outputIso_digest_stale()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            string evidencePath = Path.Combine(work, "evidence.json");
            JsonNode doc = JsonNode.Parse(File.ReadAllText(evidencePath))
                ?? throw new InvalidOperationException("evidence parse failed");
            doc["digests"]!["outputIso.sha256"] = "deadbeef";
            File.WriteAllText(evidencePath, doc.ToJsonString());

            int exit = RunAssert(repo, work, expectDrivers: true, out _, out string stderr);
            Assert.NotEqual(0, exit);
            Assert.Contains("outputIso.sha256 mismatch", stderr, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_fails_when_RequireLane_mismatches()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            int exit = RunAssert(repo, work, expectDrivers: true, out _, out string stderr, requireLane: "Release");
            Assert.NotEqual(0, exit);
            Assert.Contains("lane must be Release", stderr, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_fails_when_Release_packageStrict_missing()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            string evidencePath = Path.Combine(work, "evidence.json");
            JsonNode doc = JsonNode.Parse(File.ReadAllText(evidencePath))
                ?? throw new InvalidOperationException("evidence parse failed");
            doc["lane"] = "Release";
            doc.AsObject().Remove("packageStrict");
            File.WriteAllText(evidencePath, doc.ToJsonString());

            int exit = RunAssert(repo, work, expectDrivers: true, out _, out string stderr, requireLane: "Release");
            Assert.NotEqual(0, exit);
            Assert.Contains("packageStrict", stderr, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_fails_when_Release_packageStrict_false()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            string evidencePath = Path.Combine(work, "evidence.json");
            JsonNode doc = JsonNode.Parse(File.ReadAllText(evidencePath))
                ?? throw new InvalidOperationException("evidence parse failed");
            doc["lane"] = "Release";
            doc["packageStrict"] = false;
            File.WriteAllText(evidencePath, doc.ToJsonString());

            int exit = RunAssert(repo, work, expectDrivers: true, out _, out string stderr, requireLane: "Release");
            Assert.NotEqual(0, exit);
            Assert.Contains("packageStrict must be true", stderr, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_fails_when_fu_digest_missing_on_ExpectFuPosture()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            int exit = RunAssert(
                repo,
                work,
                expectDrivers: true,
                out _,
                out string stderr,
                expectFuPosture: true);
            Assert.NotEqual(0, exit);
            Assert.Contains("FU posture digest missing", stderr, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    [Trait("Category", "Metal")]
    public void Assert_metal_evidence_passes_release_fu_posture_when_payload_complete()
    {
        string repo = FindRepoRoot();
        string work = CopyFixtureToTemp(repo);
        try
        {
            string evidencePath = Path.Combine(work, "evidence.json");
            JsonNode doc = JsonNode.Parse(File.ReadAllText(evidencePath))
                ?? throw new InvalidOperationException("evidence parse failed");
            doc["lane"] = "Release";
            doc["packageStrict"] = true;
            JsonObject digests = doc["digests"]!.AsObject();
            digests["policy.cloudContent.DisableWindowsConsumerFeatures"] = "1";
            digests["policy.cloudContent.DisableSoftLanding"] = "1";
            digests["policy.store.AutoDownload"] = "2";
            File.WriteAllText(evidencePath, doc.ToJsonString());

            string payload = Path.Combine(work, "payload");
            Directory.CreateDirectory(payload);
            File.WriteAllText(
                Path.Combine(payload, "jobs.json"),
                """
                {"jobs":[{"id":"winget.import","kind":"winget.import"},{"id":"scoop.batch","kind":"scoop.batch","packageId":"starship"},{"id":"shell.stamp","kind":"shell.stamp"}]}
                """);
            File.WriteAllText(
                Path.Combine(payload, "winget-import.json"),
                """
                {"Sources":[{"Packages":[
                  {"PackageIdentifier":"Git.MinGit"},
                  {"PackageIdentifier":"Microsoft.PowerShell"},
                  {"PackageIdentifier":"Microsoft.WindowsTerminal"},
                  {"PackageIdentifier":"Microsoft.Coreutils"},
                  {"PackageIdentifier":"Nilesoft.Shell"}
                ]}]}
                """);

            int exit = RunAssert(
                repo,
                work,
                expectDrivers: true,
                out string stdout,
                out string stderr,
                requireLane: "Release");
            Assert.True(exit == 0, $"exit={exit}\nstdout={stdout}\nstderr={stderr}");
            string acceptance = File.ReadAllText(Path.Combine(work, "metal-acceptance.json"));
            Assert.Contains("\"fuPosture\": true", acceptance, StringComparison.Ordinal);
            Assert.Contains("\"lane\": \"Release\"", acceptance, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    private static string CopyFixtureToTemp(string repo)
    {
        string fixture = Path.Combine(repo, "tests", "fixtures", "metal-evidence");
        string work = Path.Combine(Path.GetTempPath(), "winmint-s5-" + Guid.NewGuid().ToString("N"));
        CopyTree(fixture, work);
        return work;
    }

    private static int RunAssert(
        string repo,
        string workDirectory,
        bool expectDrivers,
        out string stdout,
        out string stderr,
        string? requireLane = null,
        bool expectFuPosture = false)
    {
        string script = Path.Combine(repo, "tools", "metal", "Assert-MetalEvidence.ps1");
        Assert.True(File.Exists(script), script);
        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(script);
        psi.ArgumentList.Add("-WorkDirectory");
        psi.ArgumentList.Add(workDirectory);
        psi.ArgumentList.Add("-RequireOutputIso");
        if (expectDrivers)
        {
            psi.ArgumentList.Add("-ExpectDrivers");
        }

        if (!string.IsNullOrWhiteSpace(requireLane))
        {
            psi.ArgumentList.Add("-RequireLane");
            psi.ArgumentList.Add(requireLane);
        }

        if (expectFuPosture)
        {
            psi.ArgumentList.Add("-ExpectFuPosture");
        }

        using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
        stdout = p.StandardOutput.ReadToEnd();
        stderr = p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(60_000), "Assert-MetalEvidence.ps1 timed out");
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
