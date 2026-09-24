use std::{
    fs,
    io::Write,
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
};

use serde_json::{json, Value};

#[test]
fn failed_cli_login_explains_next_step_and_does_not_select_session() {
    let dir = tempfile::tempdir().unwrap();
    let fake = dir.path().join("colab");
    fs::write(
        &fake,
        "#!/bin/sh\nprintf 'Enter the authorization code to authorize colab-cli\\n' >&2\nexit 1\n",
    )
    .unwrap();
    let mut permissions = fs::metadata(&fake).unwrap().permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&fake, permissions).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_nvim-notebook-rs"))
        .arg("worker")
        .env("NVIM_NOTEBOOK_COLAB", &fake)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    writeln!(
        input,
        "{}",
        json!({"id":1,"op":"colab_new","session":"test","gpu":null})
    )
    .unwrap();
    writeln!(input, "{}", json!({"id":2,"op":"run","backend":"colab","lines":["# %% [code] id=a","1 + 1"],"line":2,"all":false})).unwrap();
    drop(input);
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    let replies = output
        .stdout
        .split(|byte| *byte == b'\n')
        .filter(|line| !line.is_empty())
        .map(|line| serde_json::from_slice::<Value>(line).unwrap())
        .collect::<Vec<_>>();
    assert_eq!(replies[0]["data"]["success"], false);
    assert!(replies[0]["data"]["output"]
        .as_str()
        .unwrap()
        .contains(":NotebookColabLogin"));
    assert_eq!(replies[1]["ok"], false);
    assert!(replies[1]["error"]
        .as_str()
        .unwrap()
        .contains("NotebookColabNew"));
}
