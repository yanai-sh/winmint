# C# NuGet Dependency Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the standing C# NuGet tiers bar in ADR-004 so agents can answer “may I add package X?” without inventing policy.

**Architecture:** Docs-only. Expand ADR-004’s one-line NuGet bullet into short tiers + why-not-BCL. Package versions and inventory stay in `.csproj` / the one-shot design spec — not in the ADR.

**Tech Stack:** Markdown ADR under `docs/decisions/`. Spec: `docs/superpowers/specs/2026-10-06-csharp-nuget-dependency-gate-design.md`.

## Global Constraints

- No PackageReference adds, removes, or version bumps
- No `Directory.Packages.props` / CPM
- No contract allowlist harness
- ADR = choice + rejected — no NuGet id catalog, no version pins (ADR-014)
- Keep ADR-004 short; tiers match the design spec table

## File map

| File | Responsibility |
|------|----------------|
| `docs/decisions/ADR-004-stack-and-guest-control-plane.md` | Standing NuGet tiers bar (Decision + Rejected) |
| `docs/superpowers/specs/2026-10-06-csharp-nuget-dependency-gate-design.md` | Already committed audit + verdict (do not restate inventory in ADR) |

---

### Task 1: ADR-004 NuGet tiers

**Files:**
- Modify: `docs/decisions/ADR-004-stack-and-guest-control-plane.md`

**Interfaces:**
- Consumes: design spec §§ Tiers, Gate, Rejected, ADR-004 shape
- Produces: Decision bullets for NuGet tiers; Rejected bullets for CPM / living allowlist / enforce-now harness

- [ ] **Step 1: Update the header `Updated` date** to `2026-10-06` (keep Status Accepted and original Date).

- [ ] **Step 2: In `### Rejected`, after the existing guest-pwsh paragraph, append:**

```markdown
Also rejected for NuGet posture: Central Package Management as the dependency gate; a living deps allowlist / `deps.md`; an enforce-now contract harness that fail-closes on PackageReferences (revisit only if Contracts / Orchestrator / WinPeApply gain packages).
```

- [ ] **Step 3: Replace the Decision bullet**

```markdown
- NuGet is Microsoft-thin; every package needs “why not BCL.” Wizard-only MVVM toolkit stays off the ISO.
```

**with:**

```markdown
- NuGet is Microsoft-thin; every new `PackageReference` needs one sentence “why not BCL (or inbox platform API)?” Prefer Microsoft-owned or packages already on the Wizard path. Tiers:
  - **ISO / AOT** (Provisioning, WinPeApply): prefer zero runtime NuGet; build-only (`PrivateAssets`) Win32 generators OK when BCL/`LibraryImport` alone is worse; no UI, DI, logging-provider, or HTTP-stack packages.
  - **Brain** (Contracts, Orchestrator): zero PackageReferences.
  - **Host adapters** (Cli, Wizard): host UX only (CLI parse, Avalonia, Wizard MVVM); must not become Orchestrator/ISO dependencies. Wizard-only MVVM toolkit stays off the ISO.
  - **Build/test** (Directory.Build.props analyzers, Tests): analyzers `PrivateAssets`; test runner OK; no product runtime leak.
```

- [ ] **Step 4: Verify** — read the ADR end-to-end; confirm no package id list, no versions, no inventory table. Grep the repo for other “NuGet is Microsoft-thin” one-liners that should point at the expanded bar (update only if they contradict; do not duplicate the tiers table elsewhere).

```powershell
rg -n "NuGet is Microsoft-thin|PackageReference|why not BCL" docs/ AGENTS.md CONTEXT.md
```

Expected: ADR-004 holds the tiers; design spec remains the audit artifact; no second living policy file.

- [ ] **Step 5: Commit**

```powershell
git add docs/decisions/ADR-004-stack-and-guest-control-plane.md
git commit -m @"
docs: expand ADR-004 NuGet tiers bar

"@
```

---

### Task 2: Gate

- [ ] **Step 1: Confirm no `.csproj` / `Directory.Build.props` diffs in the change set**

```powershell
git status
git diff --name-only HEAD~1
```

Expected: only ADR-004 (and this plan if committed separately).

- [ ] **Step 2: `just check` green** (docs-only change; gate still required per AGENTS.md)

---

## Spec coverage (self-review)

| Spec requirement | Task |
|------------------|------|
| Standing gate / tiers / why-not-BCL | Task 1 |
| Current-state verdict (keep lean set) | Already in design spec; no code task — Task 2 forbids PackageReference churn |
| ADR-004 shape, no id catalog / versions | Task 1 Steps 3–4 |
| Rejected CPM / allowlist / enforce-now harness | Task 1 Step 2 |
| No package churn | Global Constraints + Task 2 |
