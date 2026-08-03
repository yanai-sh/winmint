# PSScriptAnalyzer for elevated servicing kernels (pwsh 7.6+).
# Scripts are UTF-8 without BOM (pwsh-native). Exclude only the legacy
# PSUseBOMForUnicodeEncodedFile rule — it still expects a BOM when non-ASCII
# is present; that is Windows PowerShell 5.1-era guidance, not applicable here.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'
    )
}
