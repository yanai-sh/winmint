# Account modes (`oobeLocal` + `localAutoLogon`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Profile `account.mode` dual path — portable `oobeLocal` (native OOBE identity, no baked owner password) plus existing `localAutoLogon` bake-in — without C2 identity UI; keep curated/Smoke on bake-in until Primary proves `oobeLocal`.

**Architecture:** `account.mode` is the sole wire discriminator. BuildPlan validates and emits mode-specific unattend. Offline Shell stamp stays for `localAutoLogon`; `oobeLocal` may omit or defer Shell (explorer through OOBE, then Supervisor). Wizard progressive-discloses bake-in. Smoke hard-pins `localAutoLogon`.

**Tech Stack:** net11.0 C# (`WinMint.Orchestrator`, Cli, Wizard, Provisioning), elevated `servicing/*.ps1`, contract tests under `tests/contract/`, unit tests under `tests/WinMint.Tests/`.

**Specs / law:** [ADR-017](../decisions/ADR-017-account-modes.md), [design](../specs/2026-10-09-account-modes-design.md), glossary in `CONTEXT.md`. Parent map: #136.

## Global Constraints

- Do not flip Wizard curated default or `samples/sl7.profile.json` to `oobeLocal` in this plan (proof-gated).
- Do not implement C2 splash identity UI or Tenure M/U.
- Do not change Cli/Smoke default WIM index (Pro).
- Flash remains outside the product seam (ADR-012).
- `just check` green after each code task.
- Commits: `feat(orchestrator):` / `feat(wizard):` / `feat(provisioning):` / `test(contract):` as appropriate.

---

### Task 1: Profile wire accepts `oobeLocal`

**Files:**
- Modify: `src/WinMint.Orchestrator/Profile.cs` — add `OobeLocalMode = "oobeLocal"`; document password rules
- Modify: `src/WinMint.Orchestrator/BuildPlan.cs` — ParseDocument mode allow-list; username/password required only for `localAutoLogon`; `oobeLocal` forbids password/passwordPath; Plan() password gate mode-aware; unattend builder branch (no LocalAccounts/AutoLogon for `oobeLocal`)
- Modify: `src/WinMint.Orchestrator/CuratedDefaults.cs` — leave emit on `localAutoLogon` (proof gate)
- Test: `tests/WinMint.Tests/` — extend Profile/BuildPlan tests (or add `AccountModeTests.cs`)

**Interfaces:**
- Consumes: existing `AccountDocument.Mode`, `AccountProfile`
- Produces: `AccountProfile.OobeLocalMode`; Plan succeeds for `oobeLocal` without password; unattend XML omits UserAccounts/AutoLogon for that mode

- [ ] **Step 1: Failing unit test — oobeLocal parse + plan**

```csharp
[Fact]
public void Parse_oobeLocal_without_password_succeeds()
{
    // minimal Profile JSON: account.mode=oobeLocal, username omitted or ignored per decision,
    // dma.settle filled, schemaVersion set — assert Result.IsOk and Mode constant.
}

[Fact]
public void Plan_oobeLocal_unattend_omits_AutoLogon()
{
    // Plan(profile) → UnattendXml must not contain AutoLogon / LocalAccounts
}
```

- [ ] **Step 2: Run tests — expect FAIL on unsupported mode**

Run: `dotnet test tests/WinMint.Tests --filter AccountMode` (or named tests)

- [ ] **Step 3: Implement Parse + Plan gates + unattend branch**

```csharp
public const string OobeLocalMode = "oobeLocal";
// allow LocalAutoLogonMode | OobeLocalMode
// localAutoLogon: username + password required (existing)
// oobeLocal: reject password/passwordPath; username optional/absent (pick one — prefer absent)
```

Unattend for `oobeLocal`: keep OOBE HideOnlineAccountScreens / HideWireless from requireWifi; **omit** `<UserAccounts>` and `<AutoLogon>`.

- [ ] **Step 4: `dotnet test` + `just check` green**

- [ ] **Step 5: Commit** `feat(orchestrator): accept account.mode oobeLocal`

---

### Task 2: Shell stamp mode-aware (`oobeLocal` defer marker)

**Files:**
- Modify: `src/WinMint.Orchestrator/BuildPlan.cs` / stage binding — for `oobeLocal`, either skip `StampOfflineShell` or emit a parameter `DeferShell=true` (prefer skip offline stamp + Machine-setup/FirstLogonCommands path documented in payload)
- Modify: `servicing/Stamp-OfflineShell.ps1` and/or Machine setup in `ProvisioningSession` — if Shell was not stamped offline, after first logon as owner set Winlogon Shell to Supervisor and re-enter tenure (minimal deferred path)
- Test: unit/contract for stage list: `localAutoLogon` includes StampOfflineShell; `oobeLocal` does not (or sets defer flag)

**Interfaces:**
- Consumes: Task 1 Profile mode on Plan
- Produces: `oobeLocal` images that can complete OOBE with explorer; then Supervisor FirstLogon

- [ ] **Step 1: Failing test — oobeLocal plan stages omit StampOfflineShell** (or assert defer flag)

- [ ] **Step 2: Implement stage gating**

- [ ] **Step 3: Implement deferred Shell entry** (smallest path that Machine setup or first Supervisor launch can take — prefer one place)

- [ ] **Step 4: `just check`**

- [ ] **Step 5: Commit** `feat(provisioning): defer Shell stamp for oobeLocal`

---

### Task 3: Wizard bake-in progressive disclosure

**Files:**
- Modify: `src/WinMint.Wizard/ViewModels/AccountStageViewModel.cs` (+ axaml if needed)
- Modify: `src/WinMint.Wizard/ViewModels/WizardViewModel.cs` — readiness: curated defaults stay password bootstrap; advanced bake-in warns ISO contains password
- Modify: `src/WinMint.Orchestrator/CuratedDefaults.cs` / Wizard emit path — still `localAutoLogon` until proof (no default flip)
- Test: Wizard/ProfileDraft tests if present

**Interfaces:**
- Consumes: Task 1 mode constants
- Produces: Account stage can author `oobeLocal` (no password) OR bake-in with explicit warning

- [ ] **Step 1: Failing test or manual Wizard checklist in contract text freeze**

- [ ] **Step 2: UI — toggle/choice “Create account when Windows starts (portable)” vs “Bake auto-logon (automation)”**

- [ ] **Step 3: `just check`**

- [ ] **Step 4: Commit** `feat(wizard): account mode portable vs bake-in`

---

### Task 4: Contracts + Smoke pin

**Files:**
- Create: `tests/contract/Test-AccountModes.ps1` — freeze: BuildPlan/Cli accepts both modes; Smoke recipes / samples still `localAutoLogon`; curated emit still bake-in
- Modify: Smoke profile fixtures if any lack explicit mode (must stay `localAutoLogon`)

- [ ] **Step 1: Write contract script assertions (string/plan dump)**

- [ ] **Step 2: `pwsh -File tests/contract/Test-AccountModes.ps1` then `just check`**

- [ ] **Step 3: Commit** `test(contract): freeze account.mode dual path`

---

### Task 5: Proof gate (human / Hyper-V)

**Files:** none required in product — issue checklist on #136 child

- [ ] Build `oobeLocal` Output ISO (Test lane OK for VM)
- [ ] Install with interactive OOBE local account
- [ ] Confirm Supervisor FirstLogon Completes (deferred Shell if used)
- [ ] Comment evidence on proof ticket; only then open “flip curated default” follow-up

**Commit:** none (ops)

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| Dual mode wire | 1 |
| Unattend branch | 1 |
| Deferred Shell | 2 |
| Wizard disclosure | 3 |
| Smoke pin / no default flip | 1, 3, 4 |
| Proof before curated flip | 5 |
| No C2 UI | all (non-goal) |
