# PSScriptAnalyzer for elevated servicing kernels (pwsh 7.6+).
# Scripts are UTF-8 without BOM (pwsh-native). Exclude only the legacy
# PSUseBOMForUnicodeEncodedFile rule — it still expects a BOM when non-ASCII
# is present; that is Windows PowerShell 5.1-era guidance, not applicable here.
#
# ponytail: PSUseCompatibleCommands profiles in PSScriptAnalyzer 1.25 stop at
# pwsh 7.0 — enabling them false-flags 7.6 cmdlets. Syntax 7.0 is the ceiling
# we can check; bump when PSSCA ships a 7.6 profile.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
    }
}
