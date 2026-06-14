# Testing Patterns

## 1) Test Stack and Commands

- Primary test framework: script-based PowerShell contract tests plus Rust built-in `cargo test`.
- Assertion/mocking tools: custom PowerShell assertion helpers in `tests/contract/ProfileInvariantTests` and Rust `assert_eq!`/`assert!`; no Pester config appears in the repo.
- Commands:

```powershell
pwsh -NoProfile -File tests\contract\Test-Fast.ps1
pwsh -NoProfile -File tests\contract\Test-ProfileInvariants.ps1
pwsh -NoProfile -File tests\contract\Test-Integration.ps1 -RunIsoDryRun
pwsh -NoProfile -File tools\validation\Validate.ps1
cargo test --manifest-path apps/gui/Cargo.toml
cargo test -p winmint-core
```

## 2) Test Layout

- Test file placement pattern: PowerShell contract tests live under `tests/contract`; profile fixtures live under `tests/profiles`; large local fixture roots live under `tests/fixtures`.
- Naming convention: PowerShell tests use `Test-*.ps1`; helper assertions live under `tests/contract/ProfileInvariantTests`.
- Setup files: `tests/contract/TestFixtures.ps1` provides shared fixture helpers; `tests/contract/Test-ProfileInvariants.ps1` dot-sources runtime modules and assertion files.
- Rust tests are colocated in crate source files, e.g. `#[cfg(test)] mod tests` in `crates/winmint-core/src/profile.rs`.

## 3) Test Scope Matrix

| Scope | Covered? | Typical target | Notes |
|-------|----------|----------------|-------|
| Unit/contract | Yes | Profile invariants, CLI matrix, agent state transitions, bootstrap contract, UI contract spine, serviced WIM cache. | `tests/contract/Test-Fast.ps1` runs the fast suite. |
| Static validation | Yes | Required docs/assets, release manifest, schemas, PowerShell parser, PSScriptAnalyzer, Rust crates. | `tools/validation/Validate.ps1` orchestrates validation steps. |
| Integration | Partial | ISO dry-run profile creation and build flow. | `tests/contract/Test-Integration.ps1 -RunIsoDryRun` requires elevation and fixture ISO. |
| VM acceptance | Partial/tooling present | Hyper-V build/test helpers and guest acceptance scripts. | `tools/vm/` scripts exist; CI does not run them. |
| GUI runtime | Partial | Rust crate check/test in CI; source UI contract spine in PowerShell. | `.github/workflows/ci.yml`, `tests/contract/Test-UiContractSpine.ps1` |
| E2E installer | [TODO] | Full Windows install flow on generated ISO. | VM tooling exists, but CI does not run an E2E installer workflow. |

## 4) Mocking and Isolation Strategy

- Main mocking approach: PowerShell tests dot-source runtime modules and override or stub functions where needed; fixture profiles and local fixture roots stand in for real media/drivers.
- Isolation guarantees: tests write generated matrix/log artifacts under `output/`; large ISO/driver fixtures are ignored by git per `tests/README.md`.
- Common failure mode in tests: integration dry-run needs elevated PowerShell and an ISO fixture; without `-RequireAdmin`, the integration script warns and skips.

## 5) Coverage and Quality Signals

- Coverage tool + threshold: [TODO]; no coverage tool or threshold config found.
- Current reported coverage: [TODO].
- CI quality gates: `tests/contract/Test-ProfileInvariants.ps1`, `tools/validation/Validate.ps1`, `cargo check --manifest-path apps/gui/Cargo.toml`, and `cargo test --manifest-path apps/gui/Cargo.toml`.
- Scan output found no production `TODO`, `FIXME`, or `HACK` markers; a direct `rg` search also found no matches outside excluded artifacts.

## 6) Evidence

- `tests/README.md`
- `tests/contract/Test-Fast.ps1`
- `tests/contract/Test-ProfileInvariants.ps1`
- `tests/contract/Test-Integration.ps1`
- `tests/contract/Test-CliMatrix.ps1`
- `tools/validation/Validate.ps1`
- `.github/workflows/ci.yml`
- `.cargo/config.toml`
- `crates/winmint-core/src/profile.rs`
