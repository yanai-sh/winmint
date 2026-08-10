# Research: SophiApp 2.0 (Daria) vs WinMint

**Date:** 2026-08-09  
**Question:** What is in-development SophiApp 2.0 on `dev-SophiApp2`, and how does it compare to WinMint?  
**Method:** Primary sources on GitHub (`dev-SophiApp2` tip `7741c83`, 2026-08-02) + WinMint repo docs. Marketing summaries treated as claims to verify.

## Executive summary

**SophiApp 2.0** is a live, post-install **Windows fine-tuning GUI** (WinUI 3 / Windows App SDK unpackaged app) that reads OS state and applies optional tweaks via registry, Group Policy (`LGPO.exe`), AppX APIs, and embedded PowerShell. **WinMint** is a **workstation-state compiler**: Profile → offline ISO/USB servicing → FirstLogon Provisioning Supervisor, so the user does not run a separate debloat GUI after Setup. Feature *topics* overlap (AppX remove, OneDrive, Copilot/AI, telemetry-ish policies, optional DoH on WinMint’s side), but the **product job and mutation venue** are different — complementary more than competitive.

## Verified SophiApp 2.0 facts

| Claim | Verdict | Source |
| --- | --- | --- |
| Active rewrite on `dev-SophiApp2` | **Verified** — tip merge 2026-08-02; frequent 2026 commits (AI, UWP/TaskScheduler refactor, requirements chain) | [commits/dev-SophiApp2](https://github.com/Sophia-Community/SophiApp/commits/dev-SophiApp2) |
| Codename / product name “Daria” / 2.0 | **Verified in README caution** | [README `dev-SophiApp2`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/README.md) |
| Avoid SophiApp **1.0.97** until 2.0 ships | **Verified** (README still says release target “2025 H2”) | same README caution + [t.me/SophiaNews/3897](https://t.me/SophiaNews/3897) |
| WinUI 3 + Windows App SDK | **Verified** — `UseWinUI`, `Microsoft.WindowsAppSDK` 1.7.x, `net10.0-windows10.0.26100.0`, version `2.716.0` | [`SophiApp.csproj`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/SophiApp.csproj) |
| Unpackaged / portable packaging | **Verified** — `WindowsPackageType=None`, `WindowsAppSDKSelfContained=true` | same csproj |
| App settings not in registry | **Mostly verified** — unpackaged path uses `Settings.json` beside the exe (`SettingsService`); MSIX path would use `ApplicationData.LocalSettings` | [`SettingsService.cs`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/Services/SettingsService.cs) |
| Dynamic UI from schema | **Verified** — embedded `UIMarkup.json` → `ModelService.BuildJsonModelsAsync()` builds checkbox/radio models; ~118 named entries across Privacy / Personalization / System / Security / ContextMenu / Gaming / TaskScheduler | [`ModelService.cs`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/Services/ModelService.cs), [`UIMarkup.json`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/UIMarkup/UIMarkup.json) |
| Live state before toggle | **Verified pattern** — `Accessors` query registry/AppX/CBS; `Mutators` apply | [`Accessors.cs`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/Customizations/Accessors.cs), [`Mutators.cs`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/Customizations/Mutators.cs) |
| Startup OS/API requirements gate | **Verified** — architecture, Defender, hosts file, harmful tweakers, UWP components, BitLocker, UEFI certs, build, etc. | [`RequirementsService.cs`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/Services/RequirementsService.cs) |
| Policy via Microsoft-ish tooling | **Verified** — registry + bundled `Binaries/LGPO.exe` via `GroupPolicyService` | [`GroupPolicyService.cs`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/Services/GroupPolicyService.cs), csproj `LGPO.exe` content |
| Windows AI / Copilot control | **Verified** — UI id `RemoveWindowsAI`; mutator clears WindowsAI/WindowsCopilot policy trees, toggles Recall optional feature, removes/opens Copilot package | Mutators + UIMarkup; commits e.g. `Added RemoveAI functioon` (2026-02-22) |
| OneDrive / UWP uninstall | **Verified** — `OneDrive` mutator; `AppxPackagesService` + `BuildUwpAppModelsAsync` | Services + Customizations |
| Toast-scheduled cleanup | **Verified** — `CleanupTask` mutator; toast sender + `WindowsCleanup` URL protocol → scheduled task under `\Sophia\` | [`AppNotificationService.cs`](https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/src/SophiApp/Services/AppNotificationService.cs) |
| Search / themes / pages | **Verified** — `SearchPage`, theme services, category Views (Privacy, Security, System, UWP, TaskScheduler, …) | `src/SophiApp/Views/` |
| GitHub Actions present | **Verified** — `.github/workflows/SophiApp.yml` (+ Badge.yml); tip workflow still resembles 1.x layout — treat “cloud-verifiable 2.0 zip SHA” as **aspirational** until a 2.0 release artifact + matching Actions log exists | tree on branch |
| Replaces master **1.0.97** WPF stack | **Verified contrast** — published release remains **1.0.97** (2023-07-27); master lineage is .NET Framework 4.8 WPF; `dev-SophiApp2` is the WinUI rewrite | [releases](https://github.com/Sophia-Community/SophiApp/releases), master vs `dev-SophiApp2` csproj |
| **x64-only** | **Verified** — csproj `Platforms`/`RuntimeIdentifiers` = x64; `GetSupportedArchitecture` accepts only AMD64/Intel64 captions | csproj + RequirementsService |
| README still documents WPF-era install story | **Verified** — top-level README on the branch still describes portable `SophiApp.exe` + Chocolatey/Scoop and many 1.x feature bullets; treat as partially stale vs 2.x code | README |

### Architecture sketch (from branch)

```
WinUI 3 Shell (unpackaged, WASDK self-contained)
  → Initialize / RequirementsService (fail or warn gates)
  → ModelService loads UIMarkup.json → UI models
  → Accessors (read) / Mutators (write)
       → RegistryService, GroupPolicyService(+LGPO), AppxPackagesService,
         PowerShellService (embedded PS 7.4 assemblies), ScheduledTaskService,
         HttpService (runtime downloads), AppNotificationService
```

DI-style services under `Services/`, MVVM ViewModels, CommunityToolkit.Mvvm. Customization logic is concentrated in static `Accessors`/`Mutators` rather than one class per tweak.

## Unverified or marketing-only / nuance

| Claim | Status |
| --- | --- |
| “Zero registry overhead” / “leaves no configuration keys” | **Overstated** if read as “never touches registry.” App *settings* are file-based when unpackaged; **tweaks and toast registration write registry/HKCR** (and LGPO pol). Toast path registers `WindowsCleanup` protocol and AUMID keys. |
| “Zero persistent background services” | **Plausible for the app process**; cleanup uses **scheduled tasks** + toasts (persistence by design when enabled). |
| DNS-over-HTTPS providers (Cloudflare/Quad9/Google/AdGuard) in SophiApp 2.0 | **Not found** on `dev-SophiApp2` (no Dns/DoH paths; UIMarkup has NetworkAdaptersSavePower / NetworkDiscovery / NetworkProtection only). May exist in **Sophia Script** CLI or be planned — do not attribute to this branch without new evidence. |
| “VC++ 2015–2026” / “.NET 10 install” | Runtime install **paths exist** (`RedistributablePackageService`; commit “Added install NET 10 function”, 2026-03-10). Exact marketing version strings (e.g. “2015–2026”) should be checked against Mutators before citing. |
| HEVC *install* in 2.0 UI | **Not confirmed** on tip as a first-class install toggle (README still lists it; do not assume parity with 1.x). |
| “Advanced mode” / gear-hidden tweaks | **Not confirmed** on tip (README still describes it; verify Settings UI before citing). |
| “Sanitized troubleshooting logs” / no PII | **Overstated** — Serilog file logging is present; logs can include machine/user context. Safe-to-share claims need a redaction audit, not marketing. |
| “130+ tweaks” | README claim; UIMarkup on tip has **~118** `Name` entries (UWP list is dynamic and separate). |
| Public preview timing | Telegram [SophiaNews/3897](https://t.me/SophiaNews/3897) (NY message): aimed first public preview **H1 2025**, categories done except System at that time, WinUI 3 friction, track branch. README still says **2025 H2**. As of **2026-08** the branch is still active and **no 2.0 GitHub release** — treat schedule as aspirational. |
| “Non-destructive / only documented APIs / anti-cheat safe” | **Intent** matches project messaging (LGPO, optional features, AppX remove). Not independently proven; still registry/policy heavy. WinMint’s own posture is similarly “documented-ish servicing,” not a formal certification. |

## WinMint comparison

WinMint sources: [CONTEXT.md](../../CONTEXT.md), [ARCHITECTURE.md](../ARCHITECTURE.md), [ADR-009](../decisions/ADR-009-product-constant-policies.md), [workstation-compiler spec](../specs/2026-08-05-workstation-compiler-winpe-apply.md).

| Axis | SophiApp 2.0 (Daria) | WinMint |
| --- | --- | --- |
| **Product job** | Interactive post-install tweaker GUI | Compile **Profile** → bootable ISO/USB → unattended install → locked FirstLogon |
| **When it runs** | Anytime on a live desktop | Build host + guest Machine setup / Shell tenure |
| **Mutation surface** | Live OS (registry, GPO, AppX, optional features, tasks) | Offline WIM/hive (ImageServicing) + online FirstLogon jobs (ProvisioningSession); default **online** AppX debloat per workstation-compiler spec |
| **Input contract** | Human clicking toggles (+ UIMarkup schema) | Declarative **Profile** (keep-flag catalogs, packages, policies, DMA) |
| **UI stack** | WinUI 3 + WASDK | C# CLI; Avalonia wizard later; guest splash is Supervisor Direct2D/GDI — **not** WinUI on the ISO |
| **Package model** | Dynamic UWP uninstall list; optional runtime downloads (HEVC install UI unconfirmed on tip) | Catalogued winget/scoop/WSL jobs; product-constant OneDrive uninstall job |
| **AI / Copilot** | Interactive `RemoveWindowsAI` (Recall + Copilot package + policy trees) | `policies.keepCopilot` (default false) + optional AppX remove via preset; EdgeDebloat separate from Copilot keys ([ADR-009](../decisions/ADR-009-product-constant-policies.md)) |
| **DoH** | **Not present** on inspected branch | Optional `policies.dohProvider` FirstLogon job ([ADR-009](../decisions/ADR-009-product-constant-policies.md)) |
| **Telemetry / privacy depth** | Many interactive Privacy toggles (DiagTrack, diagnostic level, advertising ID, …) | Narrower product-constant offline stamps + keep-flag removes; not a 100+ tweak matrix |
| **Portability / residual** | Unpackaged app; settings JSON; OS changes remain; optional Sophia scheduled tasks | Residual minimization after green FirstLogon ([ADR-008](../decisions/ADR-008-residual-minimization.md)); `%ProgramData%\WinMint\` may remain for evidence |
| **Arch** | **x64 only** (rejects non-AMD64/Intel64) | **ARM64-first** product posture |
| **Maturity** | 2.0 in active development; 1.0.97 deprecated; Sophia Script CLI is the maintained non-GUI path | Alpha post backlog 01–30; Smoke / metal verticals |

### Overlap vs complementary

- **Overlap:** AppX debloat, OneDrive removal, Copilot/AI-ish posture, privacy-adjacent policies, redistributables — same *problem space*, different *lifecycle*.
- **WinMint explicitly wants to obsolete the “run SophiApp after Setup” workflow** for its target user (workstation-compiler: “never run a separate post-install debloat tool”).
- **SophiApp still makes sense** when: OS is already installed; user wants interactive exploration/search of ~100 toggles; ongoing maintenance toasts; or x64 machines outside WinMint’s Profile/ISO loop.
- **SophiApp does not replace** WinMint’s Source-ISO legal model, DMA settle, Shell lock, BuildPlan, or ARM64-first packaging story.
- **WinMint does not replace** SophiApp’s broad interactive tweak catalog or toast cleanup UX.

## Implications for WinMint (short)

1. No need to chase SophiApp’s WinUI dynamic-tweak architecture — different product.
2. Where policy topics coincide (Copilot, OneDrive, DoH, AppX), keep WinMint’s **Profile/opcode** model; treat SophiApp/Sophia Script as reference implementations for *how* a live tweak is expressed, not as a UI to embed.
3. SophiApp’s **x64-only** gate is a hard non-overlap with WinMint’s ARM64 host — do not assume binary reuse.
4. “Official API / non-destructive” marketing is ambient in this niche; WinMint’s differentiator remains **compile-once workstation delivery**, not a larger toggle count.

## Sources

- https://github.com/Sophia-Community/SophiApp/tree/dev-SophiApp2  
- https://github.com/Sophia-Community/SophiApp/commits/dev-SophiApp2  
- https://github.com/Sophia-Community/SophiApp/blob/dev-SophiApp2/README.md  
- https://t.me/SophiaNews/3897  
- WinMint: `CONTEXT.md`, `docs/ARCHITECTURE.md`, `docs/decisions/ADR-009-product-constant-policies.md`, `docs/specs/2026-08-05-workstation-compiler-winpe-apply.md`
