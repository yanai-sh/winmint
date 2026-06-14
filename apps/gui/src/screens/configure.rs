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
        .child(browser_card(app, cx))
        .child(editor_card(app, cx))
        .child(shell_card(app, cx))
        .child(wsl_card(app, cx))
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

fn browser_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_2()
        .child(section_title(
            "Browsers",
            "Pick any browsers you want installed. Leave everything off for no browser.",
        ))
        .child(ui::toggle_row(
            "browser-zen",
            "Zen Browser",
            "Install Zen Browser.",
            app.intent.toolkit.browser_zen,
            cx.listener(|this, _, _, cx| this.toggle_browser_zen(cx)),
        ))
        .child(ui::toggle_row(
            "browser-helium",
            "Helium",
            "Install Helium.",
            app.intent.toolkit.browser_helium,
            cx.listener(|this, _, _, cx| this.toggle_browser_helium(cx)),
        ))
        .child(ui::toggle_row(
            "browser-librewolf",
            "LibreWolf",
            "Install LibreWolf.",
            app.intent.toolkit.browser_librewolf,
            cx.listener(|this, _, _, cx| this.toggle_browser_librewolf(cx)),
        ))
        .child(ui::toggle_row(
            "browser-brave",
            "Brave",
            "Install Brave.",
            app.intent.toolkit.browser_brave,
            cx.listener(|this, _, _, cx| this.toggle_browser_brave(cx)),
        ))
        .child(ui::toggle_row(
            "browser-edge",
            "Microsoft Edge",
            "Keep Microsoft Edge installed.",
            app.intent.toolkit.browser_edge,
            cx.listener(|this, _, _, cx| this.toggle_browser_edge(cx)),
        ))
}

fn editor_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_2()
        .child(section_title(
            "Editors",
            "Pick any editors you want installed. Leave everything off for none.",
        ))
        .child(ui::toggle_row(
            "editor-neovim",
            "Neovim",
            "Install Neovim.",
            app.intent.toolkit.editor_neovim,
            cx.listener(|this, _, _, cx| this.toggle_editor_neovim(cx)),
        ))
        .child(ui::toggle_row(
            "editor-vscode",
            "Visual Studio Code",
            "Install Visual Studio Code.",
            app.intent.toolkit.editor_vscode,
            cx.listener(|this, _, _, cx| this.toggle_editor_vscode(cx)),
        ))
        .child(ui::toggle_row(
            "editor-cursor",
            "Cursor",
            "Install Cursor.",
            app.intent.toolkit.editor_cursor,
            cx.listener(|this, _, _, cx| this.toggle_editor_cursor(cx)),
        ))
        .child(ui::toggle_row(
            "editor-zed",
            "Zed",
            "Install Zed.",
            app.intent.toolkit.editor_zed,
            cx.listener(|this, _, _, cx| this.toggle_editor_zed(cx)),
        ))
        .child(ui::toggle_row(
            "editor-antigravity",
            "Antigravity",
            "Install Antigravity.",
            app.intent.toolkit.editor_antigravity,
            cx.listener(|this, _, _, cx| this.toggle_editor_antigravity(cx)),
        ))
}

fn shell_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_2()
        .child(section_title(
            "Shell",
            "Pick any shell layers you want installed. Leave everything off for standard Windows.",
        ))
        .child(ui::toggle_row(
            "shell-windhawk",
            "Windhawk",
            "Install Windhawk.",
            app.intent.desktop_layers.windhawk,
            cx.listener(|this, _, _, cx| this.toggle_shell_windhawk(cx)),
        ))
        .child(ui::toggle_row(
            "shell-yasb",
            "YASB",
            "Install YASB.",
            app.intent.desktop_layers.yasb,
            cx.listener(|this, _, _, cx| this.toggle_shell_yasb(cx)),
        ))
        .child(ui::toggle_row(
            "shell-komorebi",
            "Komorebi",
            "Install Komorebi.",
            app.intent.desktop_layers.komorebi,
            cx.listener(|this, _, _, cx| this.toggle_shell_komorebi(cx)),
        ))
        .child(ui::toggle_row(
            "shell-nilesoft",
            "Nilesoft Shell",
            "Install Nilesoft Shell.",
            app.intent.desktop_layers.nilesoft,
            cx.listener(|this, _, _, cx| this.toggle_shell_nilesoft(cx)),
        ))
}

fn wsl_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    ui::surface()
        .w_full()
        .flex()
        .flex_col()
        .gap_2()
        .child(section_title(
            "WSL",
            "Pick any WSL distros you want installed. WSL2 itself stays enabled either way.",
        ))
        .child(ui::toggle_row(
            "wsl-ubuntu",
            "Ubuntu",
            "Install Ubuntu.",
            app.intent.toolkit.wsl_ubuntu,
            cx.listener(|this, _, _, cx| this.toggle_wsl_ubuntu(cx)),
        ))
        .child(ui::toggle_row(
            "wsl-fedora",
            "Fedora",
            "Install the latest Fedora WSL image.",
            app.intent.toolkit.wsl_fedora,
            cx.listener(|this, _, _, cx| this.toggle_wsl_fedora(cx)),
        ))
        .child(ui::toggle_row(
            "wsl-archlinux",
            "Arch Linux",
            "Install Arch Linux.",
            app.intent.toolkit.wsl_archlinux,
            cx.listener(|this, _, _, cx| this.toggle_wsl_archlinux(cx)),
        ))
        .child(ui::toggle_row(
            "wsl-nixos-wsl",
            "NixOS-WSL",
            "Install NixOS-WSL from the community release.",
            app.intent.toolkit.wsl_nixos_wsl,
            cx.listener(|this, _, _, cx| this.toggle_wsl_nixos_wsl(cx)),
        ))
        .child(ui::toggle_row(
            "wsl-pengwin",
            "Pengwin",
            "Install Pengwin.",
            app.intent.toolkit.wsl_pengwin,
            cx.listener(|this, _, _, cx| this.toggle_wsl_pengwin(cx)),
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
