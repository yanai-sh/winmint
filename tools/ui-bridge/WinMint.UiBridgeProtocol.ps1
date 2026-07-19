#Requires -Version 5.1
# Shared ui-bridge stdout protocol helpers. Result lines are single-line JSON with
# schemaVersion + type=result so the wizard host can ignore log noise.

$script:WinMintUiBridgeSchemaVersion = 1

function ConvertTo-WinMintUiBridgeResultJson {
    param(
        [Parameter(Mandatory)]$Result
    )

    $payload = [ordered]@{
        schemaVersion = [int]$script:WinMintUiBridgeSchemaVersion
        type          = 'result'
    }
    if ($Result -is [System.Collections.IDictionary]) {
        foreach ($key in @($Result.Keys)) {
            if ($key -in @('schemaVersion', 'type')) { continue }
            $payload[[string]$key] = $Result[$key]
        }
    }
    else {
        foreach ($prop in @($Result.PSObject.Properties)) {
            if ($prop.Name -in @('schemaVersion', 'type')) { continue }
            $payload[[string]$prop.Name] = $prop.Value
        }
    }
    return ([pscustomobject]$payload | ConvertTo-Json -Compress -Depth 12)
}

function Write-WinMintUiBridgeResult {
    param(
        [Parameter(Mandatory)]$Result,
        [string]$ResultPath = ''
    )

    $json = ConvertTo-WinMintUiBridgeResultJson -Result $Result
    if ([string]::IsNullOrEmpty($ResultPath)) {
        Write-Output $json
    }
    else {
        Set-Content -LiteralPath $ResultPath -Value $json -Encoding UTF8
    }
}

function ConvertFrom-WinMintUiBridgeStdout {
    <#
    .SYNOPSIS
        Pure parse seam for the wizard bridge protocol (mirrors WizardBridge.ParseBridgeResult).
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Stdout)

    foreach ($line in @($Stdout -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Last 50)) {
        if (-not $line.StartsWith('{')) { continue }
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            continue
        }
        $schema = $null
        $type = $null
        if ($obj.PSObject.Properties['schemaVersion']) { $schema = $obj.schemaVersion }
        if ($obj.PSObject.Properties['type']) { $type = [string]$obj.type }
        if ($null -ne $schema -and [string]$type -eq 'result') {
            return $obj
        }
    }
    return $null
}
