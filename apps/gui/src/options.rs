//! GUI option catalog: display metadata mapped to stable winmint-core wire tokens.

use crate::state::FormFactor;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConfigureToggle {
    BrowserZen,
    BrowserHelium,
    BrowserLibreWolf,
    BrowserBrave,
    BrowserEdge,
    EditorNeovim,
    EditorVSCode,
    EditorCursor,
    EditorZed,
    EditorAntigravity,
    ShellWindhawk,
    ShellYasb,
    ShellKomorebi,
    ShellNilesoft,
    WslUbuntu,
    WslFedora,
    WslArchlinux,
    WslNixosWsl,
    WslPengwin,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SelectOption {
    pub value: &'static str,
    pub label: &'static str,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct FormFactorOption {
    pub value: &'static str,
    pub label: &'static str,
    pub form_factor: FormFactor,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ToggleOption {
    pub element_id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub toggle: ConfigureToggle,
}

pub const EDITIONS: &[SelectOption] = &[
    SelectOption {
        value: winmint_core::options::EDITION_HOST,
        label: "Host",
    },
    SelectOption {
        value: winmint_core::options::EDITION_HOME,
        label: "Home",
    },
    SelectOption {
        value: winmint_core::options::EDITION_PRO,
        label: "Pro",
    },
    SelectOption {
        value: winmint_core::options::EDITION_ENTERPRISE,
        label: "Enterprise",
    },
    SelectOption {
        value: winmint_core::options::EDITION_EDUCATION,
        label: "Education",
    },
    SelectOption {
        value: winmint_core::options::EDITION_SINGLE_LANGUAGE,
        label: "Single Language",
    },
    SelectOption {
        value: winmint_core::options::EDITION_ALL,
        label: "All",
    },
];

pub const FORM_FACTORS: &[FormFactorOption] = &[
    FormFactorOption {
        value: winmint_core::options::FORM_FACTOR_AUTO,
        label: "Auto",
        form_factor: FormFactor::Auto,
    },
    FormFactorOption {
        value: winmint_core::options::FORM_FACTOR_LAPTOP,
        label: "Laptop",
        form_factor: FormFactor::Laptop,
    },
    FormFactorOption {
        value: winmint_core::options::FORM_FACTOR_DESKTOP,
        label: "Desktop",
        form_factor: FormFactor::Desktop,
    },
];

pub const BROWSERS: &[ToggleOption] = &[
    ToggleOption {
        element_id: "browser-zen",
        title: "Zen Browser",
        description: "Install Zen Browser.",
        toggle: ConfigureToggle::BrowserZen,
    },
    ToggleOption {
        element_id: "browser-helium",
        title: "Helium",
        description: "Install Helium.",
        toggle: ConfigureToggle::BrowserHelium,
    },
    ToggleOption {
        element_id: "browser-librewolf",
        title: "LibreWolf",
        description: "Install LibreWolf.",
        toggle: ConfigureToggle::BrowserLibreWolf,
    },
    ToggleOption {
        element_id: "browser-brave",
        title: "Brave",
        description: "Install Brave.",
        toggle: ConfigureToggle::BrowserBrave,
    },
    ToggleOption {
        element_id: "browser-edge",
        title: "Microsoft Edge",
        description: "Keep Microsoft Edge installed.",
        toggle: ConfigureToggle::BrowserEdge,
    },
];

pub const EDITORS: &[ToggleOption] = &[
    ToggleOption {
        element_id: "editor-neovim",
        title: "Neovim",
        description: "Install Neovim.",
        toggle: ConfigureToggle::EditorNeovim,
    },
    ToggleOption {
        element_id: "editor-vscode",
        title: "Visual Studio Code",
        description: "Install Visual Studio Code.",
        toggle: ConfigureToggle::EditorVSCode,
    },
    ToggleOption {
        element_id: "editor-cursor",
        title: "Cursor",
        description: "Install Cursor.",
        toggle: ConfigureToggle::EditorCursor,
    },
    ToggleOption {
        element_id: "editor-zed",
        title: "Zed",
        description: "Install Zed.",
        toggle: ConfigureToggle::EditorZed,
    },
    ToggleOption {
        element_id: "editor-antigravity",
        title: "Antigravity",
        description: "Install Antigravity.",
        toggle: ConfigureToggle::EditorAntigravity,
    },
];

pub const SHELL_LAYERS: &[ToggleOption] = &[
    ToggleOption {
        element_id: "shell-windhawk",
        title: "Windhawk",
        description: "Install Windhawk.",
        toggle: ConfigureToggle::ShellWindhawk,
    },
    ToggleOption {
        element_id: "shell-yasb",
        title: "YASB",
        description: "Install YASB.",
        toggle: ConfigureToggle::ShellYasb,
    },
    ToggleOption {
        element_id: "shell-komorebi",
        title: "Komorebi",
        description: "Install Komorebi.",
        toggle: ConfigureToggle::ShellKomorebi,
    },
    ToggleOption {
        element_id: "shell-nilesoft",
        title: "Nilesoft Shell",
        description: "Install Nilesoft Shell.",
        toggle: ConfigureToggle::ShellNilesoft,
    },
];

pub const WSL_DISTROS: &[ToggleOption] = &[
    ToggleOption {
        element_id: "wsl-ubuntu",
        title: "Ubuntu",
        description: "Install Ubuntu.",
        toggle: ConfigureToggle::WslUbuntu,
    },
    ToggleOption {
        element_id: "wsl-fedora",
        title: "Fedora",
        description: "Install the latest Fedora WSL image.",
        toggle: ConfigureToggle::WslFedora,
    },
    ToggleOption {
        element_id: "wsl-archlinux",
        title: "Arch Linux",
        description: "Install Arch Linux.",
        toggle: ConfigureToggle::WslArchlinux,
    },
    ToggleOption {
        element_id: "wsl-nixos-wsl",
        title: "NixOS-WSL",
        description: "Install NixOS-WSL from the community release.",
        toggle: ConfigureToggle::WslNixosWsl,
    },
    ToggleOption {
        element_id: "wsl-pengwin",
        title: "Pengwin",
        description: "Install Pengwin.",
        toggle: ConfigureToggle::WslPengwin,
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn edition_catalog_should_follow_core_order() {
        let values = EDITIONS
            .iter()
            .map(|option| option.value)
            .collect::<Vec<_>>();

        assert_eq!(values, winmint_core::options::EDITION_OPTIONS);
    }

    #[test]
    fn form_factor_catalog_should_follow_core_order() {
        let values = FORM_FACTORS
            .iter()
            .map(|option| option.value)
            .collect::<Vec<_>>();

        assert_eq!(values, winmint_core::options::FORM_FACTOR_OPTIONS);
    }
}
