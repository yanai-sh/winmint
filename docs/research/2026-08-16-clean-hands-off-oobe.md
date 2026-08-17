# Research: clean, modern, hands-off Windows 11 OOBE (WinMint)

**Date:** 2026-08-16  
**Question:** Official way to make a 24H2/25H2 ARM64 install look like ordinary Windows — no OOBE chrome, no cmd flash, no Recovery — without undocumented theater.  
**Method:** Microsoft Learn (hardware customize / manufacture / Win32). Repo + v1 harvest as product evidence only, not OS proof. Learn MCP was unavailable; pages fetched from learn.microsoft.com.

## Recommended path (WinMint invariant)

- **Answer OOBE in unattend, do not skip it.** `oobeSystem` International-Core + Shell-Setup OOBE hide flags + `LocalAccounts` + `AutoLogon`. Microsoft: screens not configured in Unattend still appear. Do not use `SkipMachineOOBE`.
- **Ireland is answers + a registry latch, not a page.** DMA on ⇒ `oobeSystem` International-Core `en-IE` (Input/System/User) with `UILanguage=en-US` (Source ISO pack). `DeviceRegion=68` in specialize. FirstLogon restores Profile visible region. User must never see an Ireland picker.
- **SetupComplete.cmd stays the SYSTEM hook.** `%WINDIR%\Setup\Scripts\SetupComplete.cmd` → `Supervisor.exe --machine-setup` (autologon/Shell verify + reserved-storage DISM). Do not move that DISM to FirstLogon (medium-IL → exit 740). Do not reboot from SetupComplete.
- **Hide the console; keep elevation.** Setup launches `cmd.exe` with a window. Hide the inherited console immediately (`ShowWindow(SW_HIDE)` already in `--machine-setup`). Optional documented follow-up: `wscript` + `WshShell.Run(..., 0, True)` so the child has no window. Parent `cmd` can still flash; `CREATE_NO_WINDOW` can only be set by the *parent* `CreateProcess`, which Setup does not.
- **Shell replacement only after OOBE.** Winlogon Shell = Supervisor then `explorer.exe`. Microsoft: custom shell before OOBE is unsupported (image not deployable; OOBE UI is launched via Explorer). v1: Shell while `OobeInProgress` → Recovery / soft-BSOD.
- **First paint is Supervisor splash, not OEM OOBE.xml.** Inbox Direct2D/GDI. No third-party OOBE skins, no `Oobe.xml` registration pages, no Ngen/unattend theater.
- **SetupComplete must exit 0** unless machine-setup truly failed. Unauthorized `DeviceRegion` during SetupComplete is not a failure (OOBE still holds the key). Non-zero empirically reseals to Recovery even though Learn says Setup does not check the exit code.
- **WinPE LaunchApply is install-time**, not the FirstLogon look. Visible `cmd` follow-up: [#119](https://github.com/yanai-sh/winmint/issues/119).

## What to hide

### SetupComplete console

| Approach | SYSTEM? | Hide? | Product |
| --- | --- | --- | --- |
| Keep `SetupComplete.cmd` → Supervisor; `ShowWindow(SW_HIDE)` first in `--machine-setup` | Yes | After cmd is already visible (flash) | **Keep.** Documented Win32; already wired. |
| `wscript` host + `WshShell.Run(cmd, 0, True)` then `WScript.Quit rc` | Yes (SetupComplete still SYSTEM) | Child hidden; parent cmd may flash | **Optional** if SW_HIDE flash remains. Learn names `cscript`/`wscript` as SetupComplete script hosts. |
| `start /min` | Yes | Minimized taskbar flash | Reject as the hide. |
| Guest `powershell.exe -WindowStyle Hidden` | Yes if spawned from SetupComplete | Hidden, but guest pwsh product runtime | **Reject.** |
| `Register-ScheduledTask` / `schtasks` as the SYSTEM worker | Can be SYSTEM | No console if action is a Windows-subsystem exe | Extra surface, racy vs OOBE. Not the SetupComplete contract. Reject as replacement. |
| `CREATE_NO_WINDOW` (0x08000000) | N/A | Only if *Setup* passed it to `cmd.exe` | Setup does not. A WinMint helper could spawn Supervisor this way; still leaves the SetupComplete `cmd` window unless that helper hides it. |
| Move machine-setup to specialize `RunSynchronous` | Yes (specialize = system context) | No cmd if Path is a Windows-subsystem exe | Too early: `LocalAccounts` may not exist; DeviceRegion Unauthorized is a SetupComplete-time race. DMA `reg add` already lives here — leave it. |
| `FirstLogonCommands` | **No** (first admin logon, elevated user) | Commands run before desktop | Wrong IL for reserved-storage DISM (740). Not a console hide. |

Learn also: SetupComplete is **disabled with OEM product keys** except Enterprise/Server. WinMint retail/generic Pro keys keep the hook. Do not reboot from the script.

### OOBE pages (still the 25H2 contract)

24H2 and 25H2 share a common core (enablement package). Unattend hide flags are the same branch unless a CU says otherwise. No Learn page lists ARM64-only extra pages.

| Page (Win11 flow) | Official hide | WinMint |
| --- | --- | --- |
| Language / region / keyboard | `oobeSystem` International-Core (`InputLocale`, `SystemLocale`, `UILanguage`, `UserLocale`) | DMA on: `en-IE` locales, **`UILanguage=en-US`**. specialize-only is not enough on 25H2 (“Hi there”). |
| Network | `HideWirelessSetupInOOBE=true`; also skipped if wired internet is detected | `true` when `requireWifiDuringOobe=false` (Smoke). Home SKU requires network to finish OOBE — out of Smoke/Pro scope. |
| EULA | `HideEULAPage=true` | Keep. OEM/System Builder note: testing prior to shipment. |
| OEM registration | `HideOEMRegistrationScreen=true` (overrides `Oobe.xml`) | Keep. Do not ship `Oobe.xml` registration chrome. |
| MSA / online sign-in | `HideOnlineAccountScreens=true` + `LocalAccounts` + `AutoLogon` (Win10+: AutoLogon and/or UserAccounts skip account-creation phase) | Keep. No BypassNRO. |
| Express / “Get going fast” | `ProtectYourPC=3` (no default; unset ⇒ page opens) | Keep `3`. |
| Server Administrator password | `HideLocalAccountScreen` — **Server only** | Do not emit on Pro. |
| Network location (Home/Work/Other) | `NetworkLocation` — **deprecated in Windows 10** | Do not emit. |
| Privacy (up to seven settings), “Customize your device”, OneDrive, M365, Hello, “Welcome back” | No dedicated hide flags. Intent/OneDrive/M365/Hello/Welcome-back are MSA-gated. Privacy is listed separately from `ProtectYourPC`. | Local account path skips MSA-gated pages. Privacy may still appear — no documented unattend kill. Do not click Next; do not invent a hide. |
| ZDP / “checking for updates” | None. Critical updates after network; user cannot opt out. | Accept as Windows. Wired+hidden Network still downloads if connected. |
| CloudExperienceHost “Getting ready” / “Just a moment” | None. Progress, not a page. Cloud service pages can appear at any time and may be absent in lab. | Do not fake a skip. Keep OOBE healthy (exit 0, valid UILanguage). |
| Recovery “Why did my PC restart?” | Failure UI, not a hide flag. `SkipUserOOBE` (deprecated) is a known cause. Bad `UILanguage` (e.g. `en-IE` MUI missing) can reseal. Custom shell during OOBE can reseal. | Exit 0 from SetupComplete; `UILanguage=en-US`; Shell only after OOBE. |

## What not to do

- **`SkipMachineOOBE` / `SkipUserOOBE`.** Automate OOBE: don’t use SkipMachineOOBE. Dedicated unattend pages 404; WSIM marks both deprecated. SkipUserOOBE is a documented Recovery trigger in field reports.
- **Guest pwsh product runtime / v1 `WinMint.ps1`.** Inbox `powershell.exe` only for Scoop bootstrap or narrow winget import.
- **WinToys-style clock hacks, Shift+F10, BypassNRO, clicking Next.** Interactive theater. Unattend LocalAccounts is the supported local-account path ([companion](2026-08-09-25h2-local-account-oobe.md)).
- **Custom shell / Shell Launcher / Assigned Access before OOBE.** Learn: unsupported; OOBE UI needs Explorer. Tenure Shell is post-OOBE only.
- **OEM `Oobe.xml` registration, third-party OOBE skins, Ngen “optimizing” theater.** OEM registration is extra chrome. Themes unattend (`UWPAppsUseLightTheme`, `WindowColor`) is the documented visual polish if ever needed — not an OOBE skin.
- **Reboot from SetupComplete.** Puts the machine in a bad state.
- **Fail-closed Machine setup on Unauthorized DeviceRegion.** Exit 1 → Recovery; Smoke cannot drive it.
- **`UILanguage=en-IE`.** Not an installed MUI on the English ISO; OOBE can reseal to Recovery.
- **`FirstLogonCommands` as the SYSTEM/DISM home.** User context; also fires on audit boot unless Reseal Mode=Audit.
- **LabConfig TPM/RAM/SecureBoot bypass as product.** Undocumented. Smoke no-vTPM only.

## DMA Ireland latch vs hide flags

**No conflict** if Ireland is used as *unattend answers*, not as a visible OOBE country page.

- Hide flags do not mention GeoID / DeviceRegion. Network hide is independent of DMA.
- `oobeSystem` International-Core `en-IE` **prevents** the region/language/keyboard panes. That is the opposite of showing Ireland.
- Sticky latch is `HKLM\...\DeviceRegion=68` (specialize `reg add`), not an OOBE screen. Visible locale/Geo/TZ restore is FirstLogon, after OOBE.
- Real conflicts: `UILanguage=en-IE` (Recovery); MachineSetup exit 1 on Unauthorized DeviceRegion (Recovery); specialize-only International-Core (25H2 still shows “Hi there”).

## Visual polish that is still Windows

- Let CloudExperienceHost run its short “Getting ready” if OOBE is otherwise answered. That *is* inbox Windows.
- Supervisor splash after autologon (in-process D2D/GDI), then `explorer.exe`. Quiet period after OOBE is Microsoft’s own “no apps auto-launch” window — do not fight it with extra first-logon UI.
- Documented theme knobs if a later issue wants dark/accent: Shell-Setup `Themes` (`UWPAppsUseLightTheme=false`, `WindowColor`). Optional; not required for hands-off OOBE.
- Reject: OEM registration HTML, custom OOBE backgrounds as product identity, lab `cmd` / Ngen screens.

## Citations

- [Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe) — hide list; **don’t use SkipMachineOOBE**
- [Customize OOBE in Windows 11](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11) — page flow; quiet period
- [OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11) — Network, ZDP, cloud pages, device intent
- [Updates during OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/windows-updates-during-oobe-in-windows-11)
- [OOBE component](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe)
- [HideEULAPage](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideeulapage) · [HideOEMRegistrationScreen](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideoemregistrationscreen) · [HideOnlineAccountScreens](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens) · [HideWirelessSetupInOOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe) · [HideLocalAccountScreen](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidelocalaccountscreen) (Server) · [ProtectYourPC](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc) · [NetworkLocation](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-networklocation) (deprecated)
- [International-Core](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-international-core) · [InputLocale](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-international-core-inputlocale) (oobeSystem **and** specialize)
- [AutoLogon](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon) · [FirstLogonCommands](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-firstlogoncommands) (no custom shell before OOBE)
- [Add a custom script to Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup?view=windows-11) — SetupComplete SYSTEM, wscript, no reboot, OEM-key disable
- [oobeSystem pass](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/oobesystem?view=windows-11) — OOBE before shell
- [Windows Setup states](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-states?view=windows-11) — `IMAGE_STATE_COMPLETE`
- [RunSynchronousCommand](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-deployment-runsynchronous-runsynchronouscommand) — specialize = system context
- [DISM reserved storage](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-storage-reserve?view=windows-11) — `/Online /Set-ReservedStorageState` only
- [CREATE_NO_WINDOW](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags)
- [WshShell.Run](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/windows-scripting/d5fk67ky(v=vs.84)) — `intWindowStyle` 0 = hide (archived WSH, still inbox)
- [Themes / UWPAppsUseLightTheme](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-themes)
- [Oobe.xml settings](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/oobexml-settings?view=windows-11) · [OEM registration pages](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/registration-pages-oobexml-in-windows-11) — reject as product chrome
- [Shell Launcher](https://learn.microsoft.com/en-us/windows/configuration/assigned-access/shell-launcher) — no custom shell before OOBE
- [What’s new 25H2](https://learn.microsoft.com/en-us/windows/whats-new/whats-new-windows-11-version-25h2) · [KB5054156](https://support.microsoft.com/en-us/topic/kb5054156-feature-update-to-windows-11-version-25h2-by-using-an-enablement-package-4d307e2d-3028-4323-bb46-552cff491643)
- [Surface: HideWirelessSetupInOOBE](https://learn.microsoft.com/en-us/surface/customize-the-oobe-for-surface-deployments)

### Repo / v1 (not OS proof)

- `BuildPlan.BuildOobeUnattendXml` already emits the hide set + Ireland oobeSystem International-Core.
- `NativeConsole.Hide` → `ShowWindow(SW_HIDE)` at start of `--machine-setup`.
- [ADR-003](../decisions/ADR-003-dma-interop.md) · [DESIGN §Invariants](../DESIGN.md) · [V1-LESSONS](../design/V1-LESSONS.md) · [25H2 local-account OOBE](2026-08-09-25h2-local-account-oobe.md)
