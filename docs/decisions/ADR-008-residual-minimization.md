# ADR-008: Residual minimization after successful provisioning

**Status:** Accepted  
**Date:** 2026-08-05  
**Related:** [ADR-007](ADR-007-cdm-not-primary.md), [PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md), [IMAGESERVICING](../design/IMAGESERVICING.md)

### Context

WinMint is a **Windows ISO builder**, not a distro. A finished install should look like user-authored Windows, not a branded runtime that permanently owns `C:\Windows\WinMint\` or leaves Setup hooks in place. Today Machine setup / Shell tenure correctly stage Supervisor, `bundle.json`, `jobs.json`, and `SetupComplete.cmd` for FirstLogon — but those paths previously survived after unlock.

Separately: CDM / leftover-junk *product* cleanup ([ADR-007](ADR-007-cdm-not-primary.md)) is a different problem. Residual minimization is **self-erasure of WinMint’s own staged brand surface**, not Windows inbox rehydrate policy.

### Decision

1. After **successful** Shell `Complete` (Winlogon Shell already restored to `explorer.exe`, Complete evidence written): best-effort **self-erase**:
   - Clear Winlogon AutoAdminLogon / DefaultPassword (and related autologon stamps used for Local+autoLogon).
   - Delete `%WINDIR%\Setup\Scripts\SetupComplete.cmd` if present.
   - Delete `%WINDIR%\WinMint\` (Supervisor, bundle, jobs) when the filesystem allows (running exe may remain locked — best-effort).
2. **Failed** Shell unlock paths do **not** erase payload (diagnosis).
3. **`%ProgramData%\WinMint\`** (logs, evidence, checkpoint tenure) may remain so Smoke/harness can harvest; harness may wipe after copy-off. Not deleted in-process on Complete.
4. Keep-flag **Deprovisioned** hive keys and Profile remove-list effects are Windows image state — **not** WinMint brand residue.
5. Reject dual `$OEM$\$$\Setup\Scripts` staging as a reliability default (extra branded copies). Reject CTT-style guest PowerShell FirstLogon CDM spray as product default ([ADR-007](ADR-007-cdm-not-primary.md)).

### Consequences

- Production wires `IResidueCleaner` on Shell Complete only.
- Smoke docs note ProgramData evidence remains until harness harvest.
- Metal Release installs should not retain durable `C:\Windows\WinMint\` or SetupComplete after green FirstLogon (best-effort when files are unlocked).
