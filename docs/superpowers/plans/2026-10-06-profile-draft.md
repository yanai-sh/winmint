# #151 ProfileDraft — shared Profile assembly — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One deep Profile-assembly module shared by Comfort bootstrap (`CuratedDefaults`) and Wizard shipping draft (`WizardDraftCompile`). Callers stop forking Profile field wiring.

**Architecture:** New Orchestrator module `ProfileDraft`: Station outcome + account + DMA + packages (+ optional advanced multiline) → `Profile`. `WizardDraftCompile` calls it then pins shipping `HostComposeOptions` (ADR-016). `CuratedDefaults` stays bootstrap username/password/emit adapter over Comfort + `ProfileDraft`. No merge of emit into draft compile.

**Tech Stack:** .NET 11 / C#, xUnit (`CuratedDefaultsTests`, `WizardDraftCompileTests`, new `ProfileDraftTests`).

## Global Constraints

- Spec: GitHub issue #151 (architecture review Worth exploring #1).
- Implement **after #150** ChipAxisResolve (Wizard packages already one seam).
- ADR-005 / ADR-016 unchanged (no outcome names in JSON; shipping pins stay on WizardDraftCompile).
- `CuratedDefaults.NewBootstrapPassword` / `BootstrapUsername` / `TryEmit` stay on CuratedDefaults.
- Cli emit remains Profile-only (no forced HostComposeOptions on emit path).
- Out of scope: Gate B #145, ChipAxisResolve body (#150), Smoke S4, Catalog package-set.
- Ponytail: smallest shared Profile builder; do not invent a port.
- No profile schema bump; CONTEXT only if a new coined term sticks (prefer reuse “draft”).
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- `just check` before final commit.
- Branch `sdd/profile-draft` in worktree; commit per task Commit step.
- After land: close issue with summary.

## File map

| File | Responsibility |
|------|----------------|
| `src/WinMint.Orchestrator/ProfileDraft.cs` (new) | Outcome + account + DMA + packages → Profile |
| `src/WinMint.Orchestrator/WizardDraftCompile.cs` | Call ProfileDraft; own HostComposeOptions pins + request DTO |
| `src/WinMint.Orchestrator/CuratedDefaults.cs` | Comfort bootstrap → ProfileDraft; keep emit/password |
| `tests/WinMint.Tests/ProfileDraftTests.cs` (new) | Shared assembly facts |
| `tests/WinMint.Tests/CuratedDefaultsTests.cs` | Still green through adapter |
| `tests/WinMint.Tests/WizardDraftCompileTests.cs` | Still green; shipping pins unchanged |

---

### Task 1: ProfileDraft module + tests

- [ ] **Step 1: Failing tests** — Comfort-equivalent Profile from seed packages; advanced merge; bad geo fails; remove-lists from outcome seed not from packages
- [ ] **Step 2: Implement `ProfileDraft`**
- [ ] **Step 3: Tests pass; Commit**

```
feat(host): ProfileDraft shared Profile assembly
```

---

### Task 2: Wire WizardDraftCompile + CuratedDefaults

- [ ] **Step 1: Both call ProfileDraft; delete duplicated Profile `new` wiring**
- [ ] **Step 2: Existing CuratedDefaults + WizardDraftCompile tests green**
- [ ] **Step 3: `just check`; Commit**

```
refactor(host): CuratedDefaults and WizardDraft via ProfileDraft
```

- [ ] **Step 4: Close issue**

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| One Profile assembly seam | 1 |
| Wizard keeps shipping options | 2 |
| Curated keeps bootstrap/emit | 2 |
| After #150 | implement gate |
| `just check` | 2 |
