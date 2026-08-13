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
        Assert.False(PwshElevatedPlanRunner.IsStoreMsixPwsh(
            @"C:\Program Files\PowerShell\7\pwsh.exe"));
    }
}
