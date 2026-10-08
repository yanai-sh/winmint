# Operator events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Canonical `apply-events.jsonl` wide events; Spectre Watch + Wizard Review render the same story; DISM stays in transcript; status keys unchanged with `log=` → events file.

**Architecture:** Servicing appends JSONL via one writer; plan emits `run.*` / `opcode.end`; rare `proof` from kernels; Watch is a small .NET console (Spectre); Wizard parses JSONL; stage `.log` may remain for kernel tee but is not the operator trail.

**Tech Stack:** pwsh 7.6+, net11.0, Spectre.Console (Watch only), Avalonia Wizard, existing contracts/xUnit.

## Global Constraints

- `apply-status` keys: `updated` / `stage` / `log` only; `log=` → `apply-events.jsonl`
- No heartbeat events; elevated liveness = `Write-Progress` + status
- Spectre only in Watch project; not Servicing / Wizard
- `summary` ≤ 80 chars; no DISM bars in JSONL
- Gate: `just check`

## File map

| File | Role |
|------|------|
| `servicing/Write-WinMintApplyEvent.ps1` | Append JSONL |
| `servicing/Invoke-ServicingPlan.ps1` | Emit events; status `log=` events path; heartbeat without LogWriter |
| `src/WinMint.Orchestrator/ApplyEvents.cs` | Shared JSONL read + row format |
| `src/WinMint.Watch/` | Spectre Live console |
| `tools/host/Watch-Host.ps1` | smoke/apply launch Watch exe; check keeps old path |
| `src/WinMint.Wizard/.../ApplyBuildPresentation.cs` | Event list from JSONL |
| `tests/contract/Test-WinMintApplyEvent.ps1` | Writer contract |
| Update host-progress / fail-closed / ApplyProgress tests | Schema + presentation |

## Tasks

### Task 1: Event writer + plan emit
- [x] Create writer + contract
- [x] Wire plan: run.start/end, opcode.end; `log=` events file
- [x] Heartbeat stays on stage `.log` + Write-Progress (not JSONL)
- [x] Fix ServicingPlanFailClosedTests expecting events file

### Task 2: Orchestrator ApplyEvents reader
- [x] Parse JSONL; format display rows; proof percent helper
- [x] Unit tests

### Task 3: WinMint.Watch Spectre
- [x] New console project + Spectre.Console; add to slnx
- [x] Live header + event table from status + JSONL
- [x] Watch-Host.ps1 launches exe for smoke/apply

### Task 4: Wizard presentation
- [x] ApplyBuildPresentation from events
- [x] Update ApplyProgressTests

### Task 5: Proof event (quality hash)
- [x] Emit `proof` from Add-QualityUpdates when hash % known

### Task 6: Gate
- [x] `just check` green
