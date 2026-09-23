use std::{fs, path::Path};

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::percent::{parse, Cell};

fn source(cell: &Value) -> Result<String> {
    match cell.get("source") {
        Some(Value::String(text)) => Ok(text.clone()),
        Some(Value::Array(lines)) => lines
            .iter()
            .map(|line| {
                line.as_str()
                    .map(str::to_owned)
                    .context("non-string source line")
            })
            .collect::<Result<Vec<_>>>()
            .map(|lines| lines.join("")),
        _ => bail!("cell source must be text or an array of text"),
    }
}

fn read(path: &Path) -> Result<Value> {
    let text = fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
    let notebook: Value = serde_json::from_str(&text).context("invalid notebook JSON")?;
    if notebook.get("nbformat").and_then(Value::as_u64) != Some(4)
        || !notebook.get("cells").is_some_and(Value::is_array)
    {
        bail!("expected a Jupyter notebook in nbformat 4");
    }
    Ok(notebook)
}

fn shown_lines(kind: &str, source: &str) -> Vec<String> {
    source
        .split_terminator('\n')
        .map(|line| match kind {
            "code" => line.to_owned(),
            _ if line.is_empty() => "#".to_owned(),
            _ => format!("# {line}"),
        })
        .collect()
}

pub fn open(path: &Path) -> Result<Vec<String>> {
    let notebook = read(path)?;
    let mut lines = Vec::new();
    for (index, cell) in notebook["cells"].as_array().unwrap().iter().enumerate() {
        let kind = cell["cell_type"].as_str().context("missing cell_type")?;
        if !matches!(kind, "code" | "markdown" | "raw") {
            bail!("unsupported cell type: {kind}");
        }
        let id = cell["id"]
            .as_str()
            .map(str::to_owned)
            .unwrap_or_else(|| format!("cell-{}", index + 1));
        lines.push(format!("# %% [{kind}] id={id}"));
        lines.extend(shown_lines(kind, &source(cell)?));
    }
    if lines.is_empty() {
        lines.push("# %% [code] id=cell-1".to_owned());
    }
    Ok(lines)
}

fn old_cell<'a>(old: &'a Value, id: &str, index: usize) -> Option<&'a Value> {
    let cells = old["cells"].as_array()?;
    cells
        .iter()
        .find(|cell| cell["id"].as_str() == Some(id))
        .or_else(|| cells.get(index).filter(|cell| cell.get("id").is_none()))
}

fn as_json_cell(cell: &Cell, old: Option<&Value>) -> Result<Value> {
    let mut result = old.cloned().unwrap_or_else(|| json!({"metadata": {}}));
    let previous_source = old.map(source).transpose()?;
    let unchanged = previous_source.as_ref().is_some_and(|previous| {
        previous == &cell.source || previous == cell.source.trim_end_matches('\n')
    });
    result["cell_type"] = json!(cell.kind);
    result["id"] = json!(cell.id);
    if !unchanged {
        result["source"] = json!(cell.source);
    }
    if cell.kind == "code" {
        if old.is_none() || !unchanged {
            result["outputs"] = json!([]);
            result["execution_count"] = Value::Null;
        }
    } else {
        result.as_object_mut().unwrap().remove("outputs");
        result.as_object_mut().unwrap().remove("execution_count");
    }
    Ok(result)
}

pub fn save(path: &Path, lines: &[String]) -> Result<usize> {
    let parsed = parse(lines)?;
    let mut notebook = if path.exists() {
        read(path)?
    } else {
        json!({"cells": [], "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"}}, "nbformat": 4, "nbformat_minor": 5})
    };
    let cells = parsed
        .iter()
        .enumerate()
        .map(|(index, cell)| as_json_cell(cell, old_cell(&notebook, &cell.id, index)))
        .collect::<Result<Vec<_>>>()?;
    notebook["cells"] = json!(cells);
    let bytes = serde_json::to_vec_pretty(&notebook)?;
    let parent = path.parent().context("notebook path has no parent")?;
    let temp = parent.join(format!(
        ".{}.{}.tmp",
        path.file_name().unwrap().to_string_lossy(),
        std::process::id()
    ));
    fs::write(&temp, bytes).with_context(|| format!("writing {}", temp.display()))?;
    if let Ok(metadata) = fs::metadata(path) {
        fs::set_permissions(&temp, metadata.permissions())?;
    }
    if let Err(error) = fs::rename(&temp, path) {
        let _ = fs::remove_file(&temp);
        return Err(error).with_context(|| format!("saving {}", path.display()));
    }
    Ok(parsed.len())
}

pub fn create(path: &Path) -> Result<()> {
    if path.exists() {
        bail!("notebook already exists: {}", path.display());
    }
    let lines = vec!["# %% [code] id=cell-1".to_owned()];
    save(path, &lines)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

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
}
