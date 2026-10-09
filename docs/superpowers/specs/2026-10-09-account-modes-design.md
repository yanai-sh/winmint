# Account modes design (`oobeLocal` + `localAutoLogon`)

**Status:** Accepted for planning (ADR-017). Implement mode wire before flipping curated default.  
**Supersedes for portability:** #136 P1 custom identity UI / Tenure M→U.

## Goal

Shareable Output ISO without baking the owner password, without a custom WinMint account UI. Keep zero-touch bake-in for Smoke/automation.

## Modes

| Mode | Profile credentials | Unattend | Shell | FirstLogon |
|------|---------------------|----------|-------|------------|
| `oobeLocal` | none | No LocalAccounts/AutoLogon; keep local-OOBE escapes (HideOnlineAccountScreens / BypassNRO as today) | Prefer offline Supervisor Shell; **defer** (explorer → set Shell → re-enter FirstLogon) if OOBE blocked | Single tenure as OOBE-created owner |
| `localAutoLogon` | username + password(Path) required | LocalAccounts + AutoLogon (today) | Offline Supervisor Shell | Single tenure from first frame |

## Defaults (gated)

1. **Implement** both modes; contracts freeze the wire.
2. **Operational default** stays `localAutoLogon` (Wizard curated emit, Smoke, `samples/sl7.profile.json`) until Primary/VM proves `oobeLocal` handoff.
3. **Then** flip curated / Wizard default to `oobeLocal`. Do not flip `sl7.profile.json` in the same change as the mode wire unless Primary migrates deliberately.

## Explicit non-goals

- In-splash / Win32 identity form (C2 UI).
- Tenure M vs U job split for portability.
- Password at Flash (ADR-012).
- MSA as shipping owner default.

## Proof gate (before curated default flip)

- Install from `oobeLocal` media on Home ARM64 (or Hyper-V proxy with interactive OOBE).
- Native local account created; first Supervisor tenure Completes; Explorer unlock; evidence off-box.
- Record whether deferred Shell was required.

## Implementation sketch (not a task list)

- `AccountProfile` / BuildPlan: accept `oobeLocal`; password required iff `localAutoLogon`.
- Unattend builder branches on mode.
- Machine setup / Shell stamp: mode-aware deferred path for `oobeLocal` only.
- Wizard Account stage: progressive disclosure for bake-in; warn ISO contains password.
- Smoke: hard-pin `localAutoLogon`.
- Retarget #136 map: P1 UI → superseded; children for mode wire + Shell spike + proof.

## Cross-critique summary

Dual-mode end-state survived UX + architecture critique. Platform critique blocked naive “default now” without Shell×OOBE proof — encoded as the gated default flip and deferred-Shell escape.
