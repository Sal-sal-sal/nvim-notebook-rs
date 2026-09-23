use std::path::Path;

use anyhow::{bail, Result};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{
    notebook,
    runtime::{Colab, Execution, Local},
};

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
pub enum Request {
    Open {
        path: String,
    },
    New {
        path: String,
    },
    Save {
        path: String,
        lines: Vec<String>,
    },
    Run {
        lines: Vec<String>,
        line: usize,
        all: bool,
        backend: String,
    },
    ColabNew {
        session: String,
        gpu: Option<String>,
    },
    ColabConnect {
        session: String,
    },
    ColabStatus,
    ColabStop,
    ColabSessions,
}

pub struct Worker {
    local: Option<Local>,
    colab: Colab,
}

impl Worker {
    pub fn new() -> Self {
        Self {
            local: None,
            colab: Colab::new(),
        }
    }

    fn local(&mut self) -> Result<&mut Local> {
        if self.local.is_none() {
            self.local = Some(Local::start()?);
        }
        Ok(self.local.as_mut().unwrap())
    }

    fn run(&mut self, lines: &[String], line: usize, all: bool, backend: &str) -> Result<Value> {
        let cells = notebook::parse(lines)?;
        let selected = notebook::select(&cells, line, all)?;
        let mut output = String::new();
        for (index, code) in selected.iter().enumerate() {
            if code.trim().is_empty() {
                continue;
            }
            let execution = match backend {
                "local" => self.local()?.execute(code)?,
                "colab" => self.colab.run(code)?,
                _ => bail!("backend must be 'local' or 'colab'"),
            };
            if all {
                output.push_str(&format!("[Cell {}]\n", index + 1));
            }
            output.push_str(&execution.output);
            if !execution.output.ends_with('\n') && !execution.output.is_empty() {
                output.push('\n');
            }
            if !execution.success {
                return Ok(json!({"success":false,"output":output}));
            }
        }
        Ok(json!({"success":true,"output":output}))
    }

    pub fn dispatch(&mut self, request: Request) -> Result<Value> {
        match request {
            Request::Open { path } => Ok(json!({"lines":notebook::open(Path::new(&path))?})),
            Request::New { path } => {
                notebook::create(Path::new(&path))?;
                Ok(json!({"lines":notebook::open(Path::new(&path))?}))
            }
            Request::Save { path, lines } => {
                let count = notebook::save(Path::new(&path), &lines)?;
                Ok(json!({"cell_count":count}))
            }
            Request::Run {
                lines,
                line,
                all,
                backend,
            } => self.run(&lines, line, all, &backend),
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
        }
    }
}

fn execution(result: Execution, session: Option<&str>) -> Result<Value> {
    Ok(json!({"success":result.success,"output":result.output,"session":session}))
}
