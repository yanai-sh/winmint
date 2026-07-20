# WinMint v2 architecture (locked)

Greenfield project: **new GitHub repository**, no backwards compatibility with WinMint v1 contracts or CLI. See [ADR-002](decisions/ADR-002-v2-architecture.md). Naming: [NAMING.md](NAMING.md). Tree: [STRUCTURE.md](STRUCTURE.md).

## Architectural style

**Use: pipeline orchestrator + ports & adapters** (hexagonal at one hard seam).

| Idea | How it shows up here |
|------|----------------------|
| **Pipeline / orchestrator** | Unelevated C# sequences validate → plan → emit job/unattend → invoke Servicing → collect evidence |
| **Port** | “Run elevated imaging job” / “stage payload tree” — small interfaces the Orchestrator owns |
| **Adapter** | Thin `pwsh -File` kernels under `servicing/` (DISM, hive, oscdimg); filesystem staging |
| **Deep modules** | Fat behaviour behind small surfaces (e.g. `IServicingRunner`, Profile validator) — see codebase-design vocabulary |

**Do not use as the backbone:**

| Style | Why it’s a poor fit |
|-------|---------------------|
| **Classic Clean Architecture** ( Domains ← Application ← Infrastructure onion, UseCase-per-feature folders) | WinMint is a **batch imaging pipeline**, not an enterprise app with many interactive use cases. The onion adds folders without a second consumer. |
| **Full tactical DDD** (aggregates, domain events, repositories, sagas) | No long-lived domain model or transactional consistency boundary across users. Profile JSON in → ISO out. |
| **Microservices** | One desktop toolchain; one process graph + elevated helper. |

**Do use lightly from DDD (strategic only):**

Three **bounded contexts** (vocabulary + ownership — not event buses):

| Context | Owns | Folder gravity |
|---------|------|----------------|
| **Authoring** | Profile intent, CLI, later Wizard | `src/WinMint.Cli`, `src/WinMint.Wizard`, Orchestrator Config |
| **Imaging** | Plan, unattend, Servicing jobs | `src/WinMint.Orchestrator`, `servicing/` |
| **Provisioning** | FirstLogon, splash, agent, staged media | `payload/`, `src/WinMint.Splash` |

Cross-context rule: Imaging must not call live Provisioning APIs; it only **stages** files. Provisioning never mounts WIMs.

## Runtime shape

```
Unelevated C# CLI / Orchestrator  →  elevated pwsh Servicing adapters
                                 →  stages payload/ into the image
Avalonia wizard (later)          →  same Orchestrator ports
Native AOT splash (ISO)          →  status JSON + provisioning lock (not Avalonia)
```

| Layer | Owns | Must not own |
|-------|------|----------------|
| **Orchestrator** (C#) | Profile validation, plan, CLI, unattend/job JSON | In-process DISM / offline hive |
| **Servicing** (elevated `pwsh -File`) | Thin DISM/WIM/hive/export adapters | Product CLI, fat monolith entry |
| **Payload** | Setup / FirstLogon / agent stub / splash host + media | Build orchestration |
| **Wizard** (Avalonia, later) | Profile authoring UI | Servicing, ISO splash |

## First vertical: Smoke

- Profile → ISO → Hyper-V unattend install → FirstLogon complete
- Evidence: splash plumbing OK + **DMA** restore
- Plumbing only: no debloat/keep matrix, no BitLocker policy
- Password-**required** local account; Hyper-V smoke SKU = **Pro**
- **CLI-first** — Avalonia after Smoke is green
- User always supplies official Microsoft **Source ISO** ([ADR-001](decisions/ADR-001-source-iso-legal.md))
- Smoke / test ISO builds use the **fast image-quality lane** (below); do not pay for release compression during iteration

### Smoke Autologon invariant

Proven hard failure in v1: if SetupComplete leaves Winlogon as `DefaultUserName=defaultuser0` with `AutoAdminLogon`, FirstLogonAnim hangs on “Just a moment” and Payload never starts.

For Local + autoLogon Smoke:

1. Stamp Winlogon to the **profile account** before any unbounded/long SetupComplete network install (toolchain / winget).
2. Keep a **final restamp** before secret cleanup.
3. Fail closed (verify + throw) when Local+autoLogon is selected; still wipe secrets after action errors.

Harvest: v1 `SetupComplete.ps1` (`autologon-stamp` before `toolchain-install`). See [PORT-FROM-V1.md](PORT-FROM-V1.md).

### Splash status model

Splash stays **Native AOT** (not Avalonia). Port the v1 presenter *behaviour*, not the WebView2 wizard or InstallPlan module catalog:

| Concern | Carry forward |
|---------|----------------|
| Host | Direct2D with GDI fallback; PreLock adopt-if-running |
| Control phases | `running` → `finishing` → `complete` / `failed` / `reboot` |
| Status JSON | OOBE-style stages (`stageId` / `taskLabel`: ready → apps → wsl → finish), `detailLabel` + `itemIndex`/`itemTotal`, stage-weighted progress, `progressMode` indeterminate for ready/finish and long items |
| Paint | Main / detail / `i of n` / thin bar — no `%`, no package-manager names, no step checklist |
| Accessibility | Reduced motion (`SPI_GETCLIENTAREAANIMATION`), high-contrast flat canvas, Narrator via window title + `EVENT_OBJECT_NAMECHANGE` |
| Reboot | `needsReboot` / `reboot` terminal phase **under** the provisioning lock — do not release the lock then reboot blindly |

Clean-sheet JSON schema in v2; use v1 `WinMintSetupShell.Status.ps1` + `apps/setup-shell/` as behaviour reference only.

## Image quality (run override, not Profile)

ISO wall-clock is dominated by DISM + WIM export. Orchestrator language does not change that. Keep **two lanes** (same idea as v1 `-Compression` / `-FastImage`):

| Lane | Export / cleanup | Use |
|------|------------------|-----|
| **Test / Smoke** | Soft or no recompress; **skip** WinSxS `StartComponentCleanup` | Iteration, Hyper-V Smoke — size irrelevant |
| **Release** | Hard recompress (`Max`) + `StartComponentCleanup` | Bare-metal / published ISOs — small when practical |

- Image quality is a **build run override**, not a Profile field.
- Manifest (or equivalent build report) must record export compression and whether component cleanup ran — never ship a fast-lane ISO as if it were release quality.
- VM harness concerns (ISO fingerprint cache / SmartBuild, PostSetup checkpoint, push-only FirstLogon) are **tools/vm** work for Smoke speed; they are not product CLI surface.

## Payload strategy: hybrid

**Port-and-reshape** from v1: DMA restore, provisioning lock, thin transaction, Common, splash host model (stages + a11y + Autologon stamp).

**Clean-sheet:** staged JSON contracts, thin agent stub, small status schema.

**Do not** wrap v1 `WinMint.ps1` as the elevated subprocess.

## Post-Smoke product stances (harvest, not Smoke scope)

When product depth lands after Smoke, carry these v1 decisions forward unless an ADR revises them:

- **Edge stays installed** — noise/ADMX debloat only; no uninstall automation or keep/remove Edge UI.
- **Home-first quiet UX** — collapse tips/rehydration paths; DMA restore-first remains.
- **Baseline host CLI** includes Microsoft Coreutils; WSL uses managed `wsl.conf` + default user per distro when distros are selected.
- **No Raycast / Everything** product paths.
- **Network device-metadata prompts blocked** offline (`PreventDeviceMetadataFromNetwork`); Windows Update driver delivery preserved.

Full path map: [PORT-FROM-V1.md](PORT-FROM-V1.md).

## Stack

- `net11.0` + SDK pin (`global.json`)
- Avalonia **12.1.x** for wizard later; splash stays native AOT (non-Avalonia)
- Source-gen JSON; `LibraryImport` for Win32; `PublishAot` on exes only
- Elevated Servicing / Payload scripts: **pwsh 7.6+** (v1 floor)
