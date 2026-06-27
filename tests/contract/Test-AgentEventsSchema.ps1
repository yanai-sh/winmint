#Requires -Version 7.6
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)

    $failures.Add($Message) | Out-Null
    Write-Error $Message -ErrorAction Continue
}

$schemaPath = Join-Path $root 'schemas\winmint.agentevents.schema.json'
$fixturePath = Join-Path $root 'tests\fixtures\agent-events-sample.jsonl'
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    Add-Failure "Agent events schema is missing: $schemaPath"
}
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
    Add-Failure "Agent events fixture is missing: $fixturePath"
}

if ($failures.Count -eq 0) {
    $schema = Get-Content -LiteralPath $schemaPath -Raw
    $lineNumber = 0
    foreach ($line in @(Get-Content -LiteralPath $fixturePath -Encoding UTF8)) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not (Test-Json -Json $line -Schema $schema -ErrorAction SilentlyContinue)) {
            Add-Failure "Agent events fixture line $lineNumber failed schema validation."
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host "Agent events schema contract failed ($($failures.Count) issue(s))." -ForegroundColor Red
    exit 1
}

Write-Host 'Agent events schema contract passed.' -ForegroundColor Green
exit 0
