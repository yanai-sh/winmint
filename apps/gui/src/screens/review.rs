//! Review step (scaffold). Shows the generated build manifest and output ISO.

use gpui::{Context, IntoElement, Window};

use crate::WinMintApp;

pub fn render(_app: &WinMintApp, _window: &mut Window, _cx: &mut Context<WinMintApp>) -> impl IntoElement {
    crate::screens::placeholder("Review", "Coming soon — inspect the manifest and output ISO.")
}
