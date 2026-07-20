# Port-from-v1 harvest map

WinMint v2 is a **new repo** with clean-sheet contracts. Do **not** submodule v1. Day-one scaffold, docs, brand, and media in this seed stand alone — **v1 on disk is optional** until a hybrid Payload / Servicing ticket needs proven behaviour.

**Last harvest sync:** 2026-07-20 (v1 commits after seed `2d7966d` through `fdaf2c1`). Re-read v1 `AGENTS.md` when a ticket needs current wording; this map is the intentional carry-forward list, not a mirror of the whole monolith.

## Locating v1 (when a ticket needs it)

```powershell
# sibling clone (recommended)
git clone https://github.com/yanai-sh/winmint.git ..\winmint-v1
# paths in the tables below are relative to that clone's root
```

Or point at any existing local v1 checkout. Never copy the v1 tree into this repo.

**Deferred shell presets** (and placeholder picker icons) may live in the companion `winmint-v2-future-assets-*.zip` (or v1’s `docs/v2/future-assets/`). Prefer the shelf for Windhawk/YASB/Komorebi presets. Avalonia / picker icons are **not** early v2 work — treat `ui/` as placeholders only.

Paths below are relative to the **v1** repo root unless noted.

## Imaging adapters → `servicing/`

| Steal idea from (v1) | Land in v2 |
|----------------------|------------|
| `src/runtime/image/Private/Image/Staging.ps1` (DISM mount/save/dismount kernels) | `servicing/Mount-Wim.ps1`, `Dismount-Wim.ps1` |
| `src/runtime/image/Private/Pipeline.ps1` (ISO mount, oscdimg export pieces) | `servicing/Mount-IsoStage.ps1`, `Export-Iso.ps1` |
| `src/runtime/image/Private/Image/Tweaks.ps1` (`Invoke-RegistryTweak` / `reg load` loop only) | `servicing/Apply-OfflineOps.ps1` |
| `src/runtime/image/Private/Image/SetupPayloadStaging.ps1` (copy logic — **not** hardcoded name lists) | `servicing/Stage-Payload.ps1` + `payload/payload-manifest.json` |
| `src/runtime/image/Private/Image/Unattend.ps1` / DMA locale merge | **Rewrite in C#** (`WinMint.Orchestrator` Unattend) — use v1 only as behaviour reference |
| Entire `WinMint.ps1` load / `Invoke-WinMintIsoPipeline` | **Do not wrap** |
| `Cli.ps1` / `Packages.ps1` image-quality path (`-Compression` Max\|Fast\|None, `-FastImage`, `StartComponentCleanup` gate, manifest `exportCompression` / `componentCleanup`) | Orchestrator **run overrides** + Servicing export/cleanup kernels; same two-lane semantics ([ARCHITECTURE.md](ARCHITECTURE.md#image-quality-run-override-not-profile)) |
| WinUtil-inspired resume: Max-compression cache / skip re-export when fingerprint matches; PE driver inject path; tweak undo / rollback evidence | Servicing export kernels + Orchestrator report fields (Smoke may use fast lane only) |
| `PreventDeviceMetadataFromNetwork` + vendor co-installer blocks (WU driver delivery preserved) | Offline hive ops — default-on for product builds after Smoke plumbing |
| Dual-channel Spectre One Half Dark console + verbose file log | Orchestrator/CLI report UX (optional for Smoke; do not block ISO path) |
| `tools/vm/` SmartBuild fingerprint, checkpoint, `-PushOnly`, ForceBuild/SmartBuild honor | `tools/vm/` Smoke harness (not product CLI) |

## Provisioning spine → `payload/`

| Steal idea from (v1) | Land in v2 |
|----------------------|------------|
| `src/runtime/setup/FirstLogon.Region.ps1` (`Restore-WinMintDmaRegionalDefaults`) | `payload/setup/` region restore module |
| `src/runtime/setup/ProvisioningGuard.ps1`, `FirstLogon.PreLock.ps1` | `payload/setup/` lock / PreLock |
| `src/runtime/setup/FirstLogon.Transaction.ps1` + `.Runtime.ps1` (step catalog — slim) | `payload/setup/` thin transaction |
| `src/runtime/common/WinMint.Runtime.Common.ps1` | `payload/common/` |
| `src/runtime/setup/FirstLogon.State.ps1` (autologon / RunOnce / MaxAttempts) | `payload/setup/` |
| `src/runtime/setup/SetupComplete.ps1` Autologon stamp **before** long network/toolchain work; final restamp before secret wipe; never leave `DefaultUserName=defaultuser0` with `AutoAdminLogon` | `payload/setup/SetupComplete.ps1` — **Smoke-critical** ([ARCHITECTURE.md](ARCHITECTURE.md#smoke-autologon-invariant)) |
| `src/runtime/setup/SetupComplete.ps1` (Panther wipe + RunOnce — drop debloat catalog for Smoke) | `payload/setup/SetupComplete.ps1` |
| `src/runtime/setup/WinMintSetupShell.Status.ps1` + OOBE stage projection (`stageId` / `taskLabel` / item progress / a11y) | **Rewrite thin** status projector + clean-sheet schema; keep stage semantics ([ARCHITECTURE.md](ARCHITECTURE.md#splash-status-model)) |
| `apps/setup-shell/` (Native AOT splash: Direct2D/GDI, reduced-motion, high-contrast, Narrator namechange) | `src/WinMint.Splash/` (port presenter model; new JSON schema) |
| `needsReboot` scheduling **under** provisioning lock (do not release lock then reboot blindly) | Payload transaction control phases (`reboot` terminal) |
| Pins / desktop finalize under lock; winget catch-up honesty signals | Post-Smoke agent/desktop verticals; Smoke may stub |
| `src/runtime/firstlogon/` agent modules + `agent-module-catalog.json` | **Smoke:** thin stub in `payload/agent/` only |

## Post-Smoke product harvest (later verticals)

Proven in v1; **out of Smoke** but intentional when product depth lands. Do not reintroduce cut paths.

| Steal idea from (v1) | Land in v2 (later) |
|----------------------|--------------------|
| `keep.edge` always true; Edge noise ADMX only; no uninstall / no UI keep-remove Edge | Profile/posture + offline Edge policy — never Edge removal automation |
| Home quiet-UX path (ContentDeliveryManager / tips collapse — Home-first) | Offline + FirstLogon quiet posture |
| Microsoft.Coreutils (`Microsoft.Coreutils`) as baseline host CLI via winget | Payload agent baseline packages |
| Managed `wsl.conf` + default user per distro | WSL agent module |
| Curated Windows Terminal profiles; pwsh **7.6+** floor | `payload/media/terminal/` + SetupComplete/agent Terminal harden |
| Explorer QoL (End Task path, folder-discovery off, extensions/hidden/long-paths baseline) | Offline tweak modules |
| OOBE rehydration suppress / live AppX exempt lists restage-safe | Debloat durability vertical |
| SL7 / Hyper-V smoke profile matrix + mocked WSL (`wslRuntimeValidation = skip`) | `tools/vm/` + fixtures (harness only) |

## Already in this seed (day one)

| Content | Location |
|---------|----------|
| .NET scaffold (`WinMint.slnx`, Orchestrator / Cli / Splash, tests) | `src/`, `tests/` |
| Brand (deduped / renamed) | `assets/brand/{mark,plate,lockup,readme}/` |
| Cursors (`modern/`), fonts, `wallpaper/bloom.png`, account avatars, Terminal, associations | `payload/media/` |
| Servicing stub entrypoints | `servicing/` |
| Start / workflow / ADRs | [`START.md`](START.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`decisions/`](decisions/) |

## Shelved — companion `future-assets/` (not in seed)

Keep the future-assets zip/shelf **outside** commit 1.

| Content | When to copy in | Location |
|---------|-----------------|----------|
| Shell presets (Windhawk / YASB / Komorebi) | When shell-layer product depth lands (CLI/agent — no GUI required) | `future-assets/shell/` |
| Picker icons (WSL / editors / desktop) | **Placeholder only** — not early; only if/when an authoring UI is scheduled | `future-assets/ui/` |
| v1 WebView2 HTML/JS | Reference archaeology only — never product authority | `future-assets/wizard-webview2/` |

## Never port as authority

- `schemas/winmint.buildprofile.schema.json` / InstallPlan shapes  
- `tools/ui-bridge/`, WebView2 wizard, `assets/runtime/setup/setup-shell/bin/**`  
- SetupComplete debloat action catalog / AppX matrices for Smoke  
- Raycast launcher / Everything search product paths (purged in v1 — do not revive)  
- Edge uninstall (`DISM /Remove-EdgeBrowser`, Tiny11-style scrub, keep/remove Edge UI)  

Update this file when a ticket harvests a new v1 path.
