using System.Text;
using WinMint.Orchestrator;
using WinMint.Contracts;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 18 — metal scoop job at S1 (Plan) + S3 (Run).</summary>
public class ScoopJobsTests
{
    [Fact]
    public void Plan_emits_scoop_batch_job_from_packages_scoop()
    {
        Profile profile = Parse(MinimalJson(scoop: ["curl", "komorebi"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor batch = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ScoopBatch);
        Assert.Equal("scoop.batch", batch.Id);
        Assert.False(batch.NeedsReboot);
        Assert.Contains("curl", batch.PackageId);
        Assert.Contains("komorebi", batch.PackageId);
        Assert.Contains("extras", batch.ScoopBuckets!);
    }

    [Fact]
    public void Plan_scoopNeedsReboot_subset_emits_needsReboot()
    {
        Profile profile = Parse(MinimalJson(scoop: ["curl"], scoopNeedsReboot: ["curl"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor batch = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == ProvisionJobKind.ScoopBatch);
        Assert.True(batch.NeedsReboot);
    }

    [Fact]
    public void Plan_scoopNeedsReboot_id_not_in_scoop_fails_closed()
    {
        Profile profile = Parse(MinimalJson(scoop: ["curl"], scoopNeedsReboot: ["jq"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("packages.scoopNeedsReboot.unknown", result.Error.Code);
    }

    [Fact]
    public async Task Shell_scoop_installs_when_ResolveScoopCmd_returns_path()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        string scoopPath = @"C:\Users\lab\scoop\shims\scoop.cmd";

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("scoop.curl", ProvisionJobKind.Scoop, PackageId: "curl")]),
            Env(processes, evidence, resolveScoopCmd: () => scoopPath),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.DoesNotContain(
            processes.Starts,
            s => s.FileName.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(
            processes.Starts,
            s => s.FileName == scoopPath && s.Arguments is ["install", "curl"]);
    }

    [Fact]
    public async Task Shell_scoop_bootstraps_then_installs_when_resolve_returns_path_after()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();
        string scoopPath = @"C:\Users\lab\scoop\shims\scoop.cmd";
        int resolveCalls = 0;
        string? Resolve()
        {
            resolveCalls++;
            return resolveCalls == 1 ? null : scoopPath;
        }

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("scoop.curl", ProvisionJobKind.Scoop, PackageId: "curl")]),
            Env(processes, evidence, resolveScoopCmd: Resolve),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Complete, result.Outcome);
        Assert.Equal("jobs.ok", result.FinalStatus.Code);
        Assert.Equal(2, resolveCalls);
        Assert.Equal("powershell.exe", processes.Starts[0].FileName, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("get.scoop.sh", processes.Starts[0].Arguments[4]);
        Assert.Contains(
            processes.Starts,
            s => s.FileName == scoopPath && s.Arguments is ["install", "curl"]);
    }

    [Fact]
    public async Task Shell_scoop_bootstraps_then_fails_when_still_missing()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("scoop.curl", ProvisionJobKind.Scoop, PackageId: "curl")]) with { PackageStrict = true },
            Env(processes, evidence, resolveScoopCmd: () => null),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.scoop.bootstrap_failed", result.FinalStatus.Code);
        Assert.Single(processes.Starts);
        Assert.Equal("powershell.exe", processes.Starts[0].FileName, StringComparer.OrdinalIgnoreCase);
        Assert.Contains("get.scoop.sh", processes.Starts[0].Arguments[4]);
        Assert.Contains("-RunAsAdmin", processes.Starts[0].Arguments[4]);
    }

    [Fact]
    public async Task Shell_scoop_fails_when_ResolveScoopCmd_missing()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = await ProvisioningSession.RunAsync(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("scoop.curl", ProvisionJobKind.Scoop, PackageId: "curl")]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.failed", result.FinalStatus.Code);
        Assert.Contains("ResolveScoopCmd", result.FinalStatus.Message);
        Assert.Empty(processes.Starts);
    }


    private static Profile Parse(string json)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(string.Join("; ", parsed.Error.Select(i => $"{i.Code}: {i.Message}")));
        }

        return parsed.Value;
    }

    private static string MinimalJson(
        IReadOnlyList<string>? scoop = null,
        IReadOnlyList<string>? scoopNeedsReboot = null)
    {
        List<string> fields = [];
        if (scoop is not null)
        {
            fields.Add($"\"scoop\": [{string.Join(",", scoop.Select(id => $"\"{id}\""))}]");
        }

        if (scoopNeedsReboot is not null)
        {
            fields.Add(
                $"\"scoopNeedsReboot\": [{string.Join(",", scoopNeedsReboot.Select(id => $"\"{id}\""))}]");
        }

        string packagesBody = string.Join(",\n                ", fields);
        return $$"""
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
              "packages": {
                {{packagesBody}}
              }
            }
            """;
    }
}
