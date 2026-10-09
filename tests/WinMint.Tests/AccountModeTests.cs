using System.Text;

using WinMint.Orchestrator;

namespace WinMint.Tests;

public class AccountModeTests
{
    [Fact]
    public void Parse_oobeLocal_without_password_succeeds()
    {
        Result<Profile, IReadOnlyList<DocumentError>> result = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.OobeLocalMode}}"
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

        Assert.True(result.IsOk, Format(result));
        Assert.Equal(AccountProfile.OobeLocalMode, result.Value.Account.Mode);
        Assert.Equal("", result.Value.Account.Username);
        Assert.Null(result.Value.Account.Password);
        Assert.Null(result.Value.Account.PasswordPath);
    }

    [Fact]
    public void Parse_oobeLocal_optional_username_accepted()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.OobeLocalMode}}",
                "username": "hint"
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

        Assert.Equal(AccountProfile.OobeLocalMode, profile.Account.Mode);
        Assert.Equal("hint", profile.Account.Username);
    }

    [Fact]
    public void Parse_oobeLocal_with_password_fails()
    {
        Result<Profile, IReadOnlyList<DocumentError>> result = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.OobeLocalMode}}",
                "password": "secret"
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
        Assert.Contains(result.Error, i => i.Code == "account.password.forbidden");
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
    public void Plan_oobeLocal_unattend_omits_AutoLogon()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.OobeLocalMode}}",
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
        Assert.DoesNotContain("AutoLogon", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("UserAccounts", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("LocalAccounts", xml, StringComparison.Ordinal);
        Assert.Contains("<HideOnlineAccountScreens>true</HideOnlineAccountScreens>", xml, StringComparison.Ordinal);
        Assert.Contains("<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_localAutoLogon_still_emits_AutoLogon()
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

        Assert.True(result.IsOk);
        string xml = result.Value.Unattend.Xml;
        Assert.Contains("AutoLogon", xml, StringComparison.Ordinal);
        Assert.Contains("LocalAccounts", xml, StringComparison.Ordinal);
        Assert.Contains("<Username>winmint</Username>", xml, StringComparison.Ordinal);
    }

    [Fact]
    public void SerializeProfile_roundtrips_oobeLocal()
    {
        Profile profile = Parse($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.OobeLocalMode}}"
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
        Assert.Contains($"\"mode\": \"{AccountProfile.OobeLocalMode}\"", json, StringComparison.Ordinal);
        Assert.DoesNotContain("password", json, StringComparison.OrdinalIgnoreCase);

        Result<Profile, IReadOnlyList<DocumentError>> again = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));
        Assert.True(again.IsOk, Format(again));
        Assert.Equal(AccountProfile.OobeLocalMode, again.Value.Account.Mode);
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
