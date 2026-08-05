# ADR-009: Product-constant offline policies (not AppX recommended set)

**Status:** Accepted  
**Date:** 2026-08-05  
**Related:** [ADR-005](ADR-005-keep-flag-matrix.md), [ADR-007](ADR-007-cdm-not-primary.md), [IMAGESERVICING](../design/IMAGESERVICING.md), [KEEPFLAG](../design/KEEPFLAG.md)

### Context

WinMint always removes OneDrive and applies Edge debloat / companion-app / WPBT stamps derived from CTT winutil essentials — separate from the keep-flag **AppX** remove-list. ADR-005 forbids a silent product-default **AppX recommended set inside Profile JSON**; that lock must not be read as “no product posture at all.”

Separately: Copilot Edge sidebar / Windows Copilot kill is **not** part of winutil EdgeDebloat (17 telemetry/shopping keys). Keeping Copilot must leave those Copilot-specific keys alone. Brave debloat applies only when the user selected Brave in packages.

CDM spray remains out ([ADR-007](ADR-007-cdm-not-primary.md)).

### Decision

1. **Product constants** (always stamped / always jobbed; not Profile toggles):
   - Offline: winutil **EdgeDebloat** (17 HKLM Edge/EdgeUpdate policies).
   - Offline: OneDrive `DisableFileSyncNGSC=1`.
   - Offline: `PreventDeviceMetadataFromNetwork=1`.
   - Offline: `DisableWpbtExecution=1` (SYSTEM ControlSet001).
   - FirstLogon: `onedrive.uninstall` (`OneDriveSetup.exe /uninstall`, best-effort).
   - FirstLogon: `reservedStorage.disable` (`dism /Online /Set-ReservedStorageState /State:Disabled`).
2. **Optional Profile `policies`** on `winmint.profile/v1` (omit = defaults):
   - `keepCopilot` (default **false**) — when false, stamp `HubsSidebarEnabled=0` + `TurnOffWindowsCopilot=1`; host recommended preset may add Copilot AppX to the remove-list. When true, do **not** stamp those keys and do **not** add Copilot AppX via preset.
   - `dohProvider` (`cloudflare` \| `google` \| `quad9` \| null) — optional FirstLogon `doh.set` job; Smoke default off.
3. **Derived (no Profile flag):** if `packages.winget` contains `Brave.Brave`, stamp winutil BraveDebloat (12 HKLM BraveSoftware policies).
4. **Opcode:** `StampOfflinePolicies` after keep-flag removes, before `StagePayload`. Param-only `policySpecs`; Plan owns branching.
5. This does **not** make CDM primary and does **not** put AppX preset names in Profile JSON.

### Consequences

- Wizard `KeepCopilot` ↔ `policies.keepCopilot`.
- Digests `policy.<family>.<Name>=<data>` under `logs/digests.json`.
- Store MSIX host pwsh fails closed on Apply (`servicing.pwsh.storeMsix`).
