mod store;
#[cfg(test)]
mod tests;

use std::{path::PathBuf, time::Instant};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub const LIMIT: usize = 100;

#[derive(Deserialize, Serialize)]
pub struct Entry {
    id: u64,
    started_at_ms: u64,
    worker_pid: u32,
    duration_ms: Option<u64>,
    request: Value,
    response: Option<Value>,
}

pub struct Pending {
    path: PathBuf,
    id: u64,
    started: Instant,
}

fn path() -> Option<PathBuf> {
    std::env::var_os("NVIM_NOTEBOOK_COLAB_JOURNAL")
        .filter(|path| !path.is_empty())
        .map(PathBuf::from)
}

pub fn begin(request: &Value) -> Result<Option<Pending>> {
    let op = request["op"].as_str().unwrap_or_default();
    let tracked = (op.starts_with("colab_") && op != "colab_journal")
        || (op == "run" && request["backend"] == "colab");
    let Some(path) = path().filter(|_| tracked) else {
        return Ok(None);
    };
    let started = Instant::now();
    let started_at_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)?
        .as_millis() as u64;
    let id = store::insert(
        &path,
        Entry {
            id: 0,
            started_at_ms,
            worker_pid: std::process::id(),
            duration_ms: None,
            request: request.clone(),
            response: None,
        },
    )?;
    Ok(Some(Pending { path, id, started }))
}

impl Pending {
    pub fn finish(self, response: &Value) -> Result<()> {
        store::complete(
            &self.path,
            self.id,
            self.started.elapsed().as_millis() as u64,
            response,
        )
    }
}

pub fn snapshot() -> Result<Value> {
    let path = path().context("Colab journal path is not configured")?;
    Ok(json!({"path":path,"limit":LIMIT,"entries":store::read(&path)?}))
}
