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

    /// <summary>Generic Win11 Pro setup key — skips product-key page; does not activate (SPLASH).</summary>
    public const string ProSetupProductKey = "VK7JG-NPHTM-C97JM-9MPGT-3V66T";

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

        // Default true: metal contract shows OOBE Network; Smoke Profiles set false explicitly.
        bool requireWifi = doc.Account!.RequireWifiDuringOobe ?? true;

        Profile profile = new(
            new AccountProfile(mode!.Value, doc.Account.Username!, doc.Account.Password, requireWifi),
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

        string unattendXml = BuildAutounattendXml(profile);

        // Stub Smoke job set — real installs land later; executor shape shared with metal.
        // Keep-flag safety net when Profile remove-list is non-empty (ticket 13).
        List<JobDescriptor> jobList =
        [
            new JobDescriptor("smoke.stub.ready", "stub"),
            new JobDescriptor("smoke.stub.complete", "stub"),
        ];
        if (profile.RemoveProvisionedAppx.Count > 0)
        {
            jobList.Add(new JobDescriptor("keepflag.appx.safetyNet", "appx.safetyNet"));
        }

        JobsArtifact jobs = new(JobsSchemaVersion, jobList);

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

    /// <summary>
    /// ISO-root Autounattend (windowsPE + oobeSystem) plus optional specialize DMA latch.
    /// Panther copy alone cannot drive WinPE — 25H2 ConX shows "Select setup option" without this.
    /// </summary>
    internal static string BuildAutounattendXml(Profile profile)
    {
        string user = XmlEscape(profile.Account.Username);
        string pass = XmlEscape(profile.Account.Password ?? "");
        // Official Unattend: show Network when false/omit; hide when true (Smoke headless).
        // docs/research/2026-08-04-oobe-wifi-local-account.md
        string hideWireless = profile.Account.RequireWifiDuringOobe ? "false" : "true";
        string specialize = profile.Dma.Enabled
            ? $$"""
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
                """
            : "";

        return $$"""
            <?xml version="1.0" encoding="utf-8"?>
            <unattend xmlns="urn:schemas-microsoft-com:unattend">
              <settings pass="windowsPE">
                <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                  <SetupUILanguage>
                    <UILanguage>en-US</UILanguage>
                  </SetupUILanguage>
                  <InputLocale>en-US</InputLocale>
                  <SystemLocale>en-US</SystemLocale>
                  <UILanguage>en-US</UILanguage>
                  <UserLocale>en-US</UserLocale>
                </component>
                <component name="Microsoft-Windows-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                  <UserData>
                    <AcceptEula>true</AcceptEula>
                    <ProductKey>
                      <Key>{{ProSetupProductKey}}</Key>
                    </ProductKey>
                  </UserData>
                  <DiskConfiguration>
                    <Disk wcm:action="add">
                      <DiskID>0</DiskID>
                      <WillWipeDisk>true</WillWipeDisk>
                      <CreatePartitions>
                        <CreatePartition wcm:action="add">
                          <Order>1</Order>
                          <Type>EFI</Type>
                          <Size>100</Size>
                        </CreatePartition>
                        <CreatePartition wcm:action="add">
                          <Order>2</Order>
                          <Type>MSR</Type>
                          <Size>16</Size>
                        </CreatePartition>
                        <CreatePartition wcm:action="add">
                          <Order>3</Order>
                          <Type>Primary</Type>
                          <Extend>true</Extend>
                        </CreatePartition>
                      </CreatePartitions>
                      <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                          <Order>1</Order>
                          <PartitionID>1</PartitionID>
                          <Format>FAT32</Format>
                          <Label>System</Label>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                          <Order>2</Order>
                          <PartitionID>2</PartitionID>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                          <Order>3</Order>
                          <PartitionID>3</PartitionID>
                          <Format>NTFS</Format>
                          <Label>Windows</Label>
                          <Letter>C</Letter>
                        </ModifyPartition>
                      </ModifyPartitions>
                    </Disk>
                  </DiskConfiguration>
                  <ImageInstall>
                    <OSImage>
                      <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>3</PartitionID>
                      </InstallTo>
                    </OSImage>
                  </ImageInstall>
                </component>
              </settings>
              {{specialize}}
              <settings pass="oobeSystem">
                <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="arm64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
                  <OOBE>
                    <HideEULAPage>true</HideEULAPage>
                    <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                    <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                    <HideWirelessSetupInOOBE>{{hideWireless}}</HideWirelessSetupInOOBE>
                    <ProtectYourPC>3</ProtectYourPC>
                  </OOBE>
                  <UserAccounts>
                    <LocalAccounts>
                      <LocalAccount wcm:action="add">
                        <Name>{{user}}</Name>
                        <Group>Administrators</Group>
                        <Password>
                          <Value>{{pass}}</Value>
                          <PlainText>true</PlainText>
                        </Password>
                      </LocalAccount>
                    </LocalAccounts>
                  </UserAccounts>
                  <AutoLogon>
                    <Enabled>true</Enabled>
                    <Username>{{user}}</Username>
                    <Password>
                      <Value>{{pass}}</Value>
                      <PlainText>true</PlainText>
                    </Password>
                    <LogonCount>5</LogonCount>
                  </AutoLogon>
                </component>
              </settings>
            </unattend>
            """;
    }

    private static string XmlEscape(string value) =>
        System.Security.SecurityElement.Escape(value) ?? string.Empty;

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
    [property: JsonPropertyName("password")] string? Password,
    [property: JsonPropertyName("requireWifiDuringOobe")] bool? RequireWifiDuringOobe);

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
