//! Wizard navigation actions + key bindings.

use gpui::{actions, App, KeyBinding};

actions!(winmint, [Next, Back]);

/// Bind arrow/enter/escape to wizard navigation within the `WinMint` key context.
pub fn bind_keys(cx: &mut App) {
    cx.bind_keys([
        KeyBinding::new("right", Next, Some("WinMint")),
        KeyBinding::new("enter", Next, Some("WinMint")),
        KeyBinding::new("left", Back, Some("WinMint")),
        KeyBinding::new("escape", Back, Some("WinMint")),
    ]);
}
