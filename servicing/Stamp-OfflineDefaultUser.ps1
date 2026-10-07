#requires -Version 7.6
param(
    [Parameter(Mandatory)] [string] $MountDir,
    [Parameter(Mandatory)] [string] $WorkDirectory,
    [Parameter(Mandatory)] [string] $DefaultUserPath
)
# Offline Default User (NTUSER.DAT) stamps. Param-only — Plan owns which rows. Never create Policies.
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
                'REG_EXPAND_SZ' { [Microsoft.Win32.RegistryValueKind]::ExpandString }
                'REG_QWORD' { [Microsoft.Win32.RegistryValueKind]::QWord }
                default { throw "unsupported reg type '$Type'" }
            }
            $value = if ($kind -eq [Microsoft.Win32.RegistryValueKind]::String `
                -or $kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) {
                [string]$Data
            }
            else {
                [int]$Data
            }
            $key.SetValue($Name, $value, $kind)
            if ($kind -eq [Microsoft.Win32.RegistryValueKind]::String `
                -or $kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) {
                $got = $key.GetValue(
                    $Name,
                    $null,
                    [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ([string]$got -ne [string]$Data) { throw "readback mismatch got=$got want=$Data" }
            }
            else {
                $got = $key.GetValue($Name)
                if ([int]$got -ne [int]$Data) {
                    throw "readback mismatch got=$got want=$Data"
                }
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

function Invoke-OfflineRegExeAdd {
    param(
        [Parameter(Mandatory)][string] $HiveKey,
        [Parameter(Mandatory)][string] $SubKey,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Type,
        [Parameter(Mandatory)][string] $Data
    )
    $regType = switch ($Type.ToUpperInvariant()) {
        'REG_DWORD' { 'REG_DWORD' }
        'REG_SZ' { 'REG_SZ' }
        'REG_EXPAND_SZ' { 'REG_EXPAND_SZ' }
        'REG_QWORD' { 'REG_QWORD' }
        default { throw "unsupported reg type '$Type'" }
    }
    $path = "$HiveKey\$SubKey"
    & reg.exe add $path /v $Name /t $regType /d $Data /f | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "reg.exe add exit $LASTEXITCODE for $path\$Name" }
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
            if ($i -eq $max -and (Test-TransientRegDenied $msg)) {
                Write-Output "reg.exe fallback $($Context)"
                Invoke-OfflineRegExeAdd -HiveKey $HiveKey -SubKey $SubKey -Name $Name -Type $Type -Data $Data
                Write-Output "The operation completed successfully (reg.exe)."
                return
            }
            if (-not (Test-TransientRegDenied $msg) -or $i -eq $max) {
                throw "reg add failed: $Context — $msg"
            }
            [gc]::Collect()
            [gc]::WaitForPendingFinalizers()
            Start-Sleep -Milliseconds (300 * $i)
        }
    }
}

if (-not (Test-Path -LiteralPath $defaultUserPath -PathType Leaf)) { throw "defaultUserPath missing: $defaultUserPath" }
$rows = @(Get-Content -LiteralPath $defaultUserPath -Raw | ConvertFrom-Json)
if ($rows.Count -eq 0) { throw 'default-user.json empty' }
foreach ($row in $rows) {
    $sub = [string]$row.SubKey
    if ($sub -match '(?i)(^|\\)Policies(\\+|$)') {
        throw "default-user row must not create Policies: $sub"
    }
}

$hivePath = Join-Path $mountDir 'Users\Default\NTUSER.DAT'
if (-not (Test-Path -LiteralPath $hivePath -PathType Leaf)) { throw "NTUSER.DAT missing: $hivePath" }

$hiveKey = 'HKLM\WinMintDU'
Write-Output "REG LOAD $hiveKey"
& reg.exe load $hiveKey $hivePath
if ($LASTEXITCODE -ne 0) { throw "reg load failed (NTUSER): $LASTEXITCODE" }
try {
    foreach ($row in $rows) {
        $ctx = "hive=NTUSER sub=$($row.SubKey) name=$($row.Name)"
        Invoke-OfflineRegAdd -HiveKey $hiveKey -SubKey $row.SubKey -Name $row.Name -Type $row.RegType -Data $row.Data -Context $ctx
        Write-Output "default-user ok: $($row.Name)=$($row.Data)"
    }
}
finally {
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 500
    & reg.exe unload $hiveKey
    if ($LASTEXITCODE -ne 0) { throw "reg unload failed (NTUSER): $LASTEXITCODE" }
}

Write-Output "StampOfflineDefaultUser ok ($($rows.Count) rows)"
exit 0
