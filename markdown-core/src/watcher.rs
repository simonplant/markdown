use notify::{Config, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// Events emitted by the file watcher.
#[derive(Debug, Clone, PartialEq)]
pub enum FileChangeEvent {
    /// File content was modified (or recreated via atomic save).
    Modified,
    /// File was deleted or moved away.
    Deleted,
}

/// Watches a single file for external changes with debouncing.
///
/// Watches the parent directory (not the file itself) so that atomic save
/// patterns (delete + create) are detected correctly. Events are debounced
/// to coalesce rapid sequences into a single notification.
pub struct FileWatcher {
    _watcher: RecommendedWatcher,
}

impl FileWatcher {
    /// Start watching a file at `path`.
    ///
    /// `debounce_ms` controls how long to wait after the first filesystem event
    /// before firing the callback, coalescing rapid events (e.g. atomic saves).
    ///
    /// `callback` is invoked on a background thread when an external change is
    /// detected after debouncing.
    pub fn new<F>(path: &str, debounce_ms: u64, callback: F) -> Result<Self, notify::Error>
    where
        F: Fn(FileChangeEvent) + Send + 'static,
    {
        let file_path = PathBuf::from(path);
        let canonical = file_path
            .canonicalize()
            .unwrap_or_else(|_| file_path.clone());
        let watch_dir = canonical
            .parent()
            .unwrap_or(Path::new("."))
            .to_path_buf();
        let watched_name = canonical.file_name().map(|n| n.to_os_string());

        let (tx, rx) = mpsc::channel::<()>();

        let mut watcher = RecommendedWatcher::new(
            {
                let watched_name = watched_name.clone();
                let tx = tx.clone();
                move |res: Result<notify::Event, notify::Error>| {
                    if let Ok(event) = res {
                        let dominated = match &watched_name {
                            Some(name) => event
                                .paths
                                .iter()
                                .any(|p| p.file_name().map_or(false, |n| n == name.as_os_str())),
                            None => false,
                        };
                        if dominated {
                            let _ = tx.send(());
                        }
                    }
                }
            },
            Config::default(),
        )?;

        watcher.watch(&watch_dir, RecursiveMode::NonRecursive)?;

        let debounce = Duration::from_millis(debounce_ms);

        std::thread::spawn(move || {
            loop {
                // Block until the first relevant event arrives
                if rx.recv().is_err() {
                    return; // Channel closed — watcher was dropped
                }

                // Debounce: absorb further events within the window
                let deadline = Instant::now() + debounce;
                loop {
                    let remaining = deadline.saturating_duration_since(Instant::now());
                    if remaining.is_zero() {
                        break;
                    }
                    match rx.recv_timeout(remaining) {
                        Ok(()) => {} // more events, keep debouncing
                        Err(mpsc::RecvTimeoutError::Timeout) => break,
                        Err(mpsc::RecvTimeoutError::Disconnected) => return,
                    }
                }

                // After debounce, check the file's current state
                if canonical.exists() {
                    callback(FileChangeEvent::Modified);
                } else {
                    callback(FileChangeEvent::Deleted);
                }
            }
        });

        Ok(FileWatcher { _watcher: watcher })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[test]
    fn detects_modification() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.md");
        std::fs::write(&file_path, "original").unwrap();

        let events: Arc<Mutex<Vec<FileChangeEvent>>> = Arc::new(Mutex::new(Vec::new()));
        let events_clone = events.clone();

        let _watcher = FileWatcher::new(
            file_path.to_str().unwrap(),
            100,
            move |event| {
                events_clone.lock().unwrap().push(event);
            },
        )
        .unwrap();

        // Give the watcher time to start
        std::thread::sleep(Duration::from_millis(200));

        // Modify the file externally
        std::fs::write(&file_path, "modified").unwrap();

        // Wait for debounce + processing
        std::thread::sleep(Duration::from_millis(500));

        let captured = events.lock().unwrap();
        assert!(
            captured.contains(&FileChangeEvent::Modified),
            "Expected Modified event, got: {:?}",
            *captured
        );
    }

    #[test]
    fn detects_deletion() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.md");
        std::fs::write(&file_path, "content").unwrap();

        let events: Arc<Mutex<Vec<FileChangeEvent>>> = Arc::new(Mutex::new(Vec::new()));
        let events_clone = events.clone();

        let _watcher = FileWatcher::new(
            file_path.to_str().unwrap(),
            100,
            move |event| {
                events_clone.lock().unwrap().push(event);
            },
        )
        .unwrap();

        std::thread::sleep(Duration::from_millis(200));

        // Delete the file
        std::fs::remove_file(&file_path).unwrap();

        std::thread::sleep(Duration::from_millis(500));

        let captured = events.lock().unwrap();
        assert!(
            captured.contains(&FileChangeEvent::Deleted),
            "Expected Deleted event, got: {:?}",
            *captured
        );
    }

    #[test]
    fn debounces_atomic_save() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.md");
        std::fs::write(&file_path, "original").unwrap();

        let events: Arc<Mutex<Vec<FileChangeEvent>>> = Arc::new(Mutex::new(Vec::new()));
        let events_clone = events.clone();

        let _watcher = FileWatcher::new(
            file_path.to_str().unwrap(),
            200,
            move |event| {
                events_clone.lock().unwrap().push(event);
            },
        )
        .unwrap();

        std::thread::sleep(Duration::from_millis(200));

        // Simulate atomic save: delete then recreate
        std::fs::remove_file(&file_path).unwrap();
        std::thread::sleep(Duration::from_millis(10));
        std::fs::write(&file_path, "new content").unwrap();

        // Wait for debounce
        std::thread::sleep(Duration::from_millis(600));

        let captured = events.lock().unwrap();
        // Should see Modified (file exists after debounce), not Deleted
        assert!(
            captured.last() == Some(&FileChangeEvent::Modified),
            "Expected final event to be Modified (atomic save), got: {:?}",
            *captured
        );
    }
}
