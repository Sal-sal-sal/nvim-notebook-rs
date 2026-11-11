use std::{
    fs,
    io::{self, Read, Write},
    process::{Command, Stdio},
};

use anyhow::{bail, Context, Result};
use serde_json::Value;

pub fn main() -> Result<()> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let request: Value = serde_json::from_str(&input)?;
    let python = request["python"]
        .as_str()
        .context("analysis Python path is required")?;
    let cache = request["cache"]
        .as_str()
        .context("documentation cache is required")?;
    fs::create_dir_all(cache)?;
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(std::path::Path::new(cache).join("download.lock"))?;
    fs2::FileExt::lock_exclusive(&lock)?;
    let directory = tempfile::tempdir()?;
    for (name, code) in [
        ("entry.py", include_str!("entry.py")),
        ("archive.py", include_str!("archive.py")),
        ("download.py", include_str!("download.py")),
        ("signatures.py", include_str!("signatures.py")),
    ] {
        fs::write(directory.path().join(name), code)?;
    }
    let mut child = Command::new(python)
        .arg("-I")
        .arg(directory.path().join("entry.py"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("starting documentation analysis Python")?;
    child
        .stdin
        .take()
        .context("documentation input pipe")?
        .write_all(input.as_bytes())?;
    let output = child.wait_with_output()?;
    if !output.status.success() {
        bail!(
            "documentation extraction failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let result: Value = serde_json::from_slice(&output.stdout)?;
    serde_json::to_writer(io::stdout().lock(), &result)?;
    Ok(())
}
