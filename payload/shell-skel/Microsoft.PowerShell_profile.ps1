#Requires -Version 7
# WinMint opinionated PowerShell 7 profile (one-shot skel). Edit freely — WinMint will not re-apply.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '', Justification = 'starship and zoxide document Invoke-Expression for init')]
param()

$PROFILE_DIR = Split-Path -Path $PROFILE -Parent

function Test-CommandExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )
    [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

$PSStyle.FileInfo.Directory = $PSStyle.Bold + $PSStyle.Foreground.Blue
Set-PSReadLineOption -EditMode Emacs -HistorySearchCursorMovesToEnd
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

if (Test-CommandExists zoxide) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

if (Test-CommandExists starship) {
    $env:STARSHIP_CONFIG = Join-Path $PROFILE_DIR 'starship.toml'
    Invoke-Expression (& { (starship init powershell | Out-String) })
}
