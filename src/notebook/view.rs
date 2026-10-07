use std::path::Path;

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::store;

pub struct OpenView {
    pub lines: Vec<String>,
    pub results: Vec<Value>,
}

fn display_output(output: &Value) -> Value {
    let mut shown = output.clone();
    if let Some(data) = shown.get_mut("data").and_then(Value::as_object_mut) {
        for format in ["image/png", "text/html"] {
            if data.contains_key(format) {
                data.insert(format.to_owned(), Value::Bool(true));
            }
        }
    }
    shown
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

pub fn open_view(path: &Path) -> Result<OpenView> {
    if std::fs::metadata(path)?.len() == 0 {
        store::create(path)?;
    }
    let notebook = store::read(path)?;
    let mut lines = Vec::new();
    let mut results = Vec::new();
    for (index, cell) in notebook["cells"].as_array().unwrap().iter().enumerate() {
        let kind = cell["cell_type"].as_str().context("missing cell_type")?;
        if !matches!(kind, "code" | "markdown" | "raw") {
            bail!("unsupported cell type: {kind}");
        }
        let id = cell["id"]
            .as_str()
            .map(str::to_owned)
            .unwrap_or_else(|| format!("cell-{}", index + 1));
        let source = store::source(cell)?;
        lines.push(format!("# %% [{kind}] id={id}"));
        lines.extend(shown_lines(kind, &source));
        if kind == "code" {
            let outputs = cell["outputs"]
                .as_array()
                .into_iter()
                .flatten()
                .map(display_output)
                .collect::<Vec<_>>();
            if !outputs.is_empty() {
                results.push(json!({"id":id,"source":source,"outputs":outputs}));
            }
        }
    }
    if lines.is_empty() {
        lines.push("# %% [code] id=cell-1".to_owned());
    }
    Ok(OpenView { lines, results })
}

pub fn open(path: &Path) -> Result<Vec<String>> {
    Ok(open_view(path)?.lines)
}
