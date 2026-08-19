using System.Text.Json;

using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ServicingWorkspaceTests
{
    [Fact]
    public void Leaf_names_match_manifest()
    {
        string root = Path.Combine(Path.GetTempPath(), "winmint-ws-" + Guid.NewGuid().ToString("N"));
        ServicingWorkspace ws = new(root);
        Assert.Equal(Path.Combine(root, "logs"), ws.Logs);
        Assert.Equal(Path.Combine(root, "payload"), ws.Payload);
        Assert.Equal(Path.Combine(root, "media"), ws.Media);
        Assert.Equal(Path.Combine(root, "evidence.json"), ws.Evidence);
        Assert.Equal(Path.Combine(root, "expected-evidence.json"), ws.ExpectedEvidence);
        Assert.Equal(Path.Combine(root, "failure.json"), ws.Failure);
        Assert.Equal(Path.Combine(root, "apply-status.txt"), ws.ApplyStatus);
        Assert.Equal(Path.Combine(root, "stages.json"), ws.Stages);
        Assert.Equal(Path.Combine(root, "install.wim"), ws.InstallWim);
        Assert.Equal(Path.Combine(root, "unattend.xml"), ws.Unattend);
        Assert.Equal(Path.Combine(root, "logs", "digests.json"), ws.Digests);
        Assert.Equal(Path.Combine(root, "quality-packages"), ws.QualityPackages);
        Assert.Equal("media.incoming-", ServicingWorkspace.IncomingMediaPrefix);
        Assert.Equal("media.previous-", ServicingWorkspace.PreviousMediaPrefix);
        Assert.Equal(
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WinMint",
                "work",
                "gate-b"),
            HostDefaults.GateBWorkDirectory);
    }

    [Fact]
    public async Task Apply_writes_expected_evidence_with_posture_keys()
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile("""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": { "mode": "localAutoLogon", "username": "winmint", "password": "lab-only" },
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
            """u8.ToArray());
        Assert.True(parsed.IsOk);
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk);

        string work = Path.Combine(Path.GetTempPath(), "winmint-expected-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "source.iso"), "iso-stub");
            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                planned.Value,
                new ServicingRun(
                    Path.Combine(work, "source.iso"),
                    work,
                    Path.Combine(work, "out.iso")),
                new ImageServicingTestFakes.RecordingElevatedPlanRunner(),
                TestContext.Current.CancellationToken);
            Assert.True(result.IsOk, result.IsOk ? null : result.Error.Message);

            using JsonDocument doc = JsonDocument.Parse(
                File.ReadAllBytes(Path.Combine(work, "expected-evidence.json")));
            Assert.Equal(
                ImageServicing.ExpectedEvidenceSchemaVersion,
                doc.RootElement.GetProperty("schemaVersion").GetString());
            HashSet<string> keys = doc.RootElement.GetProperty("requiredDigestKeys")
                .EnumerateArray()
                .Select(static e => e.GetString()!)
                .ToHashSet(StringComparer.Ordinal);
            foreach (string digest in ProductPosture.AlwaysOnDigestKeys)
            {
                Assert.Contains(digest, keys);
            }

            HashSet<string> winget = doc.RootElement.GetProperty("requiredWingetIds")
                .EnumerateArray()
                .Select(static e => e.GetString()!)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (string id in ProductPosture.WingetIds)
            {
                Assert.Contains(id, winget);
            }
        }
        finally
        {
            try
            {
                Directory.Delete(work, recursive: true);
            }
            catch
            {
                // ponytail: temp cleanup
            }
        }
    }
}
