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

    // If the link contains path separators, try it as a relative path first —
    // but contained within the note's directory (reject absolute / `..` escapes
    // so a document can't probe arbitrary filesystem paths like [[/etc/passwd]]).
    if link_text.contains('/') || link_text.contains('\\') {
        let rel = if link_text.ends_with(".md") {
            link_text.to_string()
        } else {
            target_filename.clone()
        };
        if let Some(candidate) = contained_join(parent, &rel) {
            if candidate.is_file() {
                return candidate.canonicalize().ok()?.to_str().map(String::from);
            }
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
        // Skip symlinks so a cyclic link (e.g. `loop -> .`) can't be descended
        // into repeatedly and exhaust the whole directory-visit budget.
        if entry.file_type().map(|t| t.is_symlink()).unwrap_or(false) {
            continue;
        }
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

    // Canonicalize the target so self-exclusion holds on case-insensitive
    // filesystems (macOS) and across separator/symlink differences — otherwise a
    // file can list itself as its own backlink.
    let exclude = target.canonicalize().ok();

    let mut results = Vec::new();
    let mut budget = MAX_DIRS_SCANNED;
    scan_for_backlinks(search_root, exclude.as_deref(), &patterns, &mut results, &mut budget);
    Ok(results)
}

fn scan_for_backlinks(
    dir: &Path,
    exclude: Option<&Path>,
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
        // Skip symlinks to avoid cyclic descent (see find_md_file_recursive).
        if entry.file_type().map(|t| t.is_symlink()).unwrap_or(false) {
            continue;
        }
        let path = entry.path();
        if path.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if ext.eq_ignore_ascii_case("md") {
                    // Exclude the target itself by canonical path, not raw string.
                    if let Some(ex) = exclude {
                        if path.canonicalize().ok().as_deref() == Some(ex) {
                            continue;
                        }
                    }
                    let path_str = path.to_str().unwrap_or_default();
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
                    scan_for_backlinks(&path, exclude, patterns, results, budget);
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
        let rel = if link_text.ends_with(".md") {
            link_text.to_string()
        } else {
            target_filename.clone()
        };
        // Contain the write to the note's directory: reject absolute / `..`-escaping
        // links so document content can't create or overwrite arbitrary files.
        let p = contained_join(parent, &rel)
            .ok_or("Wikilink target escapes the note directory")?;
        if let Some(target_parent) = p.parent() {
            std::fs::create_dir_all(target_parent).map_err(|e| e.to_string())?;
        }
        p
    } else {
        parent.join(&target_filename)
    };

    // Refuse to overwrite an existing file: `create_new` fails atomically if the
    // path exists, so a [[Name]] colliding with a real note can't truncate it.
    let initial_content = format!("# {}\n", base_name);
    {
        use std::io::Write;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&target_path)
            .map_err(|e| {
                if e.kind() == std::io::ErrorKind::AlreadyExists {
                    format!("Target already exists: {}", target_path.display())
                } else {
                    e.to_string()
                }
            })?;
        f.write_all(initial_content.as_bytes())
            .map_err(|e| e.to_string())?;
    }

    target_path
        .to_str()
        .map(String::from)
        .ok_or_else(|| "Invalid path".to_string())
}

/// Join `link` onto `base`, rejecting absolute links and any result that escapes
/// `base` via `..`. Purely lexical (no filesystem access) so it also works for a
/// target that doesn't exist yet. Returns the contained path, or None if it would
/// escape the base directory.
fn contained_join(base: &Path, link: &str) -> Option<PathBuf> {
    use std::path::Component;
    if Path::new(link).is_absolute() {
        return None;
    }
    let normalize = |p: &Path| -> PathBuf {
        let mut out = PathBuf::new();
        for comp in p.components() {
            match comp {
                Component::ParentDir => {
                    out.pop();
                }
                Component::CurDir => {}
                other => out.push(other.as_os_str()),
            }
        }
        out
    };
    let base_norm = normalize(base);
    let candidate = normalize(&base.join(link));
    if candidate.starts_with(&base_norm) {
        Some(candidate)
    } else {
        None
    }
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

    #[test]
    fn create_target_rejects_absolute_link() {
        let tmp = tempfile::tempdir().unwrap();
        let here = write(tmp.path(), "index.md", "# index\n");
        assert!(create_target("/tmp/evil", &here).is_err());
    }

    #[test]
    fn create_target_rejects_parent_escape() {
        let tmp = tempfile::tempdir().unwrap();
        let sub = tmp.path().join("notes");
        fs::create_dir_all(&sub).unwrap();
        let here = write(&sub, "index.md", "# index\n");
        assert!(create_target("../../escape", &here).is_err());
        assert!(!tmp.path().join("escape.md").exists());
    }

    #[test]
    fn create_target_refuses_to_overwrite_existing() {
        let tmp = tempfile::tempdir().unwrap();
        let here = write(tmp.path(), "index.md", "# index\n");
        write(tmp.path(), "Existing.md", "# Existing\nreal content\n");
        assert!(
            create_target("Existing", &here).is_err(),
            "create_target must not truncate an existing file"
        );
        assert_eq!(
            fs::read_to_string(tmp.path().join("Existing.md")).unwrap(),
            "# Existing\nreal content\n"
        );
    }
}
