using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PwshElevatedPlanRunnerTests
{
    [Fact]
    public void Pwsh_store_path_detected()
    {
        Assert.True(PwshElevatedPlanRunner.IsStoreMsixPwsh(
            @"C:\Program Files\WindowsApps\Microsoft.PowerShell_7.4.0.0_arm64__8wekyb3d8bbwe\pwsh.exe"));
        Assert.True(PwshElevatedPlanRunner.IsStoreMsixPwsh(
            @"C:/Program Files/WindowsApps/Microsoft.PowerShellPreview_7.5.0.0_arm64__8wekyb3d8bbwe/pwsh.exe"));
        Assert.True(PwshElevatedPlanRunner.IsStoreMsixPwsh(
            @"C:\Users\yanai\AppData\Local\Microsoft\WindowsApps\pwsh.exe"));
        Assert.False(PwshElevatedPlanRunner.IsStoreMsixPwsh(
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
