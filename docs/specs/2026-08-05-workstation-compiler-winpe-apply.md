# Spec: Workstation compiler — WinPE apply lane + online-first debloat

**Date:** 2026-08-05  
**Status:** Approved (2026-08-06) — tickets filed from this spec  
**Authority:** [CONTEXT](../../CONTEXT.md) · [ARCHITECTURE](../ARCHITECTURE.md) · [DESIGN](../DESIGN.md) · [Smoke](2026-07-27-smoke.md) · [PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md) · [IMAGESERVICING](../design/IMAGESERVICING.md) · [KEEPFLAG](../design/KEEPFLAG.md)  
**Supersedes (partial):** legacy-setup + offline-primary debloat as *default product posture* — not immediate code removal  
**Destination:** Solo dev USB demo — zero-touch install → locked splash → online debloat/packages → Explorer unlock

## Problem Statement

WinMint v2 reliably builds tailored ISOs and controls FirstLogon via ProvisioningSession, but the **product identity** and **install engine** are misaligned with the maintainer’s goals:

1. **Product is workstation state, not ISO craftsmanship.** The user wants a finished developer workstation. USB/ISO is delivery convenience so they never run a separate post-install debloat tool — not the thing being sold.
2. **Install engine fights Microsoft’s direction.** Windows 11 24H2/25H2 ConX setup partially honors `Autounattend.xml` on custom/serviced media. Today WinMint patches `boot.wim` to force undocumented `setup.exe /legacy`. That works but couples the product to a Setup codepath Microsoft is deprioritizing.
3. **Offline debloat is optional, not sacred.** The maintainer accepts **online** debloat and package installs during FirstLogon. Heavy offline DISM AppX removal is optimization/air-gap, not a hard requirement.
4. **UX invariant is stronger than mechanism.** Explorer/desktop must **never** appear before the status UI and before all provisioning work completes. Shell-as-Winlogon remains the recommended lock — not because an ADR says so, but because alternatives lose the first-paint race (v1 lesson).

Existing ADRs and DESIGN grill locks are **tentative** for this vertical: treat as guidance until this spec and a green spike supersede them in docs.

## Solution

Reframe WinMint as a **workstation state compiler** with USB as the default delivery artifact:

```
Profile → BuildPlan → ImageServicing (thin offline) → bootable USB
    → WinPE apply-image (zero-touch, no ConX/legacy Setup)
    → unattended OOBE (Panther unattend)
    → autologon → Supervisor Shell + splash
    → DMA settle → online debloat + packages
    → unlock Explorer
```

### Pillars (grill-locked for this spec)

| # | Decision |
|---|----------|
| P1 | **Workstation state first** — compile debloat posture, policies, packages, DMA settle targets, account intent into one Profile; ISO/USB is output. |
| P2 | **Zero-touch USB demo** — insert media, walk away, return to a usable desktop. Interactive OOBE is **out** for the default solo-dev lane. |
| P3 | **WinPE apply replaces Setup** as the target install engine — `diskpart` + `dism /Apply-Image` + `bcdboot`; no `setup.exe /legacy` on the green path. |
| P4 | **Online-first debloat** — `debloat.mode` default `online`; AppX remove-list runs live in FirstLogon. `offline` keeps today’s DISM path. No `both` (ponytail: offline + existing `appx.safetyNet` already covers stragglers). |
| P5 | **Shell tenure unchanged** — Winlogon Shell = Supervisor until complete/failed-dwell/timeout; user never accesses desktop until unlock. |
| P6 | **Network is derived, not authored** — Plan fail-closed when Profile schedules online AppX removes or non-stub package jobs and harness provides no outbound path. **Package install runtime failures** are best-effort + evidence per [ADR-011](../decisions/ADR-011-alpha-posture-and-package-delegation.md). No `network.*` Profile fields. |
| P7 | **Transitional coexistence** — current legacy-setup path stays until WinPE apply passes Smoke on 25H2 ARM64; then deprecate `Inject-Unattend.ps1` legacy patch. |

## Primary persona & demo

| | |
|--|--|
| **User** | Solo developer flashing once (ARM64-first; bare metal or Hyper-V) |
| **Demo** | Insert USB → unattended install → splash (never Explorer first) → DMA settle → debloat/packages → Explorer |
| **Non-negotiable** | No Explorer/desktop/taskbar/Start before provisioning completes |
| **Negotiable** | Offline debloat depth; exact WinPE layout; legacy path sunset date |

## User Stories

1. As a solo dev, I want one USB that installs and configures my workstation without a separate post-install tool, so that I do not hand-debloat after Setup.
2. As a solo dev, I want the install to need no keyboard input, so that “insert USB and walk away” is true.
3. As a solo dev, I want the first interactive surface after install to be WinMint splash—not Explorer—so that I know provisioning owns the session.
4. As a solo dev, I want debloat and package installs to run online during FirstLogon by default, so that removes stay current without rebuilding a heavy offline image.
5. As a solo dev, I want offline policy stamps (Edge debloat, DMA latch, Shell stamp) applied before first boot, so that posture is correct even when debloat is online.
6. As a solo dev, I want Plan to fail closed when network is required but unavailable at build/provision scheduling time, so that I do not start an online debloat/package run with no path out — while individual package install failures during FirstLogon record evidence and still unlock when invariants are green ([ADR-011](../decisions/ADR-011-alpha-posture-and-package-delegation.md)).
7. As a maintainer, I want WinPE apply to eliminate ConX/legacy Setup dependency, so that 26H2 media changes do not break the install seam.
8. As a maintainer, I want Smoke to prove the new apply lane on 25H2 ARM64 Hyper-V, so that regression is caught before legacy removal.
9. As a maintainer, I want `debloat.mode: offline` for air-gapped Profiles, so that today’s offline keep-flag path remains available.
10. As a maintainer, I want BuildPlan to emit separate artifacts for apply-phase vs OOBE-phase when useful, so that WinPE apply and Panther unattend are explicit.
11. As a maintainer, I want stage ordering and evidence digests extended—not a parallel imaging brain—so that ImageServicing invariants hold.
12. As a solo dev, I want unlock to Explorer only after complete/failed-dwell/timeout, so that Shell tenure rules from Smoke still apply.

## Implementation Decisions

### Product identity (docs + CONTEXT follow-on)

- **WinMint** = workstation state compiler; **delivery artifact** = bootable USB (ISO optional same payload).
- Retain user-supplied Source ISO ([ADR-001](../decisions/ADR-001-source-iso-legal.md) as *default prudent policy*, not immutable law).
- ADR-005/007/009 remain valid for offline mode; online mode shifts *primary* AppX work to ProvisioningSession.

### Install engine — WinPE apply (target)

Replace default boot path:

| Step | Owner | Action |
|------|-------|--------|
| 1 | Servicing / boot.wim | Custom `winpeshl.ini` → `LaunchApply.cmd` (not `setup.exe /legacy`) |
| 2 | LaunchApply.cmd | `wpeinit`; `diskpart` GPT layout (UEFI; align with today’s unattend disk intent) |
| 3 | LaunchApply.cmd | `dism /Apply-Image` from `install.wim` on install media to Windows partition |
| 4 | LaunchApply.cmd | `bcdboot` Windows\System32 → EFI System partition |
| 5 | LaunchApply.cmd | Copy **OOBE unattend** → `W:\Windows\Panther\unattend.xml` |
| 6 | LaunchApply.cmd | Copy **specialize** hooks if not solely in OOBE file (DMA Ireland latch) |
| 7 | LaunchApply.cmd | `wpeutil reboot` |

**No** `setup.exe`, **no** ConX, **no** `/legacy`.

Edition selection: use `dism /Get-WimInfo` + Profile/run index (same as today’s Pro default on multi-edition ISOs). Apply by index or name per existing ImageServicing metadata discipline.

Partition layout: start by **porting** current `BuildAutounattendXml` disk intent (EFI 100 MB, MSR 16 MB, primary extend) unless spike proves WinRE-first layout required; document delta if changed.

LabConfig (TPM/RAM/Secure Boot bypass for Hyper-V Smoke): stamp into **applied** image `HKLM\SYSTEM\Setup\LabConfig` offline before first boot, or retain boot.wim SYSTEM patch — spike chooses one; must not regress Smoke on no-vTPM VMs.

### Unattend split (recommended)

| File | Passes | Staged where | Purpose |
|------|--------|--------------|---------|
| `ApplyAnswer.xml` (name illustrative) | `windowsPE`-equivalent metadata only if needed | Not used by apply script if diskpart is scripted | Optional; may fold into cmd |
| `OobeAnswer.xml` | `specialize` (DMA latch) + `oobeSystem` | `Panther\unattend.xml` on applied image **and** ISO root for fallback | Autologon, OOBE hide, local account |

BuildPlan may emit one XML split into two files at plan time, or two explicit artifacts — implementer picks; tests assert OOBE content reaches Panther.

### ImageServicing — thin offline (default plan)

**Keep offline:**

- Mount/export/commit WIM metadata discipline
- StagePayload (Supervisor, bundle, jobs, SetupComplete)
- StampOfflineShell + autologon-related hive work
- StampOfflinePolicies (Edge debloat, WPBT, DeviceMetadata, Copilot-kill, etc.)
- InjectUnattend → **replaced by** `Stage-OobeUnattend` + `Patch-BootWimApply` (names illustrative)
- Optional drivers ([surface spec](2026-08-05-surface-catalog-drivers.md))
- Offline AppX/capability/feature removes when `debloat.mode` is `offline` (capabilities/features are **always** offline — DISM-only; mode does not move them online)

**Demote to optional (default `online`):**

- Bulk offline AppX removes when `debloat.mode: offline`; caps/features offline whenever listed (always DISM)

### ProvisioningSession — online debloat primary

When `debloat.mode` is `online` (default):

1. After DMA hard settle green, emit one **`appx.safetyNet`** job (existing kind — no new job type) with Profile AppX ids; same executor, primary not backup in this mode.
2. Capabilities / optional features: still offline DISM when listed (unchanged).
3. winget/scoop/wsl + product-constant jobs unchanged.

**Network gate (Plan-derived, not Profile):**

- `PlanRequiresNetwork(profile)` ⇒ true when `(debloat.mode == online && removeProvisionedAppx non-empty) || packages non-stub`.
- Supervisor: bounded connectivity probe before online jobs; if Plan required net and probe fails ⇒ `failed` path, splash, unlock after failed dwell.
- Distinct from `account.requireWifiDuringOobe` (OOBE Wi‑Fi page only; Smoke keeps `false`).

**Ordering:** paint → DMA settle (hard) → online debloat → package jobs → unlock.

### Lock mechanism

- **Keep** Winlogon Shell = Supervisor (P5).
- Machine setup (`SetupComplete.cmd --machine-setup`) still verifies/restamps Shell + autologon fail-closed.
- Reject first-login “fullscreen app over Explorer” unless a later spike proves equal reliability — out of this vertical.

### Profile contract (additive on `winmint.profile/v1`)

**Ponytail audit:** one new field (`debloat.mode`); no `network` block (derive at Plan); no `both`; no new job kind; `installEngine` stays **RunOptions** only.

#### Solo-dev default (omit `mode` — serializes absent; Plan treats absent as `online`)

```json
{
  "schemaVersion": "winmint.profile/v1",
  "account": {
    "mode": "localAutoLogon",
    "username": "dev",
    "passwordPath": ".scratch/dev.password",
    "requireWifiDuringOobe": true
  },
  "dma": {
    "enabled": true,
    "settle": {
      "locale": "en-US",
      "geoId": 244,
      "timeZoneId": "Pacific Standard Time",
      "locationServicesEnabled": true
    }
  },
  "debloat": {
    "removeProvisionedAppx": [
      "Microsoft.BingNews",
      "Microsoft.BingWeather"
    ]
  },
  "packages": {
    "winget": ["Anysphere.Cursor"]
  }
}
```

#### Air-gapped / offline AppX (explicit opt-in)

```json
"debloat": {
  "mode": "offline",
  "removeProvisionedAppx": ["Microsoft.BingNews"],
  "removeCapabilities": ["App.StepsRecorder~~~~0.0.1.0"],
  "disableOptionalFeatures": ["WorkFolders-Client"]
}
```

#### Field rules

| Field | Values | Default | Rules |
|-------|--------|---------|-------|
| `debloat.mode` | `online` \| `offline` | **`online`** (absent ⇒ online) | Controls **AppX list venue only** |
| `debloat.removeProvisionedAppx` | catalog ids | `[]` | Always validated ⊆ catalog; empty ⇒ no AppX work |
| `debloat.removeCapabilities` | catalog ids | `[]` | **Always offline DISM** regardless of `mode` |
| `debloat.disableOptionalFeatures` | catalog ids | `[]` | **Always offline DISM** regardless of `mode` |

| `mode` | AppX | Caps / features |
|--------|------|-----------------|
| `online` (default) | `appx.safetyNet` job after settle | offline stages if lists non-empty |
| `offline` | `RemoveProvisionedAppx` DISM stage | offline stages if lists non-empty |

**Not in Profile:** `network.*` (Plan derives); `installEngine` (RunOptions: `legacy` \| `winpeApply`, default flips at Gate C).

Wizard **`recommended`** preset: unchanged remove-list expansion; does not emit `mode` (online default). Air-gap toggle ⇒ `mode: offline` only.

**Serialize rule:** omit `debloat.mode` when `online` (same pattern as empty debloat omission today).

### Servicing stage ordering (target)

```
MountInstallWim
→ [RemoveProvisionedAppx?]      ← only when debloat.mode offline
→ [RemoveCapabilities?]
→ [DisableOptionalFeatures?]
→ [InjectDrivers?]
→ StampOfflinePolicies
→ StagePayload
→ StageOobeUnattend             ← Panther + ISO root oobe/specialize
→ StampOfflineShell
→ PatchBootWimApply             ← WinPE apply launcher (replaces legacy Inject-Unattend boot patch)
→ ExportWim
→ BuildIso
```

`Inject-Unattend.ps1` legacy path: **deprecated** after spike green; until then feature-flag or lane tag (`installEngine: legacy|winpeApply`).

### Modules (unchanged seams)

| Module | Change |
|--------|--------|
| **BuildPlan** | `debloat.mode` parse/default; `PlanRequiresNetwork`; split unattend; conditional AppX offline stage; reuse `appx.safetyNet` job when online |
| **ImageServicing** | new opcodes `PatchBootWimApply`, `StageOobeUnattend`; deprecate legacy boot patch |
| **ProvisioningSession** | online debloat primary path; network gate |
| **Cli / Wizard** | expose `debloat.mode` when needed; default solo-dev path hidden behind `online` default |

## Testing Decisions

### Seams ([TDD](../TDD.md))

| Seam | Prove |
|------|-------|
| **S1 — BuildPlan** | absent/`online` ⇒ `appx.safetyNet` job, no AppX DISM stage; `offline` ⇒ DISM, no safetyNet unless lists differ (ponytail: offline ⇒ no safetyNet for same ids); caps/features always DISM; `PlanRequiresNetwork` true/false matrix; unattend split |
| **S2 — ImageServicing** | stage order; `PatchBootWimApply` params; `RecordingElevatedPlanRunner` captures new opcodes; legacy flag still emits old patch when `installEngine: legacy` |
| **S3 — ProvisioningSession** | online debloat job runs after settle; network required + offline ⇒ failed path; Shell before Explorer order preserved |
| **S4 — Hyper-V Smoke** | **new acceptance bar:** WinPE apply lane on 25H2 ARM64; zero-touch; splash before Explorer; DMA hard; online debloat digest; unlock |

### Smoke Profile updates

- Enable virtual switch / NAT for guest internet (Hyper-V external or default switch with outbound).
- Acceptance Profile: `debloat.mode: online` with small remove-list pin (e.g. BingNews + BingWeather).
- Stub jobs remain; add digest key for online remove outcomes.
- **`installEngine: winpeApply`** on acceptance run options (name illustrative).

### `just check`

- No DISM, no real boot.wim mount in unit tests.
- Fixture: minimal `LaunchApply.cmd` content assertions; plan stage list snapshots.

### Maintainer prove-out (post-ticket)

- Physical or Hyper-V 25H2 ARM64: USB → walk away → desktop without touching keyboard.
- Compare timing vs legacy path (informational, not gate).

## Success Criteria (exit gates)

### Gate A — Spike (first ticket)

- [ ] WinPE apply installs serviced 25H2 ARM64 Pro WIM to Hyper-V Gen2 VM zero-touch
- [ ] No `setup.exe /legacy` in boot path
- [ ] Autologon + Shell stamp + Machine setup green
- [ ] Splash paints before Explorer (S4 ordering)
- [ ] DMA hard fields green

### Gate B — Online debloat (second ticket)

- [ ] Acceptance Profile `debloat.mode: online` removes pinned AppX live with network
- [ ] Offline DISM stage **not** emitted for that Profile
- [ ] Fail-closed when network required and VM isolated — evidence + failed splash + unlock

### Gate C — Legacy sunset (third ticket)

- [ ] Default `installEngine` = `winpeApply`
- [ ] Legacy path behind explicit opt-in only
- [ ] `Inject-Unattend.ps1` legacy block removed or dead-code flagged
- [ ] Docs: CONTEXT product identity; DESIGN acceptance; this spec linked from DESIGN cold history

## Out of Scope

- Autopilot / Intune / cloud provisioning (Model D)
- Post-install-only tool without USB (Model C as primary)
- Dropping Shell tenure / allowing Explorer before splash
- Interactive OOBE as default solo-dev path
- Sysprep/generalize reference-machine factory (Model B) — follow-on if fleet need appears
- UUP/download helper without legal review
- Schema `winmint.profile/v2` unless additive fields exhaust v1
- Wizard UX polish beyond `debloat.mode` exposure
- ReFS / exotic partition layouts
- Removing offline debloat entirely (stays as `debloat.mode: offline`)
- `debloat.mode: both` (use offline + safetyNet only if offline pass leaves stragglers — not a Profile enum)

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| WinPE apply partition/boot edge cases | Spike on Hyper-V + one bare-metal; keep legacy fallback until Gate C |
| Online debloat slower than offline on first boot | Accept for solo-dev; show progress on splash |
| Network absent on metal | Fail-closed; user runs with `debloat.mode: offline` or fixes connectivity |
| `/legacy` removed from future media | WinPE apply path has no dependency |
| Panther unattend ignored on first boot | Apply script copies unattend; specialize latch also in offline hive if needed |

## Phased ticket map (suggested)

| Order | Slice | Delivers |
|-------|-------|----------|
| 1 | **Spike: WinPE apply + Smoke Gate A** | `PatchBootWimApply`, apply cmd, split unattend, legacy coexistence |
| 2 | **Online debloat primary** | `debloat.mode`, jobs, network gate, Gate B |
| 3 | **Legacy sunset + docs** | default engine, CONTEXT/DESIGN refresh, Gate C |

One issue per session per [AGENTS.md](../../AGENTS.md); do not mega-epic.

## Further Notes

- **Relationship to ConX discussion:** this spec intentionally avoids fixing ConX; it routes around Setup entirely on the green path.
- **Relationship to [KEEPFLAG](../design/KEEPFLAG.md):** catalog validation unchanged; *execution venue* moves default from ImageServicing to ProvisioningSession.
- **Relationship to [Smoke](2026-07-27-smoke.md):** extends acceptance; does not fork Hyper-V-only executor/settle rules.
- After maintainer sign-off: GitHub issues [#70](https://github.com/yanai-sh/winmint/issues/70) · [#71](https://github.com/yanai-sh/winmint/issues/71) · [#72](https://github.com/yanai-sh/winmint/issues/72); `ready-for-agent` on **#70** only.

## Open Questions (resolve in spike ticket 1)

1. **WinRE partition** — retain simplified 3-partition (EFI/MSR/Windows) vs 4-partition WinRE-first from community 25H2 guides?
2. **LabConfig** — patch boot.wim SYSTEM vs offline-stamp applied image SOFTWARE/SYSTEM?

**Closed by profile audit:**

3. **`installEngine`** — **RunOptions only** (`legacy` \| `winpeApply`).
4. **Online debloat job** — **reuse `appx.safetyNet`**; no new kind.
5. **`network.*` in Profile** — **reject**; Plan derives requirement.
6. **`debloat.mode: both`** — **reject**; offline mode + organic safetyNet on stragglers if ever needed later.
