use super::*;
use crate::notebook::open;

#[test]
fn round_trip_preserves_metadata_and_unchanged_output() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("a.ipynb");
    fs::write(
        &path,
        serde_json::to_vec(&json!({
            "cells": [{"cell_type":"code","id":"abc","metadata":{"tag":"keep"},
                "source":["print(42)"], "execution_count":3,
                "outputs":[{"output_type":"stream","name":"stdout","text":"42\n"}]}],
            "metadata":{"custom":"keep"},"nbformat":4,"nbformat_minor":5
        }))
        .unwrap(),
    )
    .unwrap();
    let lines = open(&path).unwrap();
    save(&path, &lines).unwrap();
    let after = read(&path).unwrap();
    assert_eq!(after["metadata"]["custom"], "keep");
    assert_eq!(after["cells"][0]["outputs"][0]["text"], "42\n");
    let mut edited = lines;
    edited[1] = "print(43)".to_owned();
    save(&path, &edited).unwrap();
    assert_eq!(read(&path).unwrap()["cells"][0]["outputs"], json!([]));
}

#[test]
fn old_notebook_without_ids_keeps_markdown_and_code_outputs() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("old.ipynb");
    fs::write(&path, serde_json::to_vec(&json!({
        "cells": [
            {"cell_type":"markdown","metadata":{"keep":true},"source":["# Heading\n", "text"]},
            {"cell_type":"code","metadata":{},"source":"2 + 2", "execution_count":1,
             "outputs":[{"output_type":"execute_result","data":{"text/plain":"4"},"metadata":{},"execution_count":1}]}
        ],
        "metadata":{},"nbformat":4,"nbformat_minor":4
    })).unwrap()).unwrap();
    let lines = open(&path).unwrap();
    assert_eq!(lines[1], "# # Heading");
    save(&path, &lines).unwrap();
    let saved = read(&path).unwrap();
    assert_eq!(saved["cells"][0]["metadata"]["keep"], true);
    assert_eq!(saved["cells"][1]["outputs"][0]["data"]["text/plain"], "4");
}

#[test]
fn adding_a_blank_line_clears_stale_output() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("blank.ipynb");
    for source in ["raise ValueError('old')", "raise ValueError('old')\n"] {
        fs::write(
            &path,
            serde_json::to_vec(&json!({
                "cells":[{"cell_type":"code","id":"cell-1","metadata":{},
                    "source":source,"execution_count":1,
                    "outputs":[{"output_type":"error","ename":"ValueError",
                        "evalue":"old","traceback":["ValueError: old"]}]}],
                "metadata":{},"nbformat":4,"nbformat_minor":5
            }))
            .unwrap(),
        )
        .unwrap();
        let mut lines = open(&path).unwrap();
        lines.push(String::new());
        save(&path, &lines).unwrap();
        assert_eq!(read(&path).unwrap()["cells"][0]["outputs"], json!([]));
    }
}
