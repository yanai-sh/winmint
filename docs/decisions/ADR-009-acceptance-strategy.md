# ADR-009: Acceptance strategy — contract tests in CI, VM smoke manual

**Status:** Accepted  
**Date:** 2026-07-07

### Context

WinMint requires Hyper-V, elevation, and a real ISO for full install proof. CI runs on GitHub-hosted runners without Hyper-V.

### Options considered

| Option | Pros | Cons |
|--------|------|------|
| Full VM in CI | Catches splash regressions at merge | Cost, flaky, slow |
| Contract tests only in CI | Fast, deterministic | No install proof |
| **Contracts in CI + manual/local VM smoke** | Balanced | Regressions until smoke run |

### Decision

**CI:** `Validate.ps1`, Pester contract tests, setup-shell publish, no Hyper-V gate.

**Pre-release / post-shell-change:** Managed VM smoke via `Start-WinMintVmAcceptanceManaged.ps1` with `hyper-v-smoke-arm64.json`.

VM harness stays **thin scripts** (not a framework); split `WinMint-VmConsole.ps1` into `tools/vm/lib/` modules (Track 4).

Add `acceptance-result.json` schema when evidence shape stabilizes (Track 4).

**Defer:** Self-hosted CI smoke until manual gate is routinely green.

### Consequences

- Document smoke requirement in AGENTS.md and VM-Acceptance.md.
- Agents must not treat `stopped`/`running` as pass.

### Review trigger

After 3 consecutive green managed smokes on `main`, evaluate self-hosted smoke job.
