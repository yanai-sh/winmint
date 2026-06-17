//! Bridge JSON for `tools/ui-bridge/New-UiBuildProfile.ps1` (GPUI).

pub use crate::core::profile::{build_gui_intent, DesktopLayersIntent, KeepFlags, ToolkitIntent};

pub const INTENT_RELATIVE_SEGMENTS: &[&str] = &["output", "gui", "ui-intent.json"];
