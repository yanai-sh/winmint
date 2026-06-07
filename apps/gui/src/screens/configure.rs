//! Configure step: Windows edition, what to keep, and the target form factor.
//! Every control writes straight to the build intent and re-emits ui-intent.json,
//! so the on-disk contract always matches the wizard.

use gpui::{div, prelude::*, px, Context, Div, FontWeight, SharedString, Window};

use crate::components as ui;
use crate::state::FormFactor;
use crate::{theme, WinMintApp};

/// Edition selector tokens (value, label). Resolved engine-side: `Host` detects
/// this machine's edition, `All` services every edition, the rest pin one.
const EDITIONS: [(&str, &str); 7] = [
    ("Host", "Host"),
    ("Home", "Home"),
    ("Pro", "Pro"),
    ("Enterprise", "Enterprise"),
    ("Education", "Education"),
    ("SingleLanguage", "Single Language"),
    ("All", "All"),
];

const FORM_FACTORS: [(&str, &str, FormFactor); 3] = [
    ("Auto", "Auto", FormFactor::Auto),
    ("Laptop", "Laptop", FormFactor::Laptop),
    ("Desktop", "Desktop", FormFactor::Desktop),
];

pub fn render(app: &WinMintApp, _window: &mut Window, cx: &mut Context<WinMintApp>) -> Div {
    div()
        .w_full()
        .max_w(px(560.0))
        .flex()
        .flex_col()
        .gap_4()
        .child(
            div()
                .text_lg()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::color::text())
                .child("Configure your build"),
        )
        .child(edition_card(app, cx))
        .child(keep_card(app, cx))
        .child(form_factor_card(app, cx))
}

fn section_title(title: &'static str, hint: &'static str) -> Div {
    div()
        .flex()
        .flex_col()
        .gap_1()
        .child(
            div()
                .text_sm()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme::color::text())
                .child(title),
        )
        .child(
            div()
                .text_xs()
                .text_color(theme::color::text_dim())
                .child(hint),
        )
}

fn edition_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    let selected = app.intent.edition.clone();
    let mut chips = div().flex().flex_wrap().gap_2();
    for (value, label) in EDITIONS {
        let is_selected = selected.as_ref() == value;
        chips = chips.child(ui::select_chip(
            SharedString::from(format!("edition-{value}")),
            label,
            is_selected,
            cx.listener(move |this, _, _, cx| this.set_edition(value, cx)),
        ));
    }

    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_3()
        .child(section_title(
            "Windows edition",
            "Pick the edition to service. Host detects this machine's edition.",
        ))
        .child(chips)
}

fn keep_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_2()
        .child(section_title(
            "Keep",
            "Everything is removed by default. Turn an item on to keep it.",
        ))
        .child(ui::toggle_row(
            "keep-edge",
            "Microsoft Edge",
            "Keep the Edge browser and its WebView components.",
            app.intent.keep.edge,
            cx.listener(|this, _, _, cx| this.toggle_keep_edge(cx)),
        ))
        .child(ui::toggle_row(
            "keep-gaming",
            "Xbox & gaming",
            "Keep the Xbox app, Game Bar, and gaming services.",
            app.intent.keep.gaming,
            cx.listener(|this, _, _, cx| this.toggle_keep_gaming(cx)),
        ))
        .child(ui::toggle_row(
            "keep-copilot",
            "Copilot",
            "Keep Windows Copilot and Recall AI components.",
            app.intent.keep.copilot,
            cx.listener(|this, _, _, cx| this.toggle_keep_copilot(cx)),
        ))
}

fn form_factor_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    let current = app.intent.form_factor.as_wire();
    let mut chips = div().flex().gap_2();
    for (value, label, form_factor) in FORM_FACTORS {
        let is_selected = current == value;
        chips = chips.child(ui::select_chip(
            SharedString::from(format!("formfactor-{value}")),
            label,
            is_selected,
            cx.listener(move |this, _, _, cx| this.set_form_factor(form_factor, cx)),
        ));
    }

    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_3()
        .child(section_title(
            "Form factor",
            "Tunes the power profile. Auto resolves the chassis at first boot.",
        ))
        .child(chips)
}
