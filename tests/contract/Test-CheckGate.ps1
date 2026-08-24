#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gatePath = Join-Path $repo 'tools\host\Invoke-CheckGate.ps1'
. $gatePath -NoRun

$statusDir = Join-Path ([IO.Path]::GetTempPath()) ('check-gate-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
$statusPath = Join-Path $statusDir 'check-status.json'

$events = [Collections.Generic.List[string]]::new()
$native = {
    param($command, $arguments)
    $events.Add("$command $($arguments -join ' ')")
    $global:LASTEXITCODE = 0
}
$finder = {
    param($name, $version)
    $events.Add("find-module $name $version")
    $false
}
$installer = {
    param($name, $version)
    $events.Add("install-module $name $version")
}
$importer = {
    param($name, $version)
    $events.Add("import-module $name $version")
}

Invoke-CheckGate -NativeExecutor $native -ModuleFinder $finder `
    -ModuleInstaller $installer -ModuleImporter $importer `
    -StatusPath $statusPath -RunId 'test-run'

$expected = @(
    'dotnet format --verify-no-changes',
    'dotnet restore',
    'dotnet build --no-restore',
    'dotnet test --no-build -- --filter-not-trait Category=S4 --filter-not-trait Category=S5',
    'find-module PSScriptAnalyzer 1.25.0',
    'install-module PSScriptAnalyzer 1.25.0',
    'import-module PSScriptAnalyzer 1.25.0'
)
for ($i = 0; $i -lt $expected.Count; $i++) {
    if ($events[$i] -ne $expected[$i]) {
        throw "Check gate event $i was '$($events[$i])', expected '$($expected[$i])'"
    }
}
$analyzerEvent = $events | Where-Object { $_ -like 'pwsh *Invoke-ScriptAnalyzerGate.ps1*' }
if ($analyzerEvent -notlike '*-PsscriptAnalyzerVersion 1.25.0*') {
    throw 'Analyzer gate was not invoked with the pinned version'
}
if (@($events | Where-Object { $_ -like 'pwsh *Invoke-ContractTests.ps1*' }).Count -ne 1) {
    throw 'Contract discovery was not invoked exactly once'
}
$contractEvent = $events | Where-Object { $_ -like 'pwsh *Invoke-ContractTests.ps1*' }
if ($contractEvent -notlike "*-StatusPath $statusPath*") {
    throw 'Contract tests were not invoked with -StatusPath'
}
if ($contractEvent -notlike '*-RunId test-run*') {
    throw 'Contract tests were not invoked with -RunId'
}
$passed = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($passed.phase -cne 'passed') { throw "expected phase passed, got '$($passed.phase)'" }

$failureEvents = [Collections.Generic.List[string]]::new()
$failingNative = {
    param($command, $arguments)
    $failureEvents.Add($command)
    $global:LASTEXITCODE = if ($command -eq 'dotnet' -and $arguments[0] -eq 'build') { 23 } else { 0 }
}
$threw = $false
try {
    Invoke-CheckGate -NativeExecutor $failingNative -ModuleFinder { $true } `
        -ModuleInstaller $installer -ModuleImporter $importer `
        -StatusPath $statusPath -RunId 'test-run-fail'
}
catch {
    $threw = $_.Exception.Message -like '*dotnet failed with exit code 23*'
}
if (-not $threw) {
    throw 'Native command failure did not propagate'
}
if ($failureEvents -contains 'pwsh' -or $failureEvents.Count -ne 3) {
    throw 'Check gate continued after native failure'
}
$failed = Get-Content -LiteralPath $statusPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($failed.phase -cne 'failed') { throw "expected phase failed after native throw, got '$($failed.phase)'" }
if ($failed.runId -cne 'test-run-fail') { throw 'failed runId was not the failure run' }

Remove-Item -LiteralPath $statusDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Output 'Test-CheckGate ok'
