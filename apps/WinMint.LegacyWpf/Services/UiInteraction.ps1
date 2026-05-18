#Requires -Version 7.3

<#
.SYNOPSIS
    Conventional WPF + PowerShell interaction helpers (fault boundaries on the UI thread).
#>

#region agent log
function Write-WinMintUiDebugSessionNdjson {
    param(
        [Parameter(Mandatory)][string]$HypothesisId,
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$Message,
        [hashtable]$Data = @{},
        [string]$RunId = 'pre'
    )
    try {
        # Never use Get-Variable -Scope Script for repo here: dot-sourced files each have their own
        # script scope, so WinMint-UI.ps1's $script:WinMintRepositoryRoot is invisible from this file.
        $paths = [System.Collections.Generic.List[string]]::new()
        if (Get-Command Get-WinMintUiLogDirectory -ErrorAction SilentlyContinue) {
            $paths.Add((Join-Path (Get-WinMintUiLogDirectory) 'debug-55129e.log'))
        } else {
            $ld = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'WinMint\logs'
            $null = New-Item -ItemType Directory -Path $ld -Force -ErrorAction SilentlyContinue
            $paths.Add((Join-Path $ld 'debug-55129e.log'))
        }
        $ctx = Get-WinMintUiAppContextOptional
        if ($null -ne $ctx -and -not [string]::IsNullOrWhiteSpace($ctx.RepositoryRoot)) {
            $paths.Add((Join-Path ([string]$ctx.RepositoryRoot) 'debug-55129e.log'))
        }
        $payload = [ordered]@{
            sessionId    = '55129e'
            runId        = $RunId
            hypothesisId = $HypothesisId
            location     = $Location
            message      = $Message
            data         = $Data
            timestamp    = [int64][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        }
        $line = ($payload | ConvertTo-Json -Compress -Depth 8)
        $enc = [System.Text.UTF8Encoding]::new($false)
        foreach ($p in $paths) {
            try {
                $parent = [System.IO.Path]::GetDirectoryName($p)
                if (-not [string]::IsNullOrWhiteSpace($parent)) {
                    $null = New-Item -ItemType Directory -Path $parent -Force -ErrorAction SilentlyContinue
                }
                [System.IO.File]::AppendAllText($p, "$line`n", $enc)
            } catch {}
        }
    } catch {}
}
#endregion

# WPF may invoke Add_* scriptblocks without preserving outer locals; StrictMode then breaks
# closure-captured strings. Bind Source + Action in this file's script scope and look up by Tag.
$script:WinMintUiRoutedBindings = @{}

function Set-WinMintUiRoutedBinding {
    param(
        [Parameter(Mandatory)][string]$BindingKey,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    $script:WinMintUiRoutedBindings[$BindingKey] = @{
        Source = $Source
        Action = $Action
    }
}

function Clear-WinMintUiRoutedBindings {
    $script:WinMintUiRoutedBindings.Clear()
}

function Invoke-WinMintUiRoutedBinding {
    param([Parameter(Mandatory)][string]$BindingKey)
    $cell = $script:WinMintUiRoutedBindings[$BindingKey]
    if ($null -eq $cell) {
        #region agent log
        try {
            Write-WinMintUiDebugSessionNdjson -HypothesisId 'H2' -Location 'UiInteraction.ps1:Invoke-WinMintUiRoutedBinding' `
                -Message 'missing_binding' -Data @{ key = $BindingKey } -RunId 'pre'
        } catch {}
        #endregion
        return $false
    }
    return Invoke-WinMintUiRoutedAction -Source $cell.Source -Action $cell.Action
}

function Invoke-WinMintUiRoutedAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )
    #region agent log
    try {
        Write-WinMintUiDebugSessionNdjson -HypothesisId 'H2' -Location 'UiInteraction.ps1:Invoke-WinMintUiRoutedAction' `
            -Message 'routed_enter' -Data @{ source = $Source } -RunId 'pre'
    } catch {}
    #endregion
    try {
        & $Action
        #region agent log
        try {
            Write-WinMintUiDebugSessionNdjson -HypothesisId 'H2' -Location 'UiInteraction.ps1:Invoke-WinMintUiRoutedAction' `
                -Message 'routed_ok' -Data @{ source = $Source } -RunId 'pre'
        } catch {}
        #endregion
        return $true
    } catch {
        #region agent log
        try {
            Write-WinMintUiDebugSessionNdjson -HypothesisId 'H2' -Location 'UiInteraction.ps1:Invoke-WinMintUiRoutedAction' `
                -Message 'routed_caught' -Data @{
                source = $Source
                err    = $_.Exception.Message
            } -RunId 'pre'
        } catch {}
        #endregion
        $message = $_.Exception.Message
        if (Get-Command Write-WinMintUiLog -ErrorAction SilentlyContinue) {
            Write-WinMintUiLog -Level ERROR -Source $Source -Message $message
        } else {
            Write-Warning "[$Source] $message"
        }
        if (Get-Command Format-WinMintUiErrorRecord -ErrorAction SilentlyContinue) {
            $detail = Format-WinMintUiErrorRecord -InputObject $_ -AsSingleString
            if (Get-Command Export-WinMintUiFaultReport -ErrorAction SilentlyContinue) {
                $safe = ($Source -replace '[^\w\-\.]+', '_')
                Export-WinMintUiFaultReport -Body $detail -RelativeFileName "WinMint-UI-routed-$safe.txt"
            }
        }
        return $false
    }
}
