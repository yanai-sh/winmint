# FirstLogon chrome + hypervisor WSL mock

Harvest of **winmint_v1** FirstLogon desktop + Hyper-V Smoke WSL skip. v2 seams only (ADR-002). No v1 pwsh forest, no Profile `diagnostics.*`.

**Source of truth:** sibling `winmint_v1` (ideas only). Do not invent pin/remove lists in this spec — copy the v1 policy cited below.

**Approved 2026-08-24** (chat): product constants; WSL mock on any hypervisor *guest*; fail-open baseline chrome; green is the v1 desktop.

## Problem

v2 FirstLogon is a slice of v1. Missing vs `winmint_v1`: bloom SPI, `ConfigureStartPins` / `LayoutModification` replace, quiet taskbar DWords, hypervisor WSL skip, v1 default AppX groups (sl7 JSON is thinner and removes Clock). Hyper-V Smoke fail-closes on `wsl --install` and unlocks to inbox Start / dusk water.

v1 Smoke set `diagnostics.wslRuntimeValidation=skip` and mocked Terminal profiles. That flag must not return on `winmint.profile/v1`.

## Decision

Split by existing modules:

| Seam | Work |
|------|------|
| ImageServicing `Stage-Payload.ps1` | Copy `payload/media/wallpaper/bloom.jpg` → mounted `Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg` (JPEG bytes; harvest from v1 `assets/runtime/wallpaper/img0.jpg`) |
| Supervisor `workstation.quiet` | Keep dark/DND; add remaining v1 quiet DWords (search box, Task View, Copilot, chat, Recycle Bin hide, CDM suggestion spray) |
| Supervisor `wsl.platform` / `wsl.*` | If hypervisor **guest**: no `wsl.exe` install; `jobs.wsl.platform.mocked`; remaining WSL jobs skip (`jobs.wsl.*.mocked`); best-effort mock Terminal profiles |
| Supervisor `debloat.appx.safetyNet` | Live remove leftover families; `removed.appx.online.{id}` when touched; mark-only is not success |
| Supervisor `shell.chrome` (new job, after winget/scoop/`shell.stamp`/WSL/native audit) | Bloom SPI; Start/taskbar replace; write `winmint.shell.chrome/v1` |
| Fail-open | After Failed evidence, before unlock: baseline chrome (bloom + Start/taskbar replace; omit missing app pins). Not green. |

Selected winget/scoop apps (sl7: Zen, Cursor) must be **installed** on Complete. Chrome pins them; it does not soft-skip a Profile-selected app. Edge stays off the taskbar when a non-Edge browser is selected (v1 rule).

## Rejected

- Profile `diagnostics.wslRuntimeValidation` or an appearance JSON block
- `HypervisorPresent` as the guest test (true on SL7 metal because it is a Hyper-V *host*)
- Test-lane-only WSL mock (a Release ISO in a VM would still call `wsl --install`)
- Stuffing chrome into `workstation.quiet` (runs before packages; cannot pin Zen/Cursor)
- Offline Default User `LayoutModification` as the only Start/taskbar control
- Copying v1 `FirstLogon_ShellPins.json` shape (v2 writes `winmint.shell.chrome/v1` instead)
- Cursors, XDG, Windhawk, AppearanceOnce Profile field (later)
- Treating `deprovisioned.appx.*` marks as proof the package is gone (this Smoke still had Solitaire / Clock / Xbox.TCUI)
- v1 `candidateOnly` for `consumerThirdParty` / `oemConsumer` (Spotify, Netflix, LinkedIn, OEM welcome apps, …) and omitting WhatsApp — v2 default-removes those groups plus WhatsApp. Still honor v1 `preserve` and `systemExemptPrefixes`.

## Hypervisor guest

Guest only:

- Hyper-V: manufacturer contains Microsoft **and** model is `Virtual Machine`, **or** `HKLM\SOFTWARE\Microsoft\Virtual Machine\Guest` exists
- Also: VMware, VirtualBox, QEMU, KVM, Xen in manufacturer/model
- Probe throws → not a guest (real WSL). Metal stays correct.

Any guest mocks WSL even if nested virtualization is exposed.

Tenure flag: once `wsl.platform` is mocked, later `Wsl` / from-file jobs skip. They must not fail-close.

Terminal mock failure is ignored.

## `shell.chrome`

Guest wallpaper path (v1): `C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg`.

Start replace baseline (v1 JSON): Explorer, Settings (`windows.immutablecontrolpanel`), Terminal. Then sl7 Zen + Cursor links.

Taskbar replace baseline (v1 XML): Explorer + Terminal. Then Zen + Cursor. `pinEdgeToTaskbar=false` when Zen is selected.

Write pins while Supervisor is still Winlogon Shell. Explorer inherits at unlock.

Bloom missing on Complete → fail `shell.chrome` (servicing forgot the file). Fail-open: skip wallpaper, still replace Start/taskbar. Start/taskbar ACL failure: fail the job on Complete; best-effort on fail-open. Profile-selected app missing on disk → fail Complete (`jobs.failed` / chrome), not a quiet omit.

Supervisor writes `winmint.shell.chrome/v1` (wallpaper path, start pin ids, taskbar pin ids, quiet DWords applied). Smoke pulls it like `native-packages.json`.

## AppX safety net

`deprovisioned.appx.*` is only the FU-survival mark. Complete must actually remove leftovers the offline pass missed: `RemovePackage` + `DeprovisionPackageForAllUsers` when the family is still registered or provisioned, and emit `removed.appx.online.{catalogId}` for each touch. Vacuous skip only when a live query shows the family absent (provisioned + current-user). This guest still had Solitaire, Clock, and Xbox.TCUI — that is a fail.

## Desktop expectations (green) — harvest v1

A green FirstLogon is the v1 desktop. Cite these files; do not invent a second list.

| Surface | v1 source |
|---------|-----------|
| Bloom + SPI + Recycle Bin hide + search box | `src/runtime/setup/FirstLogon.Desktop.ps1` (`Set-WinMintFirstLogonDesktopDefaults`) |
| Quiet taskbar DWords | same file (`Set-WinMintFirstLogonQuietUxDefaults`) |
| Start + taskbar pin policy | same file (`Set-WinMintFirstLogonStartPins`, `Set-WinMintFirstLogonTaskbarPins`) |
| SL7 pin fixture | `tests/contract/Test-VmShellDesktopEvidence.ps1` |
| WSL skip + mock Terminal | `tests/profiles/hyper-v-sl7-smoke-arm64.json` (`diagnostics.wslRuntimeValidation=skip`); `Modules/Wsl.ps1` |
| Default AppX remove | v1 `config/appx-removal.json` **all four groups**: `coreMicrosoft`, `communication`, `gaming`, `consumerThirdParty`, `oemConsumer` (v1 had the last two `candidateOnly`; v2 makes them default) |
| Must keep | same file `preserve` + `systemExemptPrefixes` (Store, Camera, **Clock**, Notepad, Photos, Paint, Edge/WebView2; HP/Dell/Lenovo *support* tools — not Welcome/Companion) |
| sl7 Phone Link | v1 smoke `features.phoneLink: true` → keep `Microsoft.YourPhone` / CrossDevice (`optInKeep.phoneLink`) |
| WhatsApp | **v2 add** to consumer strip: `5319275A.WhatsAppDesktop` (not in v1 catalog) |
| Outlook/Chat/DevHome rehydrate | `SetupComplete/OobeRehydration.ps1` + UScheduler `OutlookUpdate` |
| Wallpaper asset | `assets/runtime/wallpaper/img0.jpg` → `WinMint-Bloom.jpg` |

**Wallpaper.** `C:\Windows\Web\Wallpaper\Windows\WinMint-Bloom.jpg` (v1 path). Inbox dusk water is a fail.

**Taskbar chrome (v1 DWords).** `SearchboxTaskbarMode=0`, `ShowTaskViewButton=0`, `TaskbarDa=0`, `TaskbarMn=0`, `ShowCopilotButton=0`. Inbox Search / Task View / Widgets / Copilot / Chat is a fail.

**Taskbar pins (v1 replace).** `PinListPlacement=Replace`: Explorer + Terminal, then sl7 selected apps (Zen, Cursor). v1 SL7 fixture: `taskbarAppIds = zen-browser, cursor`, `pinEdgeToTaskbar = false`. Store / Edge / Xbox / Outlook on the taskbar is a fail.

**Start pins (v1 replace).** `ConfigureStartPins` `pinnedList`: Explorer (`Microsoft.Windows.Explorer`), Settings (`windows.immutablecontrolpanel`), Terminal (`Microsoft.WindowsTerminal_8wekyb3d8bbwe!App`), then Zen + Cursor `.lnk`. Get Started / Xbox / Solitaire / Outlook / WhatsApp / LinkedIn / Store still pinned is a fail of replace **and** (for WhatsApp/LinkedIn) of default remove.

**Third-party + OEM (v2 default remove).** Copy v1 `consumerThirdParty` + `oemConsumer` prefixes into `ProvisionedAppxCatalog` + `ProductPosture.AppxIds` (Spotify, Netflix, TikTok, Disney, Amazon, Facebook, Instagram, LinkedIn, Twitter, McAfee, Norton, ExpressVPN, OEM Welcome/Companion/Digital Delivery, …). Add WhatsApp (`5319275A.WhatsAppDesktop`). Prefix match like v1 (one catalog id covers publisher variants). Vacuous skip if that ISO never provisioned them; presence after FirstLogon is a fail.

**Still do not remove** v1 `preserve` / `systemExemptPrefixes` (Clock, Store, Camera, Photos, Paint, Notepad, Edge/WebView2, HP/Dell/Lenovo *support* apps). sl7 keeps Phone Link.

**Bloat (clean system).** Absent for first-logon user + provisioned store: all five v1 groups above + WhatsApp. Today's `samples/sl7.profile.json` is thinner and wrongly removes Clock — drop `WindowsAlarms` / `YourPhone` from authored sl7; posture carries the default strip. No preset name in JSON (ADR-005).

**Packages (v1 + v2 posture).** Product constants already in `ProductPosture.WingetIds` / Scoop (MinGit, pwsh, Terminal, Coreutils, Nilesoft, Starship, …) plus sl7 `packages.winget` Cursor + Zen. Complete fails if any selected or constant id is missing. Pins require the `.lnk`/exe v1 resolved.

**WSL.** Same as v1 Smoke skip: mock platform + mock Terminal profile named `Fedora` for `FedoraLinux`. No live distro. Bare metal: real install.

## Smoke (Hyper-V is always a guest)

Green still requires outcome `Complete`, `jobs.ok`, `oobe.dismiss`, explorer handoff.

Also require:

- Phases: `jobs.workstation.quiet`, `jobs.wsl.platform.mocked`, `shell.chrome`
- `guest/native-packages.json` when the Profile had winget (already `-ExpectNativePackageAudit`)
- `guest/shell-chrome.json` (`winmint.shell.chrome/v1`) matching the pin/wallpaper expectations above
- Profile remove-list: each id has `removed.appx.online.{id}` **or** apply digest `removed.appx.{id}=absent` **and** chrome/safety-net live verify did not see the family

Do not require a live Fedora distro. Fail-open chrome is not green.

## Tests

- Fake guest vs SL7-host (Hyper-V role + desktop model): guest mocks; host installs
- Guest path must not invoke `wsl.exe --install`
- `Assert-SmokeEvidence` fixture includes `mocked`, `shell.chrome`, `shell-chrome.json` pin lists, and native audit
- Safety net: leftover registered family → `removed.appx.online.*` and gone; mark-only is not enough
- Payload/contract: bloom source exists; `Stage-Payload` copies it (fail Apply if missing)

## Out of scope

This Smoke VM already Failed. Fix is a new Apply/Smoke after implement, not in-guest repair.
