//! Bridge JSON for `tools/ui-bridge/New-UiBuildProfile.ps1` (GPUI).

use serde_json::{json, Value};

pub const INTENT_RELATIVE_SEGMENTS: &[&str] = &["output", "gpui", "ui-intent.json"];

pub fn intent_relative_path() -> std::path::PathBuf {
    INTENT_RELATIVE_SEGMENTS.iter().collect()
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

pub fn build_gpui_intent(
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
        "PrivLocation": false,
        "TweakHardwareBypass": false
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
    fn intent_minimal_only_shapes_defaults() {
        let intent = build_gpui_intent(
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
        let intent = build_gpui_intent(
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
        let intent2 =
            build_gpui_intent("", "amd64", "a", "b", &["Developer"], lite, DesktopLayersIntent::default());
        assert_eq!(str_vec(&intent2["Editors"]), vec!["zed"]);
        assert_eq!(str_vec(&intent2["Wsl2Distros"]).len(), 0);
    }

    #[test]
    fn intent_copilot_setup_option_and_gaming_remove_flag() {
        let with_copilot = build_gpui_intent(
            "",
            "amd64",
            "a",
            "b",
            &["CopilotPlus", "Minimal"],
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
        );
        assert_eq!(with_copilot["SetupOption"], "CopilotPlus");

        let with_gaming = build_gpui_intent(
            "",
            "amd64",
            "a",
            "b",
            &["Minimal", "Gaming"],
            ToolkitIntent::default(),
            DesktopLayersIntent::default(),
        );
        assert_eq!(with_gaming["RemoveGaming"], false);

        let no_gaming = build_gpui_intent(
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
        let intent = build_gpui_intent(
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
}
