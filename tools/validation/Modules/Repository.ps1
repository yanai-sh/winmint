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
        'apps/gui/bin/WinMint-GUI.exe',
        'apps/gui/README.md',
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
        if ($item -ne 'apps/gui/bin/WinMint-GUI.exe' -and -not (Test-Path -LiteralPath (Join-Path $root $item))) {
            Add-ValidationError "Release manifest include path does not exist: $item"
        }
    }

    $requiredExcludes = @(
        'cloudflare',
        'tests',
        'tools',
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
        'apps/gui/bin/',
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

    Write-Host 'OK repository test fixture layout'
}

function Test-RepositoryHygiene {
    Test-RepositoryNoTrackedGeneratedArtifacts
    Test-RepositoryRequiredDocs
    Test-RepositoryGitIgnorePolicy
    Test-RepositoryPreCommitHook
    Test-RepositoryReleaseManifest
    Test-RepositoryTrackedPathCasing
    Test-RepositoryFixtureLayout
}

