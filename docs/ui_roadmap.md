# GPUI UI Roadmap

Last reviewed: 2026-05-17

Current primary GUI: `apps/WinMint.GPUI`, pinned to `gpui = "0.2.2"`.

## Stance

WinMint should remain headless-first. The CLI, profile contracts, engine, setup
scripts, reports, and FirstLogon agent are the product. A GUI is a pleasant
control surface for creating intent, watching work, and inspecting output.

GPUI is now the active UI direction. WPF is deprecated and should remain a
legacy fallback while the backend is finalized. GPUI is native Rust UI, not
WebView2. The upside is a fast, polished, Zed-flavored app shell with direct
access to platform windows, input, menus, file prompts, and GPU-rendered views.
The cost is that GPUI is pre-1.0, tied closely to Zed, and currently more of a
low-level app framework than a batteries-included control library.

Keep the rule:

```text
UI creates intent.
Engine performs work.
Reports explain work.
FirstLogon finishes live-user setup.
```

For GPUI, that means:

- GPUI writes or previews `BuildProfile.json` intent.
- PowerShell remains the bridge to existing profile services.
- The engine never moves into Rust UI callbacks.
- WPF can stay as a deprecated fallback, but new UI product work belongs in GPUI.

## Current Priority

Backend finalization and polish are the top priority. GPUI should not outrun the
CLI/profile/engine contract. Reports, audits, and manifest viewing are roadmap
items for GPUI after the backend is stable.

## Current Lab

The lab already does the right thing architecturally:

- `apps/WinMint.GPUI` is isolated from the shipped PowerShell runtime.
- `tools/gpui/Start-GpuiLab.ps1` handles Rust, MSVC, LLVM, and titlebar
  launch differences.
- The GPUI app writes `output/gpui/ui-intent.json`.
- `tools/gpui/New-GpuiLabBuildProfile.ps1` converts that intent through the
  existing UI bridge into a real `BuildProfile.json`.

That boundary should survive every experiment.

## Features Worth Using

| GPUI Feature | Why It Matters For WinMint | How To Use It |
|--------------|----------------------------|---------------|
| `Application` + `App::open_window` | Simple native shell without WPF/XAML ceremony. | One primary centered window using **staged cinematic beats**, not dashboard rails — full-bleed focus per step. |

| `WindowOptions` | Useful native window settings: bounds, focus, visibility, window kind, minimum size, background, resizable/minimizable flags. | Set stable minimum sizes and centered launch bounds. Use `WindowKind::Dialog` only for focused secondary flows. |
| Transparent titlebar | `TitlebarOptions.appears_transparent` is the API for hiding the default system titlebar on macOS/Windows so the app can draw its own. | Keep this as the default lab path. Also keep `-SystemTitlebar` to compare against plain system chrome. |
| `WindowControlArea` | Maps app-rendered regions to platform hit-test behavior: drag, close, maximize, minimize. | Use for a custom titlebar that still behaves like a real Windows window. Be explicit that our icons are app-rendered, not GPUI stock controls. |
| `Window::show_window_menu` and `start_window_move` | Lets custom chrome expose system behavior beyond just close/min/max. | Add right-click or icon-click system menu support if the custom titlebar stays. |
| Entity-backed state | GPUI models and views are `Entity` values owned by the app context. | Split lab state into `BuildIntent`, `SourceProbeState`, `BuildRunState`, and `ManifestViewState` instead of one growing view struct. |
| `Render` + styled `div` elements | High-level UI can be built declaratively with a Tailwind-like API. | Good fit for compact cards, segmented group selectors, status rows, and a build timeline. Create a small local theme module before styles spread everywhere. |
| Low-level `Element` and `canvas` | Gives control for custom drawing and efficient views when needed. | Reserve for build phase timeline, shell preview, or log decorations. Do not use it for ordinary buttons and form rows yet. |
| Actions and key contexts | GPUI has explicit actions, key bindings, and context-scoped dispatch. | Add shortcuts for write profile, run dry run, start build, cancel process, open output, reveal manifest, and toggle logs. |
| Focus and text input primitives | The input example shows IME-aware text handling, focus handles, selection, clipboard, and key bindings. | Use cautiously. Profile fields need source path, computer/account names, and filters, but building every input from scratch can get expensive. |
| Platform path prompts | `App::prompt_for_paths` and `PathPromptOptions` can open native path pickers; `prompt_for_new_path` supports save destinations. | Use for source ISO/UUP folder selection and output destination. Test Windows behavior before relying on it. |
| File drop events | `FileDropEvent` and `ExternalPaths` allow OS file drops into the window. | Add "drop ISO or UUP folder here" on the source panel. This could make the GUI feel genuinely nicer than WPF. |
| Clipboard APIs | `read_from_clipboard` and `write_to_clipboard` are available through app context. | Useful for paste ISO path, copy CLI command, copy report path, copy manifest summary. |
| App menus | `set_menus`, `Menu`, and `MenuItem` support platform menus tied to actions. | Add a minimal Debug menu: open output, reveal profile, reveal manifest, open docs, quit. Keep it tiny. |
| Prompts | `Window::prompt` can show platform or custom prompts and returns an async receiver. | Use for source-prep consent, destructive output overwrite confirmation, and build failure details. |
| Async executor | GPUI has an executor integrated with the platform event loop. | Run nonblocking source probes, profile conversion, dry-run launches, log tailing, and manifest parsing. Spawn PowerShell processes outside the render path. |
| `UniformList` | Efficient uniform-height list rendering with tracked scroll state. | Use for logs, package/AppX removal preview, driver list, manifest actions, and warning tables. |
| Images, SVG, GIF, animations | Examples cover raster images, SVG rendering, opacity, and animation. | Nice for a shell preview or build status visualization, but keep it decorative and optional. |
| `#[gpui::test]` and `TestAppContext` | GPUI can test app behavior with simulated platform input, clipboard, prompts, and path selections. | Add Rust tests once the intent model is separated from rendering. Test selected groups, generated intent JSON, prompts, path selection, and action bindings. |

## Design Direction

Ship a **cinematic staged flow**, not a persistent dashboard or a direct WPF
screen port:

- **Source**: installer capture (`ISOPath` intent), native browse dialog,
  Explorer drop targets, then PowerShell-backed readiness.
- **Profile Groups**: additive posture atop implicit `Minimal`; no debloat or
  performance choice matrix.
- **Developer Options**: appears only when `Developer` is selected.
- **Desktop UI Options**: appears only when `DesktopUI` is selected.
- **Identity And Disk**: account, target device, edition mode, and explicit disk
  mode/layout intent.
- **Review**: terse receipt, attached-source preview, explicit profile write.
- **Build**: run/supervise the existing CLI and render progress.

Optional groups remain coarse (`Minimal`, `Developer`, `CopilotPlus`, `Gaming`, `DesktopUI`). Conditional beats appear **only where** AGENTS/UI contract requires real knobs today.

## Phased Plan

### Phase 0: Keep The Lab Honest

- Keep GPUI in `apps/WinMint.GPUI`.
- Keep generated state in `output/gpui/`.
- Keep `-SystemTitlebar` as an escape hatch.
- Keep build scripts Windows-native and PowerShell-driven.
- Pin GPUI and expect API churn.

Exit criteria:

- `Start-GpuiLab.ps1 -BuildOnly` works on the active Windows toolchain.
- The app can write intent and the bridge can create `BuildProfile.json`.

### Phase 1: Real Profile Authoring

Turn the lab from hardcoded sample state into a small profile author:

- Add Rust structs for the GPUI-side intent model (**partial**: `intent.rs`
  structs for toolkit/desktop layers JSON; fuller typed settings model remains
  TBD).
- Preserve PowerShell as the source of truth for profile derivation.
- Add source ISO/UUP path field. If the user already has a final UUP-generated
  ISO, the UI should guide them to provide the ISO directly; UUP input means a
  conversion zip that WinMint prepares or validates. (**landing beat + ISOPath**
  in intent.)
- Add native path prompt through `prompt_for_paths`. (**done**.)
- Add file-drop support for ISO/UUP source. (**done** via `ExternalPaths` on the landing well.)
- Add action/key binding for "write intent". (**Deferred — lab is mouse-first until shell and flows stabilize.**)
- Show the bridge command and last generated profile path. (**hint on Finish beat** references `tools\gpui\New-GpuiLabBuildProfile.ps1`; surfaced path/recency polish still optional.)

Exit criteria:

- A basic source path plus selected groups produces a valid profile through
  `New-UiBuildProfile.ps1`.
- No build decisions are duplicated in Rust.

### Phase 2: Source Probe And Validation

Use GPUI async work for fast feedback:

- Spawn a PowerShell source probe rather than parsing Windows images in Rust.
- Display architecture, edition candidates, and UUP state.
- Show warnings for missing ISO, unsupported source shape, or arch mismatch.
- Add a native prompt for UUP network/conversion acknowledgement.

Exit criteria:

- The UI can explain whether a selected source is ready before launch.
- Failed probes never block rendering or freeze the window.

### Phase 3: Build Console

Let GPUI supervise existing scripts:

- Launch CLI dry run/build through a PowerShell bridge.
- Stream stdout/stderr into a `UniformList`.
- Track process status in `BuildRunState`.
- Provide cancel, reveal output, copy command, and retry actions.
- Keep elevation handoff explicit and outside GPUI magic.

Exit criteria:

- GPUI can run `WinMint-CLI.ps1 -DryRun` and show structured progress without
  moving build logic into Rust.

### Phase 4: Manifest Viewer

Make reports feel first-class:

- Load `BuildManifest.json` after a run.
- Show build inputs, output paths, source details, warnings, removed AppX list,
  staged setup files, and FirstLogon plan.
- Use `UniformList` for long tables.
- Add copy/reveal actions for paths and commands.

Exit criteria:

- A completed build can be audited from GPUI without reading raw logs.

### Phase 5: Polish And Tests

Only polish once the profile and run loop are real:

- Extract theme tokens for colors, spacing, type, and controls.
- Add GPUI tests around intent generation, group selection, path prompts,
  clipboard actions, and prompt handling.
- Add smoke tests for the PowerShell bridge scripts.
- Retire WPF to legacy fallback status and promote GPUI only after the backend
  contract is stable enough that the UI can stay thin.

Exit criteria:

- The GPUI app can be trusted as a personal GUI while the CLI remains the real
  build surface.

## Open Questions

- Does `prompt_for_paths` feel native and reliable enough on Windows ARM64?
- Should text input use GPUI examples directly, a small local wrapper, or a
  component crate later?
- Can GPUI file drop reliably deliver paths from Windows Explorer?
- How much of Zed's UI crate should be studied or copied for patterns before
  writing local controls?
- Is custom chrome worth the maintenance, or should the lab default back to
  plain system titlebar after the experiment?

## Watchouts

- GPUI is pre-1.0. Expect source churn, especially outside Zed.
- Docs are improving but still sparse; the Zed source and examples are part of
  the learning path.
- The current docs still mention macOS/Linux as the supported getting-started
  path, even though the crate has Windows platform code and this lab builds on
  Windows ARM64.
- GPUI is not a WebView2 shell. If a future UI needs web-native component
  ecosystems, Tauri or a WebView2 host remains a separate decision.
- Custom titlebar support is native in the sense of platform hit-testing, but
  the visuals are ours. Do not treat our minimize/maximize/close glyphs as GPUI
  defaults.
- Do not reimplement profile defaults, AppX policy, package source policy, or
  UUP conversion policy in Rust.

## Near-Term Backlog

1. Split `WinMintGpui` state into intent and view state.
2. Add native source picker via `PathPromptOptions`.
3. Add file drop for ISO/UUP source path.
4. Add `actions!` for write intent, dry run, reveal output, and quit.
5. Add a `UniformList` log/status panel.
6. Add a manifest viewer stub that reads `output/gpui/BuildManifest.json`
   when present.
7. Add one GPUI test for group selection and intent JSON generation.

## References

- [GPUI home and examples](https://www.gpui.rs/)
- [GPUI crate docs](https://docs.rs/gpui/latest/gpui/)
- [WindowOptions](https://docs.rs/gpui/latest/gpui/struct.WindowOptions.html)
- [TitlebarOptions](https://docs.rs/gpui/latest/gpui/struct.TitlebarOptions.html)
- [WindowControlArea](https://docs.rs/gpui/latest/gpui/enum.WindowControlArea.html)
- [UniformList](https://docs.rs/gpui/latest/gpui/struct.UniformList.html)
- [Zed GPUI examples](https://github.com/zed-industries/zed/tree/main/crates/gpui/examples)
- [Local GPUI app](../apps/WinMint.GPUI/README.md)
