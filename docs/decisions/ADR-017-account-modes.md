# ADR-017: Account modes — portable OOBE vs bake-in AutoLogon

## Decision

Profile `account.mode` has two shipping values:

- **`oobeLocal`** — intended product default for shareable Output ISOs: no baked `LocalAccounts` / AutoLogon; native Windows OOBE creates the owner; single FirstLogon tenure as that user. May use **deferred Shell** (explorer through OOBE, Supervisor Shell after first interactive logon) when offline Shell stamp blocks OOBE.
- **`localAutoLogon`** — optional bake-in: username + password in the ISO; AutoLogon into Supervisor; single tenure from the start (today’s path). Required for Smoke / headless automation until proven otherwise.

**Default flip is gated:** implement `oobeLocal` first; Wizard / curated emit keep `localAutoLogon` until Primary (or equivalent) proves FirstLogon handoff; only then make `oobeLocal` the curated default. `samples/sl7.profile.json` is not flipped in the same change as the mode wire.

C2 custom identity UI / Tenure M→U is **superseded for the portability goal** (not deleted as archaeology — do not unpark splash account forms for this).

## Why

A password baked into the Output ISO ties media to one secret and fights “Flash this ISO.” Native OOBE already owns local identity. WinMint’s differentiator is Supervisor FirstLogon, not a second account UI. Dual mode keeps zero-touch labs without making credential-bound ISOs the permanent product story. Offline `StampOfflineShell` may collide with interactive OOBE — defer Shell for `oobeLocal` only if proof requires it; keep offline Shell for `localAutoLogon`.

## Rejected

- C2 in-splash / custom identity UI as the portable path.
- Credential-bound ISO forever, with Station pack as the only portable unit.
- Flipping curated / Wizard default to `oobeLocal` before Shell×OOBE proof.
- Password injection at Flash (Flash stays outside the product seam — ADR-012).
- MSA-primary owner identity as the shipping default.

## Review trigger

`oobeLocal` FirstLogon fails Shell/handoff on Home ARM64; Microsoft removes a stable local-OOBE escape; or deferred Shell proves unacceptable for Primary UX.
