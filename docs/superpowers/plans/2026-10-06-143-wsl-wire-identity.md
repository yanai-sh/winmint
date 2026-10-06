# #143 WSL wire identity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deepen one WSL wire-identity module so chip/token/`installId` stop leaking across catalog→plan→jobs. Gate B / Proof / expected evidence share the wire.

**Architecture:** Profile token = catalog key. Job `PackageId` = catalog `installId`. Expected evidence + Gate B assert require planned WSL kinds/PackageIds. PackagesProof (or sibling attest) covers store installIds. JobRunner fails package-strict if store install exits 0 but distro is not registered.

**Tech Stack:** .NET 11 / C#, `config/packages.json` (+ proof), PowerShell Gate B asserts in `tools/apply`, xUnit.

## Global Constraints

- Spec: GitHub issue #143 (Part of #142). Map decisions in #142.
- Profile token = catalog key (e.g. `FedoraLinux`); job `PackageId` = `installId` (e.g. `FedoraLinux-44`).
- When plan contains WSL jobs: expected evidence + Gate B assert require those job kinds and PackageIds; PackageIds must resolve to catalog installIds.
- PackagesProof (or sibling WSL attest) covers store installIds — not winget/scoop only.
- JobRunner: after store `wsl --install -d`, fail package-strict if distro not registered (no exit-0-only).
- Smoke Hyper-V mock may remain; assert plan dump / expected evidence wire, not live install.
- Out of scope: HostReview UI labels (T2/#144). DMA settle (T4/#146). SoftwarePlan collapse (T5/#147). Live `wsl -l -o` in Gate B Apply.
- Ponytail: no new catalog abstraction beyond the smallest wire helper needed for expected-evidence/Gate B; prefer allowlist attest over live `wsl -l -o` online prove.
- No `winmint.profile/v1` bump; no CONTEXT/ADR unless polarity changes (it does not for this ticket — skip CONTEXT.md Primary gloss edits).
- Commit style: `docs:` · `feat(scope):` · `fix(scope):` …
- Focused tests while iterating; `just check` before final task commit.
- Work on branch `sdd/143-wsl-wire` in worktree; commit when a task’s Commit step says so.
- After land: comment on #142 with wire fact location (types/files); close #143 with summary.

## File map

| File | Responsibility |
|------|----------------|
| `config/packages.json` | Fedora store `installId` → `FedoraLinux-44` |
| `config/packages.proof.json` | Refresh after catalog/prove-set change |
| `src/WinMint.Orchestrator/PackageCatalog.cs` | Chip label honesty if needed; resolve token→entry |
| `src/WinMint.Orchestrator/BuildPlan.Packages.cs` | Already emits `PackageId: entry.InstallId` — keep |
| `src/WinMint.Orchestrator/ImageServicing.Evidence.cs` | Expected evidence includes WSL kinds + PackageIds |
| `src/WinMint.Orchestrator/ServicingWorkspace.cs` | `ExpectedEvidenceFile` shape if extended |
| `src/WinMint.Orchestrator/PackagesProof.cs` | Store WSL installIds in prove/validate set |
| `src/WinMint.Provisioning/ProvisioningSession.JobRunner.cs` | Post-store registration verify |
| `src/WinMint.Provisioning/Win32WslTerminalMock.cs` | Mock uses install id as tab name |
| `tools/apply/Assert-ApplyEvidence.ps1` | Gate B: plan WSL PackageIds ⊆ expected + catalog |
| `tests/WinMint.Tests/WslJobsTests.cs` | Plan PackageId = InstallId; registration fail |
| `tests/WinMint.Tests/PackageCatalogTests.cs` | Token→InstallId |
| Proof / expected-evidence tests as existing patterns dictate |

---

### Task 1: Catalog + plan wire — FedoraLinux-44 installId

**Files:**
- Modify: `config/packages.json` (`FedoraLinux.installId` → `FedoraLinux-44`; displayName may be `Fedora 44`)
- Modify: `config/packages.proof.json` (catalogSha256 refresh via `just packages-check` or project recipe)
- Modify: `src/WinMint.Orchestrator/PackageCatalog.cs` (chip label `Fedora 44` if display-driven)
- Modify: `src/WinMint.Provisioning/Win32WslTerminalMock.cs` (use install id; no Fedora rename)
- Test: `tests/WinMint.Tests/WslJobsTests.cs`, `PackageCatalogTests.cs`, `StationOutcomesTests.cs` as needed

**Interfaces:**
- Consumes: existing `WslDistroEntry`, `BuildPlan.PlanPackages` (`PackageId: entry.InstallId`)
- Produces: profile token `FedoraLinux` plans job PackageId `FedoraLinux-44`

- [ ] **Step 1: Write failing tests**

Assert plan for `wsl: ["FedoraLinux"]` yields PackageId `FedoraLinux-44`. Assert `TryGetWslByProfileToken("FedoraLinux")` → InstallId `FedoraLinux-44`. Update mock/station label expectations.

- [ ] **Step 2: Run tests — expect fail**

```powershell
dotnet test tests/WinMint.Tests/WinMint.Tests.csproj --filter "FullyQualifiedName~WslJobsTests|FullyQualifiedName~PackageCatalogTests"
```

- [ ] **Step 3: Update catalog + call sites**

Set Fedora `installId` to `FedoraLinux-44`. Refresh proof. Fix mock/tests.

- [ ] **Step 4: Run tests — expect pass**

- [ ] **Step 5: Commit**

```
feat(packages): Fedora WSL store installId FedoraLinux-44
```

---

### Task 2: Expected evidence + Gate B + PackagesProof WSL store attest

**Files:**
- Modify: `ExpectedEvidenceFile` / `WriteExpectedEvidence` to require WSL job kinds and PackageIds when plan has WSL
- Modify: `tools/apply/Assert-ApplyEvidence.ps1` (and shared helpers if needed) so Gate B/package-strict assert fails if WSL jobs omitted from expected evidence when plan has WSL; PackageIds must match jobs and resolve to catalog installIds
- Modify: `PackagesProof` to include store WSL installIds in prove/validate (allowlist — not live online list)
- Tests: unit/contract covering expected evidence WSL wire + proof validate missing store id

**Interfaces:**
- Extends expected-evidence JSON (additive fields OK; keep schema version unless existing pattern bumps)
- Gate B host-side only; no live `wsl -l -o`

- [ ] **Step 1: Failing tests** for expected evidence requiring WSL PackageIds; proof validate fails if store installId missing from attest set
- [ ] **Step 2: Implement WriteExpectedEvidence + assert + PackagesProof**
- [ ] **Step 3: Tests pass; refresh proof**
- [ ] **Step 4: Commit**

```
feat(host): Gate B/Proof share WSL installId wire
```

---

### Task 3: JobRunner store registration verify + gate green

**Files:**
- Modify: `ProvisioningSession.JobRunner.cs` (+ Wsl helper if needed)
- Test: JobRunner path — exit 0 without registration → package-strict fail
- Guest seam: smallest `IsWslDistroRegistered(string installId)` (or reuse process list parse) injectable for tests

- [ ] **Step 1: Failing test** — store install exit 0, distro not registered → fail
- [ ] **Step 2: Implement registration check after store `--install -d`**
- [ ] **Step 3: `just check` green**
- [ ] **Step 4: Commit**

```
fix(provisioning): fail WSL store install without registration
```

- [ ] **Step 5: Comment on #142** with wire fact locations; leave issue close to controller

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| PackageId = catalog installId | Task 1 |
| Expected evidence + Gate B require WSL kinds/PackageIds | Task 2 |
| PackagesProof covers store installIds | Task 2 |
| JobRunner registration verify | Task 3 |
| `just check` green | Task 3 |
| Comment #142 | Task 3 |
