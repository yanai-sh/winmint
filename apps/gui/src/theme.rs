use std::path::PathBuf;

use gpui::{colors::Colors, rgb, Rgba};

pub const WINDOW_MIN_WIDTH: f32 = 980.0;
pub const WINDOW_MIN_HEIGHT: f32 = 660.0;

pub mod metric {
    pub const RADIUS: f32 = 6.0;
    pub const PANEL_PAD: f32 = 24.0;
    pub const CONTROL_H: f32 = 38.0;
}

pub mod asset {
    use super::*;

    pub fn logo() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("assets")
            .join("brand")
            .join("winmint.png")
    }
}

pub mod color {
    use super::*;

    fn palette() -> Colors {
        Colors::dark()
    }

    pub fn canvas() -> Rgba {
        palette().background
    }

    pub fn surface() -> Rgba {
        palette().container
    }

    pub fn surface_hover() -> Rgba {
        rgb(0x363636)
    }

    pub fn border_muted() -> Rgba {
        rgb(0x3a3a3a)
    }

    pub fn text() -> Rgba {
        palette().text
    }

    pub fn text_muted() -> Rgba {
        rgb(0xb0b0b0)
    }

    pub fn text_dim() -> Rgba {
        palette().disabled
    }

    pub fn accent() -> Rgba {
        palette().selected
    }

    pub fn accent_text() -> Rgba {
        palette().selected_text
    }

    pub fn danger() -> Rgba {
        rgb(0xc42b1c)
    }

    pub fn warning() -> Rgba {
        rgb(0xf2c94c)
    }

    pub fn success() -> Rgba {
        rgb(0x6ccb5f)
    }

    pub fn white() -> Rgba {
        rgb(0xffffff)
    }

    /// "Win" portion of the brand wordmark.
    pub fn brand_win() -> Rgba {
        rgb(0xF8FAFC)
    }

    /// "Mint" portion of the brand wordmark.
    pub fn brand_mint() -> Rgba {
        rgb(0x70C050)
    }
}
