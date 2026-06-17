#Requires -Version 7.6

function Get-WinMintSetupPayloadRequiredScriptNames {
    @(
        'SetupComplete.cmd'
        'SetupComplete.ps1'
        'Setup.Actions.ps1'
        'Specialize.ps1'
        'DefaultUser.ps1'
        'FirstLogon.ps1'
        'FirstLogon.Support.ps1'
        'FirstLogon.Transaction.ps1'
        'FirstLogon.Runtime.ps1'
    )
}

function Get-WinMintSetupPayloadRequiredArtifacts {
    $scriptRoot = 'C:\Windows\Setup\Scripts'
    @(
        foreach ($name in @(Get-WinMintSetupPayloadRequiredScriptNames)) {
            Join-Path $scriptRoot $name
        }
        Join-Path $scriptRoot 'SetupComplete\*.ps1'
        Join-Path $scriptRoot 'Audit-LiveInstall.ps1'
        Join-Path $scriptRoot 'WinMintSetupProfile.json'
        Join-Path $scriptRoot 'WinMintSetupPlan.json'
        Join-Path $scriptRoot 'WinMintAgent\BuildProfile.json'
        Join-Path $scriptRoot 'WinMintAgent\packages.json'
    )
}

function Assert-WinMintAgentToolSources {
    # WinMint installs first-logon tools through explicit package-manager owners:
    # winget/msstore for GUI/system apps, Scoop for developer CLI tools. Validate
    # the catalog at build time so an unsupported source fails the build here, with a
    # clear message, rather than silently failing per-tool on the user's first logon.
    param([Parameter(Mandatory)][string]$ManifestPath)

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.PSObject.Properties['tools']) { return }
    foreach ($toolProp in $manifest.tools.PSObject.Properties) {
        $tool = $toolProp.Value
        $toolSource = [string]$toolProp.Value.source
        if (-not [string]::IsNullOrWhiteSpace($toolSource) -and $toolSource -notin @('winget', 'store', 'scoop', 'direct')) {
            throw "Unsupported install source '$toolSource' for tool '$($toolProp.Name)' in packages.json. WinMint only supports the 'winget', 'store', 'scoop', and approved 'direct' install sources."
        }
        if ($toolSource -eq 'direct') {
            $architectures = @($tool.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
            $toolVersion = if ($tool.PSObject.Properties['version']) { [string]$tool.version } else { '' }
            $toolUrl = if ($tool.PSObject.Properties['url']) { [string]$tool.url } else { '' }
            $toolSha256 = if ($tool.PSObject.Properties['sha256']) { [string]$tool.sha256 } else { '' }
            if ([string]$toolProp.Name -ne 'everything-arm64-beta' -or
                [string]$tool.id -ne 'Everything-1.5.0.1415b.ARM64' -or
                $toolVersion -ne '1.5.0.1415b' -or
                $toolUrl -ne 'https://www.voidtools.com/Everything-1.5.0.1415b.ARM64.en-US-Setup.exe' -or
                $toolSha256 -ne '2D511A33A3494147F921DCB488772125E6CC654E677196AACB0235967A27D2DA' -or
                $architectures.Count -ne 1 -or
                $architectures[0] -ne 'arm64') {
                throw "Direct install source is restricted to the pinned Everything 1.5.0.1415b ARM64 payload. Invalid tool '$($toolProp.Name)' in packages.json."
            }
            if (-not $tool.PSObject.Properties['silentArgs'] -or @($tool.silentArgs).Count -eq 0) {
                throw "Direct install tool '$($toolProp.Name)' must declare silentArgs."
            }
        }
    }
}

function Copy-WinMintSetupPayloadTextFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if ([IO.Path]::GetExtension($Source) -ieq '.cmd') {
        # Batch files must be ASCII with no BOM because a UTF-8 BOM makes
        # cmd.exe fail on the first line.
        [System.IO.File]::WriteAllBytes(
            $Destination,
            [System.Text.Encoding]::ASCII.GetBytes((Get-Content -LiteralPath $Source -Raw))
        )
        return
    }

    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($Destination, (Get-Content -LiteralPath $Source -Raw), $utf8Bom)
}

function Copy-WinMintSetupScriptPayloads {
    param(
        [Parameter(Mandatory)][string]$BundleDir,
        [Parameter(Mandatory)][string]$Destination
    )

    foreach ($name in @(Get-WinMintSetupPayloadRequiredScriptNames)) {
        $source = Join-Path $BundleDir $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "WinMint setup payload missing from the repository: $source. Cannot guarantee FirstLogon/SetupComplete will run."
        }

        $destinationPath = Join-Path $Destination $name
        Copy-WinMintSetupPayloadTextFile -Source $source -Destination $destinationPath
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            throw "Failed to stage '$name' into the offline image at $Destination. SetupComplete/FirstLogon would not run on the installed system; aborting before producing a broken ISO."
        }
    }

    LogOK 'Verified SetupComplete / FirstLogon / specialize scripts are staged into the offline image.'
}

function Copy-WinMintSetupCompleteModulePayloads {
    param(
        [Parameter(Mandatory)][string]$BundleDir,
        [Parameter(Mandatory)][string]$Destination
    )

    $sourceDir = Join-Path $BundleDir 'SetupComplete'
    if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { return }

    $destinationDir = Join-Path $Destination 'SetupComplete'
    $null = New-Item -ItemType Directory -Path $destinationDir -Force -ErrorAction SilentlyContinue
    foreach ($moduleFile in @(Get-ChildItem -LiteralPath $sourceDir -Filter '*.ps1' -File)) {
        Copy-WinMintSetupPayloadTextFile -Source $moduleFile.FullName -Destination (Join-Path $destinationDir $moduleFile.Name)
    }
}

function Copy-WinMintLiveAuditPayload {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Destination
    )

    $auditSource = Join-Path $RepositoryRoot 'tools\audit\Audit-LiveInstall.ps1'
    if (Test-Path -LiteralPath $auditSource -PathType Leaf) {
        Copy-WinMintSetupPayloadTextFile -Source $auditSource -Destination (Join-Path $Destination 'Audit-LiveInstall.ps1')
    }
}

function Save-WinMintSetupPayloadJson {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Depth
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Test-WinMintAgentProfileSelection {
    param(
        [AllowNull()]$AgentProfile,
        [Parameter(Mandatory)][string]$Path
    )

    if ($null -eq $AgentProfile) { return $false }

    $value = $AgentProfile
    foreach ($segment in @($Path -split '\.')) {
        if ($null -eq $value) { return $false }
        if ($value -is [System.Collections.IDictionary]) {
            if (-not $value.Contains($segment)) { return $false }
            $value = $value[$segment]
            continue
        }
        $property = $value.PSObject.Properties[$segment]
        if (-not $property) { return $false }
        $value = $property.Value
    }

    return [bool]$value
}

function Copy-WinMintAgentRuntimePayload {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Destination,
        [AllowNull()]$AgentProfile
    )

    $agentSource = Join-Path $RepositoryRoot 'src\runtime\firstlogon'
    if (-not (Test-Path -LiteralPath $agentSource -PathType Container)) {
        throw "WinMintAgent source directory is missing: $agentSource"
    }

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Copy-Item -LiteralPath $agentSource -Destination $Destination -Recurse -Force

    $agentEntry = Join-Path $Destination 'Start-WinMintAgent.ps1'
    if (-not (Test-Path -LiteralPath $agentEntry -PathType Leaf)) {
        throw "WinMintAgent entrypoint missing after staging: $agentEntry. FirstLogon would have no agent to run; aborting before producing a broken ISO."
    }
    if (Test-Path -LiteralPath (Join-Path $Destination 'agent')) {
        throw "WinMintAgent was staged nested (WinMintAgent\agent\). FirstLogon would launch the wrong (stale) entrypoint; aborting before producing a broken ISO."
    }

    $pkgManifest = Get-WinMintPath -Name ConfigRoot -ChildPath 'packages.json'
    if (Test-Path -LiteralPath $pkgManifest -PathType Leaf) {
        Assert-WinMintAgentToolSources -ManifestPath $pkgManifest
        Copy-Item -LiteralPath $pkgManifest -Destination (Join-Path $Destination 'packages.json') -Force
    }

    if ($null -eq $AgentProfile) {
        throw 'WinMintAgent payload staging requires a generated agent profile. Refusing to fall back to a checked-in BuildProfile.json sample.'
    }

    Save-WinMintSetupPayloadJson -Value $AgentProfile -Path (Join-Path $Destination 'BuildProfile.json') -Depth 12
    LogOK 'Generated WinMintAgent profile from the selected wizard options.'
}

function Copy-WinMintAgentBrandAssets {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$AgentDestination
    )

    $brandImageSource = Join-Path $RepositoryRoot 'assets\brand\winmint_hero.png'
    if (Test-Path -LiteralPath $brandImageSource -PathType Leaf) {
        $brandAssetDir = Join-Path $AgentDestination 'Assets\Brand'
        $null = New-Item -ItemType Directory -Path $brandAssetDir -Force
        Copy-Item -LiteralPath $brandImageSource -Destination (Join-Path $brandAssetDir 'winmint_logo_wordmark.png') -Force
        LogOK 'Staged WinMint logo wordmark PNG for the first-logon console splash.'
    }
}

function Copy-WinMintAgentTerminalIconAssets {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$AgentDestination
    )

    $terminalIconSourceDir = Join-Path $RepositoryRoot 'assets\ui\wsl'
    if (Test-Path -LiteralPath $terminalIconSourceDir -PathType Container) {
        $terminalIconAssetDir = Join-Path $AgentDestination 'Assets\WindowsTerminal\Icons'
        $null = New-Item -ItemType Directory -Path $terminalIconAssetDir -Force
        Get-ChildItem -LiteralPath $terminalIconSourceDir -Filter '*.png' -File -ErrorAction SilentlyContinue |
            Copy-Item -Destination $terminalIconAssetDir -Force
        LogOK 'Staged Windows Terminal PNG profile icons for first-logon setup.'
    }
}

function Get-WinMintDesktopPresetManifest {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ToolId
    )

    $sourceDir = Join-Path $RepositoryRoot "assets\runtime\desktop\$ToolId"
    $manifestPath = Join-Path $sourceDir 'preset.manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Desktop preset manifest is missing for '$ToolId': $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1) { throw "Unsupported desktop preset manifest schema for '$ToolId': $manifestPath" }
    if ([string]$manifest.tool -ne $ToolId) { throw "Desktop preset manifest tool mismatch for '$ToolId': $manifestPath" }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.displayName)) { throw "Desktop preset manifest has no displayName: $manifestPath" }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.stageDirectory)) { throw "Desktop preset manifest has no stageDirectory: $manifestPath" }
    if (-not $manifest.files -or @($manifest.files).Count -eq 0) { throw "Desktop preset manifest has no files: $manifestPath" }

    [pscustomobject]@{
        ToolId = $ToolId
        SourceDir = $sourceDir
        ManifestPath = $manifestPath
        DisplayName = [string]$manifest.displayName
        StageDirectory = [string]$manifest.stageDirectory
        Files = @($manifest.files)
    }
}

function Get-WinMintDesktopPresetSourceFiles {
    param([Parameter(Mandatory)]$Manifest)

    $files = [System.Collections.Generic.List[object]]::new()
    $files.Add([pscustomobject]@{
        Source = [string]$Manifest.ManifestPath
        Destination = 'preset.manifest.json'
        Role = 'manifest'
    }) | Out-Null

    foreach ($file in @($Manifest.Files)) {
        $sourceName = [string]$file.source
        if ([string]::IsNullOrWhiteSpace($sourceName)) {
            throw "Desktop preset manifest has a file without source: $($Manifest.ManifestPath)"
        }
        $destinationName = if ($file.PSObject.Properties['destination'] -and -not [string]::IsNullOrWhiteSpace([string]$file.destination)) {
            [string]$file.destination
        } else {
            $sourceName
        }
        $files.Add([pscustomobject]@{
            Source = (Join-Path $Manifest.SourceDir $sourceName)
            Destination = $destinationName
            Role = if ($file.PSObject.Properties['role']) { [string]$file.role } else { '' }
        }) | Out-Null
    }

    return @($files)
}

function Copy-WinMintAgentDesktopPresetAssets {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$AgentDestination,
        [Parameter(Mandatory)][string]$ToolId
    )

    $manifest = Get-WinMintDesktopPresetManifest -RepositoryRoot $RepositoryRoot -ToolId $ToolId
    $assetDir = Join-Path $AgentDestination "Assets\$($manifest.StageDirectory)"
    $null = New-Item -ItemType Directory -Path $assetDir -Force

    foreach ($file in @(Get-WinMintDesktopPresetSourceFiles -Manifest $manifest)) {
        if (-not (Test-Path -LiteralPath $file.Source -PathType Leaf)) {
            throw "$($manifest.DisplayName) preset asset is missing: $($file.Source)"
        }
        $destination = Join-Path $assetDir ([string]$file.Destination)
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent)) {
            $null = New-Item -ItemType Directory -Path $destinationParent -Force
        }
        Copy-Item -LiteralPath $file.Source -Destination $destination -Force
    }

    LogOK "Staged $($manifest.DisplayName) curated preset for first-logon setup."
}

function Copy-WinMintAgentWindhawkAssets {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$AgentDestination,
        [AllowNull()]$AgentProfile
    )

    if (-not (Test-WinMintAgentProfileSelection -AgentProfile $AgentProfile -Path 'modules.windhawk.enabled')) {
        return
    }

    $windhawkAssetDir = Join-Path $AgentDestination 'Assets\Windhawk'
    $null = New-Item -ItemType Directory -Path $windhawkAssetDir -Force
    Copy-Item -LiteralPath (Get-WinMintPath -Name RuntimeSetupRoot -ChildPath 'WindhawkBootstrap.ps1') -Destination (Join-Path $windhawkAssetDir 'WindhawkBootstrap.ps1') -Force
    Copy-Item -LiteralPath (Get-WinMintPath -Name RuntimeSetupRoot -ChildPath 'WindhawkBootstrap.Helpers.ps1') -Destination (Join-Path $windhawkAssetDir 'WindhawkBootstrap.Helpers.ps1') -Force
    Copy-Item -LiteralPath (Get-WinMintPath -Name RuntimeSetupRoot -ChildPath 'DisableVirtualDesktopFlyouts.ps1') -Destination (Join-Path $windhawkAssetDir 'DisableVirtualDesktopFlyouts.ps1') -Force
    Copy-WinMintAgentDesktopPresetAssets -RepositoryRoot $RepositoryRoot -AgentDestination $AgentDestination -ToolId 'windhawk'
}

function Copy-WinMintAgentYasbAssets {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$AgentDestination,
        [AllowNull()]$AgentProfile
    )

    if (-not (Test-WinMintAgentProfileSelection -AgentProfile $AgentProfile -Path 'modules.shell.yasb')) {
        return
    }

    Copy-WinMintAgentDesktopPresetAssets -RepositoryRoot $RepositoryRoot -AgentDestination $AgentDestination -ToolId 'yasb'
}

function Copy-WinMintAgentKomorebiAssets {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$AgentDestination,
        [AllowNull()]$AgentProfile
    )

    if (-not (Test-WinMintAgentProfileSelection -AgentProfile $AgentProfile -Path 'modules.shell.komorebi')) {
        return
    }

    $komorebiSourceDir = Join-Path $RepositoryRoot 'assets\runtime\desktop\komorebi'
    if (-not (Test-Path -LiteralPath $komorebiSourceDir -PathType Container)) {
        throw "Komorebi preset assets are missing: $komorebiSourceDir"
    }

    $komorebiAssetDir = Join-Path $AgentDestination 'Assets\Komorebi'
    $null = New-Item -ItemType Directory -Path $komorebiAssetDir -Force
    foreach ($name in @('komorebi.json', 'applications.json', 'whkdrc')) {
        Copy-Item -LiteralPath (Join-Path $komorebiSourceDir $name) -Destination (Join-Path $komorebiAssetDir $name) -Force
    }
    LogOK 'Staged Komorebi preset for first-logon setup.'
}

function Copy-WinMintAgentAssetPayloads {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$AgentDestination,
        [AllowNull()]$AgentProfile
    )

    Copy-WinMintAgentBrandAssets -RepositoryRoot $RepositoryRoot -AgentDestination $AgentDestination
    Copy-WinMintAgentTerminalIconAssets -RepositoryRoot $RepositoryRoot -AgentDestination $AgentDestination
    Copy-WinMintAgentWindhawkAssets -RepositoryRoot $RepositoryRoot -AgentDestination $AgentDestination -AgentProfile $AgentProfile
    Copy-WinMintAgentYasbAssets -RepositoryRoot $RepositoryRoot -AgentDestination $AgentDestination -AgentProfile $AgentProfile
    Copy-WinMintAgentKomorebiAssets -RepositoryRoot $RepositoryRoot -AgentDestination $AgentDestination -AgentProfile $AgentProfile
}

function Invoke-WinMintSetupPayloadStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$ScriptRoot,
        [AllowNull()]$AgentProfile,
        [AllowNull()]$SetupProfile,
        [AllowNull()]$SetupPlan
    )

    $bundleDir = Join-Path $ScriptRoot 'src\runtime\setup'
    if (-not (Test-Path -LiteralPath $bundleDir -PathType Container)) {
        throw "WinMint setup script directory is missing: $bundleDir"
    }

    $destScripts = Join-Path $MountDir 'Windows\Setup\Scripts'
    $null = New-Item -ItemType Directory -Path $destScripts -Force -ErrorAction SilentlyContinue

    Copy-WinMintSetupScriptPayloads -BundleDir $bundleDir -Destination $destScripts
    Copy-WinMintSetupCompleteModulePayloads -BundleDir $bundleDir -Destination $destScripts
    Copy-WinMintLiveAuditPayload -RepositoryRoot $ScriptRoot -Destination $destScripts

    if ($null -ne $SetupProfile) {
        Save-WinMintSetupPayloadJson -Value $SetupProfile -Path (Join-Path $destScripts 'WinMintSetupProfile.json') -Depth 12
        LogOK 'Generated setup profile for specialize, SetupComplete, and FirstLogon scripts.'
    }

    if ($null -ne $SetupPlan) {
        Save-WinMintSetupPayloadJson -Value $SetupPlan -Path (Join-Path $destScripts 'WinMintSetupPlan.json') -Depth 16
        LogOK 'Generated setup plan for CLI/UI inspection and install-phase audit.'
    }

    $agentDest = Join-Path $destScripts 'WinMintAgent'
    Copy-WinMintAgentRuntimePayload -RepositoryRoot $ScriptRoot -Destination $agentDest -AgentProfile $AgentProfile
    Copy-WinMintAgentAssetPayloads -RepositoryRoot $ScriptRoot -AgentDestination $agentDest -AgentProfile $AgentProfile

    LogOK 'Copied setup scripts into the offline image (matching files only).'
    [pscustomobject]@{
        Destination = $destScripts
        AgentDestination = $agentDest
        RequiredArtifacts = @(Get-WinMintSetupPayloadRequiredArtifacts)
    }
}

