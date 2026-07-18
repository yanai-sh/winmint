# WinMint — Agent contract

Windows 11 ISO builder (greenfield v2). Host is Windows; use native arm64 toolchains when on ARM. Elevated Servicing and Payload scripts need **pwsh 7.6+**.

`AGENTS.md` is the compact contract for coding agents. New clone / seed zip → [`docs/START.md`](docs/START.md). Product pitch → [`README.md`](README.md). Glossary → [`CONTEXT.md`](CONTEXT.md). Architecture → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Naming → [`docs/NAMING.md`](docs/NAMING.md). Tree → [`docs/STRUCTURE.md`](docs/STRUCTURE.md). Tooling → [`docs/TOOLING.md`](docs/TOOLING.md) + root [`Justfile`](Justfile). Process → [`docs/WORKFLOW.md`](docs/WORKFLOW.md). AOT/C# → [`docs/coding-contract.md`](docs/coding-contract.md). Decisions → [`docs/decisions/`](docs/decisions/). Tracker → [`docs/agents/`](docs/agents/). Content → [`assets/`](assets/README.md), [`payload/`](payload/README.md). Hybrid ports → [`docs/PORT-FROM-V1.md`](docs/PORT-FROM-V1.md) (v1 is a separate optional clone).

## Core rule

**CLI/Orchestrator creates and executes intent. Servicing mutates the offline image. Payload finishes live-user setup. Reports explain work.**

```
Bootstrap (optional) → C# CLI / Orchestrator → elevated pwsh Servicing → Windows Setup → FirstLogon (Payload + Native AOT splash)
```

Unelevated C# owns Profile validation, planning, unattend/job JSON, and the public CLI. Elevate **only** Servicing `pwsh -File` jobs. Do not run DISM/hive mount in-process in the CLI or wizard. Do not wrap legacy WinMint v1 `WinMint.ps1` as the subprocess.

## Boundaries

| Layer | Owns | Must not own |
|-------|------|----------------|
| Orchestrator (C#) | Profile, plan, CLI, job JSON | In-process DISM / offline hive |
| Servicing (elevated pwsh) | Thin mount/stage/hive/export kernels | Product CLI, fat monolith entry |
| Payload | Setup / FirstLogon / agent stub / splash host | Build orchestration |
| Wizard (Avalonia, later) | Profile authoring UI | Servicing, ISO splash |
| Reports | Manifest / evidence / human summaries | Business decisions |

## Product stance (Smoke era)

- **Source ISO is legally user-supplied** — never bundle, pin, or silently download Windows media ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)).
- **Clean-sheet contracts** — no back-compat with v1 BuildProfile / InstallPlan / PowerShell CLI.
- **C# CLI only** — tiny download bootstrap script OK; no second product CLI in pwsh.
- **DMA default-on** for Smoke — Ireland/`en-IE` during Setup; FirstLogon restores visible region before further live-user work ([ADR-003](docs/decisions/ADR-003-dma-interop.md)).
- **Local accounts require a password** for unattended Smoke.
- **No maintenance payload** on the installed system (no leftover tasks/services/scripts).
- **Hyper-V Smoke SKU = Pro** (Enhanced Session); product default SKU may stay Home later.
- **Out of Smoke:** Avalonia wizard, debloat/keep matrix, BitLocker policy, physical hardware acceptance.
- **Image quality lanes** — test/Smoke = fast export (skip component cleanup); release = Max + cleanup. Run override, not Profile. Record what ran in the build report. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md#image-quality-run-override-not-profile).

## Delivery workflow

Multi-session build. Do not implement from a blank chat without tickets.

1. `/setup-matt-pocock-skills` (once per repo)
2. `/to-spec` (Smoke only) → `/to-tickets` (approve blockers) in one planning window
3. `/implement` **one ticket per session**, fresh context; TDD → review → commit when asked
4. Skip `/wayfinder` unless the Smoke spec is blocked by fog

**Milestones** = spec destinations. **Planned commits** = approved tickets. Work only the unblocked frontier. Keep ticket-shaped history. Details: [`docs/WORKFLOW.md`](docs/WORKFLOW.md).

## Stack

- `net11.0` + SDK pin (`global.json` / CI); LangVersion `preview` as needed
- Native AOT for publishable hosts: `PublishAot` on exe, `IsAotCompatible` on libs; source-gen JSON; `LibraryImport`
- Avalonia **12.1.x** for wizard **after** Smoke — not for ISO splash
- Splash: separate Native AOT host (Direct2D/GDI-class) reading status JSON under provisioning lock
- Payload: **hybrid** — port DMA/lock/transaction/Common/splash model; clean-sheet staged JSON + thin agent stub ([ADR-002](docs/decisions/ADR-002-v2-architecture.md))

## Commands

```powershell
winget install Casey.Just   # once
just                        # list
just check                  # format-check + build + test + analyze-ps
just sdk                    # confirm global.json pin
```

See [`docs/TOOLING.md`](docs/TOOLING.md). Fill CLI invoke lines after Smoke tickets land.

## Domain docs

- Glossary: [`CONTEXT.md`](CONTEXT.md) — use those terms; see [`docs/agents/domain.md`](docs/agents/domain.md)
- Hard decisions → ADR under `docs/decisions/`; don’t silently contradict Accepted ADRs
- Issue tracker / triage: [`docs/agents/`](docs/agents/)

## Commit style

Conventional commits: `feat(scope):`, `fix(scope):`, `docs:`, etc. Scope = component (`orchestrator`, `servicing`, `payload`, `splash`, `cli`, …). Prefer one ticket → one intentional commit (or a short intentional series).
