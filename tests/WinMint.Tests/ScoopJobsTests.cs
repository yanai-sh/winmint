using System.Text;
using WinMint.Orchestrator;
using WinMint.Provisioning;
using static WinMint.Tests.ProvisioningSessionTestFakes;

namespace WinMint.Tests;

/// <summary>Ticket 18 — metal scoop job at S1 (Plan) + S3 (Run).</summary>
public class ScoopJobsTests
{
    [Fact]
    public void Plan_emits_scoop_jobs_from_packages_scoop()
    {
        Profile profile = Parse(MinimalJson(scoop: ["curl", "jq"]));

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor curl = Assert.Single(result.Value.Jobs.Jobs, j => j.Kind == "scoop" && j.PackageId == "curl");
        Assert.Equal("scoop.curl", curl.Id);
        Assert.False(curl.NeedsReboot);
        Assert.Contains(result.Value.Jobs.Jobs, j => j.Kind == "scoop" && j.PackageId == "jq");
    }

    [Fact]
    public void Plan_scoopNeedsReboot_subset_emits_needsReboot()
    {
        Profile profile = Parse(MinimalJson(scoop: ["curl"], scoopNeedsReboot: ["curl"]));

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        JobDescriptor curl = Assert.Single(result.Value.Jobs.Jobs, j => j.PackageId == "curl");
        Assert.True(curl.NeedsReboot);
    }

    [Fact]
    public void Plan_scoopNeedsReboot_id_not_in_scoop_fails_closed()
    {
        Profile profile = Parse(MinimalJson(scoop: ["curl"], scoopNeedsReboot: ["jq"]));

        Result<BuildArtifacts, PlanFailure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("packages.scoopNeedsReboot.unknown", result.Error.Code);
    }

    [Fact]
    public void Shell_scoop_bootstraps_then_installs_when_scoop_missing()
    {
        RecordingProcessHost processes = new()
        {
            OnRun = (file, args) =>
            {
                if (file.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase))
                {
                    return new ProcessStartResult(0);
                }

                return new ProcessStartResult(0);
            },
        };
        RecordingEvidenceSink evidence = new();

        string userScoop = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop",
            "shims");
        bool createdShim = false;
        string? previous = null;
        string target = Path.Combine(userScoop, "scoop.cmd");
        try
        {
            Directory.CreateDirectory(userScoop);
            if (File.Exists(target))
            {
                previous = File.ReadAllText(target);
            }
            else
            {
                createdShim = true;
            }

            File.WriteAllText(target, "@echo off");

            SessionResult result = ProvisioningSession.Run(
                SessionMode.Shell,
                Bundle(jobs: [new ProvisionJob("scoop.curl", "scoop", PackageId: "curl")]),
                Env(processes, evidence),
                TestContext.Current.CancellationToken);

            Assert.Equal(SessionOutcome.Complete, result.Outcome);
            Assert.Equal("jobs.ok", result.FinalStatus.Code);
            Assert.DoesNotContain(
                processes.Starts,
                s => s.FileName.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase));
            Assert.Contains(
                processes.Starts,
                s => s.FileName.EndsWith("scoop.cmd", StringComparison.OrdinalIgnoreCase)
                    && s.Arguments is ["install", "curl"]);
        }
        finally
        {
            if (createdShim && File.Exists(target))
            {
                File.Delete(target);
            }
            else if (previous is not null)
            {
                File.WriteAllText(target, previous);
            }
        }
    }

    [Fact]
    public void Shell_scoop_bootstraps_via_official_admin_one_liner_when_missing()
    {
        string userScoopShim = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "scoop",
            "shims",
            "scoop.cmd");

        bool moved = false;
        string backupPath = userScoopShim + ".winmint-test-bak";
        try
        {
            if (File.Exists(userScoopShim))
            {
                File.Move(userScoopShim, backupPath, overwrite: true);
                moved = true;
            }

            RecordingProcessHost processes = new()
            {
                OnRun = (file, args) =>
                {
                    if (file.Equals("powershell.exe", StringComparison.OrdinalIgnoreCase))
                    {
                        return new ProcessStartResult(0);
                    }

                    return new ProcessStartResult(0);
                },
            };
            RecordingEvidenceSink evidence = new();

            SessionResult result = ProvisioningSession.Run(
                SessionMode.Shell,
                Bundle(jobs: [new ProvisionJob("scoop.curl", "scoop", PackageId: "curl")]),
                Env(processes, evidence),
                TestContext.Current.CancellationToken);

            Assert.Equal(SessionOutcome.Failed, result.Outcome);
            Assert.Equal("jobs.scoop.bootstrap_failed", result.FinalStatus.Code);
            Assert.Single(processes.Starts);
            Assert.Equal("powershell.exe", processes.Starts[0].FileName, StringComparer.OrdinalIgnoreCase);
            Assert.Equal("-NoProfile", processes.Starts[0].Arguments[0]);
            Assert.Equal("-ExecutionPolicy", processes.Starts[0].Arguments[1]);
            Assert.Equal("Bypass", processes.Starts[0].Arguments[2]);
            Assert.Equal("-Command", processes.Starts[0].Arguments[3]);
            Assert.Contains("get.scoop.sh", processes.Starts[0].Arguments[4]);
            Assert.Contains("-RunAsAdmin", processes.Starts[0].Arguments[4]);
        }
        finally
        {
            if (moved && File.Exists(backupPath))
            {
                File.Move(backupPath, userScoopShim, overwrite: true);
            }
        }
    }

    [Fact]
    public void Shell_unknown_job_kind_still_unsupported()
    {
        RecordingProcessHost processes = new();
        RecordingEvidenceSink evidence = new();

        SessionResult result = ProvisioningSession.Run(
            SessionMode.Shell,
            Bundle(jobs: [new ProvisionJob("metal.browser", "browser")]),
            Env(processes, evidence),
            TestContext.Current.CancellationToken);

        Assert.Equal(SessionOutcome.Failed, result.Outcome);
        Assert.Equal("jobs.kind.unsupported", result.FinalStatus.Code);
        Assert.Empty(processes.Starts);
    }

    private static Profile Parse(string json)
    {
        Result<Profile, DocumentErrors> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(string.Join("; ", parsed.Error.Issues.Select(i => $"{i.Code}: {i.Message}")));
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
              },
              "packages": {
                {{packagesBody}}
              }
            }
            """;
    }
}
