#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
    Write-Host 'PSScriptAnalyzer not installed — Install-PSResource PSScriptAnalyzer -Scope CurrentUser -TrustRepository'
    exit 0
}

$paths = @('servicing', 'payload') | Where-Object { Test-Path $_ }
if (-not $paths) {
    Write-Host 'No servicing/ or payload/ paths yet — skip'
    exit 0
}

$settings = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
$results = @()
foreach ($path in $paths) {
    $results += @(Invoke-ScriptAnalyzer -Path $path -Settings $settings -Recurse -Severity @('Error', 'Warning'))
}
if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize
    exit 1
}
Write-Host 'PSScriptAnalyzer: clean'
