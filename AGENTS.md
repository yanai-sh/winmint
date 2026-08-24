# WinMint — Agent contract

Windows 11 ISO builder (**alpha**). **ARM64-first**. Host Servicing: **pwsh 7.6+**. Guest FirstLogon: **Provisioning Supervisor**; packages may delegate to platform tools.

## Core rule

**CLI/Orchestrator creates intent. Servicing mutates the offline image. Provisioning Supervisor finishes live-user setup.**

Elevate **only** Servicing `pwsh -File`. No v1 `WinMint.ps1`. No guest **pwsh product runtime** — inbox `powershell.exe` for Scoop bootstrap or narrow winget import/configure is OK.

## Docs

Code and tests are the product ([ADR-014](docs/decisions/ADR-014-docs-are-not-living-law.md)). Markdown holds three things:

- **Glossary** — [CONTEXT.md](CONTEXT.md)
- **Why** — [docs/decisions/](docs/decisions/)
- **This map**

Do not add living design docs. Do not restate types, opcodes, or defaults that already live in `src/`. An ADR is the choice and what was rejected — not an id catalog or changelog.

Short form of the identity bars (detail is ADRs + code): Source ISO · Supervisor FirstLogon · remove-list / no presets-in-JSON / CDM not primary · residual erase · single-image WIM · `winmint.profile/v1` until a real break.

## Map

| Module | Lives in |
|--------|----------|
| **BuildPlan** | `src/WinMint.Orchestrator` |
| **ImageServicing** | `src/WinMint.Orchestrator` + `servicing/` |
| **ProvisioningSession** | `src/WinMint.Provisioning` |
| **HostCompile** | Orchestrator entry (not a fourth module) |

Front ends: `src/WinMint.Cli`, `src/WinMint.Wizard`. Guest apply helper: `src/WinMint.WinPeApply`. Staged bits: `payload/`. Pins: `global.json`, `Directory.Build.props`. Tests: `tests/` — `just check`.

Operator/legal: [README.md](README.md), [SECURITY.md](SECURITY.md), [PRIVACY.md](PRIVACY.md), [docs/CODE_SIGNING.md](docs/CODE_SIGNING.md).

## Maintainer host

**Clock** — Maintainer zone is Asia/Jerusalem (Tel Aviv). SL7’s system time can jump backward at random even after a sync (faulty DMA workaround on this machine, not product DMA settle). Do not trust `Get-Date`, `[datetime]::UtcNow`, file `LastWriteTime`, chat timestamps, or harness remaining-time as elapsed truth. Smoke stall/wall and the DVD boot-nudge window are wall-clock: a backward jump inflates them. If remaining time grows or files look newer than “now,” the clock jumped — stop treating those timers as elapsed and ask the human. A sync is temporary.

**Vanilla Source ISO (Smoke / Host Apply)** — Official Microsoft 25H2 English ARM64 ISO on this host:

`C:\Users\yanai\Documents\Win11_25H2_English_Arm64_v2.iso`

Same fact in [tests/fixtures/maintainer-host.json](tests/fixtures/maintainer-host.json). User-supplied only ([ADR-001](docs/decisions/ADR-001-source-iso-legal.md)); never commit the ISO bytes; CI must not fetch Windows media.

```powershell
just publish-provisioning
just smoke-maintainer
# Profile default: samples/sl7.profile.json (needs .scratch/sl7.password)
# or: just smoke 'C:\Users\yanai\Documents\Win11_25H2_English_Arm64_v2.iso'
# (positional path — do not use ISO=path under PowerShell)
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
