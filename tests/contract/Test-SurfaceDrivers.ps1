#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Inject-SurfaceDrivers.ps1')

if (-not (Test-MicrosoftDownloadUri -Uri 'https://download.microsoft.com/download/x.msi')) {
    throw 'download.microsoft.com must be allowed'
}
if (-not (Test-MicrosoftDownloadUri -Uri 'https://www.microsoft.com/en-us/download')) {
    throw 'www.microsoft.com must be allowed'
}
if (Test-MicrosoftDownloadUri -Uri 'http://download.microsoft.com/x.msi') {
    throw 'http must be refused'
}
if (Test-MicrosoftDownloadUri -Uri 'https://evil.example/payload.msi') {
    throw 'non-Microsoft host must be refused'
}

Write-Output 'Test-SurfaceDrivers ok'
exit 0
