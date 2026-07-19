#Requires -Version 7.6

BeforeAll {
    if (-not $TestData -or -not $TestData.GuestSignals) {
        throw 'HyperV-Guest.Tests.ps1 requires -TestData @{ GuestSignals = ...; Tier = ...; WslDistros = ... }'
    }
    $script:Signals = $TestData.GuestSignals
    $script:Tier = [string]$TestData.Tier
    $script:WslDistros = @($TestData.WslDistros)
    $script:ExpectFedora = @($script:WslDistros | Where-Object { $_ -match '^(?i)Fedora' }).Count -gt 0
}

Describe 'Hyper-V guest desktop signals' {
    It 'has an account picture bitmap' {
        $script:Signals.AccountPictureBmpExists | Should -Be $true
    }

    It 'records Start pin policy (ConfigureStartPins)' {
        [string]$script:Signals.StartPins | Should -Not -BeNullOrEmpty
    }

    It 'writes durable FirstLogon_ShellPins.json' {
        $script:Signals.ShellPinsReportPresent | Should -Be $true
    }

    It 'applies windowed centered Terminal defaults' {
        [string]$script:Signals.TerminalLaunchMode | Should -Be 'default'
        [bool]$script:Signals.TerminalCenterOnLaunch | Should -Be $true
        [int]$script:Signals.TerminalOpacity | Should -Be 80
        [string]$script:Signals.TerminalColorScheme | Should -Be 'One Half Dark'
    }

    It 'hard-replaces Terminal list to PowerShell first' {
        $profiles = @($script:Signals.TerminalProfiles)
        $profiles.Count | Should -BeGreaterThan 0
        $profiles[0] | Should -Be 'PowerShell'
        $profiles | Should -Not -Contain 'Command Prompt'
        $profiles | Should -Not -Contain 'Windows PowerShell'
    }

    It 'includes Fedora Terminal profile when Fedora WSL is selected' -Skip:( -not $script:ExpectFedora ) {
        $script:Signals.FedoraProfileExists | Should -Be $true
        [string]$script:Signals.FedoraProfileIcon | Should -Match 'fedora'
    }
}

Describe 'Hyper-V full tier guest signals' {
    It 'includes Ubuntu Terminal profile when Ubuntu WSL is selected' -Skip:( $TestData.Tier -ne 'Full' -or 'Ubuntu' -notin @($TestData.WslDistros) ) {
        $script:Signals.UbuntuProfileExists | Should -Be $true
    }

    It 'includes NixOS Terminal profile when NixOS-WSL is selected' -Skip:( $TestData.Tier -ne 'Full' -or 'NixOS-WSL' -notin @($TestData.WslDistros) ) {
        $script:Signals.NixProfileExists | Should -Be $true
    }
}
