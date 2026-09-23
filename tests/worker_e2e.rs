use std::{
    fs,
    io::{BufRead, BufReader, Write},
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
};

use serde_json::{json, Value};

fn request(input: &mut impl Write, output: &mut impl BufRead, value: Value) -> Value {
    writeln!(input, "{value}").unwrap();
    input.flush().unwrap();
    let mut line = String::new();
    output.read_line(&mut line).unwrap();
    assert!(!line.is_empty(), "worker closed without a response");
    serde_json::from_str(&line).unwrap()
}

#[test]
fn creates_edits_runs_and_uses_colab_cli() {
    let dir = tempfile::tempdir().unwrap();
    let notebook = dir.path().join("model.ipynb");
    let fake_cli = dir.path().join("colab");
    fs::write(&fake_cli, "#!/bin/sh\ncase \"$1\" in\n  exec) code=$(cat); printf 'remote:%s\\n' \"$code\" ;;\n  status|new|stop|sessions) printf '%s:%s\\n' \"$1\" \"$3\" ;;\n  *) exit 2 ;;\nesac\n").unwrap();
    let mut permissions = fs::metadata(&fake_cli).unwrap().permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&fake_cli, permissions).unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_nvim-notebook-rs"))
        .arg("worker")
        .env("NVIM_NOTEBOOK_COLAB", &fake_cli)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    let mut output = BufReader::new(child.stdout.take().unwrap());
    let path = notebook.to_string_lossy();
    assert!(request(
        &mut input,
        &mut output,
        json!({"id":1,"op":"new","path":path})
    )["ok"]
        .as_bool()
        .unwrap());
    let lines = vec![
        "# %% [code] id=one",
        "x = 40",
        "# %% [code] id=two",
        "x + 2",
    ];
    assert!(request(
        &mut input,
        &mut output,
        json!({"id":2,"op":"save","path":path,"lines":lines})
    )["ok"]
        .as_bool()
        .unwrap());
    let opened = request(
        &mut input,
        &mut output,
        json!({"id":3,"op":"open","path":path}),
    );
    assert_eq!(opened["data"]["lines"], json!(lines));
    let first = request(
        &mut input,
        &mut output,
        json!({"id":4,"op":"run","lines":lines,"line":2,"all":false,"backend":"local"}),
    );
    assert!(first["data"]["success"].as_bool().unwrap());
    let second = request(
        &mut input,
        &mut output,
        json!({"id":5,"op":"run","lines":lines,"line":4,"all":false,"backend":"local"}),
    );
    assert_eq!(second["data"]["output"].as_str().unwrap().trim(), "42");
    let connected = request(
        &mut input,
        &mut output,
        json!({"id":6,"op":"colab_connect","session":"training"}),
    );
    assert_eq!(connected["data"]["session"], "training");
    let remote = request(
        &mut input,
        &mut output,
        json!({"id":7,"op":"run","lines":lines,"line":4,"all":false,"backend":"colab"}),
    );
    assert!(remote["data"]["output"]
        .as_str()
        .unwrap()
        .contains("remote:x + 2"));
    let stopped = request(&mut input, &mut output, json!({"id":8,"op":"colab_stop"}));
    assert!(stopped["data"]["session"].is_null());
    drop(input);
    assert!(child.wait().unwrap().success());
}
