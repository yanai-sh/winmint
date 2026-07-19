# WinMint polish — primary-source research (2026-07-19)

Concise findings for four polish topics. Prefer Microsoft Learn / first-party docs. Where only community or secondary sources exist, that is stated explicitly.

---

## 1. Winget: repair sources, upgrade tooling before `upgrade --all`

### Recommended repair / bootstrap path

Microsoft’s troubleshooting guidance for a broken or missing WinGet client is:

1. Install the `Microsoft.WinGet.Client` PowerShell module from PSGallery.
2. Run `Repair-WinGetPackageManager` (optionally `-Force -Latest`).

Sandbox / machine-scope example from Learn uses `Repair-WinGetPackageManager -AllUsers` after `Install-Module Microsoft.WinGet.Client`. WinGet itself ships as part of **App Installer** (`Microsoft.DesktopAppInstaller`), updated via Microsoft Store on desktop SKUs.

Sources:

- [Use WinGet to install and manage applications](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [Debugging and troubleshooting issues with WinGet](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)

Also documented for first-logon registration lag:

```powershell
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
```

### Source repair (prefer update, reset only when needed)

| Command | Role |
|--------|------|
| `winget source update` | Refresh all sources (alias: `refresh`) |
| `winget source reset --force` | Reset to defaults `msstore` / `winget` / `winget-font`; **admin**; use rarely |
| `winget source list` | Inspect configured sources |

Source: [The WinGet source command](https://learn.microsoft.com/en-us/windows/package-manager/winget/source)

### Prefer targeted upgrades over blind `winget upgrade --all`

Official upgrade docs document `winget upgrade --all` / `-r`, but also show upgrading by exact `--id` and previewing with bare `winget upgrade`. For polish, prefer an ordered, explicit set (machine scope where the installer supports it):

```text
winget source update
# then, per package (examples of common IDs in community repo / Store):
winget upgrade --id Microsoft.DesktopAppInstaller --accept-source-agreements --accept-package-agreements
winget upgrade --id Microsoft.EdgeWebView2Runtime --scope machine --accept-package-agreements
winget upgrade --id Microsoft.WindowsTerminal --scope machine --accept-package-agreements
```

Notes from Learn:

- `--scope user|machine` filters / selects scope; **not all installers support machine scope reliably** (MSIX/MSI usually better than EXE). See troubleshooting “Scope for specific user vs machine-wide”.
- WinGet CLI is **not supported in SYSTEM / LocalSystem context**; use `Microsoft.WinGet.Client` for machine-wide work from system context.
- App Installer is a Store system component — upgrading it via winget/Store is the supported client refresh path, not a separate MSI in Learn.

Sources:

- [upgrade command](https://learn.microsoft.com/en-us/windows/package-manager/winget/upgrade)
- [Troubleshooting — scope / system context](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)
- WebView2 Evergreen is preinstalled on Windows 11; still safe to keep Evergreen Runtime current: [Evergreen vs fixed version](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/evergreen-vs-fixed-version)

### Exit code `APPINSTALLER_CLI_ERROR_UPDATE_ALL_HAS_FAILURE` (−1978335188)

**Documented in the winget-cli repo** (referenced from Learn’s troubleshooting page “Exit codes” → return-codes table), not as a deep narrative article on Learn:

| Hex | Decimal | Name | Meaning |
|-----|---------|------|---------|
| `0x8A15002C` | `-1978335188` | `APPINSTALLER_CLI_ERROR_UPDATE_ALL_HAS_FAILURE` | `winget upgrade --all` completed with one or more package failures |

Sources:

- [returnCodes.md](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md)
- [AppInstallerErrors.h](https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerSharedLib/Public/AppInstallerErrors.h)
- Learn points here: [Troubleshooting — Exit codes](https://learn.microsoft.com/en-us/windows/package-manager/winget/troubleshooting)

**Implication for polish:** treat `-1978335188` as “bulk upgrade had failures,” not as “winget is broken.” Prefer targeted upgrades of App Installer / WebView2 / Terminal so a single unrelated package cannot fail the whole bootstrap step.

---

## 2. OOBE rehydration (`UScheduler_Oobe` / Orchestrator)

### What Microsoft documents (Outlook)

Microsoft Learn **does** document Windows Update Orchestrator jobs under:

`HKLM\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe`

For **new Outlook** (`Microsoft.OutlookForWindows`):

| SKU / case | Supported control |
|------------|-------------------|
| **Windows 11** (builds later than 23H2) | New Outlook is **preinstalled**; Learn says there is **currently no way to block install**. Remove after install with `Remove-AppxProvisionedPackage` / `Remove-AppxPackage`, and remove orchestrator value `...\UScheduler_Oobe\OutlookUpdate`. After March 2024+ CU on 23H2, deprovisioning is respected so removing the registry value may be unnecessary. |
| **Windows 10** (auto-install via 2025 updates) | Create `REG_SZ` `BlockedOobeUpdaters` = `["MS_Outlook"]` under `...\UScheduler_Oobe`, and/or remove the provisioned package. |

Also documented: remove Mail & Calendar (`microsoft.windowscommunicationsapps`) to block the Mail→new Outlook handoff; Store acquisition can be blocked separately.

Source: [Control installing and using new Outlook](https://learn.microsoft.com/en-us/microsoft-365-apps/outlook/get-started/control-install) (updated 2026-07-15)

### Dev Home

- Product docs: Dev Home is sunset (unsupported as of May 2025). [Dev Home (previous versions)](https://learn.microsoft.com/en-us/previous-versions/windows/dev-home/)
- **No solid Microsoft Learn article** documents `DevHomeUpdate` under `UScheduler_Oobe` as an admin API.
- **Community observation** (forums / blogs): delete `...\UScheduler_Oobe\DevHomeUpdate` to stop auto-install; keys may return after feature updates. Treat as unsupported / best-effort.

### Chat / consumer Teams

- Microsoft documents managing the **Chat taskbar icon** and uninstalling consumer Teams AppX packages: [Managing the Teams Chat icon on Windows 11](https://learn.microsoft.com/en-us/troubleshoot/windows-client/application-management/managing-teams-chat-icon-windows-11)
- **No solid primary source** ties Chat reinstall specifically to a named `UScheduler_Oobe\*` updater the way Outlook/`OutlookUpdate` is documented.
- Enterprise/Education **policy-based inbox app removal** can remove/block selected in-box Store apps while the policy list remains selected — **not applicable to Home** as a general WinMint default: [Policy-based in-box app removal](https://learn.microsoft.com/en-us/windows/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal)

### Practical split for WinMint

| App | Primary / supported | Community-only |
|-----|---------------------|----------------|
| New Outlook | Deprovision + remove `OutlookUpdate`; Win10 `BlockedOobeUpdaters` | Extending `BlockedOobeUpdaters` beyond `MS_Outlook` |
| Dev Home | App removal / sunset | Delete `DevHomeUpdate` |
| Chat | Unpin / uninstall AppX; Chat icon policies | Assumed Orchestrator parity |

Generic OOBE update download behavior (ZDP etc.) is separate: [Updates during OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/windows-updates-during-oobe-in-windows-11)

---

## 3. Edge ADMX — additional consumer noise policies

**Do not** remove Edge or WebView2. **Keep** Copilot page-context / Hubs sidebar available (leave `HubsSidebarEnabled` unset or enabled; do not rely on disabling the sidebar to hide Copilot — as of Edge 141, toolbar Copilot visibility is `Microsoft365CopilotChatIconEnabled`).

Sources:

- [HubsSidebarEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/hubssidebarenabled)
- [Microsoft365CopilotChatIconEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/microsoft365copilotchaticonenabled)
- Policy catalog entry points: [Configure Microsoft Edge with policy settings](https://learn.microsoft.com/en-us/deployedge/configure-microsoft-edge)

### Excluded from this list (already “typical”)

Shopping, Rewards, Startup Boost, NTP content, Workspaces, `SpotlightExperiencesAndRecommendations`, `ImportOnEachLaunch`, `AddressBarTrendingSuggest`, `PromotionalTabs`, `BingAdsSuppression`, `NewTabPageAppLauncher`.

### Useful additional noise-reduction policies (primary docs)

| Policy | Suggested polish value | Effect |
|--------|------------------------|--------|
| [HideFirstRunExperience](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/hidefirstrunexperience) | `1` | Skip first-run splash / FRE |
| [AutoImportAtFirstRun](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/autoimportatfirstrun) | `4` (`DisabledAutoImport`) | Skip FRE import section; no silent import |
| [ShowRecommendationsEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/showrecommendationsenabled) | `0` | Feature tips / coach marks / assistance notifications |
| [BackgroundModeEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/backgroundmodeenabled) | `0` | No keep-alive after last window closes |
| [EdgeCollectionsEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/edgecollectionsenabled) | `0` | Disable Collections |
| [GuidedSwitchEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/guidedswitchenabled) | `0` | No work/personal profile switch prompts |
| PersonalizationReportingEnabled | `0` | Reduce personalization / reporting surface (see Edge policy list) |
| AlternateErrorPagesEnabled | `0` | Disable web-service error / suggestion pages |
| MicrosoftEdgeInsiderPromotionEnabled | `0` | Insider promo UI |
| AllowGamesMenu | `0` | Games menu |
| ComposeInlineEnabled | `0` | Inline compose (writing assistance UI) — **distinct from** Copilot sidebar page-context |
| WebWidgetAllowed | `0` | Web widget |
| EdgeFollowEnabled | `0` | Follow / shopping-adjacent follow surface |
| EdgeEnhanceImagesEnabled | `0` | Image enhancement promo feature |
| EdgeAssetDeliveryServiceEnabled | `0` | Asset delivery service |
| CryptoWalletEnabled / WalletDonationEnabled | `0` | Wallet promo surfaces |
| UserFeedbackAllowed | `0` | Feedback prompts |
| DiagnosticData | `0` | Edge diagnostic upload level (policy enum; confirm desired privacy stance) |
| EdgeUpdate `CreateDesktopShortcutDefault` | `0` | Avoid new desktop shortcuts on Edge updates |

Registry root: `HKLM\SOFTWARE\Policies\Microsoft\Edge` (and `EdgeUpdate` where noted). Full index: search [Microsoft Edge - Policies](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies) on Learn.

### Explicitly leave alone for Copilot page-context

- Do **not** set `HubsSidebarEnabled=0` if sidebar Copilot must remain available.
- Prefer leaving `Microsoft365CopilotChatIconEnabled` unset (user toggle) unless intentionally hiding the toolbar icon for Entra Edge for Business profiles.
- Keep page-context Copilot policies enabled / unset; WinMint’s AI module already distinguishes “imposed” Edge AI APIs from page-context chat.

---

## 4. Start / taskbar pins (Windows 11)

### Documented mechanisms

| Mechanism | What it configures | Primary docs |
|-----------|-------------------|--------------|
| **ConfigureStartPins** (CSP / GPO) | Start pinned list via JSON (`LayoutModification.json` / export) | [Start Policy CSP — ConfigureStartPins](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-start), [Start policy settings](https://learn.microsoft.com/en-us/windows/configuration/start/policy-settings), [Customize the Start layout](https://learn.microsoft.com/en-us/windows/configuration/start/layout) |
| **StartLayout** CSP/GPO + `LayoutModification.xml` | Legacy/full Start layout XML; on Win11 also carries taskbar via `CustomTaskbarLayoutCollection` | Same Start layout docs; [Taskbar pinned apps](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps) |
| **OEM `TaskbarLayoutModification.xml` + `LayoutXMLPath`** | Image-time taskbar (OEM; up to 3 *additional* pins in OEM doc; `PinListPlacement="Replace"` patterns in enterprise XML) | [Customize the Windows 11 Taskbar (OEM)](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-the-windows-11-taskbar) |
| **Default User `...\Shell\LayoutModification.xml`** | Widely used for new profiles | **Not** the primary enterprise CSP path; community/deployment blogs. Prefer CSP/GPO when available. |
| **Import-StartLayout** | — | **No longer supported on Windows 11** for taskbar (explicit Learn note) |

JSON pin keys (Start): `packagedAppId`, `desktopAppLink`, `desktopAppId`, etc. Optional `applyOnce` (24H2 + KB5062660): apply pins once, then allow user changes.

GPO for ConfigureStartPins: Start Menu and Taskbar → Configure Start Pins; **GPO availability starts 24H2 + KB5062660**.

### Timing / reapply caveats (documented)

From [Configure the applications pinned to the taskbar](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps):

| Delivery | When layout reapplies | User unpin behavior |
|----------|----------------------|---------------------|
| **CSP** | ~every 8 hours / ConfigRefresh | By default, policy pins restore; with **PinGeneration** (24H2 KB5060829 / 23H2 KB5060826), unpin can stick until generation bumps |
| **Provisioning package** | **Each `explorer.exe` restart** | Overwrites user changes on reapply |
| **GPO** | When GPO changes | Same overwrite semantics as Start docs |

Other caveats:

- Apps not yet provisioned for the user → pin **missing** (icon omitted), not deferred.
- OEM `LayoutXMLPath` must be present **before specialize**; FirstLogonCommands alone cannot set it unless the image is generalized afterward.
- Start `applyOnce` / taskbar `PinGeneration` require specific 24H2/23H2 cumulative updates; older builds ignore or mis-apply.
- Policy Start layout historically reapplies at sign-in and can wipe user pin changes unless `applyOnce` is used.
- First logon + explorer restart after FirstLogon agent work: expect PPKG/Default-User XML pins to re-evaluate; schedule pin work after target apps (e.g. Terminal) are installed, or use policy that reapplies once apps exist.

### Practical recommendation for WinMint FirstLogon

1. Prefer **user-scoped** pin application after packages exist (Terminal, browser, etc.).
2. Avoid relying on `Import-StartLayout`.
3. If using XML under Default User or a provisioning package, treat **explorer restart** as a reapply event.
4. For managed SKUs, `ConfigureStartPins` + taskbar XML via StartLayout CSP is the supported long-term path; Home builds may need Default User / per-user shell layout instead of Intune CSP.

---

## Source quality summary

| Topic | Primary coverage | Gaps |
|-------|------------------|------|
| Winget repair / sources / scope | Strong (Learn + returnCodes.md) | Package IDs for App Installer/WebView2/Terminal are community-repo conventions, not a single Learn “polish order” page |
| OOBE rehydration | Strong for **Outlook**; weak for Dev Home / Chat Orchestrator keys | DevHomeUpdate / Chat UScheduler = community |
| Edge ADMX extras | Strong (per-policy Learn pages) | — |
| Start/taskbar pins | Strong for CSP/GPO/OEM | Default User Shell XML timing mostly deployment folklore |
