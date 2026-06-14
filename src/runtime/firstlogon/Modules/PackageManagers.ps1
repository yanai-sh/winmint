#Requires -Version 7.3

function Get-WinMintAgentStarshipConfigPath {
    $configRoot = if (-not [string]::IsNullOrWhiteSpace([string]$env:XDG_CONFIG_HOME)) {
        [Environment]::ExpandEnvironmentVariables([string]$env:XDG_CONFIG_HOME)
    }
    else {
        Join-Path $env:USERPROFILE '.config'
    }
    return (Join-Path $configRoot 'starship.toml')
}

function Get-WinMintAgentPowerShellProfilePath {
    try {
        if ($PROFILE -and $PROFILE.PSObject.Properties['CurrentUserAllHosts'] -and
            -not [string]::IsNullOrWhiteSpace([string]$PROFILE.CurrentUserAllHosts)) {
            return [string]$PROFILE.CurrentUserAllHosts
        }
    }
    catch {
        Write-AgentLog "PowerShell profile path probe warning: $($_.Exception.Message)"
    }
    return (Join-Path $env:USERPROFILE 'Documents\PowerShell\profile.ps1')
}

function Set-WinMintAgentStarshipPowerShellProfile {
    param([Parameter(Mandatory)][string]$ProfilePath)

    $profileDir = Split-Path -Parent $ProfilePath
    if (-not [string]::IsNullOrWhiteSpace($profileDir)) {
        $null = New-Item -ItemType Directory -Path $profileDir -Force
    }
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
        Set-Content -LiteralPath $ProfilePath -Value '' -Encoding UTF8
    }

    $profileText = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8
    if ($profileText -match 'starship\s+init\s+powershell') {
        return
    }

    $block = @'

# WinMint Starship prompt begin
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
# WinMint Starship prompt end
'@
    Add-Content -LiteralPath $ProfilePath -Value $block -Encoding UTF8
}

function Install-WinMintAgentStarshipPrompt {
    param([Parameter(Mandatory)][hashtable]$State)

    $key = 'shell:starship'
    if (-not $Force -and $State.steps.ContainsKey($key) -and [string]$State.steps[$key].status -eq 'ok') {
        Write-AgentConsoleLine -Level OK -Message 'Starship prompt already configured.'
        return
    }

    try {
        Install-AgentManifestTool -ToolId 'starship' -State $State
        Update-AgentProcessPath
        $starship = Get-Command starship -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $starship) { throw 'starship command not available after install.' }

        $configPath = Get-WinMintAgentStarshipConfigPath
        $configDir = Split-Path -Parent $configPath
        if (-not [string]::IsNullOrWhiteSpace($configDir)) {
            $null = New-Item -ItemType Directory -Path $configDir -Force
        }

        if ($Force -or -not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
            Invoke-AgentNative -FilePath $starship.Source -ArgumentList @('preset', 'nerd-font-symbols', '-o', $configPath)
        }
        else {
            Write-AgentLog "Starship config already exists; leaving user config in place: $configPath"
        }

        $profilePath = Get-WinMintAgentPowerShellProfilePath
        Set-WinMintAgentStarshipPowerShellProfile -ProfilePath $profilePath
        $State.steps[$key] = @{
            status = 'ok'
            updatedAt = (Get-Date -Format o)
            preset = 'nerd-font-symbols'
            configPath = $configPath
            powerShellProfile = $profilePath
            terminalFont = 'Cascadia Code NF'
        }
        Save-AgentState -State $State
        Write-AgentConsoleLine -Level OK -Message 'Starship prompt configured.'
    }
    catch {
        $State.steps[$key] = @{
            status = 'failed'
            updatedAt = (Get-Date -Format o)
            preset = 'nerd-font-symbols'
            error = $_.Exception.Message
        }
        Save-AgentState -State $State
        throw
    }
}

function Invoke-WinMintAgentPackageManagerBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    [void]$AgentProfile
    [void]$State
    $winget = Wait-WingetPath
    if (-not $winget) { throw 'winget.exe not available after wait.' }
    Install-AgentScoop -State $State
    Install-AgentManifestTool -ToolId 'mingit' -State $State
    Install-WinMintAgentStarshipPrompt -State $State

    [pscustomobject]@{
        Id      = 'package-managers'
        Status  = 'ok'
        Message = 'winget ready; Scoop, MinGit, and Starship installed.'
    }
}
