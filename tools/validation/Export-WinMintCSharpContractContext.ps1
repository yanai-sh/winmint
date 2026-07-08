#Requires -Version 7.6
<#
.SYNOPSIS
  Emits JsonSerializerContext stubs for WinMint JSON schemas consumed by setup-shell hosts.
.DESCRIPTION
  ponytail: hand-maintained DTOs stay authoritative; this script only lists schema-backed
  types that must stay registered in SetupShellJsonContext.
#>
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'

$schemaTypes = @(
    @{ Schema = 'winmint.setupshellstatus.schema.json'; Type = 'SetupShellStatus' },
    @{ Schema = 'winmint.setupshellcontrol.schema.json'; Type = 'SetupShellControl' },
    @{ Schema = 'winmint.runtimestate.schema.json'; Type = 'RuntimeStateDocument' }
)

$lines = @(
    '// Generated manifest — register these types in apps/setup-shell/JsonContracts.cs',
    '[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase)]'
)
foreach ($entry in $schemaTypes) {
    $schemaPath = Join-Path $RepositoryRoot "schemas\$($entry.Schema)"
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        throw "Missing schema: $schemaPath"
    }
    $lines += "[JsonSerializable(typeof($($entry.Type)))]"
}
$lines += 'internal partial class SetupShellJsonContext : JsonSerializerContext;'
$text = ($lines -join [Environment]::NewLine) + [Environment]::NewLine

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Output $text
}
else {
    $text | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Wrote C# contract context manifest to $OutputPath"
}
