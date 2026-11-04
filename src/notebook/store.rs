use std::{collections::HashMap, fs, path::Path};

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};

use super::{
    ids,
    percent::{parse, Cell},
    results::{self, CellResult},
    template,
};

pub(super) fn source(cell: &Value) -> Result<String> {
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

pub(super) fn read(path: &Path) -> Result<Value> {
    let text = fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
    if text.is_empty() {
        return Ok(template::blank());
    }
    let notebook: Value = serde_json::from_str(&text).context("invalid notebook JSON")?;
    if notebook.get("nbformat").and_then(Value::as_u64) != Some(4)
        || !notebook.get("cells").is_some_and(Value::is_array)
    {
        bail!("expected a Jupyter notebook in nbformat 4");
    }
    Ok(notebook)
}

fn as_json_cell(cell: &Cell, old: Option<&Value>) -> Result<Value> {
    let mut result = old.cloned().unwrap_or_else(|| json!({"metadata": {}}));
    let previous_source = old.map(source).transpose()?;
    let unchanged = previous_source.as_ref().is_some_and(|previous| {
        previous == &cell.source
            || (!previous.ends_with('\n')
                && cell.source.strip_suffix('\n') == Some(previous.as_str()))
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
    save_with_results(path, lines, &[])
}

pub fn save_with_results(path: &Path, lines: &[String], results: &[CellResult]) -> Result<usize> {
    let parsed = parse(lines)?;
    let target;
    let path = if path.is_symlink() {
        target = fs::canonicalize(path).with_context(|| format!("resolving {}", path.display()))?;
        target.as_path()
    } else {
        path
    };
    let mut notebook = if path.exists() {
        read(path)?
    } else {
        template::blank()
    };
    let previous = notebook["cells"].as_array().unwrap();
    let previous_by_id: HashMap<_, _> =
        ids::for_cells(previous).into_iter().zip(previous).collect();
    let cells = parsed
        .iter()
        .map(|cell| {
            let mut saved = as_json_cell(cell, previous_by_id.get(&cell.id).copied())?;
            results::apply(cell, &mut saved, results);
            Ok(saved)
        })
        .collect::<Result<Vec<_>>>()?;
    notebook["cells"] = json!(cells);
    if notebook["nbformat_minor"]
        .as_u64()
        .is_some_and(|minor| minor < 5)
    {
        notebook["nbformat_minor"] = json!(5);
    }
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
    if path.exists() && fs::metadata(path)?.len() != 0 {
        bail!("notebook already exists: {}", path.display());
    }
    let lines = vec!["# %% [code] id=cell-1".to_owned()];
    save(path, &lines)?;
    Ok(())
}

#[cfg(test)]
mod tests;
