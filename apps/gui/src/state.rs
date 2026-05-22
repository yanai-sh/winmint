use gpui::SharedString;
use serde::Deserialize;

use crate::intent::{DesktopLayersIntent, ToolkitIntent};

pub const SPLASH_STATUS_PICK: &str = "Select a Windows ISO to begin.";

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum WizardStage {
    Source,
    ProfileGroups,
    DeveloperOptions,
    DesktopUiOptions,
    IdentityAndDisk,
    Review,
    Build,
}

impl WizardStage {
    pub const FLOW: [WizardStage; 7] = [
        WizardStage::Source,
        WizardStage::ProfileGroups,
        WizardStage::DeveloperOptions,
        WizardStage::DesktopUiOptions,
        WizardStage::IdentityAndDisk,
        WizardStage::Review,
        WizardStage::Build,
    ];

    pub fn label(self) -> &'static str {
        match self {
            WizardStage::Source => "Source",
            WizardStage::ProfileGroups => "Profile",
            WizardStage::DeveloperOptions => "Developer",
            WizardStage::DesktopUiOptions => "Desktop UI",
            WizardStage::IdentityAndDisk => "Identity",
            WizardStage::Review => "Review",
            WizardStage::Build => "Build",
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

impl SourceProbeStatus {
    pub fn label(self) -> &'static str {
        match self {
            SourceProbeStatus::Empty => "Waiting",
            SourceProbeStatus::Preparing => "Checking",
            SourceProbeStatus::Ready => "Ready",
            SourceProbeStatus::Failed => "Needs attention",
        }
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
    pub selected_groups: Vec<&'static str>,
    pub toolkit: ToolkitIntent,
    pub desktop_layers: DesktopLayersIntent,
}

impl Default for BuildIntent {
    fn default() -> Self {
        Self {
            architecture: "ARM64".into(),
            computer_name: "WinMint".into(),
            account_name: "dev".into(),
            selected_groups: vec!["Minimal"],
            toolkit: ToolkitIntent::default(),
            desktop_layers: DesktopLayersIntent::default(),
        }
    }
}

pub struct SourceProbeState {
    pub iso_path: SharedString,
    pub status: SourceProbeStatus,
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
            status: SourceProbeStatus::Empty,
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
        self.status = SourceProbeStatus::Empty;
        self.mount_viewport_w = 0.0;
        self.mount_viewport_h = 0.0;
        self.detected_architecture = "".into();
        self.editions.clear();
        self.error = "".into();
    }

    pub fn mark_ready(&mut self, metadata: UiIsoMetadata) {
        self.status = SourceProbeStatus::Ready;
        self.detected_architecture = metadata.architecture.into();
        self.editions = metadata.editions.into_iter().map(SharedString::from).collect();
        self.error = "".into();
    }

    pub fn mark_failed(&mut self, error: impl Into<String>) {
        self.status = SourceProbeStatus::Failed;
        self.detected_architecture = "".into();
        self.editions.clear();
        self.error = error.into().into();
    }
}

pub struct BuildRunState {
    pub status: SharedString,
}

impl Default for BuildRunState {
    fn default() -> Self {
        Self {
            status: SPLASH_STATUS_PICK.into(),
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
    pub stage: WizardStage,
    pub custom_titlebar: bool,
}

impl ViewState {
    pub fn new(custom_titlebar: bool) -> Self {
        Self {
            stage: WizardStage::Source,
            custom_titlebar,
        }
    }
}
