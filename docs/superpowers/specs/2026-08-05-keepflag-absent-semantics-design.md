# KeepFlag AppX absent semantics

**Date:** 2026-08-05  
**Status:** Approved (architecture review candidate #1; design dialogue)  
**Locks:** Listed-but-absent provisioned AppX ⇒ idempotent ok + digest (same as caps/features)

## Problem

[KEEPFLAG](../../design/KEEPFLAG.md) said ImageServicing must **fail closed** when a Profile-listed AppX catalog id was not on the mounted image (ticket **12**). Shipped [`Remove-ProvisionedAppx.ps1`](../../../servicing/Remove-ProvisionedAppx.ps1) already treats that case as success for reuse-media re-Apply and always writes `removed.appx.<id>=absent`. Capabilities/features already document listed-but-absent ⇒ ok + digest (ticket **20**). Agents reading KEEPFLAG would implement the wrong failure mode.

## Decision

**Policy A:** desired end state is “gone.” Listed id not present / already stripped ⇒ success + digest. Unknown catalog id remains fail-closed at **BuildPlan**.

**Approach:** Doc retcon only. No kernel, test, or ADR changes.

## Changes

| File | Change |
|------|--------|
| `docs/design/KEEPFLAG.md` | Catalog / ImageServicing bullet: fail-closed → idempotent ok + digest; note ticket **12** wording overturned |
| `docs/design/IMAGESERVICING.md` | `RemoveProvisionedAppx` sketch: same absent posture + KEEPFLAG link |
| `docs/TICKETS.md` | Ticket **12** Done note: absent policy = idempotent ok + digest |

## Non-goals

- Kernel or digest shape changes (already correct)
- New regression test / ADR
- Catalog-id match locality across C# / pwsh (architecture review candidate #2)
- ProvisioningSession safety-net behavior

## Success

An agent reading KEEPFLAG alone would implement today’s AppX remove kernel, not throw-on-missing.
