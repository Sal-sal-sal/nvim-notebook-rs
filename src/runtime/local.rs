use std::{
    io::{BufRead, BufReader, Write},
    process::{Child, ChildStdin, ChildStdout, Command, Stdio},
};

use anyhow::{bail, Context, Result};
use serde::Deserialize;
use serde_json::json;

use super::Execution;

const DRIVER: &str = r#"
import ast, contextlib, io, json, sys, traceback
scope = {"__name__": "__main__"}
for message in sys.stdin:
    request = json.loads(message)
    capture = io.StringIO()
    success = True
    try:
        with contextlib.redirect_stdout(capture), contextlib.redirect_stderr(capture):
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
    print(json.dumps({"success": success, "output": capture.getvalue()}), flush=True)
"#;

#[derive(Deserialize)]
struct Reply {
    success: bool,
    output: String,
}

pub struct Local {
    child: Child,
    input: ChildStdin,
    output: BufReader<ChildStdout>,
}

impl Local {
    pub fn start() -> Result<Self> {
        let python = std::env::var("NVIM_NOTEBOOK_PYTHON").unwrap_or_else(|_| "python3".to_owned());
        let mut child = Command::new(python)
            .args(["-u", "-c", DRIVER])
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
        let mut line = String::new();
        if self.output.read_line(&mut line)? == 0 {
            bail!("local Python kernel stopped unexpectedly");
        }
        let reply: Reply = serde_json::from_str(&line).context("invalid local Python response")?;
        Ok(Execution {
            success: reply.success,
            output: reply.output,
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
    }
}
