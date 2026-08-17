# Research: modern Windows platform capabilities WinMint is not using

**Date:** 2026-08-17  
**Question:** Besides the ADK-host hunt (`docs/research/2026-08-17-adk-platform-tools-winmint-ought-to-use.md`, `b4c50ca`) and the OOBE/DMA notes already shipped, which Learn-documented APIs or platform capabilities would improve ImageServicing, BuildPlan unattend, ProvisioningSession, packages, DMA settle, splash, Hyper-V Smoke, or host CLI — and is WinMint approximating them with the wrong tool?  
**Scope:** Other product seams only. Do **not** redo winpeshl / Setup GUI / OOBE answers vs DMA latch. Do **not** recommend Autopilot, Intune, WCD/PPKG as primary, Shell Launcher before OOBE, guest DISM API, or WinUI/Avalonia on the ISO.  
**Method:** Microsoft Learn MCP was not available in this session. Queries ran through `npx @microsoft/learn-cli search` / `fetch` against learn.microsoft.com only. No invented APIs. Grounding is the v2 repo, not generic “use Intune.”

## 1. Method

| Query | Primary Learn hits used |
| --- | --- |
| Offline Registry Library / Offreg.dll vs `reg load` | [Offline Registry Library](https://learn.microsoft.com/windows/win32/devnotes/offline-registry-library-portal), [About the Offline Registry Library](https://learn.microsoft.com/windows/win32/devnotes/about-the-offline-registry-library), [OROpenHive](https://learn.microsoft.com/windows/win32/devnotes/oropenhive), [reg load](https://learn.microsoft.com/windows-server/administration/windows-commands/reg-load) |
| BCD APIs vs `bcdboot` | [BCDBoot Command-Line Options](https://learn.microsoft.com/windows-hardware/manufacture/desktop/bcdboot-command-line-options-techref-di?view=windows-11), [BCDEdit](https://learn.microsoft.com/windows-hardware/manufacture/desktop/bcdedit-command-line-options?view=windows-11), [Boot Configuration Data WMI](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/bcd/boot-configuration-data-portal) |
| Storage WMI / VDS vs `diskpart` in WinPE | [WinPE intro — Storage](https://learn.microsoft.com/windows-hardware/manufacture/desktop/winpe-intro?view=windows-11), [WinPE Optional Components](https://learn.microsoft.com/windows-hardware/manufacture/desktop/winpe-add-packages--optional-components-reference?view=windows-11), [Get-Disk](https://learn.microsoft.com/powershell/module/storage/get-disk?view=windowsserver2025-ps), [VDS superseded](https://learn.microsoft.com/windows/win32/vds/virtual-disk-service-portal) |
| WinGet COM / configure / DSC | [Use WinGet](https://learn.microsoft.com/windows/package-manager/winget/), [WinGet Configuration](https://learn.microsoft.com/windows/package-manager/configuration/), [configure](https://learn.microsoft.com/windows/package-manager/winget/configure), [Windows Package Manager COM API](https://learn.microsoft.com/windows/win32/appxpkg/windows-package-manager-com-api) (Phone-era; not the modern client) |
| AppX / reserved storage | [PackageManager](https://learn.microsoft.com/uwp/api/windows.management.deployment.packagemanager?view=winrt-28000), [DISM Reserved Storage](https://learn.microsoft.com/windows-hardware/manufacture/desktop/dism-storage-reserve?view=windows-11) |
| Geo / locale | [SetUserGeoID](https://learn.microsoft.com/windows/win32/api/winnls/nf-winnls-setusergeoid), [SetUserGeoName](https://learn.microsoft.com/windows/win32/api/winnls/nf-winnls-setusergeoname), [GetUserDefaultGeoName](https://learn.microsoft.com/windows/win32/api/winnls/nf-winnls-getuserdefaultgeoname), [Set-WinHomeLocation](https://learn.microsoft.com/powershell/module/international/set-winhomelocation?view=windowsserver2025-ps), [Set-Culture](https://learn.microsoft.com/powershell/module/international/set-culture?view=windowsserver2025-ps), [GlobalizationPreferences.TrySetHomeGeographicRegion](https://learn.microsoft.com/uwp/api/windows.system.userprofile.globalizationpreferences.trysethomegeographicregion?view=winrt-28000) |
| OOBE unattend 24H2/25H2 Pro | [Automate OOBE](https://learn.microsoft.com/windows-hardware/customize/desktop/automate-oobe), [OOBE child elements](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe), [HideOnlineAccountScreens](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens), [HideLocalAccountScreen](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidelocalaccountscreen), [NetworkLocation](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-networklocation), [VMModeOptimizations](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-vmmodeoptimizations) |
| Hyper-V | [Hyper-V WMI v2](https://learn.microsoft.com/windows/win32/hyperv_v2/windows-virtualization-portal), [WMI v1 → v2](https://learn.microsoft.com/windows-server/virtualization/hyper-v/refactor-wmi-v1-to-wmi-v2), [New-VM](https://learn.microsoft.com/powershell/module/hyper-v/new-vm?view=windowsserver2025-ps) |

**Grounding (repo, not OS proof):** `servicing/*.ps1` `dism.exe` + `reg load` / `reg add`; `payload/winpe/LaunchApply.cmd` `diskpart` + `dism /Apply-Image` + `bcdboot` + `reg load` LabConfig; `BuildPlan.BuildOobeUnattendXml` International-Core + Shell-Setup hide/account/autologon; specialize `reg add` DeviceRegion; Supervisor `WinRTAppxPackageManager` (`Windows.Management.Deployment.PackageManager`), `Win32RegionSnapshot` (`SetUserGeoID` / `GetUserGeoID` / `GetUserDefaultLocaleName` + inbox `Set-Culture` + `tzutil`), reserved-storage inbox `dism.exe`; `tools/vm/Invoke-Smoke.ps1` Hyper-V cmdlets + `Msvm_Keyboard`; host `winget.exe` in `Invoke-PackagesCheck.ps1`. ADK-host, winpeshl, and OOBE-vs-DMA are out of scope — see `2026-08-17-adk-platform-tools-winmint-ought-to-use.md`, [#119](https://github.com/yanai-sh/winmint/issues/119), `2026-08-16-clean-hands-off-oobe.md`.

## 2. Already using

Short so this note does not “discover” existing WinRT / `LibraryImport` / inbox CLI.

| Seam | What the repo already calls | Learn name |
| --- | --- | --- |
| ImageServicing | Elevated `dism.exe /English` (mount, export, AppX, capability, feature, driver). Not DISM PowerShell (Store pwsh “Class not registered”). | DISM CLI — documented primary servicing tool |
| Host ISO | `oscdimg` from ADK Deployment Tools | Oscdimg |
| Host media probe | `Mount-DiskImage` | Storage cmdlets on the **host** |
| Offline hive stamps | `reg load` + `reg add` (policies, Shell, Deprovisioned marks) | `reg load` / `RegLoadKey` |
| WinPE apply | `diskpart` + `dism /Apply-Image` + `bcdboot … /s S: /f UEFI` | WinPE inbox Storage + DISM + BCDBoot |
| Unattend | `oobeSystem` International-Core + Shell-Setup `HideEULAPage` / `HideOEMRegistrationScreen` / `HideOnlineAccountScreens` / `HideWirelessSetupInOOBE` / `ProtectYourPC` + `LocalAccounts` + `AutoLogon` | Automate OOBE |
| DMA latch | specialize `reg add` `DeviceRegion=68` + `.DEFAULT` Geo | No manufacturing API; ADR-003 |
| DMA settle (visible) | `SetUserGeoID` / `GetUserGeoID`; inbox `Set-Culture`; `tzutil /s` | NLS GeoID + International `Set-Culture` + TZUtil |
| AppX safety net / winget path | `Windows.Management.Deployment.PackageManager` (find / remove / deprovision / `RegisterPackageByFamilyNameAsync`) | Package deployment API |
| Packages | `winget.exe` `install` / `import` after App Installer register; Scoop via inbox `powershell.exe` | WinGet CLI; ADR-011 delegation |
| Reserved storage | Inbox `dism.exe /Online /Set-ReservedStorageState /State:Disabled` in `--machine-setup` (SYSTEM) | DISM Reserved Storage — online-only |
| Splash | In-process GDI (`CreateWindowExW` / `TextOutW`); D2D only if first opaque frame fails | Inbox GDI; no ISO UI framework |
| Smoke | Hyper-V PowerShell (`New-VM`, `New-VHD`, switches, DVD) + `root\virtualization\v2` `Msvm_Keyboard` for key inject | Cmdlets wrap WMI v2; keyboard has no cmdlet |
| Host catalog proof | Native ARM64 `winget.exe` download | WinGet CLI |

CsWin32 `NativeMethods.txt` already lists the settle/splash/reboot/account P/Invokes. Do not re-recommend those.

## 3. Ranked improvements

Honest list. Nothing here is #119 quality (named Learn host, current wrong tool, independent follow-up). High-cost / YAGNI is the typical answer.

| Rank | Capability | Learn URL | Seam | Why better | Cost / risk | YAGNI vs real gap |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `SetUserGeoName` / `GetUserDefaultGeoName` (ISO 3166-1 / UN M.49) instead of `SetUserGeoID` / `GetUserGeoID` for **visible** settle | [SetUserGeoName](https://learn.microsoft.com/windows/win32/api/winnls/nf-winnls-setusergeoname) · [SetUserGeoID](https://learn.microsoft.com/windows/win32/api/winnls/nf-winnls-setusergeoid) (banner: use `SetUserGeoName`) · [GetUserDefaultGeoName](https://learn.microsoft.com/windows/win32/api/winnls/nf-winnls-getuserdefaultgeoname) | ProvisioningSession settle (`Win32RegionSnapshot`) | Learn marks GeoID APIs as “may be altered or unavailable”; `GEO_ID` is “backward compatibility — do not use in new applications.” Same user-Geo store, newer name API. | Profile `dma.settle.geoId` is an int; DeviceRegion latch stays DWORD **68** (no ISO manufacturing key). Dual vocabulary. CsWin32 add + verify path. | **Soft gap, not a wrong tool.** GeoID still works on 24H2/25H2. Switch if GeoID starts failing or Learn drops it. Do **not** replace DeviceRegion `reg add`. |
| 2 | Offline Registry Library (`OROpenHive` / `ORSetValue` / `ORSaveHive`) instead of `reg load` for offline hive stamps | [Offline Registry Library](https://learn.microsoft.com/windows/win32/devnotes/offline-registry-library-portal) · [About](https://learn.microsoft.com/windows/win32/devnotes/about-the-offline-registry-library) | ImageServicing (`Stamp-OfflinePolicies`, `Stamp-OfflineShell`, `Remove-ProvisionedAppx`) and LaunchApply LabConfig | Learn’s stated audience is “servicing an operating system image.” Avoids loading a hive into the live HKLM (collision, dirty unload, privilege). Read-open + write-save; no access checks on hive objects. | **Not inbox.** `Offreg.dll` is a WDK redistributable. Must ship/side-load the DLL into elevated `pwsh` kernels (or a helper). `ORSaveHive` needs target OS version numbers and will not overwrite an existing file. Simple locking. Host Apply already elevates, so `reg load` is the documented privileged path. | **YAGNI** unless a recorded hive load/unload flake appears. Do not add a WDK binary to chase elegance. |
| 3 | `bcdboot /offline` (and `/bootex` when CA 2023 applies) | [BCDBoot options](https://learn.microsoft.com/windows-hardware/manufacture/desktop/bcdboot-command-line-options-techref-di?view=windows-11) — `/offline` “Supported starting with Windows 11, Version 24H2 Build 26100.8037 and Version 25H2 Build 26100.8037” | LaunchApply after apply | Learn’s apply-image path is still `bcdboot <Windows> /s <ESP> /f UEFI` — already used. `/offline` only forces offline boot-file selection (bootex vs non-bootex) when servicing boot binaries without booting them. | Flag is build-gated. Wrong use on older Source ISO `bcdboot` is a no-op or error. `/bootex` is CVE-2023-24932 Secure Boot CA 2023, not a general apply improvement. | **YAGNI** until a Primary/Smoke boot fails on boot-manager revocation. Keep current `bcdboot W:\Windows /s S: /f UEFI`. Do not replace with BCD WMI / BCDEdit — Learn says recover/new-PC system partition is BCDBoot’s job. |
| 4 | `Microsoft.WinGet.Client` (PowerShell) on the **host** instead of spawning `winget.exe` for catalog proof | [Scripting WinGet](https://learn.microsoft.com/windows/package-manager/winget/#use-winget) → [Microsoft.WinGet.Client](https://www.powershellgallery.com/packages/Microsoft.WinGet.Client/) | Host `Invoke-PackagesCheck.ps1` only | Typed cmdlets / `Repair-WinGetPackageManager` instead of parsing CLI. Same App Installer engine. | Extra Gallery module on the maintainer host. Guest use would be **guest pwsh product runtime**. Learn does **not** document a public `Microsoft.Management.Deployment` COM surface for third-party AOT apps — the Learn “Windows Package Manager COM API” page is the old Phone `PMSvc` (“not available to all Windows apps”). | **YAGNI.** Host `winget.exe` already does download + source update. Do not wrap COM in Supervisor. |
| 5 | `winget configure` / DSC v3 instead of `winget import` + `shell.stamp` | [WinGet Configuration](https://learn.microsoft.com/windows/package-manager/configuration/) · [configure](https://learn.microsoft.com/windows/package-manager/winget/configure) · [v3 schema](https://learn.microsoft.com/windows/package-manager/configuration/create-v3) | ProvisioningSession packages | One declarative file for packages + machine settings. ADR-011 already names it as an allowed delegate. | DSC resources + YAML + WinGet ≥ 1.6 (v3: ≥ 1.11 + `Microsoft.DesiredStateConfiguration`). Trust review of every resource. `shell.stamp` is intentionally not configure (one-shot skel). Guest inbox `powershell.exe` only for narrow wrappers. | **Deferred by design**, not unused-by-accident. [PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md) and the alpha package spec keep configure out of default. Spike only if import cannot express a needed setting. |

No further ranks. The rest of the hunt list is already-using or reject (section 4).

## 4. Rejects

| Capability | Why rejected |
| --- | --- |
| **Autopilot / Intune / MDM** | Cloud enrollment. Conflicts with user-supplied Source ISO + local unattend + Supervisor. |
| **WCD / `.ppkg` as primary** | Runtime IT/BYOD provisioning. Already rejected in the ADK-host note. |
| **Shell Launcher / Assigned Access before OOBE** | Learn: custom shell before OOBE is unsupported; image not deployable. Tenure Shell stays post-OOBE only. |
| **Guest DISM API / `DismAPI.dll` / `DismSetReservedStorageState`** | ADK host requirement. Inbox `dism.exe` is the documented online reserved-storage CLI. Already using that in `--machine-setup`. |
| **Setup GUI / `setup.exe` / `/legacy` / `Autounattend.xml` search order** | WinPE apply stays the install engine. |
| **DISM API / WimgApi as a host-kernel rewrite** | Same engine as `dism.exe`. ADK-host note already closed this. |
| **BCD WMI / BCDEdit as apply** | Learn: new system partition after apply-image is BCDBoot. WMI is for complex/nonstandard edits. |
| **VDS (`IVds*`)** | Superseded since Windows 8 by Storage Management API. Not a WinPE inbox tool. |
| **WinPE-StorageWMI / `Get-Disk` in LaunchApply** | Learn: base WinPE storage is **DiskPart + BCDBoot**. Storage WMI is an **ADK optional component** (`WinPE-StorageWMI`) that also needs WinPE-PowerShell/NetFX/WMI. Injecting ADK OCs into the **user Source ISO** `boot.wim` is a different product (CopyPE-shaped). English `diskpart` parse is a known ceiling (`LaunchApply.cmd` ponytail); localized WinPE refuses — safe direction. Do not bloat `boot.wim` to parse `MSFT_Disk.BusType`. |
| **`HideLocalAccountScreen`** | Server editions only. Pro Smoke/Primary do not need it. |
| **`NetworkLocation`** | Deprecated in Windows 10. Do not add. |
| **`VMModeOptimizations`** | Requires `sysprep /mode:vm`. WinMint applies `install.wim`; it does not generalize. SkipWinRE in a container is the wrong product. |
| **`GlobalizationPreferences.TrySetHomeGeographicRegion`** | Learn: IoT / Embedded mode + `systemManagement` capability. Not desktop Pro settle. |
| **`Set-WinHomeLocation` as product** | Same user GeoID store as `SetUserGeoID`, via International PowerShell. Guest pwsh product runtime if used as the Supervisor path. Inbox `Set-Culture` is already the documented locale setter (no `SetUserDefaultLocaleName` export). |
| **WinGet Phone-era COM (`PMSvc`)** | Learn: “not available to all Windows apps.” Wrong API family. |
| **WinUI / Avalonia / peer Splash.exe on the ISO** | Splash stays in-process GDI/D2D. |
| **Invented DeviceRegion unattend / manufacturing API** | International-Core has no GeoID/DeviceRegion. Keep `reg add` + ADR-003. |

## 5. Issues

Zero new GitHub issues. Closest named successor is `SetUserGeoName` for visible settle — a deprecation banner on an API that still works, not a wrong-host swap like winpeshl `[LaunchApp]`. The research file is the deliverable.
