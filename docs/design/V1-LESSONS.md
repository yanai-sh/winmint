# v1 lessons (why greenfield)

**Archive:** sibling [`winmint_v1`](https://github.com/yanai-sh/winmint_v1) — archaeology, not authority.  
**Companion:** [ARCHITECTURE harvest rule](../ARCHITECTURE.md#v1-harvest-rule) · [ADR-004](../decisions/ADR-004-stack-and-guest-control-plane.md)

v1 shipped a working ISO builder, but **guest FirstLogon was hard to trust and hard to test**. That is the primary reason for this clean-sheet control plane — not “rewrite for C#.”

## What v1 looked like on the critical path

```
SetupComplete (SYSTEM)
  → Winlogon Shell = WinMintLogonShell.cmd
      → pwsh LogonShell → peer WinMintSetupShell.exe (polls JSON)
      → self-start PreLock + FirstLogon (RunOnce won’t fire without Explorer)
          → more pwsh + Agent child
          → status/control/state JSON mailboxes
  → unlock Shell → Explorer
```

Rough runtime size: **~130+** product scripts under `src/runtime/` (image/setup/firstlogon). Concurrent guest processes: LogonShell pwsh, FirstLogon/PreLock pwsh, Splash exe, Agent pwsh.

## Documented failure modes (primary sources)

_Source paths refer to the v1 repo archive._

| Pain | What happened | Source |
|------|----------------|--------|
| **Shell ↔ RunOnce deadlock** | Custom Shell prevented Explorer → Unattend RunOnce never ran → FirstLogon stuck / “Just a moment” | `docs/research/2026-07-27-firstlogon-shell-override.md` |
| **defaultuser0 + AutoAdminLogon** | First interactive logon hung on OOBE anim; FirstLogon never started | `AGENTS.md`, VM stall fail-fast |
| **Autologon stamp race** | SetupComplete stamped real user; OOBE reboot / harness still saw `defaultuser0` | `docs/research/2026-07-27-v1-oobe-softbsod-harvest.md` |
| **pwsh cold start / late splash** | Seconds before guard/splash; light Explorer desktop first | `docs/research/2026-07-22-firstlogon-splash-theme-dma-audit.md` (~+4.8s fire→guard) |
| **Sticky DMA intermediate fail** | Culture fail ~114ms after language list → agent skipped; final LocaleName later OK | same DMA audit |
| **File control plane** | Splash polls `setup-shell-control.json` / `setup-shell-status.json`; agent writes `state.json` | `docs/codebase/ARCHITECTURE.md` |
| **Push loops skip the pain** | Headless push exercises agent without proving splash→Explorer on fresh ISO | `docs/codebase/TESTING.md`, `docs/VM-Acceptance.md` |

## Why it was difficult to test

- **Dot-source ambient engine** (ADR-003): weak typing, load-order coupling, “no broad unit framework / mocks of internals.”
- **Real FirstLogon only on elevated Hyper-V** (ADR-009 keeps VM out of CI); Smoke Wait default **~90 minutes**; stall fail-fast still needed for Shell↔RunOnce hangs.
- Contract/Pester covered Profile/plan/CLI — **not** Winlogon Shell tenure, peer Splash JSON IPC, or DMA settle races.
- Fast iteration (checkpoint + push) **optimized away** the path that failed in the wild.

Shallow modules everywhere: many scripts, large interfaces (ambient state + file mailboxes), little behaviour callable through one small seam.

## How v2 answers each pain

| v1 pain | v2 module / rule |
|---------|------------------|
| Multi-pwsh + peer Splash + JSON mailbox | **ProvisioningSession** — one AOT process; in-process splash; **in-memory** status; JSON = evidence only |
| Shell ↔ RunOnce / PreLock graph | Supervisor **is** Shell; Machine setup + Shell are modes of one phase machine |
| pwsh cold start on critical path | **No guest pwsh** (ADR-004) |
| Sticky DMA intermediate errors | Settle by **final snapshot**; hard locale/GeoID/TZ; soft location |
| defaultuser0 / stamp races | Offline Shell stamp + Machine setup fail-closed verify/restamp |
| Explorer flash on reboot | Hold Shell on `reboot` + durable checkpoint |
| Untestable ambient engine | **BuildPlan** / **ProvisioningSession** as deep modules; TDD at [confirmed seams](../TDD.md) |
| Headless push false confidence | Smoke acceptance must prove Shell tenure + DMA hard fields ([S4](../TDD.md)) |

## Harvest vs do-not-copy

**Harvest:** password-required local; never `defaultuser0`+AutoAdminLogon; splash before Explorer; fail-open unlock; reboot holds Shell; DMA Ireland + restore; image-quality lanes; thin host DISM kernels; VM fingerprint/checkpoint as **harness** concerns.

**Do not copy:** PreLock/LogonShell/RunOnce topology; peer Splash.exe; file status/control as control plane; guest pwsh FirstLogon; wrapping `WinMint.ps1`; v1 BuildProfile/InstallPlan; WebView2 on ISO; OOBE soft-BSOD custom-Shell-while-OobeInProgress stacks.

## Agent rule

When a change “feels like v1,” check this doc. If it reintroduces a row from the pain table, **stop** — update ADR/ARCHITECTURE first, don’t “temporarily” stage guest pwsh or a splash peer.
