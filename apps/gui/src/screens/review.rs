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
    let build_delta_path = if app.build_run.build_delta_path.is_empty() {
        "Not available".into()
    } else {
        app.build_run.build_delta_path.clone()
    };
    let last_progress = if app.build_run.last_progress.is_empty() {
        "None".into()
    } else {
        app.build_run.last_progress.clone()
    };
    let build_delta_summary = &app.build_run.build_delta_summary;
    let phase_summary = if build_delta_summary.phase_counts.is_empty() {
        "Not available".to_string()
    } else {
        build_delta_summary
            .phase_counts
            .iter()
            .map(|(phase, count)| format!("{phase}={count}"))
            .collect::<Vec<_>>()
            .join(", ")
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
                .child(summary_row("BuildDelta", build_delta_path))
                .child(summary_row(
                    "Records",
                    build_delta_summary.total_records.to_string().into(),
                ))
                .child(summary_row(
                    "User controlled",
                    build_delta_summary
                        .user_controlled_records
                        .to_string()
                        .into(),
                ))
                .child(summary_row("Phases", phase_summary.into()))
                .child(summary_row("Report", report_path))
                .child(summary_row("Progress", last_progress))
                .child(summary_row("Last status", app.build_run.status.clone()))
                .children(
                    build_delta_summary
                        .highlighted_records
                        .iter()
                        .map(highlight_row),
                ),
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

fn highlight_row(record: &crate::bridge::BuildDeltaRecordSummary) -> Div {
    let detail = if record.kind.is_empty() {
        format!("{} change(s)", record.change_count)
    } else {
        format!("{} · {} change(s)", record.kind, record.change_count)
    };

    div()
        .w_full()
        .flex()
        .flex_col()
        .gap_1()
        .child(
            div()
                .text_sm()
                .text_color(theme::color::text())
                .child(record.title.clone()),
        )
        .child(
            div()
                .text_xs()
                .text_color(theme::color::text_dim())
                .child(format!("{} · {}", record.phase, detail)),
        )
}
