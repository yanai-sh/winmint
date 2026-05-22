mod components;
mod intent;
mod state;
mod theme;

use std::borrow::Cow;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use components as ui;
use gpui::{
    div,
    prelude::*,
    px,
    size,
    App,
    Application,
    AssetSource,
    Bounds,
    Context,
    Div,
    ExternalPaths,
    SharedString,
    TitlebarOptions,
    Window,
    WindowBackgroundAppearance,
    WindowBounds,
    WindowControlArea,
    WindowOptions,
};
use state::{
    BuildIntent, BuildRunState, ManifestViewState, SourceProbeState, SourceProbeStatus, ViewState,
    SPLASH_STATUS_PICK,
};

struct Assets {
    base: PathBuf,
}

impl AssetSource for Assets {
    fn load(&self, path: &str) -> gpui::Result<Option<Cow<'static, [u8]>>> {
        fs::read(self.base.join(path))
            .map(|data| Some(Cow::Owned(data)))
            .map_err(Into::into)
    }

    fn list(&self, path: &str) -> gpui::Result<Vec<SharedString>> {
        fs::read_dir(self.base.join(path))
            .map(|entries| {
                entries
                    .filter_map(|entry| {
                        entry
                            .ok()
                            .and_then(|entry| entry.file_name().into_string().ok())
                            .map(SharedString::from)
                    })
                    .collect()
            })
            .map_err(Into::into)
    }
}

struct WinMintGpui {
    intent: BuildIntent,
    source: SourceProbeState,
    build_run: BuildRunState,
    manifest: ManifestViewState,
    view: ViewState,
}

impl WinMintGpui {
    fn new(custom_titlebar: bool) -> Self {
        Self {
            intent: BuildIntent::default(),
            source: SourceProbeState::default(),
            build_run: BuildRunState::default(),
            manifest: ManifestViewState::default(),
            view: ViewState::new(custom_titlebar),
        }
    }

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
        self.source.status = SourceProbeStatus::Preparing;
        self.build_run.status = format!(
            "Reading {}.",
            self.source
                .iso_path
                .as_str()
                .rsplit(['\\', '/'])
                .next()
                .unwrap_or(self.source.iso_path.as_str())
        )
        .into();

        self.schedule_source_ready(cx);
        cx.notify();
    }

    fn schedule_source_ready(&mut self, cx: &mut Context<Self>) {
        self.source.generation = self.source.generation.wrapping_add(1);
        let gen = self.source.generation;
        cx.spawn(async move |entity, async_cx| {
            async_cx
                .background_executor()
                .timer(Duration::from_millis(650))
                .await;
            let _ = entity.update(async_cx, |this, cx| {
                if this.source.generation != gen {
                    return;
                }
                if !matches!(this.source.status, SourceProbeStatus::Preparing) {
                    return;
                }
                this.source.status = SourceProbeStatus::Ready;
                this.build_run.status = format!(
                    "Source ready: {}",
                    this.source
                        .iso_path
                        .as_str()
                        .rsplit(['\\', '/'])
                        .next()
                        .unwrap_or(this.source.iso_path.as_str())
                )
                .into();
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

    fn apply_external_paths(&mut self, paths: &ExternalPaths, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(first) = paths.paths().first() {
            self.set_iso_path(first.to_string_lossy().into_owned().into(), window, cx);
        }
    }

    fn prompt_iso_path(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !matches!(self.source.status, SourceProbeStatus::Empty) {
            return;
        }
        // Capture viewport before the async spawn so dimensions survive.
        let vp = window.viewport_size();
        let vp_w: f32 = vp.width.into();
        let vp_h: f32 = vp.height.into();

        if let Some(p) = rfd::FileDialog::new()
            .set_title("Choose Windows ISO")
            .add_filter("ISO files", &["iso"])
            .pick_file()
        {
            self.source.mount_viewport_w = vp_w;
            self.source.mount_viewport_h = vp_h;
            self.set_iso_path_after_viewport(p.to_string_lossy().into_owned().into(), cx);
        }
    }

    fn write_intent(&mut self, cx: &mut Context<Self>) {
        let intent_payload = intent::build_gpui_intent(
            &self.source.iso_path.to_string(),
            &self.intent.architecture.to_string(),
            &self.intent.computer_name.to_string(),
            &self.intent.account_name.to_string(),
            self.intent.selected_groups.as_slice(),
            self.intent.toolkit,
            self.intent.desktop_layers,
        );

        let output_path = intent::intent_relative_path();

        let result = fs::create_dir_all(output_path.parent().unwrap()).and_then(|_| {
            fs::write(
                &output_path,
                serde_json::to_string_pretty(&intent_payload).unwrap(),
            )
        });

        self.build_run.status = match result {
            Ok(()) => format!("Wrote {}", output_path.display()).into(),
            Err(error) => format!("Could not write intent: {error}").into(),
        };
        cx.notify();
    }

    fn source_display_tail(&self) -> String {
        let s = self.source.iso_path.as_str();
        if s.len() <= 48 {
            return s.to_string();
        }
        format!("…{}", &s[s.len().saturating_sub(45)..])
    }

    fn footer_status(&self) -> SharedString {
        if self.manifest.manifest_path.is_empty() {
            return self.build_run.status.clone();
        }
        format!(
            "{} · Manifest {}",
            self.build_run.status,
            self.manifest.manifest_path
        )
        .into()
    }

    fn render_toolbar(&self) -> impl IntoElement {
        div()
            .absolute()
            .top(px(0.0))
            .left(px(0.0))
            .right(px(0.0))
            .h(px(72.0))
            .child(ui::titlebar_hit_regions())
            .child(
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

    fn render_source_body(&self, _window: &mut Window, cx: &mut Context<Self>) -> Div {
        let source_panel = match self.source.status {
            SourceProbeStatus::Empty => ui::iso_landing_well("splash-iso-well")
                .on_drop(cx.listener(|this, paths: &ExternalPaths, window, cx| {
                    this.apply_external_paths(paths, window, cx);
                }))
                .on_click(cx.listener(|this, _, window, cx| {
                    this.prompt_iso_path(window, cx);
                }))
                .into_any_element(),
            SourceProbeStatus::Preparing => ui::source_preparing_panel(
                self.source
                    .iso_path
                    .as_str()
                    .rsplit(['\\', '/'])
                    .next()
                    .unwrap_or(self.source.iso_path.as_str())
                    .to_string(),
            )
            .into_any_element(),
            SourceProbeStatus::Ready => div()
                .w_full()
                .h(px(230.0))
                .flex()
                .flex_col()
                .justify_center()
                .gap_4()
                .rounded_md()
                .border_1()
                .border_color(theme::color::border_muted())
                .bg(theme::color::surface())
                .p_6()
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .gap_3()
                        .child(ui::detail_row("ISO", self.source_display_tail()))
                        .child(ui::detail_row("Architecture", self.intent.architecture.to_string())),
                )
                .child(
                    div()
                        .w_full()
                        .flex()
                        .flex_wrap()
                        .gap_3()
                        .justify_start()
                        .items_center()
                        .child(
                            ui::primary_button("continue-source", "Continue").on_click(cx.listener(
                                |this, _, _, cx| {
                                    this.write_intent(cx);
                                },
                            )),
                        )
                        .child(
                            ui::secondary_button("pick-different", "Choose a different ISO…")
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.reset_source_pick(cx);
                                })),
                        ),
                )
                .into_any_element(),
        };

        let title = "Source";
        let hint = match self.source.status {
            SourceProbeStatus::Empty => SPLASH_STATUS_PICK,
            SourceProbeStatus::Preparing => "Reading source.",
            SourceProbeStatus::Ready => "Source ready.",
        };

        div()
            .w_full()
            .max_w(px(760.0))
            .flex()
            .flex_col()
            .gap_8()
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap_3()
                    .child(ui::prose_title(title))
                    .child(ui::prose_hint(hint)),
            )
            .child(
                div()
                    .w_full()
                    .child(source_panel),
            )
    }

    fn render_wizard_shell(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        div()
            .flex_1()
            .w_full()
            .flex()
            .overflow_hidden()
            .child(ui::step_rail(self.view.stage as usize))
            .child(
                div()
                    .flex_1()
                    .flex()
                    .flex_col()
                    .min_w(px(0.0))
                    .child(
                        div()
                            .flex_1()
                            .w_full()
                            .flex()
                            .items_center()
                            .justify_center()
                            .px_12()
                            .pt(px(88.0))
                            .pb(px(48.0))
                            .child(self.render_source_body(window, cx)),
                    )
                    .child(ui::status_footer(self.footer_status())),
            )
    }
}

impl Render for WinMintGpui {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let mut frame = ui::app_frame().relative();

        frame = frame.when(self.view.custom_titlebar, |fr| fr.child(self.render_toolbar()));

        frame = frame.child(self.render_wizard_shell(window, cx));

        frame
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let system_titlebar = args
        .iter()
        .any(|a| a == "--system-titlebar" || a == "--native-titlebar");
    let custom_titlebar = !system_titlebar;

    Application::new().with_assets(Assets {
        base: PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join(".."),
    }).run(move |cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(1120.0), px(740.0)), cx);
        let title: SharedString = "WinMint".into();
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some(title),
                appears_transparent: custom_titlebar,
                ..Default::default()
            }),
            window_background: WindowBackgroundAppearance::Opaque,
            window_min_size: Some(size(
                px(theme::WINDOW_MIN_WIDTH),
                px(theme::WINDOW_MIN_HEIGHT),
            )),
            ..Default::default()
        };
        cx.open_window(options, move |_, cx| {
            cx.new(|_| WinMintGpui::new(custom_titlebar))
        })
        .unwrap();
    });
}
