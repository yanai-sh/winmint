# Spec: Witnessed Smoke on current HEAD

**Date:** 2026-08-17  
**Status:** Design.  
**Issue:** [#120](https://github.com/yanai-sh/winmint/issues/120)  
**Authority:** [DESIGN](../../DESIGN.md#acceptance) · [CONTEXT](../../../CONTEXT.md) · [TDD](../../TDD.md)  
**Harness:** `tools/vm/Invoke-Smoke.ps1` · `just smoke`

## Decision

S4 Smoke stays one elevated command from Source ISO to `Smoke green` / fail. No guest click, no hand boot-key. Headless is the default. A host **Smoke status** file is a watch-only projection of the wait loop. Optional `-Monitor` opens Hyper-V Connect after the VM starts. This prove-out uses `-Monitor` once so the maintainer sees WinPE apply and FirstLogon splash; later runs may omit it.

Harness-green on an old Output ISO does not meet this spec. Current `main` (includes [#119](https://github.com/yanai-sh/winmint/issues/119)) must land on a **new Apply**. Fixture S4 is not exit.

## Problem

`Invoke-Smoke.ps1` already Applies, creates a Gen2 VM, nudges DVD boot, waits, pulls `%ProgramData%\WinMint\` evidence, and asserts. Scratch logs have printed `Smoke green`. Those runs were agent-waited; the first [#118](https://github.com/yanai-sh/winmint/issues/118) green needed a Hyper-V click to unpause WinPE Quick Edit; HEAD now has a winpeshl helper that no greened ISO contains. The maintainer has not witnessed a hands-off loop on current HEAD. The waiter prints only on events; there is no attachable live status and no opt-in Connect.

## Goals

- One elevated S4 command: Source ISO → Apply → VM → assert. Zero guest interaction.
- Live `smoke-status.json` so a second terminal or agent can watch without sitting in the waiter.
- Opt-in `-Monitor` opens Hyper-V Connect after `Start-VM`. Missing `vmconnect` must not fail the run.
- This prove-out: maintainer runs current HEAD with `-Monitor` and `samples/acceptance.profile.json`, comments the issue, stops.
- `just check` stays free of Hyper-V.

## Non-goals

- Host Apply (S5), Primary, Flash, Prepared-media `-IncludeSmoke`.
- Wizard, web, toast, screenshot timeline, thumbnail loops.
- Changing DESIGN’s Smoke bar (splash-before-Explorer, DMA hard fields, unlock, pinned remove-list).
- Detecting a human click from the harness.
- Raising the default wall clock (90 min stays). Prove-out passes 180 for this run only.
- Committing guest evidence. Scratch stays gitignored.
- Stamping DESIGN “Smoke green” before the issue comment exists.

## Workflow

1. Implement Smoke status + `-Monitor` on `Invoke-Smoke.ps1` (and thin Justfile pass-through). Contract-test the phase map without Hyper-V.
2. Drive [#120](https://github.com/yanai-sh/winmint/issues/120) (`ready-for-human` for the run; `ready-for-agent` only while coding the harness).
3. Maintainer, elevated MSI pwsh, mutex free, **no** `-SkipApply`:

```powershell
pwsh -NoProfile -File tools/vm/Invoke-Smoke.ps1 `
  -Iso 'C:\Users\yanai\AppData\Local\WinMint\source-iso\Win11_25H2_English_Arm64_v2.iso' `
  -Work '.scratch/smoke' `
  -Profile 'samples/acceptance.profile.json' `
  -WallClockMinutes 180 `
  -Monitor
```

Equivalent once Justfile vars exist: `just smoke ISO=… WALL=180 MONITOR=1` with the same Profile/workdir defaults (`WORK=.scratch/smoke`, `PROFILE=samples/acceptance.profile.json`).

4. Watch optional Connect: WinPE apply with no click; splash then Explorer. AFK during hashing/export is fine.
5. Comment on the issue: HEAD, Output ISO leaf, both gates seen y/n, `Smoke green` or the fail line, path to `.scratch/smoke/smoke-evidence/acceptance.json`.
6. Stop. A fail becomes a new issue, not an expansion of this spec. Primary (#96) stays parked.

Pass: assert exit 0, no guest click, current-HEAD Output ISO, maintainer used `-Monitor` this once. Test-lane `Complete` with “1 package failure(s)” is still green.

## Smoke status

Path: `{Work}/smoke-status.json`. Not under `smoke-evidence/` (that folder is guest pull + assert). Not Evidence. The wait loop must not read this file to decide the next phase.

Write at every phase transition, at each wait-loop poll (today 30 s), and on terminal green/fail. During blocking Apply, keep `phase=apply`; DISM stdout is the live Apply feed. Do not spawn a sidecar process to scrape DISM. A status write failure is a warning, not a failed Smoke.

```json
{
  "schemaVersion": "winmint.smoke.status/v1",
  "updatedAt": "2026-08-17T20:00:00Z",
  "phase": "apply",
  "vmName": "winmint-smoke",
  "vmState": null,
  "cpu": null,
  "heartbeat": null,
  "vhdFileSizeMB": null,
  "stallMinutesLeft": 45,
  "wallMinutesLeft": 180,
  "lastHostLine": "Applying Profile=samples/acceptance.profile.json …",
  "outputIso": null
}
```

`phase` is a host observation, not a guest splash claim:

| phase | When |
| --- | --- |
| `apply` | Publish/Apply; VM not started |
| `vm-boot` | VM Running, VHD file size under 1 GB |
| `winpe-apply` | VHD file size ≥ 1 GB, heartbeat not OK |
| `setup-reboot` | VM Starting, Stopping, or Off |
| `guest-up` | Heartbeat OK; guest evidence not yet Complete/Failed |
| `assert` | Guest evidence pulled; assert running |
| `green` | Assert exit 0 |
| `failed` | Throw or assert non-zero |

Do not emit `splash` or `firstlogon` as phases. Splash-before-Explorer stays an `Assert-SmokeEvidence` predicate after pull. Connect is how a human sees paint.

## `-Monitor`

Switch on `Invoke-Smoke.ps1`, default off. After `Start-VM`, start `vmconnect.exe` for that VM name. If the process cannot start, `Write-Warning` and continue. Do not pass `-Monitor` from CI (`just check` never calls this script).

Justfile `smoke` grows optional `WALL` (default `90`) and `MONITOR` (empty = omit `-Monitor`; any non-empty value = pass `-Monitor`).

## Constraints

- One Apply per Host. Mutex `Global\WinMint.ImageServicing.v1` must be free. Do not start a second Smoke.
- Fresh workdir `.scratch/smoke`, VM name `winmint-smoke`. Full Apply (no `-SkipApply`) so #119 lands in `boot.wim`.
- Same Supervisor/settle/job executor as production. Acceptance Profile pins the remove-list.
- Clicking the guest is a human fail for this prove-out even if assert later passes.
- Durable guest evidence remains `%ProgramData%\WinMint\`. Smoke status is host-only and may be deleted with the workdir.

## Testing

- `just check`: one contract test maps a fake snapshot (VM state, VHD size, heartbeat, evidence-ready) → `phase`. No Hyper-V, no ISO.
- S4 fixture tests stay filtered out of `just check`.
- Do not assert `vmconnect` launched in CI.

## Out of scope

Avalonia/WebView2 on the host for this; guest pwsh control plane; reading Smoke status as a mailbox; screenshot artifacts as acceptance; changing stall (45 min) or default wall (90 min) except the explicit prove-out 180.
