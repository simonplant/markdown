use std::sync::Mutex;

use em_core::Document;
use tauri::menu::{MenuBuilder, MenuItemBuilder, SubmenuBuilder};
use tauri::{Emitter, State};

pub struct AppState {
    pub document: Mutex<Option<Document>>,
}

impl Default for AppState {
    fn default() -> Self {
        AppState {
            document: Mutex::new(None),
        }
    }
}

#[tauri::command]
fn open_file(state: State<'_, AppState>, path: String) -> Result<String, String> {
    let doc = Document::open_file(&path).map_err(|e| e.to_string())?;
    let text = doc.current_text().to_string();
    *state.document.lock().unwrap() = Some(doc);
    Ok(text)
}

#[tauri::command]
fn edit(state: State<'_, AppState>, offset: usize, delete: usize, insert: String) -> Result<(), String> {
    let mut guard = state.document.lock().unwrap();
    let doc = guard.as_mut().ok_or("No document open")?;
    doc.edit(offset, delete, &insert);
    Ok(())
}

#[tauri::command]
fn save_file(state: State<'_, AppState>, path: String, content: String) -> Result<(), String> {
    std::fs::write(&path, &content).map_err(|e| e.to_string())?;
    *state.document.lock().unwrap() = Some(Document::from_content(content));
    Ok(())
}

#[tauri::command]
fn current_text(state: State<'_, AppState>) -> Result<String, String> {
    let guard = state.document.lock().unwrap();
    let doc = guard.as_ref().ok_or("No document open")?;
    Ok(doc.current_text().to_string())
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![open_file, edit, save_file, current_text])
        .setup(|app| {
            let open_item = MenuItemBuilder::with_id("open", "Open…")
                .accelerator("CmdOrCtrl+O")
                .build(app)?;
            let save_item = MenuItemBuilder::with_id("save", "Save")
                .accelerator("CmdOrCtrl+S")
                .build(app)?;
            let file_menu = SubmenuBuilder::new(app, "File")
                .item(&open_item)
                .item(&save_item)
                .build()?;
            let menu = MenuBuilder::new(app).item(&file_menu).build()?;
            app.set_menu(menu)?;
            Ok(())
        })
        .on_menu_event(|app, event| {
            match event.id().as_ref() {
                "open" => {
                    let _ = app.emit("menu-open", ());
                }
                "save" => {
                    let _ = app.emit("menu-save", ());
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

    #[test]
    fn bridge_open_edit_save_current_text() {
        let state = AppState::default();

        // Create a temp file with known content
        let mut tmp = tempfile::NamedTempFile::new().unwrap();
        tmp.write_all(b"hello world").unwrap();
        tmp.flush().unwrap();
        let path = tmp.path().to_str().unwrap().to_string();

        // open_file: load via em_core, store in AppState
        {
            let doc = Document::open_file(&path).unwrap();
            let text = doc.current_text().to_string();
            assert_eq!(text, "hello world");
            *state.document.lock().unwrap() = Some(doc);
        }

        // edit: mutate the document through AppState
        {
            let mut guard = state.document.lock().unwrap();
            let doc = guard.as_mut().expect("document should be open");
            doc.edit(6, 5, "rust");
        }

        // current_text: read back the edited content
        {
            let guard = state.document.lock().unwrap();
            let doc = guard.as_ref().expect("document should be open");
            assert_eq!(doc.current_text(), "hello rust");
        }

        // save_file: persist via em_core
        {
            let guard = state.document.lock().unwrap();
            let doc = guard.as_ref().expect("document should be open");
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
            *state.document.lock().unwrap() = Some(doc);
            text
        };
        assert_eq!(text, "# Hello\n\nOriginal content.");

        // 3. Simulate JS editing: user types " Edited!" at the end
        let edited_content = format!("{} Edited!", text);

        // 4. Save with content from JS (simulates invoke('save_file', {path, content}))
        {
            std::fs::write(&path, &edited_content).unwrap();
            *state.document.lock().unwrap() =
                Some(Document::from_content(edited_content.clone()));
        }

        // 5. Verify AppState is updated
        {
            let guard = state.document.lock().unwrap();
            let doc = guard.as_ref().unwrap();
            assert_eq!(doc.current_text(), "# Hello\n\nOriginal content. Edited!");
        }

        // 6. Reopen from disk and verify persistence
        let reopened = Document::open_file(&path).unwrap();
        assert_eq!(
            reopened.current_text(),
            "# Hello\n\nOriginal content. Edited!"
        );
    }
}
