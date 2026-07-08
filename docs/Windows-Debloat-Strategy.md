# Windows Debloat Strategy

Status: design reference (not the spec — `AGENTS.md` + contract tests + code are authoritative)  
Last researched: 2026-04-30  
Last reconciled to shipped behavior: 2026-06-13

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
| BAREbONE1 / barebones11-style scripts | Useful as an aggressive removal inventory for review. | Removing Edge/WebView-adjacent pieces, Phone Link / Cross Device, language/speech/OCR, and using Compact OS as a default. Small reinstallable inbox apps are not platform dependencies. |
| Windows X-Lite / Optimum11 | Clear edition split and resource-use goal. | Prebuilt opaque ISO trust model, optional security/update platform, and "lowest resources" as the top product goal. |
| Win11Debloat | Lightweight PowerShell, Audit Mode support, admin/user targeting, and focused bloat/privacy categories. | Running every privacy/cleanup toggle as a default ISO policy. |
| Sparkle | Modern tweak catalog, restore-point framing, documented tweak pages, selective app removal, and useful utilities/app-installer grouping. | Defender RTP/Core Isolation toggles, Ultimate Performance, global service-manual mode, hibernation/location disables, or gaming/NVIDIA/network tweaks as workstation defaults. |
| Winhance / UnattendedWinstall | Native-feeling UX, restore point mindset, unattended install coverage, broad modern Windows cleanup categories. | High-choice model and broad toggles that are useful in a repair tool but wrong for WinMint's opinionated image. |
| O&O ShutUp10++ | Recommendation tiers are useful: some privacy settings are low-risk, others are convenience/security tradeoffs. | "Apply everything" privacy posture. Windows cannot be made truly private without breaking useful Windows behavior. |
| AtlasOS / ReviOS | Performance-focused custom Windows projects prove there is demand for a cleaner OS personality. | Removing or disabling security, restore/reset, updates, or feature updates as a normal workstation default. |
| Sophia Script / SophiApp / privacy.sexy | Script transparency, documented methods, reversibility, and current-state detection are valuable references. | Exposing hundreds of switches to the user. WinMint should decide, test, and document. |

## Current WinMint Audit

| Area | Current state | Recommendation |
|------|---------------|----------------|
| AppX cleanup | Curated provisioned package removal is cataloged in `config/appx-removal.json` and serviced by the image pipeline. DMA-on defaults keep broad third-party/OEM prefixes candidate-only. | Keep. This is the right kind of image-level debloat, but the normal Home/DMA path should stay slimmer than legacy community removal lists. |
| Windows Update | `src/runtime/setup/SetupComplete.ps1` restores BITS, wuauserv, UsoSvc, and WaaSMedicSvc. | Keep. This is a strong guardrail against over-debloat. |
| WSL platform | WSL, Virtual Machine Platform, and OpenSSH are enabled in the image. | Keep. These are core workstation features. |
| Edge | `-KeepEdge` keeps Edge installed and debloated. Without `-KeepEdge`, removal intent is serviced through the normal supported Edge app uninstaller exposed by DMA setup. | Treat Edge like a normal removable browser app on DMA builds. If the supported uninstaller leaves Edge present, report that as incomplete rather than patching policy files or applying hidden switches. Never patch `IntegratedServicesRegionPolicySet.json`. **Never** remove WebView2 / Edge *runtime* infrastructure. |
| OneDrive | Fully removed during setup/first logon; sync policies stay blocked and known folders are forced back to local profile paths. | Keep. Users who want OneDrive can reinstall it after setup. |
| Game Bar / Xbox | Xbox packages and GameDVR are removed/disabled; Game Bar protocols are redirected to a no-op handler to avoid Store prompts after removal. | Keep. This is low-value background noise for this image. |
| Recall / Copilot | Recall is removed when detected; Copilot and WebExperience are removed/deprovisioned. | Keep, but preserve the list as an AI-removal policy surface because Microsoft keeps moving these components. |
| WPBT | WPBT execution disabled. | Keep. This prevents OEM firmware payload injection. |
| BitLocker auto-encryption | Auto-encryption is prevented; active BitLocker protection is logged and preserved. | Keep. Prevent surprise encryption, but do not fight a deliberate user/admin encryption choice. |
| Hardware bypass | TPM/Secure Boot/RAM/CPU/storage bypasses are an explicit advanced option and default off. | Keep guarded. Unsupported hardware bypass must stay opt-in and covered by static tests. |
| Compact OS | The unattend does not force Compact OS. | Keep default non-compact. Compact saves disk but can add CPU overhead; reserve it for an explicit tiny-image mode. |
| `/ResetBase` | Image save runs normal `StartComponentCleanup` without `/ResetBase`. | Keep. Preserve rollback and serviceability by default; reserve ResetBase for an explicit tiny-image mode. |
| Language feature removal | Non-selected language packages are removed. | Keep narrowly, but preserve all selected UI/input/system locales and test feature update behavior. |
| AutoLogon | Passworded unattended local-account builds use bounded unattend AutoLogon, then FirstLogon persists autologon only until the agent succeeds so rebooting modules can resume. FirstLogon clears credentials and retry state on success. | Keep guarded. Persistent autologon is an install-time recovery mechanism only; static tests must prevent it from surviving a successful install. |
| Maintenance task | Post-update policy/AppX drift control. | **On ice:** WinMint does not stage a maintenance script, scheduled task, background service, or other recurring drift-control payload on the installed system. After installation, the user manages their machine. |
| Live install audit | `Audit-LiveInstall.ps1` records provisioned/installed AppX, Win32 uninstall entries, Tier 0 platform health, and debug-only service/task/startup inventory during FirstLogon. | Keep non-destructive and opt-in. This is a scout and validator, not a live debloater; harvested inventory must be manually classified before changing WinMint policy. The only residual exception is the explicit diagnostic report under `ProgramData\WinMint\Logs` when the user selected live install audit. |

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

Reinstallable inbox apps such as Calculator, Sound Recorder, Sticky Notes, Quick Assist, Maps, To Do, OneNote, the Remote Desktop Store client, and legacy media apps are not Tier 0. Removing them does not gimp the operating system: the Store/App Installer platform remains intact, so users can reinstall any of these apps after setup if they want them.

### Tier 1: Apply By Default

These should be part of WinMint Core because they remove noise without compromising the workstation.

| Category | Default action |
|----------|----------------|
| Consumer AppX | Remove Clipchamp, News, Weather, Whiteboard, 3D Viewer, Mixed Reality Portal, Xbox apps, Solitaire, Feedback Hub, Get Help, Teams consumer, Outlook new, Dev Home, Power Automate, Microsoft Family, People, Office Hub, Calculator, Quick Assist, Sound Recorder, Sticky Notes, Maps, Microsoft To Do, **Zune** media apps (`Microsoft.ZuneMusic` / `Microsoft.ZuneVideo`), **OneNote** (`Microsoft.Office.OneNote`), **Remote Desktop** Store client (`Microsoft.RemoteDesktop*`), **Phone Link / Cross Device** unless `-PhoneLink` / `features.phoneLink` is selected, and **best-effort trial/OEM provisioned** prefixes (McAfee, Norton, ExpressVPN, Surfshark, AVG, Avast, KasperskyLab, Dolby trials, CCleaner). Also remove the **Windows Media Player Legacy** capability (`Media.WindowsMediaPlayer`) and **Extended Wallpapers** capability globally. These are reinstallable Store/inbox apps, not platform dependencies. Preserve **Camera**, **Clock/Alarms**, **Notepad**, Store infrastructure, Desktop App Installer, and WebView2. |
| AI surfaces | Remove Recall and imposed Copilot app/shell surfaces; disable Notepad AI, web AI APIs, and app access to system/generative AI models. Keep explicit app-local tools such as Edge Copilot page-context chat, Paint AI, Click to Do, and the local Settings agent. |
| Advertising/content | Disable Windows consumer features, soft landing, suggested apps, cloud optimized content, advertising ID, tailored experiences, tips, Start recommendations, backup/setup pressure prompts, and Spotlight promotional surfaces. |
| Search noise | Disable Start menu Bing/web search and search highlights; keep local search/indexing functional. |
| Edge noise | Hide first-run, disable startup boost/background mode, disable recommendations/promos/personalization reporting. |
| OneDrive pressure | Uninstall OneDrive, remove setup binaries/residue, disable personal sync and autostart, hide Explorer integration, and keep known folders local. |
| Xbox/GameDVR | Remove Xbox packages, disable Game Bar/GameDVR overlays, and no-op Game Bar protocols to avoid Store prompts after removal. |
| Developer package managers | Keep winget/msstore for GUI/system apps and install Scoop as the user-local owner for developer CLI tools. MinGit is installed through Scoop as baseline Windows-host Git plumbing; Starship is installed through Scoop with the `nerd-font-symbols` preset; selected Neovim is Scoop-owned. ARM64 builds prefer native ARM64/aarch64 package assets where package-manager metadata supports them; amd64 builds use default package-manager architecture selection. |
| Explorer/dev QoL | Show file extensions, show hidden files, keep Explorer Home as the launch page, hide Gallery, enable long paths (`longpaths-policy`), enable End Task on the taskbar right-click menu (`taskbar-endtask`, always on), hide noisy taskbar/tray affordances, keep local clipboard history on with cloud upload off, and set sane context/menu defaults. |
| Setup privacy | Keep `ProtectYourPC=3`. Fully unattended local-account installs hide OOBE network/account friction and use the profile computer name directly; Microsoft OOBE account installs leave the normal network/account pages visible. |
| OEM payloads | Disable WPBT, Razer-style auto-installers, driver companion co-installers, and known vendor app injection paths where policy exists. Windows Update driver delivery remains enabled. |
| Setup cleanup | Remove copied unattend credentials and setup residue after install. |
| Final restore point | After successful FirstLogon cleanup, enable System Restore for the system drive and create a `WinMint post-install complete` restore point. |

### Tier 2: Conditional Or Experimental

These may be good, but need measurement or a clear hardware/workflow condition.

| Candidate | Why it is tempting | Risk / guardrail |
|-----------|--------------------|------------------|
| Disable DiagTrack / telemetry services | Reduces telemetry process activity. | Test Windows Update, Store, Defender, reliability monitor, and Settings. Prefer policy before service disabling. |
| Disable background apps globally | Can reduce idle noise. | Can break notifications and Store app behavior. Consider only after AppX cleanup leaves few apps. |
| Windows Search tuning | SearchIndexer can be noisy. | Do not disable local search or the Search service. Raycast is an opt-in launcher choice; it complements Start/Settings search rather than replacing the platform indexer. |
| Storage Sense defaults | Can keep the system clean. | Do not auto-delete Downloads or developer artifacts. |
| Hibernation / Fast Startup / power plan | Fast Startup can cause dual-boot/WSL/driver edge cases; desktops have no battery to protect. | **Form-factor-aware hibernation**, resolved at first boot via `Win32_SystemEnclosure.ChassisTypes` in `src/runtime/setup/SetupComplete/Power.ps1`. **Power plan defaults to Balanced** and may be explicitly set to Energy Saver, High Performance, or Ultimate Performance; WinMint activates the selected plan without deleting other schemes. **Desktop hibernation only:** `powercfg -h off` is limited to desktops. **Dual-boot** builds additionally disable Fast Startup offline (`dual-boot-windows-policy`). |
| Delivery Optimization | Peer download/upload can be unwanted. | Keep Windows Update enabled, but set Delivery Optimization policy so the PC is not used as a peer update source for other devices. |
| Print stack | Core printing and Print to PDF stay. | **WinMint Core** removes optional **Windows Fax and Scan** (`Print.Fax.Scan` capability only). Do not disable Print Spooler or remove drivers by default. XPS *Viewer* remains a separate optional removal (viewing XPS files; unrelated to physical printers). |
| Location / Maps / Sensors | Privacy win. | Time zone, hardware sensors, and app permissions can behave strangely. Disable app access first, not services. |
| Optional Features / Capabilities | Can reduce image footprint. | Remove only obvious non-core features and test WU/feature update. Preserve OpenSSH, WSL, .NET, language/input, Windows client basics. |
| Defender exclusions | Can greatly improve Node/Rust/Python build performance. | Folder exclusions are security holes. Prefer Dev Drive performance mode over broad exclusions. |
| Dev Drive | Real developer performance feature using ReFS and Defender performance mode for **Windows-hosted** trees. | Not a WinMint default. User-managed only. Not interchangeable with WSL2: the Linux distro stays in its **WSL VHDX**; Dev Drive cannot host that layout. |
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
| Ultimate Performance by default | Bad laptop/thermal default; not a universal performance improvement. Keep it as an explicit `target.powerPlan = UltimatePerformance` selection only. |
| Disable dynamic ticking or apply timer folklore tweaks | Gaming-only tradeoff with battery/sleep/latency risks; requires measurement per hardware class. |
| Disable CPU security mitigations | Not acceptable for a general workstation baseline. |
| Visual effects "best performance" | Makes Windows feel dated for negligible benefit on modern machines. |
| Registry cleaners | No meaningful performance upside; high breakage risk. |

## Additional Ideas To Consider

### 1. Dev Drive As A User-Managed Option

Most debloat tools focus on removing things. For a developer workstation, adding the right storage model may matter more. Windows Dev Drive uses ReFS and Defender performance mode for developer workloads, and Microsoft documents it as a performance feature for code, package caches, and build output. WinMint does not enable it by default; users can set it up separately if they want that storage model.

Potential WinMint direction:

- Do not silently repartition for Dev Drive.
- Add a future "Developer workspace" step only when disk layout is already being chosen.
- Route **Windows-native** code, package caches, and build output there when the user opts in.
- Keep WSL Linux files inside the WSL VHD (`\\wsl$\...` / ext4), not on `/mnt/c` on a Dev Drive, unless the user knowingly accepts cross-OS IO tradeoffs.

### 2. WSL2-First Performance Profile

WinMint should treat WSL as the primary Linux layer, not an optional toy. The Developer profile defaults to Ubuntu LTS, but the user can opt out, choose Debian, Arch, Fedora, or select multiple distributions. A custom distro selection must never force Ubuntu back in.

Linux projects should live under `/home/<user>/code` inside the WSL filesystem. Windows-native projects and package caches can use a user-managed Dev Drive if the user chooses to configure one, but Linux source should not default to `/mnt/c/...`.

Candidate defaults (host `.wslconfig`, written by FirstLogon before distro install):

```ini
[wsl2]
pageReporting=true
networkingMode=mirrored
dnsTunneling=true
firewall=true
# NAT-only — uncomment if you switch networkingMode back to nat:
# localhostForwarding=true
# autoProxy=true

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

WinMint embeds a commented `/etc/wsl.conf` reference appendix in the managed `.wslconfig` template (header: WinMint does not create this file). Distro-side `/etc/wsl.conf` is **user-managed** — WinMint does not automate it.

Current decision:

- Use `gradual` for `autoMemoryReclaim`; it returns cache steadily without the sharper behavior of immediate cache drops.
- Default to `networkingMode=mirrored` for WSL-first dev ergonomics (shared localhost/LAN stack). VPN or firewall issues are possible; users can switch to `networkingMode=nat` and uncomment the NAT-only lines in `.wslconfig`.
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

Windows AI components are moving targets. WinMint should maintain a small AI policy layer:

- Disable Recall snapshot, export, and data-analysis policy values.
- Remove provisioned Copilot/Recall/WebExperience packages where safe.
- Disable Recall optional feature when present.
- Disable Edge inline compose/rewrite, web AI APIs, and promo policies while preserving explicit Edge Copilot page-context chat.
- Disable AI additions in inbox apps only when they are imposed or low-value. Notepad AI is disabled by default; Paint AI is preserved.
- Do not touch Office AI policy, agent connectors, workspaces, or remote connectors.

Avoid deleting servicing packages unless tests prove updates and repair still work.

### 6. Developer Defender Strategy

The usual developer answer is to add broad Defender exclusions for `node_modules`, package caches, WSL VHDs, and source folders. That is fast but not clean.

Preferred order:

1. Use Dev Drive performance mode for Windows-hosted source if the user configures it.
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

AutoLogon may be persisted during first-logon recovery so selected modules can resume after a reboot, but success must always clear retry state, disable AutoAdminLogon, and wipe the plaintext password.

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
| P1 | Keep extending the build manifest report with risk and reversibility metadata as new surfaces are added. | Trust and auditability; this borrows Sparkle/Sophia's best UX idea without inheriting their whole tweak matrix. |
| P1 | Keep the protected platform allowlist under contract tests. | Prevent future over-debloat from breaking WSL/update/security. |
| P1 | Keep the Home privacy baseline in one source of truth. | More complete O&O/WinUtil-style coverage without UI bloat. |
| P1 | Keep AI removal layer tests current. | Copilot/Recall surfaces keep changing. |
| P2 | Investigate DiagTrack service state with smoke tests. | Potential idle/noise win, but needs evidence. |
| P2 | Add optional mirrored-networking control for WSL. | Useful for some VPN/LAN workflows; not safe enough for Core default. |
| P2 | Document Dev Drive as a user-managed option only. | Keep the product stance explicit without making it a default baseline. |
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
