# Restore-path guidance (docs only)

**Date:** 2026-08-09  
**Status:** Design (approved in grill)  
**Issue:** [#96](https://github.com/yanai-sh/winmint/issues/96) Primary gate (maintainer SL7 wipe); public wording for all metal/wipe operators  
**Glossary:** [CONTEXT](../../../CONTEXT.md) (Primary gate, Smoke, Source ISO)

## Problem Statement

Before a destructive WinMint wipe, the operator needs a way back to bootable Windows if the install fails. Surface bare-metal recovery (BMR) is serial-gated and must not be redistributed. Other Windows-on-ARM devices use different OEM recovery flows. WinMint assumes competent operators who have read the README; stuffing restore lectures into CLI/Wizard creates noise and false safety theater (the product cannot verify recovery media).

## Solution

Document restore-path hygiene in **README** (and agent/Primary-gate notes). **Do not** add CLI or Wizard prompts, warnings, or gates. Never ship or hotlink recovery images. Link Microsoft’s Surface recovery download only as a Surface *example*; keep wording device-agnostic for other WoA OEMs.

## User Stories

1. As a metal/wipe operator, I want a short README preflight that tells me to have a restore path for *this* PC, so I am not surprised after a failed wipe.
2. As a Surface operator, I want a link to the official Surface recovery image download, so I fetch a serial-matched BMR myself.
3. As a non-Surface WoA operator, I want the same README sentence to cover OEM or Windows recovery media, so Surface is not implied as required.
4. As a maintainer running Primary gate (#96), I want my existing local BMR zip to count as restore path for *this* SL7, without committing or linking that file in the repo.
5. As a Wizard/CLI user, I do not want backup/restore nag copy on every plan/build, so product surfaces stay about compose and Apply.
6. As an agent, I want CONTEXT Primary gate to say restore path is operator hygiene (OEM/Windows recovery; no WinMint media), so sessions do not invent CLI guardrails.

## Implementation Decisions

- **Placement:** README only for public product lobby (2–4 lines under Quickstart or a tiny “Before you wipe a machine” blurb). Optional one-line cross-link from CONTEXT Primary gate / #96 wizard stages — not Profile, BuildPlan, Cli, or Avalonia.
- **Out of product runtime:** No `Status` strings, no confirm dialogs, no `--require-restore`, no Wizard stage for backup.
- **Wording shape (canonical):** Before wiping a machine with a WinMint ISO, have a restore path for that device — OEM recovery when the vendor provides it (Surface: [Surface recovery image download](https://support.microsoft.com/surfacerecoveryimage), serial + Microsoft account), or a Windows recovery drive. WinMint does not download or ship recovery images.
- **Non-Surface:** One sentence; “check your PC maker’s support site” is enough — no deep OEM link farm.
- **Maintainer #96:** Local serial-matched BMR (e.g. under Downloads) satisfies restore path for this device; never add the path to README or git. Primary-gate wizard may ask “restore path ready?” as a human confirm, not a file probe of a personal zip.
- **ADR-001 adjacency:** Source ISO legal posture stays separate; this note is wipe hygiene, not media redistribution of Windows setup ISOs.
- **Assumption:** Operators read the README before metal wipe — pedantic restore copy stays out of GUI/CLI.

## Testing Decisions

- No automated tests (docs-only).
- Self-check: `rg` / review that Cli and Wizard have no new restore/backup user-facing strings from this work.
- Primary-gate wizard (if authored) uses confirm-only restore stage; does not require or commit BMR paths.

## Out of Scope

- Bundling, mirroring, or Redistributing Surface BMR / OEM recovery images
- CLI/Wizard guardrails or blocking builds on “backup present”
- Full disk clone as a product requirement
- M4 hardware campaign; leftover/CDM cleanup
- Changing Smoke or Gate B harness behavior

## Further Notes

- Grill 2026-08-09: Approach “link-only / docs-only”; audience both public + maintainer priority on this SL7; Surface serial gate → link out; non-Surface = OEM or Windows recovery; README-before-use ⇒ strip pedantry from CLI/GUI.
