use anyhow::{bail, Result};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cell {
    pub kind: String,
    pub id: String,
    pub source: String,
    pub first_line: usize,
    pub last_line: usize,
}

fn marker(line: &str) -> Option<(String, String)> {
    let tail = line.strip_prefix("# %% [")?;
    let (kind, rest) = tail.split_once(']')?;
    if !matches!(kind, "code" | "markdown" | "raw") {
        return None;
    }
    let id = rest.strip_prefix(" id=")?;
    if id.is_empty() || id.contains(char::is_whitespace) {
        return None;
    }
    Some((kind.to_owned(), id.to_owned()))
}

fn source_line(kind: &str, line: &str) -> Result<String> {
    if kind == "code" {
        return Ok(line.to_owned());
    }
    if line == "#" {
        return Ok(String::new());
    }
    line.strip_prefix("# ")
        .map(str::to_owned)
        .ok_or_else(|| anyhow::anyhow!("{kind} lines must start with '# ' or '#'"))
}

pub fn parse(lines: &[String]) -> Result<Vec<Cell>> {
    let mut cells = Vec::new();
    let mut current: Option<Cell> = None;
    for (index, line) in lines.iter().enumerate() {
        if let Some((kind, id)) = marker(line) {
            if let Some(mut cell) = current.take() {
                cell.last_line = index;
                cells.push(cell);
            }
            current = Some(Cell {
                kind,
                id,
                source: String::new(),
                first_line: index + 1,
                last_line: index + 1,
            });
        } else if line.starts_with("# %% [") {
            bail!(
                "invalid cell marker on line {}: expected '# %% [code|markdown|raw] id=...'",
                index + 1
            );
        } else if let Some(cell) = current.as_mut() {
            cell.source.push_str(&source_line(&cell.kind, line)?);
            cell.source.push('\n');
        } else if !line.trim().is_empty() {
            bail!("notebook text must start with a '# %% [type] id=...' marker");
        }
    }
    if let Some(mut cell) = current {
        cell.last_line = lines.len();
        cells.push(cell);
    }
    if cells.is_empty() {
        bail!("notebook must contain at least one cell");
    }
    let mut ids = std::collections::HashSet::new();
    for cell in &cells {
        if !ids.insert(&cell.id) {
            bail!("duplicate cell id: {}", cell.id);
        }
    }
    Ok(cells)
}

pub fn select(cells: &[Cell], line: usize, all: bool) -> Result<Vec<Cell>> {
    let selected = cells
        .iter()
        .filter(|cell| {
            cell.kind == "code" && (all || line >= cell.first_line && line <= cell.last_line)
        })
        .cloned()
        .collect::<Vec<_>>();
    if selected.is_empty() {
        bail!("cursor is outside a Python code cell");
    }
    Ok(selected)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selects_only_code_under_cursor() {
        let lines = [
            "# %% [markdown] id=m",
            "# Title",
            "# %% [code] id=c",
            "x = 2",
            "print(x)",
        ]
        .map(str::to_owned);
        let cells = parse(&lines).unwrap();
        assert!(select(&cells, 2, false).is_err());
        assert_eq!(
            select(&cells, 4, false).unwrap()[0].source,
            "x = 2\nprint(x)\n"
        );
    }

    #[test]
    fn rejects_duplicate_ids() {
        let lines = ["# %% [code] id=c", "x = 1", "# %% [code] id=c"].map(str::to_owned);
        assert!(parse(&lines).is_err());
    }

    #[test]
    fn rejects_invalid_markers_at_any_cell_boundary() {
        let invalid = [
            "# %% [code] }d=broken",
            "# %% [code] id=",
            "# %% [code] id=broken extra",
            "# %% [unknown] id=broken",
            "# %% [code]id=broken",
            "# %% [code]  id=broken",
            "# %% [code] id=broken ",
        ];
        let positions = [0, 2, 4];
        for marker in invalid {
            for index in positions {
                let mut lines = [
                    "# %% [code] id=one",
                    "print(1)",
                    "# %% [code] id=two",
                    "print(2)",
                ]
                .map(str::to_owned)
                .to_vec();
                lines.insert(index, marker.to_owned());
                let error = parse(&lines).unwrap_err().to_string();
                assert!(
                    error.contains(&format!("invalid cell marker on line {}", index + 1)),
                    "marker {marker:?} at line {} returned {error:?}",
                    index + 1
                );
            }
        }
    }
}
