# Research: Windows 11 25H2 local account + AutoLogon OOBE (vs BypassNRO theater)

**Date:** 2026-08-09  
**Question:** On official consumer Source ISOs for Windows 11 **25H2** (and late **24H2** if identical), with Autounattend that creates a local admin + AutoLogon and sets `HideOnlineAccountScreens=true` (plus related OOBE hides), does Setup/OOBE still force Microsoft-account / network theater that needs Shift+F10 workarounds (`BypassNRO.cmd`, registry hacks, Rufus “remove MSA requirement”)? What must be baked into unattend and/or `boot.wim` for a reliable **local account + autologon** path without human Shift+F10? Also: are `LabConfig` `BypassTPMCheck` / `BypassRAMCheck` / `BypassSecureBootCheck` still relevant on 25H2 for installs without TPM?  
**Method:** Microsoft Learn unattend/OOBE docs, Windows Insider / enablement-package notes, Rufus FAQ + `wue.c` source. Community blogs used only as low-confidence corroboration. Repo code cited as “what WinMint emits,” not as proof of OS behavior.

## Summary verdict

**For a typical Pro consumer ISO with a correctly applied `oobeSystem` Autounattend that creates `UserAccounts/LocalAccounts` + `AutoLogon` + `HideOnlineAccountScreens=true`: BypassNRO / Shift+F10 MSA theater is not required.** Microsoft documents that path as the supported way to automate OOBE and skip interactive account creation. Rufus’s own author distinguishes the same: BypassNRO restores the *interactive* “offline local account” button when the network is down; creating a local account in unattend skips MSA even with network up.

**Interactive consumer OOBE without that unattend (or with unattend that Setup never processes) still forces MSA/network theater on 24H2/25H2.** Microsoft is actively removing field workarounds (`OOBE\BYPASSNRO`, `ms-cxh:localonly`, etc.) in Insider flights; that campaign targets the *human Shift+F10* path, not the documented unattend contract — but it raises the cost of depending on BypassNRO as a product seam.

**What must be baked for WinMint’s reliable path (no human Shift+F10):**

| Bake | Why |
| --- | --- |
| `oobeSystem` unattend that Setup/`oobe.exe` actually loads (`Autounattend.xml` root and/or `%WINDIR%\Panther\unattend.xml` / WinMint `OobeUnattend.xml` → Panther) | Without a processed answer file, you fall into interactive MSA theater. |
| `Microsoft-Windows-Shell-Setup` / `UserAccounts` / `LocalAccounts` (local admin) | Creates the account; Learn + AutoLogon notes: account-creation OOBE phase is skipped when unattend creates a user. |
| `AutoLogon` (`Enabled`, `Username`, `Password`, `LogonCount`) | Documents skip of user-creation phase when configured; WinMint FirstLogon depends on it. |
| `OOBE/HideOnlineAccountScreens=true` | Documented hide of online sign-in page. |
| `OOBE/HideWirelessSetupInOOBE` per profile (`requireWifiDuringOobe`) | Hides Network page when true; does **not** replace LocalAccounts. |
| Other WinMint OOBE hides (`HideEULAPage`, `HideOEMRegistrationScreen`, `ProtectYourPC`) | Deterministic OOBE; Learn lists them under automate-OOBE. |
| **Engine that honors Autounattend** — WinPE apply (product default) or `setup.exe /legacy` (legacy lane) | WinMint’s own design: ConX Setup on 24H2/25H2 may only partially honor Autounattend on serviced media. |
| **`LabConfig` triple** when the target has no TPM / fails Setup hardware checks (Hyper-V Smoke without vTPM) | Still the de-facto Setup/first-boot bypass; **not** needed on metal with TPM 2.0 + Secure Boot meeting requirements. **Not** a substitute for LocalAccounts. |
| **Not required for the Autounattend path:** `BypassNRO` registry / `BypassNRO.cmd` / Rufus “Remove requirement for an online Microsoft account” alone | Those restore interactive offline-account UX; Rufus still uses them for that UX, and separately uses LocalAccounts when you ask it to create a user. |

**25H2 vs late 24H2:** Microsoft states 24H2 and 25H2 share a common core (enablement package). Treat OOBE/unattend contracts as the same branch unless a specific cumulative/Insider build notes otherwise. Interactive-bypass removals land via Insider/CUs on that shared branch — re-validate on the exact ISO build WinMint pins, not on the marketing version string alone.

## Evidence table

| Claim | Verdict | Confidence | Source |
| --- | --- | --- | --- |
| `HideOnlineAccountScreens=true` hides OOBE online sign-in | **Documented** | High | [HideOnlineAccountScreens](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens) |
| `HideWirelessSetupInOOBE=true` hides Network page (wired internet can also skip it) | **Documented** | High | [HideWirelessSetupInOOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe) |
| Automate OOBE via `UserAccounts` + OOBE hide settings; do **not** use `SkipMachineOOBE` | **Documented** | High | [Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe) |
| `LocalAccounts` creates local users in `oobeSystem` | **Documented** | High | [LocalAccounts](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts) |
| `AutoLogon` + / or `UserAccounts` skip OOBE user-account creation phase (Win10+ note) | **Documented** | High | [AutoLogon](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon) |
| Interactive OOBE still pushes MSA + internet; Microsoft removing “local-only” field mechanisms | **First-party (Insider)** | Medium–High for interactive path; **does not** say unattend LocalAccounts is removed | [Insider Build 26220.6772](https://blogs.windows.com/windows-insider/2025/10/06/announcing-windows-11-insider-preview-build-26220-6772-dev-channel/) (“Local-only commands removal”); secondary reporting [The Verge](https://www.theverge.com/news/793579/microsoft-windows-11-local-account-bypass-workaround-changes) |
| 24H2 and 25H2 share identical system-file core (eKB) | **Documented** | High | [KB5054156](https://support.microsoft.com/en-us/topic/kb5054156-feature-update-to-windows-11-version-25h2-by-using-an-enablement-package-4d307e2d-3028-4323-bb46-552cff491643); [What's new 25H2](https://learn.microsoft.com/en-us/windows/whats-new/whats-new-windows-11-version-25h2) |
| Rufus “Remove requirement for an online Microsoft account” = `BypassNRO` DWORD under `HKLM\Software\Microsoft\Windows\CurrentVersion\OOBE` (specialize RunSynchronous), restoring offline interactive local-account path; **network must be unavailable** for that UX | **First-party Rufus** | High | [Rufus FAQ](https://github.com/pbatard/rufus/wiki/FAQ#Help_I_dont_see_the_option_to_bypass_the_need_for_a_Microsoft_account_with_Windows_11); [`wue.c`](https://github.com/pbatard/rufus/blob/master/src/wue.c) (`UNATTEND_NO_ONLINE_ACCOUNT` → `reg add … BypassNRO`); maintainer [issue #2844](https://github.com/pbatard/rufus/issues/2844), [#2188](https://github.com/pbatard/rufus/issues/2188) |
| Rufus: creating a **local account in unattend** can skip MSA even with network connected (separate from BypassNRO) | **First-party Rufus source comment** | Medium–High | [`wue.c`](https://github.com/pbatard/rufus/blob/master/src/wue.c) comment at local-account emission (~L347–348) |
| Rufus TPM/Secure Boot/RAM option = `LabConfig` `BypassTPMCheck` / `BypassSecureBootCheck` / `BypassRAMCheck` = 1 (boot.wim registry and/or windowsPE RunSynchronous) | **First-party Rufus** | High | [`wue.c`](https://github.com/pbatard/rufus/blob/master/src/wue.c) (`bypass_name[]`, LabConfig RegCreateKey); FAQ TPM section |
| `LabConfig` bypasses remain effective for Setup “This PC can’t run Windows 11” on no-TPM VMs/hardware through 24H2/25H2-era media | **Community + tooling consensus; not a Learn product contract** | Medium | Rufus still ships the same keys; long-standing community procedure (e.g. [BleepingComputer 2021 LabConfig discovery writeup](https://www.bleepingcomputer.com/news/microsoft/how-to-bypass-the-windows-11-tpm-20-requirement/)); no Microsoft Learn page found documenting LabConfig as supported |
| ConX Setup may partially ignore Autounattend on custom 24H2/25H2 media → need `/legacy` or non-Setup apply | **Repo design claim** (motivates WinMint engine); corroboration outside repo is mixed | Medium (for WinMint product risk) | [workstation-compiler spec](../specs/2026-08-05-workstation-compiler-winpe-apply.md); `Inject-Unattend.ps1` comment |
| Pure blog “25H2 always needs Shift+F10 / BypassNRO even with Autounattend” | **Overstated / conflates interactive vs unattend paths** | Low | Many SEO guides; prefer Learn + Rufus source |

## What WinMint already covers

Repo context only — proves product intent, not OS truth:

| Mechanism | Where |
| --- | --- |
| `HideOnlineAccountScreens=true` | `BuildPlan` Autounattend / OobeUnattend template |
| `HideWirelessSetupInOOBE` from `account.requireWifiDuringOobe` (default show Network; Smoke hides) | `BuildPlan` + `Profile` |
| `LocalAccounts` + `AutoLogon` (`localAutoLogon` only) | `BuildPlan` |
| `HideEULAPage`, `HideOEMRegistrationScreen`, `ProtectYourPC=3` | `BuildPlan` |
| LabConfig TPM/RAM/SecureBoot = 1 | Legacy: `Inject-Unattend.ps1` → `boot.wim` SYSTEM; WinPE apply: `Patch-BootWimApply.ps1` stamps applied-image SYSTEM hive after DISM apply |
| Avoid ConX Autounattend fragility | Default **WinPE apply** (no `setup.exe`); legacy lane `winpeshl.ini` → `setup.exe /legacy` |
| **No** `BypassNRO` | By design (product does not emit it) |

## Gap candidates

1. **Prove on pinned 25H2 ARM64 Pro ISO** that Panther `unattend.xml` from WinPE apply still skips MSA with NIC up (Smoke already targets this class of install; keep evidence on the exact build pin).  
2. **Do not add BypassNRO unless Autounattend stops being honored** — it is an interactive-path patch under Insider attack; LocalAccounts is the durable seam.  
3. **Watch Insider/CU notes** that broaden “local-only commands removal” into breaking `HideOnlineAccountScreens` / unattend LocalAccounts (not stated as of the 26220.6772 blog text; still a monitoring item).  
4. **LabConfig:** keep for no-vTPM Hyper-V / unsupported hardware; optional omit on metal with TPM+Secure Boot if you want fewer undocumented stamps. WinPE apply already skips Setup’s hardware gate; LabConfig on applied SYSTEM remains for any first-boot/setup residual checks WinMint cares about.  
5. **`requireWifiDuringOobe=true`:** Network page can still appear; that is intentional and separate from MSA. If Network + MSA reappear together on a future build despite LocalAccounts, treat as engine/unattend-delivery failure first.  
6. **Home vs Pro:** Pro “Domain join instead” is an interactive escape hatch only; WinMint’s path should remain unattend LocalAccounts (edition-agnostic in Learn).  
7. **S Mode:** Rufus FAQ — S Mode forces MSA and conflicts with local-account unattend; out of scope for WinMint Pro Smoke but worth knowing.

## Confidence

| Area | Level | Notes |
| --- | --- | --- |
| Documented unattend settings exist and are the right bake list | **High** | Learn still lists them; Automate OOBE warns against `SkipMachineOOBE`. |
| Autounattend LocalAccounts + hides ⇒ no Shift+F10 on typical Pro ISO when answer file is processed | **Medium–High** | Strong docs + Rufus source agreement; not re-labbed in this research session on a fresh 25H2 ISO. |
| Interactive BypassNRO theater still exists / is being killed on the shared 24H2–25H2 branch | **High** for “Microsoft is removing field bypasses”; **Medium** for which exact retail CU has which hole closed. |
| LabConfig still works for no-TPM Setup on 25H2 media | **Medium** | Still in Rufus; widely used; **unsupported / undocumented** by Microsoft. |
| ConX ignores Autounattend enough to need `/legacy` or WinPE apply | **Medium** | Primary driver is WinMint design/spec + servicing comments; treat as product risk mitigation already in place. |

## Sources

### Primary / first-party

- [HideOnlineAccountScreens](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens)  
- [HideWirelessSetupInOOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe)  
- [OOBE component](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe)  
- [Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)  
- [AutoLogon](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon)  
- [LocalAccounts](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts)  
- [What’s new in Windows 11, version 25H2](https://learn.microsoft.com/en-us/windows/whats-new/whats-new-windows-11-version-25h2)  
- [KB5054156 — 25H2 enablement package](https://support.microsoft.com/en-us/topic/kb5054156-feature-update-to-windows-11-version-25h2-by-using-an-enablement-package-4d307e2d-3028-4323-bb46-552cff491643)  
- [Windows Insider Preview Build 26220.6772](https://blogs.windows.com/windows-insider/2025/10/06/announcing-windows-11-insider-preview-build-26220-6772-dev-channel/)  
- [Rufus FAQ (MSA + TPM sections)](https://github.com/pbatard/rufus/wiki/FAQ)  
- [Rufus `src/wue.c`](https://github.com/pbatard/rufus/blob/master/src/wue.c)  

### Secondary (low confidence / reporting)

- [The Verge — local account bypass changes](https://www.theverge.com/news/793579/microsoft-windows-11-local-account-bypass-workaround-changes)  
- Rufus issues [#2188](https://github.com/pbatard/rufus/issues/2188), [#2810](https://github.com/pbatard/rufus/issues/2810), [#2844](https://github.com/pbatard/rufus/issues/2844)  

### Repo context (not OS proof)

- `src/WinMint.Orchestrator/BuildPlan.cs` (unattend template)  
- `servicing/Inject-Unattend.ps1`, `servicing/Patch-BootWimApply.ps1`  
- [docs/specs/2026-08-05-workstation-compiler-winpe-apply.md](../specs/2026-08-05-workstation-compiler-winpe-apply.md)  
- [docs/design/SPLASH.md](../design/SPLASH.md) (LabConfig lesson)
