using WinMint.Orchestrator;

namespace WinMint.Tests;

/// <summary>
/// samples/sl7.profile.json reads .scratch/sl7.password. Tests that load it must
/// create that file themselves. A sibling test used to write it, and the SL7
/// review test failed when it ran first.
/// </summary>
internal static class Sl7SamplePassword
{
    private static readonly Lock Gate = new();

    internal static Result<Profile, IReadOnlyList<DocumentError>> TryLoad()
    {
        lock (Gate)
        {
            string scratch = Path.Combine(TestRepo.Root, ".scratch");
            Directory.CreateDirectory(scratch);
            File.WriteAllText(
                Path.Combine(scratch, "sl7.password"),
                AccountProfile.DefaultLocalPassword);
            string samplePath = Path.Combine(TestRepo.Root, "samples", "sl7.profile.json");
            return ProfileFile.TryLoad(samplePath);
        }
    }
}
