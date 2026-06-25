# Codebase Concerns

Snapshot note: updated 2026-06-25. Onboarding/audit snapshot — not a continuous authoritative source.

## Core Sections (Required)

### 1) TODOs and Technical Debt Markers

- Scan output reports **zero** `TODO`/`FIXME`/`HACK` markers in production code.
- No inline suppression comments that indicate deferred work were found.

### 2) High-Churn Files (last 90 days)

| File | Commits | Risk signal |
|------|---------|-------------|
| `tests/contract/ProfileInvariantTests/StaticAssertions.ps1` | 29 | Parity tests between `config/tweaks.json` and tweak modules — highest churn; schema changes ripple here |
| `AGENTS.md` | 21 | Living architecture contract — expected high churn as product evolves |
| `README.md` | 21 | User-facing — expected |
| `tests/contract/Test-ProfileInvariants.ps1` | 18 | Profile schema tests — tracks profile schema changes |
| `tests/contract/ProfileInvariantTests/ProfileAssertions.ps1` | 16 | Profile field assertions |
| `src/runtime/image/Engine.ps1` | 14 | Core engine pipeline — active development area |
| `tools/validation/Modules/Assets.ps1` | 13 | Repo asset validation |
| `WinMint-CLI.ps1` | 13 | CLI entry point |
| `apps/gui/src/main.rs` | 12 | Wizard root — active GUI development |
| `schemas/winmint.buildprofile.schema.json` | 12 | Profile schema evolving with feature additions |

### 3) Structural Concerns

- **`config/tweaks.json` ↔ tweak module parity:** two representations of the same truth. `StaticAssertions.ps1` guards against drift but both files must be updated together whenever a tweak is added/removed. High toil, high churn (28 commits). A code-generation step from tweak modules to the JSON mirror would eliminate this entirely.
- **GUI bridge has no timeout or process cancellation:** `bridge::run_source_probe` and `bridge::start_build_from_profile` block indefinitely on a child `pwsh` process. A hung ADK command or missing dependency has no recovery path in the GUI today.
- **DISM version validated at runtime, not at profile authoring time:** a build is committed and started before the host DISM version check runs. A preflight check during `new` would surface this earlier.
- **`components.rs` single-file rule:** `apps/gui/src/components.rs` is intentionally kept as one file until it grows internal state or exceeds ~500 lines. At that point, a planned split to a `components/` directory (re-exporting `ui::*`) is the documented path — but no flag or tracking exists for when that threshold is crossed.

### 4) Security Considerations

- **Password in BuildProfile.json:** unattended local-account builds store a password in the profile. The profile lives in `output/` (gitignored) but is a plaintext JSON file on disk. No encryption or credential store integration today.
- **Arbitrary PowerShell execution on bootstrap:** `irm https://winmint.yanai.sh | iex` is a pipe-to-shell pattern. Mitigated by SHA256 verification of the release zip, HTTPS, and Cloudflare-hosted redirect — but the pattern itself carries inherent risk if the CDN or GitHub release is compromised.
- **No input validation on ISO path in GUI:** the bridge accepts any path string ending in `.iso`; the PowerShell engine validates the actual file, but there is no length or character sanitization before the path is passed to child processes.
- **`AggressiveExperimental` gate:** internal-only research techniques (TrustedInstaller tricks, CBS metadata deletion) are gated behind this flag. Ensure it is never shipped enabled in release builds.

### 5) Performance Notes

- Build times are dominated by DISM mount/unmount and `oscdimg.exe` ISO assembly — inherently sequential and Windows-kernel-bound. No parallelism opportunity inside a single build.
- ISO source files (7.4–7.8 GB) are in `tests/fixtures/iso/` and `output/` — gitignored but consume significant local disk. CI uses a stub empty file.
- `Swatinem/rust-cache@v2` is configured in CI for the GUI crate, keeping Cargo build times reasonable.

### 6) Test Coverage Gaps

- No CI test for end-to-end ISO builds or actual DISM servicing — requires Windows host + ADK + real ISO.
- No automated GUI interaction test; GPUI rendering is untested beyond `cargo check`/`cargo test`.
- VM acceptance tests (`tools/vm/`) are local-only and not part of CI.

### 7) Evidence

- `docs/codebase/.codebase-scan.txt` — churn data and TODO scan
- `tests/contract/ProfileInvariantTests/StaticAssertions.ps1` — parity test (highest churn)
- `apps/gui/src/bridge.rs` — blocking bridge without timeout
- `AGENTS.md` — `AggressiveExperimental` gate documentation
- `.github/workflows/ci.yml` — CI coverage scope
