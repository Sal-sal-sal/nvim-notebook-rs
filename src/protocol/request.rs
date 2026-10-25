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
    Run(Run),
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
    ColabJournal,
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

#[derive(Deserialize)]
pub struct Run {
    pub all: bool,
    #[serde(default = "default_notebook_runtime")]
    pub notebook_runtime: u64,
    pub lines: Vec<String>,
    pub line: usize,
    pub backend: String,
    pub path: Option<String>,
}

fn default_notebook_runtime() -> u64 {
    3600
}
