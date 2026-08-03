# Bulk Crap Uninstaller (BCU) — research (2026-08-03)

Question: what is Bulk Crap Uninstaller, how does it work (architecture, techniques, data sources), and what — if anything — could WinMint adopt for its later debloat / keep-flag matrix vertical?

WinMint framing (from product docs, not BCU sources): Offline **ImageServicing** mutates WIM/ISO via elevated host pwsh; **ProvisioningSession** (Native AOT C#) finishes FirstLogon live; debloat / keep-flag matrix is an **explicitly deferred** vertical (not smoke — [TICKETS.md](../TICKETS.md), [smoke spec](../specs/2026-07-27-smoke.md)). Prefer learnable techniques over bundling a third-party GUI uninstaller.

Trust tiers used throughout:

- **[primary]** — official site, GitHub repo (README, `Licence.txt`, `NOTICE`, `CONTRIBUTING.md`), and source under `source/` as of the `master` tree inspected 2026-08-03. The canonical repo is [Klocman/Bulk-Crap-Uninstaller](https://github.com/Klocman/Bulk-Crap-Uninstaller) (also reachable as [BCUninstaller/Bulk-Crap-Uninstaller](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller)); homepage [bcuninstaller.com](https://www.bcuninstaller.com/).
- **[inference]** — conclusions drawn by mapping primary facts onto WinMint seams; labeled as such.

## What BCU is

Bulk Crap Uninstaller (BCUninstaller / BCU) is a free, open-source **live Windows program manager / bulk uninstaller**. Official positioning: it “excels at removing large amounts of applications with minimal to no user input,” can detect portable/orphan apps, clean leftovers, force-uninstall, and run uninstalls from premade lists ([primary — homepage](https://www.bcuninstaller.com/); [primary — README](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/README.md)).

Documented inventory / management sources on the homepage:

- Normal and hidden/protected registered applications (Programs and Features–style)
- Damaged or missing uninstallers
- Portable apps (common locations / portable drives)
- Chocolatey packages, Oculus apps, Steam games/apps
- Windows Features, Windows Store (UWP) apps, Windows Updates

([primary — homepage, “Very thorough installed application detection”](https://www.bcuninstaller.com/))

Design stance on removal: BCU **prefers the application’s original uninstaller** over blind file deletion, explicitly to avoid missing context-menu entries, services, etc. ([primary — homepage, “Fast, automatic uninstall”](https://www.bcuninstaller.com/)).

Current product line (README): **v6** targets Windows 10+ with **.NET 8** desktop runtime (portable builds bundle runtime); v5 is .NET 6 / Win7+; older branches exist for XP-era .NET Framework ([primary — README](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/README.md)). The README also flags that the project is **looking for maintainers** ([primary — README / discussions link](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/README.md)).

## License

BCU is **Apache License 2.0**, not GPL/AGPL. Confirmed in:

- Repo `Licence.txt` (Apache 2.0 text; copyright notice “Copyright 2017 Marcin Szeniak”) ([primary — Licence.txt](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/Licence.txt))
- Homepage commercial-use blurb: usable in private and commercial settings “as long as no conditions of the license are broken” ([primary — homepage](https://www.bcuninstaller.com/))
- README license badge / statement ([primary — README](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/README.md))
- `NOTICE` identifies Marcin Szeniak as project manager / lead and points to the GitHub project ([primary — NOTICE](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/NOTICE))

**Inference for WinMint:** Apache 2.0 is generally compatible with incorporating code into a GPL-3 project *if* Apache attribution / NOTICE obligations are met and the combined distribution remains under WinMint’s GPL-3 terms. That does **not** make shipping BCU as a product dependency a good idea — only that license alone is not an automatic blocker for *copying techniques or small excerpts* with proper notices. Bundling the BCU binary is legally allowed under Apache 2.0 with attribution, but is a product/architecture question (see synthesis).

## Architecture

### Codebase split

`CONTRIBUTING.md` documents the modular split ([primary — CONTRIBUTING.md](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/CONTRIBUTING.md)):

| Piece | Role |
|-------|------|
| `BulkCrapUninstaller` | WinForms GUI |
| `BCU-console` | CLI front-end |
| `UninstallTools` | Core library (inventory, uninstall orchestration, junk, lists, startup) |
| Helper exes | Specialized adapters talking to UninstallTools over CLI; usable alone in scripts |

Helpers present in the `source/` tree include at least: `StoreAppHelper`, `SteamHelper`, `WinUpdateHelper`, `OculusHelper`, `ScriptHelper`, plus `UninstallerAutomatizer` and `UniversalUninstaller` ([primary — source tree](https://github.com/Klocman/Bulk-Crap-Uninstaller/tree/master/source)).

There is **no** project named `QuietUninstallHelper`. Quiet automation is implemented as:

1. **Native quiet strings** from registry / synthesizers (`QuietUninstallString`, MSI `/qb /X`, Inno `/VERYSILENT`, …)
2. **`UninstallerAutomatizer`** — UI Automation (FlaUI / TestStack.White) that drives interactive uninstallers (especially NSIS) by clicking “good” buttons and avoiding cancel/reboot-now controls ([primary — AutomatedUninstallManager.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallerAutomatizer/Automation/AutomatedUninstallManager.cs))
3. **`UniversalUninstaller`** — separate helper for manual / force-style removal UX (directory-oriented; live GUI helper under `source/UniversalUninstaller/`)

### Inventory pipeline (`UninstallTools`)

`ApplicationUninstallerFactory.GetUninstallerEntries` orchestrates roughly ([primary — ApplicationUninstallerFactory.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Factory/ApplicationUninstallerFactory.cs)):

1. Enumerate MSI product GUIDs (`MsiTools.MsiEnumProducts`)
2. Concurrently run “misc” independent factories (`IIndependantUninstallerFactory`)
3. Scan uninstall registry via `RegistryFactory`
4. Enrich missing install locations / metadata (`InfoAdder` pipeline)
5. Optional drive / portable scan via `DirectoryFactory` (uses registry results as seeds; introduces duplicates to merge later)
6. Merge store/feature/update/etc. results, then drive results
7. Attach startup entries discovered by `StartupManager` factories

Independent factories under `Factory/` include: `RegistryFactory`, `DirectoryFactory`, `StoreAppFactory`, `WindowsFeatureFactory`, `WindowsUpdateFactory`, `SteamFactory`, `ChocolateyFactory`, `OculusFactory`, `ScoopFactory`, `ScriptFactory`, `PredefinedFactory` ([primary — Factory directory](https://github.com/Klocman/Bulk-Crap-Uninstaller/tree/master/source/UninstallTools/Factory)).

`UninstallerType` enum covers: Unknown, Msiexec, InnoSetup, Steam, Nsis, InstallShield, SdbInst, WindowsFeature, WindowsUpdate, StoreApp, SimpleDelete, Chocolatey, Oculus, PowerShell ([primary — UninstallerType.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/UninstallerType.cs)).

### CLI (`BCU-console`)

Commands ([primary — BCU-console Program.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/BCU-console/Program.cs)):

- `list` — print installed apps
- `export` — XML export of entries
- `uninstall <file.bcul>` — match apps against an uninstall list and run bulk uninstall

Switches: `/Q` (prefer quiet), `/U` (unattended — documented with strong warnings), `/J[=level]` (post-uninstall junk cleanup; default confidence **VeryGood**), `/V` (verbose). Console configures quiet automation on by default (`QuietAutomatization`, `UseQuietUninstallDaemon`, kill-stuck).

### Premade lists (keep / exclude UX)

`.bcul` files are XML-serialized `UninstallList` objects: ordered **include/exclude filters** with conditions; exclude wins; include-only or exclude-only semantics are explicit in `TestEntry` ([primary — UninstallList.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Lists/UninstallList.cs), [Filter.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Lists/Filter.cs)). Homepage also markets “automatically uninstall according to premade lists” ([primary — homepage](https://www.bcuninstaller.com/)).

**Inference:** this is the closest BCU analogue to a **keep-flag matrix** — declarative selection over a discovered inventory, not a hard-coded “debloat script.”

## Inventory data sources (detail)

### Registry uninstall keys

`RegistryFactory` reads ([primary — RegistryFactory.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Factory/RegistryFactory.cs)):

- `HKLM` / `HKCU` `\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
- On 64-bit processes, also `Wow6432Node\...\Uninstall`

Fields consumed include `DisplayName`, `UninstallString`, `QuietUninstallString` (plus fuzzy `UninstallString_*` / hidden variants), `InstallLocation`, `Publisher`, `SystemComponent`, `WindowsInstaller`, Inno-specific value names, Steam key-name prefix, `NoRemove` (protected), update heuristics (`ParentKeyName`, `ReleaseType`, `KB######` default values).

### Windows Installer (MSI)

Factory pipeline enumerates MSI products first and uses GUID correlation when registry entries are incomplete ([primary — ApplicationUninstallerFactory.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Factory/ApplicationUninstallerFactory.cs)). Quiet MSI path: `MsiExec.exe /qb /X{GUID} REBOOT=ReallySuppress /norestart` ([primary — UninstallManager.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Uninstaller/UninstallManager.cs)).

### Store / UWP apps

`StoreAppFactory` shells out to `StoreAppHelper.exe /query` and `/uninstall` ([primary — StoreAppFactory.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Factory/StoreAppFactory.cs)). The helper uses live `Windows.Management.Deployment.PackageManager` — `FindPackagesForUserWithPackageTypes(..., PackageTypes.Main)` and `RemovePackageAsync` — plus `AppxManifest.xml` / PRI string extraction ([primary — StoreAppHelper AppManager.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/StoreAppHelper/AppManager.cs)). Factory also documents a PowerShell form: `Remove-AppxPackage -package {fullName} -confirm:$false` (same file).

This is **user/live package** removal, not DISM provisioned-package offline removal.

### Windows Features

`WindowsFeatureFactory` inventories via WMI (`WmiQueries.GetWindowsFeatures`) and builds uninstall strings through `DismTools.GetDismUninstallString` → `Dism.exe /norestart [/quiet] /online /disable-feature /featurename=...` ([primary — WindowsFeatureFactory.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Factory/WindowsFeatureFactory.cs); [DismTools.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/KlocTools/IO/DismTools.cs)).

Critical: every DISM invocation in `DismTools` uses **`/online`**. There is **no** `/image`, WIM mount, or provisioned-package path in the repo tree (recursive tree search 2026-08-03: `DismTools.cs` only; zero hits for `WIM`, `offline`, `Mount`, `provisioned`).

### Startup / related

`UninstallTools/Startup` covers normal Run-key startups, services, scheduled tasks, and browser helper objects; results are attached to matching uninstall entries ([primary — Startup tree](https://github.com/Klocman/Bulk-Crap-Uninstaller/tree/master/source/UninstallTools/Startup); wired from `ApplicationUninstallerFactory`).

## Leftover (“junk”) detection

`JunkManager.FindJunk` reflects all `IJunkCreator` implementations, runs each against targets, merges duplicates, and filters prohibited system directories / self-paths ([primary — JunkManager.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/JunkManager.cs)).

Finder categories under `Junk/Finders/` include ([primary — Junk tree](https://github.com/Klocman/Bulk-Crap-Uninstaller/tree/master/source/UninstallTools/Junk)):

- **Drive:** install/uninstaller locations, common drive folders, Prefetch, Windows Error Reporting dumps, uninstaller-kind-specific paths
- **Registry:** uninstall keys, Software keys, COM, firewall rules, AppCompat flags, Event Log, UserAssist, tracing, installer folders, Registered Applications, …
- **Misc:** shortcuts, startup junk
- **Orphans:** `ProgramFilesOrphans` (empty / unused Program Files cleanup — also exposed as a dedicated GUI action on the homepage)

Confidence is additive records → levels `Unknown`, `Bad`, `Questionable`, `Good`, `VeryGood` (numeric thresholds 0 / 5 / 7 / 9 / 12) ([primary — ConfidenceLevel.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/Confidence/ConfidenceLevel.cs)). Matching uses product-name similarity (Sift4 distance), publisher/company traps, path depth, known-folder penalties, and “similarly named app” demotions ([primary — ConfidenceGenerators.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/Confidence/ConfidenceGenerators.cs)).

CLI junk cleanup defaults to **VeryGood** and warns that lower levels need extreme caution ([primary — BCU-console Program.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/BCU-console/Program.cs)).

**Inference:** leftover detection is inherently **post-uninstall, live-filesystem / live-registry**. It is not an offline-WIM leftover model.

## Quiet / silent uninstall techniques and reliability posture

Layered approach (from sources above):

1. Prefer registry `QuietUninstallString` when present.
2. Synthesize known silent flags:
   - **Inno Setup:** `unins000.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` ([primary — InnoSetupQuietUninstallStringGenerator.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Factory/InfoAdders/InnoSetupQuietUninstallStringGenerator.cs)) — comments note `/VERYSILENT` can reboot without asking if `/NORESTART` is omitted; BCU includes `/NORESTART`.
   - **MSI:** quiet `/qb /X` with reboot suppress ([primary — UninstallManager.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Uninstaller/UninstallManager.cs)).
   - **NSIS:** wrap the normal uninstall command with `UninstallerAutomatizer.exe Nsis [/K] …` when automation is enabled ([primary — NsisQuietUninstallStringGenerator.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Factory/InfoAdders/NsisQuietUninstallStringGenerator.cs)).
3. **UI Automation fallback** (`UninstallerAutomatizer`): attach to the uninstaller process, find buttons by localized “good/cancel/bad” names across cultures and known NSIS automation IDs, optionally move windows mostly off-screen, detect recurring popups as failure ([primary — AutomatedUninstallManager.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallerAutomatizer/Automation/AutomatedUninstallManager.cs)).
4. Force / simple-delete paths exist for apps with no usable uninstaller (homepage + `UninstallerType.SimpleDelete` / `UniversalUninstaller`).

Reliability posture in product copy and CLI: automation is a major feature, but unattended mode and aggressive junk levels carry **explicit “no warranties / thorough testing / extreme caution” warnings** ([primary — homepage](https://www.bcuninstaller.com/); [BCU-console Program.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/BCU-console/Program.cs)). Homepage also claims handling of crashing/hanging uninstallers.

**Inference:** quiet reliability is best for MSI/Inno/store/feature paths with real silent APIs; NSIS UI automation is best-effort and desktop-session dependent — a poor fit for headless FirstLogon jobs.

## Offline WIM / DISM / provisioned packages

**Fact:** BCU’s DISM usage is **`/online` only** (feature inventory/disable). Store removal uses live `PackageManager`. Registry/MSI/drive scanners assume a running OS. Repo tree shows **no** offline image, WIM mount, or provisioned AppX APIs ([primary — DismTools.cs](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/KlocTools/IO/DismTools.cs); recursive tree search 2026-08-03 as above).

**Inference:** BCU is **not** an offline image servicing tool. Anything WinMint does in Offline Servicing (DISM `/Image`, registry hive load, `Remove-AppxProvisionedPackage`, package/feature removal in the WIM) must come from WinMint’s own ImageServicing design — BCU does not supply that layer.

## Live-system only vs reusable as technique

| Capability | Live-only? | Reusable idea without shipping BCU |
|------------|------------|-------------------------------------|
| Registry uninstall inventory | Live (or offline hive analog) | Catalog shape; field list; protected/`SystemComponent` flags |
| MSI product enumeration | Live | Rarely relevant to ISO debloat of inbox apps |
| Store `PackageManager` / `Remove-AppxPackage` | Live user packages | FirstLogon cleanup of **rehydrated** user AppX only |
| DISM `/online /disable-feature` | Live | Mirror with DISM `/Image` in Servicing |
| Drive / portable scanners | Live | Low value for golden ISO |
| Premade include/exclude lists | Concept | Keep-flag / Profile matrix UX |
| Junk confidence scoring | Live post-uninstall | Optional post–metal-package cleanup under Supervisor; keep high confidence bar |
| NSIS UI automation | Live interactive desktop | Do **not** adopt for ProvisioningSession |
| Prefer original uninstaller | Principle | Prefer platform APIs (DISM, AppX, pkgmgr) over delete-by-path |

## Synthesis — WinMint adoption

### Adopt / borrow (ideas)

1. **Declarative keep/exclude matrix over a typed catalog** — BCU’s `.bcul` include/exclude filters are a proven UX for “remove these, never touch those” ([primary — UninstallList / Filter](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Lists/UninstallList.cs)). Map to BuildPlan **Profile** keep-flags: explicit keep beats heuristic remove.
2. **Multi-source factory catalog** — separate detectors per package kind (provisioned AppX, capability, optional feature, inbox EXE) rather than one mega-script ([primary — Factory pattern](https://github.com/Klocman/Bulk-Crap-Uninstaller/tree/master/source/UninstallTools/Factory)).
3. **Prefer official removal APIs** — BCU’s “use the real uninstaller” rule translates to: DISM/AppX APIs offline; live AppX APIs only when Servicing cannot finish the job ([primary — homepage](https://www.bcuninstaller.com/)).
4. **Confidence tiers for cleanup aggressiveness** — VeryGood-default junk posture is a good model for any FirstLogon leftover pass ([primary — ConfidenceLevel + console `/J`](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/Confidence/ConfidenceLevel.cs)).
5. **Quiet-string synthesis for known installers** — only if WinMint ever uninstalls third-party metal packages at FirstLogon (MSI/Inno flags are small, well-documented techniques). Not needed for inbox debloat.

### Do **not** adopt

1. **Shipping BCU (GUI or console) in the ISO or as a Servicing dependency** — wrong abstraction (live uninstaller manager), large .NET desktop surface, maintainer-seeking upstream, guest must stay C# Supervisor / no guest pwsh orchestration of a foreign GUI tool. License permits redistribution; product architecture does not recommend it. Evidence does **not** strongly support bundling.
2. **UI Automation quiet uninstall** (`UninstallerAutomatizer`) in ProvisioningSession — fragile, locale/desktop dependent, conflicts with Shell-tenure / splash model.
3. **Treating Programs-and-Features inventory as the ISO debloat source of truth** — offline provisioned packages and features do not look like HKLM Uninstall keys in a mounted WIM the way a live box does.
4. **Steam / Chocolatey / Oculus / Scoop / portable-drive scanners** — out of scope for WinMint ISO customization.
5. **Blind force-delete as primary debloat** — contradicts both BCU’s own stated preference and WinMint’s servicing model.

### Map to WinMint seams

| Idea | BuildPlan / Profile | ImageServicing (offline) | ProvisioningSession (FirstLogon) |
|------|---------------------|---------------------------|----------------------------------|
| Keep/exclude list UX | **Primary home** — keep-flag matrix schema & presets | Consumes resolved remove/keep sets | May enforce user-scoped leftovers only if Profile says so |
| Provisioned AppX / feature catalog | Names + default keep flags | **Primary execution** — DISM `/Image`, hive edits, provisioned package remove | Only for packages that reappear per-user after OOBE |
| Registry Uninstall inventory | Optional validation catalog (host reference machine) | Possible offline hive read for *added* software in custom images; not inbox AppX | Possible audit job; not the main debloat engine |
| Leftover confidence cleanup | Aggressiveness enum on Profile | Limited (delete known paths in mount) | Optional high-confidence cleanup after metal installs |
| Quiet MSI/Inno tricks | N/A for inbox | N/A | Only if Supervisor uninstalls third-party bundles |
| BCU binary / GUI | — | **No** | **No** |

### License implications if code were copied

- Upstream: **Apache 2.0** with `NOTICE` and copyright ([primary — Licence.txt](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/Licence.txt), [NOTICE](https://github.com/Klocman/Bulk-Crap-Uninstaller/blob/master/NOTICE)).
- WinMint ships **GPL-3.0** (`LICENSE` in repo root).
- Copying BCU source into WinMint would require retaining Apache notices / NOTICE attribution; the combined work stays under GPL-3 obligations for WinMint’s distribution. Prefer **reimplementing small techniques** (filter list shape, confidence enum, silent flag constants) over importing `UninstallTools` wholesale — less NOTICE surface, no WinForms/FlaUI dependency graph, and no accidental live-only assumptions.

## Bottom line

BCU is a mature **live-system** bulk uninstall / leftover cleaner with a clean modular core (`UninstallTools`), a useful **include/exclude list** abstraction, and thorough registry/MSI/Store/feature scanners — but **zero offline-WIM awareness**. For WinMint’s deferred debloat vertical: steal the **catalog + keep/exclude + confidence** ideas into Profile / ImageServicing / (narrow) ProvisioningSession; do **not** ship BCU.
