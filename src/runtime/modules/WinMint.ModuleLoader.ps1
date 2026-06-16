# Shared loader for WinMint backend script modules.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not (Get-Variable -Name WinMintModuleLoadedFiles -Scope Script -ErrorAction SilentlyContinue)) {
    $script:WinMintModuleLoadedFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
}

function Get-WinMintModuleRepositoryRoot {
    $current = Split-Path -Parent $PSScriptRoot
    while ($current) {
        if ((Test-Path -LiteralPath (Join-Path $current 'AGENTS.md')) -or
            (Test-Path -LiteralPath (Join-Path $current '.git'))) {
            return (Resolve-Path -LiteralPath $current).Path
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }

    throw 'Unable to determine WinMint repository root from module loader.'
}

function Get-WinMintRuntimeModuleFileList {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Bootstrap', 'Profile', 'Catalog', 'Audit', 'Reporting', 'Engine', 'Setup', 'FirstLogon')]
        [string]$Area
    )

    switch ($Area) {
        'Bootstrap' { return @() }
        'Profile' {
            return @(
                'src/runtime/image/Core.ps1',
                'src/runtime/image/Private/WslSelection.ps1',
                'src/runtime/image/Private/Config/OptionCatalog.ps1',
                'src/runtime/image/Private/Config/Profile.ps1',
                'src/runtime/image/Private/Config/ProfileAuthoring.ps1',
                'src/runtime/image/Private/Headless.ps1'
            )
        }
        'Catalog' {
            return @(
                'src/runtime/image/Core.ps1',
                'src/runtime/image/Private/WslSelection.ps1',
                'src/runtime/image/Private/Config/Profile.ps1',
                'src/runtime/image/Private/Catalog.ps1',
                'src/runtime/image/Private/Image/AiRemoval.ps1',
                'src/runtime/image/Private/Image/Tweaks/TweakRegistry.ps1'
            )
        }
        'Audit' {
            return @(
                'src/runtime/image/Core.ps1',
                'src/runtime/image/Private/WslSelection.ps1',
                'src/runtime/image/Private/Config/Profile.ps1',
                'src/runtime/image/Private/Catalog.ps1',
                'src/runtime/image/Private/Image/AiRemoval.ps1',
                'src/runtime/image/Private/Image/Tweaks/TweakRegistry.ps1',
                'src/runtime/image/Private/InstallPlan.ps1',
                'src/runtime/image/Private/Audit.ps1'
            )
        }
        'Reporting' {
            return @(
                'src/runtime/image/Core.ps1',
                'src/runtime/image/Private/Audit.ps1',
                'src/runtime/image/Private/Manifest.ps1',
                'src/runtime/image/Reports.ps1'
            )
        }
        'Engine' {
            return @(
                'src/runtime/image/Core.ps1',
                'src/runtime/image/Private/Manifest.ps1',
                'src/runtime/image/Reports.ps1',
                'src/runtime/image/Private/WslSelection.ps1',
                'src/runtime/image/Private/Config/OptionCatalog.ps1',
                'src/runtime/image/Private/Config/Profile.ps1',
                'src/runtime/image/Private/Config/ProfileAuthoring.ps1',
                'src/runtime/image/Engine.ps1',
                'src/runtime/image/Private/Bootstrap.ps1',
                'src/runtime/image/Private/Runtime.ps1',
                'src/runtime/image/Private/PayloadStore.ps1',
                'src/runtime/image/Private/UpdatePayloads.ps1',
                'src/runtime/image/Private/Console/Host.ps1',
                'src/runtime/image/Private/Console/Display.ps1',
                'src/runtime/image/Private/Catalog.ps1',
                'src/runtime/image/Private/Image/AiRemoval.ps1',
                'src/runtime/image/Private/Image/Staging.ps1',
                'src/runtime/image/Private/IsoStageCache.ps1',
                'src/runtime/image/Private/IntermediatesCache.ps1',
                'src/runtime/image/Private/Image/Drivers.ps1',
                'src/runtime/image/Private/Image/Tweaks/TweakRegistry.ps1',
                'src/runtime/image/Private/Image/Tweaks.ps1',
                'src/runtime/image/Private/Image/SetupPayloadStaging.ps1',
                'src/runtime/image/Private/Image/Unattend.ps1',
                'src/runtime/image/Private/InstallPlan.ps1',
                'src/runtime/image/Private/Image/Assets.ps1',
                'src/runtime/image/Private/Image/Packages.ps1',
                'src/runtime/image/Private/Media.ps1',
                'src/runtime/image/Private/UsbMedia.ps1',
                'src/runtime/image/Private/Console/Review.ps1',
                'src/runtime/image/Private/Pipeline.Console.ps1',
                'src/runtime/image/Private/Headless.ps1',
                'src/runtime/image/Private/Audit.ps1',
                'src/runtime/image/Private/Pipeline.ps1',
                'src/runtime/image/Cli.ps1',
                'src/runtime/image/WinMint.ps1'
            )
        }
        'Setup' {
            return @(
                'src/runtime/image/Core.ps1',
                'src/runtime/image/Private/WslSelection.ps1',
                'src/runtime/image/Private/Config/Profile.ps1',
                'src/runtime/image/Private/InstallPlan.ps1',
                'src/runtime/image/Private/Image/Unattend.ps1',
                'src/runtime/setup/Setup.Actions.ps1'
            )
        }
        'FirstLogon' {
            return @(
                'src/runtime/firstlogon/Agent.Console.ps1',
                'src/runtime/firstlogon/Agent.Runtime.ps1',
                'src/runtime/firstlogon/Modules/Profiles.ps1',
                'src/runtime/firstlogon/Modules/PackageManagers.ps1',
                'src/runtime/firstlogon/Modules/Wsl.ps1',
                'src/runtime/firstlogon/Modules/Git.ps1',
                'src/runtime/firstlogon/Modules/Dotfiles.ps1',
                'src/runtime/firstlogon/Modules/Raycast.ps1',
                'src/runtime/firstlogon/Modules/LauncherKey.ps1',
                'src/runtime/firstlogon/Modules/PhoneLink.ps1',
                'src/runtime/firstlogon/Modules/TilingDesktop.ps1',
                'src/runtime/firstlogon/Modules/Windhawk.ps1',
                'src/runtime/firstlogon/Modules/Browsers.ps1',
                'src/runtime/firstlogon/Modules/Editors.ps1',
                'src/runtime/firstlogon/Modules/LiveInstallAudit.ps1'
            )
        }
    }
}
