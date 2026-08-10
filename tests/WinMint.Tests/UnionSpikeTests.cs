namespace WinMint.Tests;

// Production stays on Result<TOk,TErr> until PublishAot spike is expanded.
internal readonly record struct SpikeOk(int Value);

internal readonly record struct SpikeErr(string Message);

internal union SpikeResult(SpikeOk, SpikeErr);

public class UnionSpikeTests
{
    [Fact]
    public void Pattern_matches_ok_and_err_cases()
    {
        SpikeResult ok = new SpikeOk(42);
        Assert.Equal(
            42,
            ok switch
            {
                SpikeOk o => o.Value,
                SpikeErr e => throw new InvalidOperationException(e.Message),
            });

        SpikeResult err = new SpikeErr("nope");
        Assert.Equal(
            "nope",
            err switch
            {
                SpikeOk => "unexpected",
                SpikeErr e => e.Message,
            });
    }
}
