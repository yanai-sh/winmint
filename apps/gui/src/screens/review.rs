//! Review step. Shows the artifacts the bridge has produced so far.

use gpui::{div, prelude::*, px, Context, Div, FontWeight, SharedString, Window};

use crate::components as ui;
use crate::{theme, WinMintApp};

pub fn render(app: &WinMintApp, _window: &mut Window, _cx: &mut Context<WinMintApp>) -> Div {
    let profile_path = if app.build_run.profile_path.is_empty() {
        "Not generated".into()
    } else {
        app.build_run.profile_path.clone()
    };
    let manifest_path = if app.manifest.manifest_path.is_empty() {
        "Not available".into()
    } else {
        app.manifest.manifest_path.clone()
    };
    let output_path = if app.build_run.output_path.is_empty() {
        "Not available".into()
    } else {
        app.build_run.output_path.clone()
    };
    let report_path = if app.build_run.report_path.is_empty() {
        "Not available".into()
    } else {
        app.build_run.report_path.clone()
    };
    let last_progress = if app.build_run.last_progress.is_empty() {
        "None".into()
    } else {
        app.build_run.last_progress.clone()
    };

    div()
        .w_full()
        .max_w(px(620.0))
        .flex()
        .flex_col()
        .gap_4()
        .child(
            div()
                .text_lg()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::color::text())
                .child("Review"),
        )
        .child(
            ui::surface()
                .w_full()
                .flex()
                .flex_col()
                .gap_3()
                .child(summary_row("Profile", profile_path))
                .child(summary_row("Output", output_path))
                .child(summary_row("Manifest", manifest_path))
                .child(summary_row("Report", report_path))
                .child(summary_row("Progress", last_progress))
                .child(summary_row("Last status", app.build_run.status.clone())),
        )
}

fn summary_row(label: &'static str, value: SharedString) -> Div {
    div()
        .w_full()
        .flex()
        .items_center()
        .justify_between()
        .gap_4()
        .child(
            div()
                .w(px(112.0))
                .flex_shrink_0()
                .text_xs()
                .text_color(theme::color::text_dim())
                .child(label),
        )
        .child(
            div()
                .min_w(px(0.0))
                .text_sm()
                .text_color(theme::color::text())
                .truncate()
                .child(value),
        )
}
