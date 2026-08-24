# ADR-008: Residual self-erase

**Status:** Accepted · **Date:** 2026-08-05

### Context

WinMint compiles an ISO; it is not a distro. After a green FirstLogon the guest should look like the user’s Windows, not a branded runtime. That is separate from CDM/inbox rehydrate ([ADR-007](ADR-007-cdm-not-primary.md)).

### Rejected

Leaving `%WINDIR%\WinMint\` and SetupComplete in place after green Complete. Dual `$OEM$\$$\Setup\Scripts` as the reliability default. Erasing payload on **failed** unlock (need diagnosis). Treating Deprovisioned hive keys as WinMint brand residue.

### Decision

After successful Shell Complete (Explorer restored, Complete evidence written): best-effort erase of WinMint’s own tenure surface (autologon stamps, SetupComplete, `%WINDIR%\WinMint\`).

`%ProgramData%\WinMint\` may remain for evidence harvest. Failed unlock does not erase.

Paths and cleaner wiring live in code.

### Review trigger

A green install still presents as a WinMint runtime, or erase starts destroying diagnosis on failed unlock.
