#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $PoliciesPath
)
# Offline HKLM policy stamps (SOFTWARE + SYSTEM). Param-only — Plan owns which rows.
$mountDir = $MountDir
$workDirectory = $WorkDirectory
$policiesPath = $PoliciesPath

. (Join-Path $PSScriptRoot 'Save-WinMintDigestMap.ps1')

$logDir = Join-Path $workDirectory 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

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

# ProductPosture owns the digest key; family is declared on the row. JSON so Data may contain ; | ~~~~.
if (-not (Test-Path -LiteralPath $policiesPath -PathType Leaf)) { throw "policiesPath missing: $policiesPath" }
$rows = @(Get-Content -LiteralPath $policiesPath -Raw | ConvertFrom-Json)
if ($rows.Count -eq 0) { throw 'policies.json empty' }

$digests = @{}
$byHive = $rows | Group-Object -Property Hive
foreach ($group in $byHive) {
    $hiveName = ([string]$group.Name).Trim().ToUpperInvariant()
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
            Invoke-OfflineRegAdd -HiveKey $hiveKey -SubKey $row.SubKey -Name $row.Name -Type $row.RegType -Data $row.Data -Context $ctx
            $digests[$row.Digest] = [string]$row.Data
            Write-Output "policy ok: $($row.Digest)=$($row.Data)"
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

Save-WinMintDigestMap -WorkDirectory $workDirectory -Digests $digests
Write-Output "StampOfflinePolicies ok ($($rows.Count) rows)"
exit 0
