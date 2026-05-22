#![allow(dead_code)]
// Palette of composed controls; GPUI is splash-only for now but posture/tiles
// remain for when multi-beat authoring returns.

use std::time::Duration;

use gpui::{div, img, prelude::*, px, App, ClickEvent, Div, ExternalPaths, FontWeight, SharedString, Stateful, Window, WindowControlArea};
use gpui_animation::{
    animation::{AnimatedWrapper, TransitionExt},
    transition,
};

use crate::{state::{SourceProbeStatus, WizardStage}, theme};

pub fn app_frame() -> Div {
    div()
        .size_full()
        .bg(theme::color::canvas())
        .text_color(theme::color::text())
        .flex()
        .flex_col()
}

pub const SPLASH_WORDMARK_TEXT: f32 = 78.0;
pub const SPLASH_WORDMARK_LH: f32 = 88.0;

pub fn titlebar_hit_regions() -> Div {
    div()
        .absolute()
        .top(px(0.0))
        .left(px(0.0))
        .right(px(132.0))
        .h(px(72.0))
        .window_control_area(WindowControlArea::Drag)
}

/// Brand-styled wordmark used in the splash flight. Two adjacent colored
/// text divs — there are no multi-color spans in GPUI 0.2.2. Colors and font
/// match the product brand palette: "Win" #F8FAFC, "Mint"
/// #70C050, Segoe UI Variable Display, semibold.
pub fn brand_wordmark(text_size: f32, line_height: f32) -> Div {
    div()
        .flex()
        .items_center()
        .font_family("Segoe UI Variable Display")
        .font_weight(FontWeight::SEMIBOLD)
        .text_size(px(text_size))
        .line_height(px(line_height))
        .child(
            div()
                .text_color(theme::color::brand_win())
                .child("Win"),
        )
        .child(
            div()
                .text_color(theme::color::brand_mint())
                .child("Mint"),
        )
}

fn mark_image(size: f32) -> gpui::Img {
    img(theme::asset::mark())
        .w(px(size))
        .h(px(size))
}

pub fn splash_brand_lockup() -> Div {
    div()
        .flex()
        .items_center()
        .justify_center()
        .gap_5()
        .child(mark_image(112.0))
        .child(brand_wordmark(62.0, 72.0))
}

pub fn rail_brand() -> impl IntoElement {
    div()
        .flex()
        .items_center()
        .gap_3()
        .px_2()
        .py_1()
        .rounded_md()
        .border_1()
        .border_color(theme::color::canvas())
        .id("rail-brand-lockup")
        .child(mark_image(42.0))
        .child(brand_wordmark(29.0, 34.0))
        .with_transition("rail-brand-lockup")
        .transition_on_hover(
            Duration::from_millis(200),
            transition::general::EaseOutQuad,
            |hovered, state| {
                if *hovered {
                    state
                        .border_color(theme::color::border_muted())
                        .bg(theme::color::surface_hover())
                } else {
                    state.origin()
                }
            },
        )
}

pub fn step_rail(active_index: usize) -> Div {
    div()
        .w(px(280.0))
        .h_full()
        .flex()
        .flex_col()
        .justify_between()
        .px_8()
        .pt(px(82.0))
        .pb(px(28.0))
        .border_r_1()
        .border_color(theme::color::border_muted())
        .bg(theme::color::sidebar())
        .child(
            div()
                .flex()
                .flex_col()
                .gap_10()
                .child(rail_brand())
                .child(
                    div()
                        .flex()
                        .flex_col()
                        .gap_2()
                        .children(WizardStage::FLOW.iter().enumerate().map(|(index, stage)| {
                            let state = if index < active_index {
                                StepState::Done
                            } else if index == active_index {
                                StepState::Active
                            } else {
                                StepState::Pending
                            };
                            step_item(index + 1, stage.label(), state)
                        })),
                ),
        )
}

enum StepState {
    Done,
    Active,
    Pending,
}

fn step_item(index: usize, label: &'static str, state: StepState) -> Div {
    let active = matches!(state, StepState::Active);
    let done = matches!(state, StepState::Done);
    div()
        .h(px(44.0))
        .flex()
        .items_center()
        .gap_3()
        .rounded_sm()
        .px_3()
        .when(active, |item| item.bg(theme::color::surface()))
        .child(
            div()
                .w(px(22.0))
                .h(px(22.0))
                .rounded_full()
                .flex()
                .items_center()
                .justify_center()
                .text_xs()
                .font_weight(FontWeight::SEMIBOLD)
                .bg(if active || done {
                    theme::color::accent()
                } else {
                    theme::color::surface_hover()
                })
                .text_color(if active || done {
                    theme::color::accent_text()
                } else {
                    theme::color::text_dim()
                })
                .child(if done { "✓".to_string() } else { index.to_string() }),
        )
        .child(
            div()
                .text_sm()
                .font_weight(if active {
                    FontWeight::SEMIBOLD
                } else {
                    FontWeight::NORMAL
                })
                .text_color(if active {
                    theme::color::text()
                } else {
                    theme::color::text_dim()
                })
                .child(label),
        )
}

pub fn status_footer(status: SharedString) -> Div {
    div()
        .h(px(48.0))
        .w_full()
        .flex()
        .items_center()
        .px_8()
        .border_t_1()
        .border_color(theme::color::border_muted())
        .text_xs()
        .text_color(theme::color::text_dim())
        .child(status)
}

pub fn surface() -> Div {
    div()
        .rounded(px(theme::metric::RADIUS))
        .border_1()
        .border_color(theme::color::border_muted())
        .bg(theme::color::surface())
        .p(px(theme::metric::PANEL_PAD))
}

pub fn section_label(title: &'static str, hint: &'static str) -> Div {
    div()
        .flex()
        .flex_col()
        .gap_2()
        .child(
            div()
                .text_lg()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::color::text())
                .child(title),
        )
        .child(
            div()
                .text_sm()
                .text_color(theme::color::text_dim())
                .child(hint),
        )
}

pub fn status_badge(status: SourceProbeStatus) -> Div {
    let color = match status {
        SourceProbeStatus::Empty => theme::color::text_dim(),
        SourceProbeStatus::Preparing => theme::color::warning(),
        SourceProbeStatus::Ready => theme::color::success(),
        SourceProbeStatus::Failed => theme::color::danger(),
    };
    div()
        .px_3()
        .py_1()
        .rounded_full()
        .border_1()
        .border_color(color)
        .text_xs()
        .text_color(color)
        .child(status.label())
}

pub fn callout(message: impl Into<String>, danger: bool) -> Div {
    div()
        .w_full()
        .rounded(px(theme::metric::RADIUS))
        .border_1()
        .border_color(if danger { theme::color::danger() } else { theme::color::warning() })
        .bg(theme::color::surface_hover())
        .px_4()
        .py_3()
        .text_sm()
        .text_color(theme::color::text())
        .child(message.into())
}

pub fn titlebar_button(
    id: &'static str,
    glyph: &'static str,
    area: WindowControlArea,
    close: bool,
) -> Stateful<Div> {
    div()
        .id(id)
        .w(px(42.0))
        .h(px(30.0))
        .flex()
        .items_center()
        .justify_center()
        .font_family("Segoe Fluent Icons")
        .text_size(px(10.0))
        .text_color(theme::color::text_muted())
        .window_control_area(area)
        .hover(move |style| {
            if close {
                style
                    .bg(theme::color::danger())
                    .text_color(theme::color::white())
            } else {
                style
                    .bg(theme::color::surface_hover())
                    .text_color(theme::color::text())
            }
        })
        .child(glyph)
}

pub fn eyebrow(label: &'static str) -> Div {
    div()
        .text_xs()
        .text_color(theme::color::text_dim())
        .child(label)
}

pub fn pill(label: impl Into<String>, active: bool) -> Div {
    div()
        .px_3()
        .py_1()
        .rounded_sm()
        .border_1()
        .border_color(if active {
            theme::color::accent()
        } else {
            theme::color::border_muted()
        })
        .bg(if active {
            theme::color::surface_hover()
        } else {
            theme::color::surface()
        })
        .text_xs()
        .text_color(if active {
            theme::color::text()
        } else {
            theme::color::text_muted()
        })
        .child(label.into())
}

pub fn primary_button(id: &'static str, label: &'static str) -> Stateful<Div> {
    div()
        .id(id)
        .h(px(theme::metric::CONTROL_H))
        .px_5()
        .flex()
        .items_center()
        .rounded_sm()
        .bg(theme::color::accent())
        .text_color(theme::color::accent_text())
        .hover(|style| style.bg(theme::color::white()).cursor_pointer())
        .child(label)
}

pub fn secondary_button(id: &'static str, label: &'static str) -> Stateful<Div> {
    div()
        .id(id)
        .h(px(theme::metric::CONTROL_H))
        .px_4()
        .flex()
        .items_center()
        .rounded_sm()
        .border_1()
        .border_color(theme::color::border_muted())
        .bg(theme::color::surface())
        .text_color(theme::color::text())
        .hover(|style| style.bg(theme::color::surface_hover()).cursor_pointer())
        .child(label)
}

pub fn beat_scrub(labels: &[&'static str], active_index: usize) -> Div {
    div().flex().items_center().justify_center().gap_4().flex_wrap().children(
        labels.iter().enumerate().map(|(i, lab)| {
            let on = i == active_index;
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(div().w(px(8.)).h(px(8.)).rounded_full().bg(if on {
                    theme::color::accent()
                } else {
                    theme::color::border_muted()
                }))
                .child(
                    div()
                        .text_xs()
                        .text_color(if on {
                            theme::color::text()
                        } else {
                            theme::color::text_dim()
                        })
                        .child(*lab),
                )
        }),
    )
}

pub fn fluent_icon_block(glyph: &'static str, size: f32) -> Div {
    div()
        .flex()
        .items_center()
        .justify_center()
        .rounded_md()
        .w(px(size + 24.))
        .h(px(size + 24.))
        .bg(theme::color::surface_hover())
        .border_1()
        .border_color(theme::color::border_muted())
        .font_family("Segoe Fluent Icons")
        .text_size(px(size))
        .text_color(theme::color::text_muted())
        .child(glyph)
}

pub fn posture_tile(
    id: impl Into<gpui::ElementId>,
    fluent_glyph: &'static str,
    selected: bool,
) -> Stateful<Div> {
    div()
        .id(id)
        .cursor_pointer()
        .flex()
        .items_center()
        .gap_5()
        .p_6()
        .rounded_md()
        .border_2()
        .border_color(if selected {
            theme::color::accent()
        } else {
            theme::color::border_muted()
        })
        .bg(if selected {
            theme::color::surface_hover()
        } else {
            theme::color::surface()
        })
        .hover(|style| style.bg(theme::color::surface_hover()))
        .child(fluent_icon_block(fluent_glyph, 28.))
}

pub fn prose_title(text: &'static str) -> Div {
    div()
        .text_size(px(34.))
        .line_height(px(40.))
        .font_weight(FontWeight::SEMIBOLD)
        .text_color(theme::color::text())
        .child(text)
}

pub fn prose_hint(text: &'static str) -> Div {
    div()
        .text_sm()
        .text_color(theme::color::text_dim())
        .child(text)
}

pub fn detail_row(label: &'static str, value: impl Into<String>) -> Div {
    div()
        .w_full()
        .flex()
        .items_center()
        .justify_between()
        .gap_6()
        .py_3()
        .border_b_1()
        .border_color(theme::color::border_muted())
        .child(
            div()
                .text_sm()
                .text_color(theme::color::text_dim())
                .child(label),
        )
        .child(
            div()
                .text_sm()
                .text_color(theme::color::text())
                .font_weight(FontWeight::SEMIBOLD)
                .child(value.into()),
        )
}

pub fn source_preparing_panel(filename: impl Into<String>) -> Div {
    div()
        .w_full()
        .h(px(230.0))
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .gap_4()
        .rounded_md()
        .border_1()
        .border_color(theme::color::border_muted())
        .bg(theme::color::surface())
        .child(
            div()
                .w(px(220.0))
                .h(px(6.0))
                .rounded_full()
                .bg(theme::color::surface_hover())
                .overflow_hidden()
                .child(
                    div()
                        .w(px(132.0))
                        .h(px(6.0))
                        .rounded_full()
                        .bg(theme::color::accent()),
                ),
        )
        .child(
            div()
                .text_lg()
                .text_color(theme::color::text())
                .child("Reading source"),
        )
        .child(
            div()
                .text_sm()
                .text_color(theme::color::text_muted())
                .child(filename.into()),
        )
}

pub fn iso_landing_well(
    id: &'static str,
    on_drop: impl Fn(&ExternalPaths, &mut Window, &mut App) + 'static,
    on_click: impl Fn(&ClickEvent, &mut Window, &mut App) + 'static,
) -> AnimatedWrapper<Stateful<Div>> {
    div()
        .id(id)
        .cursor_pointer()
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .gap_3()
        .w_full()
        .h(px(230.))
        .p_8()
        .rounded_md()
        .border_dashed()
        .border_2()
        .border_color(theme::color::border_muted())
        .bg(theme::color::surface())
        .drag_over::<ExternalPaths>(|style, _, _, _| {
            style.border_color(theme::color::accent()).border_2().bg(theme::color::surface_hover())
        })
        .child(fluent_icon_block("\u{E958}", 40.))
        .child(
            div()
                .text_lg()
                .text_center()
                .text_color(theme::color::text())
                .child("Drop or choose Windows ISO"),
        )
        .child(
            div()
                .text_sm()
                .text_center()
                .text_color(theme::color::text_muted())
                .child("Click this area to browse."),
        )
        .on_drop(on_drop)
        .with_transition(id)
        .transition_on_hover(
            Duration::from_millis(180),
            transition::general::EaseOutQuad,
            |hovered, state| {
                if *hovered {
                    state
                        .border_color(theme::color::accent())
                        .bg(theme::color::surface_hover())
                } else {
                    state.origin()
                }
            },
        )
        .on_click(on_click)
}

pub fn segmented_choice(id: &'static str, label: &'static str, selected: bool) -> Stateful<Div> {
    div()
        .id(id)
        .cursor_pointer()
        .px_6()
        .py_3()
        .rounded_md()
        .border_2()
        .border_color(if selected {
            theme::color::accent()
        } else {
            theme::color::border_muted()
        })
        .bg(if selected {
            theme::color::surface_hover()
        } else {
            theme::color::surface()
        })
        .text_sm()
        .font_weight(if selected {
            FontWeight::SEMIBOLD
        } else {
            FontWeight::NORMAL
        })
        .text_color(theme::color::text())
        .hover(|style| style.bg(theme::color::surface_hover()))
        .child(label)
}

pub fn selectable_chip(
    id: &'static str,
    fluent_glyph: &'static str,
    label: &'static str,
    on: bool,
) -> Stateful<Div> {
    div()
        .id(id)
        .cursor_pointer()
        .flex()
        .items_center()
        .gap_3()
        .px_4()
        .py_2()
        .rounded_md()
        .border_1()
        .border_color(if on {
            theme::color::accent()
        } else {
            theme::color::border_muted()
        })
        .bg(if on {
            theme::color::surface_hover()
        } else {
            theme::color::surface()
        })
        .hover(|style| style.bg(theme::color::surface_hover()))
        .child(
            div()
                .font_family("Segoe Fluent Icons")
                .text_size(px(14.))
                .text_color(if on {
                    theme::color::accent()
                } else {
                    theme::color::text_dim()
                })
                .child(fluent_glyph),
        )
        .child(div().text_sm().text_color(theme::color::text()).child(label))
}
