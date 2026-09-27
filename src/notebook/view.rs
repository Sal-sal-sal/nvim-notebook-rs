use std::path::Path;

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::store;

pub struct OpenView {
    pub lines: Vec<String>,
    pub errors: Vec<Value>,
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
    let notebook = store::read(path)?;
    let mut lines = Vec::new();
    let mut errors = Vec::new();
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
            let failed = cell["outputs"]
                .as_array()
                .into_iter()
                .flatten()
                .filter(|output| output["output_type"] == "error")
                .cloned()
                .collect::<Vec<_>>();
            if !failed.is_empty() {
                errors.push(json!({"id":id,"source":source,"outputs":failed}));
            }
        }
    }
    if lines.is_empty() {
        lines.push("# %% [code] id=cell-1".to_owned());
    }
    Ok(OpenView { lines, errors })
}

pub fn open(path: &Path) -> Result<Vec<String>> {
    Ok(open_view(path)?.lines)
}
