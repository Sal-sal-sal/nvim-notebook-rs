use super::*;

fn entry(number: u64) -> Entry {
    Entry {
        id: 0,
        started_at_ms: number,
        worker_pid: std::process::id(),
        duration_ms: None,
        request: json!({"op":"colab_status","number":number}),
        response: None,
    }
}

#[test]
fn retains_last_hundred_and_completes_the_original_request() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("journal.json");
    for number in 1..=105 {
        assert_eq!(store::insert(&path, entry(number)).unwrap(), number);
    }
    store::complete(&path, 105, 123, &json!({"ok":false,"error":"failure"})).unwrap();
    store::complete(&path, 1, 5, &json!({"ok":true})).unwrap();
    let entries = store::read(&path).unwrap();
    assert_eq!(entries.len(), LIMIT);
    assert_eq!(entries[0].id, 6);
    assert_eq!(entries[99].id, 105);
    assert_eq!(entries[99].duration_ms, Some(123));
    assert_eq!(entries[99].response.as_ref().unwrap()["error"], "failure");
    assert!(entries[0].response.is_none());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        assert_eq!(
            std::fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}

#[test]
fn concurrent_writers_do_not_lose_or_duplicate_entries() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("journal.json");
    std::thread::scope(|scope| {
        for writer in 0..4 {
            let path = &path;
            scope.spawn(move || {
                for index in 0..20 {
                    let id = store::insert(path, entry(writer * 20 + index)).unwrap();
                    store::complete(path, id, 1, &json!({"ok":true})).unwrap();
                }
            });
        }
    });
    let entries = store::read(&path).unwrap();
    assert_eq!(entries.len(), 80);
    for (index, entry) in entries.iter().enumerate() {
        assert_eq!(entry.id, index as u64 + 1);
        assert_eq!(entry.response.as_ref().unwrap()["ok"], true);
    }
}

#[test]
fn invalid_existing_journal_is_reported_without_overwriting_it() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("journal.json");
    std::fs::write(&path, "broken JSON").unwrap();
    assert!(store::insert(&path, entry(1)).is_err());
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "broken JSON");
}
