@{
    # Run: Invoke-ScriptAnalyzer -Path . -Settings PSScriptAnalyzerSettings.psd1

    Severity            = @('Error', 'Warning')

    ExcludeRules        = @(
        # Build helpers change state without -WhatIf/-Confirm — intentional for UI functions
        'PSUseShouldProcessForStateChangingFunctions',

        # CmdletBinding on an interactive GUI script is correct; avoid noise about DryRun param
        'PSReviewUnusedParameter',

        # Dot-sourcing internal helper blocks is intentional in this codebase
        'PSAvoidUsingInvokeExpression',

        # Script entry points and validation helpers intentionally report directly to the console
        'PSAvoidUsingWriteHost',

        # Empty catch blocks are reserved for optional-feature graceful degradation.
        'PSAvoidUsingEmptyCatchBlock',

        # Project targets PS 7.3+ exclusively; UTF-8 without BOM is correct and preferred
        'PSUseBOMForUnicodeEncodedFile',

        # Plural nouns are semantically correct for functions that return or operate on collections
        'PSUseSingularNouns',

        # False positives: PSSA flags variables declared in param() blocks inside ThreadJob
        # ScriptBlocks as if they were undeclared outer-scope captures requiring $using:
        'PSUseUsingScopeModifierInNewRunspaces',

        # WinMint supports direct -Password for interactive CLI use while steering
        # automation toward -PasswordPath/-PasswordEnvVar; schema validation still permits passwordless.
        'PSAvoidUsingPlainTextForPassword',

        # The profile contract deliberately models account name and optional password
        # separately for unattended setup generation.
        'PSAvoidUsingUsernameAndPasswordParams'
    )

    Rules               = @{
        PSAvoidLongLines    = @{ Enable = $true; MaximumLineLength = 220 }
        PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('7.3') }
    }
}
