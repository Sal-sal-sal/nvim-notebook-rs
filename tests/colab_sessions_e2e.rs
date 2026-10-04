use serde_json::{json, Value};
use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
};

fn list(output: &str) -> Value {
    let dir = tempfile::tempdir().unwrap();
    let cli = dir.path().join("colab");
    fs::write(
        &cli,
        "#!/usr/bin/env python3\nimport os\nprint(os.environ['SESSION_LIST'])\n",
    )
    .unwrap();
    let mut permissions = fs::metadata(&cli).unwrap().permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&cli, permissions).unwrap();
    let mut worker = Command::new(env!("CARGO_BIN_EXE_nvim-notebook-rs"))
        .arg("worker")
        .env("NVIM_NOTEBOOK_COLAB", cli)
        .env("SESSION_LIST", output)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = worker.stdin.take().unwrap();
    writeln!(input, "{}", json!({"id":1,"op":"colab_sessions"})).unwrap();
    drop(input);
    let result = worker.wait_with_output().unwrap();
    assert!(result.status.success());
    serde_json::from_slice(&result.stdout).unwrap()
}

#[test]
fn exposes_named_sessions_without_ansi_duplicates_or_invalid_names() {
    let result = list("\u{1b}[32m[training] | Hardware: T4\u{1b}[0m\n[training] | Hardware: T4\n[other-1] | Hardware: CPU\n[bad name] | Hardware: CPU\n[?] | Hardware: CPU");
    assert_eq!(result["ok"], true);
    assert_eq!(result["data"]["success"], true);
    assert_eq!(result["data"]["sessions"], json!(["training", "other-1"]));
    assert_eq!(result["data"]["unmanaged"], true);
}

#[test]
fn empty_session_list_is_distinct_from_an_unmanaged_assignment() {
    let result = list("No active sessions");
    assert_eq!(result["data"]["sessions"], json!([]));
    assert_eq!(result["data"]["unmanaged"], false);
}
