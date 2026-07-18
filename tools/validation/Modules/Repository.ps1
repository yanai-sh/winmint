#Requires -Version 7.6

function Get-RepositoryTrackedPath {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Warning 'git not found; skipping repository tracked-path checks.'
        return @()
    }

    $paths = @(& $git.Source -C $root ls-files 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'git ls-files failed; skipping repository tracked-path checks.'
        return @()
    }

    @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-RepositoryNoTrackedGeneratedArtifacts {
    $tracked = @(Get-RepositoryTrackedPath)
    if ($tracked.Count -eq 0) { return }

    $generatedPatterns = @(
        '^output(?:/|$)',
        '^input(?:/|$)',
        '^dist(?:/|$)',
        '^\.claude(?:/|$)',
        '^\.superpowers(?:/|$)',
        '^\.winmint-ui\.json$',
        '(^|/)bin/',
        '(^|/)obj/',
        '^tests/fixtures/(?:iso|drivers)/(?!\.gitkeep$|\.gitignore$)',
        '\.(iso|wim|esd|swm|vhd|vhdx|log)$'
    )

    $violations = @(
        foreach ($path in $tracked) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $path))) {
                continue
            }
            foreach ($pattern in $generatedPatterns) {
                if ($path -match $pattern) {
                    $path
                    break
                }
            }
        }
    )

    foreach ($path in $violations) {
        Add-ValidationError "Generated/local artifact is tracked by git: $path"
    }
    if ($violations.Count -eq 0) {
        Write-Host 'OK repository generated/local artifact policy'
    }
}

function Test-RepositoryRequiredDocs {
    $required = @(
        'AGENTS.md',
        'README.md',
        'docs\Project-Structure.md',
        'docs\Distribution.md',
        'docs\Release-Readiness.md',
        'docs\Hardware-Acceptance.md',
        'tests\README.md'
    )

    foreach ($relativePath in $required) {
        $path = Join-Path $root $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-ValidationError "Required repository document is missing: $relativePath"
        }
    }
    Write-Host 'OK repository required documents'
}

function Test-RepositoryPreCommitHook {
    $relativePath = '.githooks\pre-commit'
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-ValidationError "Required pre-commit hook is missing: $relativePath"
        return
    }

    $text = Get-Content -LiteralPath $path -Raw
    if ($text -match 'scripts/Validate\.ps1') {
        Add-ValidationError '.githooks\pre-commit references stale scripts/Validate.ps1; use tools/validation/Validate.ps1.'
    }
    if ($text -notmatch 'tools/validation/Validate\.ps1') {
        Add-ValidationError '.githooks\pre-commit must run tools/validation/Validate.ps1.'
    }
    Write-Host 'OK repository pre-commit hook target'
}

function Test-RepositoryReleaseManifest {
    $relativePath = 'config\release-manifest.json'
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-ValidationError "Release manifest is missing: $relativePath"
        return
    }

    try {
        $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-ValidationError "Release manifest parse failed: $relativePath :: $($_.Exception.Message)"
        return
    }

    if ($manifest.schema -ne 'winmint.releaseManifest.v1') {
        Add-ValidationError "Unsupported release manifest schema: $($manifest.schema)"
    }

    $include = @($manifest.include | ForEach-Object { [string]$_ })
    $exclude = @($manifest.exclude | ForEach-Object { [string]$_ })
    $requiredIncludes = @(
        'WinMint-CLI.ps1',
        'WinMint-GUI.ps1',
        'winmint.ps1',
        'tools/ui-bridge',
        'assets',
        'config',
        'docs',
        'schemas',
        'src'
    )
    foreach ($item in $requiredIncludes) {
        if ($include -notcontains $item) {
            Add-ValidationError "Release manifest missing required include: $item"
            continue
        }
        if (-not (Test-Path -LiteralPath (Join-Path $root ($item -replace '/', '\')) -PathType Leaf -ErrorAction SilentlyContinue) -and
            -not (Test-Path -LiteralPath (Join-Path $root ($item -replace '/', '\')) -PathType Container)) {
            Add-ValidationError "Release manifest include path does not exist: $item"
        }
    }

    $requiredExcludes = @(
        'cloudflare',
        'tests',
        'tools/vm',
        'tools/dev',
        'tools/release',
        'tools/validation',
        'node_modules',
        'output',
        'temp',
        '**/target',
        '**/.venv',
        'input/drivers/**/*.msi',
        'input/drivers/**/_msi_extract_*',
        'assets/runtime/cursors/_extract',
        'assets/runtime/cursors/*.zip',
        'assets/runtime/cursors/*/png',
        '**/*.iso',
        '**/*.log'
    )
    foreach ($item in $requiredExcludes) {
        if ($exclude -notcontains $item) {
            Add-ValidationError "Release manifest missing required exclude: $item"
        }
    }

    Write-Host 'OK repository release manifest boundary'
}

function Test-RepositoryReleaseReadiness {
    $relativePath = 'config\release-readiness.json'
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-ValidationError "Release readiness contract is missing: $relativePath"
        return
    }

    try {
        $contract = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-ValidationError "Release readiness contract parse failed: $relativePath :: $($_.Exception.Message)"
        return
    }

    if ([string]$contract.schema -ne 'winmint.releaseReadiness.v1') {
        Add-ValidationError "Unsupported release readiness schema: $($contract.schema)"
    }
    if ([string]$contract.publicLaunch.command -ne 'irm https://winmint.yanai.sh | iex') {
        Add-ValidationError 'Release readiness public launch command must remain irm https://winmint.yanai.sh | iex.'
    }
    if ([string]$contract.publicLaunch.mode -ne 'ephemeral') {
        Add-ValidationError 'Release readiness public launch mode must be ephemeral.'
    }
    foreach ($booleanField in @('requiresChecksum', 'forbidsDefaultLocalAppDataCache', 'durableCacheOptInOnly')) {
        $property = $contract.publicLaunch.PSObject.Properties[$booleanField]
        if (-not $property -or $property.Value -ne $true) {
            Add-ValidationError "Release readiness publicLaunch.$booleanField must be true."
        }
    }

    if ([string]$contract.hostRequirements.backendPowerShell -ne '7.6.2+') {
        Add-ValidationError 'Release readiness backend PowerShell requirement must be 7.6.2+.'
    }
    if ([string]$contract.hostRequirements.sourceIso -notmatch '25H2\+') {
        Add-ValidationError 'Release readiness source ISO requirement must mention Windows 11 25H2+.'
    }

    $gateIds = @($contract.gates | ForEach-Object { [string]$_.id })
    foreach ($requiredGate in @('release-bundle-smoke', 'contract-validation', 'repository-validation', 'clean-host-smoke')) {
        if ($gateIds -notcontains $requiredGate) {
            Add-ValidationError "Release readiness contract missing required gate: $requiredGate"
        }
    }
    foreach ($gate in @($contract.gates)) {
        if ($gate.required -ne $true) {
            Add-ValidationError "Release readiness gate must be required: $($gate.id)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$gate.evidence)) {
            Add-ValidationError "Release readiness gate missing evidence command/path: $($gate.id)"
        }
        if (@($gate.covers).Count -eq 0) {
            Add-ValidationError "Release readiness gate missing coverage list: $($gate.id)"
        }
    }
    if (@($contract.notReadyIf).Count -lt 4) {
        Add-ValidationError 'Release readiness contract must list concrete not-ready conditions.'
    }

    Write-Host 'OK repository release readiness contract'
}

function Test-RepositoryHardwareAcceptance {
    $relativePath = 'config\hardware-acceptance.json'
    $path = Join-Path $root $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-ValidationError "Hardware acceptance contract is missing: $relativePath"
        return
    }

    try {
        $contract = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Add-ValidationError "Hardware acceptance contract parse failed: $relativePath :: $($_.Exception.Message)"
        return
    }

    if ([string]$contract.schema -ne 'winmint.hardwareAcceptance.v1') {
        Add-ValidationError "Unsupported hardware acceptance schema: $($contract.schema)"
    }

    $machines = @($contract.machines)
    if ($machines.Count -lt 3) {
        Add-ValidationError 'Hardware acceptance contract must track ARM64 Surface, amd64 laptop, and amd64 desktop coverage.'
    }
    $machineIds = @($machines | ForEach-Object { [string]$_.id })
    foreach ($requiredId in @('surface-laptop-7-arm64', 'thinkpad-return-amd64', 'alienware-aurora-amd64')) {
        if ($machineIds -notcontains $requiredId) {
            Add-ValidationError "Hardware acceptance contract missing required machine: $requiredId"
        }
    }

    $priority = @($contract.priority | ForEach-Object { [string]$_ })
    if ($priority.Count -eq 0 -or $priority[0] -ne 'surface-laptop-7-arm64') {
        Add-ValidationError 'Hardware acceptance priority must put Surface Laptop 7 ARM64 first.'
    }
    foreach ($id in $priority) {
        if ($machineIds -notcontains $id) {
            Add-ValidationError "Hardware acceptance priority references unknown machine: $id"
        }
    }

    foreach ($machine in $machines) {
        $profileRelative = [string]$machine.profile
        if ([string]::IsNullOrWhiteSpace($profileRelative)) {
            Add-ValidationError "Hardware acceptance machine '$($machine.id)' is missing profile."
            continue
        }
        $profilePath = Join-Path $root ($profileRelative -replace '/', '\')
        if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
            Add-ValidationError "Hardware acceptance profile is missing for '$($machine.id)': $profileRelative"
            continue
        }

        try {
            $profile = Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            Add-ValidationError "Hardware acceptance profile parse failed for '$($machine.id)': $profileRelative :: $($_.Exception.Message)"
            continue
        }

        if ([string]$profile.source.architecture -ne [string]$machine.architecture) {
            Add-ValidationError "Hardware acceptance architecture mismatch for '$($machine.id)': contract=$($machine.architecture), profile=$($profile.source.architecture)"
        }
        if ([string]$profile.drivers.source -ne [string]$machine.requiredDriverSource) {
            Add-ValidationError "Hardware acceptance driver source mismatch for '$($machine.id)': contract=$($machine.requiredDriverSource), profile=$($profile.drivers.source)"
        }
        if ([string]$profile.drivers.path -ne [string]$machine.requiredDriverPath) {
            Add-ValidationError "Hardware acceptance driver path mismatch for '$($machine.id)': contract=$($machine.requiredDriverPath), profile=$($profile.drivers.path)"
        }
        if ($machine.surface -eq $true -and [string]$machine.requiredDriverSource -ne 'SurfaceCatalog') {
            Add-ValidationError "Surface hardware acceptance machine '$($machine.id)' must use SurfaceCatalog."
        }
        if (@($machine.checks).Count -lt 4) {
            Add-ValidationError "Hardware acceptance machine '$($machine.id)' must list concrete checks."
        }
    }

    $evidence = @($contract.evidence | ForEach-Object { [string]$_ })
    if ($evidence.Count -lt 5) {
        Add-ValidationError 'Hardware acceptance contract must list required evidence artifacts.'
    }
    foreach ($expectedEvidence in @(
            'BuildProfile.json',
            'BuildManifest.json',
            'BuildDelta.json',
            '%LOCALAPPDATA%\WinMint\state.json',
            'C:\ProgramData\WinMint\Logs'
        )) {
        if ($evidence -notcontains $expectedEvidence) {
            Add-ValidationError "Hardware acceptance evidence list missing: $expectedEvidence"
        }
    }

    Write-Host 'OK repository hardware acceptance contract'
}

function Test-RepositoryTrackedPathCasing {
    $tracked = @(Get-RepositoryTrackedPath)
    if ($tracked.Count -eq 0) { return }

    $canonicalPaths = @(
        'tools/validation/Validate.ps1',
        'tools/validation/Modules/Repository.ps1',
        'tests/README.md',
        'tests/fixtures/iso/.gitignore',
        'tests/fixtures/iso/.gitkeep',
        'tests/fixtures/drivers/.gitignore',
        'tests/fixtures/drivers/.gitkeep',
        'src/runtime/image/WinMint.ps1',
        'WinMint-GUI.ps1',
        'src/runtime/firstlogon/Start-WinMintAgent.ps1',
        'config/release-manifest.json'
    )

    foreach ($path in $canonicalPaths) {
        $caseMatches = @($tracked | Where-Object { $_.ToLowerInvariant() -eq $path.ToLowerInvariant() })
        if ($caseMatches.Count -gt 0 -and $caseMatches -notcontains $path) {
            Add-ValidationError "Tracked path casing drift. Expected '$path', found '$($caseMatches -join ', ')'."
        }
        elseif ($caseMatches.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $root $path))) {
            Add-ValidationError "Canonical repository path is missing: $path"
        }
    }

    $duplicates = @(
        $tracked |
            Group-Object { $_.ToLowerInvariant() } |
            Where-Object { $_.Count -gt 1 }
    )
    foreach ($group in $duplicates) {
        Add-ValidationError "Case-insensitive duplicate tracked paths: $($group.Group -join ', ')"
    }

    Write-Host 'OK repository tracked path casing'
}

function Test-RepositoryGitIgnorePolicy {
    $gitignorePath = Join-Path $root '.gitignore'
    if (-not (Test-Path -LiteralPath $gitignorePath -PathType Leaf)) {
        Add-ValidationError 'Root .gitignore is missing.'
        return
    }

    $lines = @(Get-Content -LiteralPath $gitignorePath | ForEach-Object { [string]$_ })
    $rules = @(
        $lines |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#') }
    )

    foreach ($duplicate in @($rules | Group-Object | Where-Object { $_.Count -gt 1 })) {
        Add-ValidationError "Duplicate .gitignore rule: $($duplicate.Name)"
    }

    $requiredRules = @(
        '*.iso',
        '*.wim',
        '*.esd',
        '*.swm',
        '*.vhd',
        '*.vhdx',
        'dist/',
        'input/',
        'output/',
        'temp/',
        '.winmint-ui.json',
        'node_modules/',
        'input/drivers/**/*.msi',
        'input/drivers/**/_msi_extract_*/',
        '**/bin/',
        '**/obj/',
        '**/target/',
        'assets/runtime/setup/setup-shell/bin/',
        'assets/runtime/cursors/_extract/',
        'assets/runtime/cursors/*.zip',
        'assets/runtime/cursors/*/png/',
        '.claude/',
        '.superpowers/'
    )

    foreach ($rule in $requiredRules) {
        if ($rules -notcontains $rule) {
            Add-ValidationError "Root .gitignore missing required rule: $rule"
        }
    }

    foreach ($relativePath in @(
            'tests\fixtures\iso\.gitignore',
            'tests\fixtures\drivers\.gitignore'
        )) {
        $path = Join-Path $root $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-ValidationError "Fixture .gitignore missing: $relativePath"
            continue
        }
        $fixtureRules = @(Get-Content -LiteralPath $path | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        foreach ($rule in @('*', '!.gitignore', '!.gitkeep')) {
            if ($fixtureRules -notcontains $rule) {
                Add-ValidationError "Fixture .gitignore '$relativePath' missing rule: $rule"
            }
        }
    }

    Write-Host 'OK repository .gitignore policy'
}

function Test-RepositoryFixtureLayout {
    $fixtureDirs = @(
        'tests\fixtures\iso',
        'tests\fixtures\drivers'
    )

    foreach ($relativePath in $fixtureDirs) {
        $path = Join-Path $root $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            Add-ValidationError "Required test fixture directory is missing: $relativePath"
            continue
        }

        foreach ($requiredFile in @('.gitignore', '.gitkeep')) {
            $requiredPath = Join-Path $path $requiredFile
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                Add-ValidationError "Required test fixture file is missing: $relativePath\$requiredFile"
            }
        }
    }

    # Source ISO check: verify a real (non-zero-byte) Windows ISO is resolvable.
    # A 0-byte placeholder in tests/fixtures/iso/ satisfies Test-Path for contract tests
    # but will fail any real build or dry-run. This check warns early.
    $localIsoDir = Join-Path $env:LOCALAPPDATA 'WinMint\source-iso'
    $localIso = if (Test-Path -LiteralPath $localIsoDir) {
        Get-ChildItem -LiteralPath $localIsoDir -Filter '*.iso' -File |
            Where-Object { $_.Length -gt 0 } |
            Select-Object -First 1
    }
    if (-not $localIso) {
        $fixtureIsoDir = Join-Path $root 'tests\fixtures\iso'
        $fixtureIso = Get-ChildItem -LiteralPath $fixtureIsoDir -Filter '*.iso' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -gt 0 } |
            Select-Object -First 1
        if (-not $fixtureIso) {
            $zeroByteStub = Get-ChildItem -LiteralPath $fixtureIsoDir -Filter '*.iso' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -eq 0 } |
                Select-Object -First 1
            if ($zeroByteStub) {
                Write-Warning "Source ISO placeholder '$($zeroByteStub.Name)' is 0 bytes and cannot be used for builds. Place the real Windows 11 ARM64 ISO in: $localIsoDir"
            }
            else {
                Write-Warning "No source ISO found. Place the official Windows 11 ARM64 ISO in: $localIsoDir"
            }
        }
    }

    Write-Host 'OK repository test fixture layout'
}

function Test-RepositoryHygiene {
    Test-RepositoryNoTrackedGeneratedArtifacts
    Test-RepositoryRequiredDocs
    Test-RepositoryGitIgnorePolicy
    Test-RepositoryPreCommitHook
    Test-RepositoryReleaseManifest
    Test-RepositoryReleaseReadiness
    Test-RepositoryHardwareAcceptance
    Test-RepositoryTrackedPathCasing
    Test-RepositoryFixtureLayout
}

