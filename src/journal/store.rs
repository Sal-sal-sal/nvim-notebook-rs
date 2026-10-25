use std::{fs, fs::OpenOptions, path::Path};

use anyhow::{Context, Result};
use serde_json::Value;

use super::{Entry, LIMIT};

pub fn read(path: &Path) -> Result<Vec<Entry>> {
    match fs::read(path) {
        Ok(bytes) => serde_json::from_slice(&bytes).context("reading Colab journal JSON"),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
        Err(error) => Err(error).context("reading Colab journal"),
    }
}

fn update<T>(path: &Path, change: impl FnOnce(&mut Vec<Entry>) -> Result<T>) -> Result<T> {
    let parent = path
        .parent()
        .filter(|path| !path.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut directory = fs::DirBuilder::new();
    directory.recursive(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        directory.mode(0o700);
    }
    directory
        .create(parent)
        .context("creating Colab journal directory")?;
    let mut options = OpenOptions::new();
    options.create(true).read(true).write(true).truncate(false);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let lock = options.open(path.with_extension("lock"))?;
    fs2::FileExt::lock_exclusive(&lock)?;
    let mut entries = read(path)?;
    let result = change(&mut entries)?;
    if entries.len() > LIMIT {
        entries.drain(..entries.len() - LIMIT);
    }
    let temporary = tempfile::NamedTempFile::new_in(parent)?;
    serde_json::to_writer(temporary.as_file(), &entries)?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).context("saving Colab journal")?;
    Ok(result)
}

pub fn insert(path: &Path, mut entry: Entry) -> Result<u64> {
    update(path, |entries| {
        entry.id = entries.last().map_or(1, |last| last.id + 1);
        let id = entry.id;
        entries.push(entry);
        Ok(id)
    })
}

pub fn complete(path: &Path, id: u64, duration_ms: u64, response: &Value) -> Result<()> {
    update(path, |entries| {
        if let Some(entry) = entries.iter_mut().find(|entry| entry.id == id) {
            entry.duration_ms = Some(duration_ms);
            entry.response = Some(response.clone());
        }
        Ok(())
    })
}
