# OOBE Wi‑Fi + local account via Unattend — research (2026-08-04)

Question: For Windows 11 Pro ARM64 (25H2-class images), what is the **supported** Unattend / OOBE pattern that (1) creates a local user at ISO build time, (2) never shows MSA sign-in, (3) **does** show the Network / Wi‑Fi page so the user supplies credentials interactively, (4) AutoLogons that local user after OOBE for WinMint Supervisor-as-Shell — preferring official Microsoft mechanisms and labeling community registry/BypassNRO paths as fallbacks with longevity risk?

WinMint framing (from product docs, not Microsoft sources): **BuildPlan** emits `Autounattend` / unattend into the ISO; **ImageServicing** injects it offline; **ProvisioningSession** (Native AOT C#) runs as Winlogon Shell after FirstLogon AutoLogon. Smoke Profile today sets `HideOnlineAccountScreens` **and** `HideWirelessSetupInOOBE` both `true` (fully headless OOBE). Metal / “user must join Wi‑Fi” is a different contract: show Network, still suppress MSA. Account mode remains `localAutoLogon`.

Trust tiers used throughout:

- **[primary]** — Microsoft Learn Unattend reference, Automate OOBE / Automate Windows Setup, Customize OOBE (Win11), OOBE screen details.
- **[ms-blog]** — Windows Insider Blog / Microsoft-authored deployment posts.
- **[community]** — Microsoft Q&A, reputable deployment blogs (e.g. Oofhours). Useful for “what people see,” not supported contracts.
- **[product]** — WinMint design / current answer-file emit.
- **[inference]** — mapping primary facts onto WinMint seams; labeled as such.

## Verdict (short)

The **official** surface already separates the two levers WinMint needs:

| Goal | Official setting | Pass |
|------|------------------|------|
| Create local user (skip interactive account creation) | `UserAccounts/LocalAccounts` (+ password) | `oobeSystem` |
| Hide MSA / online sign-in UI | `OOBE/HideOnlineAccountScreens` = `true` | `oobeSystem` |
| **Show** Network / Wi‑Fi page | `OOBE/HideWirelessSetupInOOBE` = `false` **or omit** (default false) | `oobeSystem` |
| AutoLogon after OOBE | `AutoLogon` (`Enabled`, `Username`, `Password`, `LogonCount`) | `oobeSystem` |
| Skip Express settings page | `OOBE/ProtectYourPC` = `3` | `oobeSystem` |

Microsoft documents Network **before** account screens in the Win11 OOBE flow, and documents that `UserAccounts` / `AutoLogon` skip the account-creation phase. There is **no** Learn page that forbids `HideOnlineAccountScreens=true` together with showing wireless. **[inference]** That combination is the recommended product pattern for metal; Smoke may keep wireless hidden because Hyper‑V often already has wired connectivity (Network page skipped anyway when Windows decides the PC is online).

Do **not** use BypassNRO / LabConfig / SkipMachineOOBE for this contract: BypassNRO exists to *avoid* network+MSA for local-account DIY installs (opposite of “must connect Wi‑Fi”); LabConfig is hardware-check evasion; SkipMachineOOBE is explicitly warned against. **[primary]** / **[ms-blog]**

---

## 1. Framing — WinMint desired contract

- Local account (`username` + password) is authored in Profile and stamped into Unattend at ISO build — **not** created by interactive OOBE account UI.
- MSA / “sign in with Microsoft” pages must not appear during OOBE once the device is online.
- User **must** see and complete the Network page (Wi‑Fi credentials are **not** in the Profile/ISO).
- After OOBE completes, AutoLogon as that local user so Supervisor can run as Shell (FirstLogon tenure).
- Prefer Learn Unattend / Automate OOBE; registry and Shift+F10 tricks only as documented fallbacks with risk notes.

**Current emit [product]:** `BuildPlan` emits local `UserAccounts`, `AutoLogon`, `HideOnlineAccountScreens=true`, and `HideWirelessSetupInOOBE` from Profile `account.requireWifiDuringOobe` (default **true** → wireless hide `false`; Smoke samples set `false` → wireless hide `true`). See §7–§8.

---

## 2. Official Unattend surface

### Automate OOBE (catalog)

Microsoft’s **Automate OOBE** page lists the supported Unattend knobs for skipping OOBE UI, including International-Core locales, `UserAccounts`, the `OOBE` hide-* settings, and `ProtectYourPC`. Screens **not** configured in Unattend still appear. **[primary — Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)**

| Setting | Pass | Role for this contract |
|---------|------|------------------------|
| [`UserAccounts`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts) / [`LocalAccounts`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts) | `oobeSystem` | Create local account(s) + password during install |
| [`HideOnlineAccountScreens`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens) | `oobeSystem` | Hide online / MSA sign-in page |
| [`HideWirelessSetupInOOBE`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe) | `oobeSystem` | Hide **or show** Network page |
| [`ProtectYourPC`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc) | `oobeSystem` | Express settings: `3` = turn off / skip “Get going fast” |
| [`HideEULAPage`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideeulapage) | `oobeSystem` | Hide EULA (OEM/System Builder: **testing prior to shipment** only) |
| [`HideOEMRegistrationScreen`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideoemregistrationscreen) | `oobeSystem` | Hide OEM registration |
| [`HideLocalAccountScreen`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidelocalaccountscreen) | `oobeSystem` | **Server editions only** — Administrator password screen; irrelevant for Win11 Pro desktop |
| [`AutoLogon`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon) | `oobeSystem` (also audit/specialize) | Automatic logon after Setup; credentials cleared from answer file when Setup completes |

Parent component: [`Microsoft-Windows-Shell-Setup` / `OOBE`](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe). Setup automation overview (answer-file search, caching, sensitive-data clearing): **[primary — Windows Setup Automation Overview](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview?view=windows-11)**. Setup page automation (language, product key, EULA, disk): **[primary — Automate Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11)**.

### Setting semantics (primary)

**`HideOnlineAccountScreens`** — “whether the user will be required to sign-in during OOBE”; primarily for enterprises that do not want email-as-username. Sign-in page appears only if the user has an internet connection. `true` = hide; `false` = default (do not hide). **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens)**

**`HideWirelessSetupInOOBE`** — hides the **Network** screen during Windows Welcome when `true`. Network is shown when the setting is **not** `true` **and** Windows cannot determine that the computer is connected to the internet. Despite the name, the Network page is **skipped if the computer has a wired connection to the internet**. Default = `false` (do not hide). **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe)**

**`ProtectYourPC`** — Express settings bundle (speech/inking personalization, location/ad ID, malicious web content, suggested open networks, problem reports). Values `1`/`2` turn Express on; `3` turns Express **off**. No default: if unset, the “Get going fast” page opens. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc)**

**`UserAccounts` / `LocalAccounts`** — create local accounts during installation (`oobeSystem` / `auditSystem`). **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts)**

**`AutoLogon`** — automatic logon account; credentials deleted from the unattended answer file after Windows Setup completes. **Important (Win10+):** configuring `AutoLogon` causes the OS to **skip the user account creation phase during OOBE**; additionally, account creation is skipped in all Windows versions when at least one user is created via `UserAccounts` in the same unattend. Microsoft recommends creating at least one Administrators-group user via Unattend when AutoLogon targets a built-in/existing account. Disable AutoLogon before shipping to end customers. **`LogonCount` is mandatory** when AutoLogon is used. **[primary — AutoLogon](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon)**; same note in **[primary — changed answer-file settings (Win10)](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/changed-answer-file-settings-for-previous-windows10-builds)**

**`LogonCount` known issue:** Windows may add 1 to `LogonCount` when the value is > 0; to get *N* automated logons, set `LogonCount` to *N−1*. Exactly one automated logon needs a FirstLogonCommands workaround to zero `AutoLogonCount`. **[primary — LogonCount](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon-logoncount)**

**Do not use `SkipMachineOOBE`:** Automate OOBE warns explicitly: “Don't use the SkipMachineOOBE setting to automate OOBE. Instead, use the above unattend settings.” **[primary — Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)**

### OOBE page order (Win11 OEM docs)

Non-exhaustive, generally expected order (**[primary — Customize OOBE in Windows 11](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)**; details **[primary — OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11)**):

1. Language → Region → Keyboard  
2. **Connect to a network** (after keyboard)  
3. Critical patches / ZDP / driver downloads  
4. EULA  
5. “Get the latest from Windows”  
6. **Sign in / create local or Microsoft account (MSA)**  
7. Welcome back (MSA restore)  
8. **Windows Hello setup**  
9. Privacy settings  
10. Customize your device / OneDrive / M365 / OEM registration (many are cloud-service pages)

**Home SKU note:** “connecting to a network is required to complete OOBE on Home SKUs”; users do not have the option to continue without connecting. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)** · **[primary — OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11)**

WinMint Smoke SKU is **Pro** ([ADR-002](../decisions/ADR-002-v2-architecture.md)); Home’s forced-network rule is still useful context for any future Home Profile, but Pro is the prove-out target.

**Inference — pages remaining after Wi‑Fi when local account is already in Unattend:** Network (if shown) → critical updates → EULA (unless hidden) → privacy/Express (unless `ProtectYourPC` set) → possible Hello / cloud pages. Account-creation / MSA sign-in should be skipped when `UserAccounts` and/or `AutoLogon` + `HideOnlineAccountScreens` are set per AutoLogon Important note and Automate OOBE. Cloud-service pages can still appear and may vary by flight — Microsoft says testing may not always see them. **[primary — OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11)**

### Showing wireless while hiding MSA — documented?

Microsoft documents the two settings **independently**. There is no Learn sentence that says “if wireless is shown, online account screens cannot be hidden,” nor the reverse. Automate OOBE lists both under the same `OOBE` hide group. **[primary — Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)**

**Inference:** Official docs **allow** the pattern `HideOnlineAccountScreens=true` + `HideWirelessSetupInOOBE=false`. Whether every Win11 22H2+/24H2/25H2 consumer build honors that on Pro ARM64 when online is a **prove-out** (see §9), not a documented prohibition. Community reports of MSA leakage usually involve missing `UserAccounts`, wrong settings, Sysprep without accounts, or interactive Home paths — not a published “wireless implies MSA” rule. **[community — e.g. Q&A 24H2 “Who’s going to use this device”](https://learn.microsoft.com/en-us/answers/questions/2105735/win11-24h2-sysprep-oobe-cant-suppress-whos-going-t)** (misuses `HideLocalAccountScreen` on desktop; answers push `HideOnlineAccountScreens` + local accounts — treat as community signal only).

---

## 3. Recommended answer-file pattern

### XML sketch (`oobeSystem`, ARM64)

Rationale: create local admin; hide MSA; **show** Network; skip Express; AutoLogon for Supervisor. Keep DMA/locale/`windowsPE` blocks as WinMint already emits (Ireland latch when DMA on) — omitted here for focus.

```xml
<settings pass="oobeSystem">
  <component name="Microsoft-Windows-Shell-Setup"
             processorArchitecture="arm64"
             publicKeyToken="31bf3856ad364e35"
             language="neutral"
             versionScope="nonSxS"
             xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
    <OOBE>
      <HideEULAPage>true</HideEULAPage>
      <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
      <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
      <!-- Show Network: false or omit. Do NOT set true for metal Wi‑Fi contract. -->
      <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
      <ProtectYourPC>3</ProtectYourPC>
    </OOBE>
    <UserAccounts>
      <LocalAccounts>
        <LocalAccount wcm:action="add">
          <Name>winmint</Name>
          <Group>Administrators</Group>
          <Password>
            <Value><!-- Profile password --></Value>
            <PlainText>true</PlainText>
          </Password>
        </LocalAccount>
      </LocalAccounts>
    </UserAccounts>
    <AutoLogon>
      <Enabled>true</Enabled>
      <Username>winmint</Username>
      <Password>
        <Value><!-- same password --></Value>
        <PlainText>true</PlainText>
      </Password>
      <!-- LogonCount: must be set; account for +1 quirk if counting precisely -->
      <LogonCount>5</LogonCount>
    </AutoLogon>
  </component>
</settings>
```

**Rationale (tied to primary):**

1. **`LocalAccounts`** — supported creation of the local user; with AutoLogon, skips interactive account-creation phase. **[primary — AutoLogon Important](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon)**
2. **`HideOnlineAccountScreens=true`** — official hide for online sign-in when internet is present. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens)**
3. **`HideWirelessSetupInOOBE=false`** — Network page eligible when Windows does not already detect internet; wired Smoke VMs may still skip the page. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe)**
4. **`ProtectYourPC=3`** — avoids interactive Express settings page. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc)**
5. **`AutoLogon`** — post-OOBE logon for Shell Supervisor; credentials scrubbed from answer file after Setup. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon)**
6. **Do not add `SkipMachineOOBE` / `SkipUserOOBE`.** **[primary — Automate OOBE warning](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)**
7. **Do not rely on `HideLocalAccountScreen`** for Win11 Pro — Server-only. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidelocalaccountscreen)**

**Smoke variant [inference]:** keep `HideWirelessSetupInOOBE=true` (or leave false and rely on wired skip) so Hyper‑V acceptance stays non-interactive. Prefer a Profile flag (e.g. `account.requireWifiDuringOobe` / invert of hide-wireless) rather than two frozen answer-file shapes.

**Password hygiene [primary]:** answer files cache under `%WINDIR%\Panther`; Setup clears sensitive data per pass, but Microsoft still warns about passwords remaining on disk between reboots — delete cached answer files before customer delivery. **[primary — Automation Overview, Sensitive Data](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview?view=windows-11)** WinMint Machine setup already restamps/wipes autologon secrets in design ([PROVISIONINGSESSION](../design/PROVISIONINGSESSION.md)).

---

## 4. Known failure modes / MSA leakage when online

| Failure mode | What happens | Trust |
|--------------|--------------|-------|
| No `UserAccounts` / no AutoLogon account | OOBE still offers account creation; online → MSA push | **[primary — AutoLogon Important](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon)**; flow **[primary — Customize OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)** |
| `HideOnlineAccountScreens` omitted / `false` | With internet, sign-in page can appear | **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens)** |
| Expecting wireless hide to suppress MSA | Orthogonal settings — hiding Wi‑Fi does not create a local user | **[inference]** from independent docs |
| Wired internet already up | Network page **skipped** even when `HideWirelessSetupInOOBE=false` | **[primary — HideWirelessSetupInOOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe)** |
| Home SKU without network | OOBE cannot complete without connectivity | **[primary — Customize OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)** |
| Cloud-service pages after account | OneDrive / M365 / intent pages may still appear when online | **[primary — OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11)** |
| Sysprep generalize without local account in unattend | Community reports of “Who’s going to use this device?” on 24H2 | **[community — Q&A](https://learn.microsoft.com/en-us/answers/questions/2105735/win11-24h2-sysprep-oobe-cant-suppress-whos-going-t)** |
| AutoLogon as `defaultuser0` / stamp races | FirstLogon never starts / Soft-BSOD-class hangs | **[product — V1-LESSONS](../design/V1-LESSONS.md)** — harvest: never defaultuser0+AutoAdminLogon |
| `LogonCount` off-by-one | Fewer/more AutoLogons than expected | **[primary — LogonCount](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon-logoncount)** |
| Interactive PIN / Hello after MSA path | PIN setup associated with MSA OOBE; local Unattend path may still show Hello | Flow lists Hello after account **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)**; no Unattend hide in Automate OOBE table |

---

## 5. Fallbacks — registry / BypassNRO / LabConfig

| Mechanism | What it does | Official? | Longevity / risk on 25H2-class |
|-----------|--------------|-----------|--------------------------------|
| Unattend `HideOnlineAccountScreens` / `UserAccounts` / `AutoLogon` / wireless hide flag | Supported OOBE automation | **Yes [primary]** | Prefer forever — this is the product path |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE\HideOnlineAccountScreens` DWORD live during OOBE | Same semantic as Unattend, applied late via Shift+F10 | **Mirrors Unattend name**; live edit is **[community]** operational practice, not a deployment guide | Better than BypassNRO if Unattend failed to apply; still not a substitute for baking Unattend |
| `BypassNRO` DWORD under `...\OOBE` + reboot | Historically enabled “I don’t have internet” / limited setup → local account **without** network | **Not** in Automate OOBE / Unattend reference. Microsoft **removed `bypassnro.cmd`** from Insider builds “to enhance security and user experience” and to ensure users exit setup **with internet connectivity and a Microsoft Account** **[ms-blog — Insider Build 26120.3653](https://blogs.windows.com/windows-insider/2025/03/28/announcing-windows-11-insider-preview-build-26120-3653-beta-channel/)** | **High risk / wrong tool for WinMint.** Opposes “must show Wi‑Fi.” Script already removed; registry may be weakened further. Do not bake into ISO |
| `oobe\BypassNRO` / `BypassNRO.cmd` | Wrapper that set BypassNRO + reboot | Same as above — removed from builds per Insider blog | Dead on current media; do not depend |
| `start ms-cxh:localonly` and similar Shift+F10 tricks | Force local-account UI mid-OOBE | **[community]** only | Breaks across flights; not a Profile contract |
| `HKLM\SYSTEM\Setup\LabConfig` (`BypassTPMCheck`, `BypassSecureBootCheck`, …) | Skip **hardware requirement** checks during Setup | **Not** a supported production Unattend feature; discussed as lab/unsupported by deployment authors **[community — Oofhours](https://oofhours.com/2022/01/22/you-can-bypass-the-windows-11-hardware-requirement-check-but-its-not-a-good-idea/)** | Irrelevant to MSA/Wi‑Fi; unsupported configs may lose update eligibility messaging. Out of scope for WinMint Pro-on-capable-hardware |
| `SkipMachineOOBE` / `SkipUserOOBE` in answer file | Old “skip OOBE” switches | Explicitly **don’t use** **[primary — Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)** | Deprecated / harmful; can break OOBE completion |

**Inference:** WinMint should treat BypassNRO-class tricks as **anti-patterns** for the stated metal contract (require Wi‑Fi, hide MSA via Unattend). If MSA still appears with the recommended Unattend on a specific 25H2 ARM64 build, escalate as a prove-out failure / Microsoft behavior change — do not silently inject BypassNRO into ImageServicing.

---

## 6. Hello / PIN expectations

- Win11 Customize OOBE lists **Windows Hello setup** after the account step. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)**
- Automate OOBE’s supported hide list does **not** include a “HideWindowsHello” / “SkipPIN” Unattend setting. **[primary — Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe)**
- Enterprise **Windows Hello for Business** is controlled via GPO / Intune / [`PassportForWork` CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/passportforwork-csp) — that is **WHfB policy**, not a consumer OOBE Unattend skip for convenience PIN. **[primary — PassportForWork CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/passportforwork-csp)**
- Interactive MSA OOBE commonly leads into PIN; community Q&A workarounds again point at BypassNRO / local-account paths — **[community]**, not a supported Unattend API.

**Inference for WinMint:** Expect Hello/PIN to be **best-effort skip** when using local Unattend + `HideOnlineAccountScreens` (no MSA enrollment). There is **no** official Unattend guarantee to suppress Hello on Pro consumer images. Smoke should fail-fast / evidence if Hello blocks AutoLogon→Shell; metal Profile docs should say “Hello may still appear; no official Unattend suppress.” Do not invent registry Hello kills as product policy without a separate research ticket.

---

## 7. Implications for WinMint

| Concern | Implication |
|---------|-------------|
| **Smoke vs metal** | Smoke (Hyper‑V, often wired): Network page often auto-skipped; `HideWirelessSetupInOOBE=true` is fine for non-interactive acceptance. Metal Wi‑Fi contract: emit `false` / omit. Prefer **Profile flag**, not a second frozen schema. |
| **AutoLogon** | Keep Unattend AutoLogon for first Shell entry; Machine setup verifies/restamps and wipes secrets per design. Account for `LogonCount` +1 quirk if counting reboots precisely. |
| **Shell timing** | AutoLogon must target the Unattend local user — never `defaultuser0`. OOBE must fully finish before Shell tenure; stall fail-fast remains required ([V1-LESSONS](../design/V1-LESSONS.md)). |
| **DMA / locales** | Unrelated to MSA/Wi‑Fi; keep Ireland latch when DMA enabled ([ADR-003](../decisions/ADR-003-dma-interop.md)). |
| **Pro vs Home** | Prove on **Pro**. Home forces network to complete OOBE; local-account Unattend still recommended if Home is ever supported, but MSA pressure is historically stronger on interactive Home. |
| **HideEULAPage** | Allowed in testing; OEM doc says OEMs/System Builders only for testing prior to shipment. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideeulapage)** Acceptable for Smoke ISOs; note before any “ship to end users” Profile. |
| **Post-OOBE quiet period** | After OOBE, Windows has a quiet period (no auto-launch UI); Start may open. **[primary — Customize OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)** Supervisor-as-Shell should still own the session before Explorer unlock — product timing, not Unattend. |
| **ZDP during OOBE** | Connecting to Wi‑Fi can trigger critical update download + reboot mid-OOBE; pages may repeat if network was lost. **[primary](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11)** · **[primary — OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11)** Harness timeouts must tolerate this on metal. |

---

## 8. Recommended implementation choice (ranked)

1. **Official Unattend pattern (recommended)** — `LocalAccounts` + `HideOnlineAccountScreens=true` + `HideWirelessSetupInOOBE=false` (metal) / `true` (Smoke optional) + `ProtectYourPC=3` + `AutoLogon` with mandatory `LogonCount`. Profile-drive the wireless hide bit. **Why:** All settings are on Automate OOBE / Unattend reference; matches desired contract without opposing Microsoft’s “exit with internet” direction.

2. **Same Unattend + evidence-gated Smoke prove-out** — ship (1) only after ARM64 Pro 25H2 evidence that MSA does not reappear when Network is shown and online. **Why:** Docs allow the combo; builds can still grow cloud pages; prove-out is cheaper than inventing registry.

3. **Live `HideOnlineAccountScreens` registry during OOBE (fallback only)** — if Unattend failed to apply. **Why:** Same named setting as official Unattend; still not a substitute for fixing InjectUnattend.

4. **BypassNRO / LabConfig / SkipMachineOOBE / ms-cxh tricks** — **reject for this feature.** Wrong semantics (skip network), explicitly discouraged or removed, high 25H2 longevity risk.

---

## 9. Open prove-outs needed on 25H2 ARM64

Run on **Windows 11 Pro ARM64**, 25H2-class media, with DMA Profile as product requires. Capture screenshots / harness evidence (not just exit codes).

1. **Metal Wi‑Fi matrix:** `HideWirelessSetupInOOBE=false`, Wi‑Fi adapter present, no wired link → Network page appears → user joins SSID → **no** MSA page → OOBE completes → AutoLogon as Profile user → Supervisor Shell starts.
2. **Smoke wired matrix:** External/Default Switch with internet → confirm Network skipped (wired) even with hide=false; MSA still hidden; acceptance green.
3. **MSA leakage soak:** After Wi‑Fi connect, walk remaining pages (privacy, Hello, cloud). Record any “Sign in with Microsoft” / “Who’s going to use this PC” / forced MSA.
4. **Hello/PIN:** Note whether Hello appears on local-account path; whether it is dismissible; whether it blocks AutoLogon.
5. **ZDP reboot:** On a device that downloads OOBE critical updates after Wi‑Fi, confirm AutoLogon + Shell still recover (LogonCount budget).
6. **Negative control:** Temporarily omit `HideOnlineAccountScreens` with internet → confirm MSA appears (proves the lever is doing work).
7. **Home (optional, out of Smoke SKU):** only if product ever claims Home — network required without BypassNRO.

---

## Primary links (bookmark set)

1. [Automate OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/automate-oobe) — supported Unattend catalog; SkipMachineOOBE warning. **[primary]**
2. [Automate Windows Setup](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11) — Setup UI page automation. **[primary]**
3. [Windows Setup Automation Overview](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-setup-automation-overview?view=windows-11) — answer-file search, Panther cache, secrets. **[primary]**
4. [Customize OOBE (Windows 11)](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/customize-oobe-in-windows-11) — page order; Home network requirement; Hello. **[primary]**
5. [OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11) — Network placement; ZDP; cloud pages. **[primary]**
6. [HideOnlineAccountScreens](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hideonlineaccountscreens) · [HideWirelessSetupInOOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-hidewirelesssetupinoobe) · [ProtectYourPC](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe-protectyourpc) · [OOBE parent](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-oobe) **[primary]**
7. [UserAccounts](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts) · [LocalAccounts](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-useraccounts-localaccounts) · [AutoLogon](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon) · [LogonCount](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-autologon-logoncount) **[primary]**
8. [Changed answer-file settings (Win10)](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/changed-answer-file-settings-for-previous-windows10-builds) — AutoLogon skips account creation. **[primary]**
9. [Insider Build 26120.3653](https://blogs.windows.com/windows-insider/2025/03/28/announcing-windows-11-insider-preview-build-26120-3653-beta-channel/) — removes `bypassnro.cmd`; intent = internet + MSA. **[ms-blog]**
10. [PassportForWork CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/passportforwork-csp) — WHfB policy surface (not consumer OOBE Unattend). **[primary]**

Community (labeled, not contract):

- [Q&A: 24H2 Sysprep “Who’s going to use this device?”](https://learn.microsoft.com/en-us/answers/questions/2105735/win11-24h2-sysprep-oobe-cant-suppress-whos-going-t) **[community]**
- [Oofhours: LabConfig / hardware bypass caveats](https://oofhours.com/2022/01/22/you-can-bypass-the-windows-11-hardware-requirement-check-but-its-not-a-good-idea/) **[community]**
