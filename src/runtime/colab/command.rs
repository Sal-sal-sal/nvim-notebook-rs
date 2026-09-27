use std::{
    env,
    ffi::OsStr,
    path::Path,
    process::{Command, Stdio},
};

use anyhow::{bail, Context, Result};

use super::super::Execution;

pub fn run(executable: &str, args: &[&str]) -> Result<Execution> {
    let ca_bundle = env::var_os("NVIM_NOTEBOOK_COLAB_CA_BUNDLE");
    execute(executable, args, ca_bundle.as_deref())
}

fn execute(executable: &str, args: &[&str], ca_bundle: Option<&OsStr>) -> Result<Execution> {
    let mut command = Command::new(executable);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(bundle) = ca_bundle {
        if !Path::new(bundle).is_file() {
            bail!(
                "Colab CA bundle does not exist: {}",
                Path::new(bundle).display()
            );
        }
        command.env("SSL_CERT_FILE", bundle);
    }
    let child = command
        .spawn()
        .with_context(|| format!("starting Colab CLI: {executable}"))?;
    let result = child.wait_with_output()?;
    let mut output = String::from_utf8_lossy(&result.stdout).into_owned();
    output.push_str(&String::from_utf8_lossy(&result.stderr));
    if !result.status.success() && output.to_lowercase().contains("authorization code") {
        output =
            format!("Colab authorization required. Run :NotebookColabLogin, then retry.\n{output}");
    }
    Ok(Execution {
        success: result.status.success(),
        output,
        outputs: Vec::new(),
        execution_count: serde_json::Value::Null,
        artifacts: Vec::new(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passes_ca_bundle_only_to_colab_command() {
        let dir = tempfile::tempdir().unwrap();
        let bundle = dir.path().join("cacert.pem");
        std::fs::write(&bundle, "test CA").unwrap();
        let result = execute(
            "/bin/sh",
            &["-c", "printf '%s' \"$SSL_CERT_FILE\""],
            Some(bundle.as_os_str()),
        )
        .unwrap();
        assert!(result.success);
        assert_eq!(result.output, bundle.to_string_lossy());
        assert!(execute("/bin/true", &[], Some(dir.path().as_os_str())).is_err());
    }
}
