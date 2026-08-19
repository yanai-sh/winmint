using WinMint.Contracts;
using WinMint.Provisioning;

namespace WinMint.Tests;

public class BundleLoaderTests
{
    [Fact]
    public void LoadFromFile_unknown_job_kind_fails_closed()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-bundle-kind-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "bundle.json");
            File.WriteAllText(
                path,
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.SchemaVersion}}",
                  "supervisorPath": "C:\\Windows\\WinMint\\WinMint.Provisioning.exe",
                  "username": "winmint",
                  "password": "lab",
                  "dmaEnabled": false,
                  "settle": null
                }
                """);
            File.WriteAllText(
                Path.Combine(dir, "jobs.json"),
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.JobsSchemaVersion}}",
                  "jobs": [{ "id": "test.browser", "kind": "browser" }]
                }
                """);

            BundleLoadResult loaded = BundleLoader.LoadFromFile(path);
            Assert.False(loaded.IsOk);
            Assert.Equal("jobs.kind.unknown", loaded.Error.Code);
            Assert.Contains("browser", loaded.Error.Message, StringComparison.Ordinal);
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

    [Fact]
    public void LoadFromFile_parses_known_kinds_to_enum()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-bundle-ok-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "bundle.json");
            File.WriteAllText(
                path,
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.SchemaVersion}}",
                  "supervisorPath": "C:\\Windows\\WinMint\\WinMint.Provisioning.exe",
                  "username": "winmint",
                  "password": "lab",
                  "dmaEnabled": false,
                  "settle": null
                }
                """);
            File.WriteAllText(
                Path.Combine(dir, "jobs.json"),
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.JobsSchemaVersion}}",
                  "jobs": [
                    { "id": "smoke.stub.ready", "kind": "stub" },
                    { "id": "winget.jqlang.jq", "kind": "winget", "packageId": "jqlang.jq" },
                    { "id": "scoop.curl", "kind": "scoop", "packageId": "curl" },
                    { "id": "wsl.Ubuntu", "kind": "wsl", "packageId": "Ubuntu" },
                    { "id": "debloat.appx.safetyNet", "kind": "appx.safetyNet" }
                  ]
                }
                """);

            BundleLoadResult loaded = BundleLoader.LoadFromFile(path);
            Assert.True(loaded.IsOk, loaded.IsOk ? null : $"{loaded.Error.Code}: {loaded.Error.Message}");
            Assert.Equal(
                [
                    ProvisionJobKind.Stub,
                    ProvisionJobKind.Winget,
                    ProvisionJobKind.Scoop,
                    ProvisionJobKind.Wsl,
                    ProvisionJobKind.AppxSafetyNet,
                ],
                loaded.Value.Jobs.Select(j => j.Kind).ToArray());
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
