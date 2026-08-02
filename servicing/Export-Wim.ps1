#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Export WIM. compression/cleanup values are ticket 09; lane name is already in params from BuildPlan.
$mountDir = $Parameters['mountDir']
$wimOut = $Parameters['wimOut']
$lane = $Parameters['lane']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($wimOut)) { throw 'wimOut required' }

# ponytail: DISM export params (Test vs Release) land in ticket 09.
Set-Content -LiteralPath $wimOut -Value "export-stub lane=$lane" -Encoding utf8
Write-Host "ExportWim ok lane=$lane"
exit 0
