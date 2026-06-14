#Requires -Version 7.3

function Get-RemovableUsbVolumeCandidate {
    <# <summary>Volumes Windows reports as Removable with an assigned drive letter (typical USB flash drives).</summary> #>
    return @(
        Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } |
            Sort-Object DriveLetter |
            ForEach-Object {
                $dl = $_.DriveLetter
                $freeGb = [math]::Round($_.SizeRemaining / 1GB, 1)
                $sizeGb = [math]::Round($_.Size / 1GB, 1)
                [pscustomobject]@{
                    DriveLetter = [string]$dl
                    SizeGb      = $sizeGb
                    FreeGb      = $freeGb
                    Label       = "[bold]${dl}:[/]  Removable USB  ·  [cyan]$sizeGb GB[/] total  ·  [green]$freeGb GB[/] free"
                }
            }
    )
}

function Show-BuildConfigurationSummaryAndConfirm {
    <# <summary>Rich summary, optional USB-after-build choice, then confirm to start the build or dry-run validation.</summary> #>
    param(
        [Parameter(Mandatory)][string]$SourceIsoPath,
        [Parameter(Mandatory)][string]$TargetArchitecture,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][bool]$AccountPasswordProvided,
        [Parameter(Mandatory)][bool]$AutoLogon,
        [Parameter(Mandatory)][string]$EditionName,
        [Parameter(Mandatory)][bool]$AutoWipeDisk,
        [Parameter(Mandatory)][bool]$MirrorHostRegional,
        [Parameter(Mandatory)][string]$TimeZoneId,
        [Parameter(Mandatory)][string]$InputLocale,
        [Parameter(Mandatory)][string]$UILanguage,
        [Parameter(Mandatory)][string]$UserLocale,
        [ValidateSet('Windows11Modern')][string]$CursorPackKind = 'Windows11Modern',
        [string]$DriverMode = 'None',
        [string]$DriverPath = '',
        [switch]$InstallWindhawk,
        [switch]$InstallYasb,
        [switch]$InstallKomorebi,
        [switch]$InstallNilesoft,
        [string[]]$Wsl2Distros = @(),
        [switch]$DryRun
    )

    Write-SectionHeader 'Configuration review' -DimLine 'Read the table carefully before you confirm — especially disk scope and USB options.'

    $passDisplay = if (-not $AccountPasswordProvided) { '[silver](not set)[/]' } else { '[silver]********[/] [dim](hidden)[/]' }
    $regionalLine = if ($MirrorHostRegional) {
        '[green]Same as this PC[/] [dim](time zone, locales, keyboard)[/]'
    }
    else {
        '[yellow]Custom (gold image)[/]'
    }
    $diskModeValue = if (-not $AutoWipeDisk) {
        '[green]Manual — Setup disk UI (autounattend does not clear disks)[/]'
    }
    else {
        '[bold red]Unattended[/] [dim]— primary disk: one Windows volume for the whole disk[/]'
    }
    $diskExtra = Get-Win11IsoDiskLayoutExtraMarkup -AutoWipeDisk:$AutoWipeDisk
    $cursorRow = '[cyan]Windows 11 Modern[/] [dim](bundled WinMint default)[/]'
    $driverRow = switch ($DriverMode) {
        'Host'   { '[cyan]Mirror this PC[/] [dim](Export-WindowsDriver)[/]' }
        'Custom' { "[cyan]Custom path[/] [dim]$DriverPath[/]" }
        default  { '[silver]None[/]' }
    }
    $desktopLayers = [System.Collections.Generic.List[string]]::new()
    if ($InstallWindhawk) { $desktopLayers.Add('Windhawk') | Out-Null }
    if ($InstallYasb) { $desktopLayers.Add('YASB') | Out-Null }
    if ($InstallKomorebi) { $desktopLayers.Add('Komorebi') | Out-Null }
    if ($InstallNilesoft) { $desktopLayers.Add('Nilesoft') | Out-Null }
    $desktopRow = if ($desktopLayers.Count) {
        "[green]$($desktopLayers -join ', ')[/]"
    }
    else {
        '[silver]Standard Windows[/]'
    }
    $wslRow = if (@($Wsl2Distros).Count) {
        "[green]$(@($Wsl2Distros) -join ', ')[/]"
    }
    else {
        '[silver]None[/]'
    }

    $tree = [Spectre.Console.Tree]::new('[bold white]Build profile[/]')

    $srcNode = $tree.AddNode('[bold cyan3]Source media[/]')
    $srcNode.AddNode("ISO [dim]·[/] [cyan]$($SourceIsoPath)[/]") | Out-Null
    $srcNode.AddNode("Architecture [dim]·[/] [cyan]$TargetArchitecture[/] [dim](file name / install.wim)[/]") | Out-Null

    $idNode = $tree.AddNode('[bold cyan3]Account & identity[/]')
    $idNode.AddNode("Computer [dim]·[/] [green]$ComputerName[/]") | Out-Null
    $idNode.AddNode("User [dim]·[/] [green]$UserName[/]") | Out-Null
    $idNode.AddNode("Password [dim]·[/] $passDisplay") | Out-Null
    $idNode.AddNode("Autologon [dim]·[/] $(if ($AutoLogon) { '[green]Yes[/]' } else { '[silver]No[/]' })") | Out-Null

    $edNode = $tree.AddNode('[bold cyan3]Edition & regional[/]')
    $edNode.AddNode("Edition [dim]·[/] [green]$EditionName[/]") | Out-Null
    $edNode.AddNode("Regional [dim]·[/] $regionalLine") | Out-Null
    $edNode.AddNode("Time zone [dim]·[/] [cyan]$TimeZoneId[/]") | Out-Null
    $edNode.AddNode("UI language [dim]·[/] [cyan]$UILanguage[/]") | Out-Null
    $edNode.AddNode("User locale [dim]·[/] [cyan]$UserLocale[/]") | Out-Null
    $edNode.AddNode("Input locale [dim]·[/] [cyan]$InputLocale[/]") | Out-Null
    $edNode.AddNode("Cursor [dim]·[/] $cursorRow") | Out-Null

    $deskNode = $tree.AddNode('[bold cyan3]Desktop[/]')
    $deskNode.AddNode("Layers [dim]·[/] $desktopRow") | Out-Null
    $deskNode.AddNode("WSL distros [dim]·[/] $wslRow") | Out-Null
    $deskNode.AddNode("Drivers [dim]·[/] $driverRow") | Out-Null

    $diskNode = $tree.AddNode('[bold cyan3]Target disk[/]')
    $diskNode.AddNode("Mode [dim]·[/] $diskModeValue") | Out-Null
    if ($AutoWipeDisk -and -not [string]::IsNullOrWhiteSpace($diskExtra)) {
        $diskNode.AddNode("Notes [dim]·[/] $diskExtra") | Out-Null
    }

    Write-SpectreSpacing
    [Spectre.Console.AnsiConsole]::Write($tree)
    Write-SpectreSpacing

    if ($AutoWipeDisk) {
        Write-SpectreSpacing
        $diskWarnRenderable = @(
            '[red]Unattended Setup will remove every partition on the [bold]primary disk[/] [red]and recreate EFI, MSR, and a Windows volume. All data on that disk is destroyed.[/]'
            '[silver]Dual-boot templates leave trailing space[/] [green]unallocated[/] [silver]for another OS; nominal 1 TB / 2 TB sizes are baked in — edit[/] [cyan]autounattend.xml[/] [silver]if your disk differs.[/]'
            '[darkorange]Boot this installer only on hardware you intend to erase, or switch to manual disk mode in autounattend before broad deployment.[/]'
        ) | Format-SpectreRows
        $null = Format-SpectrePanel -Data $diskWarnRenderable -Header '[bold red]WARNING — Target disk[/]' -Border Rounded -Color Red -Expand | Out-SpectreHost | Out-Host
        $diskAckBody = @(
            '[red]The ISO you are building includes[/] [bold]autounattend[/] [red]disk steps that run during Setup without another prompt.[/]'
            '[silver]Typing YES means you accept total data loss on that disk if this media boots on the wrong machine.[/]'
        ) | Format-SpectreRows
        if (-not (Confirm-Win11IsoTypedDestructiveAcknowledgment -PanelHeader '[bold red]Typed confirmation — primary disk[/]' -PanelBodyMarkup $diskAckBody -RequiredPhrase 'YES')) {
            return [pscustomobject]@{ Proceed = $false; PostBuildUsbDriveLetter = $null }
        }
    }

    $postUsbLetter = $null
    $usbList = @(
        Get-WinMintUsbDiskCandidate |
            Where-Object { -not $_.IsBoot -and -not $_.IsSystem -and $_.BusType -in @('USB', 'SD', 'MMC') }
    )
    if ($DryRun) {
        Write-SectionHeader 'USB (dry-run detection)'
        if ($usbList.Count -ge 1) {
            $usbLines = ($usbList | ForEach-Object { "Disk $($_.DiskNumber): $($_.FriendlyName) · $($_.SizeGB) GB · $($_.BusType)" }) -join "`n"
            $usbPanel = @(
                "[green]USB candidate disk(s) on this PC:[/] [dim]($($usbList.Count))[/]"
                $usbLines
                '[dim]Dry run does not prepare USB media.'
                'Use -WriteUsb -UsbDiskNumber N -ConfirmUsbDiskNumber N for post-build USB writing.[/]'
            ) -join "`n"
            $null = Format-SpectrePanel -Data $usbPanel -Header '[bold grey]Detected[/]' -Border Rounded -Color Grey -Expand | Out-SpectreHost | Out-Host
        }
        else {
            $usbMissing = @(
                '[yellow]No removable USB disk candidates detected[/]'
                '[dim]Windows reported no non-system USB/SD/MMC disk candidate.'
                'A full build can still produce an ISO only; use tools\media\New-WinMintUsbInstaller.ps1 -ListUsbDisks to inspect targets.[/]'
            ) -join ' '
            $null = Format-SpectrePanel -Data $usbMissing `
                -Header '[bold grey]USB[/]' -Border Rounded -Color Grey -Expand | Out-SpectreHost | Out-Host
        }
    }

    Write-SpectreSpacing
    # Read-SpectreConfirm may emit host renderables before the final boolean; capture only booleans from the output stream.
    $confirmMsg = if ($DryRun) {
        '[bold]Start dry-run verification with these settings?[/] [grey](Staged ISO, WIM metadata, boot files, prerequisites; no WIM customization or output ISO.)[/]'
    }
    else {
        '[bold]Start the unattended build with these settings?[/] [grey](Expect a long run.)[/]'
    }
    $confirmOk = if ($DryRun) { '[green]Starting dry run…[/]' } else { '[green]Starting build…[/]' }
    $confirmFail = if ($DryRun) { '[yellow]Dry run cancelled.[/]' } else { '[yellow]Build cancelled.[/]' }
    $confirmStream = @(Read-SpectreConfirm -Message $confirmMsg -DefaultAnswer y `
            -ConfirmSuccess $confirmOk `
            -ConfirmFailure $confirmFail)
    $boolResults = @($confirmStream | Where-Object { $_ -is [bool] })
    $go = if ($boolResults.Count -ge 1) { [bool]$boolResults[-1] } else { $false }
    return [pscustomobject]@{ Proceed = $go; PostBuildUsbDriveLetter = $postUsbLetter }
}
