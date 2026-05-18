#Requires -Version 7.3

if (-not ([System.Management.Automation.PSTypeName]'WinMintNative').Type) {
    $src = Get-Content -Raw "$PSScriptRoot\WinMintNative.cs"
    $srcBytes = [System.Text.Encoding]::UTF8.GetBytes($src)
    $srcHash  = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::HashData($srcBytes)).Replace('-', '').Substring(0, 8)
    $cacheDir = Join-Path ([System.IO.Path]::GetTempPath().TrimEnd('\', '/')) 'WinMint_TypeCache'
    $dllPath  = Join-Path $cacheDir "WinMintNative_$srcHash.dll"
    $loaded   = $false
    if (Test-Path $dllPath) {
        try { Add-Type -Path $dllPath -ErrorAction Stop; $loaded = $true } catch {}
    }
    if (-not $loaded) {
        try {
            $null = [System.IO.Directory]::CreateDirectory($cacheDir)
            Add-Type -TypeDefinition $src -Language CSharp -OutputAssembly $dllPath
            Add-Type -Path $dllPath
        } catch {
            Add-Type -TypeDefinition $src -Language CSharp
        }
    }
}
