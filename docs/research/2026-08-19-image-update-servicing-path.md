# Research: first-session quality-update wait (Smoke / workstation image)

**Date:** 2026-08-19  
**Question:** For a Hyper-V Smoke / workstation image, what is the recommended way to avoid a 30+ minute first-session “Just a moment” / quality-update wait: (A) offline DISM `/Add-Package` (SSU then LCU) into `install.wim`, (B) standard online Windows Update / OOBE ZDP on first boot (current Smoke: guest on Default Switch NAT), or (C) building media from UUP instead of a retail/business Source ISO?  
**Method:** Primary pages fetched from learn.microsoft.com and Microsoft Support KBs / Windows IT Pro Blog that own the feature. Context7 had no Windows hardware-manufacture library; Microsoft Learn MCP was not in this session. Community UUP converters are labeled non-primary and are not cited as OS proof. Repo + ADRs are product constraints, not OS proof.

## Recommended path (differs by goal)

The answer is **not one letter for every WinMint run**. Microsoft splits “critical ZDP after network” from “quality update during OOBE when the image is behind.” WinMint already splits **Smoke iteration** from **Primary/SL7 wipe currency**. Those two splits must stay aligned.

| Goal | Path | Why |
| --- | --- | --- |
| **(a) Smoke iteration speed** | **B, with a reasonably current user-supplied Source ISO.** Do **not** slipstream an LCU on every Test Apply. | Smoke already needs guest NAT for winget (`Default Switch`). After network, ZDP cannot be opted out. Test lane is `compression=fast` + `cleanup=skip` so host Apply stays cheap. Baking SSU/LCU + optional `ResetBase` into every Smoke ISO moves the 30+ minutes onto the **host** and still leaves first-boot pending work. |
| **(b) Primary / SL7 wipe image currency** | **Current official Source ISO, then A if that ISO is behind.** Never C as a product source. | Microsoft’s documented “image is current before first boot” path is Catalog packages + DISM (or a newer official ISO from VS/VL channels). Release lane already runs `/StartComponentCleanup /ResetBase`. Operator supplies the ISO; WinMint fetches same-train Catalog `.msu` during Apply ([ADR-013](../decisions/ADR-013-catalog-lcu.md)). |
| **(c) First-session spinner** | **A shrinks the 30+ minute *quality* wait. B’s ZDP still runs (typically smaller) even if the WIM already has the current LCU.** | Learn: critical ZDP starts after network and cannot be opted out. The 30+ minute OOBE install is the *other* clause — a newer Windows than the image, depending on OS build. A current LCU in the WIM does **not** skip ZDP; it typically leaves a smaller remaining payload. “Just a moment” is also CloudExperienceHost progress / a Shell hang — not a hide flag. |

**Product change:** ImageServicing opcode `AddQualityUpdates` ([ADR-013](../decisions/ADR-013-catalog-lcu.md), kernel `servicing/Add-QualityUpdates.ps1`). Catalog combined LCU on **staged** media when UBR is behind; Prepared media stays an unpatched Source-ISO tree. Guest ZDP after NAT remains.

## Verdict table (A / B / C)

| Path | Microsoft role | Smoke | Primary / SL7 | Product |
| --- | --- | --- | --- | --- |
| **A — Offline DISM `/Add-Package`** | Documented OEM/IT image servicing: mount `install.wim`, add Catalog `.msu`/`.cab` in order, cleanup, export. | **Accept when WIM UBR is behind** (same host Apply as Release). Test still uses `cleanup=skip` (no `/ResetBase`). | **Accept.** ImageServicing downloads ARM64 Catalog `.msu` when behind; fail closed if Catalog/DISM cannot complete. | `AddQualityUpdates` + `PatchBootWimApply` package-then-LaunchApply. Mutates **staged media** only. |
| **B — Online WU / OOBE ZDP** | Documented OOBE behavior after network. Critical ZDP: no opt-out. Quality updates during OOBE: 30+ minutes when the image is behind. | **Keep.** Default Switch NAT is required for winget prove-out. Do not unplug the guest to skip ZDP. | **Accept remaining ZDP** even on a current WIM. Do not block WU as a Primary strategy (posture does not). | Current Smoke. |
| **C — UUP dump / community ISO converters** | Official UUP is the **Windows Update publishing/scan/download model** (client, WSUS, ConfigMgr). It is not a Microsoft ISO factory. Community dump converters reconstruct media from UUP payloads. | **Reject** as Source ISO. | **Reject** as Source ISO. | **Reject.** [CONTEXT](../../CONTEXT.md) already: avoid “golden ISO, UUP default source.” [ADR-001](../decisions/ADR-001-source-iso-legal.md): no silent Windows download, including UUP as a public product path. |

## 1. Offline DISM (path A)

### `/Add-Package` order — SSU before LCU

Microsoft’s manufacture CLI: packages on one command line are installed **in the order listed**. `/Add-Package` does **not** fully check dependencies; if a package has prerequisites, install them first (or use an `offlineServicing` answer file). From Windows 11 21H2 onward, `/Add-Package` accepts `.msu` on offline **and** online images.

Combined payload (February 2021+): the monthly LCU **includes** the latest SSU for Windows Update / WSUS / Catalog. That does **not** mean “add the combined `.msu` in any order and forget SSU” for **custom offline media**. Microsoft Support’s owned slipstream warning: custom ISO/WIM that slipstreams the LCU **without** first slipstreaming a current SSU can produce a broken image (Edge Legacy removed and not replaced). Workaround they own: extract the SSU cab from the combined package, `/Add-Package` the SSU **first**, then the LCU.

```text
expand Windows10.0-KBxxxxxxx-x64.msu /f:Windows10.0-KBxxxxxxx-x64.cab
expand Windows10.0-KBxxxxxxx-x64.cab /f:*
# then DISM /Add-Package SSU-*.cab, then the LCU
```

IT media-refresh sequence (Dynamic Update) makes the same order explicit: **add servicing stack (via the combined CU) first**, languages/FODs next, **latest cumulative last**, then cleanup/export. WinRE is **not** serviced by applying the LCU to `winre.wim`; SSU from the CU + Safe OS Dynamic Update is the documented WinRE path.

**24H2+ checkpoint CUs:** the target LCU may require a prior checkpoint `.msu`. WU/WSUS apply that seamlessly. Catalog/DISM users must either install checkpoints in KB order or put **only** the checkpoint(s) + target in a folder and `/Add-Package` the target so DISM discovers prerequisites. Extra `.msu` files in that folder are not allowed.

| Step | Accept / reject for WinMint servicing |
| --- | --- |
| ARM64 Catalog `.msu` (`Windows11.0-KB*-arm64.msu`, “ARM64-based Systems”) matching the Source ISO build family | **Accept.** Wrong arch fails applicability. |
| SSU (extracted cab or combined CU used as SSU) **then** LCU; 24H2: checkpoint folder | **Accept.** |
| Dump every monthly CU since RTM into one folder | **Reject** unless the KB/Catalog pop-up lists those files as checkpoints. |
| `wusa.exe` against a mounted offline WIM | **Reject.** WUSA is online. Offline is DISM `/Add-Package`. |
| Guest `pwsh` / `Add-WindowsPackage` as product runtime | **Reject.** Host elevated `dism.exe` only, same as other kernels. |

### `/Cleanup-Image /StartComponentCleanup /ResetBase`

| Switch | Microsoft contract | WinMint today |
| --- | --- | --- |
| `/StartComponentCleanup` | Removes superseded component versions; shrinks WinSxS. | Release `cleanup=full` runs this **with** `/ResetBase`. |
| `/ResetBase` | Further shrinks the store by resetting the superseded base. **Installed updates cannot be uninstalled afterwards.** `/Defer` is factory-only when ResetBase takes >30 minutes. | Same Release command. Test is `cleanup=skip` — do not ResetBase on Smoke iteration. |
| `/AnalyzeComponentStore` | Report; cleanup “recommended” is the cue. | Not used. Optional diagnostic, not a kernel. |
| `/RevertPendingActions` | Recovery only, on an image that **did not boot**. Not for a running OS. | Not a slipstream step. |

**Tradeoff:** ResetBase is the documented size bar for a **shipped** image (WinMint Release already wants this). It is the wrong default for Smoke: it is slow, irreversible for uninstall, and Microsoft’s own media-update note says cleanup **fails** if the image still has pending operations (example they own: enabling .NET / Optional Components offline). Two documented escapes: skip cleanup (larger WIM) or defer those pending-creating features until after cleanup — then next month you must start from an image **without** leftover pending actions.

### Pending actions / first-boot remaining work

DISM limitations (owning page, not Q&A): installing a package in an **offline** image often leaves state **install pending** because of **pending online actions**. The package is finished **when the image boots** and those actions run. Later servicing cannot proceed until that completes. `/PreventPending` **skips** adding a package if the package or image already has pending online actions — it does not finish the pending work offline.

So path A **reduces** OOBE quality-update download/install of an old LCU; it does **not** promise a first boot with zero CBS work. A 30+ minute OOBE “checking for updates” on a months-behind ISO is the large remaining quality payload. First-boot “Getting ready” / short CBS pending is still Windows.

Do not cite deleting `pending.xml` as a Microsoft-supported cleanup. Learn’s named knobs are `/PreventPending`, `/RevertPendingActions` (recovery), and **booting** the image.

### ARM64 package SKUs

- Catalog rows are architecture-specific. Use **ARM64-based Systems**, not x64, for SL7 / native ARM64 Smoke.
- Combined LCU + SSU still ships per architecture. Hotpatch KBs list “Windows for Arm64” as a SKU line.
- UUP on-premises foundation download is **per architecture** (AMD64 and ARM64 called out separately). That is WSUS/ConfigMgr content, not an ISO SKU.
- DISM package identity includes the architecture token (`~arm64~~` vs `~amd64~~` / `~x86~~`). `/Get-Packages` after Add-Package is the check.
- 24H2 checkpoint examples on Learn use `windows11.0-kb5043080-x64_….msu`; Catalog also ships the ARM64 filename for the same KB. Match the image, not the Learn x64 example bytes.

## 2. OOBE / ZDP (path B)

Owning page: [Updates during OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/windows-updates-during-oobe-in-windows-11) (also restated under [OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11)).

| Behavior | Official | Opt out? |
| --- | --- | --- |
| After the user (or wired detection) **connects to a network**, critical **ZDP** (zero-day patch) Windows updates **and** critical driver updates start downloading. | Required for the device to operate. Windows shows “checking for / applying updates.” Device may restart. | **No.** “The user can't opt out.” |
| Metered cellular/Wi-Fi during OOBE | Only critical updates (critical drivers + ZDP) are allowed. | N/A for Smoke NAT (unmetered Default Switch). |
| If a **newer version of Windows** is available than the version released with the device, **depending on OS build**, the user **may be offered the latest Windows updates during OOBE**. Download + install **can take 30 minutes or more**. Size, network, and hardware decide duration. OOBE restarts after install. Keep the PC on and plugged in. | This is the quality/feature catch-up, not the ZDP sentence. | **No hide flag.** Unattend does not name a ZDP/quality skip. |
| CloudExperienceHost “Getting ready” / “Just a moment” | Progress / cloud pages, not a customizable screen. Cloud pages can appear or be absent in lab. | **None.** Do not fake a skip. |

Companion research already accepted ZDP as Windows: [2026-08-16-clean-hands-off-oobe](2026-08-16-clean-hands-off-oobe.md). This note does not reopen that.

**WinMint “Just a moment” is three different things.** Do not collapse them:

| Spinner | Cause | This note |
| --- | --- | --- |
| OOBE ZDP / quality update | Network + behind image | Path A shrinks quality; ZDP remains. |
| CloudExperienceHost “Getting ready” | Inbox OOBE progress | Accept. No hide. |
| FirstLogon hang on `defaultuser0` / Shell vs RunOnce | Product bug class (Smoke story 4; v1 Shell deadlock) | **Not** a Windows Update problem. Machine setup + post-OOBE Shell already own it. |

## 3. Does a current LCU in the WIM still trigger ZDP?

**Yes.** ZDP is gated on **network**, not on “LCU already equals this month.”

- Critical ZDP/drivers still scan/apply after connect. Typically **smaller** when the image already contains the current quality baseline — Learn does not give a byte count; it does say only **critical** updates are required and that quality catch-up is the 30+ minute path when the **released-with-device** build is behind.
- A current LCU does **not** document a ZDP skip, a “checking for updates” skip, or a cloud-page skip.
- Smoke on Default Switch will always enter that scan. Cutting NAT to avoid ZDP would also break winget prove-out — **reject** that trade.

## 4. Official UUP vs community converters vs how Microsoft wants a current image

### Official UUP (Windows Update packaging)

UUP is Microsoft’s **single publishing, hosting, scan, and download model** for OS quality and feature updates. The client downloads **UpdateAgent**, evaluates **CompDB** metadata, and produces an **action list** of payloads (ESDs/packages) to reach a composition state. That is how Windows Update, Windows Update client policies, and (from 2023) WSUS/ConfigMgr on-premises deliver Windows 11 quality updates — including a one-time ~10 GB **per architecture** foundation on distribution points, then smaller monthly diffs.

Official UUP is **not**:

- A supported “download these ESDs and burn a retail ISO” product,
- A replacement for a user-supplied Source ISO,
- Something WinMint should speak as a default media source.

Microsoft’s owned “update installation media **prior to deployment**” page tells IT to start from **volume-licensed media** (VLSC and “other relevant channels” including **Visual Studio Subscriptions**, Windows Update client policies, WSUS) and to apply **Microsoft Update Catalog** Dynamic Update / CU packages with DISM. Optional FODs/languages are **separate ISOs** on VLSC, not reconstructed from UUP dumps.

Visual Studio Subscriptions Learn: subscriber [Downloads](https://my.visualstudio.com/downloads/featured) lists Windows 11 titles; architecture / language / file type are drop-downs. That is an official ISO **channel**, not a UUP converter. Learn does **not** contract a Patch-Tuesday ISO SLA; the documented “make this media current” procedure is Catalog + DISM (path A), or install then Windows Update (path B).

Consumer [Windows 11 software download](https://www.microsoft.com/software-download/windows11) is also an official ISO source. It is often **not** the newest CU; catching up is still A or B.

### Community UUP dump converters (non-primary)

Sites and scripts that scrape Windows Update UUP metadata, download payloads, and wrap `install.wim`/`esd` into an ISO are **community**. They are not Microsoft Learn, not a Catalog package, and not a VS/VL download. Do not cite them as official. Using them as WinMint Source ISO would be a silent/golden Windows obtain path in all but name.

| Source | Official? | WinMint |
| --- | --- | --- |
| User-supplied retail / VS / VL / software-download ISO | Yes | **Required.** |
| Microsoft Update Catalog SSU/LCU/SafeOS/Setup DU `.msu` | Yes | Operator-fetched input to a possible future DISM kernel; not auto-download. |
| Windows Update / WSUS / WUfB on the installed OS | Yes (UUP protocol) | Guest after OOBE; Smoke NAT already on. |
| Community UUP dump → ISO | **No** | **Reject** as Source ISO / default. |

## 5. WinMint constraints (repo — not OS proof)

Do not invent product changes to dodge OOBE. Living constraints that this recommendation must not contradict:

| Constraint | Locus |
| --- | --- |
| User-supplied official Microsoft **Source ISO** only. No bundling, pinning, or silent Windows ISO/UUP-dump download. Same-train Catalog quality `.msu` is ImageServicing. | [DESIGN §Invariants](../DESIGN.md#invariants) · [ADR-001](../decisions/ADR-001-source-iso-legal.md) · [ADR-013](../decisions/ADR-013-catalog-lcu.md) · [CONTEXT](../../CONTEXT.md) |
| **Prepared media** is an immutable Source-ISO tree keyed by schema + Source ISO SHA-256 + index. Copied to staged media; never mounted; not a cache in product copy; not a golden patched WIM. | [CONTEXT](../../CONTEXT.md) · [IMAGESERVICING](../design/IMAGESERVICING.md) |
| Every Apply still requires the Source ISO file and a matching rehash. Prepared media must not stand in for a missing ISO. | IMAGESERVICING |
| Host Servicing = elevated `pwsh -File` kernels calling `dism.exe`. No in-process DISM from Cli/Wizard. | DESIGN · IMAGESERVICING |
| Test lane: `compression=fast`, `cleanup=skip`. Release: `compression=max`, `cleanup=full` (`/StartComponentCleanup /ResetBase`). Smoke uses Test. | `ExportLane.For` · CliLog Release warning |
| There is **no** `Add-Package` / LCU opcode today. Grep: UUP only in ADR-001 / CONTEXT / historical specs; `Add-Package` is not a kernel; ZDP only in OOBE research. | this repo, 2026-08-19 |
| Smoke guest **must** have network: `Invoke-Smoke.ps1` fails closed if Hyper-V **Default Switch** is missing — “needed for guest network (winget prove-out).” | `tools/vm/Invoke-Smoke.ps1` |
| Product-constant Store `AutoDownload=2` is **not** a Windows Update block. | [ADR-009](../decisions/ADR-009-product-constant-policies.md) |

**Implication for A:** if a future issue adds offline CU servicing, it belongs on **staged media** during Apply (or the operator replaces the Source ISO, which is a new Prepared-media key). Patching the Prepared-media store in place would make a “golden ISO” by another name and break SHA identity.

## 6. Recommendation (explicit)

### (a) Smoke iteration speed — **B + current-enough Source ISO**

- Keep Default Switch NAT. Winget prove-out needs it; ZDP will run; that is accepted Windows.
- Keep Test `cleanup=skip`. Do not add SSU/LCU/`ResetBase` to the Smoke host loop.
- If Smoke’s wall is a **30+ minute OOBE quality install**, the cheap fix is an **operator-supplied newer official ISO** (VS/VL/software-download), not converting UUP dumps and not slipstreaming on every `just smoke`.
- Do not disable network, BypassNRO, or unattend-skip OOBE to hide the spinner.

### (b) Primary / SL7 wipe currency — **official ISO, A if behind**

- Operator obtains ARM64 Windows 11 Pro (or matching SKU) media from Visual Studio Subscriptions, volume licensing, or Microsoft software-download — **outside** WinMint.
- If that ISO is months behind Patch Tuesday, Microsoft’s documented pre-deployment path is Catalog ARM64 checkpoint+LCU (SSU first) into `install.wim`, then Release `ResetBase`/export — **not** a community UUP ISO.
- Remaining ZDP after network is still expected and should stay small.
- Do not bake a maintainer golden WIM into Prepared media.

### (c) First-session spinner — **A for quality duration; B for ZDP; never C**

- **30+ minutes:** path A (or a newer official ISO) is the Microsoft-owned way to avoid OOBE quality catch-up. Path B is what you have today when the Source ISO is old and the guest has NAT.
- **ZDP / “checking for updates” after network:** still happens with a current LCU; typically smaller; **cannot be opted out.**
- **“Just a moment” as CloudExperienceHost or `defaultuser0`:** not an update-servicing path. See [2026-08-16](2026-08-16-clean-hands-off-oobe.md) and Smoke story 4.

## What not to do

- **Community UUP dump as Source ISO / default.** Not official; contradicts ADR-001 and CONTEXT.
- **Silent Catalog/WU download of LCUs inside WinMint.** Same legal/product rule as UUP-as-source. Operator fetch is allowed; product fetch is a new ADR.
- **Treat Prepared media as a patched golden image.** Identity is Source ISO SHA-256.
- **ResetBase on Test/Smoke** to “finish” an LCU. Irreversible uninstall; slow; pending actions can make it fail; Test is `skip` on purpose.
- **Unplug Smoke NAT** to skip ZDP. Breaks winget; ZDP is not optional after network anyway on a connected install.
- **Unattend / policy to skip OOBE updates.** Learn names no such hide. Do not invent one.
- **Delete `pending.xml` / `/RevertPendingActions` as a slipstream trick.** Revert is recovery for a non-booting image.
- **x64 MSU on an ARM64 WIM.** Applicability fails or produces a lie.
- **LCU on `winre.wim` as the WinRE servicing path.** Learn: SSU + Safe OS Dynamic Update; LCU applies to `install.wim` and `boot.wim` (WinPE), not WinRE.

## Citations

- [Updates during OOBE](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/windows-updates-during-oobe-in-windows-11) — ZDP after network, no opt-out; quality updates 30+ minutes when image is behind
- [OOBE screen details](https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/oobe-screen-details-in-windows-11) — network, critical ZDP/drivers, metered = critical only, cloud pages
- [DISM OS package servicing](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dism-operating-system-package-servicing-command-line-options?view=windows-11) — `/Add-Package` order, `.msu` on 21H2+, `/PreventPending`, checkpoint folder, `/Cleanup-Image` `/ResetBase` uninstall bar, **install pending** until first boot
- [Add or remove packages offline](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-or-remove-packages-offline-using-dism?view=windows-11) — command-line order; answer file for dependencies
- [Servicing stack updates](https://learn.microsoft.com/en-us/windows/deployment/update/servicing-stack-updates) — SSU vs LCU; combined CU includes SSU from Feb 2021
- [KB5011487 known issue](https://support.microsoft.com/en-us/topic/march-8-2022-kb5011487-os-builds-19042-1586-19043-1586-and-19044-1586-8297eadb-3b8b-4ca5-9083-ca41a91c1c56) — slipstream SSU **before** LCU; `expand` extract SSU from combined package (Microsoft Support, owns the combined-package slipstream failure)
- [Reduce component store (offline)](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/reduce-the-size-of-the-component-store-in-an-offline-windows-image?view=windows-11) — `/StartComponentCleanup` `/ResetBase` `/Defer`
- [Update installation media with Dynamic Update](https://learn.microsoft.com/en-us/windows/deployment/update/media-dynamic-update) — VLSC / VS / WSUS as media channels; Catalog packages; **SSU via combined CU first, LCU last**; WinRE vs install.wim vs boot.wim; pending .NET/OC vs cleanup
- [Checkpoint CUs and the Catalog](https://learn.microsoft.com/en-us/windows/deployment/update/catalog-checkpoint-cumulative-updates) — 24H2 checkpoints; DISM folder; LCU not for WinRE
- [Microsoft Update Catalog](https://www.catalog.update.microsoft.com/) — official `.msu` source
- [Get started with Windows Update / UUP architecture](https://learn.microsoft.com/en-us/windows/deployment/update/windows-update-overview) — official UUP = scan/download model (CompDB, action list, ESDs)
- [How Windows Update works](https://learn.microsoft.com/en-us/windows/deployment/update/how-windows-update-works) — USO scan/download/install/commit
- [Optional content](https://learn.microsoft.com/en-us/windows/deployment/update/optional-content) — VLSC image vs separate FOD/LP ISOs; UUP for optional-content acquisition
- [WSUS + UUP](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-update-services/get-started/windows-server-update-services-wsus) — UUP on-premises is WSUS/ConfigMgr, not ISO rebuild
- [UUP on premises (Windows IT Pro Blog)](https://techcommunity.microsoft.com/blog/windows-itpro-blog/get-ready-for-the-first-uup-on-premises-updates-coming-in-march/3738461) — official Microsoft blog; 10 GB per architecture (AMD64 and ARM64); quality updates via UUP
- [Download software (Visual Studio Subscriptions)](https://learn.microsoft.com/en-us/visualstudio/subscriptions/download-software) — official Windows 11 ISO channel; architecture selector
- [Windows 11 software download](https://www.microsoft.com/software-download/windows11) — official consumer ISO
- [Server Core servicing / DISM Add-Package](https://learn.microsoft.com/en-us/windows-server/administration/server-core/server-core-servicing) — `/PreventPending` (Context7 hit; same DISM contract)

### Repo / v1 (not OS proof)

- [CONTEXT](../../CONTEXT.md) — Source ISO; avoid golden ISO / UUP default source; Prepared media identity
- [ADR-001](../decisions/ADR-001-source-iso-legal.md) — no silent Windows ISO/UUP-dump download
- [ADR-013](../decisions/ADR-013-catalog-lcu.md) — Catalog LCU is ImageServicing
- [DESIGN](../DESIGN.md) — user-supplied Source ISO invariant; Smoke vs Primary
- [IMAGESERVICING](../design/IMAGESERVICING.md) — `AddQualityUpdates`; Prepared media SHA key; staged copy
- `ExportLane.For` — Test `skip` / Release `full` ResetBase
- `tools/vm/Invoke-Smoke.ps1` — Default Switch NAT for winget
- [2026-08-16-clean-hands-off-oobe](2026-08-16-clean-hands-off-oobe.md) — ZDP accepted as Windows; “Just a moment” not a hide flag
