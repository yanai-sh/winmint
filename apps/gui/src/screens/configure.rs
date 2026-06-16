//! Configure step: Windows edition, what to keep, and the target form factor.
//! Every control writes straight to the build intent and re-emits ui-intent.json,
//! so the on-disk contract always matches the wizard.

use gpui::{div, prelude::*, px, Context, Div, FontWeight, SharedString, Window};

use crate::components as ui;
use crate::options::{self, ConfigureToggle, ToggleOption};
use crate::{theme, WinMintApp};

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
    for option in options::EDITIONS {
        let value = option.value;
        let is_selected = selected.as_ref() == value;
        chips = chips.child(ui::select_chip(
            SharedString::from(format!("edition-{value}")),
            option.label,
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

fn toggle_rows(
    app: &WinMintApp,
    cx: &mut Context<WinMintApp>,
    options: &'static [ToggleOption],
) -> Vec<impl IntoElement> {
    options
        .iter()
        .map(|option| {
            let toggle = option.toggle;
            ui::toggle_row(
                option.element_id,
                option.title,
                option.description,
                is_toggle_selected(app, toggle),
                cx.listener(move |this, _, _, cx| toggle_option(this, toggle, cx)),
            )
        })
        .collect()
}

fn is_toggle_selected(app: &WinMintApp, toggle: ConfigureToggle) -> bool {
    match toggle {
        ConfigureToggle::BrowserZen => app.intent.toolkit.browser_zen,
        ConfigureToggle::BrowserHelium => app.intent.toolkit.browser_helium,
        ConfigureToggle::BrowserFirefoxDeveloperEdition => {
            app.intent.toolkit.browser_firefox_developer_edition
        }
        ConfigureToggle::BrowserBrave => app.intent.toolkit.browser_brave,
        ConfigureToggle::BrowserEdge => app.intent.toolkit.browser_edge,
        ConfigureToggle::EditorNeovim => app.intent.toolkit.editor_neovim,
        ConfigureToggle::EditorVSCode => app.intent.toolkit.editor_vscode,
        ConfigureToggle::EditorCursor => app.intent.toolkit.editor_cursor,
        ConfigureToggle::EditorZed => app.intent.toolkit.editor_zed,
        ConfigureToggle::EditorAntigravity => app.intent.toolkit.editor_antigravity,
        ConfigureToggle::ShellWindhawk => app.intent.desktop_layers.windhawk,
        ConfigureToggle::ShellYasb => app.intent.desktop_layers.yasb,
        ConfigureToggle::ShellKomorebi => app.intent.desktop_layers.komorebi,
        ConfigureToggle::ShellNilesoft => app.intent.desktop_layers.nilesoft,
        ConfigureToggle::WslUbuntu => app.intent.toolkit.wsl_ubuntu,
        ConfigureToggle::WslFedora => app.intent.toolkit.wsl_fedora,
        ConfigureToggle::WslArchlinux => app.intent.toolkit.wsl_archlinux,
        ConfigureToggle::WslNixosWsl => app.intent.toolkit.wsl_nixos_wsl,
        ConfigureToggle::WslPengwin => app.intent.toolkit.wsl_pengwin,
    }
}

fn toggle_option(app: &mut WinMintApp, toggle: ConfigureToggle, cx: &mut Context<WinMintApp>) {
    match toggle {
        ConfigureToggle::BrowserZen => app.toggle_browser_zen(cx),
        ConfigureToggle::BrowserHelium => app.toggle_browser_helium(cx),
        ConfigureToggle::BrowserFirefoxDeveloperEdition => {
            app.toggle_browser_firefox_developer_edition(cx)
        }
        ConfigureToggle::BrowserBrave => app.toggle_browser_brave(cx),
        ConfigureToggle::BrowserEdge => app.toggle_browser_edge(cx),
        ConfigureToggle::EditorNeovim => app.toggle_editor_neovim(cx),
        ConfigureToggle::EditorVSCode => app.toggle_editor_vscode(cx),
        ConfigureToggle::EditorCursor => app.toggle_editor_cursor(cx),
        ConfigureToggle::EditorZed => app.toggle_editor_zed(cx),
        ConfigureToggle::EditorAntigravity => app.toggle_editor_antigravity(cx),
        ConfigureToggle::ShellWindhawk => app.toggle_shell_windhawk(cx),
        ConfigureToggle::ShellYasb => app.toggle_shell_yasb(cx),
        ConfigureToggle::ShellKomorebi => app.toggle_shell_komorebi(cx),
        ConfigureToggle::ShellNilesoft => app.toggle_shell_nilesoft(cx),
        ConfigureToggle::WslUbuntu => app.toggle_wsl_ubuntu(cx),
        ConfigureToggle::WslFedora => app.toggle_wsl_fedora(cx),
        ConfigureToggle::WslArchlinux => app.toggle_wsl_archlinux(cx),
        ConfigureToggle::WslNixosWsl => app.toggle_wsl_nixos_wsl(cx),
        ConfigureToggle::WslPengwin => app.toggle_wsl_pengwin(cx),
    }
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
        .children(toggle_rows(app, cx, options::BROWSERS))
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
        .children(toggle_rows(app, cx, options::EDITORS))
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
        .children(toggle_rows(app, cx, options::SHELL_LAYERS))
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
        .children(toggle_rows(app, cx, options::WSL_DISTROS))
}

fn form_factor_card(app: &WinMintApp, cx: &mut Context<WinMintApp>) -> Div {
    let current = app.intent.form_factor.as_wire();
    let mut chips = div().flex().gap_2();
    for option in options::FORM_FACTORS {
        let value = option.value;
        let form_factor = option.form_factor;
        let is_selected = current == value;
        chips = chips.child(ui::select_chip(
            SharedString::from(format!("formfactor-{value}")),
            option.label,
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
