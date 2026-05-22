use std::path::PathBuf;

use gpui::{colors::Colors, rgb, Rgba};

pub const WINDOW_MIN_WIDTH: f32 = 980.0;
pub const WINDOW_MIN_HEIGHT: f32 = 660.0;

pub mod asset {
    use super::*;

    pub fn mark() -> PathBuf {
        // Full-vector mark: panes + faceted mint leaf paths. Do not point at
        // `WinMint.svg` or `winmint-brand-final.svg` — their leaf is a raster
        // `<image>` and GPUI's SVG renderer does not load that payload.
        PathBuf::from("assets")
            .join("brand")
            .join("winmint-mark-v2.svg")
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

    pub fn sidebar() -> Rgba {
        rgb(0x1f1f1f)
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

    pub fn white() -> Rgba {
        rgb(0xffffff)
    }

    /// "Win" portion of the brand wordmark — near-white, per
    /// `assets/brand/winmint-brand-final.svg`.
    pub fn brand_win() -> Rgba {
        rgb(0xF8FAFC)
    }

    /// "Mint" portion of the brand wordmark — leaf green, per the brand SVG.
    pub fn brand_mint() -> Rgba {
        rgb(0x70C050)
    }
}
