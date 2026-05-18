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

        # Out-Null on WPF .Add() calls suppresses unwanted int return values — correct pattern
        'PSAvoidUsingWriteHost',

        # All empty catch blocks in this codebase are intentional: DLL load fallbacks,
        # optional-feature graceful degradation, and WPF disposal on window teardown
        'PSAvoidUsingEmptyCatchBlock',

        # Project targets PS 7.3+ exclusively; UTF-8 without BOM is correct and preferred
        'PSUseBOMForUnicodeEncodedFile',

        # Plural nouns are semantically correct for functions that return or operate on collections
        'PSUseSingularNouns',

        # False positives: PSSA flags variables declared in param() blocks inside ThreadJob
        # ScriptBlocks as if they were undeclared outer-scope captures requiring $using:
        'PSUseUsingScopeModifierInNewRunspaces',

        # WinMint keeps CLI compatibility for -Password while warning automation toward
        # -PasswordPath/-PasswordEnvVar; schema validation still permits passwordless.
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
