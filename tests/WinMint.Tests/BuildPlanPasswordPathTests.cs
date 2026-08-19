using System.Text;

using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>S1 — BuildPlan passwordPath purity (no filesystem I/O).</summary>
public class BuildPlanPasswordPathTests
{
    [Fact]
    public void TryParseProfile_path_only_retains_authored_path_without_reading()
    {
        string missing = Path.Combine(Path.GetTempPath(), "winmint-never-" + Guid.NewGuid().ToString("N") + ".txt");
        string json = MinimalProfile(passwordPath: missing);

        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));

        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Select(i => i.Code)));
        Assert.Null(parsed.Value.Account.Password);
        Assert.Equal(missing, parsed.Value.Account.PasswordPath);
    }

    [Fact]
    public void TryParseProfile_same_bytes_are_cwd_independent()
    {
        string json = MinimalProfile(passwordPath: "relative-secret.txt");
        byte[] utf8 = Encoding.UTF8.GetBytes(json);

        string cwd = Directory.GetCurrentDirectory();
        string other = Path.Combine(Path.GetTempPath(), "winmint-cwd-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(other);
        try
        {
            Result<Profile, IReadOnlyList<DocumentError>> a = BuildPlan.TryParseProfile(utf8);
            Directory.SetCurrentDirectory(other);
            Result<Profile, IReadOnlyList<DocumentError>> b = BuildPlan.TryParseProfile(utf8);

            Assert.True(a.IsOk);
            Assert.True(b.IsOk);
            Assert.Equal(a.Value.Account.Password, b.Value.Account.Password);
            Assert.Equal(a.Value.Account.PasswordPath, b.Value.Account.PasswordPath);
        }
        finally
        {
            Directory.SetCurrentDirectory(cwd);
            Directory.Delete(other, recursive: true);
        }
    }

    [Fact]
    public void TryParseProfile_both_password_sources_conflict()
    {
        string json = MinimalProfile(password: "inline", passwordPath: "secret.txt");

        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));

        Assert.False(parsed.IsOk);
        Assert.Contains(parsed.Error, i => i.Code == "account.password.sources.conflict");
    }

    [Fact]
    public void Plan_unresolved_path_only_fails_password_required()
    {
        Profile profile = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(
            MinimalProfile(passwordPath: @"C:\never\reads\this.txt"))).Value;

        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);

        Assert.False(planned.IsOk);
        Assert.Equal("account.password.required", planned.Error.Code);
    }

    [Fact]
    public void SerializeProfile_materialized_path_backed_omits_inline_password()
    {
        Profile parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(
            MinimalProfile(passwordPath: "secret.txt"))).Value;
        Profile materialized = parsed with
        {
            Account = parsed.Account with { Password = "from-path" },
        };

        string roundTrip = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(materialized));

        Assert.Contains("passwordPath", roundTrip, StringComparison.Ordinal);
        Assert.DoesNotContain("\"password\"", roundTrip, StringComparison.Ordinal);
    }

    private static string MinimalProfile(string? password = null, string? passwordPath = null)
    {
        string secret = password is not null
            ? $$"""
                "password": {{JsonEscape(password)}},
                """
            : passwordPath is not null
                ? $$"""
                    "passwordPath": {{JsonEscape(passwordPath)}},
                    """
                : "";

        if (password is not null && passwordPath is not null)
        {
            secret = $$"""
                "password": {{JsonEscape(password)}},
                "passwordPath": {{JsonEscape(passwordPath)}},
                """;
        }

        return $$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "localAutoLogon",
                "username": "yanai",
                {{secret}}
                "requireWifiDuringOobe": false
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
        "\"" + value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal) + "\"";
}
