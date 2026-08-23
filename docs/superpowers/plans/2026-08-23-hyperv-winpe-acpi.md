# Hyper-V WinPE ACPI + session land

**Goal:** Land the in-progress Smoke/Apply host work and the Hyper-V WinPE ACPI fix so the next `just smoke-maintainer` does not 0xA5.

**Branch:** `feat/winpe-acpi-hyperv` (do not commit on `main`).

## Global Constraints

- CLI creates intent. Servicing mutates the offline image. Supervisor finishes FirstLogon.
- Elevate only Servicing `pwsh -File`. No v1 `WinMint.ps1`.
- `apply-status.txt` stays ImageServicing (`updated=` / `stage=` / `log=`). `smoke-status.json` stays the S4 waiter projection. Do not invent a fourth status file.
- `install.wim` still gets the full SurfaceMsiSafe set (`system` / `extension` remain valid offline).
- WinPE `boot.wim` subset is storage/USB/HID/net only. Must not include Class `system` or `extension` (Hyper-V ACPI_BIOS_ERROR 0xA5 `_ADR`).
- Do not treat `Get-Date` as elapsed truth (SL7 clock).
- `just check` never Hyper-V and never fetches the Source ISO.
- No new dependencies. `$PSStyle` + `Write-Progress` for host presentation.
- State-changing servicing functions implement `SupportsShouldProcess` — do not `SuppressMessage` that rule.
- Vanilla isolation VM `winmint-vanilla-iso` is operator evidence, not product. Do not wire it into `just smoke`.
- Do not start `just smoke-maintainer` from an agent.

## Isolation evidence (already done)

Vanilla official ISO Gen2 (SB Off, no vTPM, 8 GB, 4 CPU) stayed Running >90s. 18590 0xA5 events were `winmint-smoke` only. Product-key / Setup UI on vanilla is Windows Setup, not a failure.

---

## Task 1: WinPE boot subset

Finish `Get-WinMintBootSetupCriticalClasses` and `Copy-SetupCriticalDriverSubset` in `servicing/Inject-SurfaceDrivers.ps1`.

- Classes: `hdc`, `scsiadapter`, `usb`, `usbdevice`, `hidclass`, `keyboard`, `mouse`, `net`.
- Not: `system`, `extension`.
- `Test-SurfaceOfflineDriverClass` for `install.wim` is unchanged.
- Contract: `tests/contract/Test-SurfaceDrivers.ps1` asserts the boot class list and that `Copy-SetupCriticalDriverSubset` copies a `usb` fixture INF and skips `system` / `extension` fixture INFs (tiny temp INFs with `Class=`).
- One sentence in `docs/design/IMAGESERVICING.md` if not already there.
- Commit only driver-subset files. Subject: `fix(servicing): keep Surface ACPI out of boot.wim`.

Covering tests: `pwsh -NoProfile -File tests/contract/Test-SurfaceDrivers.ps1`

---

## Task 2: Host progress presentation

`tools/host/Write-WinMintHostProgress.ps1`: `Write-WinMintHostPhase`, `Write-WinMintHostProgress` (`$PSStyle.Progress.View = 'Minimal'`), `Format-WinMintHostWatch` (returns a string; no `Clear-Host` inside).

Wire:

- `servicing/Invoke-ServicingPlan.ps1` — phase + progress around each kernel; keep `Tee-Object` and apply-status schema.
- `tools/vm/Watch-SmokeHost.ps1` — dashboard via `Format-WinMintHostWatch`; keep `Get-SmokeWatchVerdict` + `-PriorRunId`.
- `tools/vm/Invoke-Smoke.ps1` — host lines through the helper; wait phase has no fake percent.
- `servicing/Add-QualityUpdates.ps1` — `Write-Output` `Catalog search start` and `Catalog BITS start` in the kernel script body only (never inside functions whose output is assigned).

Contract: `tests/contract/Test-WinMintHostProgress.ps1`. Pin watcher in `tests/contract/Test-SmokeStatus.ps1`.

Commit only progress files. Subject: `feat(host): $PSStyle progress for Apply and Smoke`.

Covering tests: `Test-WinMintHostProgress.ps1`, `Test-SmokeStatus.ps1`

---

## Task 3: Mount recovery + ShouldProcess

`Resolve-WinMintStaleMount`: Invalid / Needs Remount → `/Remount-Image` then discard. Cleanup-Mountpoints does not drop remountable images. Dead-owner discard failure → cleanup, stop orphan DismHost (`SupportsShouldProcess`), settle, remount+discard once.

Replace remaining servicing `PSUseShouldProcessForStateChangingFunctions` suppressions with `SupportsShouldProcess` (or rename if the function does not mutate). `New-WinMintQualityPackageOrder` must stay a resolve (in-memory) if already renamed.

`just discard-stale-mount` recipe body is already `pwsh -Command` (windows-shell) — do not nest another `-Command`.

Contract: `tests/contract/Test-WinMintMountRecovery.ps1`, `Test-QualityCatalog.ps1`, `Test-SourceMediaCache.ps1` as needed.

Commit only mount/quality/cache ShouldProcess files. Subject: `fix(servicing): remount Invalid mounts and implement ShouldProcess`.

Covering tests: `Test-WinMintMountRecovery.ps1` (skip if `Global\WinMint.ImageServicing.v1` is held by a live Apply)

---

## Task 4: Harness leftovers already in tree

Land only these if they are still uncommitted and still correct:

- `WimIndexInfo.TryParseFamily` (Version family, not ServicePack UBR) + HostCompile driver gate.
- Supervisor `ReArmAutoLogonCount` on NeedsReboot.
- Smoke justfile `ISO WORK PROFILE WALL MONITOR STALL` order.
- Guest credential resolve / stall / screenshot / watcher / handoff / preflight already in `tools/vm/` from this session — do not revert.

Do not add features. Commit as `fix(harness): family parse, autologon re-arm, smoke just params` (split if the implementer can do two clean commits).

Covering tests: `just check` if the servicing mutex is free; otherwise C# filter + the contract files touched.

---

## After all tasks

Operator (human, Admin): `Stop-VM winmint-vanilla-iso -TurnOff` then `just smoke-maintainer`. Agents do not start Smoke.
