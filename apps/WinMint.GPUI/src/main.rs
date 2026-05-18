mod anim;
mod components;
mod intent;
mod theme;

use std::borrow::Cow;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use components as ui;
use gpui::{
    div,
    prelude::*,
    px,
    size,
    Animation,
    AnimationExt,
    App,
    Application,
    AssetSource,
    Bounds,
    Context,
    Div,
    ExternalPaths,
    FontWeight,
    SharedString,
    TitlebarOptions,
    Window,
    WindowBackgroundAppearance,
    WindowBounds,
    WindowControlArea,
    WindowOptions,
};
use intent::{DesktopLayersIntent, ToolkitIntent};

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

/// Stub mount / probe budget for the flight animation. When real `Mount-DiskImage`
/// (or probe) wiring exists, completion should flip `pane` alongside this choreo,
/// adjusting this heuristic only as a UX floor/ceiling.
pub const ESTIMATED_ISO_MOUNT_MS: u64 = 9_800;
pub const BRAND_MERGE_MS: u64 = 1_250;

/// Maximum time before we accelerate the flight past the estimated duration.
/// If mounting is taking longer than this, the animation speeds up so the
/// user isn't watching a finished logo sit idle.
pub const ANIM_CEILING_MS: u64 = 15_000;
pub const BRAND_DOCK_MS: u64 = 1_800;

const SPLASH_STATUS_PICK: &str =
    "Drag and drop your Windows ISO here, or click the well to browse.";

#[derive(Clone, Copy, PartialEq, Eq)]
enum LabPane {
    /// Splash: brand flight + picker (two sub-stages: awaiting path vs choreographed mount).
    Splash,
    /// Mount complete: terse receipt for the CLI bridge story.
    SourceReady,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum SplashMountStage {
    AwaitingSource,
    Mounting,
}

struct WinMintGpui {
    pane: LabPane,
    splash_mount: SplashMountStage,

    iso_path: SharedString,
    architecture: SharedString,
    computer_name: SharedString,
    account_name: SharedString,
    selected_groups: Vec<&'static str>,
    toolkit: ToolkitIntent,
    desktop_layers: DesktopLayersIntent,

    status: SharedString,
    custom_titlebar: bool,

    /// Monotonic guard so a stale mount timer cannot advance state after reset.
    mount_generation: u64,
    mount_started_at: Option<Instant>,

    /// Viewport dimensions captured at mount start so the animation target
    /// doesn't jump if the user resizes mid-flight.
    mount_viewport_w: f32,
    mount_viewport_h: f32,
}

impl WinMintGpui {
    fn new(custom_titlebar: bool) -> Self {
        Self {
            pane: LabPane::Splash,
            splash_mount: SplashMountStage::AwaitingSource,
            iso_path: "".into(),
            architecture: "amd64".into(),
            computer_name: "WinMint".into(),
            account_name: "dev".into(),
            selected_groups: vec!["Minimal"],
            toolkit: ToolkitIntent::default(),
            desktop_layers: DesktopLayersIntent::default(),
            status: SPLASH_STATUS_PICK.into(),
            custom_titlebar,
            mount_generation: 0,
            mount_started_at: None,
            mount_viewport_w: 0.0,
            mount_viewport_h: 0.0,
        }
    }

    fn reset_source_pick(&mut self, cx: &mut Context<Self>) {
        self.mount_generation = self.mount_generation.wrapping_add(1);
        self.pane = LabPane::Splash;
        self.splash_mount = SplashMountStage::AwaitingSource;
        self.iso_path = "".into();
        self.mount_started_at = None;
        self.mount_viewport_w = 0.0;
        self.mount_viewport_h = 0.0;
        self.status = SPLASH_STATUS_PICK.into();
        cx.notify();
    }

    fn schedule_mount_completion(&mut self, cx: &mut Context<Self>) {
        let gen = self.mount_generation;
        cx.spawn(async move |entity, async_cx| {
            async_cx
                .background_executor()
                .timer(Duration::from_millis(ESTIMATED_ISO_MOUNT_MS))
                .await;
            let _ = entity.update(async_cx, |this, cx| {
                if this.mount_generation != gen {
                    return;
                }
                if !matches!(this.splash_mount, SplashMountStage::Mounting) {
                    return;
                }
                this.pane = LabPane::SourceReady;
                this.status = "Installer image is ready.".into();
                cx.notify();
            });
        })
        .detach();
    }

    fn brand_flight_progress(&self) -> f32 {
        match self.splash_mount {
            SplashMountStage::AwaitingSource => 0.0,
            SplashMountStage::Mounting => {
                let Some(started) = self.mount_started_at else {
                    return 0.0;
                };
                let raw = started.elapsed().as_millis() as f32 / BRAND_MERGE_MS as f32;
                (raw * 0.50).clamp(0.0, 0.50)
            }
        }
        .max(if matches!(self.pane, LabPane::SourceReady) {
            let Some(started) = self.mount_started_at else {
                return 1.0;
            };
            let elapsed = started.elapsed().as_millis() as i64 - ESTIMATED_ISO_MOUNT_MS as i64;
            let dock = (elapsed.max(0) as f32 / BRAND_DOCK_MS as f32).clamp(0.0, 1.0);
            0.62 + dock * 0.38
        } else {
            0.0
        })
        .clamp(0.0, 1.0)
    }

    fn brand_activity_clock(&self) -> f32 {
        self.mount_started_at
            .map(|started| started.elapsed().as_secs_f32())
            .unwrap_or(0.0)
    }

    fn set_iso_path(&mut self, path: SharedString, window: &mut Window, cx: &mut Context<Self>) {
        let vp = window.viewport_size();
        self.mount_viewport_w = vp.width.into();
        self.mount_viewport_h = vp.height.into();
        self.set_iso_path_after_viewport(path, cx);
    }

    fn set_iso_path_after_viewport(&mut self, path: SharedString, cx: &mut Context<Self>) {
        if matches!(self.pane, LabPane::SourceReady) {
            return;
        }
        if matches!(self.splash_mount, SplashMountStage::Mounting) {
            return;
        }
        if path.is_empty() {
            return;
        }
        if !path.as_str().to_ascii_lowercase().ends_with(".iso") {
            self.status = "Choose a Windows ISO file.".into();
            cx.notify();
            return;
        }

        self.iso_path = path;
        self.splash_mount = SplashMountStage::Mounting;
        self.mount_started_at = Some(Instant::now());
        self.status = format!(
            "Mounting {}…",
            self.iso_path
                .as_str()
                .rsplit(['\\', '/'])
                .next()
                .unwrap_or(self.iso_path.as_str())
        )
        .into();

        self.schedule_mount_completion(cx);
        cx.notify();
    }

    fn apply_external_paths(&mut self, paths: &ExternalPaths, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(first) = paths.paths().first() {
            self.set_iso_path(first.to_string_lossy().into_owned().into(), window, cx);
        }
    }

    fn prompt_iso_path(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if matches!(self.pane, LabPane::SourceReady)
            || matches!(self.splash_mount, SplashMountStage::Mounting)
        {
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
            self.mount_viewport_w = vp_w;
            self.mount_viewport_h = vp_h;
            self.set_iso_path_after_viewport(p.to_string_lossy().into_owned().into(), cx);
        }
    }

    fn write_intent(&mut self, cx: &mut Context<Self>) {
        let intent_payload = intent::build_gpui_intent(
            &self.iso_path.to_string(),
            &self.architecture.to_string(),
            &self.computer_name.to_string(),
            &self.account_name.to_string(),
            self.selected_groups.as_slice(),
            self.toolkit,
            self.desktop_layers,
        );

        let output_path = intent::intent_relative_path();

        let result = fs::create_dir_all(output_path.parent().unwrap()).and_then(|_| {
            fs::write(
                &output_path,
                serde_json::to_string_pretty(&intent_payload).unwrap(),
            )
        });

        self.status = match result {
            Ok(()) => format!("Wrote {}", output_path.display()).into(),
            Err(error) => format!("Could not write intent: {error}").into(),
        };
        cx.notify();
    }

    fn source_display_tail(&self) -> String {
        let s = self.iso_path.as_str();
        if s.len() <= 48 {
            return s.to_string();
        }
        format!("…{}", &s[s.len().saturating_sub(45)..])
    }

    fn receipt_tokens(&self) -> Vec<String> {
        let mut pills = Vec::new();
        for g in intent::normalized_profile_groups(self.selected_groups.as_slice()) {
            match g {
                "Minimal" => {}
                "Developer" => pills.push("Developer toolkit".into()),
                "CopilotPlus" => pills.push("Copilot-ready".into()),
                "Gaming" => pills.push("Gaming-friendly".into()),
                "DesktopUI" => pills.push("Tiling desktop".into()),
                _ => pills.push(format!("Group: {g}")),
            }
        }
        pills
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

    fn render_status_strip(&self) -> Div {
        div()
            .px_5()
            .py_3()
            .border_t_1()
            .border_color(theme::color::border_muted())
            .text_xs()
            .text_color(theme::color::text_dim())
            .child(self.status.clone())
    }

    fn render_splash_body(&self, _window: &mut Window, cx: &mut Context<Self>) -> Div {
        let mounting = matches!(self.splash_mount, SplashMountStage::Mounting);
        let title = if mounting {
            "Opening the installer image"
        } else {
            "Bring your installer into WinMint"
        };
        let hint = if mounting {
            "WinMint is preparing the source so the build profile can continue."
        } else {
            SPLASH_STATUS_PICK
        };
        let well: gpui::AnyElement = if mounting {
            div()
                .w_full()
                .max_w(px(760.))
                .h(px(200.))
                .flex()
                .flex_col()
                .items_center()
                .justify_center()
                .gap_3()
                .rounded_md()
                .border_2()
                .border_color(theme::color::border_muted())
                .bg(theme::color::surface())
                .child(ui::fluent_icon_block("\u{E895}", 40.))
                .child(
                    div()
                        .text_lg()
                        .text_center()
                        .text_color(theme::color::text())
                        .child("Mounting your installer"),
                )
                .child(
                    div()
                        .text_sm()
                        .text_center()
                        .text_color(theme::color::text_muted())
                        .child(self.iso_path.clone()),
                )
                .into_any_element()
        } else {
            ui::iso_landing_well("splash-iso-well")
                .on_drop(cx.listener(|this, paths: &ExternalPaths, window, cx| {
                    this.apply_external_paths(paths, window, cx);
                }))
                .on_click(cx.listener(|this, _, window, cx| {
                    this.prompt_iso_path(window, cx);
                }))
                .into_any_element()
        };

        div()
            .flex_1()
            .w_full()
            .flex()
            .flex_col()
            .overflow_hidden()
            .child(
                div()
                    .flex_1()
                    .flex()
                    .flex_col()
                    .items_center()
                    .justify_center()
                    .gap_6()
                    .px_10()
                    .py_10()
                    .child(div().h(px(180.0)))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_2()
                            .items_center()
                            .max_w(px(760.))
                            .child(ui::prose_title(title))
                            .child(ui::prose_hint(hint)),
                    )
                    .child(well)
                    .when(!mounting, |col| {
                        col.child(
                            ui::secondary_button("splash-browse-secondary", "Browse for ISO…")
                                .on_click(cx.listener(|this, _, window, cx| {
                                    this.prompt_iso_path(window, cx);
                                })),
                        )
                    }),
            )
    }

    fn render_source_ready(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let tokens = self.receipt_tokens();
        let pills = tokens.into_iter().map(|t| ui::pill(t, true)).collect::<Vec<_>>();
        div()
            .flex_1()
            .w_full()
            .flex()
            .flex_col()
            .items_center()
            .justify_center()
            .p_8()
            .gap_8()
            .child(
                div()
                    .w(px(760.))
                    .flex()
                    .flex_col()
                    .gap_8()
                    .child(ui::eyebrow("READY"))
                    .child(ui::prose_title("Installer source is attached."))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_2()
                            .child(div().font_weight(FontWeight::SEMIBOLD).child("Source"))
                            .child(
                                div()
                                    .text_sm()
                                    .text_color(theme::color::text_muted())
                                    .child(self.source_display_tail()),
                            ),
                    )
                    .when(!pills.is_empty(), |col| {
                        col.child(div().flex().flex_wrap().gap_2().children(pills))
                    })
                    .child(ui::prose_hint(
                        "Profile shaping returns later; for now WinMint locks path intent for the PowerShell bridge.",
                    ))
                    .child(ui::prose_hint(
                        "From repo root: pwsh -NoProfile -File tools\\gpui\\New-GpuiLabBuildProfile.ps1 (-DryRun).",
                    ))
                    .child(
                        div()
                            .w_full()
                            .flex()
                            .flex_wrap()
                            .gap_3()
                            .justify_between()
                            .items_center()
                            .child(
                                ui::secondary_button("pick-different", "Choose a different ISO…")
                                    .on_click(cx.listener(|this, _, _, cx| {
                                        this.reset_source_pick(cx);
                                    })),
                            )
                            .child(
                                ui::primary_button("write-intent", "Write intent JSON").on_click(cx.listener(
                                    |this, _, _, cx| {
                                        this.write_intent(cx);
                                    },
                                )),
                            ),
                    ),
            )
    }
}

impl Render for WinMintGpui {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let viewport = window.viewport_size();
        let win_w: f32 = viewport.width.into();
        let win_h: f32 = viewport.height.into();
        let show_splash_decor = matches!(self.pane, LabPane::Splash);
        let flight = self.brand_flight_progress();
        let brand_activity = self.brand_activity_clock();
        let needs_flight_ticks = flight > 0.0 && flight < 1.0;

        let mut stack = div()
            .flex_1()
            .w_full()
            .flex()
            .flex_col()
            .overflow_hidden();

        stack = if show_splash_decor {
            stack.child(self.render_splash_body(window, cx))
        } else {
            stack.child(self.render_source_ready(cx))
        };

        stack = stack.child(self.render_status_strip());

        let mut frame = ui::app_frame().relative();

        frame = frame.child(ui::flying_brand(flight, brand_activity, win_w, win_h));

        frame = frame.when(self.custom_titlebar, |fr| fr.child(self.render_toolbar()));

        frame = frame.child(stack);

        if needs_flight_ticks {
            frame = frame.child(
                div().w(px(0.)).h(px(0.)).with_animation(
                    "iso-mount-flight-clock",
                    Animation::new(Duration::from_millis(ANIM_CEILING_MS)),
                    |el, _| el,
                ),
            );
        }

        frame
    }
}

const SPLASH_DEMO_HOLD_MS: u64 = 900;

/// Standalone harness for visually iterating on the splash flight (`--demo-anim`).
/// Cycle duration matches production pacing (`ESTIMATED_ISO_MOUNT_MS` + brief hold).
struct SplashAnimDemo;

impl Render for SplashAnimDemo {
    fn render(&mut self, window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        let viewport = window.viewport_size();
        let width: f32 = viewport.width.into();
        let height: f32 = viewport.height.into();
        let cycle_ms = ESTIMATED_ISO_MOUNT_MS + SPLASH_DEMO_HOLD_MS;

        ui::app_frame()
            .relative()
            .with_animation(
                "splash-demo-loop",
                Animation::new(Duration::from_millis(cycle_ms)).repeat(),
                move |el, t| {
                    let merge = crate::anim::phase(t, 0.0, 0.18) * 0.50;
                    let hold = crate::anim::phase(t, 0.18, 0.72) * 0.12;
                    let dock = crate::anim::phase(t, 0.72, 0.94) * 0.38;
                    let progress = (merge + hold + dock).clamp(0.0, 1.0);

                    el.child(ui::flying_brand(progress, t * cycle_ms as f32 / 1000.0, width, height))
                },
            )
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let demo_anim = args.iter().any(|a| a == "--demo-anim");
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
        let title: SharedString = if demo_anim {
            "WinMint splash animation demo".into()
        } else {
            "WinMint".into()
        };
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some(title),
                appears_transparent: custom_titlebar && !demo_anim,
                ..Default::default()
            }),
            window_background: WindowBackgroundAppearance::Opaque,
            window_min_size: Some(size(
                px(theme::WINDOW_MIN_WIDTH),
                px(theme::WINDOW_MIN_HEIGHT),
            )),
            ..Default::default()
        };
        if demo_anim {
            cx.open_window(options, move |_, cx| {
                cx.new(|_| SplashAnimDemo)
            })
            .unwrap();
        } else {
            cx.open_window(options, move |_, cx| {
                cx.new(|_| WinMintGpui::new(custom_titlebar))
            })
            .unwrap();
        }
    });
}
