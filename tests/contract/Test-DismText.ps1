#requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repo 'servicing\Set-OfflineComponent.ps1') -MountDir 'x' -WorkDirectory 'x' -Kind 'capability' -NamesPath 'x'
. (Join-Path $repo 'servicing\Remove-ProvisionedAppx.ps1') -MountDir 'x' -WorkDirectory 'x' -PackageFamilyNamesPath 'x'

$capText = @'
Deployment Image Servicing and Management tool
Version: 10.0.26100.1

Image Version: 10.0.26100.4349

Capability Identity : Language.Basic~~~en-US~0.0.1.0
State : Installed

Capability Identity : Browser.InternetExplorer~~~~0.0.11.0
State : Not Present

Capability Identity : App.StepsRecorder~~~~0.0.1.0
State : NotPresent

Capability Identity : WMIC~~~~
State : Absent

The operation completed successfully.
'@

$caps = ConvertFrom-DismStateText -Text $capText -Kind capability
if ($caps['Language.Basic~~~en-US~0.0.1.0'] -ne 'Installed') { throw 'capability Installed' }
if ($caps['Browser.InternetExplorer~~~~0.0.11.0'] -ne 'Not Present') { throw 'capability Not Present' }
if ($caps['App.StepsRecorder~~~~0.0.1.0'] -ne 'NotPresent') { throw 'capability NotPresent' }
if ($caps['WMIC~~~~'] -ne 'Absent') { throw 'capability Absent' }

$featText = @'
Feature Name : Microsoft-Windows-Subsystem-Linux
State : Disabled

Feature Name : WorkFolders-Client
State : Enabled

Feature Name : Containers-DisposableClientVM
State : DisabledWithPayloadRemoved
'@

$feats = ConvertFrom-DismStateText -Text $featText -Kind feature
if ($feats['Microsoft-Windows-Subsystem-Linux'] -ne 'Disabled') { throw 'feature Disabled' }
if ($feats['WorkFolders-Client'] -ne 'Enabled') { throw 'feature Enabled' }
if ($feats['Containers-DisposableClientVM'] -ne 'DisabledWithPayloadRemoved') { throw 'feature DisabledWithPayloadRemoved' }

$appxText = @'
DisplayName : Microsoft.BingNews
Version : 4.2.0.0
Architecture : arm64
ResourceId : ~
PackageName : Microsoft.BingNews_4.2.0.0_arm64__8wekyb3d8bbwe

DisplayName : Microsoft.Copilot
PackageName : Microsoft.Copilot_1.0.0.0_neutral_~_8wekyb3d8bbwe
'@

$pkgs = @(ConvertFrom-ProvisionedAppxText -Text $appxText)
if ($pkgs.Count -ne 2) { throw "appx count $($pkgs.Count)" }
if ($pkgs[0].DisplayName -ne 'Microsoft.BingNews') { throw 'appx BingNews display' }
if ($pkgs[0].PublisherId -ne '8wekyb3d8bbwe') { throw 'appx BingNews publisher' }
if ((Get-PackageFamilyName -Package $pkgs[0]) -ne 'Microsoft.BingNews_8wekyb3d8bbwe') { throw 'appx BingNews PFN' }
if (-not (Test-PackageMatchesCatalogId -Package $pkgs[1] -CatalogId 'Microsoft.Copilot')) { throw 'appx Copilot catalog match' }

Write-Output 'Test-DismText ok'
exit 0
