use serde_json::{json, Value};
use std::{
    io::Write,
    path::Path,
    process::{Command, Stdio},
};

fn worker(path: &Path, cli: &str, requests: &[Value]) -> Vec<Value> {
    let mut child = Command::new(env!("CARGO_BIN_EXE_nvim-notebook-rs"))
        .arg("worker")
        .env("NVIM_NOTEBOOK_COLAB", cli)
        .env("NVIM_NOTEBOOK_COLAB_JOURNAL", path)
        .env_remove("NVIM_NOTEBOOK_COLAB_CA_BUNDLE")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut input = child.stdin.take().unwrap();
    for request in requests {
        writeln!(input, "{request}").unwrap();
    }
    drop(input);
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    String::from_utf8(output.stdout)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect()
}

#[test]
fn persists_request_return_pairs_across_workers_and_ignores_local_operations() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("journal.json");
    let cli = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fake_colab.py");
    let requests = [
        json!({"id":1,"op":"colab_connect","session":"journal"}),
        json!({"id":2,"op":"run","backend":"colab","all":false,"line":2,
            "lines":["# %% [code] id=cell-1","raise ValueError('bad cell')"]}),
        json!({"id":3,"op":"colab_connect","session":"bad name"}),
        json!({"id":4,"op":"restart_local","path":"unused"}),
    ];
    let responses = worker(&path, cli, &requests);
    assert_eq!(responses[0]["data"]["success"], true);
    assert_eq!(responses[1]["ok"], true);
    assert_eq!(responses[1]["data"]["success"], false);
    assert_eq!(responses[2]["ok"], false);
    let snapshot = worker(&path, cli, &[json!({"id":5,"op":"colab_journal"})]);
    let entries = snapshot[0]["data"]["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 3);
    for (index, entry) in entries.iter().enumerate() {
        assert_eq!(entry["request"], requests[index]);
        assert_eq!(entry["response"], responses[index]);
        assert!(entry["duration_ms"].is_u64());
        assert!(entry["started_at_ms"].as_u64().unwrap() > 0);
    }
    assert_eq!(snapshot[0]["data"]["limit"], 100);
}

#[test]
fn retains_only_the_latest_hundred_requests_including_spawn_failures() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("journal.json");
    let mut requests: Vec<_> = (1..=105)
        .map(|id| json!({"id":id,"op":"colab_sessions"}))
        .collect();
    requests.push(json!({"id":106,"op":"colab_journal"}));
    let responses = worker(&path, "/missing/notebook-test-colab", &requests);
    assert_eq!(responses[0]["ok"], false);
    let entries = responses[105]["data"]["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 100);
    assert_eq!(entries[0]["request"]["id"], 6);
    assert_eq!(entries[99]["request"]["id"], 105);
    assert!(entries[99]["response"]["error"]
        .as_str()
        .unwrap()
        .contains("starting Colab CLI"));
}

#[test]
fn journal_io_failure_is_reported_without_failing_the_colab_action() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("journal.json");
    std::fs::write(&path, "damaged journal").unwrap();
    let cli = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fake_colab.py");
    let responses = worker(&path, cli, &[json!({"id":1,"op":"colab_sessions"})]);
    assert_eq!(responses[0]["ok"], true);
    assert_eq!(responses[0]["data"]["success"], true);
    assert!(responses[0]["journal_error"]
        .as_str()
        .unwrap()
        .contains("reading Colab journal JSON"));
    assert_eq!(std::fs::read_to_string(path).unwrap(), "damaged journal");
}
