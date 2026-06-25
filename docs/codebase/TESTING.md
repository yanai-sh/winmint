# Testing Patterns

Snapshot note: updated 2026-06-25. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) Test Runner

- **PowerShell tests:** run directly with `pwsh -NoProfile -File tests/contract/Test-*.ps1`; no external test framework — tests use custom `Add-SmokeFailure` / failure collection helpers
- **Rust tests:** `cargo test --manifest-path apps/gui/Cargo.toml` (standard Rust built-in test runner)
- **CI triggers both:** `.github/workflows/ci.yml` runs `Test-ProfileInvariants.ps1` + `Validate.ps1 -RunAnalyzer` + `cargo check` + `cargo test` on every push to `main`/`architecture/**`/`codex/**`

### 2) Test File Location

| Test suite | Location | What it covers |
|------------|---------|----------------|
| Profile invariants | `tests/contract/Test-ProfileInvariants.ps1` | Profile schema, tweak parity, option catalog shapes |
| Static assertions | `tests/contract/ProfileInvariantTests/StaticAssertions.ps1` | `config/tweaks.json` ↔ tweak module parity (highest churn file) |
| Profile assertions | `tests/contract/ProfileInvariantTests/ProfileAssertions.ps1` | Profile field values and normalization |
| Agent state transitions | `tests/contract/Test-AgentStateTransitions.ps1` | `state.json` step status lifecycle |
| Bootstrap contract | `tests/contract/Test-BootstrapContract.ps1` | `winmint.ps1` failure envelope structure |
| CLI matrix | `tests/contract/Test-CliMatrix.ps1` | CLI verb + flag combinations produce expected profiles |
| Cloudflare worker | `tests/contract/Test-CloudflareWorkerContract.ps1` | Worker response shape |
| Fast subset | `tests/contract/Test-Fast.ps1` | Quick subset for local iteration |
| FirstLogon transaction plan | `tests/contract/Test-FirstLogonTransactionPlan.ps1` | Agent module step ordering |
| Install plan | `tests/contract/Test-InstallPlanContract.ps1` | `BuildInstallPlan` output shape |
| Integration | `tests/contract/Test-Integration.ps1` | Cross-layer integration checks |
| Launchers | `tests/contract/Test-Launchers.ps1` | Entry-point launcher contracts |
| Payload store | `tests/contract/Test-PayloadStoreContract.ps1` | Payload cache behavior |
| Release manifest | `tests/contract/Test-ReleaseManifest.ps1` | `config/release-manifest.json` structural validity |
| Serviced WIM cache | `tests/contract/Test-ServicedWimCache.ps1` | Intermediates cache contract |
| UI contract spine | `tests/contract/Test-UiContractSpine.ps1` | UI intent → profile shape invariants |

### 3) Fixtures and Mocking

- **ISO fixture:** `tests/fixtures/iso/official-win11-25h2-english-arm64-v2.iso` — real ISO locally, stub empty file in CI (created by the CI `Prepare contract test fixtures` step); profile/invariant tests run without needing a real ISO
- **Driver fixture:** `tests/fixtures/drivers/SurfaceLaptop7_ARM_Win11_26100_26.033.32430.0.msi` — local only, gitignored
- **No mock framework:** tests stub missing console helpers (e.g. `Write-SectionHeader`, `Log`) with no-op functions inline before calling engine code
- **No dependency injection:** PowerShell tests dot-source engine internals directly and exercise public functions with representative input values

### 4) Coverage Posture

- No enforced coverage threshold.
- Focus is on contract/schema invariants and CLI matrix coverage rather than unit-level coverage.
- Real ISO/DISM builds are validated through the VM acceptance harness (`tools/vm/Build-And-TestVm.ps1`) — not in CI (requires a Windows host with Hyper-V and a real ISO).
- Rust tests are `cargo test` unit tests; no integration test suite for the GUI today.

### 5) VM Acceptance

- `tools/vm/Build-And-TestVm.ps1` orchestrates an end-to-end Hyper-V install test.
- Always targets **Windows 11 Pro** with the Pro generic key (Enhanced Session testing requires Pro).
- Results written to `output/vm-acceptance/` with live-teed `run.log` and `acceptance-result.json`.

### 6) Evidence

- `tests/contract/` — all contract test files
- `.github/workflows/ci.yml` — CI test commands
- `AGENTS.md` — test commands reference
- `tests/contract/TestFixtures.ps1` — shared fixture helpers
- `output/vm-acceptance/` — local VM acceptance run outputs
