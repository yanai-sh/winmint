#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
$outputIso = $Parameters['outputIso']
$wimOut = $Parameters['wimOut']
if ([string]::IsNullOrWhiteSpace($outputIso)) { throw 'outputIso required' }
if ([string]::IsNullOrWhiteSpace($wimOut)) { throw 'wimOut required' }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputIso) -ErrorAction SilentlyContinue | Out-Null
# ponytail: oscdimg lands with real ISO acceptance.
Set-Content -LiteralPath $outputIso -Value "iso-stub from=$wimOut" -Encoding utf8
Write-Host "BuildIso ok outputIso=$outputIso"
exit 0
