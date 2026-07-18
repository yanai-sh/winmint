@{
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidUsingWriteHost'
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseSingularNouns'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingUsernameAndPasswordParams'
    )

    Rules = @{
        PSUseCompatibleCmdlets = @{
            compatibility = @('core-7.6.0-windows')
        }
    }
}
