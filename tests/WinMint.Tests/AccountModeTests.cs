using System.Text;

using WinMint.Orchestrator;

namespace WinMint.Tests;

public class AccountModeTests
{
    [Fact]
    public void Parse_oobeLocal_rejected()
    {
        Result<Profile, IReadOnlyList<DocumentError>> result = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes("""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "oobeLocal"
              },
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
            """));

        Assert.False(result.IsOk);
        Assert.Contains(result.Error, i => i.Code == "account.mode.unsupported");
    }

    [Fact]
    public void Parse_localAutoLogon_requires_username_and_password()
    {
        Result<Profile, IReadOnlyList<DocumentError>> result = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint"
              },
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
            """));

        Assert.False(result.IsOk);
        Assert.Contains(result.Error, i => i.Code == "account.password.missing");
    }

    [Fact]
    public void Parse_localAutoLogon_still_requires_username()
    {
        Result<Profile, IReadOnlyList<DocumentError>> result = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
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
              }
            }
            """));

        Assert.False(result.IsOk);
        Assert.Contains(result.Error, i => i.Code == "account.username.missing");
    }

    [Fact]
    public void Plan_localAutoLogon_emits_AutoLogon_and_StampOfflineShell()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only",
                "requireWifiDuringOobe": false
              },
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
            """);

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk, result.IsOk ? "" : result.Error.Code + ": " + result.Error.Message);
        string xml = result.Value.Unattend.Xml;
        Assert.Contains("AutoLogon", xml, StringComparison.Ordinal);
        Assert.Contains("LocalAccounts", xml, StringComparison.Ordinal);
        Assert.Contains("<Username>winmint</Username>", xml, StringComparison.Ordinal);
        Assert.Contains(ServicingOpcode.StampOfflineShell, result.Value.Stages);
        Assert.DoesNotContain("FirstLogonCommands", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void SerializeProfile_roundtrips_localAutoLogon()
    {
        Profile profile = Parse($$"""
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
              }
            }
            """);

        string json = Encoding.UTF8.GetString(BuildPlan.SerializeProfile(profile));
        Assert.Contains($"\"mode\": \"{AccountProfile.LocalAutoLogonMode}\"", json, StringComparison.Ordinal);

        Result<Profile, IReadOnlyList<DocumentError>> again = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        Assert.True(again.IsOk, Format(again));
        Assert.Equal(AccountProfile.LocalAutoLogonMode, again.Value.Account.Mode);
        Assert.Equal("winmint", again.Value.Account.Username);
    }

    private static Profile Parse(string json)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        if (!parsed.IsOk)
        {
            Assert.Fail(Format(parsed));
        }

        return parsed.Value;
    }

    private static string Format(Result<Profile, IReadOnlyList<DocumentError>> result) =>
        result.IsOk ? "ok" : string.Join("; ", result.Error.Select(i => $"{i.Code}: {i.Message}"));
}
