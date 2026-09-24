use serde::Deserialize;

use crate::notebook::CellResult;

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
        #[serde(default)]
        results: Vec<CellResult>,
    },
    Edit {
        lines: Vec<String>,
        row: usize,
        action: String,
        kind: Option<String>,
    },
    Run {
        lines: Vec<String>,
        line: usize,
        all: bool,
        backend: String,
        path: Option<String>,
    },
    RestartLocal {
        path: String,
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
    ColabRestart,
    ColabUrl,
    ColabInstall {
        packages: Vec<String>,
    },
    ColabUpload {
        local: String,
        remote: String,
    },
    ColabDownload {
        remote: String,
        local: String,
    },
    ColabList {
        path: Option<String>,
    },
}
