mod notebook;
mod protocol;
mod runtime;

use std::io::{self, BufRead, Write};

use anyhow::Result;
use serde_json::{json, Value};

use protocol::{Request, Worker};

fn answer(worker: &mut Worker, line: &str) -> Value {
    let raw: Result<Value, _> = serde_json::from_str(line);
    let id = raw
        .as_ref()
        .ok()
        .and_then(|value| value.get("id"))
        .cloned()
        .unwrap_or(Value::Null);
    let result = raw
        .map_err(anyhow::Error::from)
        .and_then(|value| serde_json::from_value::<Request>(value).map_err(anyhow::Error::from))
        .and_then(|request| worker.dispatch(request));
    match result {
        Ok(value) => json!({"id":id,"ok":true,"data":value}),
        Err(error) => json!({"id":id,"ok":false,"error":format!("{error:#}")}),
    }
}

fn worker_main() -> Result<()> {
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    let mut worker = Worker::new();
    for line in stdin.lock().lines() {
        let response = answer(&mut worker, &line?);
        serde_json::to_writer(&mut stdout, &response)?;
        stdout.write_all(b"\n")?;
        stdout.flush()?;
    }
    Ok(())
}

fn main() -> Result<()> {
    match std::env::args().nth(1).as_deref() {
        Some("worker") => worker_main(),
        Some("--version") => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        _ => {
            eprintln!("Usage: nvim-notebook-rs worker | --version");
            std::process::exit(2);
        }
    }
}
