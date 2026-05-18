# Windows Debloat Strategy

Status: design reference  
Last researched: 2026-04-30

This document is the working strategy for the WinMint Windows baseline. The goal is not to create the smallest possible Windows image. The goal is to turn official Windows media into a fast, quiet, serviceable, Linux-style developer workstation with WSL as a first-class runtime. WinMint is WSL2-first: Windows hosts the hardware, UI, security, package bootstrap, and desktop shell; Linux is the default development runtime.

## Core Position

WinMint should optimize the system by removing user-hostile behavior, consumer payloads, ads, AI surfaces, and setup friction. It should not win benchmarks by breaking Windows servicing, security, networking, or WSL.

Good debloat:

- Removes provisioned consumer apps before the first user is created.
- Audits the live install after first logon to catch drift without uninstalling arbitrary user-space software.
- Uses policy and supported registry settings where possible.
- Keeps Windows Update, Defender, Firewall, Store infrastructure, App Installer, winget, WebView2, WSL, Hyper-V networking, and IPv6 working.
- Produces an auditable manifest of removed, changed, installed, and downloaded items.
- Can survive feature updates without needing a full reinstall.

Bad debloat:

- Deletes the component store, disables updates, disables Defender, disables networking infrastructure, or blindly disables services.
- Blocks Microsoft endpoints with hosts-file style hacks.
- Runs generated Win32 uninstall lists or registry-key cleanup as a first-logon policy.
- Deletes scheduled tasks and system packages without a servicing test.
- Treats all privacy traffic as equally harmful even when the cost is broken security, updates, diagnostics, Store, or WSL.

## External Tool Lessons

| Tool | Useful lesson | Do not copy |
|------|---------------|-------------|
| Tiny11Builder | Offline AppX removal, single-edition export, unattended setup, serviceable/default path. | Tiny11 Core-style removal of WinSxS, Windows Update, WinRE, or other serviceability foundations. |
| CTT WinUtil | Good catalog of common tweaks and a useful split between essential and cautionary tweaks. | Presenting a huge choice matrix, disabling hibernation/services by default, IPv6/Teredo removal, Edge removal, and visual "best performance" defaults. |
| BAREbONE1 / barebones11-style scripts | Useful as an aggressive removal inventory for review. | Removing Edge/WebView-adjacent pieces, Quick Assist, Phone Link, Maps, To Do, language/speech/OCR, and using Compact OS as a default. |
| Windows X-Lite / Optimum11 | Clear edition split and resource-use goal. | Prebuilt opaque ISO trust model, optional security/update platform, and "lowest resources" as the top product goal. |
| Win11Debloat | Lightweight PowerShell, Audit Mode support, admin/user targeting, and focused bloat/privacy categories. | Running every privacy/cleanup toggle as a default ISO policy. |
| Sparkle | Modern tweak catalog, restore-point framing, documented tweak pages, selective app removal, and useful utilities/app-installer grouping. | Defender RTP/Core Isolation toggles, Ultimate Performance, global service-manual mode, hibernation/location disables, or gaming/NVIDIA/network tweaks as workstation defaults. |
| Winhance / UnattendedWinstall | Native-feeling UX, restore point mindset, unattended install coverage, broad modern Windows cleanup categories. | High-choice model and broad toggles that are useful in a repair tool but wrong for WinMint' opinionated image. |
| O&O ShutUp10++ | Recommendation tiers are useful: some privacy settings are low-risk, others are convenience/security tradeoffs. | "Apply everything" privacy posture. Windows cannot be made truly private without breaking useful Windows behavior. |
| AtlasOS / ReviOS | Performance-focused custom Windows projects prove there is demand for a cleaner OS personality. | Removing or disabling security, restore/reset, updates, or feature updates as a normal workstation default. |
| Sophia Script / SophiApp / privacy.sexy | Script transparency, documented methods, reversibility, and current-state detection are valuable references. | Exposing hundreds of switches to the user. WinMint should decide, test, and document. |

## Current WinMint Audit

| Area | Current state | Recommendation |
|------|---------------|----------------|
| AppX cleanup | Curated provisioned package removal in `src/WinMint/Private/Catalog.ps1` and `src/WinMint/Private/Image/Staging.ps1`. | Keep. This is the right kind of image-level debloat. |
| Windows Update | `src/WinMint.Setup/SetupComplete.ps1` restores BITS, wuauserv, UsoSvc, and WaaSMedicSvc. | Keep. This is a strong guardrail against over-debloat. |
| WSL platform | WSL, Virtual Machine Platform, and OpenSSH are enabled in the image. | Keep. These are core workstation features. |
| Edge | Edge first-run/startup/background/promo behavior is policy-disabled. | Keep. Do not remove WebView2 or Edge runtime infrastructure. |
| OneDrive | Fully removed during setup/first logon; sync policies stay blocked and known folders are forced back to local profile paths. | Keep. Users who want OneDrive can reinstall it after setup. |
| Game Bar / Xbox | Xbox packages and GameDVR are removed/disabled. | Keep. This is low-value background noise for this image. |
| Recall / Copilot | Recall is removed when detected; Copilot and WebExperience are removed/deprovisioned. | Keep, but preserve the list as an AI-removal policy surface because Microsoft keeps moving these components. |
| WPBT | WPBT execution disabled. | Keep. This prevents OEM firmware payload injection. |
| BitLocker auto-encryption | Auto-encryption is prevented; active BitLocker protection is logged and preserved. | Keep. Prevent surprise encryption, but do not fight a deliberate user/admin encryption choice. |
| Hardware bypass | TPM/Secure Boot/RAM/CPU/storage bypasses are an explicit advanced option and default off. | Keep guarded. Unsupported hardware bypass must stay opt-in and covered by static tests. |
| Compact OS | The unattend does not force Compact OS. | Keep default non-compact. Compact saves disk but can add CPU overhead; reserve it for an explicit tiny-image mode. |
| `/ResetBase` | Image save runs normal `StartComponentCleanup` without `/ResetBase`. | Keep. Preserve rollback and serviceability by default; reserve ResetBase for an explicit tiny-image mode. |
| Language feature removal | Non-selected language packages are removed. | Keep narrowly, but preserve all selected UI/input/system locales and test feature update behavior. |
| AutoLogon | Passworded builds use `LogonCount=1`; FirstLogon clears credentials and registers retry state. | Keep guarded. One automatic logon is enough; static tests must prevent effectively infinite AutoLogon. |
| Maintenance task | Post-update policy/AppX drift control. | **On ice:** WinMint does not stage a maintenance script, scheduled task, background service, or other recurring drift-control payload on the installed system. After installation, the user manages their machine. |
| Live install audit | `Audit-LiveInstall.ps1` records provisioned/installed AppX, Win32 uninstall entries, and Tier 0 platform health during FirstLogon. | Keep non-destructive and opt-in. This is a scout and validator, not a live debloater; harvested Win32 lists must be manually classified before changing WinMint policy. |

## Decision Tiers

### Tier 0: Must Preserve

These are part of the platform. WinMint should not remove or disable them by default.

| Preserve | Reason |
|----------|--------|
| Windows Update, BITS, UsoSvc, WaaSMedicSvc | Security updates, Store dependencies, feature update health. |
| Defender, SmartScreen, Security Center, Firewall | Security matters more than small background savings. |
| Store infrastructure, Desktop App Installer, winget, MSIX/AppX services | Package installation and updates for developer tools. |
| WebView2 / Edge runtime infrastructure | Many Windows and third-party apps depend on it. |
| WSL, Virtual Machine Platform, Hyper-V networking, HNS, ICS dependencies, IPv6 | WSL2, VPN, localhost, and modern networking. |
| Windows Error Reporting local dump ability | Developers need crash dumps and diagnostics. |
| UAC | Do not normalize permanently elevated desktop behavior. |
| Core fonts, input, IME, language, accessibility foundations | Removing these causes user-visible breakage. |
| WinRE / recovery / reset foundations | Trust and repairability matter. |
| Component store / WinSxS | Required for servicing, feature changes, updates, and repair. |

### Tier 1: Apply By Default

These should be part of WinMint Core because they remove noise without compromising the workstation.

| Category | Default action |
|----------|----------------|
| Consumer AppX | Remove Clipchamp, News, Weather, Whiteboard, 3D Viewer, Mixed Reality Portal, Xbox apps, Solitaire, Feedback Hub, Get Help, Teams consumer, Outlook new, Dev Home, Power Automate, Microsoft Family, People, Office Hub, Calculator, Quick Assist, Maps, Microsoft To Do, **Zune** media apps (`Microsoft.ZuneMusic` / `Microsoft.ZuneVideo`), **OneNote** (`Microsoft.Office.OneNote`), **Remote Desktop** Store client (`Microsoft.RemoteDesktop*`), and **best-effort trial/OEM provisioned** prefixes (McAfee, Norton, ExpressVPN, Surfshark, AVG, Avast, KasperskyLab, Dolby trials, CCleaner). Preserve **Phone Link** / **Cross Device**, plus **Camera**, **Sound Recorder**, **Sticky Notes**, **Clock/Alarms**, and **Notepad** (explicit invariant tests). |
| AI surfaces | Disable/remove Copilot, Recall, Windows AI data analysis, AI-first search/sidebar hooks, and AI provisioned packages where serviceable. |
| Advertising/content | Disable Windows consumer features, soft landing, suggested apps, cloud optimized content, advertising ID, tailored experiences, tips, and Start recommendations. |
| Search noise | Disable Start menu Bing/web search and search highlights; keep local search/indexing functional. |
| Edge noise | Hide first-run, disable startup boost/background mode, disable recommendations/promos/personalization reporting. |
| OneDrive pressure | Uninstall OneDrive, remove setup binaries/residue, disable personal sync and autostart, hide Explorer integration, and keep known folders local. |
| Xbox/GameDVR | Remove Xbox packages and disable Game Bar/GameDVR overlays. |
| Explorer/dev QoL | Show file extensions, show hidden files, enable long paths, enable End Task on taskbar, set sane context/menu defaults. |
| Setup privacy | Keep `ProtectYourPC=3`, hide Microsoft account screens, keep Wi-Fi OOBE visible so first-logon automation has network. |
| OEM payloads | Disable WPBT, Razer-style auto-installers, and known vendor app injection paths where policy exists. |
| Setup cleanup | Remove copied unattend credentials and setup residue after install. |

### Tier 2: Conditional Or Experimental

These may be good, but need measurement or a clear hardware/workflow condition.

| Candidate | Why it is tempting | Risk / guardrail |
|-----------|--------------------|------------------|
| Disable DiagTrack / telemetry services | Reduces telemetry process activity. | Test Windows Update, Store, Defender, reliability monitor, and Settings. Prefer policy before service disabling. |
| Disable background apps globally | Can reduce idle noise. | Can break notifications and Store app behavior. Consider only after AppX cleanup leaves few apps. |
| Windows Search tuning | SearchIndexer can be noisy. | Do not disable local search or the Search service. **Flow Launcher + Everything** and **Raycast** are opt-in launcher choices; they complement Start/Settings search rather than replacing the platform indexer. |
| Storage Sense defaults | Can keep the system clean. | Do not auto-delete Downloads or developer artifacts. |
| Hibernation / Fast Startup | Fast Startup can cause dual-boot/WSL/driver edge cases. | **WinMint does not disable hibernation**—respect Windows and OEM power defaults (especially on laptops). Treat disabling **Fast Startup** as an optional explicit policy if needed; do not ship hibernate-off as a default. |
| Delivery Optimization | Peer download/upload can be unwanted. | Do not break updates. Prefer LAN-only or bandwidth-limited behavior over disabling update delivery mechanisms. |
| Print stack | Core printing and Print to PDF stay. | **WinMint Core** removes optional **Windows Fax and Scan** (`Print.Fax.Scan` capability only). Do not disable Print Spooler or remove drivers by default. XPS *Viewer* remains a separate optional removal (viewing XPS files; unrelated to physical printers). |
| Location / Maps / Sensors | Privacy win. | Time zone, hardware sensors, and app permissions can behave strangely. Disable app access first, not services. |
| Optional Features / Capabilities | Can reduce image footprint. | Remove only obvious non-core features and test WU/feature update. Preserve OpenSSH, WSL, .NET, language/input, Windows client basics. |
| Defender exclusions | Can greatly improve Node/Rust/Python build performance. | Folder exclusions are security holes. Prefer Dev Drive performance mode over broad exclusions. |
| Dev Drive | Real developer performance feature using ReFS and Defender performance mode for **Windows-hosted** trees. | Not interchangeable with WSL2: the Linux distro stays in its **WSL VHDX**; Dev Drive cannot host that layout. Offer Dev Drive only as an explicit disk step for Windows-native work; WSL-first repos remain in the distro filesystem. |
| WSL `.wslconfig` | `autoMemoryReclaim`, `dnsTunneling`, `sparseVhd`, and networking modes can improve dev ergonomics. | Mirrored networking can interact poorly with VPNs/firewalls. Use conservative defaults and document. |

### Tier 3: Reject By Default

These are common in debloat/optimizer circles but should not be WinMint defaults.

| Reject | Reason |
|--------|--------|
| Disable Defender, Firewall, SmartScreen, or Security Center | Security regression for tiny performance gain. |
| Disable Core Isolation / HVCI by default | Weakens platform security; not justified for a general developer workstation. |
| Disable Windows Update or WaaSMedic | Turns a workstation into a disposable image. |
| Remove WinSxS / use Core-style component removal | Breaks serviceability and feature changes. |
| Remove WebView2 or Edge runtime hard | Breaks modern Windows app assumptions. |
| Disable IPv6 | Breaks modern networking, WSL, VPN, and future assumptions. |
| Disable Hyper-V/HNS/ICS networking services blindly | Breaks WSL2 and modern virtualization networking. |
| Set broad service groups to Manual | Optimizer-style service flips break hardware, Store, updates, security, and networking in non-obvious ways. |
| Disable AppXSVC, ClipSVC, InstallService, Store broker services | Breaks winget/Store/MSIX plumbing. |
| Hosts-file blocks for Microsoft endpoints | Hard to audit; breaks Store, updates, activation, certificates, Defender, or sign-in paths. |
| Disable all scheduled tasks | Breaks maintenance, updates, servicing, certificates, and diagnostics. |
| Disable crash reporting entirely | Developers need local dump generation. Disable upload prompts if needed, not the local mechanism. |
| Ultimate Performance by default | Bad laptop/thermal default; not a universal performance improvement. |
| Disable dynamic ticking or apply timer folklore tweaks | Gaming-only tradeoff with battery/sleep/latency risks; requires measurement per hardware class. |
| Disable CPU security mitigations | Not acceptable for a general workstation baseline. |
| Visual effects "best performance" | Makes Windows feel dated for negligible benefit on modern machines. |
| Registry cleaners | No meaningful performance upside; high breakage risk. |

## Additional Ideas To Consider

### 1. Dev Drive As A First-Class Workstation Feature

Most debloat tools focus on removing things. For a developer workstation, adding the right storage model may matter more. Windows Dev Drive uses ReFS and Defender performance mode for developer workloads, and Microsoft documents it as a performance feature for code, package caches, and build output.

Potential WinMint direction:

- Do not silently repartition for Dev Drive.
- Add a future "Developer workspace" step only when disk layout is already being chosen.
- Offer either a real partition or a mounted VHDX-backed Dev Drive.
- Route **Windows-native** code, package caches, and build output there when the user opts in.
- Keep WSL Linux files inside the WSL VHD (`\\wsl$\...` / ext4), not on `/mnt/c` on a Dev Drive, unless the user knowingly accepts cross-OS IO tradeoffs.

### 2. WSL2-First Performance Profile

WinMint should treat WSL as the primary Linux layer, not an optional toy. The Developer profile defaults to Ubuntu LTS, but the user can opt out, choose Debian, Arch, Fedora, or select multiple distributions. A custom distro selection must never force Ubuntu back in.

Linux projects should live under `/home/<user>/code` inside the WSL filesystem. Windows-native projects and package caches can use a future Dev Drive option, but Linux source should not default to `/mnt/c/...`.

Candidate defaults:

```ini
[wsl2]
networkingMode=nat
dnsTunneling=true
autoProxy=true
localhostForwarding=true
firewall=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

Current decision:

- Use `gradual` for `autoMemoryReclaim`; it returns cache steadily without the sharper behavior of immediate cache drops.
- Keep mirrored networking out of Core. It is useful for some VPN/localhost/LAN cases, but it changes firewall/network behavior. Core uses `networkingMode=nat`.
- Container runtimes are intentionally outside the WinMint UI. The baseline should keep WSL healthy and leave distro-level container setup to the user.

### 3. Replace Service Tweaking With A Service Budget

Instead of "disable services," define a measured service budget:

- Record running services on first clean boot.
- Flag unexpected third-party/OEM services.
- Keep a denylist for obvious consumer/OEM/background services.
- Keep an allowlist for platform services WinMint never touches.
- Compare stock ISO vs WinMint in the build report.

This is more reliable than copying service-disable lists from gaming debloat scripts.

### 4. Scheduled Task Inventory

Scheduled tasks often matter more than services for idle noise. WinMint should inventory them and only disable narrow categories:

- Feedback prompts.
- Consumer content refresh.
- Advertising/suggestions.
- App compatibility telemetry where policy supports it.
- OEM app installers.

Do not blanket-disable servicing, certificate, Defender, update, disk health, or maintenance tasks.

### 5. AI Removal Surface

Windows AI components are moving targets. WinMint should maintain a small AI removal policy layer:

- Disable WindowsAI policy values.
- Remove provisioned Copilot/Recall/WebExperience packages where safe.
- Disable Recall optional feature when present.
- Disable Edge Copilot/sidebar/promo policies.
- Disable AI additions in inbox apps only when package identity is clear and reinstall path is known.

Avoid deleting servicing packages unless tests prove updates and repair still work.

### 6. Developer Defender Strategy

The usual developer answer is to add broad Defender exclusions for `node_modules`, package caches, WSL VHDs, and source folders. That is fast but not clean.

Preferred order:

1. Use Dev Drive performance mode for Windows-hosted source.
2. Keep Linux source inside WSL's native filesystem for Linux workloads.
3. Add narrow, documented exclusions only for generated build/cache directories.
4. Never exclude the whole user profile, whole system drive, or downloads folder.

### 7. First-Logon Contract

The first-logon agent should have a contract:

- It may install selected shell/dev layers.
- It must log every action.
- It must be rerunnable.
- It must clean temporary credentials and AutoLogon values.
- It must not fight the user after success.

The current default is `LogonCount=1`; keep the static guard that prevents effectively infinite AutoLogon from returning.

### 8. Rollback Kit

Every build should produce a rollback/audit folder next to the ISO:

- Removed AppX package list.
- Registry policy manifest.
- Optional feature/capability removals.
- Driver injection list.
- FirstLogon profile.
- Download URLs and hashes.
- Generated `.reg` undo snippets where practical.

This is how WinMint answers the trust problem without exposing a giant UI.

### 9. Real Performance Baseline

WinMint should publish its own numbers instead of inheriting claims from optimizer tools.

Measure in a repeatable VM:

- Fresh boot idle RAM after five minutes.
- Process count.
- Running service count.
- Scheduled tasks disabled.
- Installed provisioned AppX count.
- Time from first desktop to agent completion.
- `winget source update`.
- Windows Update scan.
- Defender update.
- Store/App Installer health.
- WSL distro install and first launch.
- WebView2-dependent app launch.

No tweak should graduate to Core unless it passes this matrix.

## Near-Term Backlog

| Priority | Change | Reason |
|----------|--------|--------|
| P0 | Keep serviceability guardrails in `tests\contract\Test-ProfileInvariants.ps1`. | Prevent `/ResetBase`, Compact OS, broad hardware bypass, or infinite AutoLogon from returning. |
| P1 | Add a debloat/tweak manifest report with risk and reversibility metadata. | Trust and auditability; this borrows Sparkle/Sophia's best UX idea without inheriting their whole tweak matrix. |
| P1 | Define a protected platform allowlist. | Prevent future over-debloat from breaking WSL/update/security. |
| P1 | Expand privacy baseline to include Start/Search/content/advertising/default-user keys in one source of truth. | More complete O&O/WinUtil-style coverage without UI bloat. |
| P1 | Add AI removal layer tests. | Copilot/Recall surfaces keep changing. |
| P2 | Investigate DiagTrack service state with smoke tests. | Potential idle/noise win, but needs evidence. |
| P2 | Add optional mirrored-networking control for WSL. | Useful for some VPN/LAN workflows; not safe enough for Core default. |
| P2 | Add Dev Drive planning/design. | High-value developer performance feature that most debloat tools ignore. |
| P3 | Scheduled task inventory and narrow disable list. | Better idle optimization than blind service disabling. |
| P3 | Optional "tiny image" mode with ResetBase/Compact tradeoffs clearly labeled. | Useful for private forks, not default. |

## Source References

- Tiny11Builder: https://github.com/ntdevlabs/tiny11builder
- BAREbONE1: https://github.com/Miustone/BAREBoNE1
- CTT WinUtil tweaks: https://winutil.christitus.com/dev/tweaks/
- CTT Win11 Creator: https://winutil.christitus.com/userguide/win11creator/
- Win11Debloat: https://github.com/Raphire/Win11Debloat
- Sparkle docs: https://docs.getsparkle.net/
- Sparkle GitHub: https://github.com/parcoil/sparkle
- Winhance: https://github.com/memstechtips/Winhance
- UnattendedWinstall: https://github.com/memstechtips/UnattendedWinstall
- O&O ShutUp10++: https://www.oo-software.com/en/shutup10
- AtlasOS: https://atlasos.net/
- Atlas docs: https://docs.atlasos.net/getting-started/install/install-playbook/
- Windows X-Lite / Optimum 11: https://windowsxlite.com/25H2/
- ReviOS docs: https://revi.cc/docs/features
- Sophia Script: https://github.com/farag2/Sophia-Script-for-Windows
- SophiApp: https://github.com/Sophia-Community/SophiApp
- privacy.sexy: https://github.com/undergroundwires/privacy.sexy
- RemoveWindowsAI: https://github.com/zoicware/RemoveWindowsAI
- Microsoft DISM AppX servicing: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options
- Microsoft Windows diagnostic data policy: https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization
- Microsoft Delivery Optimization: https://learn.microsoft.com/en-ca/windows/deployment/do/waas-delivery-optimization-reference
- Microsoft WSL configuration: https://learn.microsoft.com/en-us/windows/wsl/wsl-config
- Microsoft WSL filesystem guidance: https://learn.microsoft.com/en-us/windows/wsl/filesystems
- Microsoft Dev Drive: https://learn.microsoft.com/en-us/windows/dev-drive/
