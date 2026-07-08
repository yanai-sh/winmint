#Requires -Version 7.6

function Invoke-WinMintAgentDotfileBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $module = $AgentProfile.modules.dotfiles
    if (-not $module -or -not [bool]$module.enabled) {
        return [pscustomobject]@{
            Id      = 'dotfiles'
            Status  = 'skipped'
            Message = 'Dotfiles module is not enabled.'
        }
    }

    $repository = [string]$module.repository
    $ref = [string]$module.ref
    if ([string]::IsNullOrWhiteSpace($ref)) { $ref = 'main' }
    $installScript = [string]$module.installScript
    if ([string]::IsNullOrWhiteSpace($repository)) {
        return [pscustomobject]@{
            Id      = 'dotfiles'
            Status  = 'failed'
            Message = 'Dotfiles repository URL is missing.'
        }
    }
    if ($repository -notmatch '^https://') {
        return [pscustomobject]@{
            Id      = 'dotfiles'
            Status  = 'failed'
            Message = 'Dotfiles v1 supports https:// repositories only.'
        }
    }

    $workRoot = Join-Path $env:LOCALAPPDATA 'WinMint\dotfiles'
    $workDir = Join-Path $workRoot 'work'
    $stampPath = Join-Path $workRoot 'applied.json'
    $stamp = [ordered]@{
        repository = $repository
        ref = $ref
        installScript = $installScript
    }
    if (Test-Path -LiteralPath $stampPath) {
        try {
            $applied = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json
            if (
                [string]$applied.repository -eq $repository -and
                [string]$applied.ref -eq $ref -and
                [string]$applied.installScript -eq $installScript
            ) {
                return [pscustomobject]@{
                    Id      = 'dotfiles'
                    Status  = 'ok'
                    Message = 'Dotfiles already applied for this repository/ref.'
                }
            }
        }
        catch { }
    }

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        return [pscustomobject]@{
            Id      = 'dotfiles'
            Status  = 'failed'
            Message = 'MinGit/git is not on PATH.'
        }
    }

    if (Test-Path -LiteralPath $workDir) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Path $workDir -Force
    $cloneArgs = @('clone', '--depth', '1', '--branch', $ref, $repository, $workDir)
    & $git.Source @cloneArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return [pscustomobject]@{
            Id      = 'dotfiles'
            Status  = 'failed'
            Message = "git clone failed for $repository ($ref)."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($installScript)) {
        $scriptPath = Join-Path $workDir $installScript
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            return [pscustomobject]@{
                Id      = 'dotfiles'
                Status  = 'failed'
                Message = "Install script not found: $installScript"
            }
        }
        & (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File $scriptPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{
                Id      = 'dotfiles'
                Status  = 'failed'
                Message = "Dotfiles install script failed: $installScript"
            }
        }
    }

    $null = New-Item -ItemType Directory -Path $workRoot -Force
    ($stamp | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $stampPath -Encoding UTF8
    return [pscustomobject]@{
        Id      = 'dotfiles'
        Status  = 'ok'
        Message = if ($installScript) { "Applied dotfiles from $repository ($ref) via $installScript." } else { "Cloned dotfiles from $repository ($ref)." }
    }
}
