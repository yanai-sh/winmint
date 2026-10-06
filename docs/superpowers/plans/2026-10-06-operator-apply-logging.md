# Operator Apply Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich Apply failure messages with opcode/paths, poll apply-status under UAC with log-growth heartbeats, and fix maintainer-check success tokens.

**Architecture:** Pure helpers in Orchestrator for failure text and progress emit rules; `PwshElevatedPlanRunner` uses a timeout wait loop + optional `Action<string>` progress callback (constructor); CLI wires `CliLog`; maintainer-check is a one-file token fix.

**Tech Stack:** .NET (net from global.json), xunit via WinMint.Tests, pwsh 7.6+ contract tests.

## Global Constraints

- No new apply-status / failure.json schema keys
- No rewrite of apply-status on kernel heartbeat
- Progress poll only on UAC/`runas` path
- Orchestrator must not reference WinMint.Cli
- No new CONTEXT.md coins; ADR-014 one-shot spec already written
- Secrets: paths only

---

### Task 1: Failure message helper + tests

**Files:**
- Create: `src/WinMint.Orchestrator/ApplyOperatorMessages.cs`
- Modify: `src/WinMint.Orchestrator/PwshElevatedPlanRunner.cs` (use helper)
- Test: `tests/WinMint.Tests/ApplyOperatorMessagesTests.cs`

**Interfaces:**
- Produces: `ApplyOperatorMessages.FormatFailed(workDir, opcode, message, stage, logPath)` → string; `FormatCrashed(workDir, exitCode)` → string

- [ ] **Step 1: Write failing tests** for FormatFailed (opcode + paths) and FormatCrashed
- [ ] **Step 2: Implement helper; wire ReadFailure path in runner**
- [ ] **Step 3: Run `dotnet test --filter ApplyOperatorMessages` — PASS**

---

### Task 2: Progress tracker + UAC wait loop + CliLog

**Files:**
- Create: `src/WinMint.Orchestrator/ApplyOperatorProgressTracker.cs`
- Modify: `src/WinMint.Orchestrator/PwshElevatedPlanRunner.cs`
- Modify: `src/WinMint.Cli/CliLog.cs`, `src/WinMint.Cli/Program.cs`
- Test: `tests/WinMint.Tests/ApplyOperatorProgressTrackerTests.cs`

**Interfaces:**
- Consumes: `ServicingWorkspace.TryReadProgress`
- Produces: `ApplyOperatorProgressTracker.Consider(...)` → optional line; `PwshElevatedPlanRunner(Action<string>? onProgress = null)`

- [ ] **Step 1: Write failing tests** for stage change, still on length growth, quiet once, length reset
- [ ] **Step 2: Implement tracker + UAC WaitForExit(1000) loop**
- [ ] **Step 3: Wire CLI** `new PwshElevatedPlanRunner(line => …)` + LoggerMessages
- [ ] **Step 4: Run progress + existing ApplyProgress tests — PASS**

---

### Task 3: Maintainer-check token

**Files:**
- Modify: `tools/host/Invoke-MaintainerCheck.ps1`
- Modify: `tests/contract/Test-MaintainerCheck.ps1`

- [ ] **Step 1: Assert script source does not print quality-check ok unconditionally when advisory**
- [ ] **Step 2: Fix Invoke-MaintainerCheck.ps1**
- [ ] **Step 3: Contract / just check**

---

### Task 4: Gate

- [ ] **Step 1: `just check` green**
