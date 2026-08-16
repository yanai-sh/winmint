using System.Text;
using System.Xml.Linq;
using WinMint.Orchestrator;
using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

public class WinPeApplyPlanTests
{
    [Fact]
    public void Plan_emits_oobe_unattend_stages_without_windowsPE()
    {
        Profile profile = ParseProfile();
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(profile);

        Assert.True(result.IsOk);
        BuildArtifacts artifacts = result.Value;
        Assert.DoesNotContain("windowsPE", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.DoesNotContain("<Key>/IMAGE/INDEX</Key>", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains("oobeSystem", artifacts.Unattend.Xml, StringComparison.Ordinal);
        Assert.Contains(BuildPlan.IrelandSetupLocale, artifacts.Unattend.Xml, StringComparison.Ordinal);

        Assert.Equal(
            [
                ServicingOpcode.MountInstallWim,
                ServicingOpcode.StampOfflinePolicies,
                ServicingOpcode.StagePayload,
                ServicingOpcode.StageOobeUnattend,
                ServicingOpcode.StampOfflineShell,
                ServicingOpcode.PatchBootWimApply,
                ServicingOpcode.ExportWim,
                ServicingOpcode.BuildIso,
            ],
            artifacts.Stages);
    }

    [Fact]
    public async Task Apply_materializes_winpe_opcode_params()
    {
        Profile profile = ParseProfile();
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(profile);
        Assert.True(planned.IsOk);

        string work = NewTempDir();
        try
        {
            RecordingElevatedPlanRunner runner = new();
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: Path.Combine(work, "out.iso"),
                WimIndex: 3);
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                planned.Value,
                run,
                runner,
                TestContext.Current.CancellationToken);

            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.StageOobeUnattend
                    && s.Parameters.TryGetValue(StageParams.UnattendPath, out string? unattend)
                    && !string.IsNullOrWhiteSpace(unattend)
                    && s.Parameters.TryGetValue(StageParams.MountDir, out string? mount)
                    && mount == ImageServicing.HostMountDir);
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.MountInstallWim
                    && s.Parameters.TryGetValue(StageParams.WimIndex, out string? sourceIndex)
                    && sourceIndex == "3");
            Assert.Contains(
                runner.Stages,
                s => s.Opcode == ServicingOpcode.PatchBootWimApply
                    && !s.Parameters.ContainsKey(StageParams.WimIndex)
                    && s.Parameters.TryGetValue(StageParams.MediaDir, out string? media)
                    && media.EndsWith("media", StringComparison.OrdinalIgnoreCase));
            string written = File.ReadAllText(Path.Combine(work, "unattend.xml"));
            Assert.DoesNotContain("windowsPE", written, StringComparison.Ordinal);
        }
        finally
        {
            TryDelete(work);
        }
    }

    [Fact]
    public void PatchBootWimApply_script_contains_apply_lane_steps_not_legacy_setup()
    {
        string script = File.ReadAllText(FindPatchBootScript());
        string payload = File.ReadAllText(FindRepoFile("payload", "winpe", "LaunchApply.cmd"));
        Assert.Contains("$bootWim = Join-Path $mediaDir", script, StringComparison.Ordinal);
        Assert.Contains("Get-WinPeApplyPayloadPath", script, StringComparison.Ordinal);
        Assert.Contains("Copy-Item -LiteralPath $launchApplyPayload", script, StringComparison.Ordinal);
        Assert.DoesNotContain("$launchApply = @\"", script, StringComparison.Ordinal);
        Assert.DoesNotContain("$applyWimIndex", script, StringComparison.Ordinal);
        Assert.Contains("/Index:1", payload, StringComparison.Ordinal);
        Assert.DoesNotContain("/Index:$wimIndex", script, StringComparison.Ordinal);
        Assert.DoesNotContain("$wimIndex = [int]$Parameters['wimIndex']", script, StringComparison.Ordinal);
        Assert.Contains("LaunchApply.cmd", script, StringComparison.Ordinal);
        Assert.Contains("diskpart", payload, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Apply-Image", payload, StringComparison.Ordinal);
        Assert.Contains("bcdboot", payload, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("wpeutil reboot", payload, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("LabConfig", payload, StringComparison.Ordinal);
        Assert.DoesNotContain("setup.exe", payload, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("/legacy", payload, StringComparison.Ordinal);
        // Skip path must verify LaunchApply content — marker alone hid Index:3 after code fix.
        Assert.Contains("Test-LaunchApplyPatched", script, StringComparison.Ordinal);
        Assert.Contains("LaunchApply verified in every boot.wim index", script, StringComparison.Ordinal);
        Assert.Contains(".winmint-boot-legacy", script, StringComparison.Ordinal);

        // The erase target is discovered, never hardcoded: disk 0 can be the USB we booted from.
        // Branch behaviour lives in tests/contract/Test-DiskGuard.ps1 — this only pins the contract.
        Assert.DoesNotContain("select disk 0", payload, StringComparison.Ordinal);
        Assert.Contains("echo select disk %TARGET%", payload, StringComparison.Ordinal);
        Assert.Contains(":winmint_pick", payload, StringComparison.Ordinal);
        Assert.Contains("refusing to guess", payload, StringComparison.Ordinal);
        // What "patched" means is executed by tests/contract/Test-DiskGuard.ps1. Pin only that the
        // patcher and the pre-wipe gate read the one contract, so neither can be taught a rule alone.
        string gate = File.ReadAllText(FindRepoFile("tools", "apply", "Assert-ApplyEvidence.ps1"));
        foreach (string reader in new[] { script, gate })
        {
            Assert.Contains("WinPeApplyContract.ps1", reader, StringComparison.Ordinal);
            Assert.Contains("Get-WinPeApplyDefect", reader, StringComparison.Ordinal);
        }
    }

    [Fact]
    public void Patcher_and_gate_certify_every_boot_wim_index()
    {
        string patcher = File.ReadAllText(FindPatchBootScript());
        string gate = File.ReadAllText(FindRepoFile("tools", "apply", "Assert-ApplyEvidence.ps1"));

        foreach (string reader in new[] { patcher, gate })
        {
            Assert.Contains("/Get-WimInfo", reader, StringComparison.Ordinal);
            Assert.Contains("Index : (\\d+)", reader, StringComparison.Ordinal);
            Assert.Contains("foreach ($index in $indexes)", reader, StringComparison.Ordinal);
            Assert.Contains("/Index:$index /MountDir:$bootMount", reader, StringComparison.Ordinal);
            Assert.DoesNotContain("/Index:1 /MountDir:$bootMount", reader, StringComparison.Ordinal);
        }

        Assert.True(
            patcher.IndexOf("/Get-WimInfo", StringComparison.Ordinal)
                < patcher.IndexOf("if (Test-Path -LiteralPath $bootMarker)", StringComparison.Ordinal),
            "Patcher must enumerate boot.wim indexes before marker skip certification.");
        Assert.Contains(
            "Test-LaunchApplyPatched -Wim $bootWim -Mount $bootMount -Index $index",
            patcher,
            StringComparison.Ordinal);
        Assert.DoesNotContain(
            "Test-LaunchApplyPatched -Wim $bootWim -Mount $bootMount -Index 1",
            patcher,
            StringComparison.Ordinal);
        Assert.True(
            gate.IndexOf("foreach ($index in $indexes)", StringComparison.Ordinal)
                < gate.IndexOf("Get-WinPeApplyDefect -MountDir $bootMount", StringComparison.Ordinal),
            "Gate must evaluate the shared apply contract inside its all-index loop.");
    }

    [Fact]
    public void BuildIso_script_does_not_finalize_plan_evidence()
    {
        string script = File.ReadAllText(FindServicingScript("Build-Iso.ps1"));
        Assert.DoesNotContain("evidence.json", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("digests.json", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("failure.json", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Get-FileHash", script, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Plan_dma_on_skips_oobe_region_pane_via_oobeSystem_international_core()
    {
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(ParseProfile());
        Assert.True(result.IsOk);
        string xml = result.Value.Unattend.Xml;
        Assert.DoesNotContain("SkipMachineOOBE", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("SkipUserOOBE", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("FirstLogonCommands", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("HideLocalAccountScreen", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("NetworkLocation", xml, StringComparison.Ordinal);

        XNamespace ns = "urn:schemas-microsoft-com:unattend";
        XDocument doc = XDocument.Parse(xml);
        XElement? oobe = doc.Root!.Elements(ns + "settings")
            .FirstOrDefault(e => (string?)e.Attribute("pass") == "oobeSystem");
        Assert.NotNull(oobe);

        XElement? intl = oobe.Elements(ns + "component")
            .FirstOrDefault(c => (string?)c.Attribute("name") == "Microsoft-Windows-International-Core");
        Assert.NotNull(intl);
        Assert.Equal("en-IE", (string?)intl.Element(ns + "InputLocale"));
        Assert.Equal("en-IE", (string?)intl.Element(ns + "SystemLocale"));
        Assert.Equal("en-US", (string?)intl.Element(ns + "UILanguage"));
        Assert.Equal("en-US", (string?)intl.Element(ns + "UILanguageFallback"));
        Assert.Equal("en-IE", (string?)intl.Element(ns + "UserLocale"));

        XElement? shell = oobe.Elements(ns + "component")
            .FirstOrDefault(c => (string?)c.Attribute("name") == "Microsoft-Windows-Shell-Setup");
        Assert.NotNull(shell);
        Assert.Equal("GMT Standard Time", (string?)shell.Element(ns + "TimeZone"));
        XElement? oobeFlags = shell.Element(ns + "OOBE");
        Assert.NotNull(oobeFlags);
        Assert.Equal("true", (string?)oobeFlags.Element(ns + "HideEULAPage"));
        Assert.Equal("true", (string?)oobeFlags.Element(ns + "HideOEMRegistrationScreen"));
        Assert.Equal("true", (string?)oobeFlags.Element(ns + "HideOnlineAccountScreens"));
        Assert.Equal("3", (string?)oobeFlags.Element(ns + "ProtectYourPC"));
        Assert.NotNull(shell.Element(ns + "UserAccounts")?.Element(ns + "LocalAccounts"));
        Assert.NotNull(shell.Element(ns + "AutoLogon"));

        XElement? specialize = doc.Root.Elements(ns + "settings")
            .FirstOrDefault(e => (string?)e.Attribute("pass") == "specialize");
        Assert.NotNull(specialize);
        Assert.Null(
            specialize.Elements(ns + "component")
                .FirstOrDefault(c => (string?)c.Attribute("name") == "Microsoft-Windows-International-Core"));

        XElement? deployment = specialize.Elements(ns + "component")
            .FirstOrDefault(c => (string?)c.Attribute("name") == "Microsoft-Windows-Deployment");
        Assert.NotNull(deployment);
        string[] paths = [.. deployment.Descendants(ns + "Path").Select(p => (string?)p ?? "")];
        Assert.Contains(
            paths,
            p => p.Contains(@"Control Panel\DeviceRegion", StringComparison.Ordinal)
                && p.Contains(" /d 68 ", StringComparison.Ordinal));
        Assert.Contains(
            paths,
            p => p.Contains(@"Control Panel\International\Geo", StringComparison.Ordinal)
                && p.Contains(" /v Nation ", StringComparison.Ordinal)
                && p.Contains(" /d 68 ", StringComparison.Ordinal));
        Assert.Contains(
            paths,
            p => p.Contains(@"Control Panel\International\Geo", StringComparison.Ordinal)
                && p.Contains(" /v Name ", StringComparison.Ordinal)
                && p.Contains(" /d IE ", StringComparison.Ordinal));
    }

    [Fact]
    public void Plan_dma_off_answers_oobe_from_settle_locale_without_specialize()
    {
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(ParseProfile(dmaEnabled: false));
        Assert.True(result.IsOk);
        string xml = result.Value.Unattend.Xml;
        Assert.DoesNotContain("SkipMachineOOBE", xml, StringComparison.Ordinal);
        Assert.DoesNotContain("SkipUserOOBE", xml, StringComparison.Ordinal);

        XNamespace ns = "urn:schemas-microsoft-com:unattend";
        XDocument doc = XDocument.Parse(xml);
        Assert.Null(
            doc.Root!.Elements(ns + "settings")
                .FirstOrDefault(e => (string?)e.Attribute("pass") == "specialize"));

        XElement? oobe = doc.Root.Elements(ns + "settings")
            .FirstOrDefault(e => (string?)e.Attribute("pass") == "oobeSystem");
        Assert.NotNull(oobe);

        XElement? intl = oobe.Elements(ns + "component")
            .FirstOrDefault(c => (string?)c.Attribute("name") == "Microsoft-Windows-International-Core");
        Assert.NotNull(intl);
        Assert.Equal("en-GB", (string?)intl.Element(ns + "InputLocale"));
        Assert.Equal("en-GB", (string?)intl.Element(ns + "SystemLocale"));
        Assert.Equal("en-US", (string?)intl.Element(ns + "UILanguage"));
        Assert.Equal("en-US", (string?)intl.Element(ns + "UILanguageFallback"));
        Assert.Equal("en-GB", (string?)intl.Element(ns + "UserLocale"));

        XElement? shell = oobe.Elements(ns + "component")
            .FirstOrDefault(c => (string?)c.Attribute("name") == "Microsoft-Windows-Shell-Setup");
        Assert.NotNull(shell);
        Assert.Equal("GMT Standard Time", (string?)shell.Element(ns + "TimeZone"));
        Assert.NotNull(shell.Element(ns + "OOBE")?.Element(ns + "HideEULAPage"));
        Assert.NotNull(shell.Element(ns + "UserAccounts")?.Element(ns + "LocalAccounts"));
        Assert.NotNull(shell.Element(ns + "AutoLogon"));
    }

    [Fact]
    public void Plan_emits_winpe_stages_only()
    {
        Result<BuildArtifacts, Failure> result = BuildPlan.Plan(ParseProfile());
        Assert.True(result.IsOk);
        Assert.Contains(ServicingOpcode.StageOobeUnattend, result.Value.Stages);
        Assert.Contains(ServicingOpcode.PatchBootWimApply, result.Value.Stages);
    }

    private static Profile ParseProfile(bool dmaEnabled = true)
    {
        Result<Profile, IReadOnlyList<DocumentError>> parsed = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes($$"""
            {
              "schemaVersion": "winmint.profile/v1",
              "account": {
                "mode": "{{AccountProfile.LocalAutoLogonMode}}",
                "username": "winmint",
                "password": "lab-only"
              },
              "dma": {
                "enabled": {{(dmaEnabled ? "true" : "false")}},
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              }
            }
            """));
        Assert.True(parsed.IsOk);
        return parsed.Value;
    }

    private static string FindPatchBootScript() => FindServicingScript("Patch-BootWimApply.ps1");

    private static string FindServicingScript(string fileName) => FindRepoFile("servicing", fileName);

    private static string FindRepoFile(params string[] parts)
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null && !File.Exists(Path.Combine(dir.FullName, "WinMint.slnx")))
        {
            dir = dir.Parent;
        }

        Assert.NotNull(dir);
        return Path.Combine([dir.FullName, .. parts]);
    }

    private static string NewTempDir()
    {
        string path = Path.Combine(Path.GetTempPath(), "winmint-s2-winpe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // ponytail: best-effort temp cleanup
        }
    }
}
