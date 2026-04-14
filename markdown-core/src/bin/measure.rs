use markdown_core::Document;
use std::fs;
use std::time::Instant;

fn cold_startup_ms() -> f64 {
    let start = Instant::now();
    let _doc = Document::from_content(String::new());
    start.elapsed().as_secs_f64() * 1000.0
}

fn open_file_ms(path: &str) -> f64 {
    let start = Instant::now();
    let _doc = Document::open_file(path).expect("failed to open file");
    start.elapsed().as_secs_f64() * 1000.0
}

fn keystroke_ms_on(doc: &mut Document) -> f64 {
    let mid = doc.current_text().len() / 2;
    let start = Instant::now();
    doc.edit(mid, 0, "X");
    start.elapsed().as_secs_f64() * 1000.0
}

fn save_ms(doc: &Document, path: &str) -> f64 {
    let start = Instant::now();
    doc.save_file(path).expect("failed to save file");
    start.elapsed().as_secs_f64() * 1000.0
}

fn memory_mb() -> f64 {
    #[cfg(target_os = "linux")]
    {
        if let Ok(status) = fs::read_to_string("/proc/self/status") {
            for line in status.lines() {
                if line.starts_with("VmRSS:") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if let Some(kb_str) = parts.get(1) {
                        if let Ok(kb) = kb_str.parse::<f64>() {
                            return kb / 1024.0;
                        }
                    }
                }
            }
        }
        0.0
    }
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        let pid = std::process::id();
        if let Ok(output) = Command::new("ps")
            .args(["-o", "rss=", "-p", &pid.to_string()])
            .output()
        {
            if let Ok(s) = String::from_utf8(output.stdout) {
                if let Ok(kb) = s.trim().parse::<f64>() {
                    return kb / 1024.0;
                }
            }
        }
        0.0
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    {
        0.0
    }
}

/// Generate a realistic markdown file with headings, paragraphs, lists, code blocks, etc.
fn generate_realistic_markdown(line_count: usize) -> String {
    let mut lines = Vec::with_capacity(line_count);
    let paragraphs = [
        "The quick brown fox jumps over the lazy dog. This sentence contains every letter of the English alphabet and has been used as a typing exercise for over a century.",
        "Markdown is a lightweight markup language that you can use to add formatting elements to plaintext text documents. Created by John Gruber in 2004, Markdown is now one of the world's most popular markup languages.",
        "In software engineering, performance optimization is the process of modifying a software system to make some aspect of it work more efficiently or use fewer resources.",
        "Documentation is a critical part of any software project. Well-written docs help new contributors understand the codebase and reduce the time spent answering questions.",
        "Open source software is software with source code that anyone can inspect, modify, and enhance. It is developed in a decentralized and collaborative way, relying on peer review.",
    ];
    let code_block = "```rust\nfn main() {\n    println!(\"Hello, world!\");\n    let x = 42;\n    let y = x * 2;\n    println!(\"The answer is {}\", y);\n}\n```";
    let list_items = [
        "- First item in the unordered list",
        "- Second item with **bold text** and *italic text*",
        "- Third item with `inline code` formatting",
        "- Fourth item with a [link](https://example.com)",
    ];

    let mut i = 0;
    while i < line_count {
        let section = (i / 50) % 10;
        // Heading every ~50 lines
        if i % 50 == 0 {
            let level = match section % 3 {
                0 => "#",
                1 => "##",
                _ => "###",
            };
            lines.push(format!("{} Section {} — Line {}", level, section + 1, i + 1));
            i += 1;
            lines.push(String::new());
            i += 1;
            if i >= line_count {
                break;
            }
        }
        // Paragraph block
        let para = paragraphs[i % paragraphs.len()];
        lines.push(format!("Line {}: {}", i + 1, para));
        i += 1;
        if i >= line_count {
            break;
        }
        // List every ~20 lines
        if i % 20 == 0 {
            lines.push(String::new());
            i += 1;
            for item in &list_items {
                if i >= line_count {
                    break;
                }
                lines.push(item.to_string());
                i += 1;
            }
            lines.push(String::new());
            i += 1;
        }
        // Code block every ~35 lines
        if i % 35 == 0 && i + 10 < line_count {
            lines.push(String::new());
            i += 1;
            for code_line in code_block.lines() {
                if i >= line_count {
                    break;
                }
                lines.push(code_line.to_string());
                i += 1;
            }
            lines.push(String::new());
            i += 1;
        }
    }
    lines.truncate(line_count);
    lines.join("\n")
}

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mid = values.len() / 2;
    if values.len() % 2 == 0 {
        (values[mid - 1] + values[mid]) / 2.0
    } else {
        values[mid]
    }
}

fn main() {
    let tmp_dir = std::env::temp_dir().join("markdown-measure");
    fs::create_dir_all(&tmp_dir).expect("failed to create temp dir");

    let num_runs: usize = std::env::var("MEASURE_RUNS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(5);

    let sizes: Vec<usize> = if std::env::args().any(|a| a == "--large") {
        vec![100, 10_000, 50_000, 100_000]
    } else {
        vec![100, 10_000]
    };

    // Generate test files
    for &size in &sizes {
        let path = tmp_dir.join(format!("test_{}.md", size));
        let content = generate_realistic_markdown(size);
        fs::write(&path, &content).expect("write test file");
    }

    let save_path = tmp_dir.join("save_test.md");

    // Collect runs for standard metrics (backward compatible)
    let mut cs_runs = Vec::new();
    let mut os_runs = Vec::new();
    let mut o10k_runs = Vec::new();
    let mut ks_runs = Vec::new();
    let mut sv_runs = Vec::new();

    let small_path = tmp_dir.join("test_100.md");
    let medium_path = tmp_dir.join("test_10000.md");

    for _ in 0..num_runs {
        cs_runs.push(cold_startup_ms());
        os_runs.push(open_file_ms(small_path.to_str().unwrap()));
        o10k_runs.push(open_file_ms(medium_path.to_str().unwrap()));

        let mut doc = Document::from_content("Hello, world!".to_string());
        ks_runs.push(keystroke_ms_on(&mut doc));

        let doc_10k =
            Document::open_file(medium_path.to_str().unwrap()).expect("open 10k for save");
        sv_runs.push(save_ms(&doc_10k, save_path.to_str().unwrap()));
    }

    let mem = memory_mb();

    // Standard output (backward compatible)
    println!(
        r#"{{"cold_startup_ms":{:.4},"open_small_ms":{:.4},"open_10k_ms":{:.4},"keystroke_ms":{:.4},"save_ms":{:.4},"memory_mb":{:.2}}}"#,
        median(&mut cs_runs),
        median(&mut os_runs),
        median(&mut o10k_runs),
        median(&mut ks_runs),
        median(&mut sv_runs),
        mem
    );

    // Large-file metrics (when --large flag is present)
    if sizes.len() > 2 {
        eprintln!("\n--- Large-file performance characteristics ---");
        for &size in &sizes {
            let path = tmp_dir.join(format!("test_{}.md", size));
            let path_str = path.to_str().unwrap();

            let mut open_runs = Vec::new();
            let mut ks_large_runs = Vec::new();
            let mut save_large_runs = Vec::new();

            for _ in 0..num_runs {
                open_runs.push(open_file_ms(path_str));

                let mut doc = Document::open_file(path_str).expect("open for keystroke");
                ks_large_runs.push(keystroke_ms_on(&mut doc));

                let doc_save = Document::open_file(path_str).expect("open for save");
                save_large_runs.push(save_ms(&doc_save, save_path.to_str().unwrap()));
            }

            // Measure memory with this file loaded
            let _doc_mem = Document::open_file(path_str).expect("open for memory");
            let mem_now = memory_mb();

            eprintln!(
                "{} lines: open={:.4}ms  keystroke={:.4}ms  save={:.4}ms  memory={:.2}MB",
                size,
                median(&mut open_runs),
                median(&mut ks_large_runs),
                median(&mut save_large_runs),
                mem_now
            );
        }
    }

    // Cleanup
    let _ = fs::remove_dir_all(&tmp_dir);
}
