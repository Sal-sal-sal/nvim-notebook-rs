use std::{
    io::Write,
    process::{Command, Stdio},
};

use anyhow::{bail, Context, Result};

use super::Execution;

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

    fn command(&self, args: &[&str], input: Option<&str>) -> Result<Execution> {
        let mut child = Command::new(&self.executable)
            .args(args)
            .stdin(if input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .with_context(|| format!("starting Colab CLI: {}", self.executable))?;
        if let Some(code) = input {
            child.stdin.take().unwrap().write_all(code.as_bytes())?;
        }
        let result = child.wait_with_output()?;
        let mut output = String::from_utf8_lossy(&result.stdout).into_owned();
        output.push_str(&String::from_utf8_lossy(&result.stderr));
        Ok(Execution {
            success: result.status.success(),
            output,
        })
    }

    pub fn create(&mut self, session: &str, gpu: Option<&str>) -> Result<Execution> {
        validate_session(session)?;
        let mut args = vec!["new", "--session", session];
        if let Some(gpu) = gpu {
            if !matches!(gpu, "T4" | "L4" | "G4" | "A100" | "H100") {
                bail!("unsupported Colab GPU: {gpu}");
            }
            args.extend(["--gpu", gpu]);
        }
        let result = self.command(&args, None)?;
        if result.success {
            self.session = Some(session.to_owned());
        }
        Ok(result)
    }

    pub fn connect(&mut self, session: &str) -> Result<Execution> {
        validate_session(session)?;
        let result = self.command(&["status", "--session", session], None)?;
        if result.success {
            self.session = Some(session.to_owned());
        }
        Ok(result)
    }

    pub fn run(&self, code: &str) -> Result<Execution> {
        let session = self
            .session
            .as_deref()
            .context("use NotebookColabNew or NotebookColabConnect first")?;
        self.command(
            &["exec", "--session", session, "--timeout", "3600"],
            Some(code),
        )
    }

    pub fn status(&self) -> Result<Execution> {
        let session = self
            .session
            .as_deref()
            .context("no Colab session selected")?;
        self.command(&["status", "--session", session], None)
    }

    pub fn stop(&mut self) -> Result<Execution> {
        let session = self
            .session
            .as_deref()
            .context("no Colab session selected")?
            .to_owned();
        let result = self.command(&["stop", "--session", &session], None)?;
        if result.success {
            self.session = None;
        }
        Ok(result)
    }

    pub fn sessions(&self) -> Result<Execution> {
        self.command(&["sessions"], None)
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
