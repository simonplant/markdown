use em_core::Document;
use std::fs;
use std::io::Write;
use std::time::Instant;

fn cold_startup_ms() -> f64 {
    let start = Instant::now();
    let _doc = Document::from_content(String::new());
    start.elapsed().as_secs_f64() * 1000.0
}

fn open_small_ms(path: &str) -> f64 {
    let start = Instant::now();
    let _doc = Document::open_file(path).expect("failed to open small file");
    start.elapsed().as_secs_f64() * 1000.0
}

fn open_10k_ms(path: &str) -> f64 {
    let start = Instant::now();
    let _doc = Document::open_file(path).expect("failed to open 10k file");
    start.elapsed().as_secs_f64() * 1000.0
}

fn keystroke_ms() -> f64 {
    let mut doc = Document::from_content("Hello, world!".to_string());
    let start = Instant::now();
    doc.edit(5, 0, "X");
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

fn main() {
    let tmp_dir = std::env::temp_dir().join("em-measure");
    fs::create_dir_all(&tmp_dir).expect("failed to create temp dir");

    // Generate test files
    let small_path = tmp_dir.join("small_100.md");
    {
        let mut f = fs::File::create(&small_path).expect("create small file");
        for i in 1..=100 {
            writeln!(f, "Line {}: The quick brown fox jumps over the lazy dog.", i)
                .expect("write small");
        }
    }

    let medium_path = tmp_dir.join("medium_10k.md");
    {
        let mut f = fs::File::create(&medium_path).expect("create medium file");
        for i in 1..=10_000 {
            writeln!(
                f,
                "Line {}: The quick brown fox jumps over the lazy dog.",
                i
            )
            .expect("write medium");
        }
    }

    let save_path = tmp_dir.join("save_test.md");

    // Load a 10k-line doc into memory for save and memory measurement
    let doc_10k = Document::open_file(medium_path.to_str().unwrap())
        .expect("open 10k for memory measurement");

    // Run measurements
    let cs = cold_startup_ms();
    let os = open_small_ms(small_path.to_str().unwrap());
    let om = open_10k_ms(medium_path.to_str().unwrap());
    let ks = keystroke_ms();
    let sv = save_ms(&doc_10k, save_path.to_str().unwrap());
    let mem = memory_mb();

    // Output JSON
    println!(
        r#"{{"cold_startup_ms":{:.4},"open_small_ms":{:.4},"open_10k_ms":{:.4},"keystroke_ms":{:.4},"save_ms":{:.4},"memory_mb":{:.2}}}"#,
        cs, os, om, ks, sv, mem
    );

    // Cleanup
    let _ = fs::remove_dir_all(&tmp_dir);
}
