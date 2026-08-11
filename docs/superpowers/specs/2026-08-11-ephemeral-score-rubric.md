# WinMint score rubric — ephemeral by design

**Status:** locked for Prospect / Full-flow / Architect reviews  
**Date:** 2026-08-11  
**Supersedes for scoring:** durable-install instincts from the 2026-08-10 operator score-raise and any “default `-CacheRelease` to hit 9” advice.

## Product contract (score against this)

WinMint is a **session-shaped** tool, not a standing install:

| Layer | Ephemeral? | Notes |
|-------|------------|--------|
| Bootstrap + Wizard/Cli **tool** | **Yes** by default | `irm \| iex` extracts a verified toolkit, runs the UI/CLI, may delete the TEMP toolkit when the session ends. Closing the Wizard without a durable flag is **not** a defect. |
| ISO **work** (Apply workdir, `out.iso`, evidence) | **No** | Gigabytes on disk. Same class as winutil Win11 Creator work folders. |
| Optional durable cache (`-CacheRelease` / `-InstallRoot`) | Opt-in | Power-user convenience — **not** required for a 9. |

Do **not** demerit for:

- Missing bare-metal wipe / FirstLogon / Primary-proven Status  
- .NET 11 preview used to **build** release zips in CI  
- External Rufus DD flash (named, honest)  
- Multi-hour DISM (must be disclosed; does not alone cap below 9 if the session path is clear)

Do demerit for:

- Docs that assume a standing toolkit after an ephemeral Wizard exit without a live-session or re-fetch path  
- Clone / GitHub **source** zip as Quickstart  
- Soft Release / Test metal sold as Gate B wipe media  
- Dishonest STALL / progress claims  
- Claiming Primary wipe proven when it is not

## Lenses

### Prospect (visitor / tryability) — 1–10

**Means:** Would a curious developer try the one-liner and trust what they see in five minutes?

**9 means:** One-liner feels safe and valuable; alpha/legal honesty clear; first win possible without BYO ISO (plan/validate); tool does **not** pretend to be a permanent install; ephemeral default is explained as intentional.

**Does not mean:** Toolkit folder still present after quit.

**10:** Rare for alpha — polish + frictionless peer recommendation with almost no lab caveats.

### Full-flow (host path to flashable ISO) — 1–10

**Means:** From a **live ephemeral session** or a **single disposable re-fetch**, can I reach a flashable Gate B `out.iso` with honest wait/flash guidance?

**9 means:** Continuous session story — build while the toolkit session is alive, **or** one re-fetch command that verifies zip+sha256, runs primary-gate (or equivalent), leaves workdir/`out.iso` without requiring a standing LocalAppData install. Wait honesty + Rufus DD + SHA check. `metal` ≠ Primary.

**Does not mean:** Normal path is `cd %LOCALAPPDATA%\WinMint\versions\<tag>` after a prior Wizard quit.

**10:** Near one-shot host chain with minimal handoffs; still not bare-metal proven.

### Architect (orchestration trust) — 1–10

**Means:** Seams, integrity, recipe honesty — would you trust the host pipeline without a new framework?

**9 means:** Mandatory release `.sha256`; Gate B = Release + package-strict (`primary-gate`); soft Release metal cannot green a Primary flash path; Index/digest hardening; Gate B ≠ completed install stated honestly.

**Does not mean:** Feature completeness or wipe proven.

**10:** Little left to distrust on the host path; still alpha.

## Score bands (honest)

| Band | Prospect / Full-flow | Architect |
|------|----------------------|-----------|
| 7 | Lobby or path usable but continuity story fights ephemeral intent (e.g. docs require durable after quit) | Seams OK; some footguns |
| 8 | Ephemeral try works; wipe path exists but awkward (scriptblock tax, dual stories) | Strong integrity; minor soft edges |
| 9 | Ephemeral contract clear; live-session or one-shot re-fetch reaches Gate B ISO | Gate B fail-closed; flash honesty |
| 10 | Not expected until post-alpha / less lab friction | Not expected while Primary wipe unproven |

## Anti-patterns for reviewers

- Treating “ephemeral TEMP delete on Wizard exit” as an automatic −1  
- Requiring durable cache for a 9  
- Scoring bare-metal / FirstLogon into Full-flow  
- Rubber-stamping prior 9/9/9 self-scores  
- Mixing the old “standing toolkit” Full-flow bar with this card

## How to run a review

1. Read this file first.  
2. Read root README + Justfile `primary-gate` / `metal` + `winmint.ps1` session behavior.  
3. Deliver integer (or .5 for Architect only) scores with: Score, what earned points under **this** card, remaining gaps under 9, one line on whether durable-default advice still applies (usually: no).
