//! Shared profile intent helpers for WinMint front ends.
//!
//! WinMint uses a subtractive **keep-flag** profile model: the default build
//! removes everything (full AI removal, Edge browser, Xbox/gaming, OneDrive) and
//! `KeepEdge`/`KeepGaming`/`KeepCopilot` opt a domain back in. Editors, WSL, and
//! the desktop shell layers are independent installs; `Edition` is a selector
//! token resolved engine-side. This module is the single source of truth for the
//! flat `ui-intent.json` consumed by `tools/ui-bridge/New-UiBuildProfile.ps1`.

use serde::Serialize;
use serde_json::Value;

/// Clamp an arbitrary form-factor string to the supported set, defaulting to `Auto`.
pub fn normalized_form_factor(value: &str) -> &'static str {
    match value {
        "Laptop" => "Laptop",
        "Desktop" => "Desktop",
        _ => "Auto",
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ToolkitIntent {
    pub zed: bool,
    pub neovim: bool,
    pub wsl_ubuntu: bool,
}

impl Default for ToolkitIntent {
    fn default() -> Self {
        Self {
            zed: true,
            neovim: true,
            wsl_ubuntu: true,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DesktopLayersIntent {
    pub windhawk: bool,
    pub yasb: bool,
    pub komorebi: bool,
}

impl Default for DesktopLayersIntent {
    fn default() -> Self {
        Self {
            windhawk: true,
            yasb: true,
            komorebi: true,
        }
    }
}

/// Opt-in "keep" flags. Every field false is the subtractive default (remove
/// everything); a true flag suppresses that domain's removal.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub struct KeepFlags {
    pub edge: bool,
    pub gaming: bool,
    pub copilot: bool,
}

pub fn editors_from_toolkit(toolkit: ToolkitIntent) -> Vec<&'static str> {
    let mut editors = Vec::new();
    if toolkit.zed {
        editors.push("zed");
    }
    if toolkit.neovim {
        editors.push("neovim");
    }
    editors
}

pub fn wsl_from_toolkit(toolkit: ToolkitIntent) -> Vec<&'static str> {
    if toolkit.wsl_ubuntu {
        vec!["Ubuntu"]
    } else {
        Vec::new()
    }
}

/// Clamp the edition selector token. `Host` (default) detects the build host's
/// edition engine-side; `All` services every edition; the rest pin one edition.
/// An unrecognized value is passed through verbatim (an exact edition name is a
/// valid power-user selector that the engine resolves).
pub fn normalized_edition(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return "Host".to_string();
    }
    trimmed.to_string()
}

/// Typed, serializable build intent — the single source of truth for the flat
/// `ui-intent.json` consumed by `tools/ui-bridge/New-UiBuildProfile.ps1`.
///
/// Field order and serialized names match that contract exactly; `#[serde(rename)]`
/// pins the two keys PascalCase would otherwise reshape (`ISOPath`, `Wsl2Distros`).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct UiIntent {
    pub profile: &'static str,
    pub keep_edge: bool,
    pub keep_gaming: bool,
    pub keep_copilot: bool,
    #[serde(rename = "ISOPath")]
    pub iso_path: String,
    pub architecture: String,
    pub computer_name: String,
    pub account_name: String,
    pub account_mode: &'static str,
    pub target_device: &'static str,
    pub form_factor: &'static str,
    pub edition: String,
    pub driver_source: &'static str,
    pub driver_path: &'static str,
    pub install_windhawk: bool,
    pub install_yasb: bool,
    pub install_komorebi: bool,
    pub editors: Vec<&'static str>,
    #[serde(rename = "Wsl2Distros")]
    pub wsl2_distros: Vec<&'static str>,
    pub priv_location: bool,
    pub tweak_hardware_bypass: bool,
    pub tweak_dma_interop: bool,
}

/// Build the typed intent from flat wizard inputs. In the keep-flag model the
/// keep flags, editors/WSL, desktop layers, and edition selector are all explicit
/// — there is no profile-group gating or gaming-removal inversion to apply.
#[allow(clippy::too_many_arguments)] // Mirrors the wizard's flat intent fields one-to-one.
pub fn build_ui_intent(
    iso_path: &str,
    architecture: &str,
    computer_name: &str,
    account_name: &str,
    keep: KeepFlags,
    edition: &str,
    toolkit: ToolkitIntent,
    desktop_layers: DesktopLayersIntent,
    form_factor: &str,
) -> UiIntent {
    UiIntent {
        profile: "WinMint",
        keep_edge: keep.edge,
        keep_gaming: keep.gaming,
        keep_copilot: keep.copilot,
        iso_path: iso_path.to_string(),
        architecture: architecture.to_string(),
        computer_name: computer_name.to_string(),
        account_name: account_name.to_string(),
        account_mode: "Local",
        target_device: "DifferentPC",
        form_factor: normalized_form_factor(form_factor),
        edition: normalized_edition(edition),
        driver_source: "None",
        driver_path: "",
        install_windhawk: desktop_layers.windhawk,
        install_yasb: desktop_layers.yasb,
        install_komorebi: desktop_layers.komorebi,
        editors: editors_from_toolkit(toolkit),
        wsl2_distros: wsl_from_toolkit(toolkit),
        priv_location: true,
        tweak_hardware_bypass: false,
        tweak_dma_interop: true,
    }
}

/// JSON form of [`build_ui_intent`] for the GUI's intent writer and the PowerShell
/// bridge; the typed [`UiIntent`] is the source of truth.
#[allow(clippy::too_many_arguments)]
pub fn build_gui_intent(
    iso_path: &str,
    architecture: &str,
    computer_name: &str,
    account_name: &str,
    keep: KeepFlags,
    edition: &str,
    toolkit: ToolkitIntent,
    desktop_layers: DesktopLayersIntent,
    form_factor: &str,
) -> Value {
    serde_json::to_value(build_ui_intent(
        iso_path,
        architecture,
        computer_name,
        account_name,
        keep,
        edition,
        toolkit,
        desktop_layers,
        form_factor,
    ))
    .expect("UiIntent always serializes")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn str_vec(value: &Value) -> Vec<String> {
        value
            .as_array()
            .expect("array")
            .iter()
            .map(|v| v.as_str().expect("string").to_string())
            .collect()
    }

    const EXPECTED_INTENT_KEYS: [&str; 22] = [
        "Profile",
        "KeepEdge",
        "KeepGaming",
        "KeepCopilot",
        "ISOPath",
        "Architecture",
        "ComputerName",
        "AccountName",
        "AccountMode",
        "TargetDevice",
        "FormFactor",
        "Edition",
        "DriverSource",
        "DriverPath",
        "InstallWindhawk",
        "InstallYasb",
        "InstallKomorebi",
        "Editors",
        "Wsl2Distros",
        "PrivLocation",
        "TweakHardwareBypass",
        "TweakDmaInterop",
    ];

    fn sample(keep: KeepFlags, edition: &str, form_factor: &str) -> Value {
        build_gui_intent(
            "D:\\iso\\win.iso",
            "arm64",
            "WinMint",
            "dev",
            keep,
            edition,
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
            form_factor,
        )
    }

    #[test]
    fn ui_intent_serializes_to_the_exact_bridge_contract_keys() {
        // Guards `tools/ui-bridge/New-UiBuildProfile.ps1` — exact key set and count.
        let intent = build_ui_intent(
            "D:\\iso\\win.iso",
            "amd64",
            "WinMint",
            "dev",
            KeepFlags::default(),
            "Host",
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
            "Desktop",
        );
        let value = serde_json::to_value(&intent).expect("UiIntent serializes");
        let obj = value.as_object().expect("object");
        assert_eq!(
            obj.len(),
            EXPECTED_INTENT_KEYS.len(),
            "UiIntent emitted an unexpected number of keys: {:?}",
            obj.keys().collect::<Vec<_>>()
        );
        for key in EXPECTED_INTENT_KEYS {
            assert!(obj.contains_key(key), "missing intent key {key}");
        }
    }

    #[test]
    fn default_is_subtractive_remove_everything() {
        let intent = sample(KeepFlags::default(), "Host", "Auto");
        assert_eq!(intent["Profile"], "WinMint");
        assert_eq!(intent["KeepEdge"], false);
        assert_eq!(intent["KeepGaming"], false);
        assert_eq!(intent["KeepCopilot"], false);
        assert_eq!(intent["Edition"], "Host");
        assert_eq!(intent["FormFactor"], "Auto");
        assert_eq!(intent["TweakDmaInterop"], true);
        assert_eq!(intent["PrivLocation"], true);
    }

    #[test]
    fn keep_flags_pass_through() {
        let intent = sample(
            KeepFlags {
                edge: true,
                gaming: true,
                copilot: false,
            },
            "Pro",
            "Desktop",
        );
        assert_eq!(intent["KeepEdge"], true);
        assert_eq!(intent["KeepGaming"], true);
        assert_eq!(intent["KeepCopilot"], false);
        assert_eq!(intent["Edition"], "Pro");
        assert_eq!(intent["FormFactor"], "Desktop");
    }

    #[test]
    fn edition_token_normalizes_blank_to_host() {
        let intent = sample(KeepFlags::default(), "   ", "Auto");
        assert_eq!(intent["Edition"], "Host");
    }

    #[test]
    fn editors_and_wsl_are_explicit_not_group_gated() {
        // Editors/WSL come straight from the toolkit now — no Developer group.
        let intent = build_gui_intent(
            "",
            "arm64",
            "M",
            "u",
            KeepFlags::default(),
            "Home",
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
            "Auto",
        );
        assert_eq!(str_vec(&intent["Editors"]), vec!["zed", "neovim"]);
        assert_eq!(str_vec(&intent["Wsl2Distros"]), vec!["Ubuntu"]);

        let lite = ToolkitIntent {
            zed: true,
            neovim: false,
            wsl_ubuntu: false,
        };
        let intent2 = build_gui_intent(
            "",
            "amd64",
            "a",
            "b",
            KeepFlags::default(),
            "Home",
            lite,
            DesktopLayersIntent::default(),
            "Auto",
        );
        assert_eq!(str_vec(&intent2["Editors"]), vec!["zed"]);
        assert_eq!(str_vec(&intent2["Wsl2Distros"]).len(), 0);
    }

    #[test]
    fn desktop_layers_are_explicit_not_group_gated() {
        let layers = DesktopLayersIntent {
            windhawk: true,
            yasb: false,
            komorebi: true,
        };
        let intent = build_gui_intent(
            "",
            "arm64",
            "a",
            "b",
            KeepFlags::default(),
            "Home",
            ToolkitIntent::default(),
            layers,
            "Desktop",
        );
        assert_eq!(intent["InstallWindhawk"], true);
        assert_eq!(intent["InstallYasb"], false);
        assert_eq!(intent["InstallKomorebi"], true);
    }

    #[test]
    fn form_factor_is_clamped() {
        assert_eq!(normalized_form_factor("Laptop"), "Laptop");
        assert_eq!(normalized_form_factor("nonsense"), "Auto");
    }
}
