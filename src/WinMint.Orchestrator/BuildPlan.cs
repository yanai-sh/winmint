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

        string? password = doc.Account.Password;
        string? passwordPath = string.IsNullOrWhiteSpace(doc.Account.PasswordPath)
            ? null
            : doc.Account.PasswordPath.Trim();
        if (string.IsNullOrEmpty(password) && passwordPath is not null)
        {
            try
            {
                password = File.ReadAllText(passwordPath).TrimEnd('\r', '\n');
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
            {
                return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
                [
                    new DocumentError(
                        "account.passwordPath.unreadable",
                        $"Cannot read account.passwordPath '{passwordPath}': {ex.Message}",
                        "account.passwordPath"),
                ]));
            }
        }

        if (!ProductOfflinePolicies.TryNormalizeDohProvider(doc.Policies?.DohProvider, out string? doh, out string? dohError))
        {
            return Result.Fail<Profile, DocumentErrors>(new DocumentErrors(
            [
                new DocumentError("policies.dohProvider.unsupported", dohError!, "policies.dohProvider"),
            ]));
        }

        PoliciesProfile? policies = null;
        if (doc.Policies is not null)
        {
            policies = new PoliciesProfile(
                doc.Policies.KeepCopilot ?? false,
                doh);
        }
        else if (doh is not null)
        {
            policies = new PoliciesProfile(KeepCopilot: false, DohProvider: doh);
        }

        Profile profile = new(
            new AccountProfile(doc.Account.Username!, password, requireWifi, passwordPath),
            new DmaProfile(
                doc.Dma.Enabled ?? true,
                new DmaSettleTarget(
                    settle.Locale,
                    settle.GeoId.Value,
                    settle.TimeZoneId,
                    settle.LocationServicesEnabled.Value)),
            NormalizeRemoveList(doc.Debloat?.RemoveProvisionedAppx),
            NormalizeRemoveList(doc.Packages?.Winget),
            NormalizeRemoveList(doc.Packages?.WingetNeedsReboot),
            NormalizeRemoveList(doc.Packages?.Scoop),
            NormalizeRemoveList(doc.Packages?.ScoopNeedsReboot),
            NormalizeRemoveList(doc.Packages?.Wsl),
            NormalizeRemoveList(doc.Packages?.WslNeedsReboot),
            NormalizeRemoveList(doc.Debloat?.RemoveCapabilities),
            NormalizeRemoveList(doc.Debloat?.DisableOptionalFeatures),
            policies);

        return Result.Ok<Profile, DocumentErrors>(profile);
    }

    /// <summary>Inverse of <see cref="TryParseProfile"/> — omit empty packages/debloat objects (same as former host composer).</summary>
    public static byte[] SerializeProfile(Profile profile)
    {
        PackagesDocument? packages = null;
        if (profile.WingetPackages.Count > 0 || profile.WingetNeedsReboot.Count > 0
            || profile.ScoopPackages.Count > 0 || profile.ScoopNeedsReboot.Count > 0
            || profile.WslDistros.Count > 0 || profile.WslNeedsReboot.Count > 0)
        {
            packages = new PackagesDocument(
                profile.WingetPackages.Count == 0 ? null : profile.WingetPackages.ToArray(),
                profile.WingetNeedsReboot.Count == 0 ? null : profile.WingetNeedsReboot.ToArray(),
                profile.ScoopPackages.Count == 0 ? null : profile.ScoopPackages.ToArray(),
                profile.ScoopNeedsReboot.Count == 0 ? null : profile.ScoopNeedsReboot.ToArray(),
                profile.WslDistros.Count == 0 ? null : profile.WslDistros.ToArray(),
                profile.WslNeedsReboot.Count == 0 ? null : profile.WslNeedsReboot.ToArray());
        }

        DebloatDocument? debloat = null;
        if (profile.RemoveProvisionedAppx.Count > 0
            || profile.RemoveCapabilities.Count > 0
            || profile.DisableOptionalFeatures.Count > 0)
        {
            debloat = new DebloatDocument(
                profile.RemoveProvisionedAppx.Count == 0 ? null : profile.RemoveProvisionedAppx.ToArray(),
                profile.RemoveCapabilities.Count == 0 ? null : profile.RemoveCapabilities.ToArray(),
                profile.DisableOptionalFeatures.Count == 0 ? null : profile.DisableOptionalFeatures.ToArray());
        }

        PoliciesProfile effective = profile.EffectivePolicies;
        PoliciesDocument? policies = null;
        if (effective.KeepCopilot || !string.IsNullOrWhiteSpace(effective.DohProvider))
        {
            policies = new PoliciesDocument(
                effective.KeepCopilot ? true : null,
                string.IsNullOrWhiteSpace(effective.DohProvider) ? null : effective.DohProvider);
        }

        ProfileDocument doc = new(
            ProfileSchemaVersion,
            new AccountDocument(
                AccountModeWire.LocalAutoLogon,
                profile.Account.Username,
                profile.Account.PasswordPath is null ? profile.Account.Password : null,
                profile.Account.RequireWifiDuringOobe,
                profile.Account.PasswordPath),
            new DmaDocument(
                profile.Dma.Enabled,
                new DmaSettleDocument(
                    profile.Dma.Settle.Locale,
                    profile.Dma.Settle.GeoId,
                    profile.Dma.Settle.TimeZoneId,
                    profile.Dma.Settle.LocationServicesEnabled)),
            debloat,
            packages,
            policies);

        return JsonSerializer.SerializeToUtf8Bytes(doc, BuildPlanJsonContext.Default.ProfileDocument);
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

    private static PlanFailure? ValidateNeedsRebootSubset(
        IReadOnlyList<string> packages,
        IReadOnlyList<string> needsReboot,
        string code,
        string needsName,
        string packagesName)
    {
        HashSet<string> set = new(packages, StringComparer.OrdinalIgnoreCase);
        foreach (string id in needsReboot)
        {
            if (!set.Contains(id))
            {
                return new PlanFailure(
                    code,
                    $"{needsName} id '{id}' is not in {packagesName}.");
            }
        }

        return null;
    }

    public static Result<BuildArtifacts, PlanFailure> Plan(Profile profile, RunOptions? run = null)
    {
        RunOptions options = run ?? new RunOptions();

        if (string.IsNullOrEmpty(profile.Account.Password))
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(
                new PlanFailure("account.password.required", "Local autoLogon requires a non-empty password."));
        }

        foreach (string id in profile.RemoveProvisionedAppx)
        {
            if (!ProvisionedAppxCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(
                    new PlanFailure(
                        "debloat.removeProvisionedAppx.unknown",
                        $"removeProvisionedAppx id '{id}' is not in the shipped provisioned AppX catalog."));
            }
        }

        foreach (string id in profile.RemoveCapabilities)
        {
            if (!CapabilityCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(
                    new PlanFailure(
                        "debloat.removeCapabilities.unknown",
                        $"removeCapabilities id '{id}' is not in the shipped capability catalog."));
            }
        }

        foreach (string id in profile.DisableOptionalFeatures)
        {
            if (!OptionalFeatureCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, PlanFailure>(
                    new PlanFailure(
                        "debloat.disableOptionalFeatures.unknown",
                        $"disableOptionalFeatures id '{id}' is not in the shipped optional-feature catalog."));
            }
        }

        PlanFailure? needsRebootFail = ValidateNeedsRebootSubset(
            profile.WingetPackages,
            profile.WingetNeedsReboot,
            "packages.wingetNeedsReboot.unknown",
            "wingetNeedsReboot",
            "packages.winget");
        if (needsRebootFail is not null)
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(needsRebootFail);
        }

        needsRebootFail = ValidateNeedsRebootSubset(
            profile.ScoopPackages,
            profile.ScoopNeedsReboot,
            "packages.scoopNeedsReboot.unknown",
            "scoopNeedsReboot",
            "packages.scoop");
        if (needsRebootFail is not null)
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(needsRebootFail);
        }

        needsRebootFail = ValidateNeedsRebootSubset(
            profile.WslDistros,
            profile.WslNeedsReboot,
            "packages.wslNeedsReboot.unknown",
            "wslNeedsReboot",
            "packages.wsl");
        if (needsRebootFail is not null)
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(needsRebootFail);
        }

        HashSet<string> wingetNeedsReboot = new(profile.WingetNeedsReboot, StringComparer.OrdinalIgnoreCase);
        HashSet<string> scoopNeedsReboot = new(profile.ScoopNeedsReboot, StringComparer.OrdinalIgnoreCase);
        HashSet<string> wslNeedsReboot = new(profile.WslNeedsReboot, StringComparer.OrdinalIgnoreCase);

        string unattendXml = BuildAutounattendXml(profile);

        PoliciesProfile policies = profile.EffectivePolicies;
        if (!ProductOfflinePolicies.TryNormalizeDohProvider(policies.DohProvider, out string? dohProvider, out string? dohPlanError))
        {
            return Result.Fail<BuildArtifacts, PlanFailure>(
                new PlanFailure("policies.dohProvider.unsupported", dohPlanError!));
        }

        // Stub Smoke job set — real installs from packages.winget / packages.scoop / packages.wsl; executor shared.
        // Product-constant FirstLogon jobs (ADR-009) + keep-flag safety net when remove-list non-empty.
        List<JobDescriptor> jobList =
        [
            new JobDescriptor("smoke.stub.ready", "stub"),
            new JobDescriptor("smoke.stub.complete", "stub"),
            new JobDescriptor("onedrive.uninstall", "onedrive.uninstall"),
            new JobDescriptor("reservedStorage.disable", "reservedStorage.disable"),
        ];
        if (dohProvider is not null)
        {
            jobList.Add(new JobDescriptor($"doh.{dohProvider}", "doh.set", PackageId: dohProvider));
        }

        if (profile.RemoveProvisionedAppx.Count > 0)
        {
            jobList.Add(new JobDescriptor("keepflag.appx.safetyNet", "appx.safetyNet"));
        }

        foreach (string packageId in profile.WingetPackages)
        {
            jobList.Add(new JobDescriptor(
                $"winget.{packageId}",
                "winget",
                PackageId: packageId,
                NeedsReboot: wingetNeedsReboot.Contains(packageId)));
        }

        foreach (string packageId in profile.ScoopPackages)
        {
            jobList.Add(new JobDescriptor(
                $"scoop.{packageId}",
                "scoop",
                PackageId: packageId,
                NeedsReboot: scoopNeedsReboot.Contains(packageId)));
        }

        foreach (string distroId in profile.WslDistros)
        {
            jobList.Add(new JobDescriptor(
                $"wsl.{distroId}",
                "wsl",
                PackageId: distroId,
                NeedsReboot: wslNeedsReboot.Contains(distroId)));
        }

        JobsArtifact jobs = new(JobsSchemaVersion, jobList);

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
            new ServicingStage(
                ServicingOpcode.MountInstallWim,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.SourceIso] = options.SourceIsoPath ?? "",
                }),
        ];

        if (profile.RemoveProvisionedAppx.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.RemoveProvisionedAppx,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.PackageFamilyNames] = string.Join(';', profile.RemoveProvisionedAppx),
                }));
        }

        if (profile.RemoveCapabilities.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.RemoveCapabilities,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.CapabilityNames] = string.Join(';', profile.RemoveCapabilities),
                }));
        }

        if (profile.DisableOptionalFeatures.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.DisableOptionalFeatures,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.FeatureNames] = string.Join(';', profile.DisableOptionalFeatures),
                }));
        }

        bool braveSelected = profile.WingetPackages.Any(
            id => string.Equals(id, ProductOfflinePolicies.BraveWingetId, StringComparison.OrdinalIgnoreCase));
        IReadOnlyList<OfflinePolicyRow> policyRows = ProductOfflinePolicies.Compose(
            keepCopilot: policies.KeepCopilot,
            includeBraveDebloat: braveSelected);
        stageList.Add(new ServicingStage(
            ServicingOpcode.StampOfflinePolicies,
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                [StageParams.PolicySpecs] = ProductOfflinePolicies.EncodeSpecs(policyRows),
            }));

        stageList.AddRange(
        [
            new ServicingStage(ServicingOpcode.StagePayload, new Dictionary<string, string>(StringComparer.Ordinal)),
            new ServicingStage(ServicingOpcode.InjectUnattend, new Dictionary<string, string>(StringComparer.Ordinal)),
            new ServicingStage(
                ServicingOpcode.StampOfflineShell,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.ShellTarget] = "Supervisor.exe",
                }),
            new ServicingStage(
                ServicingOpcode.ExportWim,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.Lane] = laneName,
                    [StageParams.Compression] = compression,
                    [StageParams.Cleanup] = cleanup,
                }),
            new ServicingStage(
                ServicingOpcode.BuildIso,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.OutputIso] = options.OutputIsoPath ?? "",
                }),
        ]);

        ServicingStageList stages = new(stageList);

        BuildArtifacts artifacts = new(
            new UnattendArtifact(unattendXml),
            jobs,
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
        // Official Unattend: show Network when false/omit; hide when true (Smoke headless). See BUILDPLAN.
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
                      <InstallFrom>
                        <MetaData wcm:action="add">
                          <Key>/IMAGE/INDEX</Key>
                          <Value>1</Value>
                        </MetaData>
                      </InstallFrom>
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
}

internal sealed record ProfileDocument(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("account")] AccountDocument? Account,
    [property: JsonPropertyName("dma")] DmaDocument? Dma,
    [property: JsonPropertyName("debloat")] DebloatDocument? Debloat,
    [property: JsonPropertyName("packages")] PackagesDocument? Packages,
    [property: JsonPropertyName("policies")] PoliciesDocument? Policies = null);

internal sealed record PoliciesDocument(
    [property: JsonPropertyName("keepCopilot")] bool? KeepCopilot,
    [property: JsonPropertyName("dohProvider")] string? DohProvider);

internal sealed record PackagesDocument(
    [property: JsonPropertyName("winget")] string[]? Winget,
    [property: JsonPropertyName("wingetNeedsReboot")] string[]? WingetNeedsReboot,
    [property: JsonPropertyName("scoop")] string[]? Scoop,
    [property: JsonPropertyName("scoopNeedsReboot")] string[]? ScoopNeedsReboot,
    [property: JsonPropertyName("wsl")] string[]? Wsl,
    [property: JsonPropertyName("wslNeedsReboot")] string[]? WslNeedsReboot);

internal sealed record DebloatDocument(
    [property: JsonPropertyName("removeProvisionedAppx")] string[]? RemoveProvisionedAppx,
    [property: JsonPropertyName("removeCapabilities")] string[]? RemoveCapabilities,
    [property: JsonPropertyName("disableOptionalFeatures")] string[]? DisableOptionalFeatures);

internal sealed record AccountDocument(
    [property: JsonPropertyName("mode")] string? Mode,
    [property: JsonPropertyName("username")] string? Username,
    [property: JsonPropertyName("password")] string? Password,
    [property: JsonPropertyName("requireWifiDuringOobe")] bool? RequireWifiDuringOobe,
    [property: JsonPropertyName("passwordPath")] string? PasswordPath = null);

internal sealed record DmaDocument(
    [property: JsonPropertyName("enabled")] bool? Enabled,
    [property: JsonPropertyName("settle")] DmaSettleDocument? Settle);

internal sealed record DmaSettleDocument(
    [property: JsonPropertyName("locale")] string? Locale,
    [property: JsonPropertyName("geoId")] int? GeoId,
    [property: JsonPropertyName("timeZoneId")] string? TimeZoneId,
    [property: JsonPropertyName("locationServicesEnabled")] bool? LocationServicesEnabled);

[JsonSerializable(typeof(ProfileDocument))]
[JsonSourceGenerationOptions(
    WriteIndented = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]
internal sealed partial class BuildPlanJsonContext : JsonSerializerContext;
