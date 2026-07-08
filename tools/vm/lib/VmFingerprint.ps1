#Requires -Version 7.6
# Dot-sourced by WinMint-VmConsole.ps1 — not a standalone entrypoint.
function Get-WinMintVmPathFingerprintParts {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Prefix = ''
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop |
        Where-Object {
            $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
            $rel -notmatch '(?i)(^|[\\/])(bin|obj)([\\/]|$)' -and
            $rel -notmatch '(?i)WinMintSetupShell\.exe\.WebView2([\\/]|$)'
        } |
        Sort-Object FullName |
        ForEach-Object {
            $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/').ToLowerInvariant()
            if ($Prefix) { $rel = "$Prefix/$rel" }
            "$rel|$($_.Length)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        })
}

function Get-WinMintVmFileFingerprintPart {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $item = Get-Item -LiteralPath $Path
    $name = $item.Name.ToLowerInvariant()
    return @("$name|$($item.Length)|$((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)")
}

function Get-WinMintVmBuildFingerprintBlob {
    param([Parameter(Mandatory)][string[]]$Parts)

    return ($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`n"
}

function Get-WinMintVmBuildFingerprintHash {
    param([Parameter(Mandatory)][string]$Blob)

    return ([BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Blob))) -replace '-', '').ToLowerInvariant()
}

function Get-WinMintVmCachedIsoInfo {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$ImageFingerprint
    )

    $info = [ordered]@{
        Cached = $false
        IsoPath = ''
        StoredImageFingerprint = ''
        StoredAgentFingerprint = ''
    }
    $fingerprintPath = Join-Path $RepoRoot 'output\.vm-build-fingerprint.json'
    if (-not (Test-Path -LiteralPath $fingerprintPath)) { return [pscustomobject]$info }

    try {
        $prev = Get-Content -LiteralPath $fingerprintPath -Raw | ConvertFrom-Json
        $storedImage = if ($prev.PSObject.Properties['imageFingerprint'] -and -not [string]::IsNullOrWhiteSpace([string]$prev.imageFingerprint)) {
            [string]$prev.imageFingerprint
        }
        else {
            [string]$prev.fingerprint
        }
        $info.StoredImageFingerprint = $storedImage
        if ($prev.PSObject.Properties['agentFingerprint']) {
            $info.StoredAgentFingerprint = [string]$prev.agentFingerprint
        }
        if ($prev.isoPath -and (Test-Path -LiteralPath ([string]$prev.isoPath))) {
            $info.IsoPath = [string]$prev.isoPath
            if ($ImageFingerprint -and $storedImage -eq $ImageFingerprint) {
                $info.Cached = $true
            }
            elseif (-not $ImageFingerprint) {
                $info.Cached = $true
            }
        }
    }
    catch { }

    return [pscustomobject]$info
}

function Resolve-WinMintVmAcceptanceBuildPlan {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)]$ProfileJson,
        [Parameter(Mandatory)][string]$VMName,
        [switch]$ForceBuild,
        [switch]$UseCheckpoint,
        [switch]$PushOnly,
        [switch]$SmartBuild,
        [string]$Quality = 'fast'
    )

    $imageFp = Get-WinMintVmImageBuildFingerprint -ProfilePath $ProfilePath -ProfileJson $ProfileJson -RepoRoot $RepoRoot -Quality $Quality
    $agentFp = Get-WinMintVmAgentBuildFingerprint -RepoRoot $RepoRoot
    $isoInfo = Get-WinMintVmCachedIsoInfo -RepoRoot $RepoRoot -ImageFingerprint $imageFp
    $checkpointUsable = $false
    if ($UseCheckpoint) {
        $checkpointUsable = Test-WinMintVmPostSetupCheckpointUsable -VMName $VMName -Fingerprint $imageFp -RepoRoot $RepoRoot
    }

    $storedAgentFp = ''
    $checkpointSidecar = Get-WinMintVmPostSetupCheckpointSidecarPath -RepoRoot $RepoRoot
    if (Test-Path -LiteralPath $checkpointSidecar) {
        try {
            $sidecar = Get-Content -LiteralPath $checkpointSidecar -Raw | ConvertFrom-Json
            $storedAgentFp = [string]$sidecar.agentFingerprint
        }
        catch { }
    }
    if ([string]::IsNullOrWhiteSpace($storedAgentFp)) {
        $storedAgentFp = [string]$isoInfo.StoredAgentFingerprint
    }

    $effectiveForceBuild = [bool]$ForceBuild
    $notes = [System.Collections.Generic.List[string]]::new()
    if ($SmartBuild -and $ForceBuild -and $isoInfo.Cached) {
        $effectiveForceBuild = $false
        $notes.Add('SmartBuild ignored -ForceBuild (image fingerprint unchanged; ISO cache still valid).') | Out-Null
    }

    $strategy = 'iso-build-install'
    $estimatedMinutes = '25-35'
    if ($PushOnly) {
        if (-not $checkpointUsable) {
            throw 'Push-only iteration requires a usable PostSetup checkpoint. Run a full smoke once first (omit -PushOnly).'
        }
        $strategy = 'push-only'
        $estimatedMinutes = '2-8'
    }
    elseif ($effectiveForceBuild) {
        $strategy = 'force-rebuild'
        $estimatedMinutes = '25-35'
    }
    elseif ($checkpointUsable) {
        if ([string]::IsNullOrWhiteSpace($storedAgentFp) -or $storedAgentFp -ne $agentFp) {
            $strategy = 'checkpoint-push'
            $estimatedMinutes = '3-12'
        }
        else {
            $strategy = 'checkpoint-reuse'
            $estimatedMinutes = '3-12'
        }
    }
    elseif ($isoInfo.Cached) {
        $strategy = 'iso-cached-install'
        $estimatedMinutes = '15-25'
    }

    return [pscustomobject][ordered]@{
        Strategy = $strategy
        EstimatedMinutes = $estimatedMinutes
        ImageFingerprint = $imageFp
        AgentFingerprint = $agentFp
        StoredAgentFingerprint = $storedAgentFp
        IsoCached = [bool]$isoInfo.Cached
        IsoPath = [string]$isoInfo.IsoPath
        CheckpointUsable = [bool]$checkpointUsable
        UseCheckpoint = [bool]$UseCheckpoint
        ForceBuild = [bool]$effectiveForceBuild
        PushOnly = [bool]$PushOnly
        AgentChanged = (-not [string]::IsNullOrWhiteSpace($storedAgentFp)) -and ($storedAgentFp -ne $agentFp)
        Notes = @($notes)
    }
}

function Invoke-WinMintVmAcceptanceCheckpointIteration {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ToolsVmRoot,
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$ImageFingerprint,
        [Parameter(Mandatory)][string]$AgentMode,
        [string]$SwitchName,
        [switch]$AlwaysPushAgent
    )

    $switchForRestore = $SwitchName
    if (-not $switchForRestore) {
        $defaultSwitch = Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue
        if ($defaultSwitch) { $switchForRestore = $defaultSwitch.Name }
    }
    Write-Host "Restoring PostSetup checkpoint on '$VMName' (skipping ISO build and Windows Setup)."
    Restore-WinMintVmPostSetupCheckpoint -VMName $VMName -SwitchName $switchForRestore

    $storedAgentFp = ''
    $sidecarPath = Get-WinMintVmPostSetupCheckpointSidecarPath -RepoRoot $RepoRoot
    try {
        $sidecar = Get-Content -LiteralPath $sidecarPath -Raw | ConvertFrom-Json
        $storedAgentFp = [string]$sidecar.agentFingerprint
    }
    catch { }

    $agentFp = Get-WinMintVmAgentBuildFingerprint -RepoRoot $RepoRoot
    $agentChanged = [string]::IsNullOrWhiteSpace($storedAgentFp) -or $storedAgentFp -ne $agentFp
    if ($AlwaysPushAgent -or $agentChanged) {
        $reason = if ($agentChanged) { 'agent/runtime changed' } else { 'acceptance rerun' }
        Write-Host "Pushing live scripts and re-running FirstLogon ($reason; AgentMode=$AgentMode)."
        Invoke-WinMintVmPushAgentScripts -RepoRoot $RepoRoot -ToolsVmRoot $ToolsVmRoot -VMName $VMName -Credential $Credential `
            -ProfilePath $ProfilePath -AgentMode $AgentMode -RerunFirstLogon
    }
    else {
        Write-Host 'Agent/runtime unchanged since checkpoint â€” starting FirstLogon via restored autologon (no push).'
    }
}

function Get-WinMintVmImageBuildFingerprint {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)]$ProfileJson,
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Quality = 'fast'
    )

    $profileHash = (Get-FileHash -LiteralPath $ProfilePath -Algorithm SHA256).Hash
    $runtimeParts = Get-WinMintVmPathFingerprintParts -Root (Join-Path $RepoRoot 'src\runtime\image')
    $setupAssetParts = Get-WinMintVmPathFingerprintParts -Root (Join-Path $RepoRoot 'assets\runtime\setup')
    $setupShellSourceParts = @(
        (Get-WinMintVmPathFingerprintParts -Root (Join-Path $RepoRoot 'apps\setup-shell'))
        (Get-WinMintVmPathFingerprintParts -Root (Join-Path $RepoRoot 'assets\runtime\setup\setup-shell') | Where-Object { $_ -match '\.(json|png)$' })
    ) | ForEach-Object { $_ }
    $srcIso = [string]$ProfileJson.source.isoPath
    $srcIdentity = 'none'
    if ($srcIso) {
        $resolvedSrc = if ([IO.Path]::IsPathRooted($srcIso)) { $srcIso } else { Join-Path $RepoRoot $srcIso }
        if (Test-Path -LiteralPath $resolvedSrc) {
            $it = Get-Item -LiteralPath $resolvedSrc
            $srcIdentity = "$($it.FullName)|$($it.Length)|$($it.LastWriteTimeUtc.Ticks)"
        }
    }
    $blob = Get-WinMintVmBuildFingerprintBlob -Parts @(
        "schema=image-v1"
        "quality=$Quality"
        "profile=$profileHash"
        "src=$srcIdentity"
        "runtime=$($runtimeParts -join ';')"
        "setupAssets=$($setupAssetParts -join ';')"
        "setupShellSource=$($setupShellSourceParts -join ';')"
    )
    return Get-WinMintVmBuildFingerprintHash -Blob $blob
}

function Get-WinMintVmAgentBuildFingerprint {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $setupParts = Get-WinMintVmPathFingerprintParts -Root (Join-Path $RepoRoot 'src\runtime\setup')
    $agentParts = Get-WinMintVmPathFingerprintParts -Root (Join-Path $RepoRoot 'src\runtime\firstlogon')
    $packagesParts = Get-WinMintVmFileFingerprintPart -Path (Join-Path $RepoRoot 'config\packages.json')
    $blob = Get-WinMintVmBuildFingerprintBlob -Parts @(
        'schema=agent-v1'
        "setup=$($setupParts -join ';')"
        "firstlogon=$($agentParts -join ';')"
        "packages=$($packagesParts -join ';')"
    )
    return Get-WinMintVmBuildFingerprintHash -Blob $blob
}
