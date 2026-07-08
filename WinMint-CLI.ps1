#Requires -Version 5.1

# WinMint command-line entry point. This is a thin dispatcher: the first
# positional token selects a verb, and everything after it is forwarded to that
# verb's own parameter block (see src/runtime/image/Cli.ps1). With no verb it shows help
# and points to WinMint-GUI.ps1 for the interactive wizard.
#
#   WinMint-CLI.ps1 build <profile> [-DryRun] [-SourceIso p] [-WriteUsb -Disk n] ...
#   WinMint-CLI.ps1 new <out> [-Edition Pro] [-KeepGaming] [-Install yasb] ...
#   WinMint-CLI.ps1 validate <profile>
#   WinMint-CLI.ps1 list | clean <id|AllStale> | help
#   WinMint-CLI.ps1                       show help (use WinMint-GUI.ps1 for the wizard)

[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(ValueFromRemainingArguments = $true)][object[]]$Rest = @()
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'src\runtime\modules\WinMint.Bootstrap\WinMint.Bootstrap.psd1') -Force
$bootstrap = Invoke-WinMintRuntimeBootstrap -Entrypoint $PSCommandPath -Arguments (@($Command) + @($Rest))
if ($bootstrap.Relaunched) {
    exit $bootstrap.ExitCode
}

Import-Module (Join-Path $PSScriptRoot 'src\runtime\modules\WinMint.Engine\WinMint.Engine.psd1') -Force
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
                Show-WinMintCliHelp
                Write-Host ''
                Write-Host 'For the interactive build wizard, run WinMint-GUI.ps1 instead.'
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
