using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PwshElevatedPlanRunnerTests
{
    [Fact]
    public void Store_msix_pwsh_is_refused_before_elevation()
    {
        Failure? refused = PwshElevatedPlanRunner.RefuseStoreMsixPwsh(
            @"C:\Program Files\WindowsApps\Microsoft.PowerShell_7.4.0.0_arm64__8wekyb3d8bbwe\pwsh.exe");
        Assert.NotNull(refused);
        Assert.Equal("servicing.pwsh.storeMsix", refused.Value.Code);
    }

    [Fact]
    public void WindowsApps_alias_pwsh_is_refused_before_elevation()
    {
        Assert.NotNull(PwshElevatedPlanRunner.RefuseStoreMsixPwsh(
            @"C:\Users\yanai\AppData\Local\Microsoft\WindowsApps\pwsh.exe"));
    }

    [Fact]
    public void Msi_pwsh_is_not_refused_as_store_msix()
    {
        Assert.Null(PwshElevatedPlanRunner.RefuseStoreMsixPwsh(
            @"C:\Program Files\PowerShell\7\pwsh.exe"));
    }

    [Fact]
    public void Pwsh_path_skips_windowsapps_when_msi_is_present()
    {
        Assert.Equal(
            @"C:\Program Files\PowerShell\7\pwsh.exe",
            PwshElevatedPlanRunner.FirstNonStorePwsh(
                @"C:\Users\yanai\AppData\Local\Microsoft\WindowsApps\pwsh.exe",
                @"C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_arm64__8wekyb3d8bbwe\pwsh.exe",
                @"C:\Program Files\PowerShell\7\pwsh.exe"));
        Assert.Null(PwshElevatedPlanRunner.FirstNonStorePwsh(
            @"C:\Users\yanai\AppData\Local\Microsoft\WindowsApps\pwsh.exe"));
    }
}
