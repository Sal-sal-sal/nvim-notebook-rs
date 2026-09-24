use std::{
    io::{BufRead, BufReader, Write},
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;
use serde_json::json;

use super::{colab_notebook, Execution};

const REPLY_PREFIX: &str = "\u{1e}NVIM_NOTEBOOK_RS_REPLY:";

const DRIVER: &str = r#"
import ast, base64, contextlib, hashlib, io, json, sys, traceback
scope = {"__name__": "__main__"}
seen_figures = {}
@contextlib.contextmanager
def no_stdin():
    original = sys.stdin
    sys.stdin = io.StringIO("")
    try:
        yield
    finally:
        sys.stdin = original
for message in sys.stdin:
    request = json.loads(message)
    capture = io.StringIO()
    success = True
    images = []
    try:
        with contextlib.redirect_stdout(capture), contextlib.redirect_stderr(capture), no_stdin():
            tree = ast.parse(request["code"], mode="exec")
            if tree.body and isinstance(tree.body[-1], ast.Expr):
                prefix = ast.Module(body=tree.body[:-1], type_ignores=[])
                exec(compile(prefix, "<notebook>", "exec"), scope)
                value = eval(compile(ast.Expression(tree.body[-1].value), "<notebook>", "eval"), scope)
                if value is not None:
                    print(repr(value))
            else:
                exec(compile(tree, "<notebook>", "exec"), scope)
    except BaseException:
        success = False
        traceback.print_exc(file=capture)
    if "matplotlib.pyplot" in sys.modules:
        try:
            with contextlib.redirect_stdout(capture), contextlib.redirect_stderr(capture):
                pyplot = sys.modules["matplotlib.pyplot"]
                open_figures = set(pyplot.get_fignums())
                seen_figures = {number: digest for number, digest in seen_figures.items() if number in open_figures}
                for number in open_figures:
                    image = io.BytesIO()
                    pyplot.figure(number).savefig(image, format="png")
                    content = image.getvalue()
                    digest = hashlib.sha256(content).hexdigest()
                    if seen_figures.get(number) != digest:
                        images.append(base64.b64encode(content).decode())
                        seen_figures[number] = digest
        except BaseException:
            success = False
            traceback.print_exc(file=capture)
    print("\x1eNVIM_NOTEBOOK_RS_REPLY:" + json.dumps({"success": success, "output": capture.getvalue(), "images": images}), flush=True)
"#;

#[derive(Deserialize)]
struct Reply {
    success: bool,
    output: String,
    images: Vec<String>,
}

pub struct Local {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
}

impl Local {
    pub fn start() -> Result<Self> {
        let python = std::env::var("NVIM_NOTEBOOK_PYTHON").unwrap_or_else(|_| "python3".to_owned());
        let mut command = Command::new(python);
        command.args(["-u", "-c", DRIVER]);
        if std::env::var_os("MPLBACKEND").is_none() {
            command.env("MPLBACKEND", "Agg");
        }
        let mut child = command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .context("starting local Python kernel")?;
        let input = child.stdin.take().context("missing Python stdin")?;
        let output = BufReader::new(child.stdout.take().context("missing Python stdout")?);
        Ok(Self {
            child,
            input,
            output,
        })
    }

    pub fn execute(&mut self, code: &str) -> Result<Execution> {
        serde_json::to_writer(&mut self.input, &json!({"code":code}))?;
        self.input.write_all(b"\n")?;
        self.input.flush()?;
        let mut external = String::new();
        let reply: Reply = loop {
            let mut bytes = Vec::new();
            if self.output.read_until(b'\n', &mut bytes)? == 0 {
                bail!("local Python kernel stopped unexpectedly");
            }
            let line = String::from_utf8_lossy(&bytes);
            if let Some(start) = line.find(REPLY_PREFIX) {
                external.push_str(&line[..start]);
                break serde_json::from_str(&line[start + REPLY_PREFIX.len()..])
                    .context("invalid local Python response")?;
            }
            external.push_str(&line);
        };
        let output = external + &reply.output;
        let mut outputs = if output.is_empty() {
            Vec::new()
        } else if reply.success {
            vec![json!({"output_type":"stream","name":"stdout","text":output})]
        } else {
            vec![
                json!({"output_type":"error","ename":"PythonError","evalue":"see traceback","traceback":[output]}),
            ]
        };
        outputs.extend(reply.images.into_iter().map(
            |image| json!({"output_type":"display_data","data":{"image/png":image},"metadata":{}}),
        ));
        let (display, artifacts, _) = colab_notebook::render(&outputs)?;
        Ok(Execution {
            success: reply.success,
            output: display,
            outputs,
            execution_count: serde_json::Value::Null,
            artifacts,
        })
    }
}

impl Drop for Local {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_python_state_between_cells_and_reports_errors() {
        let mut local = Local::start().unwrap();
        assert!(local.execute("x = 40").unwrap().success);
        assert_eq!(local.execute("x + 2").unwrap().output.trim(), "42");
        let error = local.execute("raise ValueError('boom')").unwrap();
        assert!(!error.success);
        assert!(error.output.contains("ValueError: boom"));
        let input_error = local.execute("input()").unwrap();
        assert!(!input_error.success);
        assert!(input_error.output.contains("EOFError"));
        assert_eq!(local.execute("x + 2").unwrap().output.trim(), "42");
        let native = local
            .execute("import os; os.write(1, b'native line\\n'); x + 2")
            .unwrap();
        assert!(native.output.contains("native line"));
        assert!(native.output.contains("42"));
    }

    #[test]
    fn renders_local_matplotlib_figure() {
        let mut local = Local::start().unwrap();
        let result = local
            .execute("import matplotlib.pyplot as plt\nplt.plot([1, 2], [3, 4])")
            .unwrap();
        assert!(result.success, "{}", result.output);
        assert_eq!(result.artifacts.len(), 1);
        let bytes = std::fs::read(&result.artifacts[0]).unwrap();
        assert!(bytes.starts_with(b"\x89PNG\r\n\x1a\n"));
        std::fs::remove_file(&result.artifacts[0]).unwrap();
    }
}
