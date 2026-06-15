use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use gpui::{
    div, img, point, prelude::*, px, rgb, size, App, Application, Bounds, Context, Div,
    FocusHandle, Focusable, FontWeight, Hsla, Image, ImageFormat, Rgba, SharedString,
    TitlebarOptions, Window, WindowBackgroundAppearance, WindowBounds, WindowControlArea,
    WindowOptions,
};
use gpui_component::{h_flex, progress::Progress, spinner::Spinner, v_flex, Root, Sizable};

const STEPS: &[(&str, &str)] = &[
    ("package-managers", "Package managers"),
    ("winget-upgrade", "App updates"),
    ("browsers", "Browsers"),
    ("editors", "Editors"),
    ("wsl", "WSL"),
    ("desktop-shell", "Desktop"),
    ("cleanup", "Finishing"),
];

#[derive(Clone)]
struct StepView {
    id: &'static str,
    label: &'static str,
    status: StepStatus,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum StepStatus {
    Waiting,
    Running,
    Done,
}

struct FirstLogonApp {
    focus_handle: FocusHandle,
    wordmark: Arc<Image>,
    setup: SetupSummary,
    steps: Vec<StepView>,
    active_step: usize,
    tick: usize,
    _tick_task: gpui::Task<()>,
}

#[derive(Clone)]
struct SetupSummary {
    apps: SharedString,
    editors: SharedString,
    wsl: SharedString,
    desktop: SharedString,
}

impl FirstLogonApp {
    fn new(cx: &mut Context<Self>) -> Self {
        let args: Vec<String> = env::args().collect();
        let profile_path = arg_value(&args, "--profile").map(PathBuf::from);
        let profile = profile_path.as_deref().and_then(read_profile);
        let setup = profile
            .as_ref()
            .map(setup_summary)
            .unwrap_or_else(default_setup_summary);

        let mut steps = STEPS
            .iter()
            .map(|(id, label)| StepView {
                id,
                label,
                status: StepStatus::Waiting,
            })
            .collect::<Vec<_>>();
        if let Some(first) = steps.first_mut() {
            first.status = StepStatus::Running;
        }

        let _tick_task = cx.spawn(async move |this, cx| loop {
            gpui::Timer::after(Duration::from_millis(700)).await;
            this.update(cx, |state, cx| {
                state.advance_demo();
                cx.notify();
            })
            .ok();
        });

        Self {
            focus_handle: cx.focus_handle(),
            wordmark: load_brand_logo(&[
                brand_path("winmint_hero_ui.png"),
                brand_path("winmint_hero.png"),
                brand_path("winmint_full_ui_132.png"),
            ]),
            setup,
            steps,
            active_step: 0,
            tick: 0,
            _tick_task,
        }
    }

    fn advance_demo(&mut self) {
        self.tick = self.tick.wrapping_add(1);
        if self.tick % 4 != 0 {
            return;
        }
        if self.active_step >= self.steps.len() {
            return;
        }
        if let Some(step) = self.steps.get_mut(self.active_step) {
            step.status = StepStatus::Done;
        }
        self.active_step += 1;
        if let Some(next) = self.steps.get_mut(self.active_step) {
            next.status = StepStatus::Running;
        }
    }

    fn complete_count(&self) -> usize {
        self.steps
            .iter()
            .filter(|step| step.status == StepStatus::Done)
            .count()
    }

    fn is_complete(&self) -> bool {
        self.complete_count() == self.steps.len()
    }

    fn progress_percent(&self) -> f32 {
        if self.is_complete() {
            return 100.0;
        }

        let step_fraction = (self.tick % 4) as f32 / 4.0;
        let visible_progress = self.complete_count() as f32 + step_fraction;
        ((visible_progress / self.steps.len() as f32) * 100.0).clamp(0.0, 100.0)
    }

    fn current_step(&self) -> Option<&StepView> {
        self.steps.get(self.active_step)
    }

    fn status_title(&self) -> &'static str {
        if self.is_complete() {
            "Your WinMint desktop is ready"
        } else {
            "Preparing your desktop"
        }
    }

    fn status_message(&self) -> &'static str {
        if self.is_complete() {
            "Final cleanup completed."
        } else if let Some(step) = self.current_step() {
            action_message(step.id)
        } else {
            "Finishing setup."
        }
    }

    fn phase_label(&self) -> String {
        if self.is_complete() {
            "Complete".to_string()
        } else if let Some(step) = self.current_step() {
            format!(
                "Step {} of {} - {}",
                self.active_step.saturating_add(1),
                self.steps.len(),
                step.label
            )
        } else {
            format!(
                "Step {} of {}",
                self.active_step.saturating_add(1),
                self.steps.len()
            )
        }
    }

    fn render_stage(&self) -> Div {
        v_flex()
            .relative()
            .w(px(580.0))
            .h(px(300.0))
            .items_center()
            .justify_between()
            .overflow_hidden()
            .p(px(24.0))
            .child(self.render_preparation_column())
    }

    fn render_preparation_column(&self) -> Div {
        v_flex()
            .relative()
            .w_full()
            .h_full()
            .items_center()
            .justify_between()
            .child(
                v_flex()
                    .items_center()
                    .gap(px(22.0))
                    .child(
                        div()
                            .w(px(260.0))
                            .h(px(124.0))
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(
                                img(self.wordmark.clone())
                                    .id("winmint-wordmark")
                                    .w(px(240.0))
                                    .h(px(113.0)),
                            ),
                    )
                    .child(self.render_status_copy()),
            )
            .child(
                v_flex()
                    .items_center()
                    .gap(px(12.0))
                    .child(self.render_progress())
                    .child(self.render_context_line()),
            )
    }

    fn render_status_copy(&self) -> Div {
        v_flex()
            .items_center()
            .gap(px(12.0))
            .child(
                div()
                    .font_family("Segoe UI Variable Display")
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_size(px(28.0))
                    .line_height(px(34.0))
                    .text_color(color::text())
                    .child(self.status_title()),
            )
            .child(
                h_flex()
                    .gap(px(10.0))
                    .text_color(color::text_muted())
                    .text_size(px(15.0))
                    .line_height(px(22.0))
                    .child(if self.is_complete() {
                        complete_mark()
                    } else {
                        spinner_mark()
                    })
                    .child(self.status_message()),
            )
    }

    fn render_progress(&self) -> Div {
        v_flex()
            .w(px(400.0))
            .gap(px(10.0))
            .child(
                Progress::new()
                    .value(self.progress_percent())
                    .bg(Hsla::from(color::mint()))
                    .h(px(6.0))
                    .rounded(px(3.0)),
            )
            .child(
                h_flex()
                    .justify_between()
                    .text_xs()
                    .text_color(color::text_dim())
                    .child(self.phase_label())
                    .child(format!("{:.0}%", self.progress_percent())),
            )
    }

    fn render_context_line(&self) -> Div {
        h_flex()
            .justify_center()
            .gap(px(10.0))
            .text_size(px(13.0))
            .line_height(px(19.0))
            .text_color(color::text_dim())
            .child(self.current_configuration_detail())
    }

    fn current_configuration_detail(&self) -> SharedString {
        let detail = match self.current_step().map(|step| step.id) {
            Some("winget-upgrade") | Some("browsers") => {
                format!("Selected apps: {}", self.setup.apps)
            }
            Some("editors") => format!("Selected editors: {}", self.setup.editors),
            Some("wsl") => format!("Selected WSL: {}", self.setup.wsl),
            Some("desktop-shell") => format!("Selected desktop: {}", self.setup.desktop),
            Some("cleanup") => "Cleaning temporary setup files.".to_string(),
            _ => "Selected configuration is being applied.".to_string(),
        };
        detail.into()
    }
}

impl Focusable for FirstLogonApp {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl Render for FirstLogonApp {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .id("winmint-firstlogon-root")
            .track_focus(&self.focus_handle)
            .size_full()
            .bg(color::canvas())
            .text_color(color::text())
            .font_family("Segoe UI Variable Text")
            .child(
                v_flex()
                    .relative()
                    .size_full()
                    .items_center()
                    .justify_center()
                    .overflow_hidden()
                    .child(hidden_drag_region())
                    .child(self.render_stage()),
            )
    }
}

fn hidden_drag_region() -> Div {
    div()
        .absolute()
        .top(px(0.0))
        .left(px(0.0))
        .right(px(0.0))
        .h(px(44.0))
        .window_control_area(WindowControlArea::Drag)
}

fn spinner_mark() -> Div {
    div()
        .w(px(16.0))
        .h(px(16.0))
        .flex()
        .items_center()
        .justify_center()
        .child(Spinner::new().small().color(Hsla::from(color::mint())))
}

fn complete_mark() -> Div {
    div()
        .w(px(16.0))
        .h(px(16.0))
        .rounded_full()
        .flex()
        .items_center()
        .justify_center()
        .bg(color::success_soft())
        .text_color(color::success())
        .text_xs()
        .font_weight(FontWeight::SEMIBOLD)
        .child("OK")
}

fn action_message(id: &str) -> &'static str {
    match id {
        "package-managers" => "Preparing package managers.",
        "winget-upgrade" => "Updating available apps.",
        "browsers" => "Installing selected browsers.",
        "editors" => "Preparing editors and terminal defaults.",
        "wsl" => "Setting up the WSL runtime.",
        "desktop-shell" => "Applying the desktop shell.",
        "cleanup" => "Finishing the install.",
        _ => "Working.",
    }
}

fn load_brand_logo(candidates: &[PathBuf]) -> Arc<Image> {
    for path in candidates {
        if let Ok(bytes) = fs::read(path) {
            return Arc::new(Image::from_bytes(ImageFormat::Png, bytes));
        }
    }
    Arc::new(Image::empty())
}

fn brand_path(file_name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("assets")
        .join("brand")
        .join(file_name)
}

fn arg_value(args: &[String], name: &str) -> Option<String> {
    args.windows(2)
        .find(|pair| pair[0] == name)
        .map(|pair| pair[1].clone())
}

fn read_profile(path: &Path) -> Option<serde_json::Value> {
    let text = fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

fn setup_summary(profile: &serde_json::Value) -> SetupSummary {
    SetupSummary {
        apps: string_array(profile, &["development", "browsers"])
            .unwrap_or_else(|| "Selected apps".to_string())
            .into(),
        editors: string_array(profile, &["development", "editors"])
            .unwrap_or_else(|| "Selected editors".to_string())
            .into(),
        wsl: string_array(profile, &["development", "wsl", "distros"])
            .unwrap_or_else(|| {
                bool_at(profile, &["development", "wsl", "enabled"])
                    .filter(|enabled| *enabled)
                    .map(|_| "Enabled".to_string())
                    .unwrap_or_else(|| "Not selected".to_string())
            })
            .into(),
        desktop: string_array(profile, &["desktop", "layers"])
            .map(|layers| layers.replace("standard, ", ""))
            .filter(|layers| !layers.trim().is_empty())
            .unwrap_or_else(|| "Standard Windows".to_string())
            .into(),
    }
}

fn default_setup_summary() -> SetupSummary {
    SetupSummary {
        apps: "zen-browser, helium".into(),
        editors: "cursor, neovim".into(),
        wsl: "Ubuntu, NixOS-WSL".into(),
        desktop: "nilesoft".into(),
    }
}

fn string_array(profile: &serde_json::Value, path: &[&str]) -> Option<String> {
    let value = value_at(profile, path)?;
    let items = value
        .as_array()?
        .iter()
        .filter_map(|item| item.as_str())
        .filter(|item| !item.trim().is_empty())
        .map(str::to_string)
        .collect::<Vec<_>>();

    if items.is_empty() {
        None
    } else {
        Some(items.join(", "))
    }
}

fn bool_at(profile: &serde_json::Value, path: &[&str]) -> Option<bool> {
    value_at(profile, path).and_then(|value| value.as_bool())
}

fn value_at<'a>(profile: &'a serde_json::Value, path: &[&str]) -> Option<&'a serde_json::Value> {
    let mut current = profile;
    for segment in path {
        current = current.get(*segment)?;
    }
    Some(current)
}

fn main() {
    Application::new().run(|cx: &mut App| {
        gpui_component::init(cx);
        let bounds = Bounds::new(point(px(220.0), px(150.0)), size(px(720.0), px(420.0)));
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: None,
                appears_transparent: true,
                ..Default::default()
            }),
            window_background: WindowBackgroundAppearance::Transparent,
            window_min_size: Some(size(px(680.0), px(390.0))),
            is_resizable: false,
            is_minimizable: false,
            ..Default::default()
        };
        cx.open_window(options, |window, cx| {
            let view = cx.new(FirstLogonApp::new);
            let focus = view.read(cx).focus_handle.clone();
            window.focus(&focus);
            cx.new(|cx| Root::new(view, window, cx))
        })
        .expect("failed to open WinMint FirstLogon window");
        strip_native_window_chrome_after_open();
        cx.activate(true);
    });
}

#[cfg(target_os = "windows")]
fn strip_native_window_chrome_after_open() {
    std::thread::spawn(|| {
        for delay in [80, 260, 700] {
            std::thread::sleep(Duration::from_millis(delay));
            strip_native_window_chrome();
        }
    });
}

#[cfg(not(target_os = "windows"))]
fn strip_native_window_chrome_after_open() {}

#[cfg(target_os = "windows")]
fn strip_native_window_chrome() {
    use windows_sys::core::BOOL;
    use windows_sys::Win32::Foundation::{HWND, LPARAM, TRUE};
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GetWindowLongPtrW, GetWindowThreadProcessId, IsWindowVisible,
        SetWindowLongPtrW, SetWindowPos, GWL_STYLE, SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOMOVE,
        SWP_NOSIZE, SWP_NOZORDER, WS_CAPTION, WS_MAXIMIZEBOX, WS_MINIMIZEBOX, WS_SYSMENU,
        WS_THICKFRAME, WS_VISIBLE,
    };

    unsafe extern "system" fn enum_window(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let mut process_id = 0;
        unsafe {
            GetWindowThreadProcessId(hwnd, &mut process_id);
        }
        if process_id != lparam as u32 {
            return TRUE;
        }

        let style = unsafe { GetWindowLongPtrW(hwnd, GWL_STYLE) } as u32;
        if style & WS_VISIBLE == 0 || unsafe { IsWindowVisible(hwnd) } == 0 {
            return TRUE;
        }

        let stripped_style =
            style & !(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        if stripped_style != style {
            unsafe {
                SetWindowLongPtrW(hwnd, GWL_STYLE, stripped_style as isize);
                SetWindowPos(
                    hwnd,
                    std::ptr::null_mut(),
                    0,
                    0,
                    0,
                    0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
                );
            }
        }

        TRUE
    }

    unsafe {
        EnumWindows(Some(enum_window), std::process::id() as isize);
    }
}

mod color {
    use super::*;

    pub fn canvas() -> Hsla {
        Hsla::from(rgb(0x0a0f14)).opacity(0.62)
    }

    pub fn text() -> Rgba {
        rgb(0xf4f7fb)
    }

    pub fn text_muted() -> Rgba {
        rgb(0xc2c9d3)
    }

    pub fn text_dim() -> Rgba {
        rgb(0x8b95a3)
    }

    pub fn mint() -> Rgba {
        rgb(0x72d45a)
    }

    pub fn success() -> Rgba {
        rgb(0x72d45a)
    }

    pub fn success_soft() -> Hsla {
        Hsla::from(success()).opacity(0.16)
    }
}
