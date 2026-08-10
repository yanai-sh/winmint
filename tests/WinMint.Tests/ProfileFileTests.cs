using System.Text;
using System.Text.Json;
using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Host Profile loading seam — real temporary directories (issue 91).</summary>
public class ProfileFileTests
{
    [Fact]
    public void TryLoad_inline_password_no_secondary_read()
    {
        using TempProfileDir dir = new();
        string path = dir.WriteProfile(MinimalProfile(password: "lab-only"));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

        Assert.True(loaded.IsOk, Format(loaded));
        Assert.Equal("lab-only", loaded.Value.Account.Password);
        Assert.Null(loaded.Value.Account.PasswordPath);
    }

    [Fact]
    public void TryLoad_absolute_passwordPath_materializes_and_retains_authored_path()
    {
        using TempProfileDir dir = new();
        string pwFile = Path.Combine(dir.Root, "secret.txt");
        File.WriteAllText(pwFile, "from-abs\n");
        string path = dir.WriteProfile(MinimalProfile(passwordPath: pwFile));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

        Assert.True(loaded.IsOk, Format(loaded));
        Assert.Equal("from-abs", loaded.Value.Account.Password);
        Assert.Equal(pwFile, loaded.Value.Account.PasswordPath);

        string roundTrip = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(loaded.Value));
        Assert.Contains("passwordPath", roundTrip, StringComparison.Ordinal);
        Assert.DoesNotContain("\"password\"", roundTrip, StringComparison.Ordinal);
    }

    [Fact]
    public void TryLoad_relative_passwordPath_resolves_against_profile_directory()
    {
        using TempProfileDir dir = new();
        string scratch = Path.Combine(dir.Root, "scratch");
        Directory.CreateDirectory(scratch);
        File.WriteAllText(Path.Combine(scratch, "secret.txt"), "from-rel\r\n");
        string profiles = Path.Combine(dir.Root, "profiles");
        Directory.CreateDirectory(profiles);
        string path = Path.Combine(profiles, "metal.profile.json");
        File.WriteAllText(path, MinimalProfile(passwordPath: @"..\scratch\secret.txt"));

        string cwd = Directory.GetCurrentDirectory();
        string other = Path.Combine(Path.GetTempPath(), "winmint-pf-cwd-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(other);
        try
        {
            Directory.SetCurrentDirectory(other);
            Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

            Assert.True(loaded.IsOk, Format(loaded));
            Assert.Equal("from-rel", loaded.Value.Account.Password);
            Assert.Equal(@"..\scratch\secret.txt", loaded.Value.Account.PasswordPath);
        }
        finally
        {
            Directory.SetCurrentDirectory(cwd);
            Directory.Delete(other, recursive: true);
        }
    }

    [Fact]
    public void TryLoad_drive_relative_passwordPath_fails_closed()
    {
        using TempProfileDir dir = new();
        // Ambient drive-current form — must not depend on process drive state.
        string path = dir.WriteProfile(MinimalProfile(passwordPath: @"C:ambient-secret.txt"));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

        Assert.False(loaded.IsOk);
        Assert.Contains(loaded.Error.Issues, i => i.Code == "account.passwordPath.unreadable");
    }

    [Fact]
    public void TryLoad_root_relative_passwordPath_fails_closed()
    {
        using TempProfileDir dir = new();
        string path = dir.WriteProfile(MinimalProfile(passwordPath: @"\Windows\never.txt"));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

        Assert.False(loaded.IsOk);
        Assert.Contains(loaded.Error.Issues, i => i.Code == "account.passwordPath.unreadable");
    }

    [Fact]
    public void TryLoad_missing_profile_fails_closed()
    {
        string missing = Path.Combine(Path.GetTempPath(), "winmint-missing-" + Guid.NewGuid().ToString("N") + ".json");

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(missing);

        Assert.False(loaded.IsOk);
        Assert.Contains(loaded.Error.Issues, i => i.Code == "document.unreadable");
    }

    [Fact]
    public void TryLoad_missing_password_file_fails_closed()
    {
        using TempProfileDir dir = new();
        string missingPw = Path.Combine(dir.Root, "gone.txt");
        string path = dir.WriteProfile(MinimalProfile(passwordPath: missingPw));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

        Assert.False(loaded.IsOk);
        Assert.Contains(loaded.Error.Issues, i => i.Code == "account.passwordPath.unreadable");
    }

    [Fact]
    public void TryLoad_empty_password_file_materializes_empty_and_plan_fails()
    {
        using TempProfileDir dir = new();
        string pwFile = Path.Combine(dir.Root, "empty.txt");
        File.WriteAllText(pwFile, "\r\n");
        string path = dir.WriteProfile(MinimalProfile(passwordPath: "empty.txt"));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);
        Assert.True(loaded.IsOk, Format(loaded));
        Assert.Equal("", loaded.Value.Account.Password);

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(loaded.Value);
        Assert.False(planned.IsOk);
        Assert.Equal("account.password.required", planned.Error.Code);
    }

    [Fact]
    public void TryLoad_source_conflict_before_password_file_io()
    {
        using TempProfileDir dir = new();
        string pwFile = Path.Combine(dir.Root, "secret.txt");
        File.WriteAllText(pwFile, "SHOULD-NOT-READ");
        string path = dir.WriteProfile(MinimalProfile(password: "inline", passwordPath: pwFile));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

        Assert.False(loaded.IsOk);
        Assert.Contains(loaded.Error.Issues, i => i.Code == "account.password.sources.conflict");
        Assert.All(
            loaded.Error.Issues,
            i => Assert.DoesNotContain("SHOULD-NOT-READ", i.Message, StringComparison.Ordinal));
    }

    [Fact]
    public void TryLoad_whitespace_only_passwordPath_is_absent()
    {
        using TempProfileDir dir = new();
        string path = dir.WriteProfile(MinimalProfile(password: "lab-only", passwordPathRaw: "   "));

        Result<Profile, DocumentErrors> loaded = ProfileFile.TryLoad(path);

        Assert.True(loaded.IsOk, Format(loaded));
        Assert.Equal("lab-only", loaded.Value.Account.Password);
        Assert.Null(loaded.Value.Account.PasswordPath);
    }

    private static string Format(Result<Profile, DocumentErrors> loaded) =>
        loaded.IsOk ? null! : string.Join("; ", loaded.Error.Issues.Select(i => $"{i.Code}: {i.Message}"));

    private static string MinimalProfile(
        string? password = null,
        string? passwordPath = null,
        string? passwordPathRaw = null)
    {
        List<string> accountFields =
        [
            """ "mode": "localAutoLogon" """,
            """ "username": "yanai" """,
            """ "requireWifiDuringOobe": false """,
        ];

        if (password is not null)
        {
            accountFields.Insert(2, $" \"password\": {JsonEscape(password)} ");
        }

        if (passwordPathRaw is not null)
        {
            accountFields.Insert(2, $" \"passwordPath\": {JsonEscape(passwordPathRaw)} ");
        }
        else if (passwordPath is not null)
        {
            accountFields.Insert(2, $" \"passwordPath\": {JsonEscape(passwordPath)} ");
        }

        return $$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                {{string.Join(",\n", accountFields)}}
              },
              "dma": {
                "enabled": true,
                "settle": {
                  "locale": "en-US",
                  "geoId": 117,
                  "timeZoneId": "Israel Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """;
    }

    private static string JsonEscape(string value) =>
        JsonSerializer.Serialize(value);

    private sealed class TempProfileDir : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "winmint-pf-" + Guid.NewGuid().ToString("N"));

        public TempProfileDir() => Directory.CreateDirectory(Root);

        public string WriteProfile(string json, string fileName = "profile.json")
        {
            string path = Path.Combine(Root, fileName);
            File.WriteAllText(path, json);
            return path;
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(Root))
                {
                    Directory.Delete(Root, recursive: true);
                }
            }
            catch (IOException)
            {
                // best-effort cleanup
            }
        }
    }
}
