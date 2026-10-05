# WinMint — Agent contract

Windows 11 ISO builder (**alpha**). **ARM64-first**. Host Servicing: **pwsh 7.6+**. Guest FirstLogon: **Provisioning Supervisor**; packages may delegate to platform tools.

## Core rule

**CLI/Orchestrator creates intent. Servicing mutates the offline image. Provisioning Supervisor finishes live-user setup.**

Elevate **only** Servicing `pwsh -File`. No v1 `WinMint.ps1`. No guest **pwsh product runtime** — inbox `powershell.exe` for Scoop bootstrap or narrow winget import/configure is OK.

## Reach

Code and tests are the product ([ADR-014](docs/decisions/ADR-014-docs-are-not-living-law.md)). Do not add living design docs. Do not restate types, opcodes, or defaults that already live in `src/`. An ADR is the choice and what was rejected — not an id catalog or changelog.

Open by branch:

| When | Open |
|------|------|
| Coined word, polarity, avoid-list | [CONTEXT.md](CONTEXT.md) |
| Why a bar exists / what was rejected | [docs/decisions/](docs/decisions/) |
| Behaviour, types, opcodes, defaults | `src/`, `servicing/`, `tests/` |
| Operator / legal policy | [README.md](README.md), [SECURITY.md](SECURITY.md), [PRIVACY.md](PRIVACY.md), [docs/CODE_SIGNING.md](docs/CODE_SIGNING.md) |

Identity bars (detail is ADRs + code): Source ISO · Supervisor FirstLogon · remove-list / no presets-in-JSON / CDM not primary · residual erase · single-image WIM · `winmint.profile/v1` until a real break · desktop surfaces as two axes ([ADR-015](docs/decisions/ADR-015-desktop-surfaces.md)).

## Map

| Concern | Lives in |
|---------|----------|
| **BuildPlan** / plan artifacts | `src/WinMint.Orchestrator` |
| **HostCompile** (entry; not a fourth module) | `src/WinMint.Orchestrator` |
| **ImageServicing** | `src/WinMint.Orchestrator` + `servicing/` |
| **ProvisioningSession** / Supervisor | `src/WinMint.Provisioning` |
| Contracts / job wire | `src/WinMint.Contracts` |
| Cli / Wizard front ends | `src/WinMint.Cli`, `src/WinMint.Wizard` |
| WinPE apply helper | `src/WinMint.WinPeApply` |
| Package catalog / chips | `config/packages.json` (+ `config/packages.proof.json`) |
| Guest payload / skel / desktop assets | `payload/` |
| Sample profiles | `samples/` |
| Host recipes | `Justfile`, `tools/host/` |
| Smoke / Hyper-V | `tools/vm/` |
| Contract harness | `tests/contract/` |
| Unit / session tests | `tests/WinMint.Tests/` |
| Maintainer ISO / smoke recipes | `tests/fixtures/maintainer-host.json` |

Pins: `global.json`, `Directory.Build.props`. Gate: `just check`.

## Maintainer host

**Clock** — Maintainer zone is Asia/Jerusalem (Tel Aviv). SL7’s system time can jump backward at random even after a sync (faulty DMA workaround on this machine, not product DMA settle). Do not trust `Get-Date`, `[datetime]::UtcNow`, file `LastWriteTime`, chat timestamps, or harness remaining-time as elapsed truth. Smoke stall/wall and the DVD boot-nudge window are wall-clock: a backward jump inflates them. If remaining time grows or files look newer than “now,” the clock jumped — stop treating those timers as elapsed and ask the human. A sync is temporary.

**Vanilla Source ISO (Smoke / Host Apply)** — Official Microsoft **English (US)** 25H2 ARM64 ISO on this host (DISM `Languages : en-US`; not English International). Path and recipes: [tests/fixtures/maintainer-host.json](tests/fixtures/maintainer-host.json). User-supplied only ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)); never commit the ISO bytes; CI must not fetch Windows media.

**Maintainer signals** — Weekly Catalog B-release: GitHub Actions workflow **health** (subscribe to failures). SL7 ISO + Catalog: `just maintainer-check` (optional Task Scheduler; see fixture notes). Catalog-only: `just quality-check`.

```powershell
just publish-provisioning
# Elevated pwsh — Apply + Hyper-V
just smoke-maintainer-monitor
# or: sudo -E pwsh -NoProfile -File tools/vm/Invoke-SmokeElevated.ps1
# Profile: samples/sl7.profile.json (needs .scratch/sl7.password)
# Custom wall/monitor (positional — not WALL=180 on PowerShell): just smoke-maintainer .scratch/smoke 180 1 45
# Custom ISO only: just smoke 'C:\Users\yanai\Documents\Win11_25H2_English_Arm64_v2.iso'
```

## Session

Prefer one issue per session. Tiny same-risk fixes in touched code are fine — do not leave obvious breakage to obey “no drive-bys.” Apply `ready-for-agent` when starting scoped implement work. Keep `just check` green. Commits when asked: `docs:` · `feat(scope):` · `fix(scope):` …

```powershell
just check
```

**Solo — no PRs** unless asked. Issues are the work surface.

- Create: `gh issue create --title "..." --body "..."` (heredoc for multi-line)
- Read: `gh issue view <number> --comments`
- List: `gh issue list --state open --json number,title,body,labels,comments`
- Comment: `gh issue comment <number> --body "..."`
- Labels: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- Close: `gh issue close <number> --comment "..."`

Labels: `needs-triage` · `needs-info` · `ready-for-agent` · `ready-for-human` · `wontfix`. Apply `ready-for-agent` only when starting an implement session on that issue.

When a skill says “publish to the issue tracker” → create a GitHub issue.  
When a skill says “fetch the relevant ticket” → `gh issue view <number> --comments`.
