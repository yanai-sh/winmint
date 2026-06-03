//! Backend bridge: side-effecting calls into the repository's PowerShell tooling.
//!
//! Kept separate from the view layer so rendering stays pure and the IO surface
//! (process spawning, repo paths) has a single home as more bridge calls land.

use std::path::PathBuf;
use std::process::Command;

use crate::state::UiIsoMetadata;

/// Repository root, resolved relative to this crate (`apps/gui`).
pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
}

/// Probe a Windows ISO via `tools/ui-bridge/Get-UiIsoMetadata.ps1`.
pub fn run_source_probe(repo_root: PathBuf, path: String) -> Result<UiIsoMetadata, String> {
    let script = repo_root
        .join("tools")
        .join("ui-bridge")
        .join("Get-UiIsoMetadata.ps1");
    let output = Command::new("pwsh")
        .arg("-NoProfile")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(&script)
        .arg("-Path")
        .arg(&path)
        .current_dir(repo_root)
        .output()
        .map_err(|error| format!("Could not start PowerShell source probe: {error}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            return Err(format!(
                "PowerShell source probe exited with {}.",
                output.status
            ));
        }
        return Err(stderr);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str::<UiIsoMetadata>(stdout.trim())
        .map_err(|error| format!("Source probe returned invalid JSON: {error}"))
}
