#requires -Version 7.6
Set-StrictMode -Version Latest

function Resolve-SmokePhase {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('apply', 'wait', 'assert', 'green', 'failed')]
        [string] $HostStage,
        [string] $VmState,
        [long] $VhdFileSizeBytes = 0,
        [switch] $HeartbeatOk,
        [switch] $EvidenceReady
    )
    switch ($HostStage) {
        'apply' { return 'apply' }
        'assert' { return 'assert' }
        'green' { return 'green' }
        'failed' { return 'failed' }
    }
    if ($VmState -notin @('Running')) { return 'setup-reboot' }
    if ($HeartbeatOk) { return 'guest-up' }
    if ($VhdFileSizeBytes -ge 1GB) { return 'winpe-apply' }
    return 'vm-boot'
}
