using System.Text.Json;
using WinMint.Orchestrator;
using WinMint.Provisioning;

namespace WinMint.Tests;

public class FileSecretScrubberTests
{
    [Fact]
    public void Wipe_redacts_password_via_source_gen_roundtrip()
    {
        string dir = Path.Combine(Path.GetTempPath(), "winmint-wipe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "bundle.json");
        try
        {
            File.WriteAllText(
                path,
                $$"""
                {
                  "schemaVersion": "{{BundleLoader.SchemaVersion}}",
                  "supervisorPath": {{JsonSerializer.Serialize(ImageServicing.ShellStampGuestPath)}},
                  "username": "winmint",
                  "password": "lab-secret",
                  "dmaEnabled": true,
                  "settle": null,
                  "jobIds": []
                }
                """);

            ProvisioningBundle bundle = BundleLoader.LoadFromFile(path);
            Assert.Equal("lab-secret", bundle.Account.Password);

            FileSecretScrubber scrubber = new(path);
            scrubber.Wipe(bundle);

            using JsonDocument doc = JsonDocument.Parse(File.ReadAllText(path));
            Assert.Equal("", doc.RootElement.GetProperty("password").GetString());
            Assert.Equal("winmint", doc.RootElement.GetProperty("username").GetString());

            ProvisioningBundle reloaded = BundleLoader.LoadFromFile(path);
            Assert.Equal("", reloaded.Account.Password);
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
