# ADR-009: Product-constant offline policies (not AppX recommended set)

**Status:** Accepted — concrete id list is **code/default**, not DESIGN invariant wording. Living bar: [DESIGN](../DESIGN.md#invariants) item 10. Implementation: `ProductPosture`.

### Context

WinMint always removes OneDrive and applies Edge debloat / companion-app / WPBT stamps derived from CTT winutil essentials — separate from the Debloat **AppX** remove-list. ADR-005 forbids a silent product-default **AppX recommended set inside Profile JSON**; that lock must not be read as “no product posture at all.”

Separately: Edge Copilot is not part of winutil EdgeDebloat (17 telemetry/shopping keys) and remains available. The Microsoft Copilot AppX and gaming AppX families are product-required removals. Brave debloat applies only when the user selected Brave in packages.

CDM spray remains out as primary ([ADR-007](ADR-007-cdm-not-primary.md)); HKLM CloudContent policy stamps are product-constant FU posture, not per-user CDM.

### Decision

1. **Product posture** (always stamped / always jobbed; not Profile toggles) lives in `ProductPosture`:
   - Offline: winutil **EdgeDebloat** (17 HKLM Edge/EdgeUpdate policies).
   - Offline: OneDrive `DisableFileSyncNGSC=1`.
   - Offline: `PreventDeviceMetadataFromNetwork=1`.
   - Offline: `DisableWpbtExecution=1` (SYSTEM ControlSet001).
   - Offline: FU-durable consumer policies — `CloudContent\DisableWindowsConsumerFeatures=1`, `CloudContent\DisableSoftLanding=1`, `WindowsStore\AutoDownload=2` (suggested Store apps off; **not** a Windows Update block).
   - FirstLogon: `onedrive.uninstall` (`OneDriveSetup.exe /uninstall`, best-effort).
   - FirstLogon: `reservedStorage.disable` (`dism /Online /Set-ReservedStorageState /State:Disabled`).
   - FirstLogon: winget **`Git.MinGit`**, **`Microsoft.PowerShell`**, **`Microsoft.WindowsTerminal`**, **`Microsoft.Coreutils`**, and **`Nilesoft.Shell`** (unioned into effective winget set; Profile may list them too; no opt-out).
   - FirstLogon: scoop shell-core toolbox (**`starship`**, **`fzf`**, **`fd`**, **`ripgrep`**, **`bat`**, **`zoxide`**, **`jq`**, **`chezmoi`**) via `scoop.batch`; then **`shell.stamp`** (Cascadia NF + one-shot skel + light chezmoi seed). (`ls`/`ll`/`la` prefer Coreutils when present — not eza; eza has no Windows ARM64 binary.)
   - AppX: `Microsoft.Copilot`, `Microsoft.GamingApp`, `Microsoft.Xbox.TCUI`, `Microsoft.XboxGamingOverlay`, and `Microsoft.XboxSpeechToTextOverlay` are unioned into the effective remove-list; no opt-out.
2. **Optional Profile `policies`** on `winmint.profile/v1` (omit = defaults):
   - `dohProvider` (`cloudflare` \| `google` \| `quad9` \| null) — optional FirstLogon `doh.set` job; Smoke default off.
   - Legacy `keepCopilot` in JSON is ignored (not serialized).
3. **Derived (no Profile flag):** if `packages.winget` contains `Brave.Brave`, stamp winutil BraveDebloat (12 HKLM BraveSoftware policies).
4. **Opcode:** `StampOfflinePolicies` after Debloat removes, before `StagePayload`. Param-only `policySpecs`; Plan owns branching.
5. This does **not** make CDM primary and does **not** put AppX preset names in Profile JSON.

### Consequences

- Edge Copilot remains available; AppX Copilot/gaming always stripped.
- Digests `policy.<family>.<Name>=<data>` under `logs/digests.json`.
- Store MSIX host pwsh fails closed on Apply (`servicing.pwsh.storeMsix`).
