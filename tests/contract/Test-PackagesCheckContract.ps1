#requires -Version 7.6
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $repo 'tools\host\Invoke-PackagesCheck.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath,
    [ref] $tokens,
    [ref] $parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Packages check parser errors: $($parseErrors -join '; ')"
}

function Get-FunctionText {
    param([Parameter(Mandatory)][string] $Name)

    $function = $ast.Find(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] `
                -and $Node.Name -eq $Name
        },
        $true)
    if ($null -eq $function) {
        throw "Packages check contract missing function: $Name"
    }
    return $function.Extent.Text
}

$body = Get-Content -LiteralPath $scriptPath -Raw
$bounded = Get-FunctionText 'Invoke-BoundedProcess'
$winget = Get-FunctionText 'Invoke-WingetTarget'
$scoop = Get-FunctionText 'Invoke-ScoopTarget'
$boundedCalls = @($ast.FindAll(
        {
            param($Node)
            $Node -is [System.Management.Automation.Language.CommandAst] `
                -and $Node.GetCommandName() -eq 'Invoke-BoundedProcess'
        },
        $true))
$failures = @()

if ($body -notmatch '\$DownloadTimeoutSeconds\s*=\s*600') {
    $failures += 'download timeout must remain 600 seconds'
}
if ($bounded -notmatch 'WaitForExitAsync\(\$timeout\.Token\)' `
    -or $bounded -notmatch '\[TimeSpan\]::FromSeconds\(\$DownloadTimeoutSeconds\)') {
    $failures += 'winget bounded wait is missing'
}
if ($bounded -notmatch '\.Kill\(\$true\)') {
    $failures += 'winget timeout must kill the process tree'
}
if (([regex]::Matches($winget, 'Invoke-BoundedProcess')).Count -lt 2) {
    $failures += 'both winget target attempts must use the bounded process runner'
}
if ($boundedCalls.Count -ne 3 `
    -or $body -notmatch "-ArgumentList\s+@\('source', 'update', '--disable-interactivity'\)") {
    $failures += 'winget source update and both target attempts must use the bounded process runner'
}
if (([regex]::Matches($scoop, '-TimeoutSec\s+\$DownloadTimeoutSeconds')).Count -ne 2) {
    $failures += 'Scoop manifest and archive requests must both use the bounded HTTP timeout'
}
if ($bounded -notmatch 'timed out after \$DownloadTimeoutSeconds seconds' `
    -or ([regex]::Matches($scoop, '600-second timeout')).Count -ne 2) {
    $failures += 'timeout errors must state the active bound'
}

. ([scriptblock]::Create($bounded))
$script:DownloadTimeoutSeconds = 5
$probe = Invoke-BoundedProcess `
    -FileName $env:ComSpec `
    -ArgumentList @('/d', '/c', 'exit 0') `
    -Label 'bounded-process contract probe'
if ($probe -isnot [pscustomobject] `
    -or $probe.PSObject.Properties.Name -notcontains 'ExitCode' `
    -or $probe.ExitCode -ne 0) {
    $probeItems = @($probe)
    $shape = $probeItems | ForEach-Object {
        $names = @($_.PSObject.Properties | ForEach-Object Name)
        "$($_.GetType().FullName)[$($names -join ',')]"
    }
    $failures += "bounded process runner must return one result with ExitCode (got $($shape -join '; '))"
}

if ($failures.Count -gt 0) {
    throw "Packages check contract failed:`n$($failures -join "`n")"
}

Write-Output 'Packages check timeout contract passed.'
