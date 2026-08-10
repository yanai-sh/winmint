using WinMint.Orchestrator;

namespace WinMint.Tests;

public class PackageCatalogValidatorTests
{
    [Fact]
    public void Default_embedded_catalog_passes_validator()
    {
        IReadOnlyList<string> errors = PackageCatalog.Default.Validate();
        Assert.Empty(errors);
    }

    [Fact]
    public void Repo_packages_json_passes_validator()
    {
        string path = Path.Combine(FindRepoRoot(), "config", "packages.json");
        PackageCatalog catalog = PackageCatalog.LoadFromFile(path);
        IReadOnlyList<string> errors = catalog.Validate();
        Assert.Empty(errors);
    }

    [Fact]
    public void Komorebi_and_whkd_declare_extras_bucket()
    {
        Assert.True(PackageCatalog.Default.TryGetToolByKey("komorebi", out PackageToolEntry? komorebi));
        Assert.Equal("extras", komorebi!.ScoopBucket);
        Assert.True(PackageCatalog.Default.TryGetToolByKey("whkd", out PackageToolEntry? whkd));
        Assert.Equal("extras", whkd!.ScoopBucket);
    }

    private static string FindRepoRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "config", "packages.json")))
            {
                return dir.FullName;
            }

            dir = dir.Parent;
        }

        throw new InvalidOperationException("repo root not found");
    }
}
