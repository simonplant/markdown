#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

// Prove em-core is a real dependency, not just declared.
use em_core::Document;

fn main() {
    // Verify em-core links by constructing a type from it.
    let _doc: Option<Document> = None;

    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
