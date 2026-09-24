use serde::Deserialize;
use serde_json::Value;

use super::Cell;

#[derive(Deserialize)]
pub struct CellResult {
    pub id: String,
    pub source: String,
    pub outputs: Vec<Value>,
    pub execution_count: Value,
}

pub fn apply(cell: &Cell, saved: &mut Value, results: &[CellResult]) {
    if cell.kind != "code" {
        return;
    }
    if let Some(result) = results
        .iter()
        .find(|result| result.id == cell.id && result.source == cell.source)
    {
        saved["outputs"] = Value::Array(result.outputs.clone());
        saved["execution_count"] = result.execution_count.clone();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn stale_result_cannot_replace_edited_cell_output() {
        let cell = Cell {
            kind: "code".into(),
            id: "a".into(),
            source: "print(2)\n".into(),
            first_line: 1,
            last_line: 2,
        };
        let mut saved = json!({"outputs":[]});
        let stale = CellResult {
            id: "a".into(),
            source: "print(1)\n".into(),
            outputs: vec![json!({"text":"1"})],
            execution_count: json!(1),
        };
        apply(&cell, &mut saved, &[stale]);
        assert_eq!(saved["outputs"], json!([]));
    }
}
