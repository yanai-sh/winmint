#Requires -Version 7.6

function Get-WinMintOptionCatalog {
    [ordered]@{
        UiArchitecture = @('arm64', 'amd64', 'x86', 'Unknown')
        ProfileArchitecture = @('amd64', 'arm64', 'x86', '')
        AccountMode = @('Local', 'MicrosoftOobe')
        TargetDevice = @('ThisPC', 'DifferentPC')
        FormFactor = @('Auto', 'Laptop', 'Desktop')
        PowerPlan = @('Balanced', 'EnergySaver', 'HighPerformance', 'UltimatePerformance')
        Edition = @('Host', 'Home', 'Pro', 'Enterprise', 'Education', 'SingleLanguage', 'All')
        EditionMode = @('TargetLicense', 'Fixed')
        DriverSource = @('None', 'Host', 'Custom', 'HostExport', 'CustomInfFolder', 'OemMsi', 'SurfaceMsiSafe', 'SurfaceCatalog')
        DiskMode = @('Manual', 'AutoWipeDisk0', 'DualBootReserved')
        DiskLayoutPreset = @('', 'WindowsHeavy', 'Balanced', 'EvenSplit', 'LinuxHeavy')
        DesktopCursorPack = @('Windows11Modern')
        DesktopLayer = @('standard', 'windhawk', 'yasb', 'thide', 'komorebi', 'nilesoft')
        Editor = @('cursor', 'vscode', 'zed', 'antigravity', 'neovim')
        Browser = @('zen-browser', 'helium', 'firefox-developer-edition', 'brave', 'edge')
        WslDistro = @('Ubuntu', 'FedoraLinux', 'archlinux', 'NixOS-WSL', 'pengwin')
        Launcher = @('None', 'Raycast')
        UpdateMode = @('None', 'Stable25H2')
        UpdateTargetFeatureVersion = @('25H2')
        UpdateReleaseCadence = @('BRelease')
        AiPolicy = @('Core', 'ServiceableFull', 'AggressiveExperimental')
    }
}

function Test-WinMintDriverSourceUsesHostExport {
    param([string]$Source)

    $Source -in @('Host', 'HostExport')
}

function Test-WinMintDriverSourceUsesPath {
    param([string]$Source)

    $Source -in @('Custom', 'CustomInfFolder', 'OemMsi', 'SurfaceMsiSafe', 'SurfaceCatalog')
}

function Test-WinMintDriverSourceRequiresMsi {
    param([string]$Source)

    $Source -in @('OemMsi', 'SurfaceMsiSafe')
}

function Test-WinMintDriverSourceUsesSurfaceCatalog {
    param([string]$Source)

    $Source -eq 'SurfaceCatalog'
}

function Get-WinMintOptionValues {
    param([Parameter(Mandatory)][string]$Name)

    $catalog = Get-WinMintOptionCatalog
    if (-not $catalog.Contains($Name)) {
        throw "Unknown WinMint option catalog '$Name'."
    }
    @($catalog[$Name])
}

