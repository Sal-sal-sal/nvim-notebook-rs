use std::{collections::HashMap, path::Path};

use anyhow::{bail, Result};
use serde_json::{json, Value};

use crate::{
    notebook,
    runtime::{Colab, Execution, Local},
};

mod request;
pub use request::Request;

pub struct Worker {
    local: HashMap<String, Local>,
    colab: Colab,
    artifacts: Vec<String>,
}

impl Worker {
    pub fn new() -> Self {
        Self {
            local: HashMap::new(),
            colab: Colab::new(),
            artifacts: Vec::new(),
        }
    }

    fn local(&mut self, path: &str) -> Result<&mut Local> {
        if !self.local.contains_key(path) {
            self.local.insert(path.to_owned(), Local::start()?);
        }
        Ok(self.local.get_mut(path).unwrap())
    }

    fn run(
        &mut self,
        lines: &[String],
        line: usize,
        all: bool,
        backend: &str,
        path: &str,
    ) -> Result<Value> {
        let cells = notebook::parse(lines)?;
        let selected = notebook::select(&cells, line, all)?;
        let mut output = String::new();
        let mut results = Vec::new();
        let mut artifacts = Vec::new();
        for (index, cell) in selected.iter().enumerate() {
            if cell.source.trim().is_empty() {
                continue;
            }
            let execution = match backend {
                "local" => self.local(path)?.execute(&cell.source)?,
                "colab" => self.colab.run(cell, "3600")?,
                _ => bail!("backend must be 'local' or 'colab'"),
            };
            if all {
                output.push_str(&format!("[Cell {}]\n", index + 1));
            }
            output.push_str(&execution.output);
            if !execution.output.ends_with('\n') && !execution.output.is_empty() {
                output.push('\n');
            }
            artifacts.extend(execution.artifacts.iter().cloned());
            self.artifacts.extend(execution.artifacts);
            results.push(
                json!({"id":cell.id,"source":cell.source,"outputs":execution.outputs,
                                "execution_count":execution.execution_count}),
            );
            if !execution.success {
                return Ok(
                    json!({"success":false,"output":output,"results":results,"artifacts":artifacts}),
                );
            }
        }
        Ok(json!({"success":true,"output":output,"results":results,"artifacts":artifacts}))
    }

    pub fn dispatch(&mut self, request: Request) -> Result<Value> {
        match request {
            Request::Open { path } => {
                let view = notebook::open_view(Path::new(&path))?;
                Ok(json!({"lines":view.lines,"errors":view.errors}))
            }
            Request::New { path } => {
                notebook::create(Path::new(&path))?;
                Ok(json!({"lines":notebook::open(Path::new(&path))?}))
            }
            Request::Save {
                path,
                lines,
                results,
            } => {
                let count = notebook::save_with_results(Path::new(&path), &lines, &results)?;
                Ok(json!({"cell_count":count}))
            }
            Request::Edit {
                lines,
                row,
                action,
                kind,
            } => {
                let edited = match action.as_str() {
                    "insert" => notebook::insert(&lines, row, kind.as_deref().unwrap_or("code"))?,
                    "insert_above" => {
                        notebook::insert_above(&lines, row, kind.as_deref().unwrap_or("code"))?
                    }
                    "delete" => notebook::delete(&lines, row)?,
                    "up" | "down" => notebook::move_cell(&lines, row, &action)?,
                    _ => bail!("unknown cell edit action: {action}"),
                };
                Ok(json!({"lines":edited.lines,"cursor":edited.cursor}))
            }
            Request::Run {
                lines,
                line,
                all,
                backend,
                path,
            } => self.run(
                &lines,
                line,
                all,
                &backend,
                path.as_deref().unwrap_or("<default>"),
            ),
            Request::RestartLocal { path } => {
                self.local.remove(&path);
                Ok(json!({"restarted":true}))
            }
            Request::ColabNew { session, gpu } => execution(
                self.colab.create(&session, gpu.as_deref())?,
                self.colab.session.as_deref(),
            ),
            Request::ColabConnect { session } => {
                execution(self.colab.connect(&session)?, self.colab.session.as_deref())
            }
            Request::ColabStatus => execution(self.colab.status()?, self.colab.session.as_deref()),
            Request::ColabStop => execution(self.colab.stop()?, self.colab.session.as_deref()),
            Request::ColabSessions => {
                execution(self.colab.sessions()?, self.colab.session.as_deref())
            }
            Request::ColabRestart => {
                execution(self.colab.restart()?, self.colab.session.as_deref())
            }
            Request::ColabUrl => execution(self.colab.url()?, self.colab.session.as_deref()),
            Request::ColabInstall { packages } => execution(
                self.colab.install(&packages)?,
                self.colab.session.as_deref(),
            ),
            Request::ColabUpload { local, remote } => execution(
                self.colab.upload(&local, &remote)?,
                self.colab.session.as_deref(),
            ),
            Request::ColabDownload { remote, local } => execution(
                self.colab.download(&remote, &local)?,
                self.colab.session.as_deref(),
            ),
            Request::ColabList { path } => execution(
                self.colab.list(path.as_deref())?,
                self.colab.session.as_deref(),
            ),
        }
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        for artifact in &self.artifacts {
            let _ = std::fs::remove_file(artifact);
        }
    }
}

fn execution(result: Execution, session: Option<&str>) -> Result<Value> {
    Ok(json!({"success":result.success,"output":result.output,"session":session}))
}
