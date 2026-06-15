//! Build step. Owns only GPUI controls; bridge.rs owns the PowerShell calls.

use gpui::{div, prelude::*, px, Context, Div, FontWeight, SharedString, Stateful, Window};

use crate::components as ui;
use crate::{theme, WinMintApp};

pub fn render(app: &WinMintApp, _window: &mut Window, cx: &mut Context<WinMintApp>) -> Div {
    let source_name = app
        .source
        .iso_path
        .as_ref()
        .rsplit(['\\', '/'])
        .next()
        .unwrap_or(app.source.iso_path.as_ref())
        .to_string();
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
    let can_run = !app.build_run.running && !app.source.iso_path.is_empty();

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
                .child("Build"),
        )
        .child(
            ui::surface()
                .w_full()
                .flex()
                .flex_col()
                .gap_3()
                .child(summary_row("Source", source_name.into()))
                .child(summary_row("Architecture", app.intent.architecture.clone()))
                .child(summary_row("Edition", app.intent.edition.clone()))
                .child(summary_row("Profile", profile_path))
                .child(summary_row("Manifest", manifest_path))
                .child(summary_row("Report", report_path))
                .child(summary_row("Progress", last_progress))
                .child(summary_row("Status", app.build_run.status.clone())),
        )
        .child(
            div()
                .flex()
                .items_center()
                .gap_3()
                .child(action_button(
                    "build-generate-profile",
                    "Generate profile",
                    can_run,
                    cx.listener(|this, _, _, cx| this.generate_build_profile(cx)),
                ))
                .child(action_button(
                    "build-dry-run",
                    "Dry run",
                    can_run,
                    cx.listener(|this, _, _, cx| this.run_dry_build(cx)),
                )),
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

fn action_button(
    id: &'static str,
    label: &'static str,
    enabled: bool,
    on_click: impl Fn(&gpui::ClickEvent, &mut Window, &mut gpui::App) + 'static,
) -> Stateful<Div> {
    if enabled {
        return ui::primary_button(id, label).on_click(on_click);
    }

    div()
        .id(id)
        .h(px(theme::metric::CONTROL_H))
        .px_5()
        .flex()
        .items_center()
        .rounded_sm()
        .bg(theme::color::border_muted())
        .text_color(theme::color::text_dim())
        .child(label)
}
