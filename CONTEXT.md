# WinMint

Workstation state compiler — debloat, policies, packages, DMA settle, and account intent from a **Profile**. Delivery artifact: **Output ISO**. User always supplies official Microsoft **Source ISO**. Writing that ISO to removable media is **Flash** (operator step, outside the product seam).

Policy / acceptance: [DESIGN](docs/DESIGN.md).

## Language

**Source ISO** — Official Microsoft install media the user provides. It remains an Apply input every run; a stored media tree must not stand in for a missing file. No silent Windows download.  
_Avoid_: golden ISO, UUP default source; substituting Prepared media or staged media for the Source ISO

**Output ISO** — Host compile result (default leaf `winmint_{profile}_{lane}_{yyyyMMdd-HHmmss}.iso`, or explicit `--out-iso`) plus digests: the delivery artifact ImageServicing emits.  
_Avoid_: treating bootable USB as the compile output; calling Flash “Build”; opaque `out.iso` as the product name; signed ISO; Authenticode on the ISO container; calling the ISO signed because it contains Authenticode PE

**Flash** — Operator writes Output ISO to UEFI removable media with **Rufus** in **DD Image** mode (not ISO mode) and checks `digests.outputIso.sha256`. Outside WinMint’s product boundary — guidance copy only (path / Rufus DD / SHA / LaunchApply); no disk write, no Rufus launch.  
_Avoid_: USB productization; in-process raw write; Rufus fork; “any flasher” as the named recipe; conflating Flash with Primary; calling Flash or the USB Authenticode-signed

**Authenticode** — Timestamped Windows publisher signature on WinMint-owned PE files, and on `.ps1` only if the accepted signing policy covers scripts. The publisher is the certificate holder, not the WinMint product name, the maintainer, or Microsoft; ImageServicing may copy or rename those bytes, not rewrite them. Authenticode is deferred until a non-maintainer is expected to run a GitHub Release PE; do not apply to SignPath or add a signing workflow before that. GitHub Releases stay unsigned. Inner PE on an Output ISO may carry Authenticode; the container does not.  
_Avoid_: signed; signed Release; signed ISO; calling Digest or GitHub attestation Authenticode; SmartScreen-free; Microsoft-endorsed; self-signed as a stand-in; re-signing upstream PE; `irm | iex` as canonical Authenticode bootstrap; `-Force` skipping verification; quiet unsigned publish from a signing workflow; timestamp-optional; fail-open when revocation status is unavailable; applying to SignPath with no downloaders; treating signing as current work

**Profile** — Build intent for one ISO (`winmint.profile/v1`).  
_Avoid_: BuildConfig (user-facing); preset names in JSON

**Orchestrator** — Validates Profile, plans, drives elevated Servicing. Front ends: Cli + Avalonia Wizard, both thin over **HostCompile**.  
_Avoid_: second planning brain in Cli/Wizard

**HostCompile** — Orchestrator entry: Profile + compose options → immutable `HostComposition` approval → ImageServicing → `ImageEvidence`; document-only commands use `HostPlan`. Cli/Wizard are thin adapters.
_Avoid_: second Plan/Apply brain in Cli or Wizard; conflating with Flash

**BuildPlan** — Profile + run options → plan artifacts.  
_Avoid_: DISM at the flag layer; ports before a second adapter

**Plan dump** — Cli diagnostic files for inspecting BuildPlan output. `jobs.json` uses the real guest wire; `stages.json` uses `winmint.plan.stages/v1` and is never Apply input.  
_Avoid_: treating a Plan dump as materialized Servicing state

**Servicing / ImageServicing** — Offline WIM/ISO work via elevated `pwsh -File` kernels. Consumes the Output ISO path and source-media identity frozen by HostCompile. Prepared media is Servicing mechanics, not Profile, CLI, or plan intent. At most one Apply per Host.  
_Avoid_: in-process DISM from Wizard; guest FirstLogon Servicing; hosts inventing a second default Output ISO name; ReuseMedia; `--reuse-media`; caller-owned workdir reuse

**Prepared media** — Host-wide immutable Source ISO tree with the selected index as a single-index `install.wim` and a required `boot.wim`, identified by schema + Source ISO SHA-256 + source index. A complete published entry only: copied into staged media, never mounted, never auto-evicted. Invalid entries are quarantined off the hit path; publication is not Evidence, Proof, or Digest.  
_Avoid_: cache; source-media cache; run media; reuse; warm media; cold path; golden ISO; WIM-only store; install.esd; multi-index install.wim; treating a prepare directory as Prepared media; serving or in-place overwriting an invalid entry; LRU of valid entries

**Staged media** — Per-Apply mutable copy of Prepared media under the work directory. This is the tree Servicing mounts. A leftover tree from a prior Apply is not an input.  
_Avoid_: run media; work media; reuse; mounting Prepared media; treating staged media as the Source ISO

**Payload** — SetupComplete, Supervisor, jobs/media placed into the image. Guest `%WINDIR%\WinMint\` tenure-only; guest `%ProgramData%\WinMint\` may remain for evidence. Not the Host Prepared-media store.  
_Avoid_: guest pwsh control plane; dual `$OEM$` SetupScripts; calling Payload staged media

**Machine setup** — Supervisor `--machine-setup`: autologon + fail-closed Shell verify. No splash/settle/jobs.  
_Avoid_: calling this FirstLogon

**Provisioning Supervisor / ProvisioningSession** — One AOT process: Shell tenure, splash, DMA settle, jobs, reboot checkpoint, fail-open.  
_Avoid_: peer Splash.exe; guest pwsh product runtime; file mailbox control plane

**Splash** — In-process Direct2D/GDI presenter.  
_Avoid_: Splash.exe peer; Avalonia/WinUI on the ISO

**FirstLogon** — Supervisor as Shell → splash → DMA settle → jobs.  
_Avoid_: conflating with Machine setup

**Provisioning lock** — Supervisor is Shell + splash; unlock = `explorer.exe` + exit.

**Provisioning jobs** — Post hard-settle installs (per-id or batch). Same executor Smoke and Primary.  
_Avoid_: jobs before hard settle; “metal jobs” (retired name)

**DMA interop / settle** — **DMA is the EU Digital Markets Act, not Direct Memory Access.** Sticky Ireland setup region (`DeviceRegion` 68) during Setup; restore user visible region by **final snapshot**. Hard: locale/GeoID/TZ + DeviceRegion verify. Soft: location. Rationale: [ADR-003](docs/decisions/ADR-003-dma-interop.md).  
_Avoid_: reading `Dma*` types as device-memory or Kernel DMA Protection; sticky intermediate failures as authoritative

**Smoke** — Hyper-V plumbing acceptance (`Test` lane, Local+autoLogon, Pro).  
_Avoid_: treating Smoke alone as Primary wipe confidence

**Host Apply (S5)** — Elevated Apply run on the build host, then assert the workdir evidence (`just host-apply`, `tools/apply/`). No Hyper-V and no hardware install — the destructive install is Primary, and it is manual.  
_Avoid_: “metal” (retired name — it never touched hardware); treating a Test-lane Host Apply as wipe media

**Gate B** — Pre-wipe host evidence that Release + package-strict Output ISO is ready to Flash. Not a completed Primary install. The predicate is `HostReview.IsGateB` (Release ∧ package-strict).  
_Avoid_: calling Gate B “Primary”; selling soft Host Apply Release as wipe media; re-deriving Gate B from lane alone or package-strict alone

**Primary** — Release `samples/sl7.profile.json` safe to wipe primary SL7 after Gate B + real install evidence in-repo. Details: [DESIGN](docs/DESIGN.md#acceptance).  
_Avoid_: shipping recovery images; treating Gate B alone as wipe-proven; gating Primary on a tracking issue; treating Flash as Primary proof

**Image quality** — Run override `Test` | `Release` (not Profile).

**Install engine** — WinPE apply only (no Setup `/legacy`).

**Debloat** — Remove-list posture for AppX / capabilities / optional features. Profile fields are `debloat.*`. Host presets (`recommended`, Acceptance, empty) expand to lists; never write preset names into JSON.  
_Avoid_: Keep-flag (retired name); keep-list polarity; BCU; CDM as primary; Profile preset names

**Shell** — Winlogon replacement during Provisioning tenure only.  
_Avoid_: calling Wizard UI chrome “Shell”

**Wizard** — Avalonia front end over HostCompile: Source → Account → Software → Review; Phase B elevated Apply.  
_Avoid_: DISM or second planner in UI

**Package catalog** — `config/packages.json`: **chip** key ≠ Profile install id. A chip is one Wizard toggle (`ChipItem`); its key is UI vocabulary and never reaches JSON.  
_Avoid_: live winget search in Wizard

**Host** — the build machine, always: `tools/host/`, `HostDefaults`, host Servicing, **HostCompile** (compile an image on the host). Cli and Wizard are *front ends*, not hosts.  
_Avoid_: “host” for a UI shell or a process that owns a window

## Coined terms

Short words that carry weight in type names. They are kept because no generic alternative says as much — but only if they mean one thing.

**Evidence** — JSON WinMint emits so a harness can assert what happened (`IEvidenceSink`, `evidence.json`, S4/S5 bars). Never read back to decide the next phase.  
_Avoid_: calling Prepared-media publication Evidence; reading Evidence to decide a Prepared-media hit

**Prepared-media audit** — typed `prepared-media.json` ImageServicing merges into `evidence.json` after Apply. Not publication, not a control-plane input, not Evidence the harness reads to decide the next phase.  
_Avoid_: treating the audit sidecar as a HostCompile input; re-hashing Output ISO in C# when `logs/digests.json` already has the digest

**Proof** — `config/packages.proof.json`: catalog ids verified against live winget/scoop, content-hashed so `just check` can enforce freshness offline. Attests to the *catalog*, not to a run.

**Digest** — a sha256 of an artifact under `logs/digests.json`. Not a synonym for evidence or proof.  
_Avoid_: “receipt” for any of these three; calling a Digest Authenticode or signed

**Posture** — product-constant settings applied with no Profile toggle (`ProductPosture`, [ADR-009](docs/decisions/ADR-009-product-constant-policies.md)).

**Tenure** — the window in which Supervisor *is* the Shell, from first paint to unlock (`TenureState`).

**Stamp** — write a durable setting into a hive or profile skeleton, offline or live (`Stamp-*.ps1`, `ShellStamp`, `AccountStamp`).

**Kernel** — one elevated `servicing/*.ps1` doing exactly one opcode. Parameter hashtables only, never Profile JSON.

**Lane** — the `Test` | `Release` image-quality run override, and the `ExportWim` params it implies.  
_Avoid_: calling a GitHub Release “Release” without GitHub; signed Release; treating Authenticode as a Lane property

**Quiet** — the always-on noise removal a user did not ask for and cannot opt out of (`Win32WorkstationQuiet`, Wizard "quiet" copy).

**Residue** — WinMint's own files left in the guest after a green FirstLogon; the cleaner erases them ([ADR-008](docs/decisions/ADR-008-residual-minimization.md)).

**Skel** — `payload/shell-skel`: the one-shot profile skeleton copied into the user profile at `shell.stamp`.

**Safety net** — a live re-check that repairs what the offline pass should already have done (`debloat.appx.safetyNet`).

**Marks** — HKLM `Deprovisioned` keys that make an AppX removal survive a feature update.
