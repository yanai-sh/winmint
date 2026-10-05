using WinMint.Orchestrator;

namespace WinMint.Tests;

public class ProfileSecretsTests
{
    [Fact]
    public void TryResolvePasswordPath_joins_relative_to_profile_dir()
    {
        string profile = Path.Combine(Path.GetTempPath(), "winmint-secrets", "winmint.profile.json");
        Result<string, DocumentError> resolved =
            ProfileSecrets.TryResolvePasswordPath(profile, "bootstrap.password");
        Assert.True(resolved.IsOk);
        Assert.Equal(
            Path.GetFullPath(Path.Combine(Path.GetDirectoryName(profile)!, "bootstrap.password")),
            resolved.Value);
    }

    [Fact]
    public void TryResolvePasswordPath_rejects_rooted_ambient()
    {
        Result<string, DocumentError> resolved =
            ProfileSecrets.TryResolvePasswordPath(@"C:\profiles\a.json", @"\secrets\pw.txt");
        Assert.False(resolved.IsOk);
        Assert.Equal("account.passwordPath.unreadable", resolved.Error.Code);
    }

    [Fact]
    public void SidecarLeaf_uses_safe_file_name()
    {
        Assert.Equal("pw.txt", ProfileSecrets.SidecarLeaf(@"C:\x\pw.txt", "fallback.password"));
        Assert.Equal("fallback.password", ProfileSecrets.SidecarLeaf("..", "fallback.password"));
    }
}
