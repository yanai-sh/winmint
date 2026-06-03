//! Configure step (scaffold). Workstation profile, privacy, and tweaks land here.

use gpui::{Context, IntoElement, Window};

use crate::WinMintApp;

pub fn render(_app: &WinMintApp, _window: &mut Window, _cx: &mut Context<WinMintApp>) -> impl IntoElement {
    crate::screens::placeholder(
        "Configure",
        "Coming soon — workstation profile, privacy, and tweaks.",
    )
}
