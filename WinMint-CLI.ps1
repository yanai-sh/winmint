#Requires -Version 7.3

# WinMint command-line entry point. This is a thin dispatcher: the first
# positional token selects a verb, and everything after it is forwarded to that
# verb's own parameter block (see src/runtime/image/Cli.ps1). With no verb it launches
# the interactive build wizard.
#
#   WinMint-CLI.ps1 build <profile> [-DryRun] [-SourceIso p] [-WriteUsb -Disk n] ...
#   WinMint-CLI.ps1 new <out> [-Edition Pro] [-KeepGaming] [-Install yasb] ...
#   WinMint-CLI.ps1 validate <profile>
#   WinMint-CLI.ps1 list | clean <id|AllStale> | help
#   WinMint-CLI.ps1                       interactive wizard

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(ValueFromRemainingArguments = $true)][object[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 2.0

. "$PSScriptRoot\src\runtime\image\WinMint.ps1"

Initialize-WinMintEngine -RepositoryRoot $PSScriptRoot

# Remember the verbatim invocation so build/validate can self-elevate by
# relaunching this exact verb command under a UAC prompt.
$script:WinMintInvocationArgs = @($Command) + @($Rest)

$wantsJson = '-Json' -in $Rest
$exitCode = 0
$result = $null

try {
    switch -Regex ($Command.Trim()) {
        '^build$'    { $result = Invoke-WinMintVerbFunction 'Invoke-WinMintBuildCommand' $Rest }
        '^new$'      { $result = Invoke-WinMintVerbFunction 'Invoke-WinMintNewProfileCommand' $Rest }
        '^validate$' { $result = Invoke-WinMintVerbFunction 'Invoke-WinMintValidateCommand' $Rest }
        '^list$'     { $result = Invoke-WinMintVerbFunction 'Invoke-WinMintListCommand' $Rest }
        '^clean$'    { $result = Invoke-WinMintVerbFunction 'Invoke-WinMintCleanCommand' $Rest }
        '^(help|-h|-help|--help)$' { Show-WinMintCliHelp }
        '^$' {
            if (@('-h', '-help', '--help', '/?') | Where-Object { $_ -in $Rest }) {
                Show-WinMintCliHelp
            } else {
                Invoke-WinMintConsoleBuild
            }
        }
        default {
            throw "Unknown command '$Command'. Run 'WinMint-CLI.ps1 help' for usage."
        }
    }

    if ($result -and ([string]$result.result -in @('failed', 'validation-failed'))) {
        $exitCode = 1
    }
}
catch {
    if ($wantsJson) {
        Write-WinMintHeadlessJsonResult -Result (New-WinMintHeadlessResult -Result 'failed' -Failures @($_.Exception.Message))
    } else {
        Write-Error $_.Exception.Message -ErrorAction Continue
    }
    $exitCode = 1
}

exit $exitCode
