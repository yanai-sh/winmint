using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

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
            Directory.CreateDirectory(Path.Combine(work, "logs"));
            Directory.CreateDirectory(Path.Combine(work, "media"));
            File.WriteAllText(Path.Combine(work, "evidence.json"), """{"stale":true}""");
            File.WriteAllText(Path.Combine(work, "failure.json"), """{"message":"stale failure"}""");
            File.WriteAllText(Path.Combine(work, "logs", "diagnostic.log"), "keep");
            File.WriteAllText(Path.Combine(work, "media", "diagnostic.bin"), "keep");
            File.WriteAllText(
                Path.Combine(work, "stages.json"),
                """{"schemaVersion":"winmint.servicing.stages/v1","stages":[{"opcode":"Nope","parameters":{}}]}""");

            (int exitCode, string output) = RunPlan(work);

            Assert.True(exitCode == 1, $"expected exit 1, got {exitCode}\n{output}");

            string failurePath = Path.Combine(work, "failure.json");
            Assert.True(File.Exists(failurePath), $"expected failure.json\n{output}");
            string failure = File.ReadAllText(failurePath);
            Assert.Contains("Nope", failure, StringComparison.Ordinal);
            Assert.DoesNotContain("stale failure", failure, StringComparison.Ordinal);
            Assert.False(File.Exists(Path.Combine(work, "evidence.json")), "stale evidence must be removed");
            Assert.True(File.Exists(Path.Combine(work, "logs", "diagnostic.log")));
            Assert.True(File.Exists(Path.Combine(work, "media", "diagnostic.bin")));

            string status = File.ReadAllText(Path.Combine(work, "apply-status.txt"));
            Assert.DoesNotContain("stage=done", status, StringComparison.Ordinal);
            Assert.Contains("stage=failed:Nope", status, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public void Evidence_cleanup_failure_still_writes_current_failure_and_status()
    {
        string work = NewWork("cleanup-failure");
        try
        {
            string evidencePath = Path.Combine(work, "evidence.json");
            Directory.CreateDirectory(evidencePath);
            File.WriteAllText(Path.Combine(evidencePath, "stale-green.json"), """{"stale":true}""");
            File.WriteAllText(Path.Combine(work, "failure.json"), """{"message":"stale failure"}""");
            File.WriteAllText(
                Path.Combine(work, "stages.json"),
                """{"schemaVersion":"winmint.servicing.stages/v1","stages":[]}""");

            (int exitCode, string output) = RunPlan(work);

            Assert.True(exitCode == 1, $"expected exit 1, got {exitCode}\n{output}");
            Assert.True(Directory.Exists(evidencePath), "fixture forces evidence cleanup failure");
            string failure = File.ReadAllText(Path.Combine(work, "failure.json"));
            Assert.Contains("evidence cleanup failed", failure, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("stale failure", failure, StringComparison.Ordinal);
            Assert.Contains(
                "stage=failed:plan",
                File.ReadAllText(Path.Combine(work, "apply-status.txt")),
                StringComparison.Ordinal);
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
            File.WriteAllText(
                Path.Combine(work, "stages.json"),
                """{"schemaVersion":"winmint.servicing.stages/v1","stages":[]}""");
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

    [Fact]
    public void Malformed_stages_remove_stale_evidence_and_report_stages_failure()
    {
        string work = NewWork("malformed");
        try
        {
            File.WriteAllText(Path.Combine(work, "stages.json"), "{");
            File.WriteAllText(Path.Combine(work, "evidence.json"), """{"stale":true}""");

            (int exitCode, string output) = RunPlan(work);

            Assert.True(exitCode == 1, $"expected exit 1, got {exitCode}\n{output}");
            Assert.False(File.Exists(Path.Combine(work, "evidence.json")));
            Assert.Contains(
                """"opcode": "stages"""",
                File.ReadAllText(Path.Combine(work, "failure.json")),
                StringComparison.Ordinal);
            Assert.Contains(
                "stage=failed:stages",
                File.ReadAllText(Path.Combine(work, "apply-status.txt")),
                StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public void Evidence_uses_fresh_external_iso_hash_after_sidecar_merge()
    {
        string work = NewWork("success");
        string external = NewWork("external");
        try
        {
            string runner = PrepareFakeServicingRoot(work);
            string outputIso = Path.Combine(external, "output.iso");
            Directory.CreateDirectory(Path.Combine(work, "logs"));
            File.WriteAllText(Path.Combine(work, "install.wim"), "install-wim");
            File.WriteAllText(Path.Combine(work, "failure.json"), """{"stale":true}""");
            File.WriteAllText(
                Path.Combine(work, "logs", "digests.json"),
                JsonSerializer.Serialize(new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    ["outputIso.sha256"] = new string('0', 64),
                    ["policy.hideFirstRunExperience.sha256"] = new string('b', 64),
                }));
            File.WriteAllText(
                Path.Combine(work, "stages.json"),
                JsonSerializer.Serialize(new
                {
                    schemaVersion = "winmint.servicing.stages/v1",
                    stages = new object[]
                    {
                        new
                        {
                            opcode = "StampOfflineShell",
                            parameters = new Dictionary<string, string>
                            {
                                ["shellTarget"] = @"C:\Windows\WinMint\Supervisor.exe",
                            },
                        },
                        new
                        {
                            opcode = "ExportWim",
                            parameters = new Dictionary<string, string> { ["lane"] = "Test" },
                        },
                        new
                        {
                            opcode = "BuildIso",
                            parameters = new Dictionary<string, string>
                            {
                                ["outputIso"] = outputIso,
                                ["failurePath"] = Path.Combine(work, "failure.json"),
                            },
                        },
                    },
                }));

            (int exitCode, string output) = RunPlan(work, runner);

            Assert.True(exitCode == 0, $"expected exit 0, got {exitCode}\n{output}");
            string evidencePath = Path.Combine(work, "evidence.json");
            Assert.True(File.Exists(evidencePath), $"expected evidence under workdir\n{output}");
            Assert.True(File.Exists(outputIso), $"expected external ISO\n{output}");
            Assert.True(
                File.Exists(Path.Combine(work, "failure-observed.txt")),
                "fake BuildIso must observe prior failure before producing the ISO");
            Assert.False(File.Exists(Path.Combine(work, "failure.json")), "success clears stale failure last");

            using JsonDocument evidence = JsonDocument.Parse(File.ReadAllBytes(evidencePath));
            Assert.Equal(outputIso, evidence.RootElement.GetProperty("outputIsoPath").GetString());
            JsonElement digests = evidence.RootElement.GetProperty("digests");
            string expectedIsoHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(outputIso)))
                .ToLowerInvariant();
            string expectedWimHash = Convert.ToHexString(
                SHA256.HashData(File.ReadAllBytes(Path.Combine(work, "install.wim"))))
                .ToLowerInvariant();
            Assert.Equal(expectedIsoHash, digests.GetProperty("outputIso.sha256").GetString());
            Assert.Equal(expectedWimHash, digests.GetProperty("installWim.sha256").GetString());
            Assert.Equal(
                new string('b', 64),
                digests.GetProperty("policy.hideFirstRunExperience.sha256").GetString());
        }
        finally
        {
            TryDelete(work);
            TryDelete(external);
        }
    }

    private static string NewWork(string tag)
    {
        string work = Path.Combine(Path.GetTempPath(), $"winmint-plan-{tag}-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        return work;
    }

    private static string PrepareFakeServicingRoot(string work)
    {
        string servicing = Path.Combine(work, "fake-servicing");
        Directory.CreateDirectory(servicing);
        string runner = Path.Combine(servicing, "Invoke-ServicingPlan.ps1");
        File.Copy(
            Path.Combine(TestRepo.Root, "servicing", "Invoke-ServicingPlan.ps1"),
            runner);
        const string noOp = """
            param([hashtable] $Parameters)
            exit 0
            """;
        File.WriteAllText(Path.Combine(servicing, "Stamp-OfflineShell.ps1"), noOp);
        File.WriteAllText(Path.Combine(servicing, "Export-Wim.ps1"), noOp);
        File.WriteAllText(
            Path.Combine(servicing, "Build-Iso.ps1"),
            """
            param([hashtable] $Parameters)
            $failurePath = $Parameters['failurePath']
            if (-not (Test-Path -LiteralPath $failurePath -PathType Leaf)) {
                throw "prior failure missing before BuildIso: $failurePath"
            }
            Set-Content -LiteralPath (Join-Path (Split-Path -Parent $failurePath) 'failure-observed.txt') -Value 'observed'
            Set-Content -LiteralPath $Parameters['outputIso'] -Value 'fresh-iso' -Encoding utf8
            exit 0
            """);
        return runner;
    }

    private static (int ExitCode, string Output) RunPlan(string work, string? runner = null)
    {
        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList =
            {
                "-NoProfile",
                "-File",
                runner ?? Path.Combine(TestRepo.Root, "servicing", "Invoke-ServicingPlan.ps1"),
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
