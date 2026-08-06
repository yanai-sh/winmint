# Closed backlog index (01–30)

**Status:** Product backlog **01–30** done (2026-08-05). Not an open queue.  
**Next work:** maintainer pick, grill → to-spec, or a new GitHub issue — apply `ready-for-agent` only when starting that work.  
**Authority:** grill [DESIGN](DESIGN.md#grill-index-tiered) · modules [design/](design/) · milestones [ROADMAP](ROADMAP.md) · seams [TDD](TDD.md) · Smoke [spec](specs/2026-07-27-smoke.md)

Full ticket-card novels lived here through delivery; git history retains them. This file is the closed index only.

## Invariants still out

See [DESIGN grill index](DESIGN.md#grill-index-tiered) tier **I** and [ADR-011](decisions/ADR-011-alpha-posture-and-package-delegation.md):

- Profile presets-in-JSON
- Schema `v2` without a breaking change
- Leftover-confidence *product* cleanup
- CDM-as-primary keep-flag control ([ADR-007](decisions/ADR-007-cdm-not-primary.md))
- Full DPAPI host→guest channel; full D2D splash
- Slice 2 always-on OneDrive / Recall / KeepCopilot (issue **56** follow-on)

Also never in product: BitLocker Smoke, Home Smoke SKU, MicrosoftOobe, enterprise secrets, MediatR/Generic Host/Contracts project, **guest pwsh product runtime**, peer Splash.

## Closed index

| # | Issue | Done | One-line outcome |
|---|-------|------|------------------|
| 01 | [#3](https://github.com/yanai-sh/winmint/issues/3) | 2026-07-29 | Profile + Plan + Cli `validate`/`plan` |
| 02 | [#4](https://github.com/yanai-sh/winmint/issues/4) | 2026-08-02 | Servicing Apply + Shell stamp + Cli `build` |
| 03 | [#5](https://github.com/yanai-sh/winmint/issues/5) | 2026-08-03 | Machine setup stamps (autologon / Shell / wipe) |
| 04 | [#6](https://github.com/yanai-sh/winmint/issues/6) | 2026-08-03 | Shell splash + status + evidence |
| 05 | [#7](https://github.com/yanai-sh/winmint/issues/7) | 2026-08-03 | DMA settle (final snapshot authoritative) |
| 06 | [#8](https://github.com/yanai-sh/winmint/issues/8) | 2026-08-03 | Stub jobs + child-process executor |
| 07 | [#9](https://github.com/yanai-sh/winmint/issues/9) | 2026-08-04 | Unlock + timeout + stale fail-open |
| 08 | [#10](https://github.com/yanai-sh/winmint/issues/10) | 2026-08-04 | Checkpoint reboot keeps Shell |
| 09 | [#11](https://github.com/yanai-sh/winmint/issues/11) | 2026-08-04 | `Test`/`Release` ExportWim lane |
| 10 | [#12](https://github.com/yanai-sh/winmint/issues/12) | 2026-08-04 | Hyper-V Smoke harness (`tools/vm/`) |
| 11 | [#22](https://github.com/yanai-sh/winmint/issues/22) | 2026-08-04 | Profile AppX remove-list + catalog + Plan |
| 12 | [#23](https://github.com/yanai-sh/winmint/issues/23) | 2026-08-04 | Offline RemoveProvisionedAppx (absent ⇒ ok + digest) |
| 13 | [#24](https://github.com/yanai-sh/winmint/issues/24) | 2026-08-04 | FirstLogon AppX PackageManager safety-net |
| 14 | [#26](https://github.com/yanai-sh/winmint/issues/26) | 2026-08-04 | Maintainer Smoke prove-out (real 25H2 ARM64 ISO) |
| 15 | [#27](https://github.com/yanai-sh/winmint/issues/27) | 2026-08-04 | Wizard = second BuildPlan host (presets → lists) |
| 16 | [#28](https://github.com/yanai-sh/winmint/issues/28) | 2026-08-04 | Metal `winget` job (guest Hyper-V proven) |
| 17 | [#29](https://github.com/yanai-sh/winmint/issues/29) | 2026-08-04 | Profile `needsReboot` + Hyper-V reboot-resume |
| 18 | [#30](https://github.com/yanai-sh/winmint/issues/30) | 2026-08-04 | Scoop job + official FirstLogon bootstrap (metal exit) |
| 19 | [#31](https://github.com/yanai-sh/winmint/issues/31) | 2026-08-04 | Caps/features matrix spike → thin acceptance pins |
| 20 | [#32](https://github.com/yanai-sh/winmint/issues/32) | 2026-08-04 | Offline capability/feature remove + digests |
| 21 | [#33](https://github.com/yanai-sh/winmint/issues/33) | 2026-08-05 | Israel DMA sample + monotonic settle; Hyper-V Complete |
| 22 | [#34](https://github.com/yanai-sh/winmint/issues/34) | 2026-08-05 | Wizard packages UI (winget + Scoop lists) |
| 23 | [#35](https://github.com/yanai-sh/winmint/issues/35) | 2026-08-05 | Metal `wsl` job kind (S1/S3) |
| 24 | [#36](https://github.com/yanai-sh/winmint/issues/36) | 2026-08-05 | ExitWindowsEx reboot + `shutdown.exe` fallback |
| 25 | [#37](https://github.com/yanai-sh/winmint/issues/37) | 2026-08-05 | Wizard polish (caps/features + WSL + Israel DMA) |
| 26 | [#38](https://github.com/yanai-sh/winmint/issues/38) | 2026-08-05 | Leftover-confidence spike — no product cleanup |
| 27 | [#39](https://github.com/yanai-sh/winmint/issues/39) | 2026-08-05 | ADR-007: CDM not primary |
| 28 | [#40](https://github.com/yanai-sh/winmint/issues/40) | 2026-08-05 | Best-effort secrets wipe on Machine setup |
| 29 | [#41](https://github.com/yanai-sh/winmint/issues/41) | 2026-08-05 | GDI splash status text (`TextOutW`) |
| 30 | [#42](https://github.com/yanai-sh/winmint/issues/42) | 2026-08-05 | Hardware M4 opt-in evidence bars |
| 31 | [#64–#69](https://github.com/yanai-sh/winmint/issues/64) | 2026-08-05 | Package catalog + ARM64 harvest (Plan validation, Wizard chips, winget arch, WSL fromFile, native audit) |
| 32 | [#73–#79](https://github.com/yanai-sh/winmint/issues/73) | 2026-08-06 | Alpha package program: ADR-011 docs + winget import + scoop batch + best-effort + harness ([spec](specs/2026-08-06-alpha-package-program.md)) |
| 33 | [#63](https://github.com/yanai-sh/winmint/issues/63) | 2026-08-06 | Surface Catalog offline driver injection (SL7 `surface-laptop-7`, Inject-SurfaceDrivers.ps1, metal inventory digests) |
| 34 | [#58](https://github.com/yanai-sh/winmint/issues/58) | 2026-08-06 | Wizard Source edition probe: list ISO WIM indexes via Wim-Metadata; picker → `WimIndex` Apply path |
| 35 | [#59](https://github.com/yanai-sh/winmint/issues/59) | 2026-08-06 | Wizard Build polls `apply-status.txt` for opcode stage + log path during Apply |

Sequencing history: [ADR-006](decisions/ADR-006-post-keepflag-sequencing.md) (**met**). Keep-flag design: [KEEPFLAG](design/KEEPFLAG.md).

## Doc map

| Need | Read |
|------|------|
| Why / locks | [DESIGN](DESIGN.md), [V1-LESSONS](design/V1-LESSONS.md), ADRs |
| Closed index (this file) | **TICKETS** |
| When / milestones | [ROADMAP](ROADMAP.md) |
| How to run sessions | [AGENTIC](agents/AGENTIC.md), [TDD](TDD.md) |
| Domain behaviour | Smoke spec, [ARCHITECTURE](ARCHITECTURE.md), [design/](design/) |
