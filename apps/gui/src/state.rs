use gpui::SharedString;
use serde::Deserialize;

use crate::bridge::BuildDeltaSummary;
use crate::intent::{DesktopLayersIntent, KeepFlags, ToolkitIntent};

pub const SPLASH_STATUS_PICK: &str = "Select a Windows ISO to begin.";

/// Target form factor for the generated image. `Auto` resolves the chassis at
/// first boot; `Laptop`/`Desktop` force the power profile. All three are wire
/// values consumed by the engine and selectable on the Configure screen.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum FormFactor {
    #[default]
    Auto,
    Laptop,
    Desktop,
}

impl FormFactor {
    /// Stable string emitted into the intent JSON and consumed by the engine.
    pub fn as_wire(self) -> &'static str {
        match self {
            FormFactor::Auto => "Auto",
            FormFactor::Laptop => "Laptop",
            FormFactor::Desktop => "Desktop",
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum SourceProbeStatus {
    Empty,
    Preparing,
    Ready,
    Failed,
}

/// Ordered wizard steps. `Source` gates progression (Next unlocks once a source
/// is Ready); the rest are scaffolded for continued development.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum WizardStep {
    Source,
    Configure,
    Build,
    Review,
}

impl WizardStep {
    pub const ORDER: [WizardStep; 4] = [
        WizardStep::Source,
        WizardStep::Configure,
        WizardStep::Build,
        WizardStep::Review,
    ];

    pub fn title(self) -> &'static str {
        match self {
            WizardStep::Source => "Source",
            WizardStep::Configure => "Configure",
            WizardStep::Build => "Build",
            WizardStep::Review => "Review",
        }
    }

    pub fn index(self) -> usize {
        Self::ORDER.iter().position(|s| *s == self).unwrap_or(0)
    }

    pub fn next(self) -> Self {
        Self::ORDER.get(self.index() + 1).copied().unwrap_or(self)
    }

    pub fn prev(self) -> Self {
        let i = self.index();
        if i == 0 {
            self
        } else {
            Self::ORDER[i - 1]
        }
    }

    pub fn is_first(self) -> bool {
        self.index() == 0
    }

    pub fn is_last(self) -> bool {
        self.index() + 1 == Self::ORDER.len()
    }
}

#[derive(Debug, Deserialize)]
pub struct UiIsoMetadata {
    #[serde(rename = "Ok")]
    pub ok: bool,
    #[serde(rename = "Architecture")]
    pub architecture: String,
    #[serde(rename = "Editions", default)]
    pub editions: Vec<String>,
    #[serde(rename = "Error", default)]
    pub error: String,
}

pub struct BuildIntent {
    pub architecture: SharedString,
    pub computer_name: SharedString,
    pub account_name: SharedString,
    pub form_factor: FormFactor,
    /// Subtractive default: all keep flags false = remove everything.
    pub keep: KeepFlags,
    /// Edition selector token (Host/Home/Pro/Enterprise/Education/SingleLanguage/All
    /// or an exact name); resolved engine-side. Defaults to host-edition detection.
    pub edition: SharedString,
    pub toolkit: ToolkitIntent,
    pub desktop_layers: DesktopLayersIntent,
}

impl Default for BuildIntent {
    fn default() -> Self {
        Self {
            architecture: "ARM64".into(),
            computer_name: "WinMint".into(),
            account_name: "dev".into(),
            form_factor: FormFactor::Auto,
            keep: KeepFlags::default(),
            edition: "Host".into(),
            toolkit: ToolkitIntent::default(),
            desktop_layers: DesktopLayersIntent::default(),
        }
    }
}

pub struct SourceProbeState {
    pub iso_path: SharedString,
    pub iso_size: SharedString,
    pub status: SourceProbeStatus,
    pub file_picker_open: bool,
    pub generation: u64,
    pub mount_viewport_w: f32,
    pub mount_viewport_h: f32,
    pub detected_architecture: SharedString,
    pub editions: Vec<SharedString>,
    pub error: SharedString,
}

impl Default for SourceProbeState {
    fn default() -> Self {
        Self {
            iso_path: "".into(),
            iso_size: "".into(),
            status: SourceProbeStatus::Empty,
            file_picker_open: false,
            generation: 0,
            mount_viewport_w: 0.0,
            mount_viewport_h: 0.0,
            detected_architecture: "".into(),
            editions: Vec::new(),
            error: "".into(),
        }
    }
}

impl SourceProbeState {
    pub fn reset(&mut self) {
        self.generation = self.generation.wrapping_add(1);
        self.iso_path = "".into();
        self.iso_size = "".into();
        self.status = SourceProbeStatus::Empty;
        self.file_picker_open = false;
        self.mount_viewport_w = 0.0;
        self.mount_viewport_h = 0.0;
        self.detected_architecture = "".into();
        self.editions.clear();
        self.error = "".into();
    }

    pub fn mark_ready(&mut self, metadata: UiIsoMetadata) {
        self.status = SourceProbeStatus::Ready;
        self.file_picker_open = false;
        self.detected_architecture = metadata.architecture.into();
        self.editions = metadata
            .editions
            .into_iter()
            .map(SharedString::from)
            .collect();
        self.error = "".into();
    }

    pub fn mark_failed(&mut self, error: impl Into<String>) {
        self.status = SourceProbeStatus::Failed;
        self.file_picker_open = false;
        self.detected_architecture = "".into();
        self.editions.clear();
        self.error = error.into().into();
    }
}

pub struct BuildRunState {
    pub status: SharedString,
    pub spinner_phase: usize,
    pub running: bool,
    pub profile_path: SharedString,
    pub output_path: SharedString,
    pub build_delta_path: SharedString,
    pub build_delta_summary: BuildDeltaSummary,
    pub report_path: SharedString,
    pub last_progress: SharedString,
}

impl Default for BuildRunState {
    fn default() -> Self {
        Self {
            status: SPLASH_STATUS_PICK.into(),
            spinner_phase: 0,
            running: false,
            profile_path: "".into(),
            output_path: "".into(),
            build_delta_path: "".into(),
            build_delta_summary: BuildDeltaSummary::default(),
            report_path: "".into(),
            last_progress: "".into(),
        }
    }
}

pub struct ManifestViewState {
    pub manifest_path: SharedString,
}

impl Default for ManifestViewState {
    fn default() -> Self {
        Self {
            manifest_path: "".into(),
        }
    }
}

pub struct ViewState {
    pub custom_titlebar: bool,
}

impl ViewState {
    pub fn new(custom_titlebar: bool) -> Self {
        Self { custom_titlebar }
    }
}
