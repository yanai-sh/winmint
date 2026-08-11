using WinMint.Wizard;

namespace WinMint.Tests;

public class WizardStageGatesTests
{
    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public void CanGoTo_Source_always_true(bool sourceReady, bool identityReady)
    {
        Assert.True(WizardStageGates.CanGoTo(WizardStageGates.Source, sourceReady, identityReady));
    }

    [Theory]
    [InlineData(WizardStageGates.Account)]
    [InlineData(WizardStageGates.Software)]
    public void CanGoTo_Account_or_Software_requires_source(int target)
    {
        Assert.False(WizardStageGates.CanGoTo(target, sourceReady: false, identityReady: true));
        Assert.True(WizardStageGates.CanGoTo(target, sourceReady: true, identityReady: false));
    }

    [Fact]
    public void CanGoTo_Review_requires_source_and_identity()
    {
        Assert.False(WizardStageGates.CanGoTo(WizardStageGates.Review, false, false));
        Assert.False(WizardStageGates.CanGoTo(WizardStageGates.Review, true, false));
        Assert.False(WizardStageGates.CanGoTo(WizardStageGates.Review, false, true));
        Assert.True(WizardStageGates.CanGoTo(WizardStageGates.Review, true, true));
    }

    [Theory]
    [InlineData(null, "secret")]
    [InlineData("", "secret")]
    [InlineData("   ", "secret")]
    [InlineData("winmint", null)]
    [InlineData("winmint", "")]
    public void IdentityReady_false_when_username_blank_or_password_empty(string? username, string? password)
    {
        Assert.False(WizardStageGates.IdentityReady(username, password));
    }

    [Fact]
    public void IdentityReady_true_when_trimmed_username_and_password_set()
    {
        Assert.True(WizardStageGates.IdentityReady(" winmint ", "lab-only"));
    }

    [Fact]
    public void CanBuild_requires_all_ready_and_not_busy()
    {
        Assert.False(WizardStageGates.CanBuild(false, true, true, false));
        Assert.False(WizardStageGates.CanBuild(true, false, true, false));
        Assert.False(WizardStageGates.CanBuild(true, true, false, false));
        Assert.False(WizardStageGates.CanBuild(true, true, true, true));
        Assert.True(WizardStageGates.CanBuild(true, true, true, false));
    }

    [Fact]
    public void CanBuild_profileReady_means_planned_or_saved_not_only_disk_path()
    {
        // Gate takes a bool — callers pass (_lastProfileUtf8 != null || saved path).
        Assert.True(WizardStageGates.CanBuild(true, true, profileReady: true, isBusy: false));
        Assert.False(WizardStageGates.CanBuild(true, true, profileReady: false, isBusy: false));
    }

    [Fact]
    public void CanAdvance_from_Software_requires_source_and_identity()
    {
        Assert.False(WizardStageGates.CanAdvance(WizardStageGates.Software, sourceReady: true, identityReady: false));
        Assert.False(WizardStageGates.CanAdvance(WizardStageGates.Software, sourceReady: false, identityReady: true));
        Assert.True(WizardStageGates.CanAdvance(WizardStageGates.Software, sourceReady: true, identityReady: true));
    }

    [Fact]
    public void CanAdvance_from_Source_requires_source()
    {
        Assert.False(WizardStageGates.CanAdvance(WizardStageGates.Source, sourceReady: false, identityReady: true));
        Assert.True(WizardStageGates.CanAdvance(WizardStageGates.Source, sourceReady: true, identityReady: false));
    }

    [Fact]
    public void CanAdvance_from_Account_requires_source_only()
    {
        Assert.False(WizardStageGates.CanAdvance(WizardStageGates.Account, sourceReady: false, identityReady: true));
        Assert.True(WizardStageGates.CanAdvance(WizardStageGates.Account, sourceReady: true, identityReady: false));
    }

    [Fact]
    public void CanGoTo_skips_Software_when_source_and_identity_ready()
    {
        Assert.True(WizardStageGates.CanGoTo(WizardStageGates.Review, sourceReady: true, identityReady: true));
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(4)]
    public void CanGoTo_out_of_range_is_false(int target)
    {
        Assert.False(WizardStageGates.CanGoTo(target, sourceReady: true, identityReady: true));
    }
}
