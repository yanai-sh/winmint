#Requires -Version 7.6
[CmdletBinding()]
param(
    [string]$Configuration = 'Release',
    [switch]$AllArch
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$nativeProject = Join-Path $root 'apps\setup-shell\WinMintSetupShell.csproj'
$webProject = Join-Path $root 'apps\setup-shell-web\WinMintSetupShellWeb.csproj'
$outRoot = Join-Path $root 'assets\runtime\setup\setup-shell\bin'
$setupShellAssets = Join-Path $root 'assets\runtime\setup\setup-shell'

function Get-WinMintHostSetupShellPublishEntry {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch -Regex ([string]$arch) {
        '^ARM64$' { return @{ Rid = 'win-arm64'; Folder = 'arm64' } }
        default { return @{ Rid = 'win-x64'; Folder = 'x64' } }
    }
}

$allEntries = @(
    @{ Rid = 'win-arm64'; Folder = 'arm64' }
    @{ Rid = 'win-x64'; Folder = 'x64' }
)

if ($AllArch) {
    $hostEntry = Get-WinMintHostSetupShellPublishEntry
    $publishEntries = @($hostEntry) + @($allEntries | Where-Object { $_.Folder -ne $hostEntry.Folder })
    Write-Host "Publishing WinMint setup shells for x64 + arm64 (host-first: $($hostEntry.Folder)) ..."
}
else {
    $publishEntries = @(Get-WinMintHostSetupShellPublishEntry)
    Write-Host "Publishing WinMint setup shells for host architecture ($($publishEntries[0].Folder)) only; pass -AllArch for release/ISO staging."
}

foreach ($entry in $publishEntries) {
    $dest = Join-Path $outRoot $entry.Folder
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $dest -Force

    $nativeStage = Join-Path ([IO.Path]::GetTempPath()) ("winmint-native-{0}-{1}" -f $entry.Folder, [guid]::NewGuid().ToString('n'))
    $webStage = Join-Path ([IO.Path]::GetTempPath()) ("winmint-web-{0}-{1}" -f $entry.Folder, [guid]::NewGuid().ToString('n'))
    try {
        Write-Host "Publishing WinMintSetupShell.Native (Direct2D AOT) for $($entry.Rid) ..."
        dotnet publish $nativeProject `
            -c $Configuration `
            -r $entry.Rid `
            -p:PublishAot=true `
            -p:PublishSingleFile=true `
            -p:StripSymbols=true `
            -o $nativeStage
        if ($LASTEXITCODE -ne 0) {
            throw "Native publish failed for $($entry.Rid) with exit code $LASTEXITCODE."
        }

        $nativeBuilt = Join-Path $nativeStage 'WinMintSetupShell.exe'
        if (-not (Test-Path -LiteralPath $nativeBuilt -PathType Leaf)) {
            throw "Native publish succeeded but executable is missing: $nativeBuilt"
        }
        $nativeDest = Join-Path $dest 'WinMintSetupShell.Native.exe'
        Move-Item -LiteralPath $nativeBuilt -Destination $nativeDest -Force
        $nativeSizeMb = [Math]::Round((Get-Item -LiteralPath $nativeDest).Length / 1MB, 2)
        Write-Host "  -> $nativeDest ($nativeSizeMb MB)"
        if ($nativeSizeMb -gt 10) {
            throw "WinMintSetupShell.Native.exe for $($entry.Rid) is ${nativeSizeMb} MB; gate is 10 MB."
        }

        Write-Host "Publishing WinMintSetupShell (WebView2 wizard) for $($entry.Rid) ..."
        dotnet publish $webProject `
            -c $Configuration `
            -r $entry.Rid `
            -p:PublishSingleFile=true `
            -o $webStage
        if ($LASTEXITCODE -ne 0) {
            throw "WebView2 wizard publish failed for $($entry.Rid) with exit code $LASTEXITCODE."
        }

        $webBuilt = Join-Path $webStage 'WinMintSetupShell.exe'
        if (-not (Test-Path -LiteralPath $webBuilt -PathType Leaf)) {
            throw "WebView2 publish succeeded but executable is missing: $webBuilt"
        }
        $webDest = Join-Path $dest 'WinMintSetupShell.exe'
        Move-Item -LiteralPath $webBuilt -Destination $webDest -Force
        $webSizeMb = [Math]::Round((Get-Item -LiteralPath $webDest).Length / 1MB, 2)
        Write-Host "  -> $webDest ($webSizeMb MB)"
    }
    finally {
        foreach ($temp in @($nativeStage, $webStage)) {
            if (Test-Path -LiteralPath $temp) {
                Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

foreach ($heroName in @('winmint_hero_ui.png', 'winmint_hero.png')) {
    $brandSource = Join-Path $root "assets\brand\$heroName"
    if (-not (Test-Path -LiteralPath $brandSource -PathType Leaf)) {
        throw "WinMint brand hero asset is missing: $brandSource"
    }
    Copy-Item -LiteralPath $brandSource -Destination (Join-Path $setupShellAssets $heroName) -Force
    Write-Host "  -> staged $heroName"
}

if (-not (Test-Path -LiteralPath (Join-Path $setupShellAssets 'tokens.json') -PathType Leaf)) {
    throw "Setup shell tokens.json is missing under $setupShellAssets"
}

Write-Host 'WinMintSetupShell publish complete (Native + WebView2 wizard).'
