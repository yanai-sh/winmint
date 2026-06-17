//! Stable UI intent option tokens shared by Rust front ends.
#![allow(dead_code)] // Wire tokens mirror schema/catalog parity; the GUI builder uses a subset.

pub const PROFILE_NAME: &str = "WinMint";

pub const ARCH_ARM64: &str = "arm64";
pub const ARCH_AMD64: &str = "amd64";
pub const ARCH_X86: &str = "x86";
pub const ARCH_UNKNOWN: &str = "Unknown";
pub const ARCH_OPTIONS: &[&str] = &[ARCH_ARM64, ARCH_AMD64, ARCH_X86, ARCH_UNKNOWN];

pub const ACCOUNT_MODE_LOCAL: &str = "Local";
pub const ACCOUNT_MODE_MICROSOFT_OOBE: &str = "MicrosoftOobe";
pub const ACCOUNT_MODE_OPTIONS: &[&str] = &[ACCOUNT_MODE_LOCAL, ACCOUNT_MODE_MICROSOFT_OOBE];

pub const TARGET_DEVICE_THIS_PC: &str = "ThisPC";
pub const TARGET_DEVICE_DIFFERENT_PC: &str = "DifferentPC";
pub const TARGET_DEVICE_OPTIONS: &[&str] = &[TARGET_DEVICE_THIS_PC, TARGET_DEVICE_DIFFERENT_PC];

pub const FORM_FACTOR_AUTO: &str = "Auto";
pub const FORM_FACTOR_LAPTOP: &str = "Laptop";
pub const FORM_FACTOR_DESKTOP: &str = "Desktop";
pub const FORM_FACTOR_OPTIONS: &[&str] =
    &[FORM_FACTOR_AUTO, FORM_FACTOR_LAPTOP, FORM_FACTOR_DESKTOP];

pub const EDITION_HOST: &str = "Host";
pub const EDITION_HOME: &str = "Home";
pub const EDITION_PRO: &str = "Pro";
pub const EDITION_ENTERPRISE: &str = "Enterprise";
pub const EDITION_EDUCATION: &str = "Education";
pub const EDITION_SINGLE_LANGUAGE: &str = "SingleLanguage";
pub const EDITION_ALL: &str = "All";
pub const EDITION_OPTIONS: &[&str] = &[
    EDITION_HOST,
    EDITION_HOME,
    EDITION_PRO,
    EDITION_ENTERPRISE,
    EDITION_EDUCATION,
    EDITION_SINGLE_LANGUAGE,
    EDITION_ALL,
];

pub const DRIVER_SOURCE_NONE: &str = "None";
pub const DRIVER_SOURCE_HOST: &str = "Host";
pub const DRIVER_SOURCE_CUSTOM: &str = "Custom";
pub const DRIVER_SOURCE_HOST_EXPORT: &str = "HostExport";
pub const DRIVER_SOURCE_CUSTOM_INF_FOLDER: &str = "CustomInfFolder";
pub const DRIVER_SOURCE_OEM_MSI: &str = "OemMsi";
pub const DRIVER_SOURCE_SURFACE_MSI_SAFE: &str = "SurfaceMsiSafe";
pub const DRIVER_SOURCE_SURFACE_CATALOG: &str = "SurfaceCatalog";
pub const DRIVER_SOURCE_OPTIONS: &[&str] = &[
    DRIVER_SOURCE_NONE,
    DRIVER_SOURCE_HOST,
    DRIVER_SOURCE_CUSTOM,
    DRIVER_SOURCE_HOST_EXPORT,
    DRIVER_SOURCE_CUSTOM_INF_FOLDER,
    DRIVER_SOURCE_OEM_MSI,
    DRIVER_SOURCE_SURFACE_MSI_SAFE,
    DRIVER_SOURCE_SURFACE_CATALOG,
];

pub const EDITOR_CURSOR: &str = "cursor";
pub const EDITOR_VSCODE: &str = "vscode";
pub const EDITOR_ZED: &str = "zed";
pub const EDITOR_ANTIGRAVITY: &str = "antigravity";
pub const EDITOR_NEOVIM: &str = "neovim";
pub const EDITOR_OPTIONS: &[&str] = &[
    EDITOR_CURSOR,
    EDITOR_VSCODE,
    EDITOR_ZED,
    EDITOR_ANTIGRAVITY,
    EDITOR_NEOVIM,
];

pub const BROWSER_ZEN: &str = "zen-browser";
pub const BROWSER_HELIUM: &str = "helium";
pub const BROWSER_FIREFOX_DEVELOPER_EDITION: &str = "firefox-developer-edition";
pub const BROWSER_BRAVE: &str = "brave";
pub const BROWSER_EDGE: &str = "edge";
pub const BROWSER_OPTIONS: &[&str] = &[
    BROWSER_ZEN,
    BROWSER_HELIUM,
    BROWSER_FIREFOX_DEVELOPER_EDITION,
    BROWSER_BRAVE,
    BROWSER_EDGE,
];

pub const WSL_UBUNTU: &str = "Ubuntu";
pub const WSL_FEDORA: &str = "FedoraLinux";
pub const WSL_ARCHLINUX: &str = "archlinux";
pub const WSL_NIXOS: &str = "NixOS-WSL";
pub const WSL_PENGWIN: &str = "pengwin";
pub const WSL_OPTIONS: &[&str] = &[
    WSL_UBUNTU,
    WSL_FEDORA,
    WSL_ARCHLINUX,
    WSL_NIXOS,
    WSL_PENGWIN,
];

pub const SHELL_STANDARD: &str = "standard";
pub const SHELL_WINDHAWK: &str = "windhawk";
pub const SHELL_YASB: &str = "yasb";
pub const SHELL_THIDE: &str = "thide";
pub const SHELL_KOMOREBI: &str = "komorebi";
pub const SHELL_NILESOFT: &str = "nilesoft";
pub const SHELL_OPTIONS: &[&str] = &[
    SHELL_STANDARD,
    SHELL_WINDHAWK,
    SHELL_YASB,
    SHELL_THIDE,
    SHELL_KOMOREBI,
    SHELL_NILESOFT,
];
