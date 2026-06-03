//! Composed GPUI controls (`ui::*`) shared by the wizard screens and root view.

use std::sync::Arc;
use std::time::Duration;

use gpui::{
    div, img, prelude::*, px, App, ClickEvent, Div, ExternalPaths, FontWeight, Image, SharedString,
    Stateful, Window, WindowControlArea,
};
use gpui_animation::{
    animation::{AnimatedWrapper, TransitionExt},
    transition,
};

use crate::theme;

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
        .child(div().text_color(theme::color::brand_win()).child("Win"))
        .child(div().text_color(theme::color::brand_mint()).child("Mint"))
}

pub fn splash_brand_lockup(logo: Arc<Image>) -> Div {
    div().flex().items_center().justify_center().child(
        img(logo)
            .id("winmint-splash-logo")
            .w(px(132.0))
            .h(px(132.0))
            .with_fallback(|| {
                brand_wordmark(SPLASH_WORDMARK_TEXT, SPLASH_WORDMARK_LH).into_any_element()
            }),
    )
}

pub fn landing_hero_image(hero: Arc<Image>, fallback_logo: Arc<Image>) -> Div {
    div().w_full().flex().items_center().justify_center().child(
        img(hero)
            .id("winmint-landing-hero")
            .w(px(640.0))
            .h(px(274.0))
            .with_fallback(move || splash_brand_lockup(fallback_logo.clone()).into_any_element()),
    )
}

pub fn titlebar_brand_mark(logo: Arc<Image>) -> Div {
    div()
        .absolute()
        .top(px(12.0))
        .left(px(20.0))
        .h(px(28.0))
        .w(px(28.0))
        .flex()
        .items_center()
        .window_control_area(WindowControlArea::Drag)
        .child(
            img(logo)
                .id("winmint-titlebar-logo")
                .w(px(28.0))
                .h(px(28.0))
                .with_fallback(|| brand_wordmark(18.0, 22.0).into_any_element()),
        )
}

pub fn status_footer(status: SharedString, spinner_phase: Option<usize>) -> Div {
    let mut footer = div()
        .h(px(48.0))
        .w_full()
        .flex()
        .items_center()
        .gap_2()
        .px_8()
        .border_t_1()
        .border_color(theme::color::border_muted())
        .text_xs()
        .text_color(theme::color::text_dim());

    if let Some(phase) = spinner_phase {
        let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
        footer = footer.child(
            div()
                .w(px(16.0))
                .h(px(16.0))
                .flex()
                .items_center()
                .justify_center()
                .text_size(px(16.0))
                .line_height(px(16.0))
                .font_family("Cascadia Code")
                .text_color(theme::color::accent())
                .child(frames[phase % frames.len()]),
        );
    }

    footer.child(status)
}

pub fn surface() -> Div {
    div()
        .rounded(px(theme::metric::RADIUS))
        .border_1()
        .border_color(theme::color::border_muted())
        .bg(theme::color::surface())
        .p(px(theme::metric::PANEL_PAD))
}

pub fn callout(message: impl Into<SharedString>, danger: bool) -> Div {
    div()
        .w_full()
        .rounded(px(theme::metric::RADIUS))
        .border_1()
        .border_color(if danger {
            theme::color::danger()
        } else {
            theme::color::warning()
        })
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
        .occlude()
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
    div()
        .flex()
        .items_center()
        .justify_center()
        .gap_4()
        .flex_wrap()
        .children(labels.iter().enumerate().map(|(i, lab)| {
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
        }))
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
        .gap_4()
        .w(px(440.0))
        .h(px(170.0))
        .px_8()
        .rounded(px(12.0))
        .border_dashed()
        .border_2()
        .border_color(theme::color::border_muted())
        .bg(theme::color::surface())
        .drag_over::<ExternalPaths>(|style, _, _, _| {
            style
                .border_color(theme::color::accent())
                .border_2()
                .bg(theme::color::accent_soft())
        })
        .child(
            div()
                .flex()
                .items_center()
                .justify_center()
                .w(px(60.0))
                .h(px(60.0))
                .rounded(px(14.0))
                .bg(theme::color::accent_soft())
                .font_family("Segoe Fluent Icons")
                .text_size(px(26.0))
                .text_color(theme::color::accent())
                .child("\u{E958}"),
        )
        .child(
            div()
                .text_size(px(15.0))
                .font_weight(FontWeight::SEMIBOLD)
                .text_center()
                .text_color(theme::color::text())
                .child("Drop your Windows ISO here"),
        )
        .child(
            div()
                .text_xs()
                .text_center()
                .text_color(theme::color::text_dim())
                .child("or click to browse"),
        )
        .on_drop(on_drop)
        .with_transition(id)
        .transition_on_hover(
            Duration::from_millis(160),
            transition::general::EaseOutQuad,
            |hovered, state| {
                if *hovered {
                    state
                        .border_color(theme::color::accent())
                        .bg(theme::color::accent_soft())
                } else {
                    state.origin()
                }
            },
        )
        .on_click(on_click)
}
