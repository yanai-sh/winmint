#Requires -Version 7.6

# WinMint CLI verb layer. WinMint-CLI.ps1 is a thin dispatcher that routes the
# first positional token to one of these commands. Each verb owns a small,
# declared parameter surface for exactly one operation, replacing the former
# single 60-flag param block + runtime mode-sniffing. The profile is the source
# of truth: `new` authors one (all config flags live here); `build`/`validate`
# consume one with only run-specific overrides.

function Invoke-WinMintVerbFunction {
    <#
    .SYNOPSIS
    Forward the dispatcher's remaining command-line tokens to a verb function
    with native parameter binding. Array splatting alone passes everything
    positionally, so tokens are split into a positional array (array-splat) and a
    named hashtable (hashtable-splat); both bind correctly in one call. Values
    written as comma-arrays (e.g. -Install a,b) arrive as a single array element
    and are forwarded intact.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FunctionName,
        [object[]]$Tokens = @()
    )

    $positional = [System.Collections.Generic.List[object]]::new()
    $named = @{}
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $tok = $Tokens[$i]
        if ($tok -is [string] -and $tok -match '^-{1,2}(?<n>[A-Za-z][\w]*)(?::(?<v>.*))?$') {
            $name = $Matches['n']
            if ($Matches.ContainsKey('v')) {
                $named[$name] = $Matches['v']
            }
            elseif (($i + 1) -lt $Tokens.Count -and -not ($Tokens[$i + 1] -is [string] -and $Tokens[$i + 1] -match '^-{1,2}[A-Za-z]')) {
                $named[$name] = $Tokens[$i + 1]
                $i++
            }
            else {
                $named[$name] = $true
            }
        }
        else {
            $positional.Add($tok)
        }
    }

    $pos = $positional.ToArray()
    & $FunctionName @pos @named
}

function Resolve-WinMintCliElevation {
    <#
    .SYNOPSIS
    Ensure the current shell is elevated for a build/validate run. When not
    elevated, either self-elevate by relaunching the verbatim verb invocation
    (when -AllowElevate is set) or throw so the caller emits a failed result.
    Returns $true when already elevated; never returns when it self-elevates.
    #>
    [CmdletBinding()]
    param([switch]$AllowElevate)

    if (Test-WinMintAdministrator) { return $true }
    if (-not $AllowElevate) {
        throw 'WinMint build and validate require an elevated shell, including -DryRun. Re-run as Administrator or pass -AllowElevate for an explicit UAC prompt.'
    }
    $switches = @($script:WinMintInvocationArgs)
    if ('-AllowElevate' -notin $switches) { $switches += '-AllowElevate' }
    Invoke-SelfElevate -Switches $switches
    return $false
}

function Invoke-WinMintBuildCommand {
    <#
    .SYNOPSIS
    Build (or dry-run) a Windows image from a profile. The profile carries all
    configuration; only the source override, USB target, and run switches live
    on this verb.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][Alias('Profile')][string]$ProfilePath,
        [string]$SourceIso = '',
        [switch]$DryRun,
        [switch]$WriteUsb,
        [int]$Disk = -1,
        [int]$ConfirmDisk = -1,
        [switch]$AllowFixedUsbDisk,
        [ValidateSet('Max', 'Fast', 'None')][string]$Compression = 'Max',
        [switch]$FastImage,
        [switch]$Yes,
        [switch]$Json,
        [switch]$Quiet,
        [switch]$AllowElevate
    )

    if ($WriteUsb) {
        if ($DryRun) { throw '-WriteUsb cannot be combined with -DryRun.' }
        if ($Disk -lt 0) { throw '-WriteUsb requires -Disk <number>.' }
    } elseif ($Disk -ge 0 -or $ConfirmDisk -ge 0 -or $AllowFixedUsbDisk) {
        throw 'USB target flags (-Disk, -ConfirmDisk, -AllowFixedUsbDisk) require -WriteUsb.'
    }

    # -FastImage is the test-quality preset: no recompression + skip the WinSxS
    # component cleanup. It wins over -Compression so a single switch always
    # produces the fastest build. Otherwise honor the explicit compression.
    $imageCompression = if ($FastImage) { 'None' } else { $Compression }

    Invoke-WinMintProfileRun `
        -ProfilePath $ProfilePath `
        -SourceIsoOverride $SourceIso `
        -DryRun:$DryRun `
        -WriteUsb:$WriteUsb `
        -UsbDiskNumber $Disk `
        -ConfirmUsbDiskNumber $ConfirmDisk `
        -AllowFixedUsbDisk:$AllowFixedUsbDisk `
        -ImageCompression $imageCompression `
        -AllowElevate:$AllowElevate `
        -Yes:$Yes `
        -Json:$Json `
        -Quiet:$Quiet
}

function Invoke-WinMintValidateCommand {
    <#
    .SYNOPSIS
    Preflight-validate a profile without modifying any image.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][Alias('Profile')][string]$ProfilePath,
        [string]$SourceIso = '',
        [switch]$Json,
        [switch]$Quiet,
        [switch]$AllowElevate
    )
    Invoke-WinMintProfileRun `
        -ProfilePath $ProfilePath `
        -SourceIsoOverride $SourceIso `
        -ValidateOnly `
        -AllowElevate:$AllowElevate `
        -Json:$Json `
        -Quiet:$Quiet
}

function Invoke-WinMintNewProfileCommand {
    <#
    .SYNOPSIS
    Author a build profile from flags. This is the one place configuration flags
    live; the resulting profile is what `build` consumes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][Alias('Out')][string]$OutPath,
        [string]$SourceIso = '',
        [ValidateSet('amd64', 'arm64', 'x86')][string]$Architecture = '',
        [string]$ComputerName = 'WinMint',
        [string]$AccountName = 'dev',
        [ValidateSet('Local', 'MicrosoftOobe')][string]$AccountMode = 'Local',
        [string]$Password = '',
        [string]$PasswordPath = '',
        [string]$PasswordEnvVar = '',
        [switch]$AutoLogon,
        [switch]$AutoWipeDisk,
        # Host (default) | Home | Pro | Enterprise | Education | SingleLanguage |
        # All, or an exact edition name. The token drives the edition mode; there
        # is no separate -EditionMode.
        [string]$Edition = 'Host',
        # Inject a generic (non-activating) edition key so an unattended VM/CI
        # install skips the Setup product-key page. Auto injects only when the
        # build host has no firmware/OEM key. Only meaningful for a fixed edition.
        [ValidateSet('Auto', 'On', 'Off')][string]$GenericKey = 'Auto',
        [ValidateSet('None', 'Host', 'Custom', 'HostExport', 'CustomInfFolder', 'OemMsi', 'SurfaceMsiSafe', 'SurfaceCatalog')][string]$DriverSource = 'None',
        [string]$DriverPath = '',
        [string]$DriverPack = '',
        [ValidateSet('ThisPC', 'DifferentPC')][string]$TargetDevice = 'DifferentPC',
        [ValidateSet('Balanced', 'EnergySaver', 'HighPerformance', 'UltimatePerformance')][string]$PowerPlan = 'Balanced',
        [switch]$ExportHostDrivers,
        [string]$TimeZoneId = '',
        [string]$InputLocale = '',
        [string]$SystemLocale = '',
        [string]$UILanguage = '',
        [string]$UILanguageFallback = '',
        [string]$UserLocale = '',
        [switch]$KeepEdge,
        [switch]$KeepGaming,
        [switch]$KeepCopilot,
        [string[]]$Editor = @(),
        [string[]]$Browser = @(),
        [string[]]$Wsl2Distros = @(),
        [switch]$DesktopUI,
        # Window-manager tooling. Accepts a comma- or space-separated list so it
        # binds the same whether invoked interactively (-Install a,b splits into an
        # array) or via `pwsh -File` (which passes a,b as one literal token).
        [string[]]$Install = @(),
        [ValidateSet('None', 'Raycast')][string]$Launcher = 'None',
        [switch]$PhoneLink,
        [switch]$LiveInstallAudit,
        [ValidateSet('On', 'Off')][string]$Dma = 'On',
        [ValidateSet('On', 'Off')][string]$Location = 'On',
        [ValidateSet('None', 'Stable25H2')][string]$UpdateImage = 'None',
        [string]$UpdatePayloadRoot = '',
        [ValidateSet('On', 'Off')][string]$UpdateProvisionedApps = 'On',
        [switch]$Json,
        [switch]$Quiet
    )

    $secretInputs = @($Password, $PasswordPath, $PasswordEnvVar | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($secretInputs.Count -gt 1) {
        throw 'Use only one password input: -Password, -PasswordPath, or -PasswordEnvVar.'
    }
    if ($DriverPack -and ($DriverSource -ne 'None' -or $DriverPath -or $ExportHostDrivers)) {
        throw 'Use only one driver source style: -DriverPack or -DriverSource/-DriverPath/-ExportHostDrivers.'
    }

    $allowedTools = @('windhawk', 'yasb', 'thide', 'komorebi', 'nilesoft')
    $installTools = @($Install | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $badTools = @($installTools | Where-Object { $_ -notin $allowedTools })
    if ($badTools.Count -gt 0) {
        throw "Unknown -Install tool(s): $($badTools -join ', '). Valid values: $($allowedTools -join ', ')."
    }

    $secret = Resolve-WinMintHeadlessSecret -Password $Password -PasswordPath $PasswordPath -PasswordEnvVar $PasswordEnvVar
    $editionSelection = Resolve-WinMintEditionSelection -Edition $Edition -EditionSpecified $true
    # The generic key is baked into the profile here (target.productKey); the
    # build verb just consumes it. Auto detects the build host's firmware key.
    $injectGeneric = ($GenericKey -eq 'On') -or ($GenericKey -eq 'Auto' -and -not (Test-WinMintHostHasFirmwareKey))
    $productKey = ''
    if ($injectGeneric -and $editionSelection.Mode -eq 'Fixed') {
        $productKey = Get-WinMintGenericProductKey -EditionName $editionSelection.Name
    }

    $buildProfile = New-WinMintHeadlessProfileFromFlags `
        -SourceIso $SourceIso `
        -Architecture $Architecture `
        -ComputerName $ComputerName `
        -AccountName $AccountName `
        -AccountMode $AccountMode `
        -Password $secret.Password `
        -AutoLogon:$AutoLogon `
        -AutoWipeDisk:$AutoWipeDisk `
        -EditionMode $editionSelection.Mode `
        -Edition $editionSelection.Name `
        -ProductKey $productKey `
        -DriverSource $DriverSource `
        -DriverPath $DriverPath `
        -TargetDevice $TargetDevice `
        -PowerPlan $PowerPlan `
        -DriverPack $DriverPack `
        -ExportHostDrivers:$ExportHostDrivers `
        -TimeZoneId $TimeZoneId `
        -InputLocale $InputLocale `
        -SystemLocale $SystemLocale `
        -UILanguage $UILanguage `
        -UILanguageFallback $UILanguageFallback `
        -UserLocale $UserLocale `
        -KeepEdge:$KeepEdge `
        -KeepGaming:$KeepGaming `
        -KeepCopilot:$KeepCopilot `
        -Editor $Editor `
        -Browser $Browser `
        -Wsl2Distros $Wsl2Distros `
        -DesktopUI:$DesktopUI `
        -Install $installTools `
        -Launcher $Launcher `
        -LiveInstallAudit:$LiveInstallAudit `
        -PhoneLink:$PhoneLink `
        -Dma $Dma `
        -Location $Location `
        -UpdateImage $UpdateImage `
        -UpdatePayloadRoot $UpdatePayloadRoot `
        -UpdateProvisionedApps $UpdateProvisionedApps `
        -DryRun `
        -ValidateOnly `
        -TemplateMode

    $result = New-WinMintHeadlessProfileAuthoringResult -Path $OutPath -BuildProfile $buildProfile
    if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinMintHeadlessHumanResult -Result $result }
    return $result
}

function Invoke-WinMintListCommand {
    <#
    .SYNOPSIS
    List tracked build work directories and their state.
    #>
    [CmdletBinding()]
    param([switch]$Json, [switch]$Quiet)

    $work = @(Get-WinMintHeadlessWorkItem)
    $result = New-WinMintHeadlessResult -Result 'listed' -Reports ([pscustomobject]@{ work = $work })
    if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { $work | Format-Table buildId, phase, result, stale, workDir }
    return $result
}

function Invoke-WinMintCleanCommand {
    <#
    .SYNOPSIS
    Clean a tracked work directory by build id, or 'AllStale' for every stale one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, Mandatory)][string]$Target,
        [switch]$Json,
        [switch]$Quiet
    )

    $cleaned = @(Invoke-WinMintHeadlessCleanWork -Target $Target)
    $result = New-WinMintHeadlessResult -Result 'cleaned' -Reports ([pscustomobject]@{ cleaned = $cleaned })
    if ($Json) { Write-WinMintHeadlessJsonResult -Result $result } elseif (-not $Quiet) { Write-WinMintHeadlessHumanResult -Result $result }
    return $result
}

function Show-WinMintCliHelp {
    [CmdletBinding()]
    param()

    $text = @'
WinMint - subtractive Windows 11 image builder

Usage:
  WinMint-CLI.ps1 <command> [options]
  WinMint-CLI.ps1                       show help (use WinMint-GUI.ps1 for the wizard)

Commands:
  build <profile>     Build (or -DryRun) an image from a profile.
  new <out>           Author a build profile from flags.
  validate <profile>  Preflight-check a profile without touching any image.
  list                List tracked build work directories.
  clean <id|AllStale> Remove a tracked work directory.
  help                Show this help.

build options:
  -SourceIso <p>      Override the profile's source ISO for this run.
  -DryRun             Generate artifacts without servicing the image.
  -WriteUsb -Disk <n> Write the result to USB disk <n> (-ConfirmDisk, -AllowFixedUsbDisk).
  -Yes                Assume yes for prompts. -Json machine output. -Quiet no progress.
  -AllowElevate       Self-elevate with a UAC prompt when not already elevated.

new options (configuration lives here):
  -Edition Host|Home|Pro|Enterprise|Education|SingleLanguage|All|<exact name>
  -GenericKey Auto|On|Off          Bake a generic (non-activating) edition key.
  -KeepEdge -KeepGaming -KeepCopilot   Keep/restore intent for those domains.
  -DesktopUI                       Add the alternate desktop shell layer.
  -Install windhawk,yasb,thide,komorebi,nilesoft  Shell tooling to install.
  -Launcher None|Raycast
  -Dma On|Off                      DMA interop tweak (default On).
  -Location On|Off                 Location services (default On).
  -UpdateImage None|Stable25H2     Pre-service explicit stable 25H2 update payloads; Stable25H2 opts in.
  -UpdatePayloadRoot <dir>          Root containing packages\, appx\, and dependency payloads.
  -UpdateProvisionedApps On|Off     Include Store/MSIX app provisioning payloads.
  -Wsl2Distros Ubuntu,Fedora,archlinux,NixOS-WSL,pengwin
  -PowerPlan Balanced|EnergySaver|HighPerformance|UltimatePerformance
  -PhoneLink -LiveInstallAudit
  Identity/locale/driver flags: -ComputerName -AccountName -AccountMode
  -Password/-PasswordPath/-PasswordEnvVar -AutoLogon -AutoWipeDisk -Architecture
    (a Local account REQUIRES a password, or the install stops at the Windows 11
     OOBE "Create a password" page; use -AccountMode MicrosoftOobe for interactive
     account setup instead)
  -TimeZoneId -InputLocale -SystemLocale -UILanguage -UILanguageFallback -UserLocale
  -DriverSource None|Host|Custom|HostExport|CustomInfFolder|OemMsi|SurfaceMsiSafe|SurfaceCatalog
  -DriverPath -DriverPack -TargetDevice -ExportHostDrivers
'@
    Write-Host $text
}

