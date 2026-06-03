//! Build step (scaffold). Triggers the engine and streams progress here.

use gpui::{Context, IntoElement, Window};

use crate::WinMintApp;

pub fn render(_app: &WinMintApp, _window: &mut Window, _cx: &mut Context<WinMintApp>) -> impl IntoElement {
    crate::screens::placeholder("Build", "Coming soon — run the build and watch progress.")
}
