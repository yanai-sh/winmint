use std::env;
use std::fs;
use std::path::PathBuf;
use std::process;

use winmint_core::profile::GuiIntentInput;

fn print_usage() {
    eprintln!(
        "Usage:\n  winmintctl normalize-gui-intent --input <path> [--output <path>]\n\nWhen --output is omitted, normalized JSON is written to stdout."
    );
}

fn value_after(args: &[String], flag: &str) -> Option<PathBuf> {
    args.windows(2)
        .find(|window| window[0] == flag)
        .map(|window| PathBuf::from(&window[1]))
}

fn run(args: &[String]) -> Result<(), String> {
    if args.len() < 2 || args[1] != "normalize-gui-intent" {
        print_usage();
        return Err("unsupported command".to_string());
    }

    let input_path = value_after(args, "--input").ok_or_else(|| "missing --input".to_string())?;
    let output_path = value_after(args, "--output");

    let raw = fs::read_to_string(&input_path)
        .map_err(|error| format!("could not read {}: {error}", input_path.display()))?;
    let input: GuiIntentInput =
        serde_json::from_str(&raw).map_err(|error| format!("invalid GUI intent JSON: {error}"))?;
    let normalized = input.normalized_value()?;
    let json = serde_json::to_string_pretty(&normalized)
        .map_err(|error| format!("could not serialize normalized intent: {error}"))?;

    if let Some(path) = output_path {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .map_err(|error| format!("could not create {}: {error}", parent.display()))?;
        }
        fs::write(&path, format!("{json}\n"))
            .map_err(|error| format!("could not write {}: {error}", path.display()))?;
    } else {
        println!("{json}");
    }

    Ok(())
}

fn main() {
    let args = env::args().collect::<Vec<_>>();
    if let Err(error) = run(&args) {
        eprintln!("winmintctl: {error}");
        process::exit(1);
    }
}
