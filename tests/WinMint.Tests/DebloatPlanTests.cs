using System.Text;

using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>Ticket 11 — keep-flag remove-list at S1 (BuildPlan).</summary>
public class DebloatPlanTests
{
    [Fact]
    public void Plan_empty_remove_list_emits_no_remove_stages()
    {
        Profile profile = Parse(MinimalProfileJson());

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        Assert.DoesNotContain(ServicingOpcode.RemoveProvisionedAppx, result.Value.Stages);
        Assert.Empty(profile.RemoveProvisionedAppx);
    }

    [Fact]
    public void Plan_absent_debloat_emits_no_remove_stages()
    {
        Profile profile = Parse(MinimalProfileJson(includeDebloat: false));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        Assert.DoesNotContain(ServicingOpcode.RemoveProvisionedAppx, result.Value.Stages);
    }

    [Fact]
    public void Plan_unknown_remove_id_fails()
    {
        Profile profile = Parse(MinimalProfileJson(removeIds: ["NotAReal.Package.Family"]));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.False(result.IsOk);
        Assert.Equal("debloat.removeProvisionedAppx.unknown", result.Error.Code);
        Assert.Contains("NotAReal.Package.Family", result.Error.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Plan_known_remove_ids_emit_opcode_params_without_ps1_paths()
    {
        Profile profile = Parse(MinimalProfileJson(removeIds:
        [
            "Microsoft.BingNews",
            "Microsoft.GamingApp",
        ], debloatMode: "offline"));

        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
        Assert.Contains(ServicingOpcode.RemoveProvisionedAppx, result.Value.Stages);
        Assert.Equal(
            ProductPosture.UnionAppx(["Microsoft.BingNews", "Microsoft.GamingApp"]),
            result.Value.RemoveProvisionedAppx);

        IReadOnlyList<ServicingOpcode> opcodes = result.Value.Stages;
        int mountAt = opcodes.ToList().IndexOf(ServicingOpcode.MountInstallWim);
        int removeAt = opcodes.ToList().IndexOf(ServicingOpcode.RemoveProvisionedAppx);
        int payloadAt = opcodes.ToList().IndexOf(ServicingOpcode.StagePayload);
        Assert.True(mountAt >= 0 && removeAt > mountAt && removeAt < payloadAt);
    }

    private static string MinimalProfileJson(
        bool includeDebloat = true,
        IReadOnlyList<string>? removeIds = null,
        string? debloatMode = null)
    {
        string debloat = "";
        if (includeDebloat)
        {
            string[] ids = removeIds?.ToArray() ?? [];
            string array = ids.Length == 0
                ? "[]"
                : "[" + string.Join(",", ids.Select(id => $"\"{id}\"")) + "]";
            string modeLine = debloatMode is null
                ? ""
                : $$"""
                      "mode": "{{debloatMode}}",
                  """;
            debloat = $$"""
                  ,
                  "debloat": {
                    {{modeLine}}
                    "removeProvisionedAppx": {{array}}
                  }
                """;
        }

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
              }{{debloat}}
            }
            """;
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
}
