//! Shared profile intent helpers for WinMint front ends.

use serde::Deserialize;
use serde_json::{json, Value};

const SUPPORTED_PROFILE_GROUPS: &[&str] =
    &["Minimal", "Developer", "CopilotPlus", "Gaming", "DesktopUI"];

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

pub fn normalized_profile_groups<'a>(selected_groups: &[&'a str]) -> Vec<&'a str> {
    let mut groups: Vec<&'a str> = vec!["Minimal"];
    for group in selected_groups {
        if *group != "Minimal" && !groups.contains(group) {
            groups.push(group);
        }
    }
    groups
}

pub fn validate_profile_groups(selected_groups: &[&str]) -> Result<(), String> {
    for group in selected_groups {
        if !SUPPORTED_PROFILE_GROUPS.contains(group) {
            return Err(format!("unsupported profile group '{group}'"));
        }
    }
    Ok(())
}

#[derive(Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "PascalCase")]
pub struct GuiIntentInput {
    pub profile: String,
    pub profile_groups: Vec<String>,
    #[serde(rename = "ISOPath")]
    pub iso_path: String,
    pub architecture: String,
    pub computer_name: String,
    pub account_name: String,
    pub account_mode: String,
    pub target_device: String,
    pub edition_mode: String,
    pub edition: String,
    pub driver_source: String,
    pub driver_path: String,
    pub desktop_ui_default: bool,
    pub install_windhawk: bool,
    pub install_yasb: bool,
    pub install_komorebi: bool,
    pub editors: Vec<String>,
    #[serde(rename = "Wsl2Distros")]
    pub wsl2_distros: Vec<String>,
    pub remove_gaming: bool,
    pub priv_location: bool,
    pub tweak_hardware_bypass: bool,
}

impl GuiIntentInput {
    pub fn normalized_value(&self) -> Result<Value, String> {
        let selected_groups = self
            .profile_groups
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>();
        validate_profile_groups(&selected_groups)?;

        let toolkit = ToolkitIntent {
            zed: self.editors.iter().any(|editor| editor == "zed"),
            neovim: self.editors.iter().any(|editor| editor == "neovim"),
            wsl_ubuntu: self.wsl2_distros.iter().any(|distro| distro == "Ubuntu"),
        };
        let desktop_layers = DesktopLayersIntent {
            windhawk: self.install_windhawk,
            yasb: self.install_yasb,
            komorebi: self.install_komorebi,
        };

        Ok(build_gui_intent(
            &self.iso_path,
            &self.architecture,
            &self.computer_name,
            &self.account_name,
            &selected_groups,
            toolkit,
            desktop_layers,
        ))
    }
}

pub fn build_gui_intent(
    iso_path: &str,
    architecture: &str,
    computer_name: &str,
    account_name: &str,
    selected_groups: &[&str],
    toolkit: ToolkitIntent,
    desktop_layers: DesktopLayersIntent,
) -> Value {
    let groups = normalized_profile_groups(selected_groups);
    let developer = groups.contains(&"Developer");
    let copilot = groups.contains(&"CopilotPlus");
    let gaming = groups.contains(&"Gaming");
    let desktop_ui = groups.contains(&"DesktopUI");

    let editors = if developer {
        editors_from_toolkit(toolkit)
    } else {
        Vec::new()
    };
    let wsl_distros = if developer {
        wsl_from_toolkit(toolkit)
    } else {
        Vec::new()
    };

    let installs = if desktop_ui {
        desktop_layers
    } else {
        DesktopLayersIntent {
            windhawk: false,
            yasb: false,
            komorebi: false,
        }
    };

    json!({
        "Profile": "Minimal",
        "ProfileGroups": groups,
        "SetupOption": if copilot { "CopilotPlus" } else { "Minimal" },
        "ISOPath": iso_path,
        "Architecture": architecture,
        "ComputerName": computer_name,
        "AccountName": account_name,
        "AccountMode": "Local",
        "TargetDevice": "DifferentPC",
        "EditionMode": "TargetLicense",
        "Edition": "",
        "DriverSource": "None",
        "DriverPath": "",
        "DesktopUiDefault": desktop_ui,
        "InstallWindhawk": installs.windhawk,
        "InstallYasb": installs.yasb,
        "InstallKomorebi": installs.komorebi,
        "Editors": editors,
        "Wsl2Distros": wsl_distros,
        "RemoveGaming": !gaming,
        "PrivLocation": true,
        "TweakHardwareBypass": false,
        "TweakDmaInterop": true
    })
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

    fn assert_intent_keys(intent: &Value) {
        let obj = intent.as_object().expect("object");
        let required = [
            "Profile",
            "ProfileGroups",
            "SetupOption",
            "ISOPath",
            "Architecture",
            "ComputerName",
            "AccountName",
            "AccountMode",
            "TargetDevice",
            "EditionMode",
            "Edition",
            "DriverSource",
            "DriverPath",
            "DesktopUiDefault",
            "InstallWindhawk",
            "InstallYasb",
            "InstallKomorebi",
            "Editors",
            "Wsl2Distros",
            "RemoveGaming",
            "PrivLocation",
            "TweakHardwareBypass",
            "TweakDmaInterop",
        ];
        for key in required {
            assert!(obj.contains_key(key), "missing key {key}");
        }
    }

    #[test]
    fn normalized_profile_groups_minimal_first_and_dedupes() {
        let g = normalized_profile_groups(&["Developer", "Minimal", "Gaming", "Developer"]);
        assert_eq!(g, vec!["Minimal", "Developer", "Gaming"]);
    }

    #[test]
    fn validate_profile_groups_rejects_unsupported_values() {
        assert!(validate_profile_groups(&["Minimal", "DesktopUI"]).is_ok());
        assert_eq!(
            validate_profile_groups(&["Minimal", "Unsupported"]).unwrap_err(),
            "unsupported profile group 'Unsupported'"
        );
    }

    #[test]
    fn intent_minimal_only_shapes_defaults() {
        let intent = build_gui_intent(
            "D:\\iso\\win.iso",
            "amd64",
            "WinMint",
            "dev",
            &["Minimal"],
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
        );
        assert_intent_keys(&intent);
        assert_eq!(intent["ISOPath"], "D:\\iso\\win.iso");
        assert_eq!(intent["Profile"], "Minimal");
        assert_eq!(str_vec(&intent["ProfileGroups"]), vec!["Minimal"]);
        assert_eq!(intent["SetupOption"], "Minimal");
        assert_eq!(intent["RemoveGaming"], true);
        assert_eq!(str_vec(&intent["Editors"]).len(), 0);
        assert_eq!(str_vec(&intent["Wsl2Distros"]).len(), 0);
        assert_eq!(intent["DesktopUiDefault"], false);
        assert_eq!(intent["InstallWindhawk"], false);
    }

    #[test]
    fn intent_developer_adds_editors_and_wsl() {
        let intent = build_gui_intent(
            "",
            "arm64",
            "M",
            "u",
            &["Minimal", "Developer"],
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
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
            &["Developer"],
            lite,
            DesktopLayersIntent::default(),
        );
        assert_eq!(str_vec(&intent2["Editors"]), vec!["zed"]);
        assert_eq!(str_vec(&intent2["Wsl2Distros"]).len(), 0);
    }

    #[test]
    fn intent_copilot_setup_option_and_gaming_remove_flag() {
        let with_copilot = build_gui_intent(
            "",
            "amd64",
            "a",
            "b",
            &["CopilotPlus", "Minimal"],
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
        );
        assert_eq!(with_copilot["SetupOption"], "CopilotPlus");

        let with_gaming = build_gui_intent(
            "",
            "amd64",
            "a",
            "b",
            &["Minimal", "Gaming"],
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
        );
        assert_eq!(with_gaming["RemoveGaming"], false);

        let no_gaming = build_gui_intent(
            "",
            "amd64",
            "a",
            "b",
            &["Minimal"],
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
        );
        assert_eq!(no_gaming["RemoveGaming"], true);
    }

    #[test]
    fn intent_desktop_layers_independent_when_desktop_group() {
        let layers = DesktopLayersIntent {
            windhawk: true,
            yasb: false,
            komorebi: true,
        };
        let intent = build_gui_intent(
            "",
            "amd64",
            "a",
            "b",
            &["DesktopUI", "Minimal"],
            ToolkitIntent::default(),
            layers,
        );
        assert_eq!(intent["DesktopUiDefault"], true);
        assert_eq!(intent["InstallWindhawk"], true);
        assert_eq!(intent["InstallYasb"], false);
        assert_eq!(intent["InstallKomorebi"], true);
    }

    #[test]
    fn gui_intent_input_normalizes_through_shared_builder() {
        let input = GuiIntentInput {
            profile: "Minimal".to_string(),
            profile_groups: vec!["Developer".to_string(), "Minimal".to_string()],
            iso_path: "D:\\iso\\win.iso".to_string(),
            architecture: "arm64".to_string(),
            computer_name: "WinMint".to_string(),
            account_name: "dev".to_string(),
            account_mode: "Local".to_string(),
            target_device: "DifferentPC".to_string(),
            edition_mode: "TargetLicense".to_string(),
            edition: "".to_string(),
            driver_source: "None".to_string(),
            driver_path: "".to_string(),
            desktop_ui_default: false,
            install_windhawk: true,
            install_yasb: true,
            install_komorebi: true,
            editors: vec!["zed".to_string()],
            wsl2_distros: vec!["Ubuntu".to_string()],
            remove_gaming: true,
            priv_location: false,
            tweak_hardware_bypass: false,
        };

        let normalized = input.normalized_value().expect("normalized intent");
        assert_eq!(
            str_vec(&normalized["ProfileGroups"]),
            vec!["Minimal", "Developer"]
        );
        assert_eq!(str_vec(&normalized["Editors"]), vec!["zed"]);
        assert_eq!(str_vec(&normalized["Wsl2Distros"]), vec!["Ubuntu"]);
        assert_eq!(normalized["InstallWindhawk"], false);
    }
}
