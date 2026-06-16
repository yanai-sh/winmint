//! Backend bridge: side-effecting calls into the repository's PowerShell tooling.
//!
//! Kept separate from the view layer so rendering stays pure and the IO surface
//! (process spawning, repo paths) has a single home as more bridge calls land.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{de::DeserializeOwned, Deserialize};

use crate::intent::{self, DesktopLayersIntent, KeepFlags, ToolkitIntent};
use crate::state::UiIsoMetadata;

/// Repository root, resolved relative to this crate (`apps/gui`).
pub fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
}

#[derive(Clone, Copy)]
#[allow(dead_code)]
pub enum UiBridgeScript {
    SourcePreview,
    ProfileGeneration,
    BuildInvocation,
}

impl UiBridgeScript {
    fn file_name(self) -> &'static str {
        match self {
            UiBridgeScript::SourcePreview => "Get-UiIsoMetadata.ps1",
            UiBridgeScript::ProfileGeneration => "New-UiBuildProfile.ps1",
            UiBridgeScript::BuildInvocation => "Start-UiBuildFromProfile.ps1",
        }
    }
}

fn script_path(repo_root: &Path, script: UiBridgeScript) -> PathBuf {
    repo_root
        .join("tools")
        .join("ui-bridge")
        .join(script.file_name())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BridgeCommandSpec {
    program: String,
    args: Vec<String>,
    current_dir: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct BridgeCommandOutput {
    success: bool,
    status: String,
    stdout: Vec<u8>,
    stderr: Vec<u8>,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "PascalCase")]
pub struct BridgeProgressEvent {
    #[serde(default)]
    pub time: String,
    #[serde(default)]
    pub stage: String,
    #[serde(default)]
    pub level: String,
    #[serde(default)]
    pub message: String,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "PascalCase")]
pub struct BridgeBuildResult {
    pub ok: bool,
    pub dry_run: bool,
    #[serde(default)]
    pub output_path: String,
    #[serde(default)]
    pub output_iso_path: String,
    #[serde(default)]
    pub manifest_path: String,
    #[serde(default)]
    pub build_delta_path: String,
    #[serde(default)]
    pub report_path: String,
    #[serde(default)]
    pub progress: Vec<BridgeProgressEvent>,
    #[serde(default)]
    pub error: String,
    #[serde(skip_deserializing, default)]
    pub build_delta: BuildDeltaSummary,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BuildDeltaSummary {
    pub total_records: usize,
    pub user_controlled_records: usize,
    pub phase_counts: Vec<(String, usize)>,
    pub highlighted_records: Vec<BuildDeltaRecordSummary>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildDeltaRecordSummary {
    pub title: String,
    pub phase: String,
    pub kind: String,
    pub change_count: usize,
}

#[derive(Debug, Deserialize)]
struct BuildDeltaDocument {
    #[serde(default)]
    records: Vec<BuildDeltaRecord>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BuildDeltaRecord {
    #[serde(default)]
    title: String,
    #[serde(default)]
    phase: String,
    #[serde(default)]
    kind: String,
    #[serde(default)]
    user_controlled: bool,
    #[serde(default)]
    changes: Vec<String>,
}

trait BridgeCommandRunner {
    fn run(&self, spec: &BridgeCommandSpec) -> Result<BridgeCommandOutput, String>;
}

struct SystemBridgeCommandRunner;

impl BridgeCommandRunner for SystemBridgeCommandRunner {
    fn run(&self, spec: &BridgeCommandSpec) -> Result<BridgeCommandOutput, String> {
        let output = Command::new(&spec.program)
            .args(&spec.args)
            .current_dir(&spec.current_dir)
            .output()
            .map_err(|error| format!("Could not start PowerShell bridge command: {error}"))?;

        Ok(BridgeCommandOutput {
            success: output.status.success(),
            status: output.status.to_string(),
            stdout: output.stdout,
            stderr: output.stderr,
        })
    }
}

fn powershell_script_command(repo_root: &Path, script: UiBridgeScript) -> BridgeCommandSpec {
    BridgeCommandSpec {
        program: "pwsh".to_string(),
        args: vec![
            "-NoProfile".to_string(),
            "-ExecutionPolicy".to_string(),
            "Bypass".to_string(),
            "-File".to_string(),
            script_path(repo_root, script).display().to_string(),
        ],
        current_dir: repo_root.to_path_buf(),
    }
}

fn source_probe_command(repo_root: &Path, path: &str) -> BridgeCommandSpec {
    let mut spec = powershell_script_command(repo_root, UiBridgeScript::SourcePreview);
    spec.args.push("-Path".to_string());
    spec.args.push(path.to_string());
    spec
}

fn profile_generation_command(
    repo_root: &Path,
    settings_path: &Path,
    output_path: &Path,
) -> BridgeCommandSpec {
    let mut spec = powershell_script_command(repo_root, UiBridgeScript::ProfileGeneration);
    spec.args.push("-RepositoryRoot".to_string());
    spec.args.push(repo_root.display().to_string());
    spec.args.push("-SettingsPath".to_string());
    spec.args.push(settings_path.display().to_string());
    spec.args.push("-OutputPath".to_string());
    spec.args.push(output_path.display().to_string());
    spec
}

fn build_invocation_command(
    repo_root: &Path,
    profile_path: &Path,
    dry_run: bool,
) -> BridgeCommandSpec {
    let mut spec = powershell_script_command(repo_root, UiBridgeScript::BuildInvocation);
    spec.args.push("-RepositoryRoot".to_string());
    spec.args.push(repo_root.display().to_string());
    spec.args.push("-ProfilePath".to_string());
    spec.args.push(profile_path.display().to_string());
    if dry_run {
        spec.args.push("-DryRun".to_string());
    }
    spec
}

fn require_powershell_success(output: BridgeCommandOutput, label: &str) -> Result<(), String> {
    if output.success {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if !stderr.is_empty() {
        return Err(stderr);
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if !stdout.is_empty() {
        return Err(stdout);
    }

    Err(format!("PowerShell {label} exited with {}.", output.status))
}

fn json_payload(stdout: &str) -> &str {
    let trimmed = stdout.trim();
    if trimmed.starts_with('{') || trimmed.starts_with('[') {
        return trimmed;
    }
    trimmed
        .lines()
        .rev()
        .map(str::trim)
        .find(|line| line.starts_with('{') || line.starts_with('['))
        .unwrap_or(trimmed)
}

fn parse_powershell_json<T: DeserializeOwned>(
    output: BridgeCommandOutput,
    label: &str,
) -> Result<T, String> {
    if !output.success {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            return Err(format!("PowerShell {label} exited with {}.", output.status));
        }
        return Err(stderr);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str::<T>(json_payload(&stdout))
        .map_err(|error| format!("{label} returned invalid JSON: {error}"))
}

fn parse_powershell_result_json<T: DeserializeOwned>(
    output: BridgeCommandOutput,
    label: &str,
) -> Result<T, String> {
    let stdout = String::from_utf8_lossy(&output.stdout);
    match serde_json::from_str::<T>(json_payload(&stdout)) {
        Ok(value) => Ok(value),
        Err(_) if !output.success => {
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if stderr.is_empty() {
                Err(format!("PowerShell {label} exited with {}.", output.status))
            } else {
                Err(stderr)
            }
        }
        Err(parse_error) => Err(format!("{label} returned invalid JSON: {parse_error}")),
    }
}

pub struct UiIntentInput<'a> {
    pub source_iso: &'a str,
    pub architecture: &'a str,
    pub computer_name: &'a str,
    pub account_name: &'a str,
    pub keep: KeepFlags,
    pub edition: &'a str,
    pub toolkit: ToolkitIntent,
    pub desktop_layers: DesktopLayersIntent,
    pub form_factor: &'a str,
}

pub fn ui_intent_path(repo_root: &Path) -> PathBuf {
    let mut path = repo_root.to_path_buf();
    for segment in intent::INTENT_RELATIVE_SEGMENTS {
        path.push(segment);
    }
    path
}

pub fn build_profile_path(repo_root: &Path) -> PathBuf {
    repo_root
        .join("output")
        .join("gui")
        .join("BuildProfile.json")
}

pub fn write_ui_intent(repo_root: &Path, input: UiIntentInput<'_>) -> Result<PathBuf, String> {
    let payload = intent::build_gui_intent(
        input.source_iso,
        input.architecture,
        input.computer_name,
        input.account_name,
        input.keep,
        input.edition,
        input.toolkit,
        input.desktop_layers,
        input.form_factor,
    );
    let json = serde_json::to_string_pretty(&payload)
        .map_err(|error| format!("Could not serialize intent: {error}"))?;
    let output_path = ui_intent_path(repo_root);
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent).map_err(|error| {
            format!(
                "Could not create intent output directory {}: {error}",
                parent.display()
            )
        })?;
    }
    fs::write(&output_path, json)
        .map_err(|error| format!("Could not write intent {}: {error}", output_path.display()))?;
    Ok(output_path)
}

#[allow(dead_code)]
pub fn generate_build_profile(repo_root: PathBuf) -> Result<PathBuf, String> {
    generate_build_profile_with(&SystemBridgeCommandRunner, &repo_root)
}

fn generate_build_profile_with(
    runner: &impl BridgeCommandRunner,
    repo_root: &Path,
) -> Result<PathBuf, String> {
    let settings_path = ui_intent_path(repo_root);
    let output_path = build_profile_path(repo_root);
    let spec = profile_generation_command(repo_root, &settings_path, &output_path);
    let output = runner.run(&spec)?;
    require_powershell_success(output, "profile generation")?;
    Ok(output_path)
}

#[allow(dead_code)]
pub fn start_build_from_profile(
    repo_root: PathBuf,
    profile_path: PathBuf,
    dry_run: bool,
) -> Result<BridgeBuildResult, String> {
    start_build_from_profile_with(
        &SystemBridgeCommandRunner,
        &repo_root,
        &profile_path,
        dry_run,
    )
}

fn start_build_from_profile_with(
    runner: &impl BridgeCommandRunner,
    repo_root: &Path,
    profile_path: &Path,
    dry_run: bool,
) -> Result<BridgeBuildResult, String> {
    let spec = build_invocation_command(repo_root, profile_path, dry_run);
    let output = runner.run(&spec)?;
    let mut result: BridgeBuildResult = parse_powershell_result_json(output, "Build invocation")?;
    result.build_delta = load_build_delta_summary(&result.build_delta_path);
    Ok(result)
}

fn load_build_delta_summary(path: &str) -> BuildDeltaSummary {
    if path.trim().is_empty() {
        return BuildDeltaSummary::default();
    }

    let Ok(json) = fs::read_to_string(path) else {
        return BuildDeltaSummary::default();
    };
    let Ok(document) = serde_json::from_str::<BuildDeltaDocument>(&json) else {
        return BuildDeltaSummary::default();
    };

    let mut phase_counts = std::collections::BTreeMap::<String, usize>::new();
    let mut user_controlled_records = 0usize;
    let mut highlighted_records = Vec::new();

    for record in &document.records {
        if !record.phase.is_empty() {
            *phase_counts.entry(record.phase.clone()).or_default() += 1;
        }
        if record.user_controlled {
            user_controlled_records += 1;
        }
    }

    for record in document.records.iter().take(8) {
        highlighted_records.push(BuildDeltaRecordSummary {
            title: record.title.clone(),
            phase: record.phase.clone(),
            kind: record.kind.clone(),
            change_count: record.changes.len(),
        });
    }

    BuildDeltaSummary {
        total_records: document.records.len(),
        user_controlled_records,
        phase_counts: phase_counts.into_iter().collect(),
        highlighted_records,
    }
}

/// Probe a Windows ISO via `tools/ui-bridge/Get-UiIsoMetadata.ps1`.
pub fn run_source_probe(repo_root: PathBuf, path: String) -> Result<UiIsoMetadata, String> {
    run_source_probe_with(&SystemBridgeCommandRunner, &repo_root, &path)
}

fn run_source_probe_with(
    runner: &impl BridgeCommandRunner,
    repo_root: &Path,
    path: &str,
) -> Result<UiIsoMetadata, String> {
    let spec = source_probe_command(repo_root, path);
    let output = runner.run(&spec)?;
    parse_powershell_json(output, "Source probe")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    struct FakeRunner {
        output: Result<BridgeCommandOutput, String>,
    }

    impl BridgeCommandRunner for FakeRunner {
        fn run(&self, spec: &BridgeCommandSpec) -> Result<BridgeCommandOutput, String> {
            assert_eq!(spec.program, "pwsh");
            assert!(spec
                .args
                .iter()
                .any(|arg| arg.ends_with("Get-UiIsoMetadata.ps1")));
            assert!(spec.args.iter().any(|arg| arg == "-Path"));
            self.output.clone()
        }
    }

    struct CapturingRunner {
        output: Result<BridgeCommandOutput, String>,
        specs: RefCell<Vec<BridgeCommandSpec>>,
    }

    impl CapturingRunner {
        fn new(output: BridgeCommandOutput) -> Self {
            Self {
                output: Ok(output),
                specs: RefCell::new(Vec::new()),
            }
        }

        fn first_spec(&self) -> BridgeCommandSpec {
            self.specs
                .borrow()
                .first()
                .expect("bridge command should run")
                .clone()
        }
    }

    impl BridgeCommandRunner for CapturingRunner {
        fn run(&self, spec: &BridgeCommandSpec) -> Result<BridgeCommandOutput, String> {
            self.specs.borrow_mut().push(spec.clone());
            self.output.clone()
        }
    }

    fn ok_output(stdout: &str) -> BridgeCommandOutput {
        BridgeCommandOutput {
            success: true,
            status: "exit status: 0".to_string(),
            stdout: stdout.as_bytes().to_vec(),
            stderr: Vec::new(),
        }
    }

    #[test]
    fn source_probe_should_parse_successful_bridge_json() {
        let runner = FakeRunner {
            output: Ok(ok_output(
                r#"{"Ok":true,"Architecture":"ARM64","Editions":["Windows 11 Home"],"Error":""}"#,
            )),
        };

        let metadata = run_source_probe_with(&runner, Path::new("C:\\repo"), "C:\\iso\\win.iso")
            .expect("source probe should parse");

        assert_eq!(metadata.architecture, "ARM64");
    }

    #[test]
    fn source_probe_should_prefer_stderr_on_failed_bridge_command() {
        let runner = FakeRunner {
            output: Ok(BridgeCommandOutput {
                success: false,
                status: "exit status: 1".to_string(),
                stdout: Vec::new(),
                stderr: b"probe failed".to_vec(),
            }),
        };

        let error = run_source_probe_with(&runner, Path::new("C:\\repo"), "C:\\iso\\win.iso")
            .expect_err("source probe should fail");

        assert_eq!(error, "probe failed");
    }

    #[test]
    fn profile_generation_should_call_bridge_script_with_intent_and_profile_paths() {
        let runner = CapturingRunner::new(ok_output(""));
        let repo = Path::new("C:\\repo");

        let profile_path =
            generate_build_profile_with(&runner, repo).expect("profile generation should pass");

        let spec = runner.first_spec();
        assert!(spec
            .args
            .iter()
            .any(|arg| arg.ends_with("New-UiBuildProfile.ps1")));
        assert!(spec.args.iter().any(|arg| arg == "-RepositoryRoot"));
        assert!(spec
            .args
            .iter()
            .any(|arg| arg.ends_with("output\\gui\\ui-intent.json")));
        assert_eq!(profile_path, build_profile_path(repo));
    }

    #[test]
    fn build_invocation_should_call_bridge_script_with_profile_and_dry_run() {
        let runner = CapturingRunner::new(ok_output(
            r#"{"Ok":true,"DryRun":true,"OutputPath":"C:\\repo\\output","OutputIsoPath":"","ManifestPath":"C:\\repo\\output\\WinMint-BuildManifest.json","BuildDeltaPath":"C:\\repo\\output\\WinMint-BuildDelta.json","ReportPath":"C:\\repo\\output\\BuildReport.json","Progress":[],"Error":""}"#,
        ));
        let repo = Path::new("C:\\repo");
        let profile = repo.join("output").join("gui").join("BuildProfile.json");

        let result = start_build_from_profile_with(&runner, repo, &profile, true)
            .expect("build invocation should pass");

        let spec = runner.first_spec();
        assert!(spec
            .args
            .iter()
            .any(|arg| arg.ends_with("Start-UiBuildFromProfile.ps1")));
        assert!(spec.args.iter().any(|arg| arg == "-ProfilePath"));
        assert!(spec.args.iter().any(|arg| arg == "-DryRun"));
        assert!(result.ok);
        assert_eq!(
            result.manifest_path,
            "C:\\repo\\output\\WinMint-BuildManifest.json"
        );
        assert_eq!(
            result.build_delta_path,
            "C:\\repo\\output\\WinMint-BuildDelta.json"
        );
        assert_eq!(result.build_delta.total_records, 0);
    }

    #[test]
    fn build_invocation_should_parse_structured_failure_result() {
        let runner = CapturingRunner::new(BridgeCommandOutput {
            success: false,
            status: "exit status: 1".to_string(),
            stdout: br#"{"Ok":false,"DryRun":true,"OutputPath":"","OutputIsoPath":"","ManifestPath":"C:\\repo\\output\\WinMint-BuildManifest.json","BuildDeltaPath":"C:\\repo\\output\\WinMint-BuildDelta.json","ReportPath":"","Progress":[{"Time":"","Stage":"Validate","Level":"Error","Message":"failed"}],"Error":"failed"}"#.to_vec(),
            stderr: b"failed".to_vec(),
        });
        let repo = Path::new("C:\\repo");
        let profile = repo.join("output").join("gui").join("BuildProfile.json");

        let result = start_build_from_profile_with(&runner, repo, &profile, true)
            .expect("structured failure result should parse");

        assert!(!result.ok);
        assert_eq!(result.error, "failed");
        assert_eq!(
            result.build_delta_path,
            "C:\\repo\\output\\WinMint-BuildDelta.json"
        );
        assert_eq!(result.progress[0].message, "failed");
    }

    #[test]
    fn build_delta_summary_should_parse_local_delta_artifact() {
        let temp_dir =
            std::env::temp_dir().join(format!("winmint-build-delta-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&temp_dir);
        fs::create_dir_all(&temp_dir).expect("temp dir should exist");
        let delta_path = temp_dir.join("WinMint-BuildDelta.json");
        fs::write(
            &delta_path,
            r#"{"schemaVersion":1,"generatedAt":"2026-06-16T00:00:00Z","records":[{"title":"Apply AI cleanup policy","phase":"offline-image","kind":"ai-cleanup","userControlled":false,"changes":["a","b"]},{"title":"Install selected editors","phase":"first-logon","kind":"first-logon-module","userControlled":true,"changes":["a"]}]}"#,
        )
        .expect("delta artifact should write");

        let summary = load_build_delta_summary(&delta_path.display().to_string());

        assert_eq!(summary.total_records, 2);
        assert_eq!(summary.user_controlled_records, 1);
        assert_eq!(
            summary.phase_counts,
            vec![
                ("first-logon".to_string(), 1),
                ("offline-image".to_string(), 1)
            ]
        );
        assert_eq!(summary.highlighted_records[0].change_count, 2);
        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn write_ui_intent_should_persist_bridge_contract_json_under_repo_output() {
        let temp_root =
            std::env::temp_dir().join(format!("winmint-gui-bridge-test-{}", std::process::id()));
        let _ = fs::remove_dir_all(&temp_root);

        let output_path = write_ui_intent(
            &temp_root,
            UiIntentInput {
                source_iso: "C:\\iso\\win.iso",
                architecture: "ARM64",
                computer_name: "WinMint",
                account_name: "dev",
                keep: KeepFlags::default(),
                edition: "Host",
                toolkit: ToolkitIntent::default(),
                desktop_layers: DesktopLayersIntent::default(),
                form_factor: "Auto",
            },
        )
        .expect("intent should write");

        let json = fs::read_to_string(&output_path).expect("intent json should exist");
        let value: serde_json::Value = serde_json::from_str(&json).expect("intent should be json");
        assert_eq!(value["ISOPath"], "C:\\iso\\win.iso");
        assert_eq!(value["Architecture"], "arm64");

        let _ = fs::remove_dir_all(&temp_root);
    }
}
