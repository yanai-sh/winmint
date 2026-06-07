mod actions;
mod assets;
mod bridge;
mod components;
mod intent;
mod screens;
mod state;
mod theme;

use std::env;
use std::fs;
use std::sync::Arc;
use std::time::Duration;

use actions::{Back, Next};
use components as ui;
use gpui::{
    div, prelude::*, px, size, AnyElement, App, Application, Bounds, Context, Div, ExternalPaths,
    FocusHandle, Focusable, Image, PathPromptOptions, SharedString, TitlebarOptions, Window,
    WindowBackgroundAppearance, WindowBounds, WindowControlArea, WindowDecorations, WindowOptions,
};
use state::{
    BuildIntent, BuildRunState, ManifestViewState, SourceProbeState, SourceProbeStatus, ViewState,
    WizardStep, SPLASH_STATUS_PICK,
};

/// Root view. Owns the wizard state and routes rendering to the current screen.
/// State lives in fields (not a separate entity) since only this view touches it;
/// `screens::*` are descendant modules and read these fields directly.
struct WinMintApp {
    step: WizardStep,
    intent: BuildIntent,
    source: SourceProbeState,
    build_run: BuildRunState,
    manifest: ManifestViewState,
    view: ViewState,
    focus_handle: FocusHandle,
    splash_logo: Arc<Image>,
    hero_logo: Arc<Image>,
    titlebar_logo: Arc<Image>,
}

impl WinMintApp {
    fn new(custom_titlebar: bool, cx: &mut Context<Self>) -> Self {
        Self {
            step: WizardStep::Source,
            intent: BuildIntent::default(),
            source: SourceProbeState::default(),
            build_run: BuildRunState::default(),
            manifest: ManifestViewState::default(),
            view: ViewState::new(custom_titlebar),
            focus_handle: cx.focus_handle(),
            splash_logo: assets::load_brand_logo(&[
                theme::asset::logo(),
                theme::asset::full_logo(),
                theme::asset::simple_logo(),
            ]),
            hero_logo: assets::load_brand_logo(&[
                theme::asset::hero_ui_logo(),
                theme::asset::hero_logo(),
                theme::asset::logo(),
            ]),
            titlebar_logo: assets::load_brand_logo(&[
                theme::asset::simple_ui_logo(),
                theme::asset::simple_logo(),
                theme::asset::full_squircle_ui_logo(),
                theme::asset::logo(),
                theme::asset::full_squircle_logo(),
            ]),
        }
    }

    // ── Navigation ──────────────────────────────────────────────────────────

    /// Whether the current step permits advancing. Source requires a ready probe.
    fn can_advance(&self) -> bool {
        match self.step {
            // Eager: a chosen ISO is enough to proceed. The background probe only
            // enriches the source card; it never gates navigation.
            WizardStep::Source => !self.source.iso_path.is_empty(),
            _ => true,
        }
    }

    fn advance(&mut self, cx: &mut Context<Self>) {
        if self.can_advance() && !self.step.is_last() {
            self.step = self.step.next();
            cx.notify();
        }
    }

    fn retreat(&mut self, cx: &mut Context<Self>) {
        if !self.step.is_first() {
            self.step = self.step.prev();
            cx.notify();
        }
    }

    fn on_next(&mut self, _: &Next, _: &mut Window, cx: &mut Context<Self>) {
        self.advance(cx);
    }

    fn on_back(&mut self, _: &Back, _: &mut Window, cx: &mut Context<Self>) {
        self.retreat(cx);
    }

    // ── Source selection + probe (shared across the Source screen) ───────────

    fn reset_source_pick(&mut self, cx: &mut Context<Self>) {
        self.source.reset();
        self.build_run.status = SPLASH_STATUS_PICK.into();
        cx.notify();
    }

    fn set_iso_path(&mut self, path: SharedString, window: &mut Window, cx: &mut Context<Self>) {
        let vp = window.viewport_size();
        self.source.mount_viewport_w = vp.width.into();
        self.source.mount_viewport_h = vp.height.into();
        self.set_iso_path_after_viewport(path, cx);
    }

    fn set_iso_path_after_viewport(&mut self, path: SharedString, cx: &mut Context<Self>) {
        if !matches!(self.source.status, SourceProbeStatus::Empty) {
            return;
        }
        if path.is_empty() {
            return;
        }
        if !path.as_str().to_ascii_lowercase().ends_with(".iso") {
            self.build_run.status = "Choose a Windows ISO file.".into();
            cx.notify();
            return;
        }

        self.intent.architecture = Self::architecture_hint(path.as_str()).into();
        self.source.iso_path = path;
        self.source.iso_size = fs::metadata(self.source.iso_path.as_str())
            .map(|m| human_size(m.len()))
            .unwrap_or_default()
            .into();
        self.source.status = SourceProbeStatus::Preparing;
        self.source.error = "".into();
        self.source.editions.clear();
        self.source.detected_architecture = "".into();
        self.build_run.status = format!(
            "Selected {}.",
            self.source
                .iso_path
                .as_str()
                .rsplit(['\\', '/'])
                .next()
                .unwrap_or(self.source.iso_path.as_str())
        )
        .into();

        self.write_intent(cx);
        self.build_run.status = "Mounting ISO.".into();
        self.probe_source(cx);
        self.start_source_spinner(cx);
        cx.notify();
    }

    fn start_source_spinner(&mut self, cx: &mut Context<Self>) {
        let gen = self.source.generation;
        cx.spawn(async move |entity, async_cx| loop {
            async_cx
                .background_executor()
                .timer(Duration::from_millis(80))
                .await;

            let keep_spinning = entity
                .update(async_cx, |this, cx| {
                    let active = this.source.generation == gen
                        && matches!(this.source.status, SourceProbeStatus::Preparing);
                    if active {
                        this.build_run.spinner_phase = this.build_run.spinner_phase.wrapping_add(1);
                        cx.notify();
                    }
                    active
                })
                .unwrap_or(false);

            if !keep_spinning {
                break;
            }
        })
        .detach();
    }

    fn probe_source(&mut self, cx: &mut Context<Self>) {
        self.source.generation = self.source.generation.wrapping_add(1);
        let gen = self.source.generation;
        let path = self.source.iso_path.to_string();
        let repo_root = bridge::repo_root();
        cx.spawn(async move |entity, async_cx| {
            let probe = async_cx
                .background_executor()
                .spawn(async move { bridge::run_source_probe(repo_root, path) })
                .await;
            let _ = entity.update(async_cx, |this, cx| {
                if this.source.generation != gen {
                    return;
                }
                if !matches!(this.source.status, SourceProbeStatus::Preparing) {
                    return;
                }
                match probe {
                    Ok(metadata) if metadata.ok => {
                        let arch = metadata.architecture.clone();
                        this.source.mark_ready(metadata);
                        if !arch.is_empty() {
                            this.intent.architecture = arch.into();
                        }
                        this.write_intent(cx);
                        this.build_run.status = "Source selected.".into();
                    }
                    Ok(metadata) => {
                        let error = if metadata.error.is_empty() {
                            "Source probe did not return usable metadata.".to_string()
                        } else {
                            metadata.error
                        };
                        this.source.mark_failed(error.clone());
                        this.build_run.status = format!("Source check failed: {error}").into();
                    }
                    Err(error) => {
                        this.source.mark_failed(error.clone());
                        this.build_run.status = format!("Source check failed: {error}").into();
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn architecture_hint(path: &str) -> &'static str {
        let lower = path.to_ascii_lowercase();
        if lower.contains("arm64") || lower.contains("aarch64") {
            "ARM64"
        } else if lower.contains("x64") || lower.contains("amd64") {
            "x64"
        } else {
            "Unknown"
        }
    }

    fn apply_external_paths(
        &mut self,
        paths: &ExternalPaths,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if let Some(first) = paths.paths().first() {
            self.set_iso_path(first.to_string_lossy().into_owned().into(), window, cx);
        }
    }

    fn prompt_iso_path(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !matches!(self.source.status, SourceProbeStatus::Empty) {
            return;
        }
        if self.source.file_picker_open {
            return;
        }
        let vp = window.viewport_size();
        let vp_w: f32 = vp.width.into();
        let vp_h: f32 = vp.height.into();

        self.source.file_picker_open = true;
        self.build_run.status = "Opening file picker.".into();
        cx.notify();

        let paths = cx.prompt_for_paths(PathPromptOptions {
            files: true,
            directories: false,
            multiple: false,
            prompt: Some("Choose Windows ISO".into()),
        });

        cx.spawn(async move |entity, async_cx| {
            let picked = paths
                .await
                .ok()
                .and_then(Result::ok)
                .flatten()
                .and_then(|paths| paths.into_iter().next())
                .map(|path| path.to_string_lossy().into_owned());

            let _ = entity.update(async_cx, |this, cx| {
                this.source.file_picker_open = false;
                if let Some(path) = picked {
                    this.source.mount_viewport_w = vp_w;
                    this.source.mount_viewport_h = vp_h;
                    this.set_iso_path_after_viewport(path.into(), cx);
                } else if matches!(this.source.status, SourceProbeStatus::Empty) {
                    this.build_run.status = SPLASH_STATUS_PICK.into();
                    cx.notify();
                }
            });
        })
        .detach();
    }

    fn write_intent(&mut self, cx: &mut Context<Self>) {
        let intent_payload = intent::build_gui_intent(
            self.source.iso_path.as_ref(),
            self.intent.architecture.as_ref(),
            self.intent.computer_name.as_ref(),
            self.intent.account_name.as_ref(),
            self.intent.keep,
            self.intent.edition.as_ref(),
            self.intent.toolkit,
            self.intent.desktop_layers,
            self.intent.form_factor.as_wire(),
        );

        let output_path = intent::intent_relative_path();

        self.build_run.status = match serde_json::to_string_pretty(&intent_payload) {
            Ok(json) => {
                let written = output_path
                    .parent()
                    .map(fs::create_dir_all)
                    .unwrap_or(Ok(()))
                    .and_then(|()| fs::write(&output_path, json));
                match written {
                    Ok(()) => format!("Wrote {}", output_path.display()).into(),
                    Err(error) => format!("Could not write intent: {error}").into(),
                }
            }
            Err(error) => format!("Could not serialize intent: {error}").into(),
        };
        cx.notify();
    }

    fn footer_status(&self) -> SharedString {
        if self.manifest.manifest_path.is_empty()
            && matches!(self.source.status, SourceProbeStatus::Empty)
            && self.build_run.status.as_ref() == SPLASH_STATUS_PICK
        {
            return "".into();
        }

        if self.manifest.manifest_path.is_empty() {
            return self.build_run.status.clone();
        }
        format!(
            "{} · Manifest {}",
            self.build_run.status, self.manifest.manifest_path
        )
        .into()
    }

    // ── Layout ───────────────────────────────────────────────────────────────

    fn render_toolbar(&self) -> impl IntoElement {
        let show_brand_mark = !matches!(self.source.status, SourceProbeStatus::Empty);

        let mut toolbar = div()
            .absolute()
            .top(px(0.0))
            .left(px(0.0))
            .right(px(0.0))
            .h(px(72.0))
            .child(ui::titlebar_hit_regions());

        if show_brand_mark {
            toolbar = toolbar.child(ui::titlebar_brand_mark(self.titlebar_logo.clone()));
        }

        toolbar.child(
            div()
                .absolute()
                .top(px(4.0))
                .right(px(0.0))
                .h(px(32.0))
                .flex()
                .items_center()
                .child(ui::titlebar_button(
                    "window-minimize",
                    "\u{E921}",
                    WindowControlArea::Min,
                    false,
                ))
                .child(ui::titlebar_button(
                    "window-maximize",
                    "\u{E922}",
                    WindowControlArea::Max,
                    false,
                ))
                .child(ui::titlebar_button(
                    "window-close",
                    "\u{E8BB}",
                    WindowControlArea::Close,
                    true,
                )),
        )
    }

    fn render_screen(&self, window: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        match self.step {
            WizardStep::Source => screens::source::render(self, window, cx).into_any_element(),
            WizardStep::Configure => {
                screens::configure::render(self, window, cx).into_any_element()
            }
            WizardStep::Build => screens::build::render(self, window, cx).into_any_element(),
            WizardStep::Review => screens::review::render(self, window, cx).into_any_element(),
        }
    }

    fn render_nav(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let mut row = div()
            .w_full()
            .flex()
            .items_center()
            .justify_between()
            .px_12()
            .pb(px(8.0));

        if self.step.is_first() {
            row = row.child(div());
        } else {
            row = row.child(
                ui::secondary_button("nav-back", "Back")
                    .on_click(cx.listener(|this, _, _, cx| this.retreat(cx))),
            );
        }

        if !self.step.is_last() && self.can_advance() {
            row = row.child(
                ui::primary_button("nav-next", "Next")
                    .on_click(cx.listener(|this, _, _, cx| this.advance(cx))),
            );
        } else {
            row = row.child(div());
        }

        row
    }

    fn render_shell(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        // The step breadcrumb is wizard chrome — show it from Configure onward, not
        // on the Source landing. Pad the content to clear the titlebar when it's absent.
        let show_steps = !matches!(self.step, WizardStep::Source);
        let content_top = if show_steps { px(8.0) } else { px(80.0) };
        div()
            .flex_1()
            .w_full()
            .flex()
            .flex_col()
            .overflow_hidden()
            .map(|shell| {
                if show_steps {
                    let labels: Vec<&'static str> =
                        WizardStep::ORDER.iter().map(|s| s.title()).collect();
                    shell.child(
                        div()
                            .w_full()
                            .flex()
                            .justify_center()
                            .pt(px(80.0))
                            .pb(px(4.0))
                            .child(ui::beat_scrub(&labels, self.step.index())),
                    )
                } else {
                    shell
                }
            })
            .child(
                div().flex_1().flex().min_w(px(0.0)).child(
                    div()
                        .flex_1()
                        .w_full()
                        .flex()
                        .items_center()
                        .justify_center()
                        .px_12()
                        .pt(content_top)
                        .pb(px(24.0))
                        .child(self.render_screen(window, cx)),
                ),
            )
            .child(self.render_nav(cx))
            .child(ui::status_footer(
                self.footer_status(),
                matches!(self.source.status, SourceProbeStatus::Preparing)
                    .then_some(self.build_run.spinner_phase),
            ))
    }
}

/// Human-readable byte size, e.g. 5_368_709_120 -> "5.0 GB".
fn human_size(bytes: u64) -> String {
    const UNITS: [&str; 4] = ["B", "KB", "MB", "GB"];
    let mut size = bytes as f64;
    let mut unit = 0;
    while size >= 1024.0 && unit < UNITS.len() - 1 {
        size /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} B")
    } else {
        format!("{size:.1} {}", UNITS[unit])
    }
}

impl Focusable for WinMintApp {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for WinMintApp {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let mut frame = ui::app_frame()
            .id("winmint-root")
            .relative()
            .key_context("WinMint")
            .track_focus(&self.focus_handle)
            .on_action(cx.listener(Self::on_next))
            .on_action(cx.listener(Self::on_back));

        if self.view.custom_titlebar {
            frame = frame.child(self.render_toolbar());
        }

        frame.child(self.render_shell(window, cx))
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let system_titlebar = args
        .iter()
        .any(|a| a == "--system-titlebar" || a == "--native-titlebar");
    let custom_titlebar = !system_titlebar;

    Application::new()
        .with_assets(assets::Assets {
            base: bridge::repo_root(),
        })
        .run(move |cx: &mut App| {
            actions::bind_keys(cx);

            let bounds = Bounds::centered(None, size(px(1120.0), px(740.0)), cx);
            let title: SharedString = "WinMint".into();
            let options = WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                titlebar: Some(TitlebarOptions {
                    title: Some(title),
                    appears_transparent: custom_titlebar,
                    ..Default::default()
                }),
                // Client decorations let the app own the caption and have the platform
                // honor our `window_control_area` regions (min/max/close, snap layouts).
                // Without this the OS owns the frame and the custom close button is inert.
                window_decorations: Some(if custom_titlebar {
                    WindowDecorations::Client
                } else {
                    WindowDecorations::Server
                }),
                window_background: WindowBackgroundAppearance::Opaque,
                window_min_size: Some(size(
                    px(theme::WINDOW_MIN_WIDTH),
                    px(theme::WINDOW_MIN_HEIGHT),
                )),
                ..Default::default()
            };
            cx.open_window(options, move |window, cx| {
                let view = cx.new(|cx| WinMintApp::new(custom_titlebar, cx));
                let handle = view.read(cx).focus_handle.clone();
                window.focus(&handle);
                view
            })
            .expect("failed to open the WinMint window");
            cx.activate(true);
        });
}
