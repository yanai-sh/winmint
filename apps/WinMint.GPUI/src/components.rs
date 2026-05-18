#![allow(dead_code)]
// Palette of composed controls; GPUI is splash-only for now but posture/tiles
// remain for when multi-beat authoring returns.

use gpui::{div, img, prelude::*, px, Div, ExternalPaths, FontWeight, Stateful, WindowControlArea};

use crate::theme;

pub fn app_frame() -> Div {
    div()
        .size_full()
        .bg(theme::color::canvas())
        .text_color(theme::color::text())
        .flex()
        .flex_col()
}

pub const SPLASH_MARK_SIZE: f32 = 160.0;
pub const SPLASH_WORDMARK_TEXT: f32 = 78.0;
pub const SPLASH_WORDMARK_LH: f32 = 88.0;
pub const SPLASH_WORDMARK_W: f32 = 440.0;
pub const SPLASH_WORDMARK_GAP: f32 = 28.0;
pub const SPLASH_GROUP_W: f32 = SPLASH_MARK_SIZE + SPLASH_WORDMARK_GAP + SPLASH_WORDMARK_W;
pub const SPLASH_GROUP_H: f32 = 174.0;
pub const DOCKED_MARK_SIZE: f32 = 58.0;
const DOCK_LEFT: f32 = 30.0;
const DOCK_TOP: f32 = 28.0;

pub fn titlebar_hit_regions() -> Div {
    div()
        .absolute()
        .top(px(0.0))
        .left(px(0.0))
        .right(px(132.0))
        .h(px(72.0))
        .window_control_area(WindowControlArea::Drag)
}

pub fn flying_brand(progress: f32, activity: f32, window_w: f32, window_h: f32) -> Div {
    let collapse = crate::anim::ease_in_out_cubic(crate::anim::phase(progress, 0.0, 0.42));
    let hold = crate::anim::phase(progress, 0.42, 0.62);
    let fly = crate::anim::ease_in_out_cubic(crate::anim::phase(progress, 0.62, 0.94));
    let settle = crate::anim::phase(progress, 0.94, 1.0);
    let docking = fly > 0.0;

    let mark_size = crate::anim::lerp(SPLASH_MARK_SIZE, DOCKED_MARK_SIZE, fly);
    let lockup_left = (window_w - SPLASH_GROUP_W) / 2.0;
    let lockup_top = window_h * 0.22;
    let centered_mark_left = (window_w - SPLASH_MARK_SIZE) / 2.0;
    let centered_mark_top = lockup_top + (SPLASH_GROUP_H - SPLASH_MARK_SIZE) / 2.0;
    let end_left = DOCK_LEFT;
    let end_top = DOCK_TOP;
    let bounce = if settle > 0.0 {
        crate::anim::damped_sin(settle, 1.3, 5.0) * 3.0
    } else {
        0.0
    };
    let merged_mark_left = crate::anim::lerp(lockup_left, centered_mark_left, collapse);
    let merged_mark_top = centered_mark_top;
    let mark_left = crate::anim::lerp(merged_mark_left, end_left, fly) + bounce;
    let mark_top = crate::anim::lerp(merged_mark_top, end_top, fly);
    let wordmark_left = crate::anim::lerp(
        lockup_left + SPLASH_MARK_SIZE + SPLASH_WORDMARK_GAP,
        window_w / 2.0 - SPLASH_WORDMARK_W - SPLASH_WORDMARK_GAP,
        collapse,
    );
    let wordmark_top = lockup_top + (SPLASH_GROUP_H - SPLASH_WORDMARK_LH) / 2.0;
    let wordmark_opacity = (1.0 - crate::anim::phase(collapse, 0.64, 1.0)).clamp(0.0, 1.0);
    let show_wordmark = fly <= 0.01 && wordmark_opacity > 0.01 && hold < 1.0;
    let waiting = !docking && hold > 0.0;
    let pulse = if waiting {
        ((activity * std::f32::consts::TAU * 1.25).sin() + 1.0) * 0.5
    } else {
        0.0
    };
    let shake = if waiting {
        (activity * std::f32::consts::TAU * 4.6).sin() * 3.0
    } else {
        0.0
    };
    let active_mark_size = mark_size + pulse * 5.0;

    let wordmark = div()
        .absolute()
        .left(px(wordmark_left))
        .top(px(wordmark_top))
        .w(px(SPLASH_WORDMARK_W))
        .h(px(SPLASH_WORDMARK_LH))
        .opacity(wordmark_opacity)
        .child(brand_wordmark(SPLASH_WORDMARK_TEXT, SPLASH_WORDMARK_LH));

    let mark = div()
        .absolute()
        .left(px(mark_left + shake - (active_mark_size - mark_size) / 2.0))
        .top(px(mark_top - (active_mark_size - mark_size) / 2.0))
        .w(px(active_mark_size))
        .h(px(active_mark_size))
        .opacity(crate::anim::lerp(1.0, 0.92, pulse))
        .child(mark_image(active_mark_size));

    let mut group = div()
        .absolute()
        .left(px(0.0))
        .top(px(0.0))
        .size_full();
    if show_wordmark {
        group = group.child(wordmark);
    }
    group.child(mark)
}

/// Brand-styled wordmark used in the splash flight. Two adjacent colored
/// text divs — there are no multi-color spans in GPUI 0.2.2. Colors and font
/// match `assets/brand/winmint-brand-final.svg`: "Win" #F8FAFC, "Mint"
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

pub fn splash_brand_lockup() -> Div {
    div()
        .flex()
        .items_center()
        .justify_center()
        .gap_5()
        .child(mark_image(96.0))
        .child(brand_wordmark(54.0, 62.0))
}

pub fn wordmark(text_size: f32, line_height: f32) -> Div {
    div()
        .font_family("Segoe UI Variable Display")
        .font_weight(FontWeight::SEMIBOLD)
        .text_size(px(text_size))
        .line_height(px(line_height))
        .text_color(theme::color::text())
        .child("WinMint")
}

pub fn compact_brand() -> Div {
    div()
        .flex()
        .items_center()
        .gap_3()
        .child(mark_image(42.0))
        .child(wordmark(34.0, 38.0))
}

fn mark_image(size: f32) -> gpui::Img {
    img(theme::asset::mark())
        .w(px(size))
        .h(px(size))
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
        .px_5()
        .py_2()
        .rounded_sm()
        .bg(theme::color::accent())
        .text_color(theme::color::accent_text())
        .hover(|style| style.bg(theme::color::white()).cursor_pointer())
        .child(label)
}

pub fn secondary_button(id: &'static str, label: &'static str) -> Stateful<Div> {
    div()
        .id(id)
        .px_4()
        .py_2()
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

pub fn iso_landing_well(id: &'static str) -> Stateful<Div> {
    div()
        .id(id)
        .cursor_pointer()
        .flex()
        .flex_col()
        .items_center()
        .justify_center()
        .gap_3()
        .w_full()
        .h(px(200.))
        .p_8()
        .rounded_md()
        .border_dashed()
        .border_2()
        .border_color(theme::color::border_muted())
        .bg(theme::color::surface())
        .drag_over::<ExternalPaths>(|style, _, _, _| {
            style.border_color(theme::color::accent()).border_2().bg(theme::color::surface_hover())
        })
        .hover(|style| style.border_color(theme::color::text_muted()).bg(theme::color::surface_hover()))
        .child(fluent_icon_block("\u{E958}", 40.))
        .child(
            div()
                .text_lg()
                .text_center()
                .text_color(theme::color::text())
                .child("Drop your Windows ISO"),
        )
        .child(
            div()
                .text_sm()
                .text_center()
                .text_color(theme::color::text_muted())
                .child("Release to attach, or click anywhere here to browse."),
        )
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
