use anyhow::{bail, Context, Result};

use super::{colab_notebook, Execution};
use crate::notebook::Cell;

mod command;

pub struct Colab {
    executable: String,
    pub session: Option<String>,
}

impl Colab {
    pub fn new() -> Self {
        let executable =
            std::env::var("NVIM_NOTEBOOK_COLAB").unwrap_or_else(|_| "colab".to_owned());
        Self {
            executable,
            session: None,
        }
    }

    fn command(&self, args: &[&str]) -> Result<Execution> {
        command::run(&self.executable, args)
    }

    pub fn create(&mut self, session: &str, accelerator: Option<&str>) -> Result<Execution> {
        validate_session(session)?;
        let mut args = vec!["new", "--session", session];
        if let Some(accelerator) = accelerator {
            if matches!(accelerator, "T4" | "L4" | "G4" | "A100" | "H100") {
                args.extend(["--gpu", accelerator]);
            } else if matches!(accelerator, "TPU:v5e1" | "TPU:v6e1") {
                args.extend(["--tpu", &accelerator[4..]]);
            } else {
                bail!("accelerator must be T4, L4, G4, A100, H100, TPU:v5e1, or TPU:v6e1");
            }
        }
        let result = self.command(&args)?;
        if result.success {
            self.session = Some(session.to_owned());
            return self.verify_selected(result);
        }
        Ok(result)
    }

    pub fn connect(&mut self, session: &str) -> Result<Execution> {
        validate_session(session)?;
        let result = self.command(&["status", "--session", session])?;
        if result.success {
            self.session = Some(session.to_owned());
            return self.verify_selected(result);
        }
        Ok(result)
    }

    fn verify_selected(&self, status: Execution) -> Result<Execution> {
        let probe = Cell {
            kind: "code".to_owned(),
            id: "connection-check".to_owned(),
            source: "pass\n".to_owned(),
            first_line: 1,
            last_line: 1,
        };
        let result = self.run(&probe, "20")?;
        if result.success {
            Ok(status)
        } else {
            Ok(result)
        }
    }

    pub fn run(&self, cell: &Cell, timeout: &str) -> Result<Execution> {
        let session = self
            .session
            .as_deref()
            .context("use NotebookColabNew or NotebookColabConnect first")?;
        let dir = tempfile::tempdir()?;
        let path = dir.path().join("request.ipynb");
        colab_notebook::write_input(&path, cell)?;
        let file = path
            .to_str()
            .context("temporary notebook path is not UTF-8")?;
        let result = self.command(&[
            "exec",
            "--session",
            session,
            "--file",
            file,
            "--timeout",
            timeout,
        ])?;
        colab_notebook::read_output(&path, result)
    }

    pub fn status(&self) -> Result<Execution> {
        let session = self
            .session
            .as_deref()
            .context("no Colab session selected")?;
        let result = self.command(&["status", "--session", session])?;
        if result.success {
            self.verify_selected(result)
        } else {
            Ok(result)
        }
    }

    pub fn stop(&mut self) -> Result<Execution> {
        let session = self
            .session
            .as_deref()
            .context("no Colab session selected")?
            .to_owned();
        let result = self.command(&["stop", "--session", &session])?;
        if result.success {
            self.session = None;
        }
        Ok(result)
    }

    pub fn sessions(&self) -> Result<Execution> {
        self.command(&["sessions"])
    }

    fn selected(&self) -> Result<&str> {
        self.session.as_deref().context("no Colab session selected")
    }

    pub fn restart(&self) -> Result<Execution> {
        self.command(&["restart-kernel", "--session", self.selected()?])
    }

    pub fn url(&self) -> Result<Execution> {
        self.command(&["url", "--session", self.selected()?])
    }

    pub fn install(&self, packages: &[String]) -> Result<Execution> {
        if packages.is_empty() || packages.iter().any(|package| package.starts_with('-')) {
            bail!("give one or more package names without CLI flags");
        }
        let mut args = vec!["install", "--session", self.selected()?];
        args.extend(packages.iter().map(String::as_str));
        self.command(&args)
    }

    pub fn upload(&self, local: &str, remote: &str) -> Result<Execution> {
        if !std::path::Path::new(local).is_file() {
            bail!("local upload file does not exist: {local}");
        }
        self.command(&["upload", "--session", self.selected()?, local, remote])
    }

    pub fn download(&self, remote: &str, local: &str) -> Result<Execution> {
        self.command(&["download", "--session", self.selected()?, remote, local])
    }

    pub fn list(&self, path: Option<&str>) -> Result<Execution> {
        let mut args = vec!["ls", "--session", self.selected()?];
        if let Some(path) = path {
            args.push(path);
        }
        self.command(&args)
    }
}

fn validate_session(session: &str) -> Result<()> {
    if session.is_empty()
        || !session
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'))
    {
        bail!("session name may contain only letters, digits, '-' and '_'");
    }
    Ok(())
}
