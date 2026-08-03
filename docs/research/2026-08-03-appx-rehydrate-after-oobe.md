# Inbox AppX rehydrate after OOBE — research (2026-08-03)

Question: Which Windows 11 inbox / provisioned packages commonly reappear per-user after OOBE despite offline provisioned-package removal, and which live APIs (`PackageManager`, `Remove-AppxPackage`, etc.) are the supported way to remove those rehydrated packages at FirstLogon?

WinMint framing (from product docs, not MS sources): Offline **ImageServicing** mutates WIM via elevated host pwsh (`Remove-AppxProvisionedPackage` / DISM); **ProvisioningSession** (Native AOT C#, no guest pwsh) finishes FirstLogon. Debloat / keep-flag matrix is a deferred vertical. This note informs who owns which failure mode when a keep-flag says “remove.”

Trust tiers used throughout:

- **[primary]** — Microsoft Learn, WinRT API reference, PowerShell DISM/Appx cmdlet docs, Microsoft Inside MSIX engineering blog, MDM Policy CSP.
- **[ms-support / ms-blog]** — Microsoft Support articles, Windows IT Pro Tech Community posts, archived Technet/MSFT employee blogs (still MS-authored; age noted).
- **[community]** — Microsoft Q&A answers, forums, third-party write-ups. Useful for “what people see,” not for supported contracts.
- **[inference]** — mapping primary facts onto WinMint seams; labeled as such.

## Verdict (short)

Microsoft does **not** document a Win11 list of inbox packages that “rehydrate after successful offline deprovision.” What looks like rehydration is usually one of four distinct mechanisms. Keep those separate in the keep-flag matrix.

1. **Normal first-logon registration** of packages that are **still provisioned** (App Readiness / Deployment at logon) — not a bug; offline removal failed or was incomplete. **[primary]**
2. **Feature-update reintroduction** of first-party provisioned apps when `AppxAllUserStore\Deprovisioned` markers are missing — historically worst for offline-only remove; MS documented for Win10 1703/1709 and Deprovisioned keys. **[primary]**
3. **Content Delivery / consumer experiences** silently installing **Store suggested apps** per signed-in user (Candy Crush–class) — not the same as provisioned-package return. **[ms-blog]** / edition caveats on CSP **[primary]**
4. **Policy-time removal at OOBE/sign-in** (Ent/Edu 24H2+) via `RemoveDefaultMicrosoftStorePackages` — the supported “remove and stay removed” path for a curated inbox list; **not** available on Pro (WinMint smoke SKU). **[primary]**

Supported live removal for FirstLogon C#: `Windows.Management.Deployment.PackageManager` — `FindPackages*` / `FindProvisionedPackages`, `RemovePackageAsync` (+ `RemovalOptions.RemoveForAllUsers`), `DeprovisionPackageForAllUsersAsync`. PowerShell `Remove-AppxPackage` / `Remove-AppxProvisionedPackage -Online` are the same deployment surface, unavailable in guest (no pwsh). **[primary]**

---

## What “rehydrate” means (provisioned vs registered)

Microsoft’s terms (**[primary — Preinstalling packaged apps](https://learn.microsoft.com/en-us/windows/msix/desktop/deploy-preinstalled-apps)**; **[primary — Inside MSIX: Per-User vs All Users](https://devblogs.microsoft.com/insidemsix/msix-per-user-vs-all-users/)**):

| Term | Meaning |
|------|---------|
| **Stage** | Package payload stored on the machine (e.g. `%ProgramFiles%\WindowsApps`), no user yet |
| **Provision** | Package **family** added to the machine provisioned list → auto-register for users |
| **Register** | Per-user: app data, FTAs, Start tiles; runs at **user logon** |
| **Deprovision** | Remove family from provisioned list so **new** users do not auto-get it; does not unregister existing users |
| **Remove** | Unregister for a user (or all users with `RemoveForAllUsers`) |

“Rehydrate” is **community slang**, not an MS API term. In practice people use it for:

- First logon after OOBE when App Readiness / Deployment **registers** still-provisioned families (expected: “any provisioned package family the user doesn’t have → register latest staged version”) — **[primary — Inside MSIX](https://devblogs.microsoft.com/insidemsix/msix-per-user-vs-all-users/)**.
- Apps that show up again after an admin thought they removed them offline — often still provisioned, reintroduced by update, or freshly installed by consumer/CDM paths.

`Remove-AppxProvisionedPackage` explicitly: strips auto-registration for **new** users; does **not** remove packages already registered for existing users; if no user has the app yet, staged files can also go away (**[primary — Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage)**; same note on **[primary — Preinstalling packaged apps](https://learn.microsoft.com/en-us/windows/msix/desktop/deploy-preinstalled-apps)**).

**Inference:** For a clean ISO path (no prior users in the image), offline deprovision before first boot is the right place to stop **inbox provisioned** registration. FirstLogon live remove is for (a) packages that still got registered, (b) per-user Store/CDM installs, (c) audit/repair after incomplete offline work — not a substitute for deprovisioning.

---

## Mechanism 1 — Still provisioned → registers at first logon

Documented logon behavior (**[primary — Inside MSIX](https://devblogs.microsoft.com/insidemsix/msix-per-user-vs-all-users/)**):

- Before desktop, Deployment compares the user’s registered packages to staged + **provisioned** families.
- For each provisioned family the user lacks → register highest available package in that family.

So if offline `Remove-AppxProvisionedPackage` did not actually clear the family (wrong name, dependency left, region/OEM stub, script error), the package “comes back” at FirstLogon. That is **registration**, not magic rehydrate.

**WinMint implication:** ImageServicing must verify provisioned inventory after remove (`Get-AppxProvisionedPackage` / DISM equivalent against the mounted image). FirstLogon should treat remaining registration as either keep-flag miss or offline failure, not as a separate “rehydrate class” unless inventory proves deprovision succeeded.

---

## Mechanism 2 — Feature updates re-add first-party provisioned apps

**[primary — Keep removed apps from returning during an update](https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update)** (written for Win10 1703/1709; page still published; 1803 noted as fixing the online case):

- After a **feature** update (not monthly), previously removed **first-party** inbox apps can return.
- Does **not** apply to third-party, Store, or LOB apps per that article.
- Online deprovision creates `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\<PackageFamilyName>` so Windows does not reinstall/update that app on the next feature update.
- Historically, removing while the WIM was mounted **offline** did **not** create that key (device “not online”); 1803 fixed the issue for then-current servicing — the article still documents **manually creating Deprovisioned keys** as the mitigation when keys are missing.
- Online remove without offline: new users lose the app; the signed-in user may still have it (Deprovisioned applies to users created after the key).

**Inference for WinMint:** Offline ImageServicing should both remove provisioned packages **and**, where keep-flag demands “stay gone across feature updates,” stamp matching `Deprovisioned\<PFN>` keys into the offline hive. FirstLogon alone cannot prevent a future feature update from re-provisioning if markers/policy are absent.

Package name inventory in that MS article is **Win10 1709-era** (XboxApp, Zune*, 3DBuilder, …). Treat it as the **Deprovisioned-key pattern**, not as the current Win11 inbox catalog.

---

## Mechanism 3 — Consumer experiences / Content Delivery (suggested Store apps)

Separate from provisioned inbox apps: Windows can **silently install Store apps for the signed-in user** (historically Candy Crush, Twitter, etc.). Michael Niehaus (MSFT) documented this for Win10 1511: those apps are **not** provisioned on the machine, so provisioned-removal scripts miss them; mitigation is turn off consumer experiences / avoid imaging online (**[ms-blog — Seeing extra apps? Turn them off.](https://learn.microsoft.com/en-us/archive/blogs/mniehaus/seeing-extra-apps-turn-them-off)**).

Policy / registry:

| Surface | Detail | Trust |
|---------|--------|-------|
| GPO | Computer Configuration → Administrative Templates → Windows Components → Cloud Content → **Turn off Microsoft consumer experiences** | **[ms-blog]** / CSP mapping |
| Registry | `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent` → `DisableWindowsConsumerFeatures` = `1` | **[ms-blog]**; CSP maps same value |
| MDM CSP | `Experience/AllowWindowsConsumerFeatures` — **editions: Pro ❌; Enterprise/Education/IoT ✅** (**[primary — Policy CSP Experience](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience)**) | **[primary]** |

HKCU `ContentDeliveryManager` values (`SilentInstalledAppsEnabled`, `SoftLandingEnabled`, `ContentDeliveryAllowed`, …) are widely used in **[community]** guides to suppress suggestions; they are per-user, reset-prone, and not a substitute for the HKLM CloudContent policy. Do not treat community CDM DWORD lists as a supported FirstLogon API.

**Inference:** CDM/suggested apps are a **FirstLogon (or offline policy stamp) problem**, not an offline provisioned-package remove miss. On **Pro** (smoke SKU), official CSP does **not** support `AllowWindowsConsumerFeatures`; registry stamping may still be attempted for ISO customization but is **not** edition-guaranteed by the CSP matrix — keep-flag docs should say so.

---

## Mechanism 4 — Policy-based in-box removal (Ent/Edu 24H2+)

**[primary — Policy-based in-box app removal](https://learn.microsoft.com/en-us/windows/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal)**:

- Policy: **Remove default Microsoft Store packages from the system** / `RemoveDefaultMicrosoftStorePackages`.
- **Windows 11 24H2+**, **Enterprise and Education only** (not Pro).
- Runs at **OOBE**, user sign-in after OS upgrade, and sign-in after policy update.
- While selected, removed apps are **blocked from reinstall** (Store/sideload).
- Registry presence: `HKLM\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages`.
- AppxDeployment-Server Operational events after OOBE first logon: **606** success remove, **614** failed remove, **873** system component (not removed), **874** AI component (not removable), **875** malformed PFN.

**[ms-support / ms-blog — Windows IT Pro: Policy-based removal…](https://techcommunity.microsoft.com/blog/windows-itpro-blog/policy-based-removal-of-pre-installed-microsoft-store-apps/4463835)** publishes a curated static list (Ent/Edu), including among others:

Calculator, Camera, Feedback Hub, Microsoft 365 Copilot, Microsoft Clipchamp, Microsoft Copilot (consumer), Microsoft News, Microsoft Photos, Microsoft Solitaire Collection, Microsoft Sticky Notes, Microsoft Teams, Microsoft To Do, MSN Weather, Notepad, Outlook for Windows, Paint, Quick Assist, Snipping Tool, Sound Recorder, Windows Media Player, Windows Terminal, Xbox Gaming App, Xbox Identity Provider, Xbox Speech to Text Overlay, Xbox TCUI.

That list is **“apps Microsoft will remove via policy”**, not **“apps that rehydrate after offline DISM.”** Useful as a Win11-era inventory of removable inbox Store packages for keep-flag design; useless as a Pro smoke guarantee.

---

## What commonly “comes back” — documented vs reported

### Documented (primary / ms-blog)

| Class | Examples (illustrative) | Why it appears after OOBE / later |
|-------|-------------------------|-----------------------------------|
| Still-provisioned inbox | Any family left on provisioned list | Logon auto-register **[primary]** |
| First-party after feature update | Historical 1709 list: Weather, Xbox*, Zune*, Store, Photos, … | Missing `Deprovisioned` markers **[primary]** |
| Consumer Store suggestions | Candy Crush–class (era-dependent) | Per-user silent install; not provisioned **[ms-blog]** |
| Policy-removable inbox (Ent/Edu) | Clipchamp, Teams, Outlook for Windows, Copilot, Xbox*, Photos, … | Appear unless policy/offline remove applied; policy can strip at OOBE **[primary]** / **[ms-blog]** |
| Non-removable | System / AI PFNs | Policy Event 873 / 874 **[primary]** |

### Community reports (not contracts)

**[community]** Microsoft Q&A and forums repeatedly claim Win11 `Remove-AppxPackage -AllUsers` / online deprovision still leaves apps for **new** profiles, Xbox/consumer stacks returning, and kiosk/first-logon reappearance. Treat as symptom reports. Root causes usually map to incomplete deprovision, update reintroduction, or consumer features — not a secret second provisioned store. No MS primary source gives a definitive “these N packages always rehydrate after successful offline remove on Win11.”

**Inference:** Keep-flag matrix should classify packages by **removal surface** (offline deprovision + Deprovisioned key; consumer-policy; live `PackageManager`; Ent/Edu RemoveDefault policy; non-removable), not by a folklore “rehydrate list.”

---

## Supported live APIs for FirstLogon (C#, no guest pwsh)

PowerShell is documentation-equivalent to WinRT deployment; WinMint guest must call WinRT / CsWinRT from Native AOT.

### Inventory

| API / cmdlet | Role | Notes |
|--------------|------|-------|
| `PackageManager.FindPackagesForUser` / `FindPackages` | Per-user / all-user registered packages | Admin for cross-user |
| `PackageManager.FindProvisionedPackages` | Provisioned families still on device | Admin; Win10 2004+ **[primary](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.findprovisionedpackages)** |
| `Get-AppxPackage` / `Get-AppxProvisionedPackage` | Same surfaces via pwsh | Host-only in WinMint |

### Remove / deprovision

| API / cmdlet | Scope | Privilege |
|--------------|-------|-----------|
| `RemovePackageAsync(packageFullName)` | Current user unregister | Medium IL / package mgmt rules **[primary](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.removepackageasync)** |
| `RemovePackageAsync(..., RemovalOptions.RemoveForAllUsers)` | All users | Admin; enum value since 1809 **[primary](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.removaloptions)** |
| `DeprovisionPackageForAllUsersAsync(packageFamilyName)` | Stop auto-install for **new** users | Admin; 1809+ **[primary](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.deprovisionpackageforallusersasync)** |
| `Remove-AppxPackage` [`-AllUsers`] | Same as Remove* | Admin for `-AllUsers` **[primary](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage)** |
| `Remove-AppxProvisionedPackage -Online` | Online deprovision | Admin **[primary](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage)** |

Canonical all-users uninstall order from MSIX engineering (**[primary — Inside MSIX](https://devblogs.microsoft.com/insidemsix/msix-per-user-vs-all-users/)**):

1. **Deprovision** first (`DeprovisionPackageForAllUsersAsync` / `DeprovisionPackageAsync` on newer `PackageDeploymentManager`).
2. Then **Remove** with `RemoveForAllUsers`.

Warning from that post: if Remove runs before Deprovision, another registration can race in between.

Newer Windows App SDK / `Microsoft.Windows.Management.Deployment.PackageDeploymentManager` (`DeprovisionPackageAsync`, `RemovePackageByFamilyNameAsync`) is an alternate surface; classic `Windows.Management.Deployment.PackageManager` remains the Learn-documented baseline for in-box deployment.

**FirstLogon practical pattern (inference):**

1. Enumerate registered packages for the FirstLogon user (`FindPackagesForUser`).
2. For keep-flag “remove”: `RemovePackageAsync(fullName)` for that user (usually enough for smoke’s single local account).
3. If inventory still shows the family **provisioned** (`FindProvisionedPackages`): also `DeprovisionPackageForAllUsersAsync(familyName)` under elevation — otherwise the next profile gets it again.
4. Do **not** shell to `Remove-AppxPackage` in guest.

---

## What cannot be fixed live-only

| Gap | Why live FirstLogon is insufficient |
|-----|-------------------------------------|
| Package still on provisioned list for **future** users | Must deprovision (live admin or offline DISM); per-user Remove alone leaves the provisioned list |
| Feature-update reintroduction of first-party apps | Needs `Deprovisioned` keys and/or Ent/Edu removal policy; post-hoc FirstLogon does not survive the next upgrade by itself **[primary]** |
| Consumer suggested apps on next online session | Prefer HKLM CloudContent / edition-supported policy stamped early; chasing each install at FirstLogon is whack-a-mole **[ms-blog]** + CSP edition limits **[primary]** |
| System / AI non-removable packages | Policy Event 873/874; removal APIs will fail or no-op **[primary]** |
| Ent/Edu `RemoveDefaultMicrosoftStorePackages` on Pro | Unsupported edition; smoke Pro cannot rely on it **[primary]** |
| OEM / region-specific stubs not in provisioned list | May need separate Start layout / OEM channel handling; out of AppX provisioned scope |

Offline ImageServicing remains the **primary** owner for “this family must never auto-register.” ProvisioningSession owns **cleanup of what the logged-on user actually has** plus optional live deprovision if offline missed.

---

## WinMint synthesis (ImageServicing vs ProvisioningSession)

| Concern | ImageServicing (offline) | ProvisioningSession (FirstLogon C#) |
|---------|--------------------------|--------------------------------------|
| Remove provisioned inbox families | **Primary** — `Remove-AppxProvisionedPackage -Path` / DISM; verify empty | Only if still provisioned after boot — `DeprovisionPackageForAllUsersAsync` |
| Stamp `AppxAllUserStore\Deprovisioned\<PFN>` | **Primary** for “survive feature update” keep-flags | Optional repair if missing |
| Consumer experiences off | Stamp `CloudContent\DisableWindowsConsumerFeatures` when Profile asks; document Pro/CSP limits | Per-user CDM tweaks only as last resort (community-tier) |
| Ent/Edu RemoveDefault policy | Possible offline hive stamp for ENT/EDU ISOs only | Not for Pro smoke |
| Remove registered packages for the smoke user | N/A (no user yet) | **Primary** — `PackageManager.RemovePackageAsync` |
| Keep-flag matrix | Declares remove/keep + which mechanism | Executes live subset only |

**Ownership rule (inference):** If keep-flag = remove and the package is a **provisioned inbox** family → ImageServicing must deprovision (and prefer Deprovisioned markers). FirstLogon `RemovePackageAsync` is the safety net for registration that still happened and for **non-provisioned** per-user Store installs — not the primary offline debloat engine.

---

## Sources (keyed)

1. [Preinstalling packaged apps](https://learn.microsoft.com/en-us/windows/msix/desktop/deploy-preinstalled-apps) — stage / register / App Readiness; Remove-ProvisionedAppxPackage semantics. **[primary]**
2. [MSIX Per-User vs All Users (Inside MSIX)](https://devblogs.microsoft.com/insidemsix/msix-per-user-vs-all-users/) — logon registration algorithm; Deprovision-before-Remove; admin requirements. **[primary]**
3. [Keep removed apps from returning during an update](https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update) — Deprovisioned registry; offline vs online; 1709 package name table. **[primary]**
4. [Remove-AppxProvisionedPackage](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage) — offline/online deprovision. **[primary]**
5. [Remove-AppxPackage](https://learn.microsoft.com/en-us/powershell/module/appx/remove-appxpackage) — per-user / `-AllUsers`. **[primary]**
6. [PackageManager.RemovePackageAsync](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.removepackageasync), [RemovalOptions](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.removaloptions), [DeprovisionPackageForAllUsersAsync](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.deprovisionpackageforallusersasync), [FindProvisionedPackages](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.findprovisionedpackages). **[primary]**
7. [Policy-based in-box app removal](https://learn.microsoft.com/en-us/windows/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal) — Ent/Edu 24H2+; OOBE timing; Event IDs 606/614/873/874/875. **[primary]**
8. [Policy CSP Experience — AllowWindowsConsumerFeatures](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience) — Pro excluded from CSP edition matrix. **[primary]**
9. [Seeing extra apps? Turn them off. (Niehaus)](https://learn.microsoft.com/en-us/archive/blogs/mniehaus/seeing-extra-apps-turn-them-off) — Store suggested apps vs provisioned; `DisableWindowsConsumerFeatures`. **[ms-blog]** (2015; mechanism still cited)
10. [Policy-based removal of pre-installed Microsoft Store apps (Windows IT Pro)](https://techcommunity.microsoft.com/blog/windows-itpro-blog/policy-based-removal-of-pre-installed-microsoft-store-apps/4463835) — curated removable inbox list. **[ms-blog]**
