# Operator Score Raise Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Use superpowers:verification-before-completion before any â€œscore raisedâ€ or â€œdoneâ€ claim. Prefer ponytail / YAGNI on every task.

**Goal:** Raise the triple-review scores from Prospect **4** / Full-flow **5** / Architect **6** to honest alpha targets Prospect **6â€“7** / Full-flow **7** / Architect **7â€“8** by fixing operator defaults, lobby tryability, and docs honesty â€” without new frameworks.

**Architecture:** Keep the three deep modules (BuildPlan â†’ ImageServicing/`RunPlan` â†’ ProvisioningSession). Score lift is **recipe + docs + thin harness flags**, not new planners. Land existing WIP (Index:1 LaunchApply verify + BuildIso hash) first; then one Primary recipe that matches DESIGN; then prospect lobby; then mid-wait polish.

**Tech Stack:** Justfile, pwsh 7.6+, WinMint.Cli / WinMint.Wizard (.NET 11), `tools/metal/*`, existing `just check` (MTP traits).

**Research sources:** [Prospect](0d2999d7-ea40-45a8-9f29-0948011947d8) Â· [Full-flow](a1c7660b-a607-488e-a0e0-7eaf2bcdf455) Â· [Architect](943e26d4-3514-49c1-a2d7-6e20d2ca21e9) Â· [Grill lock](db3f1d28-ebbc-4189-adb3-d697d8f91ecc) Â· prior triple review (Prospect 4 / Full-flow 5 / Architect 6).

## Global Constraints

```
GRILL LOCK â€” score-raise without bloat
- Goal: Prospect 6â€“7 / Full-flow 7 / Architect 7â€“8. No fake 9â€“10.
- Prefer: Justfile/docs/harness flags over new modules; deepen seams, donâ€™t add layers.
- Ship: primary-gate (Release+package-strict) â‰  default metal Test; STALL truth; just wizard; samples map; plan/validate first win.
- Forbid: Wizard-required path; product-default package-strict; mega progress/observability; USB-as-exit; Clean Arch split; guest pwsh monolith; Test metal sold as Primary.
- Deletion/doc honesty > new surface area. One recipe beats eight. Ponytail: if a fix needs a new project, itâ€™s wrong for this plan.
- ARM64 host; elevate only Servicing `pwsh -File`; no guest pwsh product runtime.
```

### Locked decisions (grill recommendations â€” confirm before coding if disputed)

| # | Decision | Locked answer |
|---|----------|---------------|
| Q1 | `just metal` QUALITY default | **Keep `Test`**. Add `just primary-gate` (or `metal-primary`) that forces **Release**. |
| Q2 | `--package-strict` | **Only** on primary-gate / explicit wipe build. Day-to-day metal stays `--package-audit-strict` (ADR-011). |
| Q3 | Wizard vs CLI | **CLI-first** + `just wizard` launch. Do not gate Primary on Wizard completeness. |
| Q4 | Gate B definition | Pre-wipe Release Apply + `metal-acceptance.json`. Wipe remains #96 human. |
| Q5 | Apply STALL | Host Apply stays advisory/watch-file only. Do **not** copy Smoke fail-fast kill into Apply. |

### Honest score targets

| Lens | Now | After this plan | Ceiling until #96 green |
|------|-----|-----------------|-------------------------|
| Prospect | 4 | **6â€“7** | ~7.5 (preview SDK + multi-hour DISM remain) |
| Full-flow | 5 | **7** | ~8 |
| Architect | 6 | **7â€“8** | ~8.5 |

---

## File map

| File | Responsibility |
|------|----------------|
| `servicing/Patch-BootWimApply.ps1`, `Build-Iso.ps1`, `RunPlan.ps1` | WIP: Index:1 verify, hash refresh, failure.json clear (land) |
| `tools/metal/Assert-MetalEvidence.ps1`, `Invoke-MetalApply.ps1` | WIP assert + optional `--package-strict` passthrough for primary |
| `src/WinMint.Orchestrator/ImageServicing.cs` | WIP: do not pass `wimIndex` to PatchBootWimApply |
| `Justfile` | `wizard`, `plan`, `watch-apply`, `primary-gate`; keep `metal` Test |
| `README.md` | Outsider lobby; STALL truth; Primary pointer; demote Testing loops / Agents |
| `samples/README.md` | smoke vs sl7 map (new) |
| `docs/design/SPLASH.md`, `Profile.cs` comments | Autounattend â†’ OobeUnattend/Panther |
| `docs/design/SECRETS.md` | `.scratch/sl7.password` one-liner |
| `tools/metal/primary-gate-wizard.ps1` | Optional thin pwsh twin (P1) |
| `tools/metal/Assert-PrimaryGuestEvidence.ps1` | Optional post-#96 (Later â€” not P0) |

---

## Phase P0 â€” Architect trust + Primary honesty

### Task 1: Land Index:1 / hash WIP

**Files:**
- Modify: `servicing/Patch-BootWimApply.ps1`, `servicing/Build-Iso.ps1`, `servicing/RunPlan.ps1`
- Modify: `tools/metal/Assert-MetalEvidence.ps1`
- Modify: `src/WinMint.Orchestrator/ImageServicing.cs`
- Modify: `tests/WinMint.Tests/WinPeApplyPlanTests.cs` (and related metal fixture digest if present)

**Interfaces:**
- Produces: skip-only-after LaunchApply `/Index:1` verify; live `outputIso.sha256` match; PatchBootWimApply without source `wimIndex`

- [x] **Step 1:** Confirm dirty WIP matches architect brief (LaunchApply Index:1, BuildIso hash refresh, ImageServicing no longer passes `wimIndex`).
- [x] **Step 2:** Run focused tests:

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj -- --filter-class WinMint.Tests.WinPeApplyPlanTests
```

Expected: PASS.

- [x] **Step 3:** Run `just check` (or equivalent format + unit filter excluding S4/Metal).
- [x] **Step 4:** Commit as `fix(servicing): verify LaunchApply Index:1; refresh ISO digests` (only when user asks to commit).

**Verify:** Do not claim Gate B green without `just metal-assert` on a workdir when asserting wipe media.

---

### Task 2: Primary-gate recipe (Release + package-strict)

**Files:**
- Modify: `Justfile`
- Modify: `tools/metal/Invoke-MetalApply.ps1` (add optional `-PackageStrict` switch â†’ Cli `--package-strict`)
- Modify: `tools/metal/primary-gate-wizard.sh` (point Gate B + wipe at one recipe; delete Stage 5 double-build if redundant)

**Interfaces:**
- Consumes: existing `dotnet â€¦ build â€¦ --image-quality Release --package-audit-strict`
- Produces: `just primary-gate ISO=â€¦` that builds wipe-capable ISO once

- [x] **Step 1:** Keep `just metal` default `QUALITY=Test` (Q1 locked).
- [x] **Step 2:** Add Justfile recipe (exact intent):

```just
# Primary Gate B + wipe ISO: Release + package-strict. Not day-to-day metal.
primary-gate ISO WORK=".scratch/sl7-build" PROFILE="samples/sl7.profile.json":
    pwsh -NoProfile -File '{{justfile_directory()}}/tools/metal/Invoke-MetalApply.ps1' -Iso '{{ISO}}' -Work '{{WORK}}' -Profile '{{PROFILE}}' -ImageQuality Release -PackageStrict -ExpectDrivers
```

- [x] **Step 3:** In `Invoke-MetalApply.ps1`, add `[switch] $PackageStrict` and append `--package-strict` to the Cli `build` invocation when set (keep `--package-audit-strict`).
- [x] **Step 4:** Update `primary-gate-wizard.sh` stages 4â€“5 to call `just primary-gate` (or the same flags) **once** â€” no second multi-hour Apply solely to add package-strict.
- [x] **Step 5:** Banner comment above `metal`: `Test metal â‰  Primary. Wipe ISO: just primary-gate ISO=â€¦`.

**Verify:** Dry-read recipe strings; do not run multi-hour Apply in CI. Optional: `Select-String` self-check that primary-gate line contains `Release` and `PackageStrict`.

---

### Task 3: Kill STALL_SUSPECT Apply lie

**Files:**
- Modify: `README.md` (Testing loops / apply-status line)
- Optionally: `docs/TDD.md` if it repeats the lie

- [x] **Step 1:** Grep repo for `STALL_SUSPECT` next to apply-status; remove Apply association.
- [x] **Step 2:** Document Apply watch as:

```powershell
Get-Content .scratch\sl7-build\apply-status.txt -Wait
# stage=opcode|done|failed:*  updated=  log=workdir\logs\NN-Opcode.log
# STALL_SUSPECT is Smoke VM only (tools/vm), not Apply.
```

- [x] **Step 3:** Add `just watch-apply WORK=.scratch/sl7-build` wrapping that `Get-Content`.

---

## Phase P0 â€” Prospect tryability

### Task 4: `just wizard`

**Files:**
- Modify: `Justfile`

- [x] **Step 1:** Add:

```just
wizard:
    dotnet run --project src/WinMint.Wizard/WinMint.Wizard.csproj
```

- [x] **Step 2:** Smoke: `just wizard` starts (manual; kill after splash). No installer/AOT.

---

### Task 5: `samples/README.md`

**Files:**
- Create: `samples/README.md`
- Modify: `README.md` (one link under Quickstart)

- [ ] **Step 1:** Write â‰¤40 lines mapping:

| Sample | Purpose | Lane | Wipe risk |
|--------|---------|------|-----------|
| `smoke.profile.json` | Hyper-V plumbing | Test | No |
| `acceptance.profile.json` | Smoke acceptance pins | Test | No |
| `israel.profile.json` | DMA settle lab | Test | No |
| `sl7.profile.json` | Primary metal template | Release via `primary-gate` | Yes â€” needs passwordPath |

- [ ] **Step 2:** One line: host preset `recommended` expands to remove-lists at plan time; JSON never embeds preset names.
- [ ] **Step 3:** Point `sl7` password at `.scratch/sl7.password` (SECRETS).

---

### Task 6: README lobby rewrite (outsider)

**Files:**
- Modify: `README.md`
- Skill assist: `writing-guidelines` when editing copy

**Sections (order):**
1. Tagline + ADR-001 (keep)
2. **What you get** (4â€“6 lines: Profile â†’ bootable ISO; offline servicing + FirstLogon Supervisor; you supply Microsoft ISO)
3. **Status** outsider English: Alpha Â· Hyper-V smoke on real Source ISO Â· Wizard via `just wizard` Â· Primary wipe = maintainer gate (#96), not GA
4. **Try in 5 minutes** (no Source ISO): `just wizard` **or** `just plan` / validate sample
5. **Build later**: Source ISO + admin + multi-hour DISM; `just primary-gate ISO=â€¦` for wipe; `just metal` for iterative Test Gate B
6. **Maintainer** (collapsed): former Testing loops
7. Footer: Design Â· Issues Â· License â€” demote Agents off lobby

- [ ] **Step 1:** Draft README against writing-guidelines (terse, no fake Proven).
- [ ] **Step 2:** Cold read: can a visitor state product outcome + run plan/wizard in 5 minutes without Agents/CONTEXT?
- [ ] **Step 3:** Link Microsoft ISO download as pointer only (no redistribution).

---

### Task 7: `just plan` first win

**Files:**
- Modify: `Justfile`

- [ ] **Step 1:** Add:

```just
plan PROFILE="samples/smoke.profile.json" OUT=".scratch/plan":
    dotnet run --project src/WinMint.Cli -- plan '{{PROFILE}}' --out '{{OUT}}'
```

- [ ] **Step 2:** README â€œTry in 5 minutesâ€ uses `just plan` as success before ISO.
- [ ] **Step 3:** Optional S: print remove/job counts on Cli plan stdout only if already trivial â€” **do not** port PlanDiff for lobby.

---

## Phase P1 â€” Full-flow polish

### Task 8: SECRETS + Wiâ€‘Fi honesty

**Files:**
- Modify: `docs/design/SECRETS.md`
- Modify: `README.md` Primary pointer

- [ ] **Step 1:** One-liner create password file:

```powershell
Set-Content -Path .scratch/sl7.password -Value 'your-lab-password' -NoNewline
```

- [ ] **Step 2:** Note `requireWifiDuringOobe: true` on sl7 â†’ OOBE Network page expected; not â€œwalk away from Wiâ€‘Fi.â€

---

### Task 9: Autounattend â†’ OobeUnattend living docs

**Files:**
- Modify: `docs/design/SPLASH.md`
- Modify: `src/WinMint.Orchestrator/Profile.cs` (XML doc comment only)
- Leave cold `docs/research/*` unless one line pointer

- [ ] **Step 1:** Grep living docs for product Autounattend; rename to OobeUnattend / Panther.
- [ ] **Step 2:** Confirm `Stage-OobeUnattend.ps1` / LaunchApply copy path still match docs.

---

### Task 10: Discover primary-gate + flash note

**Files:**
- Modify: `Justfile` (already has `primary-gate` from Task 2)
- Modify: `README.md`
- Optional Create: `tools/metal/primary-gate-wizard.ps1` (thin twin of `.sh`)

- [ ] **Step 1:** README: â€œWipe path: `just primary-gate ISO=path\to\source.iso` then flash `WORK\out.iso`.â€
- [ ] **Step 2:** Flash procedure (docs only): UEFI USB; any reliable flasher; verify ISO sha vs `evidence.json` `outputIso.sha256`; expect WinPE LaunchApply not Setup.
- [ ] **Step 3 (optional):** pwsh twin of bash wizard if Git Bash tax remains.

---

### Task 11: Apply status visibility (thin)

**Files:**
- Prefer: `Justfile` `watch-apply` (Task 3) only
- Optional M: Cli `status --work` reusing Wizard `ApplyStatusReader` logic â€” **only if** operators still blind after Task 3

- [ ] **Step 1:** Ship `watch-apply` first; stop if enough.
- [ ] **Step 2:** If Cli poll needed: extract reader to shared library or duplicate 20-line poller in Cli â€” no OpenTelemetry.

---

## Phase Later (explicitly out of P0/P1)

- `Assert-PrimaryGuestEvidence.ps1` + Primary-gate Stage 10 wire (after one #96 wipe)
- Wizard calm OOBE IA (separate plan)
- USB productization / Rufus fork
- Apply stall-kill (false-positive risk)
- Product-default package-strict

---

## Execution order (dependencies)

```
Task 1 (land WIP)
  â†’ Task 2 (primary-gate recipe)
  â†’ Task 3 (STALL + watch-apply)
  â†’ Task 4â€“7 (wizard, samples, README, plan)  // parallelizable after 1
  â†’ Task 8â€“10 (SECRETS, OobeUnattend, flash discoverability)
  â†’ Task 11 only if needed
```

Prospect lobby (4â€“7) must **not** invent a fourth Apply recipe â€” point at `primary-gate` / `metal` from Task 2.

---

## Verification gate (before claiming scores raised)

Per `verification-before-completion`:

1. `just check` green (or document excluded failures).
2. Grep: README does **not** claim `STALL_SUSPECT` for Apply.
3. `just --list` shows `wizard`, `plan`, `primary-gate`, `watch-apply`.
4. Cold visitor checklist (Prospect Task 6 done criteria) walked once.
5. Do **not** claim Full-flow 7 without documenting flash + primary-gate in README.
6. Do **not** claim Architect 8 without Task 1 landed + Task 2 recipe present.
7. Do **not** claim Primary gate met without #96 wipe evidence (out of this plan).

---

## Self-review

| Requirement | Task |
|-------------|------|
| Land Index:1 / hash | 1 |
| Primary â‰  Test metal | 2 |
| STALL honesty | 3 |
| just wizard | 4 |
| samples map | 5 |
| Lobby rewrite | 6 |
| plan first win | 7 |
| password / Wiâ€‘Fi | 8 |
| OobeUnattend docs | 9 |
| primary-gate discover + flash | 10 |
| status watch | 3 / 11 |
| Grill forbid list | Global Constraints |
| No fake 9â€“10 | Score targets table |
