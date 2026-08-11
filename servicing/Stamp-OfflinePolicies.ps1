#requires -Version 7.6
param(
    [Parameter(Mandatory)]
    [hashtable] $Parameters
)
# Offline HKLM policy stamps (SOFTWARE + SYSTEM). Param-only — Plan owns which rows.
$mountDir = $Parameters['mountDir']
$workDirectory = $Parameters['workDirectory']
$policySpecs = $Parameters['policySpecs']
if ([string]::IsNullOrWhiteSpace($mountDir)) { throw 'mountDir required' }
if ([string]::IsNullOrWhiteSpace($workDirectory)) { throw 'workDirectory required' }
if ([string]::IsNullOrWhiteSpace($policySpecs)) { throw 'policySpecs required' }

$logDir = Join-Path $workDirectory 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$digestPath = Join-Path $logDir 'digests.json'

function Save-DigestMap {
    param([hashtable] $Digests)
    $map = @{}
    if (Test-Path -LiteralPath $digestPath) {
        foreach ($p in (Get-Content -LiteralPath $digestPath -Raw | ConvertFrom-Json).PSObject.Properties) {
            $map[[string]$p.Name] = [string]$p.Value
        }
    }
    foreach ($k in $Digests.Keys) { $map[[string]$k] = [string]$Digests[$k] }
    $map | ConvertTo-Json | Set-Content -LiteralPath $digestPath -Encoding utf8
}

function Resolve-PolicyFamily {
    param([Parameter(Mandatory)][string] $SubKey)
    if ($SubKey -match 'BraveSoftware') { return 'brave' }
    if ($SubKey -match 'OneDrive') { return 'onedrive' }
    if ($SubKey -match 'Device Installer') { return 'deviceInstaller' }
    if ($SubKey -match 'Device Metadata') { return 'device' }
    if ($SubKey -match 'WindowsCopilot') { return 'copilot' }
    if ($SubKey -match 'Session Manager') { return 'wpbt' }
    if ($SubKey -match 'FileSystem') { return 'filesystem' }
    if ($SubKey -match '\\Dsh' -or $SubKey -match 'AllowNewsAndInterests') { return 'widgets' }
    if ($SubKey -match 'CloudContent') { return 'cloudContent' }
    if ($SubKey -match 'WindowsStore') { return 'store' }
    if ($SubKey -match 'AppModelUnlock') { return 'developer' }
    if ($SubKey -match '\\Sudo') { return 'sudo' }
    return 'edge'
}

function Test-TransientRegDenied {
    param([string] $Message)
    return $Message -match 'Access is denied|unauthorized|UnauthorizedAccess|denied'
}

function Invoke-OfflineHiveValueWrite {
    param(
        [Parameter(Mandatory)][string] $HiveMountName,
        [Parameter(Mandatory)][string] $SubKey,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Type,
        [Parameter(Mandatory)][string] $Data
    )
    # HiveMountName e.g. WinMintPol_SOFTWARE (under HKLM)
    $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($HiveMountName, $true)
    if ($null -eq $root) { throw "cannot open HKLM\$HiveMountName writable" }
    try {
        $key = $root.CreateSubKey($SubKey, $true)
        if ($null -eq $key) { throw "CreateSubKey returned null: $SubKey" }
        try {
            $kind = switch ($Type.ToUpperInvariant()) {
                'REG_DWORD' { [Microsoft.Win32.RegistryValueKind]::DWord }
                'REG_SZ' { [Microsoft.Win32.RegistryValueKind]::String }
                'REG_QWORD' { [Microsoft.Win32.RegistryValueKind]::QWord }
                default { throw "unsupported reg type '$Type'" }
            }
            $value = if ($kind -eq [Microsoft.Win32.RegistryValueKind]::String) {
                [string]$Data
            }
            else {
                [int]$Data
            }
            $key.SetValue($Name, $value, $kind)
            $got = $key.GetValue($Name)
            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::String) {
                if ([string]$got -ne [string]$Data) { throw "readback mismatch got=$got want=$Data" }
            }
            elseif ([int]$got -ne [int]$Data) {
                throw "readback mismatch got=$got want=$Data"
            }
        }
        finally {
            $key.Dispose()
        }
    }
    finally {
        $root.Dispose()
    }
}

function Invoke-OfflineRegAdd {
    param(
        [Parameter(Mandatory)][string] $HiveKey,
        [Parameter(Mandatory)][string] $SubKey,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Type,
        [Parameter(Mandatory)][string] $Data,
        [string] $Context = ''
    )
    # HiveKey = HKLM\WinMintPol_SOFTWARE → mount name WinMintPol_SOFTWARE
    $mountName = $HiveKey -replace '^HKLM\\', ''
    $max = 8
    for ($i = 1; $i -le $max; $i++) {
        try {
            Invoke-OfflineHiveValueWrite -HiveMountName $mountName -SubKey $SubKey -Name $Name -Type $Type -Data $Data
            Write-Output "The operation completed successfully."
            return
        }
        catch {
            $msg = $_.Exception.Message
            Write-Output "reg write retry $i/$max $($Context): $msg"
            if (-not (Test-TransientRegDenied $msg) -or $i -eq $max) {
                throw "reg add failed: $Context — $msg"
            }
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds (300 * $i)
        }
    }
}

$rows = @()
foreach ($raw in ($policySpecs -split ';')) {
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $parts = $raw -split '\|', 5
    if ($parts.Count -ne 5) { throw "malformed policySpecs row: $raw" }
    $rows += [pscustomobject]@{
        Hive   = $parts[0].Trim().ToUpperInvariant()
        SubKey = $parts[1]
        Name   = $parts[2]
        Type   = $parts[3]
        Data   = $parts[4]
    }
}

$digests = @{}
$byHive = $rows | Group-Object -Property Hive
foreach ($group in $byHive) {
    $hiveName = [string]$group.Name
    $fileName = switch ($hiveName) {
        'SOFTWARE' { 'SOFTWARE' }
        'SYSTEM' { 'SYSTEM' }
        default { throw "unsupported hive '$hiveName'" }
    }
    $hivePath = Join-Path $mountDir "Windows\System32\config\$fileName"
    if (-not (Test-Path -LiteralPath $hivePath)) { throw "hive missing: $hivePath" }

    $hiveKey = "HKLM\WinMintPol_$hiveName"
    Write-Output "REG LOAD $hiveKey"
    & reg.exe load $hiveKey $hivePath
    if ($LASTEXITCODE -ne 0) { throw "reg load failed ($hiveName): $LASTEXITCODE" }
    try {
        foreach ($row in $group.Group) {
            $ctx = "hive=$hiveName sub=$($row.SubKey) name=$($row.Name)"
            Invoke-OfflineRegAdd -HiveKey $hiveKey -SubKey $row.SubKey -Name $row.Name -Type $row.Type -Data $row.Data -Context $ctx
            $family = Resolve-PolicyFamily -SubKey $row.SubKey
            $digests["policy.$family.$($row.Name)"] = [string]$row.Data
            Write-Output "policy ok: $family.$($row.Name)=$($row.Data)"
        }
    }
    finally {
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        Start-Sleep -Milliseconds 500
        & reg.exe unload $hiveKey
        if ($LASTEXITCODE -ne 0) { throw "reg unload failed ($hiveName): $LASTEXITCODE" }
    }
}

Save-DigestMap $digests
Write-Output "StampOfflinePolicies ok ($($rows.Count) rows)"
exit 0
