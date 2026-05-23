mod components;
mod intent;
mod state;
mod theme;

use std::borrow::Cow;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;

use components as ui;
use gpui::{
    div, prelude::*, px, size, App, Application, AssetSource, Bounds, Context, Div, ExternalPaths,
    Image, ImageFormat, SharedString, TitlebarOptions, Window, WindowBackgroundAppearance,
    WindowBounds, WindowControlArea, WindowOptions,
};
use state::{
    BuildIntent, BuildRunState, ManifestViewState, SourceProbeState, SourceProbeStatus,
    UiIsoMetadata, ViewState, SPLASH_STATUS_PICK,
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

struct WinMintGui {
    intent: BuildIntent,
    source: SourceProbeState,
    build_run: BuildRunState,
    manifest: ManifestViewState,
    view: ViewState,
    logo: Arc<Image>,
}

impl WinMintGui {
    fn new(custom_titlebar: bool) -> Self {
        Self {
            intent: BuildIntent::default(),
            source: SourceProbeState::default(),
            build_run: BuildRunState::default(),
            manifest: ManifestViewState::default(),
            view: ViewState::new(custom_titlebar),
            logo: load_brand_logo(),
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
        self.build_run.status = "Source selected.".into();
        self.probe_source(cx);
        cx.notify();
    }

    fn repo_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
    }

    fn probe_source(&mut self, cx: &mut Context<Self>) {
        self.source.generation = self.source.generation.wrapping_add(1);
        let gen = self.source.generation;
        let path = self.source.iso_path.to_string();
        let repo_root = Self::repo_root();
        cx.spawn(async move |entity, async_cx| {
            let probe = async_cx
                .background_executor()
                .spawn(async move { run_source_probe(repo_root, path) })
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
        let intent_payload = intent::build_gui_intent(
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
            self.build_run.status, self.manifest.manifest_path
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
            SourceProbeStatus::Empty => ui::iso_landing_well(
                "splash-iso-well",
                cx.listener(|this, paths: &ExternalPaths, window, cx| {
                    this.apply_external_paths(paths, window, cx);
                }),
                cx.listener(|this, _, window, cx| {
                    this.prompt_iso_path(window, cx);
                }),
            )
            .into_any_element(),
            SourceProbeStatus::Preparing => div()
                .w(px(360.0))
                .flex()
                .items_center()
                .justify_between()
                .gap_4()
                .rounded_md()
                .border_1()
                .border_color(theme::color::border_muted())
                .bg(theme::color::surface())
                .px_4()
                .py_3()
                .child(
                    div()
                        .min_w(px(0.0))
                        .flex()
                        .flex_col()
                        .gap_1()
                        .child(
                            div()
                                .text_sm()
                                .font_weight(gpui::FontWeight::SEMIBOLD)
                                .text_color(theme::color::text())
                                .child("Source selected"),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(theme::color::text_dim())
                                .child(self.source_display_tail()),
                        ),
                )
                .child(
                    ui::secondary_button("pick-different-selected", "Change").on_click(
                        cx.listener(|this, _, _, cx| {
                            this.reset_source_pick(cx);
                        }),
                    ),
                )
                .into_any_element(),
            SourceProbeStatus::Failed => ui::surface()
                .w_full()
                .h(px(250.0))
                .flex()
                .flex_col()
                .justify_center()
                .gap_4()
                .child(
                    div()
                        .flex()
                        .justify_between()
                        .items_center()
                        .child(ui::section_label(
                            "Source check failed",
                            "Choose a different ISO or retry after fixing the source.",
                        ))
                        .child(ui::status_badge(self.source.status)),
                )
                .child(ui::callout(self.source.error.to_string(), true))
                .child(
                    div()
                        .flex()
                        .gap_3()
                        .child(
                            ui::secondary_button("retry-source-probe", "Retry").on_click(
                                cx.listener(|this, _, _, cx| {
                                    this.source.status = SourceProbeStatus::Preparing;
                                    this.build_run.status = "Checking source again.".into();
                                    this.probe_source(cx);
                                    cx.notify();
                                }),
                            ),
                        )
                        .child(
                            ui::secondary_button(
                                "pick-different-after-error",
                                "Choose a different ISO",
                            )
                            .on_click(cx.listener(|this, _, _, cx| {
                                this.reset_source_pick(cx);
                            })),
                        ),
                )
                .into_any_element(),
            SourceProbeStatus::Ready => div()
                .w(px(360.0))
                .flex()
                .items_center()
                .justify_between()
                .gap_4()
                .rounded_md()
                .border_1()
                .border_color(theme::color::border_muted())
                .bg(theme::color::surface())
                .px_4()
                .py_3()
                .child(
                    div()
                        .min_w(px(0.0))
                        .flex()
                        .flex_col()
                        .gap_1()
                        .child(
                            div()
                                .text_sm()
                                .font_weight(gpui::FontWeight::SEMIBOLD)
                                .text_color(theme::color::text())
                                .child("Source selected"),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(theme::color::text_dim())
                                .child(self.source_display_tail()),
                        ),
                )
                .child(
                    ui::secondary_button("pick-different", "Change").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.reset_source_pick(cx);
                        },
                    )),
                )
                .into_any_element(),
        };

        let hint = match self.source.status {
            SourceProbeStatus::Empty => SPLASH_STATUS_PICK,
            SourceProbeStatus::Preparing => {
                "Source selected. WinMint is checking it in the background."
            }
            SourceProbeStatus::Ready => "Source selected.",
            SourceProbeStatus::Failed => "Source needs attention.",
        };

        div()
            .w_full()
            .max_w(px(420.0))
            .flex()
            .flex_col()
            .items_center()
            .gap_4()
            .child(
                div()
                    .w_full()
                    .flex()
                    .flex_col()
                    .items_center()
                    .gap_3()
                    .child(ui::splash_brand_lockup(self.logo.clone()))
                    .child(
                        div()
                            .text_lg()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .text_center()
                            .text_color(theme::color::text())
                            .child("Build a clean Windows workstation ISO."),
                    )
                    .child(
                        div()
                            .text_sm()
                            .text_center()
                            .text_color(theme::color::text_dim())
                            .child(hint),
                    ),
            )
            .child(div().flex().justify_center().child(source_panel))
    }

    fn render_wizard_shell(&self, window: &mut Window, cx: &mut Context<Self>) -> Div {
        div()
            .flex_1()
            .w_full()
            .flex()
            .flex_col()
            .overflow_hidden()
            .child(
                div().flex_1().flex().min_w(px(0.0)).child(
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
                ),
            )
            .child(ui::status_footer(self.footer_status()))
    }
}

fn load_brand_logo() -> Arc<Image> {
    let path = theme::asset::logo();
    match fs::read(&path) {
        Ok(bytes) => {
            eprintln!("WinMint GUI loaded brand logo: {}", path.display());
            Arc::new(Image::from_bytes(ImageFormat::Png, bytes))
        }
        Err(err) => {
            eprintln!(
                "WinMint GUI could not load brand logo '{}': {err}",
                path.display()
            );
            Arc::new(Image::empty())
        }
    }
}

fn run_source_probe(repo_root: PathBuf, path: String) -> Result<UiIsoMetadata, String> {
    let script = repo_root
        .join("tools")
        .join("ui-bridge")
        .join("Get-UiIsoMetadata.ps1");
    let output = Command::new("pwsh")
        .arg("-NoProfile")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(&script)
        .arg("-Path")
        .arg(&path)
        .current_dir(repo_root)
        .output()
        .map_err(|error| format!("Could not start PowerShell source probe: {error}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            return Err(format!(
                "PowerShell source probe exited with {}.",
                output.status
            ));
        }
        return Err(stderr);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str::<UiIsoMetadata>(stdout.trim())
        .map_err(|error| format!("Source probe returned invalid JSON: {error}"))
}

impl Render for WinMintGui {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let mut frame = ui::app_frame().relative();

        frame = frame.when(self.view.custom_titlebar, |fr| {
            fr.child(self.render_toolbar())
        });

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

    Application::new()
        .with_assets(Assets {
            base: PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("..")
                .join(".."),
        })
        .run(move |cx: &mut App| {
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
                cx.new(|_| WinMintGui::new(custom_titlebar))
            })
            .unwrap();
        });
}
