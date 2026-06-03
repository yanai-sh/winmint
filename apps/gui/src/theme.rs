use std::path::PathBuf;

use gpui::{colors::Colors, rgb, Hsla, Rgba};

pub const WINDOW_MIN_WIDTH: f32 = 980.0;
pub const WINDOW_MIN_HEIGHT: f32 = 660.0;

pub mod metric {
    pub const RADIUS: f32 = 6.0;
    pub const PANEL_PAD: f32 = 24.0;
    pub const CONTROL_H: f32 = 38.0;
}

pub mod asset {
    use super::*;

    fn brand_path(file_name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("assets")
            .join("brand")
            .join(file_name)
    }

    pub fn full_logo() -> PathBuf {
        brand_path("winmint_full.png")
    }

    pub fn full_ui_logo() -> PathBuf {
        brand_path("winmint_full_ui_132.png")
    }

    pub fn full_squircle_logo() -> PathBuf {
        brand_path("winmint_full_squircle.png")
    }

    pub fn full_squircle_ui_logo() -> PathBuf {
        brand_path("winmint_full_squircle_ui_28.png")
    }

    pub fn simple_ui_logo() -> PathBuf {
        brand_path("winmint_simple_ui_28.png")
    }

    pub fn logo() -> PathBuf {
        full_ui_logo()
    }

    pub fn simple_logo() -> PathBuf {
        brand_path("winmint_simple.png")
    }

    pub fn hero_logo() -> PathBuf {
        brand_path("winmint_hero.png")
    }

    /// UI-sized (@2x) hero — high-quality downscale of the full hero, sized so the
    /// GPU only scales it gently (the full-res hero aliases when downscaled ~3x).
    pub fn hero_ui_logo() -> PathBuf {
        brand_path("winmint_hero_ui.png")
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

    /// Accent at low opacity, for tinted fills (icon tiles, drop-zone hover).
    pub fn accent_soft() -> Hsla {
        Hsla::from(accent()).opacity(0.14)
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
