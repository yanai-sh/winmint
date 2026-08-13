#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $UnattendPath,
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $MediaDir
)
$unattendPath = $UnattendPath
$mountDir = $MountDir
$mediaDir = $MediaDir

$panther = Join-Path $mountDir 'Windows\Panther'
New-Item -ItemType Directory -Force -Path $panther | Out-Null
Copy-Item -LiteralPath $unattendPath -Destination (Join-Path $panther 'unattend.xml') -Force

# ISO root fallback for WinPE LaunchApply (Panther in applied image is primary via offline stage).
$oobeFallback = Join-Path $mediaDir 'OobeUnattend.xml'
Copy-Item -LiteralPath $unattendPath -Destination $oobeFallback -Force
Write-Output "OobeUnattend.xml → $oobeFallback"

Write-Output 'StageOobeUnattend ok'
exit 0
