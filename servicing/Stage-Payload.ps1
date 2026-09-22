#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $PayloadDir,
    [Parameter(Mandatory)] [string] $MountDir
)
# Stage Supervisor, SetupComplete.cmd, provisioning bundle into the offline image.
$guestWinMint = Join-Path $mountDir 'Windows\WinMint'
$guestScripts = Join-Path $mountDir 'Windows\Setup\Scripts'
New-Item -ItemType Directory -Force -Path $guestWinMint, $guestScripts | Out-Null

Copy-Item -LiteralPath (Join-Path $payloadDir 'Supervisor.exe') -Destination (Join-Path $guestWinMint 'Supervisor.exe') -Force
Copy-Item -LiteralPath (Join-Path $payloadDir 'SetupComplete.cmd') -Destination (Join-Path $guestScripts 'SetupComplete.cmd') -Force
Copy-Item -LiteralPath (Join-Path $payloadDir 'bundle.json') -Destination (Join-Path $guestWinMint 'bundle.json') -Force
Copy-Item -LiteralPath (Join-Path $payloadDir 'jobs.json') -Destination (Join-Path $guestWinMint 'jobs.json') -Force
$wingetImport = Join-Path $payloadDir 'winget-import.json'
if (Test-Path -LiteralPath $wingetImport) {
    Copy-Item -LiteralPath $wingetImport -Destination (Join-Path $guestWinMint 'winget-import.json') -Force
}

$shellSkel = Join-Path $payloadDir 'shell-skel'
if (Test-Path -LiteralPath $shellSkel) {
    # -Path (not -LiteralPath): '*' must expand. LiteralPath looks for a file named '*'.
    $guestSkel = Join-Path $guestWinMint 'shell-skel'
    New-Item -ItemType Directory -Force -Path $guestSkel | Out-Null
    Copy-Item -Path (Join-Path $shellSkel '*') -Destination $guestSkel -Recurse -Force

    $defaultPs = Join-Path $mountDir 'Users\Default\Documents\PowerShell'
    New-Item -ItemType Directory -Force -Path $defaultPs | Out-Null
    foreach ($name in @('Microsoft.PowerShell_profile.ps1', 'powershell.config.json', 'starship.toml')) {
        $src = Join-Path $shellSkel $name
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $defaultPs $name) -Force
        }
    }
    $wtSrc = Join-Path $shellSkel 'settings.json'
    if (Test-Path -LiteralPath $wtSrc -PathType Leaf) {
        $wtDest = Join-Path $mountDir 'Users\Default\AppData\Local\Microsoft\Windows Terminal'
        New-Item -ItemType Directory -Force -Path $wtDest | Out-Null
        Copy-Item -LiteralPath $wtSrc -Destination (Join-Path $wtDest 'settings.json') -Force
    }
}

$bloomSrc = Join-Path $payloadDir 'bloom.jpg'
if (-not (Test-Path -LiteralPath $bloomSrc -PathType Leaf)) {
    Write-Error 'StagePayload: bloom.jpg missing from payloadDir'
    exit 1
}
$wallpaperDir = Join-Path $mountDir 'Windows\Web\Wallpaper\Windows'
New-Item -ItemType Directory -Force -Path $wallpaperDir | Out-Null
Copy-Item -LiteralPath $bloomSrc -Destination (Join-Path $wallpaperDir 'WinMint-Bloom.jpg') -Force

$layoutSrc = Join-Path $payloadDir 'LayoutModification.xml'
if (-not (Test-Path -LiteralPath $layoutSrc -PathType Leaf)) {
    Write-Error 'StagePayload: LayoutModification.xml missing from payloadDir'
    exit 1
}
$oemDir = Join-Path $mountDir 'Windows\OEM'
New-Item -ItemType Directory -Force -Path $oemDir | Out-Null
Copy-Item -LiteralPath $layoutSrc -Destination (Join-Path $oemDir 'TaskbarLayoutModification.xml') -Force
$layoutDest = Join-Path $mountDir 'Users\Default\AppData\Local\Microsoft\Windows\Shell'
New-Item -ItemType Directory -Force -Path $layoutDest | Out-Null
Copy-Item -LiteralPath $layoutSrc -Destination (Join-Path $layoutDest 'LayoutModification.xml') -Force

$fontsDest = Join-Path $mountDir 'Windows\Fonts'
New-Item -ItemType Directory -Force -Path $fontsDest | Out-Null
foreach ($font in @('CascadiaCodeNF.ttf', 'CascadiaMonoNF.ttf')) {
    $fontSrc = Join-Path $payloadDir (Join-Path 'fonts' $font)
    if (-not (Test-Path -LiteralPath $fontSrc -PathType Leaf)) {
        Write-Error "StagePayload: font missing from payloadDir: $font"
        exit 1
    }
    Copy-Item -LiteralPath $fontSrc -Destination (Join-Path $fontsDest $font) -Force
}

Write-Output "StagePayload ok"
exit 0
