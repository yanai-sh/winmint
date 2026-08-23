# Smoke: hands-off past OOBE “Just a moment” (plus stamp / phase debounce)

**Date:** 2026-08-23  
**Status:** implemented (stamp + sticky; first-paint full dismiss rejected)  
**Scope:** Guest FirstLogon + Smoke wait. No host `Restart-VM`.

## Problem (operator-confirmed)

1. **Connect shows Windows “Just a moment” (CloudExperienceHost) with no WinMint splash.** Operator shuts the VM down to unstick it.
2. **After that manual shutdown**, login requires typing the password before splash — expected once autologon was never finished or residue already cleared `AutoAdminLogon`. That password step is a **consequence**, not the root bug.
3. Secondary (still real): `smoke-run.id` stamped only at DVD boot (fails); Evidence `smokeRunId` null. Wait phase flickers `winpe-apply` ↔ `guest-up` on heartbeat blips.

Research ([2026-08-16-clean-hands-off-oobe](../research/2026-08-16-clean-hands-off-oobe.md)): “Just a moment” has **no** unattend hide; short CEH progress is normal; do not `SkipMachineOOBE`. Custom Shell **during** OOBE is unsupported (Recovery). Overlay dismiss today runs only **after** Shell unlock (`oobe.dismiss`) — too late if CEH covers the session **before** splash is visible / if OOBE never yields FirstLogon.

## Goals

- Hands-off path: WinPE apply → OOBE answers → SetupComplete → autologon → **Supervisor splash visible** without operator shutdown or password.
- If CEH overlay sits on top **after** the Profile user is already in a Shell tenure, dismiss it **at first paint** (not only at unlock).
- Do not host-reboot on “Just a moment.”
- Keep stamp-on-first-contact + sticky `guest-up` from the earlier draft.

## Non-goals

- Host `Restart-VM` / periodic reset when CEH is visible.
- `SkipMachineOOBE` / `SkipUserOOBE` / BypassNRO / clicking Next.
- Changing Ireland / DMA unattend answers.
- Guaranteeing zero CEH frames (short “Getting ready” remains OK).

## Approaches

### A. Full early overlay dismiss at first paint (includes registry stamps) — **REJECTED for v1 of this change**

`Win32OobeOverlay.TryDismiss` calls `TryStampSetupComplete` (`UserOobe`, `OobeInProgress`, `ImageState=IMAGE_STATE_COMPLETE`). Operator evidence 2026-08-23: after manual restart during “Just a moment”, guest shows OOBE Recovery **“Why did my PC restart?”** — the same class of failure SetupComplete non-zero / premature complete-state reseal produces. Shipping full dismiss earlier increases Recovery risk if tenure/OOBE ordering is wrong. Keep full dismiss **only at unlock** (`oobe.dismiss`).

### A2. Kill-only CEH at first paint (optional follow-up)

Kill `CloudExperienceHost` / listed hosts **without** registry ImageState stamps. Only when Shell tenure already started. Not in the first implementation slice if we lack a live prove-out; prefer stamp+debounce first.

### B. Harness patience + no operator reboot (docs)

Document: do **not** shut down on “Just a moment” — that path yields password login and often Recovery. Stall already extends on CPU / setup churn.

### C. Host Restart-VM when CEH detected

Rejected.

**Recommendation for this implement:** **stamp + sticky guest-up only**; unlock-time `oobe.dismiss` unchanged; **no** first-paint full dismiss. Recovery after manual restart is operator-induced on this run — fresh Smoke after stamp fix, leave VM alone through CEH.

## Design detail (stamp + debounce) — unchanged

- Retry `smoke-run.id` stamp on first successful PS Direct in wait loop; flag once.
- Sticky `guest-up` after 2 consecutive heartbeat-OK polls while Running; clear sticky only when not Running.
- DVD eject still uses **live** heartbeat.

## Success

- Smoke Connect: after OOBE answers, splash appears without shutting the VM; no password typed.
- Manual shutdown no longer part of the happy path.
- Evidence carries matching `smokeRunId`; status phase does not flap on one heartbeat drop.
- S4 still fail-closes on live handoff + `oobe.dismiss` at unlock.

## Out of session

Live run `0352596f…` may already be poisoned by manual shutdown; prove on a **fresh** Smoke after this lands (`just publish-provisioning` then `just smoke-maintainer`).
