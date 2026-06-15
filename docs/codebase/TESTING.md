# Testing Patterns

Snapshot note: this document reflects the current development state of the repo. It is an onboarding/audit snapshot, not a continuous authoritative source of truth.

## Core Sections (Required)

### 1) Test Stack and Commands

- Primary test framework: custom PowerShell contract/smoke scripts plus Rust `cargo test` for `winmint-core` and GUI crates.
- Assertion/mocking tools: PowerShell helper functions that collect failures and throw; JSON schema checks in validation modules; Rust built-in `#[test]`. No Pester dependency was found.
- Commands:

```powershell
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1
pwsh -NoProfile -File tests\contract\Test-Fast.ps1
pwsh -NoProfile -File tools\validation\Validate.ps1
cargo test --manifest-path crates\winmint-core\Cargo.toml
cargo test --manifest-path apps\gui\Cargo.toml
pwsh -NoProfile -File tools\vm\Build-And-TestVm.ps1 -ProfilePath .\tests\profiles\hyper-v-install-arm64.json
```

### 2) Test Layout

- Test file placement pattern: PowerShell contract tests live under `tests/contract/`; shared assertion libraries live under `tests/contract/ProfileInvariantTests/`; profile fixtures live under `tests/profiles/`; local large fixture roots live under `tests/fixtures/iso` and `tests/fixtures/drivers`.
- Naming convention: `Test-*.ps1` for executable test scripts; `Assert-*` functions inside shared assertion files.
- Setup files and where they run: `tests/contract/Test-ProfileInvariants.ps1` dot-sources runtime internals and assertion files; `tools/validation/Validate.ps1` dot-sources validation modules from `tools/validation/Modules/`.

### 3) Test Scope Matrix

| Scope | Covered? | Typical target | Notes |
|-------|----------|----------------|-------|
| Unit | Yes | Rust UI intent helpers and small PowerShell helpers. | `crates/winmint-core/src/profile.rs` has `#[cfg(test)]` tests; PowerShell contract scripts call helper assertions directly. |
| Contract/static | Yes | Profile invariants, schemas, release manifest, install plan, FirstLogon transaction plan, agent state/runtime plan, CLI matrix, payload store, bootstrap, Cloudflare Worker, UI contract spine. | `tests/contract/Test-Fast.ps1` composes the fast suite. |
| Integration | Partial | Optional ISO dry-run, payload/source checks, VM helpers. | `tools/validation/Validate.ps1 -RunIntegration` invokes `Test-Integration.ps1`; VM scripts require Hyper-V/Admin and local fixtures. |
| E2E installer | Manual/fixture-based | Generated ISO boot/install in Hyper-V. | `tools/vm/Build-And-TestVm.ps1` and `tests/profiles/hyper-v-install-arm64.json` exist; CI does not run Hyper-V E2E. |
| CI | Yes | Validation and GUI crate checks/tests. | `.github/workflows/ci.yml` runs profile invariants, validation, `cargo check`, and `cargo test` for `apps/gui`. |

### 4) Mocking and Isolation Strategy

- Main mocking approach: temp directories, fixture profiles, ignored fixture roots for large ISO/driver payloads, string/static source assertions, and local JSON round trips.
- Isolation guarantees: tests create temp files/directories for generated profiles and remove them in `finally` blocks where implemented; fixture roots are gitignored except `.gitkeep`/`.gitignore`.
- Common failure mode in tests: host-dependent tooling such as DISM, ADK/oscdimg, Hyper-V, cargo, PSScriptAnalyzer, and local ISO/driver fixtures can be absent; validation modules skip some optional tooling but contract/VM tests can fail hard.

### 5) Coverage and Quality Signals

- Coverage tool + threshold: no numeric threshold is configured. The intended bar is pragmatic rather than exhaustive: protect profile/schema/release invariants with fast tests, use Rust unit tests for typed helpers, and add targeted dry-run or VM acceptance checks for risky image/setup behavior.
- Current reported coverage: `[TODO]`.
- Known gaps/flaky areas: no automated full Windows install E2E in CI; live package-manager and network paths are only indirectly covered by contract/static checks; production TODO/FIXME/HACK markers were not found by scan/search outside excluded artifacts.

### 6) Evidence

- `tests/README.md`
- `tests/contract/Test-Fast.ps1`
- `tests/contract/Test-ProfileInvariants.ps1`
- `tests/contract/Test-UiContractSpine.ps1`
- `tests/contract/Test-InstallPlanContract.ps1`
- `tests/contract/Test-FirstLogonTransactionPlan.ps1`
- `tests/contract/Test-AgentStateTransitions.ps1`
- `tests/contract/ProfileInvariantTests/StaticAssertions.ps1`
- `tests/contract/ProfileInvariantTests/ProfileAssertions.ps1`
- `tools/validation/Validate.ps1`
- `tools/validation/Modules/Core.ps1`
- `.github/workflows/ci.yml`
- `crates/winmint-core/src/profile.rs`
