using WinMint.Contracts;
using WinMint.Orchestrator;
using WinMint.Provisioning;

namespace WinMint.Tests;

/// <summary>
/// jobs.json is the only thing BuildPlan hands the guest. Writer and reader now share one wire record;
/// this is what fails if a job field stops surviving the crossing.
/// </summary>
public class JobsWireRoundTripTests
{
    [Fact]
    public void Every_job_field_survives_the_write_read_round_trip()
    {
        JobsArtifact authored = new(
            JobsWire.SchemaVersion,
            [
                new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub, NeedsReboot: true),
                new ProvisionJob(
                    "winget.jqlang.jq",
                    ProvisionJobKind.Winget,
                    PackageId: "jqlang.jq",
                    WingetArchitecture: "arm64"),
                new ProvisionJob(
                    "scoop.batch",
                    ProvisionJobKind.ScoopBatch,
                    PackageId: "curl;fd",
                    ScoopBuckets: ["extras", "main"]),
                new ProvisionJob(
                    "wsl.NixOS",
                    ProvisionJobKind.Wsl,
                    PackageId: "NixOS",
                    WslInstallKind: WslInstallKind.FromFile,
                    WslFromFileRepo: "nix-community/NixOS-WSL",
                    WslFromFileAssetNames: ["nixos.aarch64.wsl"]),
                new ProvisionJob(
                    "doh.cloudflare",
                    ProvisionJobKind.DohSet,
                    PackageId: "cloudflare",
                    DohPrimary: "1.1.1.1",
                    DohSecondary: "1.0.0.1",
                    DohTemplate: "https://cloudflare-dns.com/dns-query"),
                new ProvisionJob(
                    "package.auditNative",
                    ProvisionJobKind.PackageAuditNative,
                    PackageId: "jqlang.jq",
                    AuditStrict: true),
            ]);

        string dir = Path.Combine(Path.GetTempPath(), "winmint-jobs-wire-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string bundlePath = Path.Combine(dir, "bundle.json");
            File.WriteAllText(
                bundlePath,
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.SchemaVersion}}",
                  "supervisorPath": "C:\\Windows\\WinMint\\WinMint.Provisioning.exe",
                  "username": "winmint",
                  "password": "lab-only",
                  "dmaEnabled": false,
                  "settle": null
                }
                """);
            string written = JobsWire.Write(authored.Jobs);
            Assert.True(
                JobsWire.TryParse(
                    System.Text.Encoding.UTF8.GetBytes(written),
                    out JobsFile? parsed,
                    out JobsWireError parseError),
                $"{parseError.Code}: {parseError.Message}");
            Assert.Equal(
                ["extras", "main"],
                Assert.IsType<string[]>(parsed!.Jobs![2].ScoopBuckets));
            File.WriteAllText(Path.Combine(dir, "jobs.json"), written);

            BundleLoadResult loaded = BundleLoader.LoadFromFile(bundlePath);
            Assert.True(loaded.IsOk, loaded.IsOk ? null : $"{loaded.Error.Code}: {loaded.Error.Message}");

            // Re-serialize rather than compare records: the job's list members are reference-equal only.
            Assert.Equal(
                written,
                JobsWire.Write(loaded.Value.Jobs));
        }
        finally
        {
            try
            {
                Directory.Delete(dir, recursive: true);
            }
            catch
            {
                // ponytail: best-effort temp cleanup
            }
        }
    }
}
