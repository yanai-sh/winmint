using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

using WinMint.Orchestrator;

using static WinMint.Tests.ImageServicingTestFakes;

namespace WinMint.Tests;

/// <summary>Issue 105 — materialized stage-param names must equal kernel binder names.</summary>
public class ServicingKernelParamContractTests
{
    [Fact]
    public async Task Apply_emitted_property_names_equal_kernel_parameter_names_for_every_opcode()
    {
        BuildArtifacts plan = PlanAllOpcodes();
        string work = Path.Combine(Path.GetTempPath(), "winmint-kernel-params-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            RecordingElevatedPlanRunner runner = new();
            ServicingRun run = new(
                SourceIsoPath: Path.Combine(work, "source.iso"),
                WorkDirectory: work,
                OutputIsoPath: Path.Combine(work, "out.iso"));
            File.WriteAllText(run.SourceIsoPath, "iso-stub");

            Result<ImageEvidence, Failure> result = await ImageServicing.ApplyAsync(
                plan,
                run,
                runner,
                TestContext.Current.CancellationToken);
            Assert.True(result.IsOk, result.IsOk ? null : $"{result.Error.Code}: {result.Error.Message}");

            HashSet<ServicingOpcode> seen = [];
            foreach (ServicingStage stage in runner.Stages)
            {
                seen.Add(stage.Opcode);
                string[] emitted = [.. stage.Parameters.Keys
                    .Order(StringComparer.OrdinalIgnoreCase)
                    .Select(static n => n.ToLowerInvariant())];
                string[] kernelParams = [.. KernelParameterNames(KernelPath(stage.Opcode))
                    .Order(StringComparer.OrdinalIgnoreCase)
                    .Select(static n => n.ToLowerInvariant())];
                Assert.Equal(kernelParams, emitted);
            }

            Assert.Equal(
                Enum.GetValues<ServicingOpcode>().Order().ToArray(),
                [.. seen.Order()]);
        }
        finally
        {
            try
            {
                if (Directory.Exists(work))
                {
                    Directory.Delete(work, recursive: true);
                }
            }
            catch
            {
                // ponytail: best-effort temp cleanup
            }
        }
    }

    private static BuildArtifacts PlanAllOpcodes()
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
                "enabled": true,
                "settle": {
                  "locale": "en-GB",
                  "geoId": 242,
                  "timeZoneId": "GMT Standard Time",
                  "locationServicesEnabled": true
                }
              },
              "debloat": {
                "mode": "offline",
                "removeProvisionedAppx": ["Microsoft.BingNews"],
                "removeCapabilities": ["App.StepsRecorder~~~~0.0.1.0"],
                "disableOptionalFeatures": ["WorkFolders-Client"]
              },
              "drivers": {
                "source": "surfaceCatalog",
                "deviceId": "surface-laptop-7"
              }
            }
            """));
        Assert.True(parsed.IsOk, parsed.IsOk ? null : string.Join("; ", parsed.Error.Select(i => i.Message)));
        Result<BuildArtifacts, Failure> planned = BuildPlan.Plan(parsed.Value);
        Assert.True(planned.IsOk, planned.IsOk ? null : $"{planned.Error.Code}: {planned.Error.Message}");
        return planned.Value;
    }

    private static string KernelPath(ServicingOpcode opcode)
    {
        string plan = File.ReadAllText(
            Path.Combine(TestRepo.Root, "servicing", "Invoke-ServicingPlan.ps1"));
        Match hit = Regex.Match(
            plan,
            $@"'{opcode}'\s*\{{[^\}}]*Join-Path \$scriptRoot '([^']+\.ps1)'",
            RegexOptions.CultureInvariant);
        Assert.True(hit.Success, $"Invoke-ServicingPlan.ps1 has no kernel for {opcode}");
        return Path.Combine(TestRepo.Root, "servicing", hit.Groups[1].Value);
    }

    private static string[] KernelParameterNames(string kernelPath)
    {
        string escaped = kernelPath.Replace("'", "''", StringComparison.Ordinal);
        ProcessStartInfo psi = new()
        {
            FileName = "pwsh",
            ArgumentList =
            {
                "-NoProfile",
                "-Command",
                $$"""
                $cmd = Get-Command '{{escaped}}'
                $skip = [string[]](
                    [System.Management.Automation.PSCmdlet]::CommonParameters +
                    [System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
                @($cmd.Parameters.Keys | Where-Object { $skip -notcontains $_ })
                """,
            },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        using Process p = Process.Start(psi) ?? throw new InvalidOperationException("pwsh failed to start");
        string stdout = p.StandardOutput.ReadToEnd();
        string stderr = p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(30_000), $"Get-Command timed out for {kernelPath}");
        Assert.True(p.ExitCode == 0, $"Get-Command failed for {kernelPath} exit={p.ExitCode}\n{stderr}\n{stdout}");
        return stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }
}
