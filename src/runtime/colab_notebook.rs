use std::{
    fs,
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
};

use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};

use super::Execution;
use crate::notebook::Cell;

static NEXT_ARTIFACT: AtomicU64 = AtomicU64::new(1);

pub fn write_input(path: &Path, cell: &Cell) -> Result<()> {
    let notebook = json!({
        "cells": [{"cell_type":"code","id":cell.id,"metadata":{},"source":cell.source,
                   "outputs":[],"execution_count":null}],
        "metadata":{"kernelspec":{"display_name":"Python 3","language":"python","name":"python3"}},
        "nbformat":4,"nbformat_minor":5
    });
    fs::write(path, serde_json::to_vec(&notebook)?)?;
    Ok(())
}

fn text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Array(parts) => parts.iter().filter_map(Value::as_str).collect(),
        _ => String::new(),
    }
}

fn artifact(extension: &str, bytes: &[u8]) -> Result<String> {
    let dir = std::env::temp_dir().join("nvim-notebook-rs-output");
    fs::create_dir_all(&dir)?;
    let number = NEXT_ARTIFACT.fetch_add(1, Ordering::Relaxed);
    let path = dir.join(format!("{}-{number}.{extension}", std::process::id()));
    fs::write(&path, bytes)?;
    Ok(path.to_string_lossy().into_owned())
}

pub(super) fn render(outputs: &[Value]) -> Result<(String, Vec<String>, bool)> {
    let mut display = String::new();
    let mut artifacts = Vec::new();
    let mut failed = false;
    for output in outputs {
        match output["output_type"].as_str().unwrap_or("") {
            "stream" => display.push_str(&text(&output["text"])),
            "error" => {
                failed = true;
                let trace = text(&output["traceback"]);
                if trace.is_empty() {
                    display.push_str(&format!(
                        "{}: {}\n",
                        output["ename"].as_str().unwrap_or("Error"),
                        output["evalue"].as_str().unwrap_or("")
                    ));
                } else {
                    display.push_str(&trace);
                }
            }
            "display_data" | "execute_result" => {
                let plain = text(&output["data"]["text/plain"]);
                if !plain.is_empty() {
                    display.push_str(&plain);
                    display.push('\n');
                }
                for (mime, extension) in [("image/png", "png"), ("image/jpeg", "jpg")] {
                    if let Some(encoded) = output["data"][mime].as_str() {
                        let path = artifact(extension, &STANDARD.decode(encoded)?)?;
                        display.push_str(&format!("![Image output]({path})\n"));
                        artifacts.push(path);
                    }
                }
                let html = text(&output["data"]["text/html"]);
                if !html.is_empty() {
                    let path = artifact("html", html.as_bytes())?;
                    display.push_str(&format!("[HTML output]({path})\n"));
                    artifacts.push(path);
                }
            }
            _ => {}
        }
    }
    Ok((display, artifacts, failed))
}

pub fn read_output(input: &Path, mut cli: Execution) -> Result<Execution> {
    let output_path = input.with_file_name("request_output.ipynb");
    if !output_path.exists() {
        if cli.success {
            cli.success = false;
            cli.output
                .push_str("\nColab CLI did not create its output notebook.\n");
        }
        return Ok(cli);
    }
    let notebook: Value = serde_json::from_slice(&fs::read(&output_path)?)
        .with_context(|| format!("invalid Colab output notebook: {}", output_path.display()))?;
    let cell = notebook["cells"]
        .as_array()
        .and_then(|cells| cells.first())
        .context("Colab output notebook has no cell")?;
    let outputs = cell["outputs"]
        .as_array()
        .cloned()
        .context("Colab output cell has no outputs")?;
    let (display, artifacts, failed) = render(&outputs)?;
    cli.success &= !failed;
    cli.output = if cli.success || !display.is_empty() {
        display
    } else {
        cli.output
    };
    cli.outputs = outputs;
    cli.execution_count = cell["execution_count"].clone();
    cli.artifacts = artifacts;
    Ok(cli)
}
