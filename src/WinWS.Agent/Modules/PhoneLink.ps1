#Requires -Version 7.3

function Set-WinWSRegistryDword {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -Path $Path -Force
    }
    $null = New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force
}

function Invoke-WinWSAgentPhoneLinkBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AgentProfile,
        [Parameter(Mandatory)][hashtable]$State
    )

    $config = Get-AgentModuleConfig -Name 'phoneLink'
    if (-not $config) {
        return [pscustomobject]@{
            Id = 'phoneLink'
            Status = 'skipped'
            Message = 'Phone Link module is not present in the agent profile.'
        }
    }

    $result = [ordered]@{
        Id = 'phoneLink'
        Status = 'ok'
        HiddenCrossDeviceFolder = $false
        ClipboardPrepared = $false
        ShowInFileExplorerPrepared = [bool]$config.showInFileExplorer
        Message = 'Phone Link preserved; user-paired devices remain controlled by Windows Settings and Phone Link.'
    }

    if ($config.PSObject.Properties['crossDeviceCopyPaste'] -and [bool]$config.crossDeviceCopyPaste) {
        Set-WinWSRegistryDword -Path 'HKCU:\Software\Microsoft\Clipboard' -Name 'EnableClipboardHistory' -Value 1
        Set-WinWSRegistryDword -Path 'HKCU:\Software\Microsoft\Clipboard' -Name 'CloudClipboardAutomaticUpload' -Value 1
        $result.ClipboardPrepared = $true
    }

    if ($config.PSObject.Properties['hideCrossDeviceHomeFolder'] -and [bool]$config.hideCrossDeviceHomeFolder) {
        $crossDevicePath = Join-Path $env:USERPROFILE 'CrossDevice'
        if (-not (Test-Path -LiteralPath $crossDevicePath)) {
            $null = New-Item -ItemType Directory -Path $crossDevicePath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $crossDevicePath) {
            $item = Get-Item -LiteralPath $crossDevicePath -Force
            $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
            $result.HiddenCrossDeviceFolder = $true
        }
    }

    return [pscustomobject]$result
}
