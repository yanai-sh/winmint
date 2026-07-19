# Spec: FirstLogon reliability polish (Track A)

**Date:** 2026-07-19  
**Status:** Ready for tickets  
**Parent grill:** [2026-07-19-polish-program-grill-outcomes.md](2026-07-19-polish-program-grill-outcomes.md)  
**Research:** [docs/research/2026-07-19-polish-primary-sources.md](../research/2026-07-19-polish-primary-sources.md)  
**Related:** [2026-07-19-start-taskbar-pins-terminal-design.md](2026-07-19-start-taskbar-pins-terminal-design.md)

## Problem Statement

After a WinMint install, FirstLogon can report success while the desktop still feels unfinished: selected browsers/editors missing from Start/taskbar, package managers left on stale App Installer/WebView2/Terminal, or DMA location posture only half-restored. Users cannot trust “setup complete.”

## Solution

Deepen existing FirstLogon seams so pins, winget catch-up, and DMA restore are honest and evidence-backed—without new product toggles. Later tickets harden provisioning-lock presenter signals and under-lock WSL reboot/resume.

## User Stories

1. As an installer, I want my chosen browsers and editors on Start and taskbar after FirstLogon, so that the desktop matches the Profile.
2. As an installer, I want Edge pinned only when I selected Edge as a browser, so that Zen-first builds do not force an Edge Start pin.
3. As an installer, I want missing pin targets reported clearly, so that I know what failed without a cryptic blank taskbar.
4. As an installer, I want App Installer, WebView2, and Terminal brought current before broad upgrades, so that FirstLogon installs are not fighting a broken winget stack.
5. As an installer, I want `winget upgrade --all` partial failure not treated as full success without targeted repair, so that “ok” means usable.
6. As an installer with DMA on, I want my visible region and location posture restored before agent work, so that Ireland Setup does not leak into daily use.
7. As an installer, I want location consent/`lfsvc` checked when restore requests location on, so that Maps/time-zone features work.
8. As a Hyper-V smoker, I want pin and DMA evidence in acceptance artifacts, so that plumbing fails when restore/pins silently skip.
9. As a maintainer, I want presenter/host health visible in acceptance later, so that GDI-fallback or blank splash is not ignored.
10. As a bare-metal user with WSL distros, I want a controlled reboot under the provisioning lock when the agent needs one, so that WSL finishes without a stuck desktop (smoke stays mocked).

## Implementation Decisions

- Prefer existing FirstLogon Desktop / PackageManagers / Region modules over new modules.
- Pins: follow approved pin design; selection from `development.browsers` / `editors`; apply after apps exist and after provisioning-lock release path already used for explorer reload; keep best-effort skip for missing shortcuts unless registry/XML write fails.
- Winget: `Repair-WinGetPackageManager` (and source update) before targeted machine-scope upgrades of Desktop App Installer, WebView2 Runtime, and Windows Terminal; only then consider broader upgrade; do not treat bulk UPDATE_ALL_HAS_FAILURE as clean success without recording which packages failed.
- DMA: extend compliance so when restore requests location services enabled, consent store + `lfsvc` posture are pass/fail criteria alongside GeoID/TZ/locale.
- Presenter signal (later): surface `presenter=` / host health into VM acceptance plumbing, not logs-only.
- WSL reboot (later): under-lock reboot/resume when agent returns `needsReboot`; Hyper-V smoke keeps `wslRuntimeValidation=skip`.

## Testing Decisions

- Test external behavior: pin report JSON, winget module outcomes, DMA compliance result, acceptance signals.
- Prefer existing seams: `Test-ShellPinsAndTerminalProfiles.ps1`, Profile invariants, VM evidence collectors, FirstLogon region contracts.
- Must items require contract tests; VM smoke evidence for pins + DMA on SL7/smoke profiles.

## Seams (for implementers)

1. FirstLogon pin selection + apply + `FirstLogon_ShellPins.json` (highest product seam).
2. FirstLogon PackageManagers bootstrap/catch-up result (agent step status + log).
3. DMA restore compliance object consumed by FirstLogon runtime hard-fail path.
4. (Later) Acceptance plumbing for setup-shell presenter.
5. (Later) Agent `needsReboot` → transaction reboot under lock.

## Out of Scope

- Edge uninstall; new Profile flags; changing DMA Ireland setup latch; enabling real WSL in Hyper-V smoke; Tier‑3 disables.

## Further Notes

Ship order preference (not technical blockers): pins → winget → DMA must, then Track B durability, then later A6/A9.
