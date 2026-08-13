using System.Text.Json;
using System.Text.Json.Serialization;
using WinMint.Contracts;

namespace WinMint.Orchestrator;

public static partial class BuildPlan
{
    public const string ProfileSchemaVersion = "winmint.profile/v1";
    public const string PlanStagesSchemaVersion = "winmint.plan.stages/v1";

    public const string IrelandSetupLocale = DmaInterop.IrelandLocale;
    public const int IrelandSetupGeoId = DmaInterop.IrelandGeoId;
    public const string IrelandSetupGeoName = DmaInterop.IrelandGeoName;

    /// <summary>Parse and validate a <c>winmint.profile/v1</c> UTF-8 document into a <see cref="Profile"/>.</summary>
    public static Result<Profile, IReadOnlyList<DocumentError>> TryParseProfile(ReadOnlySpan<byte> utf8Json)
    {
        if (utf8Json.IsEmpty)
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(InvalidJson("Document is empty."));
        }

        ProfileDocument? doc;
        try
        {
            doc = JsonSerializer.Deserialize(utf8Json, BuildPlanJsonContext.Default.ProfileDocument);
        }
        catch (JsonException ex)
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(InvalidJson(ex.Message));
        }

        if (doc is null)
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(InvalidJson("Document deserialized to null."));
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
            else if (!string.Equals(doc.Account.Mode, AccountProfile.LocalAutoLogonMode, StringComparison.Ordinal))
            {
                issues.Add(new DocumentError(
                    "account.mode.unsupported",
                    $"Unsupported account.mode '{doc.Account.Mode}'. Smoke supports {AccountProfile.LocalAutoLogonMode} only.",
                    "account.mode"));
            }

            if (string.IsNullOrWhiteSpace(doc.Account.Username))
            {
                issues.Add(new DocumentError("account.username.missing", "account.username is required.", "account.username"));
            }
        }

        if (issues.Count > 0)
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(issues);
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
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(issues);
        }

        // Default true: real-hardware contract shows OOBE Network; Smoke Profiles set false explicitly.
        bool requireWifi = doc.Account!.RequireWifiDuringOobe ?? true;

        string? password = doc.Account.Password;
        string? passwordPath = string.IsNullOrWhiteSpace(doc.Account.PasswordPath)
            ? null
            : doc.Account.PasswordPath.Trim();
        // Host materializes passwordPath via ProfileFile; BuildPlan stays pure (issue 91).
        if (!string.IsNullOrEmpty(password) && passwordPath is not null)
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
            [
                new DocumentError(
                    "account.password.sources.conflict",
                    "account.password and account.passwordPath cannot both be set.",
                    "account"),
            ]);
        }

        if (!ProductPosture.TryNormalizeDohProvider(doc.Policies?.DohProvider, out string? doh, out string? dohError))
        {
            return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
            [
                new DocumentError("policies.dohProvider.unsupported", dohError!, "policies.dohProvider"),
            ]);
        }

        PoliciesProfile? policies = null;
        if (doc.Policies is not null || doh is not null)
        {
            policies = new PoliciesProfile(DohProvider: doh);
        }

        DriversProfile? drivers = null;
        if (doc.Drivers is not null)
        {
            if (string.IsNullOrWhiteSpace(doc.Drivers.Source))
            {
                return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
                [
                    new DocumentError("drivers.source.missing", "drivers.source is required.", "drivers.source"),
                ]);
            }

            if (string.IsNullOrWhiteSpace(doc.Drivers.DeviceId))
            {
                return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
                [
                    new DocumentError("drivers.deviceId.missing", "drivers.deviceId is required.", "drivers.deviceId"),
                ]);
            }

            drivers = new DriversProfile(doc.Drivers.Source.Trim(), doc.Drivers.DeviceId.Trim());
        }

        DebloatMode debloatMode = DebloatMode.Online;
        if (doc.Debloat?.Mode is not null)
        {
            if (string.Equals(doc.Debloat.Mode, "online", StringComparison.OrdinalIgnoreCase))
            {
                debloatMode = DebloatMode.Online;
            }
            else if (string.Equals(doc.Debloat.Mode, "offline", StringComparison.OrdinalIgnoreCase))
            {
                debloatMode = DebloatMode.Offline;
            }
            else
            {
                return Result.Fail<Profile, IReadOnlyList<DocumentError>>(
                [
                    new DocumentError(
                        "debloat.mode.unsupported",
                        $"Unsupported debloat.mode '{doc.Debloat.Mode}'. Expected online|offline.",
                        "debloat.mode"),
                ]);
            }
        }

        Profile profile = new(
            new AccountProfile(doc.Account.Username!, password, requireWifi, passwordPath),
            new DmaProfile(
                doc.Dma.Enabled ?? true,
                new DmaSettleTarget(
                    settle.Locale,
                    settle.GeoId,
                    settle.TimeZoneId,
                    settle.LocationServicesEnabled)),
            debloatMode,
            NormalizeRemoveList(doc.Debloat?.RemoveProvisionedAppx),
            NormalizeRemoveList(doc.Packages?.Winget),
            NormalizeRemoveList(doc.Packages?.WingetNeedsReboot),
            NormalizeRemoveList(doc.Packages?.Scoop),
            NormalizeRemoveList(doc.Packages?.ScoopNeedsReboot),
            NormalizeRemoveList(doc.Packages?.Wsl),
            NormalizeRemoveList(doc.Packages?.WslNeedsReboot),
            NormalizeRemoveList(doc.Debloat?.RemoveCapabilities),
            NormalizeRemoveList(doc.Debloat?.DisableOptionalFeatures),
            policies,
            drivers);

        return Result.Ok<Profile, IReadOnlyList<DocumentError>>(profile);
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
        if (profile.DebloatMode == DebloatMode.Offline
            || profile.RemoveProvisionedAppx.Count > 0
            || profile.RemoveCapabilities.Count > 0
            || profile.DisableOptionalFeatures.Count > 0)
        {
            debloat = new DebloatDocument(
                profile.DebloatMode == DebloatMode.Offline ? "offline" : null,
                profile.RemoveProvisionedAppx.Count == 0 ? null : profile.RemoveProvisionedAppx.ToArray(),
                profile.RemoveCapabilities.Count == 0 ? null : profile.RemoveCapabilities.ToArray(),
                profile.DisableOptionalFeatures.Count == 0 ? null : profile.DisableOptionalFeatures.ToArray());
        }

        PoliciesProfile effective = profile.EffectivePolicies;
        PoliciesDocument? policies = string.IsNullOrWhiteSpace(effective.DohProvider)
            ? null
            : new PoliciesDocument(effective.DohProvider);

        DriversDocument? drivers = profile.Drivers is null
            ? null
            : new DriversDocument(profile.Drivers.Source, profile.Drivers.DeviceId);

        ProfileDocument doc = new(
            ProfileSchemaVersion,
            new AccountDocument(
                AccountProfile.LocalAutoLogonMode,
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
            policies,
            drivers);

        return JsonSerializer.SerializeToUtf8Bytes(doc, BuildPlanJsonContext.Default.ProfileDocument);
    }

    private static Failure? ValidateDrivers(DriversProfile drivers, RunOptions options)
    {
        if (!string.Equals(drivers.Source, SurfaceDriverCatalog.SourceSurfaceCatalog, StringComparison.OrdinalIgnoreCase))
        {
            return new Failure(
                "drivers.source.unsupported",
                $"drivers.source '{drivers.Source}' is unsupported (only '{SurfaceDriverCatalog.SourceSurfaceCatalog}' in this vertical).");
        }

        if (!SurfaceDriverCatalog.TryGet(drivers.DeviceId, out SurfaceDriverDevice? device) || device is null)
        {
            return new Failure(
                "drivers.deviceId.unknown",
                $"drivers.deviceId '{drivers.DeviceId}' is not in the Surface driver catalog.");
        }

        if (!string.IsNullOrWhiteSpace(options.ImageArchitecture))
        {
            string imageArch = SurfaceDriverCatalog.NormalizeArchitecture(options.ImageArchitecture);
            if (!string.Equals(imageArch, device.Architecture, StringComparison.OrdinalIgnoreCase))
            {
                return new Failure(
                    "drivers.architecture.mismatch",
                    $"drivers.deviceId '{device.Id}' targets {device.Architecture}, but the image architecture is {options.ImageArchitecture}.");
            }
        }

        if (options.WindowsBuild is int build && build < device.MinimumWindowsBuild)
        {
            return new Failure(
                "drivers.windowsBuild.tooLow",
                $"drivers.deviceId '{device.Id}' requires Windows build {device.MinimumWindowsBuild} or later; source build is {build}.");
        }

        return null;
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

    private static Failure? ValidateNeedsRebootSubset(
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
                return new Failure(
                    code,
                    $"{needsName} id '{id}' is not in {packagesName}.");
            }
        }

        return null;
    }

    /// <summary>FirstLogon always needs outbound network (product-constant MinGit + Nilesoft winget). Not authored in Profile JSON.</summary>
    public static bool PlanRequiresNetwork() => true;

    /// <summary>Compose plan artifacts (jobs, stages, unattend, manifest) from a validated <see cref="Profile"/>.</summary>
    public static Result<BuildArtifacts, Failure> Plan(Profile profile, RunOptions? run = null)
    {
        RunOptions options = run ?? new RunOptions();

        if (string.IsNullOrEmpty(profile.Account.Password))
        {
            return Result.Fail<BuildArtifacts, Failure>(
                new Failure("account.password.required", "Local autoLogon requires a non-empty password."));
        }

        IReadOnlyList<string> appx = ProductPosture.UnionAppx(profile.RemoveProvisionedAppx);
        foreach (string id in appx)
        {
            if (!ProvisionedAppxCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, Failure>(
                    new Failure(
                        "debloat.removeProvisionedAppx.unknown",
                        $"removeProvisionedAppx id '{id}' is not in the shipped provisioned AppX catalog."));
            }
        }

        foreach (string id in profile.RemoveCapabilities)
        {
            if (!CapabilityCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, Failure>(
                    new Failure(
                        "debloat.removeCapabilities.unknown",
                        $"removeCapabilities id '{id}' is not in the shipped capability catalog."));
            }
        }

        foreach (string id in profile.DisableOptionalFeatures)
        {
            if (!OptionalFeatureCatalog.Ids.Contains(id))
            {
                return Result.Fail<BuildArtifacts, Failure>(
                    new Failure(
                        "debloat.disableOptionalFeatures.unknown",
                        $"disableOptionalFeatures id '{id}' is not in the shipped optional-feature catalog."));
            }
        }

        if (profile.Drivers is not null)
        {
            Failure? driverFail = ValidateDrivers(profile.Drivers, options);
            if (driverFail is not null)
            {
                return Result.Fail<BuildArtifacts, Failure>(driverFail.Value);
            }
        }

        PackageCatalog catalog = options.PackageCatalog ?? PackageCatalog.Default;
        string imageArchitecture = string.IsNullOrWhiteSpace(options.ImageArchitecture)
            ? PackageCatalog.DefaultImageArchitecture
            : PackageCatalog.NormalizeArch(options.ImageArchitecture);
        Result<PackagePlanSlice, Failure> packages = PlanPackages(
            profile,
            catalog,
            imageArchitecture,
            options.PackageAuditStrict);
        if (!packages.IsOk)
        {
            return Result.Fail<BuildArtifacts, Failure>(packages.Error);
        }
        PackagePlanSlice packageSlice = packages.Value;

        string unattendXml = BuildOobeUnattendXml(profile);

        PoliciesProfile policies = profile.EffectivePolicies;
        if (!ProductPosture.TryNormalizeDohProvider(policies.DohProvider, out string? dohProvider, out string? dohPlanError))
        {
            return Result.Fail<BuildArtifacts, Failure>(
                new Failure("policies.dohProvider.unsupported", dohPlanError!));
        }

        // Product-constant FirstLogon jobs (ADR-009) + debloat safety net when remove-list non-empty.
        // smoke.stub.* only when RunOptions.IncludeSmokeStubs (Smoke/acceptance harness).
        List<ProvisionJob> jobList = [];
        if (options.IncludeSmokeStubs)
        {
            jobList.Add(new ProvisionJob("smoke.stub.ready", ProvisionJobKind.Stub));
            jobList.Add(new ProvisionJob("smoke.stub.complete", ProvisionJobKind.Stub));
        }

        jobList.Add(new ProvisionJob("onedrive.uninstall", ProvisionJobKind.OneDriveUninstall));
        jobList.Add(new ProvisionJob("reservedStorage.disable", ProvisionJobKind.ReservedStorageDisable));
        jobList.Add(new ProvisionJob("workstation.quiet", ProvisionJobKind.WorkstationQuiet));
        if (dohProvider is not null)
        {
            DohProviderSpec? doh = ProductPosture.ResolveDoh(dohProvider);
            if (doh is null)
            {
                return Result.Fail<BuildArtifacts, Failure>(
                    new Failure(
                        "policies.dohProvider.unsupported",
                        $"policies.dohProvider '{dohProvider}' is unsupported (use cloudflare, google, or quad9)."));
            }

            jobList.Add(new ProvisionJob(
                $"doh.{dohProvider}",
                ProvisionJobKind.DohSet,
                PackageId: dohProvider,
                DohPrimary: doh.Primary,
                DohSecondary: doh.Secondary,
                DohTemplate: doh.DohTemplate));
        }

        if (appx.Count > 0 && profile.DebloatMode == DebloatMode.Online)
        {
            jobList.Add(new ProvisionJob("debloat.appx.safetyNet", ProvisionJobKind.AppxSafetyNet));
        }

        jobList.AddRange(packageSlice.Jobs);

        JobsArtifact jobs = new(JobsWire.SchemaVersion, jobList);

        ExportLane exportLane = ExportLane.For(options.ImageQuality);

        List<ServicingStage> stageList =
        [
            new ServicingStage(
                ServicingOpcode.MountInstallWim,
                new Dictionary<string, string>(StringComparer.Ordinal)),
        ];

        // Stamp HKLM policies before AppX/capability/driver DISM mutations. Creating new
        // Policies\Microsoft\* keys (Widgets Dsh) flakes Unauthorized on a heavily-serviced mount.
        bool injectDrivers = profile.Drivers is not null;
        bool braveSelected = packageSlice.EffectivePackages.Any(
            package => package.Source is EffectivePackageSource.Winget or EffectivePackageSource.Store
                && string.Equals(
                    package.ResolvedInstallId,
                    ProductPosture.BraveWingetId,
                    StringComparison.OrdinalIgnoreCase));
        IReadOnlyList<OfflinePolicyRow> policyRows = ProductPosture.ComposePolicies(
            includeBraveDebloat: braveSelected,
            includeDriverHygiene: injectDrivers);
        stageList.Add(new ServicingStage(
            ServicingOpcode.StampOfflinePolicies,
            new Dictionary<string, string>(StringComparer.Ordinal)));

        if (appx.Count > 0 && profile.DebloatMode == DebloatMode.Offline)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.RemoveProvisionedAppx,
                new Dictionary<string, string>(StringComparer.Ordinal)));
        }

        if (profile.RemoveCapabilities.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.RemoveCapabilities,
                new Dictionary<string, string>(StringComparer.Ordinal)));
        }

        if (profile.DisableOptionalFeatures.Count > 0)
        {
            stageList.Add(new ServicingStage(
                ServicingOpcode.DisableOptionalFeatures,
                new Dictionary<string, string>(StringComparer.Ordinal)));
        }

        if (injectDrivers)
        {
            SurfaceDriverDevice device = SurfaceDriverCatalog.Devices[profile.Drivers!.DeviceId];
            stageList.Add(new ServicingStage(
                ServicingOpcode.InjectDrivers,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.DeviceId] = device.Id,
                    [StageParams.DetailsUrl] = device.DetailsUrl,
                    [StageParams.ExpectedFileNameRegex] = device.ExpectedFileNameRegex,
                }));
        }

        stageList.Add(new ServicingStage(ServicingOpcode.StagePayload, new Dictionary<string, string>(StringComparer.Ordinal)));
        stageList.Add(new ServicingStage(ServicingOpcode.StageOobeUnattend, new Dictionary<string, string>(StringComparer.Ordinal)));

        stageList.Add(new ServicingStage(
            ServicingOpcode.StampOfflineShell,
            new Dictionary<string, string>(StringComparer.Ordinal)));

        stageList.Add(new ServicingStage(ServicingOpcode.PatchBootWimApply, new Dictionary<string, string>(StringComparer.Ordinal)));

        stageList.AddRange(
        [
            new ServicingStage(
                ServicingOpcode.ExportWim,
                new Dictionary<string, string>(StringComparer.Ordinal)
                {
                    [StageParams.Lane] = exportLane.Name,
                    [StageParams.Compression] = exportLane.Compression,
                    [StageParams.Cleanup] = exportLane.Cleanup,
                }),
            new ServicingStage(
                ServicingOpcode.BuildIso,
                new Dictionary<string, string>(StringComparer.Ordinal)),
        ]);

        ServicingStageList stages = new(stageList);

        BuildArtifacts artifacts = new(
            new UnattendArtifact(unattendXml),
            jobs,
            stages,
            new DmaContract(profile.Dma.Enabled, profile.Dma.Enabled ? profile.Dma.Settle : null),
            new BuildManifest(options.ImageQuality, PlanRequiresNetwork()),
            profile.Account,
            appx,
            packageSlice.EffectivePackages,
            policyRows,
            profile.RemoveCapabilities,
            profile.DisableOptionalFeatures,
            packageSlice.WingetImportJson,
            options.PackageStrict,
            braveSelected);

        return Result.Ok<BuildArtifacts, Failure>(artifacts);
    }

    /// <summary>OOBE-phase unattend (specialize + oobeSystem) for WinPE apply — no windowsPE disk/ImageInstall.</summary>
    internal static string BuildOobeUnattendXml(Profile profile)
    {
        string user = XmlEscape(profile.Account.Username);
        string pass = XmlEscape(profile.Account.Password ?? "");
        // Official Unattend: show Network when false/omit; hide when true (Smoke headless). See BUILDPLAN.
        string hideWireless = profile.Account.RequireWifiDuringOobe ? "false" : "true";
        string specialize = BuildSpecializeXml(profile);

        return $$"""
            <?xml version="1.0" encoding="utf-8"?>
            <unattend xmlns="urn:schemas-microsoft-com:unattend">
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

    private static string BuildSpecializeXml(Profile profile) =>
        profile.Dma.Enabled
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
                      <Description>WinMint DMA DeviceRegion latch (Ireland {{IrelandSetupGeoId}})</Description>
                      <Path>reg add "HKLM\{{DmaInterop.DeviceRegionSubKey}}" /v DeviceRegion /t REG_DWORD /d {{IrelandSetupGeoId}} /f</Path>
                    </RunSynchronousCommand>
                    <RunSynchronousCommand wcm:action="add">
                      <Order>2</Order>
                      <Description>WinMint DMA .DEFAULT Geo Nation (Ireland {{IrelandSetupGeoId}})</Description>
                      <Path>reg add "HKU\{{DmaInterop.DefaultUserGeoSubKey}}" /v Nation /t REG_SZ /d {{IrelandSetupGeoId}} /f</Path>
                    </RunSynchronousCommand>
                    <RunSynchronousCommand wcm:action="add">
                      <Order>3</Order>
                      <Description>WinMint DMA .DEFAULT Geo Name ({{IrelandSetupGeoName}})</Description>
                      <Path>reg add "HKU\{{DmaInterop.DefaultUserGeoSubKey}}" /v Name /t REG_SZ /d {{IrelandSetupGeoName}} /f</Path>
                    </RunSynchronousCommand>
                  </RunSynchronous>
                </component>
              </settings>
              """
            : string.Empty;

    private static string XmlEscape(string value) =>
        System.Security.SecurityElement.Escape(value) ?? string.Empty;

    private static IReadOnlyList<DocumentError> InvalidJson(string message) =>
        [new DocumentError("document.invalidJson", message)];

}

internal sealed record ProfileDocument(
    [property: JsonPropertyName("schemaVersion")] string? SchemaVersion,
    [property: JsonPropertyName("account")] AccountDocument? Account,
    [property: JsonPropertyName("dma")] DmaDocument? Dma,
    [property: JsonPropertyName("debloat")] DebloatDocument? Debloat,
    [property: JsonPropertyName("packages")] PackagesDocument? Packages,
    [property: JsonPropertyName("policies")] PoliciesDocument? Policies = null,
    [property: JsonPropertyName("drivers")] DriversDocument? Drivers = null);

internal sealed record DriversDocument(
    [property: JsonPropertyName("source")] string? Source,
    [property: JsonPropertyName("deviceId")] string? DeviceId);

internal sealed record PoliciesDocument(
    [property: JsonPropertyName("dohProvider")] string? DohProvider);

internal sealed record PackagesDocument(
    [property: JsonPropertyName("winget")] string[]? Winget,
    [property: JsonPropertyName("wingetNeedsReboot")] string[]? WingetNeedsReboot,
    [property: JsonPropertyName("scoop")] string[]? Scoop,
    [property: JsonPropertyName("scoopNeedsReboot")] string[]? ScoopNeedsReboot,
    [property: JsonPropertyName("wsl")] string[]? Wsl,
    [property: JsonPropertyName("wslNeedsReboot")] string[]? WslNeedsReboot);

internal sealed record DebloatDocument(
    [property: JsonPropertyName("mode")] string? Mode,
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

internal sealed record WingetImportFile(
    [property: JsonPropertyName("$schema")] string Schema,
    [property: JsonPropertyName("CreationDate")] DateTimeOffset CreationDate,
    [property: JsonPropertyName("Sources")] WingetImportSourceFile[] Sources);

internal sealed record WingetImportSourceFile(
    [property: JsonPropertyName("SourceDetails")] WingetSourceDetailsFile SourceDetails,
    [property: JsonPropertyName("Packages")] IReadOnlyList<WingetImportPackageFile> Packages);

internal sealed record WingetSourceDetailsFile(
    [property: JsonPropertyName("Name")] string Name,
    [property: JsonPropertyName("Identifier")] string Identifier,
    [property: JsonPropertyName("Argument")] string Argument,
    [property: JsonPropertyName("Type")] string Type);

internal sealed record WingetImportPackageFile(
    [property: JsonPropertyName("PackageIdentifier")] string PackageIdentifier,
    [property: JsonPropertyName("InitialOverrideArguments")] string? InitialOverrideArguments);

[JsonSerializable(typeof(WingetImportFile))]
[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, WriteIndented = true)]
internal sealed partial class WingetImportJsonContext : JsonSerializerContext;
