# Operator build feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (or `executing-plans`) task-by-task. Use **dedicated specialized subagents** with model **`composer-2.5`** only (see Execution protocol). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shared human Apply trail (no DISM bars) for Wizard Review + elevated/CLI, with mandatory indeterminate motion and real `%` only when trail proof lines provide it.

**Architecture:** One Servicing DISM wrapper appends raw stdout/stderr to `$WorkDirectory/dism-transcript.log` (stage banners). Kernels keep milestone `Write-Output`. `Invoke-WinMintLoggedKernel` drops residual bar lines from console (and trail). Wizard Review deepens existing pane: filter heartbeats in `StatusTail`, parse `quality hash N%` for determinate progress, keep spinner when unknown. No Spectre, no event bus, no `apply-status` key changes.

**Tech Stack:** PowerShell 7.6+, existing `Write-WinMintHostProgress.ps1`, Avalonia Wizard Review bindings, xUnit `ApplyProgressTests`, contract `Test-WinMintHostProgress.ps1`.

**Spec:** [docs/superpowers/specs/2026-10-07-operator-build-feedback-design.md](../specs/2026-10-07-operator-build-feedback-design.md)

## Global Constraints

- `#requires -Version 7.6` on touched host/servicing scripts
- No Spectre / OpenTUI / new NuGet / Gallery TUI packages
- Do not change `apply-status.txt` keys: `updated`, `stage`, `log`
- No fake completion `%` from stage index alone (optional `Step i/n` text only)
- `reg.exe` spam is follow-up — not required in this plan
- Smoke Watch dashboard / Check-status chrome out of scope
- Commits only when the human asks

## Execution protocol (mandatory)

Parent agent does **not** implement code itself. For each task below, launch **exactly one** specialized subagent via Task with:

- `model`: `composer-2.5`
- `subagent_type`: as listed on the task
- Full prompt: task goal, file list, acceptance checks, link to this plan + design spec, Global Constraints
- Wait for completion; run the task’s verify command; only then start the next task
- On failure: resume the same subagent with the failure output (still `composer-2.5`)

| Task | Subagent (`subagent_type`) | Why |
|------|----------------------------|-----|
| 1 DISM wrapper + contract | `ponytail-imageservicing` | Servicing DISM boundary |
| 2 Wire streaming DISM call sites | `ponytail-imageservicing` | Kernel / helper DISM invocations |
| 3 Logged-kernel bar filter | `ponytail-hosts` | Host console tee + helper detectors |
| 4 Wizard Review motion + unit tests | `generalPurpose` | Avalonia + WizardViewModel |
| 5 Gate | `ponytail-hosts` | `just check` |

## File map

| File | Responsibility |
|------|----------------|
| **Create** `servicing/Invoke-WinMintDism.ps1` | `Invoke-WinMintDism` → transcript; optional `-PassThruText` |
| Servicing kernels listed in Task 2 | Replace bare `& dism.exe` / `Start-Process dism` |
| `servicing/Invoke-ServicingPlan.ps1` | Bar filter in logged-kernel tee |
| `tools/host/Write-WinMintHostProgress.ps1` | `Test-WinMintDismProgressBarLine` |
| `tests/contract/Test-WinMintDism.ps1` + `Test-WinMintHostProgress.ps1` | Contracts |
| Wizard Review VM + axaml + `ApplyProgressTests` | Pane motion + filter + hash `%` |

---

### Task 1: DISM wrapper + contract

**Subagent:** `ponytail-imageservicing` @ `composer-2.5`

- [ ] Create `servicing/Invoke-WinMintDism.ps1`
- [ ] Create `tests/contract/Test-WinMintDism.ps1`
- [ ] Verify: `pwsh -NoProfile -File tests/contract/Test-WinMintDism.ps1`

### Task 2: Wire streaming DISM call sites

**Subagent:** `ponytail-imageservicing` @ `composer-2.5`

- [ ] Wire Mount/Export/Quality/Drivers/PatchBoot/Get/Remove/Set/Mount helpers
- [ ] Verify: no bare streaming dism outside wrapper; Test-WinMintDism green

### Task 3: Logged-kernel defense + shared bar detector

**Subagent:** `ponytail-hosts` @ `composer-2.5`

- [ ] `Test-WinMintDismProgressBarLine` + logged-kernel skip
- [ ] Extend `Test-WinMintHostProgress.ps1`
- [ ] Verify: `pwsh -NoProfile -File tests/contract/Test-WinMintHostProgress.ps1`

### Task 4: Wizard Review pane

**Subagent:** `generalPurpose` @ `composer-2.5`

- [ ] Filter heartbeats/bars; parse hash `%`; ProgressBar bindings; step cue text
- [ ] Extend `ApplyProgressTests`
- [ ] Verify: `dotnet test … --filter FullyQualifiedName~ApplyProgress`

### Task 5: Full gate

**Subagent:** `ponytail-hosts` @ `composer-2.5`

- [ ] `just check` green
- [ ] Mark design spec status `accepted` if check passes

## Out of scope

- `reg.exe` quieting; JSONL bus; Smoke Watch UI; fake `%` from `11/14`
