//! Bridge JSON for `tools/ui-bridge/New-UiBuildProfile.ps1` (GPUI).

pub use winmint_core::profile::{build_gui_intent, DesktopLayersIntent, KeepFlags, ToolkitIntent};

pub const INTENT_RELATIVE_SEGMENTS: &[&str] = &["output", "gui", "ui-intent.json"];

pub fn intent_relative_path() -> std::path::PathBuf {
    INTENT_RELATIVE_SEGMENTS.iter().collect()
}
