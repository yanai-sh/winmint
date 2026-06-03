//! Wizard screens. Each module exposes `render(app, window, cx)` returning the
//! screen body; the root view (`WinMintApp`) routes to one based on the current
//! `WizardStep`. Add a step by adding a module here + a `WizardStep` variant.

use gpui::{div, prelude::*, FontWeight, IntoElement};

use crate::theme;

pub mod build;
pub mod configure;
pub mod review;
pub mod source;

/// Centered title + subtitle used by not-yet-built steps.
pub fn placeholder(title: &'static str, subtitle: &'static str) -> impl IntoElement {
    div()
        .flex()
        .flex_col()
        .items_center()
        .gap_3()
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
                .child(subtitle),
        )
}
