# WinMint — Agent contract

Windows 11 ISO builder (**alpha**). **ARM64-first**. Host Servicing: **pwsh 7.6+**. Guest FirstLogon: **Provisioning Supervisor**; packages may delegate to platform tools.

## Core rule

**CLI/Orchestrator creates intent. Servicing mutates the offline image. Provisioning Supervisor finishes live-user setup.**

Elevate **only** Servicing `pwsh -File`. No v1 `WinMint.ps1`. No guest **pwsh product runtime** — inbox `powershell.exe` for Scoop bootstrap or narrow winget import/configure is OK.

## Invariants

Living list: [DESIGN](docs/DESIGN.md#invariants). Short form: Source ISO · Supervisor FirstLogon · remove-list / no presets-in-JSON / CDM not primary · residual erase · single-image WIM · `winmint.profile/v1` until a real break.

## Defaults

Revisable with spike evidence — [DESIGN](docs/DESIGN.md#defaults).

## Deep modules

BuildPlan · ImageServicing · ProvisioningSession — [docs/design/](docs/design/). HostCompile is the Orchestrator entry (not a fourth module).

## Maintainer host

**Clock** — Maintainer zone is Asia/Jerusalem (Tel Aviv). SL7’s system time can jump backward at random even after a sync (faulty DMA workaround on this machine, not product DMA settle). Do not trust `Get-Date`, `[datetime]::UtcNow`, file `LastWriteTime`, chat timestamps, or harness remaining-time as elapsed truth. Smoke stall/wall and the DVD boot-nudge window are wall-clock: a backward jump inflates them. If remaining time grows or files look newer than “now,” the clock jumped — stop treating those timers as elapsed and ask the human. A sync is temporary.

**Vanilla Source ISO (Smoke / Host Apply)** — Official Microsoft 25H2 English ARM64 ISO on this host:

`C:\Users\yanai\Documents\Win11_25H2_English_Arm64_v2.iso`

Same fact in [tests/fixtures/maintainer-host.json](tests/fixtures/maintainer-host.json). User-supplied only ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)); never commit the ISO bytes; CI must not fetch Windows media.

```powershell
just publish-provisioning
just smoke-maintainer
# or: just smoke 'C:\Users\yanai\Documents\Win11_25H2_English_Arm64_v2.iso'
# (positional path — do not use ISO=path under PowerShell)
```

## Session

Prefer one issue per session. Tiny same-risk fixes in touched code are fine — do not leave obvious breakage to obey “no drive-bys.” Apply `ready-for-agent` when starting scoped implement work. Keep `just check` green. Commits when asked: `docs:` · `feat(scope):` · `fix(scope):` …

```powershell
just check
```

**Solo — no PRs** unless asked. Issues are the work surface ([issue-tracker](docs/agents/issue-tracker.md)).

## Read order

[CONTEXT](CONTEXT.md) → [DESIGN](docs/DESIGN.md) → the one module design for the seam. [AGENTIC](docs/agents/AGENTIC.md) when the session needs it. TDD / ARCHITECTURE / STACK only when tests, shape, or pins are the work. Shipped specs are historical.
