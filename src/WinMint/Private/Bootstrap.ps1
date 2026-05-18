#Requires -Version 7.3

function Test-WinMintAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevate {
    [CmdletBinding()]
    param(
        [string]$EntryScriptPath = (Join-Path (Get-WinMintRepositoryRoot) 'WinMint-CLI.ps1'),
        [string[]]$Switches = @()
    )

    if (Test-WinMintAdministrator) { return }
    if (-not (Test-Path -LiteralPath $EntryScriptPath)) {
        throw "Cannot self-elevate because the entry script was not found: $EntryScriptPath"
    }

    $pwsh = (Get-Process -Id $PID).Path
    $argumentList = [System.Collections.Generic.List[string]]::new()
    $argumentList.Add('-NoProfile')
    $argumentList.Add('-ExecutionPolicy')
    $argumentList.Add('Bypass')
    $argumentList.Add('-File')
    $argumentList.Add($EntryScriptPath)
    foreach ($switch in $Switches) {
        if (-not [string]::IsNullOrWhiteSpace($switch)) { $argumentList.Add($switch) }
    }

    Start-Process -FilePath $pwsh -ArgumentList $argumentList.ToArray() -Verb RunAs | Out-Null
    exit
}
