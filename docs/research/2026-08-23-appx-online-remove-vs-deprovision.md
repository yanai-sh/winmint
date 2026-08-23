# Research: online AppX remove vs deprovision (FirstLogon safety net evidence)

**Date:** 2026-08-23  
**Question:** Smoke intermittently fails: guest Evidence has `removed.appx.online.*` phases but zero `deprovisioned.appx.*` phases, and the assert requires at least one `deprovisioned.appx.*` whenever any `removed.appx.online.*` exists. What do Microsoft's primary sources say each mechanism actually does, and which phase semantics are defensible?  
**Method:** Microsoft Learn only (WinRT API reference, DISM cmdlet/command-line reference, Windows application-management guidance). Repo code/design read for grounding, not as OS proof.

## Findings

### The four mechanisms

| Mechanism | What it does | FU-rehydrate survival | Privilege |
| --- | --- | --- | --- |
| [`PackageManager.RemovePackageAsync(String)`](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.removepackageasync) | Removes the package **for the current user**; payload stays if other users have it. | None by itself — registration removal only. | Medium IL or higher suffices (or AppContainer + `packageManagement`, or publisher match). |
| [`RemovalOptions.RemoveForAllUsers`](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.removaloptions) (1809+) | Removes the package for all users on the device. | None by itself. | Admin in practice (0x80070005 otherwise — [Q&A](https://learn.microsoft.com/en-us/answers/questions/2285955/how-to-uninstall-msix-installed-application-from-a)); staged-for-SYSTEM packages may need SYSTEM. |
| [`PackageManager.DeprovisionPackageForAllUsersAsync(String)`](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.deprovisionpackageforallusersasync) (1809+) | "Deprovisions an app Package so new users on the device will no longer have the app automatically installed." Does **not** remove for existing users. | Yes — deprovisioning creates the Deprovisioned registry key (1803+ behavior below). | **"The caller of this method must have administrator privilege."** (Remarks) |
| [`Remove-AppxProvisionedPackage`](https://learn.microsoft.com/en-us/powershell/module/dism/remove-appxprovisionedpackage) / [DISM `/Remove-ProvisionedAppxPackage`](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-app-package--appx-or-appxbundle--servicing-command-line-options) (offline `/Image` or `/Online`) | Removes provisioning; app not installed for new users; existing accounts keep it. If the app "has not been registered to any user profile" (e.g. unbooted image), it "will remove the package completely." | Yes on 1803+ — removal creates the Deprovisioned key. | Elevated DISM. |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\<PFN>` | Registry key that "tells Windows not to reinstall or update that app the next time Windows is updated." | **This key IS the survival mechanism.** | HKLM write = admin; HKLM read = any IL. |

Canonical page for the registry mechanism: [Keep removed apps from returning during an update](https://learn.microsoft.com/en-us/windows/application-management/remove-provisioned-apps-during-update). Key statements:

- "When you remove a provisioned app, we create a registry key that tells Windows not to reinstall or update that app the next time Windows is updated." Pre-1803 the key was missed when the removal happened offline; "fixed in Windows 10, version 1803" — so on 25H2, offline DISM removal creates the mark too.
- Rehydrate applies to **feature updates only** ("not monthly updates or security-related updates") and **first-party inbox apps only** ("doesn't apply to third-party apps, Microsoft Store apps, or LOB apps").
- Removing a provisioned app while Windows is online "is only removed for *new users* — the user that you signed in as will still have that provisioned app." Deprovision at FirstLogon therefore does not clean the first user; a per-user remove is still needed (the safety net's `RemovePackageAsync` is correct).

### Q2 — Stamping Deprovisioned when the package is already gone

**Yes, explicitly documented.** The same page instructs: "To prevent these apps from reappearing at the next update, manually create a registry key for each app" — via a hand-authored `.reg` of `Deprovisioned\<PFN>` keys, for apps that were **already removed** earlier (that is the whole scenario of the page). Creating the mark for an absent package is Microsoft's own remediation, not a hack. The mark is keyed by **package family name** and is forward-looking: it gates the *next* update, independent of current package presence. (Community/ConfigMgr practice confirms the inverse: deleting the key re-provisions the app at the next FU.)

### Q3 — FirstLogon / medium-IL constraints

The Supervisor Shell at FirstLogon is medium IL (AGENTS/OOBE research: reserved-storage DISM already exits 740 there). Against that:

- `RemovePackageAsync(String)` (current user) — **works at medium IL** (Remarks list "Medium IL, or higher" as sufficient).
- `DeprovisionPackageForAllUsersAsync` — **requires administrator** (Remarks). At medium IL it fails (access denied).
- [`FindProvisionedPackages`](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.findprovisionedpackages) (2004+) — **"must have administrator privilege"** (Remarks). Same for [`FindPackages`](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.findpackages) (all-user queries); only current-user queries ([`FindPackagesForUser("")`](https://learn.microsoft.com/en-us/uwp/api/windows.management.deployment.packagemanager.findpackagesforuser)) are unprivileged.
- HKLM `Deprovisioned` **write** — admin. HKLM **read** — fine at medium IL.

So at medium IL the safety net can genuinely do exactly two things: remove for the current user, and **read-verify** Deprovisioned marks. "Fail-open" that swallows access-denied from the admin-only calls and reports empty results is indistinguishable from "nothing was provisioned" — that is evidence corruption, not resilience.

### Q4 — Official image-builder guidance

[Preinstall apps using DISM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/preinstall-apps-using-dism) / [Sideload apps with DISM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sideload-apps-with-dism-s14): remove provisioned apps **offline** with `/Image /Remove-ProvisionedAppxPackage`; on an unbooted image this removes the package completely. Post-update survival is the Deprovisioned key page above. There is no documented "re-remove at first logon" pattern from Microsoft; the offline remove + registry mark is the complete official mechanism. WinMint's offline-primary + explicit stamp design (DEBLOAT.md, ADR-005 §6) matches the documentation exactly.

### Q5 — "Removed" when nothing was present

Nothing in Microsoft's model treats a no-op as a removal: DISM returns per-package results, `RemovePackageAsync` reports `DeploymentResult` per actual operation, and the documented remediation for "already gone" is *stamp the mark*, not *log a removal*. Emitting `removed.appx.online.{catalogId}` unconditionally is an attempt-log masquerading as an outcome-log. The documented always-true invariant is the other one: **for every PFN on the remove list, a Deprovisioned mark must exist** — present package or not. That is the assertable fact; "removed online" is incidental and usually false on a correctly-serviced image (offline removal already emptied the image, so FirstLogon finds nothing — the normal, healthy case).

## Implications for WinMint

The Smoke failure is by construction, not an OS race: `removed.appx.online.*` is emitted per catalog id even when live find returns nothing, while `deprovisioned.appx.*` is emitted only for PFNs the live finds collected. On a healthy image (offline removal completed), the collected PFN set is empty → phases contradict the assert every time the safety net runs cleanly; "intermittent" is just whether anything was still live.

Recommendations (no code here):

1. **Invert which phase is unconditional.** Always emit `deprovisioned.appx.{pfn}` for the known PFN list (verify/stamp per DEBLOAT.md); emit `removed.appx.online.{catalogId}` **only when at least one package was actually removed or deprovisioned live**. This matches Microsoft's model: the mark is the durable invariant, live removal is the exception.
2. **Source PFNs from the catalog, not from live finds.** The Profile catalog id → PFN mapping is static in-repo knowledge (same mapping the offline stamp already uses). Deriving PFNs from `FindRegistered`/`FindProvisioned` guarantees an empty set exactly when the image is correct, and depends on admin-only queries besides.
3. **Respect medium IL.** At FirstLogon, treat `deprovisioned.appx.{pfn}` as a **read-verify** of the HKLM mark (readable at medium IL). Stamp-on-missing only in a context that can write HKLM (offline Servicing already does; `--machine-setup` SYSTEM hook is the online fallback seam). Do not let the safety net call `DeprovisionPackageForAllUsersAsync` / `FindProvisionedPackages` at medium IL and interpret access-denied as absence.
4. **Fix the Smoke assert to assert the documented invariant:** every remove-list PFN has a Deprovisioned mark in guest evidence (registry read), instead of coupling two phase families with different cardinalities (catalog id vs PFN) and different emission conditions. `removed.appx.online.*` present with zero live packages is then simply impossible, and zero `removed.appx.online.*` becomes the *expected* healthy signal.
5. **Keep the current-user `RemovePackageAsync` step.** It is the only medium-IL-legal remove, and it is genuinely needed: deprovisioning does not remove the app for the already-created first user.

## What NOT to do

- **Do not emit `removed.appx.online.*` for no-ops.** Evidence phases are observations; the documented no-op remediation is a mark, not a removal claim.
- **Do not treat access-denied as "not provisioned."** `FindProvisionedPackages` and `DeprovisionPackageForAllUsersAsync` are admin-only by documentation; swallowing 0x80070005 at medium IL fabricates a clean result.
- **Do not skip the Deprovisioned mark because the package is absent.** The mark is forward-looking (next feature update); Microsoft's own guidance is to create it for already-removed apps.
- **Do not add `RemoveForAllUsers` at FirstLogon.** Admin-required in practice; medium IL fails, and staged-for-SYSTEM packages need SYSTEM.
- **Do not extend Deprovisioned marks to non-inbox apps.** Documented scope is first-party apps shipped with Windows; third-party/Store/LOB rehydrate is not governed by this key.
- **Do not build a per-boot re-deprovision loop.** 1803+ made the registry mark durable across feature updates; live re-assertion is the ADR-007-style anti-pattern the design already rejects.
