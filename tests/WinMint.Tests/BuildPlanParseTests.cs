using System.Text;
using WinMint.Orchestrator;

namespace WinMint.Tests;

public class BuildPlanParseTests
{
    [Theory]
    [InlineData("")]
    [InlineData("{")]
    [InlineData("not-json")]
    public void TryParseProfile_invalid_json_returns_document_error(string json)
    {
        Result<Profile, IReadOnlyList<DocumentError>> result = BuildPlan.TryParseProfile(Encoding.UTF8.GetBytes(json));

        Assert.False(result.IsOk);
        Assert.NotEmpty(result.Error);
        Assert.Contains(result.Error, i => i.Code == "document.invalidJson");
    }
}
