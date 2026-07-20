# Shared Setup action catalog for machine-phase execution and audit generation.

function Get-WinMintSetupActionCatalog {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{
            Id = 'time-sync'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\SystemHygiene.ps1'
            FunctionName = 'Invoke-ScTimeSync'
            Title = 'Synchronize system time before machine-phase cleanup'
            Kind = 'setup-action'
            Default = $true
            Requires = @('network')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Attempt secure time synchronization before setup cleanup continues')
            Artifacts = @('SetupComplete.log')
            Reversible = $false
        }
        [pscustomobject]@{
            Id = 'desktop-shortcut-cleanup'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\SystemHygiene.ps1'
            FunctionName = 'Invoke-ScDesktopShortcutCleanup'
            Title = 'Remove installer-created desktop shortcuts'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Remove unwanted public desktop shortcuts left by machine-phase installers')
            Artifacts = @('SetupComplete.log')
            Reversible = $false
        }
        [pscustomobject]@{
            Id = 'first-logon-runonce'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete.ps1'
            FunctionName = ''
            Title = 'Register PowerShell 7 RunOnce handoff for FirstLogon'
            Kind = 'setup-action'
            Default = $true
            Requires = @('WinMintAgent', 'PowerShell7')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Register FirstLogon.ps1 under pwsh.exe via HKLM RunOnce as a machine-phase fallback')
            Artifacts = @('SetupComplete.log')
            Reversible = $true
        }
        # Must run before other SetupComplete work. OOBE leaves
        # DefaultUserName=defaultuser0; FirstLogonAnim "Just a moment" hangs until
        # Winlogon is restamped to the profile Local account.
        [pscustomobject]@{
            Id = 'autologon-stamp'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\AutoLogon.ps1'
            FunctionName = 'Invoke-ScAutoLogonStamp'
            Title = 'Stamp Winlogon Autologon for the profile local account'
            Kind = 'setup-action'
            Default = $true
            Requires = @('account.autoLogon')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @(
                'Replace OOBE defaultuser0 Winlogon Autologon with the Local profile account',
                'Clear AutoLogonCount so FirstLogon can persist Autologon across agent reboots'
            )
            Artifacts = @('SetupComplete_AutoLogon.json')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'hyperv-guest-basic-console'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\HyperVGuestConsole.ps1'
            FunctionName = 'Invoke-ScHyperVGuestBasicConsole'
            Title = 'Disable Hyper-V Enhanced Session console connections'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @('diagnostics.vmGuestBasicConsole=false')
            UserControlled = $false
            Changes = @('Set guest DisableEnhancedSessionConsoleConnection so VMConnect never prompts for a password')
            Artifacts = @('SetupComplete.log')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'oobe-rehydration-suppression'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\OobeRehydration.ps1'
            FunctionName = 'Invoke-ScOobeRehydrationSuppression'
            Title = 'Block OOBE app rehydration jobs'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Disable setup-driven app rehydration tasks that reinstall removed inbox apps')
            Artifacts = @('SetupComplete_OobeRehydration.json')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'windows-update-restore'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\WindowsUpdate.ps1'
            FunctionName = 'Invoke-ScWindowsUpdateRestore'
            Title = 'Restore Windows Update and servicing infrastructure'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @('setupComplete.preserveWindowsUpdate=false')
            UserControlled = $false
            Changes = @(
                'Remove update-blocking registry policy overrides',
                'Restore BITS, wuauserv, UsoSvc, and WaaSMedicSvc startup configuration'
            )
            Artifacts = @('SetupComplete.log')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'appx-cleanup'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\AppxCleanup.ps1'
            FunctionName = 'Invoke-ScAppxRemoval'
            Title = 'Enforce live-image AppX cleanup'
            Kind = 'setup-action'
            Default = $true
            Requires = @('appxRemovalPrefixes')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Remove targeted inbox AppX packages from the installed image')
            Artifacts = @('SetupComplete_AppxCleanup.json')
            Reversible = $false
        }
        [pscustomobject]@{
            Id = 'ai-cleanup'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\AiCleanup.ps1'
            FunctionName = 'Invoke-ScAiServiceableCleanup'
            Title = 'Apply serviceable AI cleanup to the installed system'
            Kind = 'setup-action'
            Default = $true
            Requires = @('aiRemoval.policy')
            SuppressedBy = @('KeepCopilot')
            UserControlled = $true
            Changes = @(
                'Disable selected AI services and scheduled tasks',
                'Remove serviceable AI capabilities that remain after offline servicing'
            )
            Artifacts = @('SetupComplete_AiCleanup.json')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'telemetry-task-hardening'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\TelemetryTasks.ps1'
            FunctionName = 'Invoke-ScTelemetryTaskHardening'
            Title = 'Disable targeted telemetry scheduled tasks'
            Kind = 'setup-action'
            Default = $true
            Requires = @('privacy.disableTelemetryTasks')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Disable selected telemetry-related scheduled tasks')
            Artifacts = @('SetupComplete_TelemetryTasks.json')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'power-profile'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\Power.ps1'
            FunctionName = 'Invoke-ScPowerProfile'
            Title = 'Activate the selected power profile'
            Kind = 'setup-action'
            Default = $true
            Requires = @('power.selectedPlan')
            SuppressedBy = @()
            UserControlled = $true
            Changes = @(
                'Activate the selected power plan',
                'Disable desktop hibernation only when desktop form factor rules allow it'
            )
            Artifacts = @('SetupComplete_Power.json')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'bitlocker-note'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\SystemHygiene.ps1'
            FunctionName = 'Invoke-ScBitLockerNote'
            Title = 'Record BitLocker/device-encryption posture'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Write diagnostic note about BitLocker posture for post-install review')
            Artifacts = @('SetupComplete.log')
            Reversible = $false
        }
        [pscustomobject]@{
            Id = 'boot-timeout'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\SystemHygiene.ps1'
            FunctionName = 'Invoke-ScBootTimeout'
            Title = 'Normalize boot manager timeout'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Set a predictable boot manager timeout for supported boot flows')
            Artifacts = @('SetupComplete.log')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'toolchain-install'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\Toolchain.ps1'
            FunctionName = 'Invoke-ScToolchainInstall'
            Title = 'Confirm inbox Windows Terminal (no SetupComplete winget)'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @(
                'Record whether Windows Terminal is present on the image',
                'Do not winget-install or upgrade Terminal during SetupComplete (inbox on Windows 11 25H2+)'
            )
            Artifacts = @('SetupComplete.log')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'activation-check'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\SystemHygiene.ps1'
            FunctionName = 'Invoke-ScActivationCheck'
            Title = 'Probe Windows activation status'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Record activation diagnostic state after setup')
            Artifacts = @('SetupComplete.log')
            Reversible = $false
        }
        [pscustomobject]@{
            Id = 'npu-detection'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\SystemHygiene.ps1'
            FunctionName = 'Invoke-ScNpuDetection'
            Title = 'Detect NPU hardware for diagnostic reporting'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Record NPU presence for installation diagnostics')
            Artifacts = @('SetupComplete.log')
            Reversible = $false
        }
        [pscustomobject]@{
            Id = 'svchost-split'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\SvcHost.ps1'
            FunctionName = 'Invoke-ScSvcHostSplit'
            Title = 'Set SvcHost split threshold for clearer process accounting'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Adjust SvcHost split threshold so Task Manager reports per-service resource use more clearly')
            Artifacts = @('SetupComplete.log')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'onedrive-removal'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\OneDrive.ps1'
            FunctionName = 'Invoke-ScOneDriveRemoval'
            Title = 'Remove OneDrive integration during machine phase'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @('Uninstall and clean machine-scoped OneDrive integration before first user logon')
            Artifacts = @('SetupComplete.log')
            Reversible = $true
        }
        # Catch OOBE/other mid-SetupComplete Winlogon rewrites to defaultuser0 after long work.
        [pscustomobject]@{
            Id = 'autologon-stamp-final'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete\AutoLogon.ps1'
            FunctionName = 'Invoke-ScAutoLogonStampFinal'
            Title = 'Final Winlogon Autologon restamp before secret cleanup'
            Kind = 'setup-action'
            Default = $true
            Requires = @('account.autoLogon')
            SuppressedBy = @()
            UserControlled = $false
            Changes = @(
                'Re-stamp Local profile Autologon after toolchain and other machine-phase work',
                'Prevent defaultuser0 from returning before first interactive logon'
            )
            Artifacts = @('SetupComplete_AutoLogon.json', 'SetupComplete_AutoLogon.final.json')
            Reversible = $true
        }
        [pscustomobject]@{
            Id = 'inline-secret-cleanup'
            Phase = 'setupComplete'
            RelativePath = 'SetupComplete.ps1'
            FunctionName = ''
            Title = 'Remove staged unattend and Wi-Fi secrets inline'
            Kind = 'setup-action'
            Default = $true
            Requires = @()
            SuppressedBy = @()
            UserControlled = $false
            Changes = @(
                'Delete Panther unattend XML copies that contain the staged AutoLogon password',
                'Delete staged Wi-Fi payload artifacts after setup'
            )
            Artifacts = @('SetupComplete_errors.log', 'SetupComplete_warnings.log')
            Reversible = $false
        }
    )
}

function Get-WinMintSetupActionModulePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($action in @(
            Get-WinMintSetupActionCatalog |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.FunctionName) } |
                Select-Object -Property RelativePath -Unique
        )) {
        $modulePath = Join-Path $PayloadRoot ([string]$action.RelativePath)
        if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            throw "Setup action module is missing: $modulePath"
        }
        $paths.Add($modulePath) | Out-Null
    }
    return @($paths)
}

function Import-WinMintSetupActionModules {
    # Dot-sourcing inside this function binds module functions to function-local scope.
    # Promote every *new* function to script: so SetupComplete's action loop can call
    # Invoke-Sc* and their helpers (Resolve-Sc*, Get-Sc*, Find-Sc*, Test-Sc*, …).
    # Promoting only Invoke-Sc* left helpers stranded — Invoke-ScPowerProfile then failed
    # with "The term 'Resolve-ScPowerPlanActivation' is not recognized".
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadRoot
    )

    $before = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @(Get-ChildItem -Path 'Function:' -ErrorAction SilentlyContinue | ForEach-Object Name)) {
        [void]$before.Add([string]$name)
    }

    foreach ($modulePath in @(Get-WinMintSetupActionModulePaths -PayloadRoot $PayloadRoot)) {
        . $modulePath
    }

    foreach ($fn in @(Get-ChildItem -Path 'Function:' -ErrorAction SilentlyContinue)) {
        if ($before.Contains([string]$fn.Name)) { continue }
        Set-Item -LiteralPath "Function:script:$($fn.Name)" -Value $fn.ScriptBlock
    }
}
