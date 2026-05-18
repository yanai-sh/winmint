# WinMint

Opinionated Windows 11 ISO builder for clean developer workstation installs. Starts from official Windows media, applies a curated set of setup automation, debloat, optional DMA interoperability, drivers, desktop layer presets, and first-logon bootstrap, then emits a bootable ISO.

Works on x64 and ARM64 hardware (Surface, standard laptops, VMs). All choices are designed to not compromise system features the user might reasonably want.

> Personal-use project under active development. Some UI options may exist ahead of full automation so the intended flow can be designed and tested in place.

WinMint does not replace Rufus or Ventoy. Build the ISO here; write it to USB with the tool you already trust.

---

## Quick start

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-GUI.ps1
```

The primary GPUI launcher starts the packaged WinMint GUI. The legacy WPF fallback remains available as `WinMint-LegacyUI.ps1`; it auto-elevates via UAC because reading the offline `install.wim` for the edition list (`Get-WindowsImage`) and every later DISM/registry/disk operation needs admin.

Select your source ISO in the wizard. Browse via the file dialog, or copy an ISO in Explorer and bring the wizard to the foreground — clipboard auto-detection picks it up. Architecture is inferred from the filename and cross-checked against the WIM metadata.

Local layout:

```
winmint/
├── WinMint-GUI.ps1    # primary GPUI launcher
├── WinMint-LegacyUI.ps1 # legacy WPF fallback
├── WinMint-CLI.ps1    # headless/console builder (profile or flags; no GUI required)
├── winmint.ps1         # bootstrap downloader — fetches the latest release and launches the UI
├── apps/               # UI front ends (primary GPUI + legacy WPF)
├── src/                # engine, FirstLogon agent, and staged setup payloads
├── tools/              # validation, release, bridge, and authoring tools
├── config/
│   └── autounattend.xml      # OOBE automation template
├── assets/
│   └── drivers/              # optional: custom driver payloads
└── output/                   # generated ISO lands here (auto-created)
```

### Remote launch

```powershell
irm https://winmint.yanai.sh | iex
```

### Headless build

Run the builder without a GUI. The CLI is profile-first: `BuildProfile.json` is the full-fidelity contract used by the CLI, GPUI, legacy WPF UI, and automation. Use profile execution for repeatable builds, profile generation for editable templates, and shallow flags for quick automation.

#### Profile builds

```powershell
# Build from a committed/generated profile contract
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -ProfilePath .\BuildProfile.json

# Generate an editable starter profile without building or requiring elevation
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -NewProfile .\BuildProfile.json `
  -Preset Developer

# Save flag-composed intent as a profile, then edit/reuse it later
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -OutProfile .\dev-desktop.json `
  -Preset Developer `
  -DesktopUI `
  -Architecture amd64
```

`-ProfilePath` consumes the first-class `BuildProfile.json` contract directly and strips secrets from the public artifact written under `output\`. `-NewProfile` and `-OutProfile` write schema-valid profiles and exit without building; they are intended for editable templates and future GUI/automation handoff.

#### Flag builds

```powershell
# Build from flags, with no prompts
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -NonInteractive `
  -SourceIso .\Win11_25H2_amd64.iso `
  -Architecture amd64 `
  -ComputerName WinMint `
  -AccountName dev

# Keep official account OOBE, while still preconfiguring machine/region/disk choices
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -NonInteractive `
  -SourceIso .\Win11_25H2_ARM64.iso `
  -Architecture arm64 `
  -SetupOption CopilotPlus `
  -EditionMode Fixed `
  -Edition 'Windows 11 Pro' `
  -ComputerName SL7 `
  -AccountName Yanai `
  -AccountMode MicrosoftOobe `
  -LocationServices `
  -AutoWipeDisk `
  -TimeZoneId 'Israel Standard Time' `
  -UILanguage en-US `
  -UILanguageFallback en-US `
  -SystemLocale he-IL `
  -UserLocale he-IL `
  -InputLocale 'en-US;he-IL'

# Build from a user-provided UUP Dump source only when you want
# WinMint to prepare the ISO. If you already converted UUP to an ISO,
# pass that ISO through -SourceIso instead.
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -NonInteractive `
  -UupDumpSource .\uup_dump\26220.8474_arm64_en-us_core_f75dadfc_convert.zip `
  -Yes `
  -Architecture arm64 `
  -TargetDevice ThisPC `
  -SetupOption CopilotPlus `
  -AccountMode MicrosoftOobe

# Build for another device using one OEM driver pack file.
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -NonInteractive `
  -SourceIso .\Win11_25H2_ARM64.iso `
  -Architecture arm64 `
  -TargetDevice DifferentPC `
  -DriverPack .\assets\drivers\SurfaceLaptop7_ARM_Win11.msi

# CI/profile smoke test, no ISO required
pwsh -NoProfile -ExecutionPolicy Bypass -File .\WinMint-CLI.ps1 `
  -DryRun `
  -NonInteractive `
  -Architecture amd64
```

There is intentionally no v1 terminal wizard/TUI. GUI front ends author intent, the shared PowerShell profile factory resolves it, and the engine consumes the resulting profile.

#### Source ISO and UUP Dump

`-SourceIso` is the preferred input when you already have a final Windows ISO, including an ISO you created yourself from UUP Dump. Passing `-SourceIso` implies the no-prompt path for CLI builds.

`-UupDumpSource` accepts a UUP Dump conversion zip only when you want WinMint to prepare and validate the ISO first. UUP Dump folders are not accepted: if UUP Dump already produced an ISO, pass that ISO with `-SourceIso`. `-Yes` is required before WinMint downloads or converts Windows payloads.

`-TargetDevice ThisPC` means same-machine reinstall: WinMint captures installed drivers and uses the build host timezone, locale, and keyboard layouts as target intent. `-TargetDevice DifferentPC` means the build host is only a factory: WinMint uses default Windows drivers unless `-DriverPack <msi|zip>` is supplied, and any target timezone, locale, and keyboard assumptions should be checked explicitly.

#### Account, region, and edition

Use `-EditionMode TargetLicense` for the best automatic OEM activation path. Use `-EditionMode Fixed -Edition '<licensed edition>'` only when you know the target edition or accept manual activation; fixed edition builds service one image and shrink the final ISO.

`-AccountMode Local` is the default unattended local-admin flow. `-AccountMode MicrosoftOobe` removes the account-bypass pieces from `autounattend.xml`, so Windows runs the official Microsoft-account/sign-in OOBE while WinMint still applies the CLI-provided machine, disk, servicing, and first-logon configuration.

Pass `-DmaInterop` to opt into the EEA setup-region DMA interoperability path; WinMint uses Ireland with Germany as a defensive fallback, disables automatic time-zone updates, then restores the configured region after successful FirstLogon. Location services are disabled by default; pass `-LocationServices` to keep them enabled. Other privacy surfaces are WinMint baseline policy, not profile choices.

#### Optional feature groups

`-Preset Minimal|Developer|CopilotPlus|Gaming|DesktopUI` seeds profile groups, and additive group flags can be combined with it. With no profile group flags, WinMint uses the `Minimal` posture: remove obvious consumer bloat, Copilot/WebExperience surfaces, and Xbox gaming apps.

Additive group flags are `-Developer`, `-Copilot`, `-Gaming`, and `-DesktopUI`/`--Desktop-UI`. `-Developer` enables OpenSSH/developer-mode defaults but does not preselect editors, WSL distros, package managers, or launchers. `-Copilot` keeps Microsoft Copilot and WebExperience surfaces, `-Gaming` keeps Xbox/gaming packages and policies, and `-DesktopUI` selects the WinMint shell stack for direct flag-built builds. `-SetupOption CopilotPlus` is still accepted as a compatibility alias for the Copilot group.

Launchers are not implied by any profile group; pass `-Launcher FlowEverything` for Flow Launcher plus Everything Alpha, `-Launcher Raycast` for Raycast, or omit the flag for no launcher. Phone Link first-logon policy and live install audit are disabled by default; pass `-PhoneLink` or `-LiveInstallAudit` only when you want those live-user modules. Profile templates include selected groups but leave granular editor, WSL distro, shell-layer, launcher, audit, and Phone Link choices unselected unless explicit flags are provided. Recall is always removed when present.

---

## Safety model

- **Your ISO is the base.** WinMint does not ship or pin a hidden golden Windows image. The source ISO you choose is the version DISM services.
- **Security foundations stay intact.** WinMint does not disable Defender, Firewall, SmartScreen, Windows Update, Store infrastructure, WebView2, WSL, IPv6, WinRE, the component store, or UAC.
- **No recurring maintenance agent.** WinMint does not leave a scheduled maintenance task, background service, or drift-fighting script behind on the installed system.
- **Destructive disk modes are explicit.** `Manual` leaves disk choice to Windows Setup, `AutoWipeDisk0` targets disk 0, and `DualBootReserved` creates a Windows layout using a selected preset while leaving remaining space unallocated for another OS.

---

## Contracts and outputs

WinMint uses three JSON contracts:

| Contract | Schema | Purpose |
|----------|--------|---------|
| `BuildProfile.json` | `schemas/winmint.buildprofile.schema.json` | User/build intent from the GUI or CLI |
| `BuildManifest.json` | `schemas/winmint.buildmanifest.schema.json` | Machine-readable record of what the engine did |
| `state.json` | `schemas/winmint.agentstate.schema.json` | FirstLogon agent retry/resume state on the installed system |

Build outputs land under `output/`:

- Bootable ISO
- `WinMint-BuildManifest.json` — source ISO metadata, payload hashes, editions selected, drivers injected, build duration, warnings
- `WinMint-BuildProfile.json` — secrets-free copy of the build profile, with password material stripped

---

## Architecture detection

Parsed from the ISO filename via case-insensitive regex:

| Patterns                            | Resolves to |
|-------------------------------------|-------------|
| `arm64`, `aarch64`                  | `arm64`     |
| `x86_64`, `x86-64`, `x64`, `amd64` | `amd64`     |

If the filename has no marker, the app prompts once. The inference is then cross-checked against the WIM metadata and `setup.exe` PE header — all three must agree, or the build aborts with no side effects.

---

## Recommended base image

**Official multi-edition ISO from Microsoft:**

- ARM64 (Surface, Qualcomm): https://www.microsoft.com/en-us/software-download/windows11arm64
- x64: https://www.microsoft.com/en-us/software-download/windows11
- LTSC: use [UUP Dump](https://uupdump.net), edition `Enterprise LTSC`. The build detects LTSC from the WIM metadata and skips consumer tweaks automatically.

---

## What gets built

The build pipeline runs in four phases:

**1. Offline image (DISM against mounted WIM)**
- AppX package removal
- Registry tweaks baked into the offline hive
- Language cleanup
- ViVeTool pre-stage (feature ID overrides)
- Scheduled task deletion
- Driver injection (optional)
- Setup script staging (`autounattend.xml`, `SetupComplete`, `FirstLogon`, agent)

**2. OOBE automation (`autounattend.xml`)**
- `-AccountMode Local`: local account creation, no Microsoft account page
- `-AccountMode MicrosoftOobe`: official Windows account page shown
- Timezone injected from the target regional profile (`-TimeZoneId` in CLI/profile builds; the UI defaults to the builder setting but writes it as profile intent)
- Optional DMA interoperability (`-DmaInterop`) baked by using Ireland (`en-IE`, GeoID 68) as the Windows setup region
- Builder/user region restored after successful FirstLogon; automatic time-zone updates are disabled when DMA interoperability is selected
- Wi-Fi page preserved (not skipped)
- Privacy pages skipped/preconfigured (location services are disabled unless `-LocationServices` is selected; other privacy surfaces are disabled by baseline policy)
- Recall removal at image servicing time

**3. SetupComplete (runs as SYSTEM before first logon)**
- Windows Update policy restoration
- System restore point creation
- PowerShell 7 and Windows Terminal install (if internet available)
- SvcHost split threshold set to installed RAM
- Boot timeout reduced to 2 seconds
- BitLocker auto-encryption prevented; active BitLocker protection is preserved

**4. FirstLogon agent (runs as the new user on first logon)**
- Package manager bootstrap (winget)
- WSL2-first setup: WSL options are shown when the `Developer` group is enabled, but no distro is preselected. The user can select Ubuntu, Debian, Arch, Fedora, or multiple distros.
- `%UserProfile%\.wslconfig` generation for NAT networking, DNS tunneling, proxy forwarding, localhost forwarding, firewall integration, gradual memory reclaim, and sparse VHDs
- Desktop shell layers (composable; each layer is independently toggled in the wizard):
  - **Komorebi** — tiling window manager
  - **YASB** — status bar (taskbar replacement)
  - **Windhawk** — UI mod engine (suppresses virtual desktop flyouts by default)
- Editors: Cursor, VSCodium, Zed, Neovim (per wizard selection)
- **Launchers** are opt-in first-logon modules (`-Launcher FlowEverything`, `-Launcher Raycast`, or `features.launcher`). FlowEverything installs Flow Launcher plus voidtools Everything Alpha; Everything Alpha runs as a background service/index provider with its tray icon hidden. Raycast installs through winget as its own launcher choice. The Windows Search / indexing service is left intact so Settings and shell integrations keep working.
- **Phone Link policy** and **live install audit** are opt-in live-user modules. They do not run unless `-PhoneLink`, `-LiveInstallAudit`, or matching profile features are selected.
- AutoLogon registry cleanup on successful completion

WinMint is WSL2-first. Put Linux projects under `/home/<user>/code` inside the WSL distro (that tree lives in the WSL VHDX). **Dev Drive** (ReFS) is only for Windows-native repos and build caches if you add it later; it does not replace the WSL filesystem and is not where the Linux distro lives—use Dev Drive for Windows paths, WSL for Linux paths.

---

## What gets changed and why

### AppX removals

Grouped by category. WinMint exposes these through profile groups, not granular debloat toggles.

**Always removed** — no legitimate role in the WinMint baseline:
- `Microsoft.GetHelp` — links to web support, superseded by search
- `Microsoft.MicrosoftOfficeHub` — Store upsell stub, not Office itself
- `Microsoft.WindowsFeedbackHub` — sends system telemetry on demand
- `Microsoft.549981C3F5F10` (Cortana) — replaced by Windows Search; background service with no opt-out
- `MicrosoftCorporationII.MicrosoftFamily` — parental controls
- `Microsoft.StartExperiencesApp` (Tips) — promotional content disguised as help
- `Microsoft.BingSearch` — Bing integration in Start; the local search box works without it

**Advertising and AI (removed by Minimal; Copilot/WebExperience kept by `Copilot`):**
- `Microsoft.BingNews` / `MicrosoftWindows.Client.WebExperience` (Widgets) — news feed on the taskbar; no developer use
- `Microsoft.Windows.DevHome` — Microsoft's developer setup tool; WinMint replaces its function
- `Microsoft.Copilot` — Copilot sidebar; can be re-enabled from Settings

**Gaming/Xbox (removed by Minimal; kept by `Gaming`):**
- Xbox overlay, identity provider, TCUI, speech-to-text — services and overlays active in the background on every game launch
- `Microsoft.GamingApp` — Xbox app; kept when the `Gaming` group is selected

**Communication (default on):**
- `MSTeams` (personal Teams) — the enterprise Teams is a separate install and unaffected
- `Microsoft.People` / `Microsoft.windowscommunicationsapps` (Mail & Calendar) — superseded by web or dedicated clients

**Microsoft apps (default on):**
- `Microsoft.OutlookForWindows` — the new Outlook app; install manually if wanted
- `Microsoft.PowerAutomateDesktop` — RPA tool, not a default for developers
- `Microsoft.MicrosoftSolitaireCollection`, `Clipchamp.Clipchamp` — consumer extras with no workstation role

**Preserved Microsoft conveniences:**
- **Phone Link** and **Cross Device** stay provisioned by default (coherent phone ↔ PC linking).
- **Camera**, **Voice Recorder**, **Sticky Notes**, **Clock (Alarms & Timer)**, and **Notepad** stay provisioned by default.

**Also removed by default (reinstall from Store if needed):** Zune Music/Video (legacy media inbox), OneNote (UWP), Remote Desktop (Store client), and common **trial / OEM-bundled** AppX where package names match (McAfee, Norton, ExpressVPN, Surfshark, AVG, Avast, KasperskyLab, Dolby trials, CCleaner — no-op if your SKU never shipped them). Full OEM suites (Lenovo/HP/Dell companion apps) vary by machine; extend `Get-WinMintAppxBloatwareCategories` when you have a SKU-specific list.

### Registry tweaks (offline, applied to the mounted image)

Applied during setup so they take effect before the user ever logs in. Most user-preference stamps are reversible through Windows Settings; machine-policy stamps can be removed from the documented registry paths.

### European interoperability / DMA

WinMint can opt into Microsoft Digital Markets Act interoperability by installing with an EEA setup region. When `-DmaInterop` is selected, the generated answer file uses Ireland (`en-IE`, GeoID 68) for the Windows setup/user-region path so Windows exposes EEA/DMA behavior such as Edge/Bing uninstall affordances, stronger default-browser respect, and Windows Search provider interoperability where the source Windows build supports them. Germany (`de-DE`, GeoID 94) is retained only as a defensive fallback if Ireland's region metadata cannot be resolved on the build runtime.

After the FirstLogon agent completes successfully, WinMint restores the builder's configured end-state: time zone, display language, input choices, user/system locale, and home-location GeoID. When DMA interoperability is enabled, WinMint also disables the Auto Time Zone Updater service so Windows location inference does not keep snapping the time zone back to the EEA setup location. Location services are disabled by default; users can re-enable them in Settings or builds can opt in with `-LocationServices`.

Known consequences:
- Microsoft documents DMA behavior as region-selected-at-setup behavior. `-DmaInterop` intentionally chooses an EEA setup region even when the user lives elsewhere.
- Microsoft Store catalog, recommendations, legal prompts, or account/service experiences may briefly or persistently reflect EEA behavior. Microsoft account billing region usually remains separate, but Store/content edge cases are possible.
- Edge is not removed automatically. If the user later uninstalls Edge, Edge-backed PWAs, sites installed as apps, widgets, and some Copilot surfaces can stop working.
- LTSC/IoT SKUs may not expose every DMA affordance, especially Edge uninstall.
- Feature updates, repair installs, or Microsoft policy changes may alter DMA behavior. WinMint documents the policy in `BuildManifest.json`, but it does not fight servicing with a recurring maintenance task.

**Advertising ID** (`AdvertisingInfo\Enabled=0`): Disables the per-device advertising identifier used to link app telemetry across sessions. Settings → Privacy → General → "Let apps show me personalized ads" re-enables it.

**Feedback frequency** (`Siuf\Rules\NumberOfSIUFInPeriod=0`): Suppresses Windows feedback nag prompts. Does not disable Feedback Hub itself.

**Bing in Start search** (`Search\BingSearchEnabled=0`, `CortanaConsent=0`, `Policies\Explorer\DisableSearchBoxSuggestions=1`): Stops the search box from sending keystrokes to Microsoft servers on every query. Local file and app search still works normally. Settings → Privacy → Search permissions re-enables web suggestions.

**Contact harvesting** (`InputPersonalization\TrainedDataStore\HarvestContacts=0`): Would normally allow Windows to scan contacts from Mail and People to improve typing suggestions. Both apps are removed, so this key is inert — set for belt-and-suspenders coverage.

**Windows suggestions and setup nags disabled** (`ContentDeliveryManager` subscribed-content keys, `SoftLandingEnabled=0`, `SystemPaneSuggestionsEnabled=0`, `UserProfileEngagement\ScoobeSystemSettingEnabled=0`): Disables welcome-experience promos, tips, suggested notifications, Settings suggestions, and "finish setting up your device" prompts for newly created users.

**Settings Home hidden** (`SettingsPageVisibility=hide:home`): Opens Settings directly into the real settings pages instead of the promotional Home dashboard. Removing the policy restores Settings Home.

**File Explorer opens to This PC** (`Explorer\Advanced\LaunchTo=1`): Uses the stable built-in Explorer target. Windows does not support `%USERPROFILE%` as a native `Open File Explorer to` value; use a shortcut or launcher action for that.

**App launch tracking disabled** (`Explorer\Advanced\Start_TrackProgs=0`): Stops Windows from tracking app launches to tune Start/search suggestions. Pinning and normal app search continue to work.

**CEIP and app inventory telemetry disabled** (`SQMClient\Windows\CEIPEnable=0`, `AppCompat\AITEnable=0`, `DisableInventory=1`): Turns off legacy customer-experience and application-inventory reporting without disabling Windows Update, Defender, Store infrastructure, or crash-diagnostic tooling.

**Task View button hidden**: Win+Tab still works. The taskbar button duplicates a keyboard shortcut and takes up space.

**End Task in taskbar context menu**: Enables right-click → End Task directly from the taskbar without opening Task Manager (default-on in 25H2; the registry stamp ensures it across feature updates).

**Menu show delay = 0**: Removes the ~400 ms animation delay before context menus appear. No functional change; purely feel.

**Dark mode**: System and app dark mode enabled by default. Toggleable in Settings → Personalization.

**UAC prompt dimming disabled** (`PromptOnSecureDesktop=0`): UAC consent prompts still appear, but Windows does not switch to the dimmed secure desktop. WinMint does not set "Never notify", does not change `ConsentPromptBehaviorAdmin`, and does not disable UAC.

**Sticky Keys disabled**: The Shift×5 shortcut is a productivity hazard. Accessibility → Keyboard → Sticky Keys re-enables it.

**SVG default app**: Associates `.svg` files with the built-in Photos viewer rather than prompting on first open.

### SetupComplete operations (runs once as SYSTEM)

**SvcHostSplitThreshold set to installed RAM**: Windows groups multiple services into a single `svchost.exe` process on low-RAM machines (default threshold: ~3.5 GB, a Windows Vista-era heuristic). On any machine with more RAM than the threshold, each service gets its own process. This makes Task Manager, Process Explorer, and resource diagnostics actually readable — you can see which service is using CPU or memory, not just an anonymous svchost pool. The threshold is set to the exact installed RAM at first boot so it reflects the actual hardware.

**Boot timeout = 2 seconds**: The default 30-second boot menu timeout is only useful on dual-boot machines. Single-boot installs waste 30 seconds on every unexpected restart.

**BitLocker auto-encryption prevention**: A fresh install can auto-enable device encryption before the user has saved a recovery key. WinMint prevents surprise auto-encryption, but if BitLocker protection is already active it logs that state and leaves protection enabled.

**System restore point**: Created immediately after setup so the user has a rollback target before the first-logon agent runs.

### Deliberately excluded

These are common in other debloat tools. WinMint does not apply them:

| What | Why not |
|------|---------|
| Disable Windows Defender real-time protection | Security regression; developer machines run untrusted scripts, Docker workloads, and downloaded binaries |
| Disable Core Isolation / HVCI | Weakens process isolation; not justified by any performance gain on modern hardware |
| Disable UAC / set "Never notify" | Removes an important consent boundary. WinMint only disables secure-desktop dimming so prompts are less disruptive |
| Mass service disabling (150+ services) | High instability risk, especially on ARM/Surface where some "optional" services are hardware dependencies |
| Ultimate Performance power plan | Wrong default on laptops and tablets; destroys battery life with no meaningful throughput gain for development workloads |
| Classic right-click context menu | The Windows 11 context menu is a deliberate design improvement and works correctly with developer shell integrations. Reverting it also degrades touch ergonomics on Surface hardware |
| Speech privacy opt-out | Users may actively use speech input or dictation; the Settings toggle is non-obvious enough that silently disabling it would be surprising |
| Handwriting / ink collection restrict | Directly affects Surface Pen learning; tablet feature, must not be touched |
| TCP stack "optimizations" (CTCP, ECN, etc.) | Most are already Windows 11 defaults. The remainder have marginal and workload-specific effects |
| PowerToys | Changes keyboard shortcuts and installs background services that conflict with the shell layer choices (Komorebi, YASB, Windhawk). Easy self-install for users who want it |

---

## Activation

WinMint defaults to target-license edition selection. The generated ISO keeps the official multi-edition install image and lets Windows Setup use the target device firmware key when one is available.

For a target device that is not the build host, prefer an explicit target edition:

```powershell
-EditionMode Fixed -Edition 'Windows 11 Pro'
```

Fixed edition mode services only that image and writes official Windows Setup image-selection metadata (`/IMAGE/NAME`) into `autounattend.xml`. WinMint does not write generic install keys or activation keys. Activation still comes from the target device's digital license, OEM firmware key, retail key, Microsoft account entitlement, or organization licensing.

To check the target device's embedded OEM key before building:

```powershell
Get-WmiObject SoftwareLicensingService |
    Select-Object OA3xOriginalProductKeyDescription, OA3xOriginalProductKey
```

- **"Windows 11 Home"** or **"Windows 11 Pro"** → `TargetLicense` can use that edition automatically.
- **Empty / no firmware key** → use `-EditionMode Fixed -Edition '<licensed edition>'` so Setup does not depend on the build host or a firmware key.

### Why timezone matters

If the timezone is wrong, OOBE skips region selection and Windows defaults to Pacific Standard Time. For users outside the US West Coast this produces a multi-hour clock skew that breaks TLS certificate validation against Microsoft's licensing servers. The error message ("can't connect to your organization's activation server") is misleading — the real cause is the clock.

Set the target timezone in the profile. For CLI builds, pass `-TimeZoneId` explicitly when the target machine is in a different region than the build host:

```powershell
-TimeZoneId 'Israel Standard Time'
```

WinMint writes that timezone into `autounattend.xml`, keeps the Wi-Fi page visible so the machine can join the network before FirstLogon, and runs a Windows Time resync in `SetupComplete` before the activation audit. The timezone is target intent, not proof that the ISO was built on that target machine.

---

## Requirements

- Windows 11 host (for DISM)
- **Source ISO must be Windows 11 25H2 or newer** — the registry tweaks, AppX list, and ViVeTool feature IDs target 25H2's defaults. There is **no** separate “reference” or golden ISO inside the repo: **the ISO you choose is the base** WinMint services.
- PowerShell 7.3+
- Admin rights (the wizard auto-elevates at launch via UAC)
- ~25 GB free disk space on TEMP drive
- ~1.2× source ISO size on the output drive
- `oscdimg.exe` (app offers to install via winget if missing)

---

## Inspired by

| Project | What it contributed |
|---------|---------------------|
| [CTT WinUtil](https://github.com/ChrisTitusTech/winutil) | The broadest reference for what a developer workstation install should and shouldn't include; shaped the AppX removal list and the philosophy around not disabling security features |
| [Sophia Script](https://github.com/farag2/Sophia-Script-for-Windows) | Source for many of the DefaultUser and HKLM privacy tweaks; particularly the ContentDeliveryManager keys, search disables, and the SvcHostSplitThreshold rationale |
| [tiny11](https://github.com/ntdevlabs/tiny11builder) | Early proof that offline WIM modification + autounattend is a viable build model |
| [Win11Debloat](https://github.com/Raphire/Win11Debloat) | Registry tweak catalogue; useful negative reference for what not to apply on Surface/tablet hardware |
| [Wintoys](https://apps.microsoft.com/detail/9p8ltpgcbzxd) | Reference for exposing Windows DMA interoperability as a practical user-choice feature; WinMint keeps it as an explicit CLI toggle |
| [Sparkle](https://github.com/parcoil/sparkle) | Useful reference for documented tweaks, restore-point framing, and selective app removal; its gaming/security/service toggles are treated as opt-in or rejected for WinMint Core |
| [Schneegans unattend generator](https://schneegans.de/windows/unattend-generator/) | Authoritative reference for autounattend.xml structure, OOBE element semantics, and password encoding |

---

## Credits

**Tools installed by the agent**

| Tool | Author | License |
|------|--------|---------|
| [Komorebi](https://github.com/LGUG2Z/komorebi) | LGUG2Z | MIT |
| [whkd](https://github.com/LGUG2Z/whkd) | LGUG2Z | MIT |
| [YASB](https://github.com/amnweb/yasb) | AmN | MIT |
| [Windhawk](https://windhawk.net) | RamenSoftware | Freeware |
| [Flow Launcher](https://www.flowlauncher.com) | Flow Launcher contributors | MIT |
| [Everything Alpha](https://www.voidtools.com) | voidtools | Freeware |
| [Raycast](https://www.raycast.com/windows) | Raycast Technologies Ltd. | Proprietary |

**Build tooling**

| Tool | Notes |
|------|-------|
| [ViVeTool](https://github.com/thebookisclosed/ViVe) | Windows feature flag control; fetched from GitHub releases at build time |
| [oscdimg](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/oscdimg-command-line-options) | ISO assembly; part of the Windows ADK (Microsoft) |

**Bundled assets**

| Asset | Source | License |
|-------|--------|---------|
| BreezeX Light cursor theme | [ful1e5/BreezeX_Cursor](https://github.com/ful1e5/BreezeX_Cursor) | GPL-3.0 |
| Cascadia Code Nerd Font | [microsoft/cascadia-code](https://github.com/microsoft/cascadia-code) | SIL OFL 1.1 |

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for full license texts.

---

## License

WinMint is licensed under GPL-3.0-only. See [`LICENSE`](LICENSE).

Bundled third-party assets retain their original licenses. See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
