using System.Security.Cryptography;

using WinMint.Orchestrator;

namespace WinMint.Tests;

internal static class TestIso
{
    internal static SourceIsoIdentity Identity(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        return new SourceIsoIdentity(Convert.ToHexStringLower(SHA256.HashData(bytes)), bytes.Length);
    }

    internal static SourceIsoIdentity FixedHash(string path, string sha256) =>
        new(sha256, new FileInfo(path).Length);

    internal static Task<Result<IReadOnlyList<WimIndexInfo>, Failure>> List(params WimIndexInfo[] rows) =>
        Task.FromResult(Result.Ok<IReadOnlyList<WimIndexInfo>, Failure>(rows));
}
