//! Source step: choose a Windows ISO. Eager — selecting an ISO shows the source
//! card and unlocks Next immediately; the background mount/probe only enriches the
//! card (editions, confirmed arch) and never blocks. Form factor lives on Configure.

use gpui::{div, prelude::*, px, AnyElement, Context, Div, ExternalPaths, FontWeight, SharedString, Window};

use crate::components as ui;
use crate::state::SourceProbeStatus;
use crate::{theme, WinMintApp};

pub fn render(app: &WinMintApp, _window: &mut Window, cx: &mut Context<WinMintApp>) -> Div {
    if matches!(app.source.status, SourceProbeStatus::Empty) {
        render_empty(app, cx)
    } else {
        render_selected(app, cx)
    }
}

/// Nothing chosen yet: brand hero + the drop/browse well.
fn render_empty(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    div()
        .w_full()
        .max_w(px(640.0))
        .flex()
        .flex_col()
        .items_center()
        .gap_6()
        .child(ui::landing_hero_image(
            app.hero_logo.clone(),
            app.splash_logo.clone(),
        ))
        .child(
            div()
                .flex()
                .flex_col()
                .items_center()
                .gap_2()
                .child(
                    div()
                        .text_size(px(20.0))
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_center()
                        .text_color(theme::color::text())
                        .child("Build a clean Windows workstation ISO."),
                )
                .child(
                    div()
                        .text_sm()
                        .text_center()
                        .text_color(theme::color::text_dim())
                        .child("Start from any Windows 10 or 11 image."),
                ),
        )
        .child(ui::iso_landing_well(
            "splash-iso-well",
            cx.listener(|this, paths: &ExternalPaths, window, cx| {
                this.apply_external_paths(paths, window, cx);
            }),
            cx.listener(|this, _, window, cx| {
                this.prompt_iso_path(window, cx);
            }),
        ))
}

/// An ISO is chosen: compact header + the source card (fills in eagerly).
fn render_selected(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    div()
        .w_full()
        .max_w(px(560.0))
        .flex()
        .flex_col()
        .items_center()
        .gap_4()
        .child(
            div()
                .text_lg()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::color::text())
                .child("Windows source"),
        )
        .child(source_card(app, cx))
}

fn source_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    let name = file_name(app.source.iso_path.as_str()).to_string();
    let arch = arch_label(app.intent.architecture.as_ref());
    let size = app.source.iso_size.as_ref();
    let meta = if size.is_empty() {
        arch.to_string()
    } else {
        format!("{size} · {arch}")
    };

    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_3()
        .child(
            div()
                .flex()
                .items_center()
                .justify_between()
                .gap_4()
                .child(
                    div()
                        .min_w(px(0.0))
                        .flex()
                        .flex_col()
                        .gap_1()
                        .child(
                            div()
                                .text_sm()
                                .font_weight(FontWeight::SEMIBOLD)
                                .text_color(theme::color::text())
                                .child(name),
                        )
                        .child(
                            div()
                                .text_xs()
                                .text_color(theme::color::text_dim())
                                .child(meta),
                        ),
                )
                .child(
                    ui::secondary_button("source-change", "Change").on_click(cx.listener(
                        |this, _, _, cx| {
                            this.reset_source_pick(cx);
                        },
                    )),
                ),
        )
        .child(inspection(app))
}

/// Background-probe status line — advisory only, never blocks Next.
fn inspection(app: &WinMintApp) -> AnyElement {
    match app.source.status {
        SourceProbeStatus::Preparing => div()
            .text_xs()
            .text_color(theme::color::text_dim())
            .child("Inspecting image…")
            .into_any_element(),
        SourceProbeStatus::Ready => {
            let count = app.source.editions.len();
            div()
                .flex()
                .flex_col()
                .gap_1()
                .child(
                    div()
                        .text_xs()
                        .text_color(theme::color::success())
                        .child(format!(
                            "Valid Windows image · {count} edition{}",
                            if count == 1 { "" } else { "s" }
                        )),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(theme::color::text_dim())
                        .child(editions_summary(&app.source.editions)),
                )
                .into_any_element()
        }
        SourceProbeStatus::Failed => ui::callout(
            format!(
                "Couldn't read this image: {}. You can still continue.",
                app.source.error
            ),
            false,
        )
        .into_any_element(),
        SourceProbeStatus::Empty => div().into_any_element(),
    }
}

fn editions_summary(editions: &[SharedString]) -> String {
    let shown: Vec<&str> = editions.iter().take(4).map(|e| e.as_ref()).collect();
    let mut summary = shown.join(", ");
    if editions.len() > 4 {
        summary.push_str(", …");
    }
    summary
}

fn arch_label(arch: &str) -> &str {
    match arch {
        "arm64" | "ARM64" => "ARM64",
        "amd64" | "x64" => "x64",
        "x86" => "x86",
        "" | "Unknown" => "Unknown architecture",
        other => other,
    }
}

fn file_name(path: &str) -> &str {
    path.rsplit(['\\', '/']).next().unwrap_or(path)
}
