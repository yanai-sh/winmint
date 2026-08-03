using System.Text.Json;
using System.Text.Json.Serialization;

namespace WinMint.Orchestrator;

public static class BuildPlan
{
    public const string ProfileSchemaVersion = "winmint.profile/v1";
    public const string JobsSchemaVersion = "winmint.jobs/v1";
    public const string StagesSchemaVersion = "winmint.servicing.stages/v1";

    public const string IrelandSetupLocale = "en-IE";
    public const int IrelandSetupGeoId = 68;

    public static Result<Profile, DocumentErrors> TryParseProfile(ReadOnlySpan<byte> utf8Json)
    {
        if (utf8Json.IsEmpty)
        {
            return Result.Fail<Profile, DocumentErrors>(InvalidJson("Document is empty."));
        }

        ProfileDocument? doc;
        try
        {
            doc = JsonSerializer.Deserialize(utf8Json, BuildPlanJsonContext.Default.ProfileDocument);
        }
        catch (JsonException ex)
        {
            return Result.Fail<Profile, DocumentErrors>(InvalidJson(ex.Message));
        }

        if (doc is null)
        {
            return Result.Fail<Profile, DocumentErrors>(InvalidJson("Document deserialized to null."));
        }

        List<DocumentError> issues = [];

        if (string.IsNullOrWhiteSpace(doc.SchemaVersion))
        {
            issues.Add(new DocumentError("document.schemaVersion.missing", "schemaVersion is required.", "schemaVersion"));
        }
        else if (!string.Equals(doc.SchemaVersion, ProfileSchemaVersion, StringComparison.Ordinal))
        {
            issues.Add(new DocumentError(
                "document.schemaVersion.unsupported",
                $"Unsupported schemaVersion '{doc.SchemaVersion}'. Expected '{ProfileSchemaVersion}'.",
                "schemaVersion"));
        }

        if (doc.Account is null)
        {
            issues.Add(new DocumentError("account.missing", "account is required.", "account"));
        }

        if (doc.Dma is null)
        {
            issues.Add(new DocumentError("dma.missing", "dma is required.", "dma"));
        }
        else if (doc.Dma.Settle is null)
        {
            issues.Add(new DocumentError("dma.settle.missing", "dma.settle is required.", "dma.settle"));
        }

        AccountMode? mode = null;
        if (doc.Account is not null)
        {
            if (string.IsNullOrWhiteSpace(doc.Account.Mode))
            {
                issues.Add(new DocumentError("account.mode.missing", "account.mode is required.", "account.mode"));
            }
            else if (!string.Equals(doc.Account.Mode, AccountModeWire.LocalAutoLogon, StringComparison.Ordinal))
            {
                issues.Add(new DocumentError(
                    "account.mode.unsupported",
                    $"Unsupported account.mode '{doc.Account.Mode}'. Smoke supports {AccountModeWire.LocalAutoLogon} only.",
                    "account.mode"));
            }
            else
            {
                mode = AccountMode.LocalAutoLogon;
            }

            if (string.IsNullOrWhiteSpace(doc.Account.Username))
            {
                issues.Add(new DocumentError("account.username.missing", "account.username is required.", "account.username"));
            }
        }

        if (issues.Count > 0)
        {
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(issues));
        }

        DmaSettleDocument settle = doc.Dma!.Settle!;
        if (string.IsNullOrWhiteSpace(settle.Locale)
            || string.IsNullOrWhiteSpace(settle.TimeZoneId)
            || settle.GeoId is null
            || settle.LocationServicesEnabled is null)
        {
            issues.Add(new DocumentError(
                "dma.settle.incomplete",
                "dma.settle requires locale, geoId, timeZoneId, and locationServicesEnabled.",
                "dma.settle"));
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(issues));
        }

        Profile profile = new(
            new AccountProfile(mode!.Value, doc.Account!.Username!, doc.Account.Password),
            new DmaProfile(
                doc.Dma.Enabled ?? true,
                new DmaSettleTarget(
                    settle.Locale,
                    settle.GeoId.Value,
                    settle.TimeZoneId,
                    settle.LocationServicesEnabled.Value)),
            NormalizeRemoveList(doc.Debloat?.RemoveProvisionedAppx));

        return Result.Ok<Profile, DocumentErrors>(profile);
    }

    private static string[] NormalizeRemoveList(string[]? raw)
    {
        if (raw is null || raw.Length == 0)
        {
            return [];
        }

        return raw
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Select(s => s.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public static Result<BuildArtifacts, PlanFailure> Plan(Profile profile, RunOptions? run = null)
    {
        RunOptions options = run ?? new RunOptions();

        if (profile.Account.Mode == AccountMode.LocalAutoLogon
            && string.IsNullOrEmpty(profile.Account.Password))
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(
                new PlanFailure("account.password.required", "Local autoLogon requires a non-empty password."));
        }

        foreach (string id in profile.RemoveProvisionedAppx)
        {
            if (!ProvisionedAppxCatalog.Contains(id))
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(
                    new PlanFailure(
                        "debloat.removeProvisionedAppx.unknown",
                        $"removeProvisionedAppx id '{id}' is not in the shipped provisioned AppX catalog."));
            }
        }

        string unattendXml = profile.Dma.Enabled
            ? $$"""
              <?xml version="1.0" encoding="utf-8"?>
              <unattend xmlns="urn:schemas-microsoft-com:unattend">
                <settings pass="specialize">
                  <component name="Microsoft-Windows-International-Core" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                    <InputLocale>{{IrelandSetupLocale}}</InputLocale>
                    <SystemLocale>{{IrelandSetupLocale}}</SystemLocale>
                    <UILanguage>{{IrelandSetupLocale}}</UILanguage>
                    <UserLocale>{{IrelandSetupLocale}}</UserLocale>
                  </component>
                  <component name="Microsoft-Windows-Deployment" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                    <RunSynchronous>
                      <RunSynchronousCommand wcm:action="add">
                        <Order>1</Order>
                        <Description>WinMint DMA setup GeoID latch (Ireland {{IrelandSetupGeoId}})</Description>
                        <Path>reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control\Nls\Geo" /v Nation /t REG_SZ /d {{IrelandSetupGeoId}} /f</Path>
                      </RunSynchronousCommand>
                    </RunSynchronous>
                  </component>
                </settings>
              </unattend>
              """
            : """
              <?xml version="1.0" encoding="utf-8"?>
              <unattend xmlns="urn:schemas-microsoft-com:unattend" />
              """;

        // Stub Smoke job set — real installs land later; executor shape shared with metal.
        JobsArtifact jobs = new(
            JobsSchemaVersion,
            [
                new JobDescriptor("smoke.stub.ready", "stub"),
                new JobDescriptor("smoke.stub.complete", "stub"),
            ]);

        PayloadManifest payload = new(
        [
            "Supervisor.exe",
            "SetupComplete.cmd",
            "jobs.json",
        ]);

        string laneName;
        string compression;
        string cleanup;
        if (options.ImageQuality == ImageQualityLane.Release)
        {
            laneName = "Release";
            compression = "max";
            cleanup = "full";
        }
        else
        {
            laneName = "Test";
            compression = "fast";
            cleanup = "skip";
        }

        List<ServicingStage> stageList =
        [
            new ServicingStage(ServicingOpcode.MountInstallWim, Dict((StageParams.SourceIso, options.SourceIsoPath ?? ""))),
        ];

        if (profile.RemoveProvisionedAppx.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.RemoveProvisionedAppx,
                Dict((StageParams.PackageFamilyNames, string.Join(';', profile.RemoveProvisionedAppx)))));
        }

        stageList.AddRange(
        [
            new ServicingStage(ServicingOpcode.StagePayload, Dict()),
            new ServicingStage(ServicingOpcode.InjectUnattend, Dict()),
            new ServicingStage(ServicingOpcode.StampOfflineShell, Dict((StageParams.ShellTarget, "Supervisor.exe"))),
            new ServicingStage(
                ServicingOpcode.ExportWim,
                Dict((StageParams.Lane, laneName), (StageParams.Compression, compression), (StageParams.Cleanup, cleanup))),
            new ServicingStage(ServicingOpcode.BuildIso, Dict((StageParams.OutputIso, options.OutputIsoPath ?? ""))),
        ]);

        ServicingStageList stages = new(stageList);

        BuildArtifacts artifacts = new(
            new UnattendArtifact(unattendXml),
            jobs,
            payload,
            stages,
            new DmaContract(profile.Dma.Enabled, profile.Dma.Enabled ? profile.Dma.Settle : null),
            new BuildManifest(options.ImageQuality),
            profile.Account);

        return Result.Ok<BuildArtifacts, PlanFailure>(artifacts);
    }

    private static DocumentErrors InvalidJson(string message) =>
        new([new DocumentError("document.invalidJson", message)]);

    private static Dictionary<string, string> Dict(params (string Key, string Value)[] pairs)
    {
        Dictionary<string, string> map = new(pairs.Length, StringComparer.Ordinal);
        foreach ((string key, string value) in pairs)
        {
            map[key] = value;
        }

        return map;
    }
}

internal sealed record ProfileDocument(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("account")] AccountDocument? Account,
    [property: JsonPropertyName("dma")] DmaDocument? Dma,
    [property: JsonPropertyName("debloat")] DebloatDocument? Debloat);

internal sealed record DebloatDocument(
    [property: JsonPropertyName("removeProvisionedAppx")] string[]? RemoveProvisionedAppx);

internal sealed record AccountDocument(
    [property: JsonPropertyName("mode")] string? Mode,
    [property: JsonPropertyName("username")] string? Username,
    [property: JsonPropertyName("password")] string? Password);

internal sealed record DmaDocument(
    [property: JsonPropertyName("enabled")] bool? Enabled,
    [property: JsonPropertyName("settle")] DmaSettleDocument? Settle);

internal sealed record DmaSettleDocument(
    [property: JsonPropertyName("locale")] string? Locale,
    [property: JsonPropertyName("geoId")] int? GeoId,
    [property: JsonPropertyName("timeZoneId")] string? TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool? LocationServicesEnabled);

[JsonSerializable(typeof(ProfileDocument))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class BuildPlanJsonContext : JsonSerializerContext;
