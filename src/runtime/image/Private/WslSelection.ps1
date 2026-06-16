#Requires -Version 7.3

function ConvertTo-WinMintWslSelectionToken {
    param([AllowNull()][string]$Value)

    $token = ([string]$Value).Trim()
    switch -Regex ($token) {
        '^(Ubuntu|Ubuntu-\d+\.\d+)$' { return 'Ubuntu' }
        '^(Fedora|FedoraLinux|FedoraLinux-\d+)$' { return 'FedoraLinux' }
        '^(Arch(?: Linux)?|archlinux)$' { return 'archlinux' }
        '^(NixOS-WSL|NixOS|nixos-wsl)$' { return 'NixOS-WSL' }
        '^(Pengwin|pengwin)$' { return 'pengwin' }
        default { return $token }
    }
}

function ConvertTo-WinMintWslAgentToken {
    param([AllowNull()][string]$ProfileToken)

    switch ([string]$ProfileToken) {
        'NixOS-WSL' { return 'NixOS' }
        default { return [string]$ProfileToken }
    }
}

function Get-WinMintWslSelectionDisplayName {
    param([AllowNull()][string]$ProfileToken)

    switch ([string]$ProfileToken) {
        'Ubuntu' { return 'Ubuntu' }
        'FedoraLinux' { return 'Fedora' }
        'archlinux' { return 'Arch Linux' }
        'NixOS-WSL' { return 'NixOS' }
        'pengwin' { return 'Pengwin' }
        default { return [string]$ProfileToken }
    }
}

function New-WinMintWslSelectionItem {
    param([Parameter(Mandatory)][string]$Token)

    $profileToken = ConvertTo-WinMintWslSelectionToken -Value $Token
    $agentToken = ConvertTo-WinMintWslAgentToken -ProfileToken $profileToken

    [ordered]@{
        inputToken = $Token
        profileToken = $profileToken
        agentToken = $agentToken
        displayName = Get-WinMintWslSelectionDisplayName -ProfileToken $profileToken
        packageIdentity = $profileToken
        installIdentity = $agentToken
    }
}

function ConvertTo-WinMintWslSelection {
    [CmdletBinding()]
    param(
        [AllowNull()][object[]]$Values = @(),
        [AllowNull()][object[]]$FallbackValues = @()
    )

    $sourceValues = @($Values)
    if ($sourceValues.Count -eq 0) {
        $sourceValues = @($FallbackValues)
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $sourceValues) {
        foreach ($part in (([string]$value) -split ',')) {
            $token = ([string]$part).Trim()
            if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'None') { continue }

            $item = New-WinMintWslSelectionItem -Token $token
            if ($seen.Add([string]$item.profileToken)) {
                $items.Add($item) | Out-Null
            }
        }
    }

    $profileTokens = @($items | ForEach-Object { [string]$_.profileToken })
    $agentTokens = @($items | ForEach-Object { [string]$_.agentToken })
    [pscustomobject]@{
        Items = $items.ToArray()
        ProfileTokens = $profileTokens
        AgentTokens = $agentTokens
        ProfileToken = if ($profileTokens.Count -eq 0) { 'None' } elseif ($profileTokens.Count -eq 1) { $profileTokens[0] } else { $profileTokens -join ',' }
        AgentToken = if ($agentTokens.Count -eq 0) { 'None' } elseif ($agentTokens.Count -eq 1) { $agentTokens[0] } else { $agentTokens -join ',' }
        DisplayNames = @($items | ForEach-Object { [string]$_.displayName })
        PackageIdentities = @($items | ForEach-Object { [string]$_.packageIdentity })
        InstallIdentities = @($items | ForEach-Object { [string]$_.installIdentity })
    }
}
