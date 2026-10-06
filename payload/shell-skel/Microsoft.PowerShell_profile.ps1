#Requires -Version 7
# WinMint opinionated PowerShell 7 profile (one-shot skel). Edit freely — WinMint will not re-apply.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'starship and zoxide document Invoke-Expression for init')]
param()

$PROFILE_DIR = Split-Path -Path $PROFILE -Parent
# Agents/CI often set TERM=dumb; skip UX that assumes a real console.
$interactive = [Environment]::UserInteractive -and $env:TERM -ne 'dumb'

function Test-CommandExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )
    [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

if ($interactive) {
    $PSStyle.FileInfo.Directory = $PSStyle.Bold + $PSStyle.Foreground.Blue
    try {
        Set-PSReadLineOption -EditMode Emacs -HistorySearchCursorMovesToEnd -HistoryNoDuplicates
        Set-PSReadLineOption -Colors @{
            Default          = $PSStyle.Reset
            InlinePrediction = $PSStyle.Italic + $PSStyle.Foreground.BrightBlack
            Operator         = $PSStyle.Reset
            Parameter        = $PSStyle.Reset
        }

        Set-PSReadLineKeyHandler -Chord 'Tab' -Function MenuComplete
        Set-PSReadLineKeyHandler -Chord 'UpArrow' -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Chord 'DownArrow' -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Backspace' -Function BackwardDeleteWord
        Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
        Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord

        # Needs VT; redirected/agent consoles reject this — leave other options in place.
        try {
            Set-PSReadLineOption -PredictionSource History
        } catch {
        }
    } catch {
        # Hosts without PSReadLine (or option mismatches) must not brick startup.
    }
}

# Prefer Microsoft Coreutils ls (native arm64/x64) over PowerShell's Get-ChildItem alias.
$coreutilsLs = Get-Command ls.exe -CommandType Application -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -match '[\\/]coreutils[\\/]' } |
    Select-Object -First 1
if ($null -ne $coreutilsLs) {
    Remove-Alias ls -ErrorAction SilentlyContinue
    function ls { & $coreutilsLs.Source @args }
    function ll { & $coreutilsLs.Source -lh @args }
    function la { & $coreutilsLs.Source -lah @args }
}

if (Test-CommandExists bat) {
    Set-Alias -Name cat -Value bat -Option AllScope -Force
}

if ($interactive -and (Test-CommandExists zoxide)) {
    try {
        Invoke-Expression (& { (zoxide init powershell | Out-String) })
    } catch {
        # Broken Scoop shim must not brick pwsh.
    }
}

if ($interactive -and (Test-CommandExists starship)) {
    try {
        $env:STARSHIP_CONFIG = Join-Path $PROFILE_DIR 'starship.toml'
        Invoke-Expression (& { (starship init powershell | Out-String) })
    } catch {
        # Broken Scoop shim must not brick pwsh.
    }
}
