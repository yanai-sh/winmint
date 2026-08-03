#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
$unattendPath = $Parameters['unattendPath']
$mountDir = $Parameters['mountDir']
if ([string]::IsNullOrWhiteSpace($unattendPath)) { throw 'unattendPath required' }
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }

$panther = Join-Path $mountDir 'Windows\Panther'
New-Item -ItemType Directory -Force -Path $panther | Out-Null
Copy-Item -LiteralPath $unattendPath -Destination (Join-Path $panther 'unattend.xml') -Force
Write-Output "InjectUnattend ok"
exit 0
