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
    fs::write(&fake_cli, include_str!("fake_colab.py")).unwrap();
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
    let restarted_local = request(
        &mut input,
        &mut output,
        json!({"id":16,"op":"restart_local","path":"<default>"}),
    );
    assert_eq!(restarted_local["data"]["restarted"], true);
    let missing_state = request(
        &mut input,
        &mut output,
        json!({"id":17,"op":"run","lines":lines,"line":4,"all":false,"backend":"local"}),
    );
    assert_eq!(missing_state["data"]["success"], false);
    assert!(missing_state["data"]["output"]
        .as_str()
        .unwrap()
        .contains("NameError"));
    let connected = request(
        &mut input,
        &mut output,
        json!({"id":6,"op":"colab_connect","session":"training"}),
    );
    assert_eq!(connected["data"]["session"], "training");
    let install = request(
        &mut input,
        &mut output,
        json!({"id":12,"op":"colab_install","packages":["torch","numpy"]}),
    );
    assert!(install["data"]["output"]
        .as_str()
        .unwrap()
        .contains("install --session training torch numpy"));
    let source_file = dir.path().join("data.csv");
    fs::write(&source_file, "x\n1\n").unwrap();
    let uploaded = request(
        &mut input,
        &mut output,
        json!({"id":13,"op":"colab_upload","local":source_file,"remote":"/content/data.csv"}),
    );
    assert!(uploaded["data"]["success"].as_bool().unwrap());
    let downloaded = dir.path().join("copy.csv");
    let transfer = request(
        &mut input,
        &mut output,
        json!({"id":14,"op":"colab_download","remote":"/content/data.csv","local":downloaded}),
    );
    assert!(transfer["data"]["success"].as_bool().unwrap());
    assert!(fs::read_to_string(&downloaded)
        .unwrap()
        .contains("/content/data.csv"));
    let restarted = request(
        &mut input,
        &mut output,
        json!({"id":15,"op":"colab_restart"}),
    );
    assert!(restarted["data"]["success"].as_bool().unwrap());
    let remote = request(
        &mut input,
        &mut output,
        json!({"id":7,"op":"run","lines":lines,"line":4,"all":false,"backend":"colab"}),
    );
    assert!(remote["data"]["output"]
        .as_str()
        .unwrap()
        .contains("remote:x + 2"));
    let results = remote["data"]["results"].as_array().unwrap();
    assert_eq!(results[0]["id"], "two");
    let saved = request(
        &mut input,
        &mut output,
        json!({"id":8,"op":"save","path":path,"lines":lines,"results":results}),
    );
    assert!(saved["ok"].as_bool().unwrap());
    let on_disk: Value = serde_json::from_slice(&fs::read(&notebook).unwrap()).unwrap();
    assert_eq!(on_disk["cells"][1]["outputs"][0]["text"], "remote:x + 2\n");
    let error_lines = vec!["# %% [code] id=bad", "raise ValueError('bad cell')"];
    let failed = request(
        &mut input,
        &mut output,
        json!({"id":9,"op":"run","lines":error_lines,"line":2,"all":false,"backend":"colab"}),
    );
    assert_eq!(failed["data"]["success"], false);
    assert!(failed["data"]["output"]
        .as_str()
        .unwrap()
        .contains("ValueError: bad cell"));
    let plot_lines = vec!["# %% [code] id=plot", "plot()"];
    let plot = request(
        &mut input,
        &mut output,
        json!({"id":10,"op":"run","lines":plot_lines,"line":2,"all":false,"backend":"colab"}),
    );
    let image_path = plot["data"]["artifacts"][0].as_str().unwrap();
    assert!(fs::metadata(image_path).unwrap().len() > 20);
    fs::remove_file(image_path).unwrap();
    let stopped = request(&mut input, &mut output, json!({"id":11,"op":"colab_stop"}));
    assert!(stopped["data"]["session"].is_null());
    let tpu = request(
        &mut input,
        &mut output,
        json!({"id":18,"op":"colab_new","session":"tpu_test","gpu":"TPU:v6e1"}),
    );
    assert!(tpu["data"]["output"]
        .as_str()
        .unwrap()
        .contains("--tpu v6e1"));
    let stopped_tpu = request(&mut input, &mut output, json!({"id":19,"op":"colab_stop"}));
    assert!(stopped_tpu["data"]["success"].as_bool().unwrap());
    drop(input);
    assert!(child.wait().unwrap().success());
}
