# Port-from-v1 harvest map

WinMint v2 is a **new repo** with clean-sheet contracts. Do **not** submodule v1. Day-one scaffold, docs, brand, and media in this seed stand alone — **v1 on disk is optional** until a hybrid Payload / Servicing ticket needs proven behaviour.

## Locating v1 (when a ticket needs it)

```powershell
# sibling clone (recommended)
git clone https://github.com/yanai-sh/winmint.git ..\winmint-v1
# paths in the tables below are relative to that clone's root
```

Or point at any existing local v1 checkout. Never copy the v1 tree into this repo.

**Deferred UI/shell art** may also live in the companion `winmint-v2-future-assets-*.zip` (or v1’s `docs/v2/future-assets/`). Prefer the zip/shelf over digging through v1 for pickers and shell presets.

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
| `tools/vm/` SmartBuild fingerprint, checkpoint, `-PushOnly` | `tools/vm/` Smoke harness (not product CLI) |

## Provisioning spine → `payload/`

| Steal idea from (v1) | Land in v2 |
|----------------------|------------|
| `src/runtime/setup/FirstLogon.Region.ps1` (`Restore-WinMintDmaRegionalDefaults`) | `payload/setup/` region restore module |
| `src/runtime/setup/ProvisioningGuard.ps1`, `FirstLogon.PreLock.ps1` | `payload/setup/` lock / PreLock |
| `src/runtime/setup/FirstLogon.Transaction.ps1` + `.Runtime.ps1` (step catalog — slim) | `payload/setup/` thin transaction |
| `src/runtime/common/WinMint.Runtime.Common.ps1` | `payload/common/` |
| `src/runtime/setup/FirstLogon.State.ps1` (autologon / RunOnce / MaxAttempts) | `payload/setup/` |
| `src/runtime/setup/SetupComplete.ps1` (Panther wipe + RunOnce only — drop debloat catalog) | `payload/setup/SetupComplete.ps1` |
| `src/runtime/setup/WinMintSetupShell.Status.ps1` | **Rewrite thin** status projector (~phases only; no module catalog) |
| `apps/setup-shell/` (Native AOT splash host) | `src/WinMint.Splash/` (port model, new status schema) |
| `src/runtime/firstlogon/` agent modules + `agent-module-catalog.json` | **Smoke:** thin stub in `payload/agent/` only |

## Already in this seed (day one)

| Content | Location |
|---------|----------|
| .NET scaffold (`WinMint.slnx`, Orchestrator / Cli / Splash, tests) | `src/`, `tests/` |
| Brand (deduped / renamed) | `assets/brand/{mark,plate,lockup,readme}/` |
| Cursors (`modern/`), fonts, `wallpaper/bloom.png`, account avatars, Terminal, associations | `payload/media/` |
| Servicing stub entrypoints | `servicing/` |
| Start / workflow / ADRs | [`START.md`](START.md), [`ARCHITECTURE.md`](ARCHITECTURE.md), [`decisions/`](decisions/) |

## Shelved — companion `future-assets/` (not in seed)

Keep the future-assets zip/shelf **outside** commit 1. Copy into the v2 repo only when the matching vertical lands.

| Content | Location |
|---------|----------|
| Wizard pickers (WSL / editors / desktop) | `future-assets/ui/` |
| Shell presets (Windhawk / YASB / Komorebi) | `future-assets/shell/` |
| v1 WebView2 wizard HTML/JS (reference only) | `future-assets/wizard-webview2/` |

## Never port as authority

- `schemas/winmint.buildprofile.schema.json` / InstallPlan shapes  
- `tools/ui-bridge/`, WebView2 wizard, `assets/runtime/setup/setup-shell/bin/**`  
- SetupComplete debloat action catalog / AppX matrices for Smoke  

Update this file when a ticket harvests a new v1 path.
