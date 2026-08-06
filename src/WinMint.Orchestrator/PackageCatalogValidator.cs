namespace WinMint.Orchestrator;

/// <summary>Maintainer validator for embedded <c>packages.json</c> (alpha catalog program).</summary>
public static class PackageCatalogValidator
{
    public static IReadOnlyList<string> Validate(PackageCatalog catalog)
    {
        List<string> errors = [];
        ValidateTools(catalog, errors);
        return errors;
    }

    private static void ValidateTools(PackageCatalog catalog, List<string> errors)
    {
        foreach (string key in catalog.ToolCatalogKeys)
        {
            if (!catalog.TryGetToolByKey(key, out PackageToolEntry? tool))
            {
                continue;
            }

            if (tool.Architectures.Count == 0
                || !tool.Architectures.Any(a => string.Equals(a, "arm64", StringComparison.OrdinalIgnoreCase)))
            {
                errors.Add($"Tool '{key}' ({tool.InstallId}) missing arm64 in catalog architectures.");
            }

            if (string.Equals(tool.Source, "scoop", StringComparison.OrdinalIgnoreCase))
            {
                string bucket = tool.ScoopBucket ?? "main";
                if (bucket is not ("main" or "extras"))
                {
                    errors.Add($"Tool '{key}' has unsupported scoopBucket '{bucket}'.");
                }

                if ((tool.InstallId is "komorebi" or "whkd") && bucket != "extras")
                {
                    errors.Add($"Tool '{key}' must declare scoopBucket extras.");
                }
            }
        }
    }
}
