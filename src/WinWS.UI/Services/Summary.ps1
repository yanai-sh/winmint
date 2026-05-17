#Requires -Version 7.3

function New-WinWSUiSummaryItem {
    param(
        [AllowNull()][string]$Primary = '',
        [AllowNull()][string]$Secondary = '',
        [AllowNull()][string]$Meta = '',
        [string[]]$Badges = @(),
        [bool]$IsDanger = $false
    )

    [pscustomobject]@{
        Primary   = [string]$Primary
        Secondary = [string]$Secondary
        Meta      = [string]$Meta
        Badges    = @($Badges)
        IsDanger  = [bool]$IsDanger
    }
}

function Get-WinWSUiDisplayFileName {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return 'Not selected' }
    try {
        return [System.IO.Path]::GetFileName($Path)
    } catch {
        return [string]$Path
    }
}

function Get-WinWSUiDisplayParentPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    try {
        $parent = [System.IO.Path]::GetDirectoryName($Path)
        if ([string]::IsNullOrWhiteSpace($parent)) { return '' }
        if ($parent.Length -le 52) { return $parent }
        return '{0}...{1}' -f $parent.Substring(0, 24), $parent.Substring($parent.Length - 24)
    } catch {
        return ''
    }
}

function Join-WinWSUiDisplayList {
    param(
        [object[]]$Items,
        [string]$Fallback = 'None'
    )

    $values = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($values.Count -eq 0) { return $Fallback }
    return ($values | ForEach-Object { [string]$_ }) -join ', '
}

function ConvertTo-WinWSUiLayerName {
    param([string]$Layer)

    switch ([string]$Layer) {
        'windhawk' { 'Windhawk' }
        'yasb' { 'YASB' }
        'komorebi' { 'Komorebi' }
        'standard' { 'Standard Windows' }
        default { [string]$Layer }
    }
}

function ConvertTo-WinWSUiEditorName {
    param([string]$Editor)

    switch ([string]$Editor) {
        'cursor' { 'Cursor' }
        'vscodium' { 'VSCodium' }
        'neovim' { 'Neovim' }
        'zed' { 'Zed' }
        default { [string]$Editor }
    }
}

function Get-WinWSUiSourceSummary {
    param([Parameter(Mandatory)][object]$State)

    $arch = [string]$State.Iso.Architecture
    if ([string]::IsNullOrWhiteSpace($arch)) { $arch = 'architecture pending' }
    $editionCount = @($State.Iso.Editions).Count
    $meta = $editionCount -gt 0 ? "$editionCount editions available" : 'Editions pending'

    New-WinWSUiSummaryItem `
        -Primary ('Windows 11 ISO - {0}' -f $arch) `
        -Secondary (Get-WinWSUiDisplayFileName -Path $State.Iso.Path) `
        -Meta $meta
}

function Get-WinWSUiMachineSummary {
    param([Parameter(Mandatory)][object]$State)

    $target = [string]$State.Machine.TargetDevice -eq 'ThisPC' ? 'This PC' : 'Another PC'
    $edition = [string]$State.Machine.EditionMode -eq 'Fixed' ?
        [string]$State.Machine.Edition :
        'ISO default edition'
    $driverSource = switch ([string]$State.Drivers.Source) {
        'Host' { 'Export drivers from this PC' }
        'Custom' { Get-WinWSUiDisplayFileName -Path $State.Drivers.Path }
        default { 'Windows inbox drivers' }
    }
    $badges = [System.Collections.Generic.List[string]]::new()
    if ([string]$State.Drivers.Source -eq 'Custom') { $badges.Add('Custom drivers') }
    if ([string]$State.Drivers.Source -eq 'Host') { $badges.Add('Host drivers') }
    if ([bool]$State.Machine.HardwareBypass) { $badges.Add('Hardware bypass') }

    New-WinWSUiSummaryItem `
        -Primary $target `
        -Secondary ('{0}; {1}' -f $edition, $driverSource) `
        -Badges $badges.ToArray()
}

function Get-WinWSUiDiskSummary {
    param([Parameter(Mandatory)][object]$State)

    if ([string]$State.Disk.Mode -eq 'AutoWipeDisk0') {
        return New-WinWSUiSummaryItem `
            -Primary 'Erase disk 0 during Windows Setup' `
            -Secondary 'Existing partitions on disk 0 will be deleted.' `
            -Badges @('Armed') `
            -IsDanger $true
    }

    New-WinWSUiSummaryItem `
        -Primary 'Manual disk selection in Windows Setup' `
        -Secondary 'Windows Setup will ask where to install.'
}

function Get-WinWSUiIdentitySummary {
    param([Parameter(Mandatory)][object]$State)

    $computerName = [string]$State.Identity.ComputerName
    $accountName = [string]$State.Identity.AccountName
    if ([string]::IsNullOrWhiteSpace($computerName)) { $computerName = 'Computer name pending' }
    if ([string]::IsNullOrWhiteSpace($accountName)) { $accountName = 'Account pending' }

    $passwordSet = -not [string]::IsNullOrWhiteSpace([string]$State.Identity.Password)
    $secondary = $passwordSet ? 'Password-protected local admin' : 'Passwordless local admin'

    New-WinWSUiSummaryItem `
        -Primary ('{0} / {1}' -f $computerName, $accountName) `
        -Secondary $secondary `
        -Badges @($passwordSet ? 'Password set' : 'Passwordless')
}

function Get-WinWSUiWorkstationSummary {
    param([Parameter(Mandatory)][object]$State)

    $groups = @($State.ProfileGroups | Where-Object { [string]$_ -ne 'Minimal' })
    $groupNames = if ($groups.Count -eq 0) { 'Minimal' } else { $groups -join ', ' }
    $layers = @($State.Desktop.Layers |
        Where-Object { [string]$_ -ne 'standard' } |
        ForEach-Object { ConvertTo-WinWSUiLayerName -Layer ([string]$_) })
    $editors = @($State.Development.Editors |
        ForEach-Object { ConvertTo-WinWSUiEditorName -Editor ([string]$_) })
    $distros = @($State.Development.WslDistros)

    $primary = Join-WinWSUiDisplayList -Items $layers -Fallback 'Standard Windows'
    $tools = Join-WinWSUiDisplayList -Items $editors -Fallback 'No editors'
    $linux = Join-WinWSUiDisplayList -Items $distros -Fallback 'No WSL'

    New-WinWSUiSummaryItem `
        -Primary $primary `
        -Secondary ('{0} + {1}' -f $tools, $linux) `
        -Meta ('Profile groups: {0}' -f $groupNames)
}

function Get-WinWSUiOutputSummary {
    param([Parameter(Mandatory)][object]$State)

    $computerName = [string]$State.Identity.ComputerName
    $safeName = if ([string]::IsNullOrWhiteSpace($computerName)) { 'Custom' } else { $computerName }
    $fileName = 'WinWS-Slim-{0}.iso' -f $safeName
    $outputPath = [string]$State.Build.OutputPath
    if ([string]::IsNullOrWhiteSpace($outputPath)) {
        $outputPath = Join-Path (Join-Path $State.RepositoryRoot 'output') $fileName
    }

    New-WinWSUiSummaryItem `
        -Primary $fileName `
        -Secondary $outputPath
}

function Get-WinWSUiLaunchContractSummary {
    param([Parameter(Mandatory)][object]$State)

    [pscustomobject]@{
        Source      = Get-WinWSUiSourceSummary -State $State
        Target      = Get-WinWSUiMachineSummary -State $State
        Disk        = Get-WinWSUiDiskSummary -State $State
        Identity    = Get-WinWSUiIdentitySummary -State $State
        Workstation = Get-WinWSUiWorkstationSummary -State $State
        Output      = Get-WinWSUiOutputSummary -State $State
    }
}
