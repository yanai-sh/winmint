using WinMint.Wizard;

namespace WinMint.Tests;

public class WizardStageGatesTests
{
    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(true, true)]
    public void CanGoTo_Media_always_true(bool sourceReady, bool identityReady)
    {
        Assert.True(WizardStageGates.CanGoTo(WizardStageGates.Media, sourceReady, identityReady));
    }

    [Theory]
    [InlineData(WizardStageGates.You)]
    [InlineData(WizardStageGates.Taste)]
    public void CanGoTo_You_or_Taste_requires_source(int target)
    {
        Assert.False(WizardStageGates.CanGoTo(target, sourceReady: false, identityReady: true));
        Assert.True(WizardStageGates.CanGoTo(target, sourceReady: true, identityReady: false));
    }

    [Fact]
    public void CanGoTo_Included_requires_source_and_identity()
    {
        Assert.False(WizardStageGates.CanGoTo(WizardStageGates.Included, false, false));
        Assert.False(WizardStageGates.CanGoTo(WizardStageGates.Included, true, false));
        Assert.False(WizardStageGates.CanGoTo(WizardStageGates.Included, false, true));
        Assert.True(WizardStageGates.CanGoTo(WizardStageGates.Included, true, true));
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
    public void CanAdvance_from_Taste_requires_identity()
    {
        Assert.False(WizardStageGates.CanAdvance(WizardStageGates.Taste, sourceReady: true, identityReady: false));
        Assert.True(WizardStageGates.CanAdvance(WizardStageGates.Taste, sourceReady: true, identityReady: true));
    }

    [Fact]
    public void CanAdvance_from_Media_requires_source()
    {
        Assert.False(WizardStageGates.CanAdvance(WizardStageGates.Media, sourceReady: false, identityReady: true));
        Assert.True(WizardStageGates.CanAdvance(WizardStageGates.Media, sourceReady: true, identityReady: false));
    }

    [Fact]
    public void CanAdvance_from_You_requires_identity()
    {
        Assert.False(WizardStageGates.CanAdvance(WizardStageGates.You, sourceReady: true, identityReady: false));
        Assert.True(WizardStageGates.CanAdvance(WizardStageGates.You, sourceReady: true, identityReady: true));
    }

    [Fact]
    public void CanGoTo_skips_Taste_when_source_and_identity_ready()
    {
        Assert.True(WizardStageGates.CanGoTo(WizardStageGates.Included, sourceReady: true, identityReady: true));
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(4)]
    public void CanGoTo_out_of_range_is_false(int target)
    {
        Assert.False(WizardStageGates.CanGoTo(target, sourceReady: true, identityReady: true));
    }
}
