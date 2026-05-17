# WinMint — Roadmap

Current branch: `architecture/profile-engine`

For deep context on any milestone see `docs/Architecture-Plan.md`, `docs/Windows-Debloat-Strategy.md`, and `AGENTS.md`.

---

## Current status

M0–M3 complete. M3.5 mostly done (XamlReader.Parse + step-transition easing shipped; DPI-aware preview deferred — WPF event dispatcher / PS scope mismatch). M4 ready except for the testing matrix and final `Validate.ps1 -RunAnalyzer` pass. Full pipeline works end-to-end. WPF first-logon progress UI live. Agent reads `BuildProfile.json` from the build. The wizard auto-elevates at launch via UAC (using `pwsh.exe` directly — `wt.exe`'s MSIX activator silently strips `-Verb RunAs`). No app state written to `%APPDATA%` — the tool is intentionally stateless; each run starts fresh from the wizard.

---

## M0 — Image correctness fixes · _done_ ✓

| # | Issue | Fix applied |
|---|-------|-------------|
| 1 | `/ResetBase` destroys update rollback | Removed from `Packages.ps1` |
| 2 | `Compact=true` penalises CPU | Removed from `autounattend.xml` |
| 3 | `hardware-bypass` always applied | Removed from default list in `Engine.ps1`; invariant test added |

---

## M1 — Profile contract · _done_ ✓

**What changed:**
- `Start-WinWSBuild -Profile $profile` added to `Engine.ps1` — single entry point, works without WPF loaded
- Console and UI paths both call `Start-WinWSBuild`; neither creates a build config directly
- `Start-WinWSBuild` saves a secrets-free `WinWS-BuildProfile.json` to `output/` as a build artifact
- `%APPDATA%` profile snapshot removed — program is stateless
- `schemas/winws.agentstate.schema.json` created
- `Test-ProfileInvariants.ps1` extended with hardware-bypass guard

---

## M2 — Agent completion + first-logon UI · _done_ ✓

All active agent modules working (Windhawk, YASB, Komorebi, WSL, editors, Flow+Everything). WPF first-logon progress window shows per-module status, offers retry on retryable failures, recommends reboot when needed. Agent reads `BuildProfile.json`. AutoLogon cleaned up on successful completion. Failed optional layer does not abort remaining modules.

---

## M3 — Release hardening · _done_ ✓

**Goal:** Every build is auditable and the release bundle is verifiable.

Tasks:
- [x] `BuildManifest.json` covers: removed AppX list, registry policies applied, drivers injected, payloads with source URLs and hashes, first-logon profile, risk flags _(`src/WinWS/Reports.ps1`)_
- [x] `schemas/winws.buildmanifest.schema.json` formal schema
- [x] Payload hash recorded in manifest before extract/stage _(`Assert-Win11IsoFileHash` runs at every download site)_
- [x] `removals.capabilitiesRemoved` populated from actual DISM capability removals _(filled in `Remove-WinWSCapabilities`)_

**Deferred:** pre-use verify against a pinned `ExpectedSha256`. All four downloads (PS7, ViVeTool, winget, Cascadia NF) use GitHub `releases/latest`; pinning hashes would freeze that policy and add per-version maintenance. The post-download hash in the manifest is the audit trail; trust comes from GitHub TLS + signed tags. Revisit if a release goes through an untrusted mirror.
- [x] Release bundle (`scripts/release/New-WinMintReleaseBundle.ps1`) includes all three schemas
- [x] `scripts/Validation/Validate.ps1` checks schema files are present and parseable _(`Test-BuildManifestSchema`, `Test-BuildProfileSchema`, walks `schemas/*.json`)_

**Done when:** A release ZIP contains schemas and the manifest from a full build passes schema validation. _(Status: done — `New-WinMintReleaseBundle.ps1` includes `schemas/`, `Test-BuildManifestSchema` validates the manifest shape.)_

---

## M3.5 — WPF UI quality

| # | Item | Status |
|---|------|--------|
| 1 | `XamlReader.Parse` instead of `XmlNodeReader` chain | ✓ `WinMint-UI.ps1` |
| 2 | DPI-aware shell preview bitmaps | **deferred.** First implementation hooked `Window.SourceInitialized` / `DpiChanged` to re-decode bitmaps at `container.height × DPI`. PowerShell's WPF event dispatcher loses script-scope function lookup at fire time — every workaround (`.GetNewClosure()`, `$function:` capture, scriptblock-by-reference) treated a symptom of the wrong design. Slight blur at 150%+ scaling is recoverable; a wizard that won't launch is not. Revisit only if the preview moves to a `MVVM`/binding-driven model where `IValueConverter` can perform the decode without reaching script scope. |
| 3 | Easing on step-transition fade-outs | ✓ `New-CubicEaseOut` applied to the two remaining un-eased splash fade-outs; all other step transitions already eased |

> **Drag-and-drop removed.** The wizard runs elevated (DISM `Get-WindowsImage` needs admin to read the offline `install.wim` for the edition list, and the build itself needs admin), and UIPI blocks Explorer (medium IL) from delivering OLE drops to a high-IL process. Browse + clipboard auto-detect (already shipped) cover the same UX without the elevation/drag conflict. Window position persistence and clipboard detection both shipped during M3.5.

---

## M4 — v1.0 ship criteria

**Goal:** The tool is ready for use beyond personal development.

Acceptance criteria:
- [x] **Build review step** — final wizard screen listing packages removed, tweaks applied, agent modules enabled, and driver source, shown before the user commits to a build _(Preflight page, `PagePanel5`)_
- [x] **Accessibility** — `AutomationProperties.Name` on every interactive control _(audited: 41 occurrences cover all buttons, radios, checkboxes, text inputs, password boxes, and the ISO selector card; hidden state-tracker checkboxes excluded as `Visibility="Collapsed"`)_
- [ ] **Testing matrix** — x64 VM (no drivers / This PC drivers), ARM64 target (Different PC), INF folder drivers, no internet at first logon, internet at first logon, multiple WSL distros, Standard desktop only, full shell layer stack _(human VM work)_
- [x] `README.md` reflects the current build flow accurately _(auto-elevation; clipboard auto-detection; no drag-and-drop)_
- [x] No stale scripts, commented-out dead code, or task markers left in shipped files _(grep confirmed; all `scripts/*.ps1` files are referenced from engine, manifest, or autounattend)_
- [x] `Validate.ps1 -RunAnalyzer` passes with documented analyzer exclusions and long-file warnings only.

---

## Backlog / not yet scheduled

Items are grouped by type and ordered within each group by priority.

### Product features

- Optional WSL mirrored-networking control after Core NAT `.wslconfig` defaults prove stable
- OEM driver downloader / PnP export for different-PC targets
- Dual-boot disk preset slider in the GUI — expose named stops only (`WindowsHeavy` 70/30, `Balanced` 60/40, `EvenSplit` 50/50, `LinuxHeavy` 40/60); backend already treats these as 64 GB-rounded presets with 256 GB Windows / 128 GB Linux hard minimums and leaves Linux space unallocated
- Dev Drive as an explicit workspace option during disk layout step
- Scheduled task inventory and narrow disable list (replacing current service-based assumptions)
- Monaspace Nerd Fonts decision: bundle subset vs lazy-download vs omit

### WPF — architectural (post-v1.0, high effort)

- **MVVM refactor** — replace `FindName()` + `Add_Click` wiring with `ViewModelBase` (INotifyPropertyChanged with auto-generated script properties) + `ActionCommand` (ICommand with built-in throttle and worker tracking); reference: PsModelUI `ViewModelBase.ps1` and `ActionCommand.ps1`; eliminates per-property setter boilerplate and manual `Dispatcher` marshalling but requires rewriting XAML `x:Name` bindings to `{Binding}` throughout
- **Runspace pool with function injection** — replace ad-hoc `Start-ThreadJob` calls with a shared `[RunspaceFactory]::CreateRunspacePool` pool initialised at startup with wizard helpers pre-injected; reference: PsModelUI `Set-ViewModelPool.ps1`; most valuable once the UI gains more async work (e.g. build log streaming)
- **`EnableCollectionSynchronization`** — required for any future streaming `ObservableCollection` (build log, progress feed); allows background threads to append without `Dispatcher.InvokeAsync`; reference: PsModelUI `Demo.ps1` GridContent pattern

### WPF — polish (post-v1.0, low effort)

- Per-frame animation for indeterminate progress during ISO verification — smooth spinner without timer overhead (`Animation/Per-FrameAnimation`)
- `ShowActivated = false` on any future in-process secondary dialogs to prevent focus stealing (`Windows/ShowWindowWithoutActivation`) — not applicable to the elevated window spawned via `Start-Process`

### Speculative / deferred

- `%APPDATA%\WinWS\profiles\` cloud sync support

---

## Decided against

| Feature | Reason |
|---------|---------|
| Headless / parameterised CLI build | Tool identity is a guided personal workstation builder; `WinMint-CLI.ps1` remains as a thin power-user wrapper (accepts a `BuildProfile.json` path, runs engine), not a full flag surface; dry-run value lands in the wizard as a review step instead |
| Write to USB | Ventoy/Rufus are dedicated tools; not worth the compatibility surface |
| Browser pre-install | Easy self-install; keeps ISO lean |
| PowerToys | Opinionated system-wide changes (keyboard shortcuts, background services) that conflict with the install's own shell layer choices; easy self-install for users who want it |
| VLC / 7-Zip | Win11 23H2+ handles common formats natively |
| Hyper-V toggle | Pro-only; conditional UI adds complexity for niche use |
| RDP toggle | Superseded by tools like RustDesk for most target users |
| WinUI 3 | Windows App SDK deployment fights the no-installer launch model |
| Electron/Tauri | Adds runtime and trust complexity to a security-sensitive ISO builder |
| Container runtime UI | Users who need Docker/Podman install it inside their WSL distro |
| MVVM dynamic class generation (PsModelUI `New-ViewModel`) | String-built class definitions lose IDE support and make stack traces harder to read; explicit PS classes are clearer for a production tool |
| PsModelUI `-AutomaticProperties` | A typo in a property name creates a new property silently instead of an error |
| WPF element tree debug helper | Dev-only; `$window.FindName()` and PS debugger are sufficient |
