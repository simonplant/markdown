//! Wikilink resolution, backlink computation, and target creation.
//!
//! Extracted from the Tauri shell into the core (EPIC-CORE-API) so the same
//! logic is reached identically through every binding (uniffi on Apple, WASM on
//! the web) — ARCHITECTURE §3.8: "no separate API per platform, only a separate
//! binding." These functions touch the filesystem but contain no platform-UI
//! types, so they belong to the headless engine. FEAT-035.

use std::path::{Path, PathBuf};

/// Upper bound on directories visited during a single tree scan. A wikilink
/// that doesn't resolve must not turn into a full-disk walk: when the current
/// file lives under a system temp dir (or any large tree), the upward search
/// can otherwise descend into enormous sibling hierarchies. Real note vaults
/// resolve well within this budget; beyond it we give up and report "not
/// found" rather than hang. (The pre-extraction shell code was unbounded.)
const MAX_DIRS_SCANNED: usize = 4096;

/// A reference to a target document found in another `.md` file.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Backlink {
    /// Absolute or as-found path of the file containing the link.
    pub path: String,
    /// 1-based line number of the link.
    pub line: usize,
    /// The line text (truncated for display).
    pub context: String,
}

/// Resolve a wikilink target to a real `.md` file path.
///
/// Searches the directory tree starting from the current file's directory,
/// walking upward (max 5 levels) to find the nearest match. Returns the first
/// match found, or `None` if nothing matches.
pub fn resolve(link_text: &str, current_file_path: &str) -> Option<String> {
    let current = Path::new(current_file_path);
    let parent = current.parent()?;

    // Normalize: strip a trailing `.md` if present; we add it back below.
    let base_name = link_text.strip_suffix(".md").unwrap_or(link_text);
    let target_filename = format!("{}.md", base_name);

    // If the link contains path separators, try it as a relative path first.
    if link_text.contains('/') || link_text.contains('\\') {
        let relative = if link_text.ends_with(".md") {
            parent.join(link_text)
        } else {
            parent.join(&target_filename)
        };
        if relative.is_file() {
            return relative.canonicalize().ok()?.to_str().map(String::from);
        }
    }

    // Walk the tree from `parent`, then upward (max 5 levels). A single
    // directory-visit budget is shared across the whole upward walk so a
    // broken link can't escalate into a full-disk scan.
    let mut budget = MAX_DIRS_SCANNED;
    let mut search_dir = Some(parent);
    let mut depth = 0;
    while let Some(dir) = search_dir {
        if depth > 5 || budget == 0 {
            break;
        }
        if let Some(found) = find_md_file_recursive(dir, &target_filename, &mut budget) {
            return found.to_str().map(String::from);
        }
        search_dir = dir.parent();
        depth += 1;
    }

    None
}

/// Recursively search a directory for a `.md` file matching `filename`
/// (case-insensitive). Returns the first match (breadth-first within a
/// directory, then depth-first). Skips hidden, `node_modules`, and `target`.
/// `budget` caps total directories visited; on exhaustion the search stops and
/// reports no match.
fn find_md_file_recursive(dir: &Path, filename: &str, budget: &mut usize) -> Option<PathBuf> {
    if *budget == 0 {
        return None;
    }
    *budget -= 1;

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
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if !name.starts_with('.') && name != "node_modules" && name != "target" {
                    subdirs.push(path);
                }
            }
        }
    }

    for subdir in subdirs {
        if let Some(found) = find_md_file_recursive(&subdir, filename, budget) {
            return Some(found);
        }
        if *budget == 0 {
            break;
        }
    }

    None
}

/// Compute backlinks: every `.md` file in the directory tree that links to the
/// file at `file_path` via `[[name]]` or `[[name.md]]` (case-insensitive).
pub fn backlinks(file_path: &str) -> Result<Vec<Backlink>, String> {
    let target = Path::new(file_path);
    let target_stem = target
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or("Invalid file path")?;

    let patterns: Vec<String> = vec![
        format!("[[{}]]", target_stem),
        format!("[[{}.md]]", target_stem),
    ];

    let search_root = target.parent().ok_or("No parent directory")?;

    let mut results = Vec::new();
    let mut budget = MAX_DIRS_SCANNED;
    scan_for_backlinks(search_root, file_path, &patterns, &mut results, &mut budget);
    Ok(results)
}

fn scan_for_backlinks(
    dir: &Path,
    exclude_path: &str,
    patterns: &[String],
    results: &mut Vec<Backlink>,
    budget: &mut usize,
) {
    if *budget == 0 {
        return;
    }
    *budget -= 1;

    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if ext.eq_ignore_ascii_case("md") {
                    let path_str = path.to_str().unwrap_or_default();
                    if path_str == exclude_path {
                        continue;
                    }
                    if let Ok(content) = std::fs::read_to_string(&path) {
                        for (line_num, line) in content.lines().enumerate() {
                            let line_lower = line.to_lowercase();
                            for pattern in patterns {
                                if line_lower.contains(&pattern.to_lowercase()) {
                                    results.push(Backlink {
                                        path: path_str.to_string(),
                                        line: line_num + 1,
                                        context: line.chars().take(120).collect(),
                                    });
                                    break; // one match per line is enough
                                }
                            }
                        }
                    }
                }
            }
        } else if path.is_dir() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                if !name.starts_with('.') && name != "node_modules" && name != "target" {
                    scan_for_backlinks(&path, exclude_path, patterns, results, budget);
                    if *budget == 0 {
                        return;
                    }
                }
            }
        }
    }
}

/// Create a new `.md` file for a wikilink target that doesn't exist yet.
/// Returns the path of the created file. The file is seeded with an `# {name}`
/// heading.
pub fn create_target(link_text: &str, current_file_path: &str) -> Result<String, String> {
    let current = Path::new(current_file_path);
    let parent = current.parent().ok_or("No parent directory")?;

    let base_name = link_text.strip_suffix(".md").unwrap_or(link_text);
    let target_filename = format!("{}.md", base_name);

    let target_path = if link_text.contains('/') || link_text.contains('\\') {
        let p = if link_text.ends_with(".md") {
            parent.join(link_text)
        } else {
            parent.join(&target_filename)
        };
        if let Some(target_parent) = p.parent() {
            std::fs::create_dir_all(target_parent).map_err(|e| e.to_string())?;
        }
        p
    } else {
        parent.join(&target_filename)
    };

    let initial_content = format!("# {}\n", base_name);
    std::fs::write(&target_path, &initial_content).map_err(|e| e.to_string())?;

    target_path
        .to_str()
        .map(String::from)
        .ok_or_else(|| "Invalid path".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn write(dir: &Path, name: &str, body: &str) -> String {
        let p = dir.join(name);
        if let Some(parent) = p.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(&p, body).unwrap();
        p.to_str().unwrap().to_string()
    }

    #[test]
    fn resolve_finds_sibling_file() {
        let tmp = tempfile::tempdir().unwrap();
        let here = write(tmp.path(), "index.md", "# index\n");
        write(tmp.path(), "Target Note.md", "# Target Note\n");

        let got = resolve("Target Note", &here).expect("should resolve");
        assert!(got.ends_with("Target Note.md"), "got {got}");
    }

    #[test]
    fn resolve_is_case_insensitive_on_name() {
        let tmp = tempfile::tempdir().unwrap();
        let here = write(tmp.path(), "index.md", "# index\n");
        write(tmp.path(), "Notes.md", "# Notes\n");

        assert!(resolve("notes", &here).is_some());
    }

    #[test]
    fn resolve_returns_none_when_missing() {
        let tmp = tempfile::tempdir().unwrap();
        let here = write(tmp.path(), "index.md", "# index\n");
        assert_eq!(resolve("Nope", &here), None);
    }

    #[test]
    fn backlinks_finds_referencing_files() {
        let tmp = tempfile::tempdir().unwrap();
        let target = write(tmp.path(), "Target.md", "# Target\n");
        write(tmp.path(), "a.md", "see [[Target]] here\n");
        write(tmp.path(), "b.md", "no link\n");
        write(tmp.path(), "c.md", "ref [[target.md]] lower\n");

        let mut links = backlinks(&target).unwrap();
        links.sort_by(|a, b| a.path.cmp(&b.path));
        assert_eq!(links.len(), 2, "a.md and c.md link to Target");
        assert!(links.iter().all(|l| l.line == 1));
    }

    #[test]
    fn backlinks_excludes_the_target_itself() {
        let tmp = tempfile::tempdir().unwrap();
        let target = write(tmp.path(), "Self.md", "I mention [[Self]]\n");
        let links = backlinks(&target).unwrap();
        assert!(links.is_empty(), "a file linking to itself is not a backlink");
    }

    #[test]
    fn create_target_writes_seeded_heading() {
        let tmp = tempfile::tempdir().unwrap();
        let here = write(tmp.path(), "index.md", "# index\n");

        let created = create_target("New Page", &here).unwrap();
        assert!(created.ends_with("New Page.md"));
        assert_eq!(fs::read_to_string(&created).unwrap(), "# New Page\n");
    }
}
