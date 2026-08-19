# Host tools, contract tests, guest pwsh 7 profile skel.
# Same Error+Warning bar as servicing, plus excludes that are wrong for
# operator CLIs / test doubles (Write-Host, ShouldProcess, $Profile, …).
#
# ponytail: command-compat profiles stop at pwsh 7.0 (see servicing settings).
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSUseBOMForUnicodeEncodedFile'
        'PSAvoidUsingWriteHost'
        'PSUseSingularNouns'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSupportsShouldProcess'
        'PSAvoidAssignmentToAutomaticVariable'
        'PSUseApprovedVerbs'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSReviewUnusedParameter'
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
    }
}
