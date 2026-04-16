use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use markdown_core::watcher::{FileChangeEvent, FileWatcher};
use markdown_core::Document;
use tauri::menu::{MenuBuilder, MenuItemBuilder, PredefinedMenuItem, SubmenuBuilder};
use tauri::{Emitter, Manager, State, WebviewUrl, WebviewWindowBuilder};

static WINDOW_COUNTER: AtomicU32 = AtomicU32::new(1);

/// Per-window file watcher state.
struct WatchState {
    _watcher: FileWatcher,
    /// Content hash of the last save we performed, used to distinguish
    /// our own saves from external changes.
    last_saved_hash: Arc<AtomicU64>,
}

pub struct AppState {
    pub documents: Mutex<HashMap<String, Document>>,
    pub pending_opens: Mutex<HashMap<String, String>>,
    pub watch_states: Mutex<HashMap<String, WatchState>>,
}

impl Default for AppState {
    fn default() -> Self {
        AppState {
            documents: Mutex::new(HashMap::new()),
            pending_opens: Mutex::new(HashMap::new()),
            watch_states: Mutex::new(HashMap::new()),
        }
    }
}

/// FNV-1a hash for content comparison (self-save detection).
fn fnv1a_hash(data: &[u8]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for &byte in data {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

#[derive(serde::Serialize, Clone)]
struct FileChangePayload {
    kind: String,
    path: String,
}

// ---------------------------------------------------------------------------
// Recent files helpers
// ---------------------------------------------------------------------------

fn load_recent_files(app: &tauri::AppHandle) -> Vec<String> {
    let Ok(data_dir) = app.path().app_data_dir() else {
        return vec![];
    };
    let path = data_dir.join("recent.json");
    let Ok(data) = std::fs::read_to_string(&path) else {
        return vec![];
    };
    let mut files: Vec<String> = serde_json::from_str(&data).unwrap_or_default();
    // Silently remove paths that no longer exist on disk
    files.retain(|p| std::path::Path::new(p).exists());
    files
}

fn save_recent_files(app: &tauri::AppHandle, files: &[String]) -> Result<(), String> {
    let data_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&data_dir).map_err(|e| e.to_string())?;
    let path = data_dir.join("recent.json");
    let json = serde_json::to_string_pretty(files).map_err(|e| e.to_string())?;
    std::fs::write(&path, json).map_err(|e| e.to_string())?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Menu builder
// ---------------------------------------------------------------------------

fn rebuild_menu(app: &tauri::AppHandle) -> Result<(), tauri::Error> {
    let recent = load_recent_files(app);

    let new_item = MenuItemBuilder::with_id("new", "New")
        .accelerator("CmdOrCtrl+N")
        .build(app)?;
    let open_item = MenuItemBuilder::with_id("open", "Open\u{2026}")
        .accelerator("CmdOrCtrl+O")
        .build(app)?;
    let save_item = MenuItemBuilder::with_id("save", "Save")
        .accelerator("CmdOrCtrl+S")
        .build(app)?;

    let mut file_menu = SubmenuBuilder::new(app, "File")
        .item(&new_item)
        .item(&open_item);

    if !recent.is_empty() {
        let mut recent_sub = SubmenuBuilder::new(app, "Open Recent");
        for file_path in &recent {
            let display = std::path::Path::new(file_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or(file_path);
            let item = MenuItemBuilder::with_id(
                &format!("recent:{}", file_path),
                display,
            )
            .build(app)?;
            recent_sub = recent_sub.item(&item);
        }
        let recent_menu = recent_sub.build()?;
        file_menu = file_menu.item(&recent_menu);
    }

    let file_menu = file_menu.separator().item(&save_item).build()?;

    // macOS app menu with standard items (About, Hide, Quit)
    #[cfg(target_os = "macos")]
    let menu = {
        let app_menu = SubmenuBuilder::new(app, "Markdown")
            .item(&PredefinedMenuItem::about(app, Some("About Markdown"), None)?)
            .separator()
            .item(&PredefinedMenuItem::hide(app, None)?)
            .item(&PredefinedMenuItem::hide_others(app, None)?)
            .item(&PredefinedMenuItem::show_all(app, None)?)
            .separator()
            .item(&PredefinedMenuItem::quit(app, None)?)
            .build()?;
        MenuBuilder::new(app)
            .item(&app_menu)
            .item(&file_menu)
            .build()?
    };
    #[cfg(not(target_os = "macos"))]
    let menu = {
        let quit_item = MenuItemBuilder::with_id("quit", "Exit")
            .accelerator("Alt+F4")
            .build(app)?;
        let file_with_quit = SubmenuBuilder::new(app, "File")
            .item(&new_item)
            .item(&open_item)
            .separator()
            .item(&save_item)
            .separator()
            .item(&quit_item)
            .build()?;
        MenuBuilder::new(app).item(&file_with_quit).build()?
    };

    app.set_menu(menu)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Existing IPC commands (updated for per-window document state)
// ---------------------------------------------------------------------------

#[tauri::command]
fn open_file(state: State<'_, AppState>, window: tauri::Window, path: String) -> Result<String, String> {
    let doc = Document::open_file(&path).map_err(|e| e.to_string())?;
    let text = doc.current_text().to_string();
    state
        .documents
        .lock()
        .unwrap()
        .insert(window.label().to_string(), doc);
    Ok(text)
}

#[tauri::command]
fn edit(
    state: State<'_, AppState>,
    window: tauri::Window,
    offset: usize,
    delete: usize,
    insert: String,
) -> Result<(), String> {
    let mut docs = state.documents.lock().unwrap();
    let doc = docs
        .get_mut(window.label())
        .ok_or("No document open")?;
    doc.edit(offset, delete, &insert);
    Ok(())
}

#[tauri::command]
fn save_file(
    state: State<'_, AppState>,
    window: tauri::Window,
    path: String,
    content: String,
) -> Result<(), String> {
    // Update the save hash BEFORE writing so the watcher can distinguish
    // our own saves from external changes.
    let hash = fnv1a_hash(content.as_bytes());
    {
        let watch_states = state.watch_states.lock().unwrap();
        if let Some(ws) = watch_states.get(window.label()) {
            ws.last_saved_hash.store(hash, Ordering::SeqCst);
        }
    }

    std::fs::write(&path, &content).map_err(|e| e.to_string())?;
    state
        .documents
        .lock()
        .unwrap()
        .insert(window.label().to_string(), Document::from_content(content));
    Ok(())
}

#[tauri::command]
fn current_text(state: State<'_, AppState>, window: tauri::Window) -> Result<String, String> {
    let docs = state.documents.lock().unwrap();
    let doc = docs.get(window.label()).ok_or("No document open")?;
    Ok(doc.current_text().to_string())
}

// ---------------------------------------------------------------------------
// New IPC commands for FEAT-019
// ---------------------------------------------------------------------------

#[tauri::command]
fn get_recent_files(app: tauri::AppHandle) -> Vec<String> {
    load_recent_files(&app)
}

#[tauri::command]
fn add_recent_file(app: tauri::AppHandle, path: String) -> Result<(), String> {
    let mut files = load_recent_files(&app);
    files.retain(|p| p != &path);
    files.insert(0, path);
    files.truncate(10);
    save_recent_files(&app, &files)?;
    // Rebuild menu to show updated recent files
    rebuild_menu(&app).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
fn create_window(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    file_path: Option<String>,
) -> Result<(), String> {
    let n = WINDOW_COUNTER.fetch_add(1, Ordering::Relaxed);
    let label = format!("window-{}", n);

    if let Some(ref path) = file_path {
        state
            .pending_opens
            .lock()
            .unwrap()
            .insert(label.clone(), path.clone());
    }

    WebviewWindowBuilder::new(&app, &label, WebviewUrl::App("index.html".into()))
        .title("Markdown")
        .inner_size(900.0, 700.0)
        .build()
        .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
fn get_pending_open(state: State<'_, AppState>, window: tauri::Window) -> Option<String> {
    state
        .pending_opens
        .lock()
        .unwrap()
        .remove(window.label())
}

#[tauri::command]
fn close_current_window(app: tauri::AppHandle, window: tauri::Window) -> Result<(), String> {
    let is_last = app.webview_windows().len() <= 1;
    window.destroy().map_err(|e| e.to_string())?;
    if is_last {
        app.exit(0);
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Wikilink commands (FEAT-035)
// ---------------------------------------------------------------------------

/// Resolve a wikilink target to a real .md file path.
/// Searches the directory tree starting from the current file's directory,
/// walking upward to find the nearest match.
#[tauri::command]
fn resolve_wikilink(link_text: String, current_file_path: String) -> Option<String> {
    let current = std::path::Path::new(&current_file_path);
    let parent = current.parent()?;

    // Normalize: strip .md extension if present, we'll add it back
    let base_name = link_text.strip_suffix(".md").unwrap_or(&link_text);
    let target_filename = format!("{}.md", base_name);

    // If link_text contains path separators, try as a relative path from current dir
    if link_text.contains('/') || link_text.contains('\\') {
        let relative = if link_text.ends_with(".md") {
            parent.join(&link_text)
        } else {
            parent.join(&target_filename)
        };
        if relative.is_file() {
            return relative.canonicalize().ok()?.to_str().map(String::from);
        }
    }

    // Walk the directory tree starting from parent, searching for the file.
    // First check the current directory, then walk upward (max 5 levels).
    let mut search_dir = Some(parent);
    let mut depth = 0;
    while let Some(dir) = search_dir {
        if depth > 5 {
            break;
        }
        if let Some(found) = find_md_file_recursive(dir, &target_filename) {
            return found.to_str().map(String::from);
        }
        search_dir = dir.parent();
        depth += 1;
    }

    None
}

/// Recursively search a directory for a .md file matching the given filename.
/// Returns the first match found (depth-first).
fn find_md_file_recursive(dir: &std::path::Path, filename: &str) -> Option<std::path::PathBuf> {
    // Check immediate children first (breadth-first for locality)
    let Ok(entries) = std::fs::read_dir(dir) else {
        return None;
    };

    let mut subdirs = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if name.eq_ignore_ascii_case(filename) {
                    return Some(path);
                }
            }
        } else if path.is_dir() {
            // Skip hidden directories and common non-content directories
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if !name.starts_with('.') && name != "node_modules" && name != "target" {
                    subdirs.push(path);
                }
            }
        }
    }

    // Then recurse into subdirectories
    for subdir in subdirs {
        if let Some(found) = find_md_file_recursive(&subdir, filename) {
            return Some(found);
        }
    }

    None
}

/// Compute backlinks: find all .md files in the directory tree that link to the given file.
#[tauri::command]
fn compute_backlinks(file_path: String) -> Result<Vec<BacklinkEntry>, String> {
    let target = std::path::Path::new(&file_path);
    let target_stem = target
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or("Invalid file path")?;

    // Build the pattern to search for: [[filename]] (with or without .md)
    let patterns: Vec<String> = vec![
        format!("[[{}]]", target_stem),
        format!("[[{}.md]]", target_stem),
    ];

    // Find the project root by walking up to find a directory that contains .md files
    let search_root = target.parent().ok_or("No parent directory")?;

    let mut backlinks = Vec::new();
    scan_for_backlinks(search_root, &file_path, &patterns, &mut backlinks);

    Ok(backlinks)
}

#[derive(serde::Serialize)]
struct BacklinkEntry {
    path: String,
    line: usize,
    context: String,
}

fn scan_for_backlinks(
    dir: &std::path::Path,
    exclude_path: &str,
    patterns: &[String],
    results: &mut Vec<BacklinkEntry>,
) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if ext.eq_ignore_ascii_case("md") {
                    let path_str = path.to_str().unwrap_or_default();
                    // Skip the file itself
                    if path_str == exclude_path {
                        continue;
                    }
                    if let Ok(content) = std::fs::read_to_string(&path) {
                        for (line_num, line) in content.lines().enumerate() {
                            let line_lower = line.to_lowercase();
                            for pattern in patterns {
                                if line_lower.contains(&pattern.to_lowercase()) {
                                    results.push(BacklinkEntry {
                                        path: path_str.to_string(),
                                        line: line_num + 1,
                                        context: line.chars().take(120).collect(),
                                    });
                                    break; // One match per line is enough
                                }
                            }
                        }
                    }
                }
            }
        } else if path.is_dir() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if !name.starts_with('.') && name != "node_modules" && name != "target" {
                    scan_for_backlinks(&path, exclude_path, patterns, results);
                }
            }
        }
    }
}

/// Create a new .md file for a wikilink target that doesn't exist yet.
/// Returns the path of the created file.
#[tauri::command]
fn create_wikilink_target(link_text: String, current_file_path: String) -> Result<String, String> {
    let current = std::path::Path::new(&current_file_path);
    let parent = current.parent().ok_or("No parent directory")?;

    let base_name = link_text.strip_suffix(".md").unwrap_or(&link_text);
    let target_filename = format!("{}.md", base_name);

    let target_path = if link_text.contains('/') || link_text.contains('\\') {
        // Relative path — create in the specified location
        let p = if link_text.ends_with(".md") {
            parent.join(&link_text)
        } else {
            parent.join(&target_filename)
        };
        // Ensure parent directories exist
        if let Some(target_parent) = p.parent() {
            std::fs::create_dir_all(target_parent).map_err(|e| e.to_string())?;
        }
        p
    } else {
        // Simple name — create in the same directory as the current file
        parent.join(&target_filename)
    };

    // Create with a heading matching the link text
    let initial_content = format!("# {}\n", base_name);
    std::fs::write(&target_path, &initial_content).map_err(|e| e.to_string())?;

    target_path
        .to_str()
        .map(String::from)
        .ok_or_else(|| "Invalid path".to_string())
}

// ---------------------------------------------------------------------------
// File watching commands (FEAT-026)
// ---------------------------------------------------------------------------

/// Start watching a file for external changes. Emits "file-changed-externally"
/// events to the calling window when the file is modified or deleted by an
/// external process. Our own saves are filtered out via content-hash comparison.
#[tauri::command]
fn start_watching(
    app: tauri::AppHandle,
    state: State<'_, AppState>,
    window: tauri::Window,
    path: String,
) -> Result<(), String> {
    let label = window.label().to_string();

    // Compute the initial content hash so we can detect self-saves
    let initial_hash = std::fs::read(std::path::Path::new(&path))
        .map(|content| fnv1a_hash(&content))
        .unwrap_or(0);
    let last_saved_hash = Arc::new(AtomicU64::new(initial_hash));

    let hash_ref = last_saved_hash.clone();
    let event_path = path.clone();

    let watcher = FileWatcher::new(&path, 200, move |event| {
        match event {
            FileChangeEvent::Modified => {
                // Read the new file content and compare with our last save hash
                if let Ok(content) = std::fs::read(std::path::Path::new(&event_path)) {
                    let new_hash = fnv1a_hash(&content);
                    let saved_hash = hash_ref.load(Ordering::SeqCst);
                    if new_hash == saved_hash {
                        return; // Our own save — ignore
                    }
                    // Update hash so we don't re-fire for the same external content
                    hash_ref.store(new_hash, Ordering::SeqCst);
                }
                let _ = app.emit(
                    "file-changed-externally",
                    FileChangePayload {
                        kind: "modified".to_string(),
                        path: event_path.clone(),
                    },
                );
            }
            FileChangeEvent::Deleted => {
                let _ = app.emit(
                    "file-changed-externally",
                    FileChangePayload {
                        kind: "deleted".to_string(),
                        path: event_path.clone(),
                    },
                );
            }
        }
    })
    .map_err(|e| e.to_string())?;

    // Insert new watcher (drops any previous watcher for this window)
    state.watch_states.lock().unwrap().insert(
        label,
        WatchState {
            _watcher: watcher,
            last_saved_hash,
        },
    );

    Ok(())
}

/// Stop watching the file for a given window.
#[tauri::command]
fn stop_watching(state: State<'_, AppState>, window: tauri::Window) {
    state
        .watch_states
        .lock()
        .unwrap()
        .remove(window.label());
}

/// Read file content without modifying state (used for diff display).
#[tauri::command]
fn read_file_content(path: String) -> Result<String, String> {
    std::fs::read_to_string(&path).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// App entry point
// ---------------------------------------------------------------------------

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            open_file,
            edit,
            save_file,
            current_text,
            get_recent_files,
            add_recent_file,
            create_window,
            get_pending_open,
            close_current_window,
            resolve_wikilink,
            compute_backlinks,
            create_wikilink_target,
            start_watching,
            stop_watching,
            read_file_content,
        ])
        .setup(|app| {
            rebuild_menu(app.handle())?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                // Clean up file watcher for this window
                let app = window.app_handle();
                if let Some(state) = app.try_state::<AppState>() {
                    state
                        .watch_states
                        .lock()
                        .unwrap()
                        .remove(window.label());
                }
                if app.webview_windows().len() == 0 {
                    app.exit(0);
                }
            }
        })
        .on_menu_event(|app, event| {
            let id = event.id().as_ref();
            match id {
                "new" => {
                    let _ = app.emit("menu-new", ());
                }
                "open" => {
                    let _ = app.emit("menu-open", ());
                }
                "save" => {
                    let _ = app.emit("menu-save", ());
                }
                _ if id.starts_with("recent:") => {
                    let path = &id["recent:".len()..];
                    let state = app.state::<AppState>();
                    let n = WINDOW_COUNTER.fetch_add(1, Ordering::Relaxed);
                    let label = format!("window-{}", n);
                    state
                        .pending_opens
                        .lock()
                        .unwrap()
                        .insert(label.clone(), path.to_string());
                    let _ = WebviewWindowBuilder::new(
                        app,
                        &label,
                        WebviewUrl::App("index.html".into()),
                    )
                    .title("Markdown")
                    .inner_size(900.0, 700.0)
                    .build();
                }
                "quit" => {
                    app.exit(0);
                }
                _ => {}
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    const TEST_LABEL: &str = "test-window";

    #[test]
    fn bridge_open_edit_save_current_text() {
        let state = AppState::default();

        // Create a temp file with known content
        let mut tmp = tempfile::NamedTempFile::new().unwrap();
        tmp.write_all(b"hello world").unwrap();
        tmp.flush().unwrap();
        let path = tmp.path().to_str().unwrap().to_string();

        // open_file: load via markdown_core, store in AppState
        {
            let doc = Document::open_file(&path).unwrap();
            let text = doc.current_text().to_string();
            assert_eq!(text, "hello world");
            state
                .documents
                .lock()
                .unwrap()
                .insert(TEST_LABEL.to_string(), doc);
        }

        // edit: mutate the document through AppState
        {
            let mut docs = state.documents.lock().unwrap();
            let doc = docs.get_mut(TEST_LABEL).expect("document should be open");
            doc.edit(6, 5, "rust");
        }

        // current_text: read back the edited content
        {
            let docs = state.documents.lock().unwrap();
            let doc = docs.get(TEST_LABEL).expect("document should be open");
            assert_eq!(doc.current_text(), "hello rust");
        }

        // save_file: persist via markdown_core
        {
            let docs = state.documents.lock().unwrap();
            let doc = docs.get(TEST_LABEL).expect("document should be open");
            doc.save_file(&path).unwrap();
        }

        // Verify saved content by reopening
        let reopened = Document::open_file(&path).unwrap();
        assert_eq!(reopened.current_text(), "hello rust");
    }

    #[test]
    fn e2e_open_edit_save_reopen() {
        let state = AppState::default();

        // 1. Create a temp .md file with initial content
        let mut tmp = tempfile::Builder::new()
            .suffix(".md")
            .tempfile()
            .unwrap();
        tmp.write_all(b"# Hello\n\nOriginal content.").unwrap();
        tmp.flush().unwrap();
        let path = tmp.path().to_str().unwrap().to_string();

        // 2. Open file (simulates invoke('open_file', {path}))
        let text = {
            let doc = Document::open_file(&path).unwrap();
            let text = doc.current_text().to_string();
            state
                .documents
                .lock()
                .unwrap()
                .insert(TEST_LABEL.to_string(), doc);
            text
        };
        assert_eq!(text, "# Hello\n\nOriginal content.");

        // 3. Simulate JS editing: user types " Edited!" at the end
        let edited_content = format!("{} Edited!", text);

        // 4. Save with content from JS (simulates invoke('save_file', {path, content}))
        {
            std::fs::write(&path, &edited_content).unwrap();
            state.documents.lock().unwrap().insert(
                TEST_LABEL.to_string(),
                Document::from_content(edited_content.clone()),
            );
        }

        // 5. Verify AppState is updated
        {
            let docs = state.documents.lock().unwrap();
            let doc = docs.get(TEST_LABEL).unwrap();
            assert_eq!(doc.current_text(), "# Hello\n\nOriginal content. Edited!");
        }

        // 6. Reopen from disk and verify persistence
        let reopened = Document::open_file(&path).unwrap();
        assert_eq!(
            reopened.current_text(),
            "# Hello\n\nOriginal content. Edited!"
        );
    }

    #[test]
    fn recent_files_ordering_and_trim() {
        let mut files: Vec<String> = vec!["/a.md", "/b.md", "/c.md"]
            .into_iter()
            .map(String::from)
            .collect();

        // Add a new file — should prepend
        let new_path = "/d.md".to_string();
        files.retain(|p| p != &new_path);
        files.insert(0, new_path);
        files.truncate(10);

        assert_eq!(files[0], "/d.md");
        assert_eq!(files.len(), 4);

        // Add existing file — should move to front
        let existing = "/b.md".to_string();
        files.retain(|p| p != &existing);
        files.insert(0, existing);
        files.truncate(10);

        assert_eq!(files[0], "/b.md");
        assert_eq!(files[1], "/d.md");
        assert_eq!(files.len(), 4);
    }
}
