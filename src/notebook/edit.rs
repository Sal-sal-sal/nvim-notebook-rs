use std::{
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{bail, Result};

use super::parse;

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

pub struct Edit {
    pub lines: Vec<String>,
    pub cursor: usize,
}

fn current(cells: &[super::Cell], row: usize) -> Result<usize> {
    cells
        .iter()
        .position(|cell| row >= cell.first_line && row <= cell.last_line)
        .ok_or_else(|| anyhow::anyhow!("cursor is outside a cell"))
}

fn marker(kind: &str) -> Result<String> {
    if !matches!(kind, "code" | "markdown" | "raw") {
        bail!("cell type must be code, markdown, or raw");
    }
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let sequence = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    Ok(format!("# %% [{kind}] id=cell-{nanos:x}-{sequence:x}"))
}

fn insert_at(lines: &[String], at: usize, kind: &str) -> Result<Edit> {
    let mut edited = lines.to_vec();
    let blank = if kind == "code" { "" } else { "#" };
    edited.splice(at..at, [marker(kind)?, blank.to_owned()]);
    Ok(Edit {
        lines: edited,
        cursor: at + 2,
    })
}

pub fn insert(lines: &[String], row: usize, kind: &str) -> Result<Edit> {
    let cells = parse(lines)?;
    insert_at(lines, cells[current(&cells, row)?].last_line, kind)
}

pub fn insert_above(lines: &[String], row: usize, kind: &str) -> Result<Edit> {
    let cells = parse(lines)?;
    insert_at(lines, cells[current(&cells, row)?].first_line - 1, kind)
}

pub fn delete(lines: &[String], row: usize) -> Result<Edit> {
    let cells = parse(lines)?;
    if cells.len() == 1 {
        bail!("cannot delete the only cell");
    }
    let index = current(&cells, row)?;
    let mut edited = lines.to_vec();
    edited.drain(cells[index].first_line - 1..cells[index].last_line);
    let cursor = if index + 1 < cells.len() {
        cells[index].first_line
    } else {
        cells[index - 1].first_line
    };
    Ok(Edit {
        lines: edited,
        cursor,
    })
}

pub fn move_cell(lines: &[String], row: usize, direction: &str) -> Result<Edit> {
    let cells = parse(lines)?;
    let index = current(&cells, row)?;
    let target = match direction {
        "up" if index > 0 => index - 1,
        "down" if index + 1 < cells.len() => index + 1,
        "up" | "down" => bail!("cell is already at the {direction} edge"),
        _ => bail!("direction must be up or down"),
    };
    let mut blocks = cells
        .iter()
        .map(|cell| lines[cell.first_line - 1..cell.last_line].to_vec())
        .collect::<Vec<_>>();
    blocks.swap(index, target);
    let mut edited = lines[..cells[0].first_line - 1].to_vec();
    let cursor = edited.len() + 1 + blocks.iter().take(target).map(Vec::len).sum::<usize>();
    edited.extend(blocks.into_iter().flatten());
    Ok(Edit {
        lines: edited,
        cursor,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn inserts_moves_and_deletes_cells_without_losing_source() {
        let lines = ["# %% [code] id=a", "x = 1", "# %% [code] id=b", "x + 1"].map(str::to_owned);
        let inserted = insert(&lines, 2, "markdown").unwrap();
        assert_eq!(parse(&inserted.lines).unwrap().len(), 3);
        let moved = move_cell(&inserted.lines, inserted.cursor, "down").unwrap();
        let cells = parse(&moved.lines).unwrap();
        assert_eq!(cells[1].id, "b");
        assert_eq!(cells[1].source, "x + 1\n");
        let deleted = delete(&moved.lines, moved.cursor).unwrap();
        assert_eq!(parse(&deleted.lines).unwrap().len(), 2);
    }

    #[test]
    fn inserts_above_first_and_second_cells() {
        let lines = ["# %% [code] id=a", "x = 1", "# %% [code] id=b", "x + 1"].map(str::to_owned);
        let first = insert_above(&lines, 2, "code").unwrap();
        let cells = parse(&first.lines).unwrap();
        assert_eq!(first.cursor, 2);
        assert_eq!(cells[1].id, "a");
        assert_eq!(cells[2].id, "b");
        let middle = insert_above(&lines, 4, "markdown").unwrap();
        let cells = parse(&middle.lines).unwrap();
        assert_eq!(middle.cursor, 4);
        assert_eq!(cells[0].id, "a");
        assert_eq!(cells[1].kind, "markdown");
        assert_eq!(cells[2].id, "b");
    }
}
