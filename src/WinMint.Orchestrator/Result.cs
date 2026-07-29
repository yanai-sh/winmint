namespace WinMint.Orchestrator;

public readonly struct Result<TOk, TErr>
{
    private readonly TOk? _ok;
    private readonly TErr? _err;

    private Result(bool isOk, TOk? ok, TErr? err)
    {
        IsOk = isOk;
        _ok = ok;
        _err = err;
    }

    public bool IsOk { get; }

    public TOk Value => IsOk
        ? _ok!
        : throw new InvalidOperationException("Result is error.");

    public TErr Error => !IsOk
        ? _err!
        : throw new InvalidOperationException("Result is ok.");

    internal static Result<TOk, TErr> FromOk(TOk value) => new(true, value, default);

    internal static Result<TOk, TErr> FromError(TErr error) => new(false, default, error);
}

public static class Result
{
    public static Result<TOk, TErr> Ok<TOk, TErr>(TOk value) => Result<TOk, TErr>.FromOk(value);

    public static Result<TOk, TErr> Fail<TOk, TErr>(TErr error) => Result<TOk, TErr>.FromError(error);
}
