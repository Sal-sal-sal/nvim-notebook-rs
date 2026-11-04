use std::collections::HashSet;

use serde_json::Value;

pub(super) fn for_cells(cells: &[Value]) -> Vec<String> {
    let explicit: HashSet<_> = cells
        .iter()
        .filter_map(|cell| cell["id"].as_str())
        .collect();
    cells
        .iter()
        .enumerate()
        .map(|(index, cell)| match cell["id"].as_str() {
            Some(id) => id.to_owned(),
            None => legacy_id(index, &explicit),
        })
        .collect()
}

fn legacy_id(index: usize, explicit: &HashSet<&str>) -> String {
    let base = format!("cell-{}", index + 1);
    let mut id = base.clone();
    let mut suffix = 1;
    while explicit.contains(id.as_str()) {
        id = format!("{base}-{suffix}");
        suffix += 1;
    }
    id
}
