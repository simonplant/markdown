//! Raw C ABI for the JS / WebAssembly binding (EPIC-WASM).
//!
//! `wasm-bindgen` targets `wasm32-unknown-unknown`; we ship on `wasm32-wasip1`
//! (so tree-sitter's C gets a libc — see `docs/wasm-spike.md`), so the JS glue
//! is hand-rolled here as a tiny buffer ABI:
//!
//! 1. host calls [`mc_alloc`]`(len)` and writes the UTF-8 markdown into it,
//! 2. host calls [`mc_diagnose`]/[`mc_format`]`(ptr, len)` → pointer to a
//!    **length-prefixed** result: a little-endian `u32` byte length followed by
//!    that many UTF-8 JSON bytes,
//! 3. host reads the JSON, then frees both buffers with [`mc_dealloc`]
//!    (`mc_dealloc(input, len)` and `mc_dealloc(result, 4 + json_len)`).
//!
//! The serialized shapes are the binding's buffer-out contract (`docs/CORE-API.md`).
//! The pure functions [`diagnostics_json`] and [`format_json`] hold the logic and
//! are unit-tested natively; the `extern "C"` shims only marshal memory.

use std::alloc::{alloc, dealloc, Layout};

use serde::Serialize;

#[derive(Serialize)]
struct DiagnosticOut<'a> {
    rule: &'a str,
    severity: &'static str,
    /// Byte offset where the problem starts.
    start: usize,
    /// Byte offset where the problem ends (exclusive).
    end: usize,
    message: &'a str,
}

#[derive(Serialize)]
struct MutationOut<'a> {
    offset: usize,
    delete: usize,
    insert: &'a str,
}

fn severity_str(s: &crate::doctor::Severity) -> &'static str {
    match s {
        crate::doctor::Severity::Error => "error",
        crate::doctor::Severity::Warning => "warning",
        crate::doctor::Severity::Hint => "hint",
    }
}

/// Parse `text`, run the doctor, and return the diagnostics as a JSON array.
/// Pure and binding-agnostic — this is what both WASM and (later) uniffi serve.
pub fn diagnostics_json(text: &str) -> String {
    let tree = crate::parser::parse(text);
    let diagnostics = crate::doctor::check(&tree, text, None);
    let out: Vec<DiagnosticOut> = diagnostics
        .iter()
        .map(|d| DiagnosticOut {
            rule: d.rule,
            severity: severity_str(&d.severity),
            start: d.span.0,
            end: d.span.1,
            message: &d.message,
        })
        .collect();
    serde_json::to_string(&out).unwrap_or_else(|_| "[]".to_string())
}

/// Parse `text`, run the formatter, and return the mutations as a JSON array.
pub fn format_json(text: &str) -> String {
    let tree = crate::parser::parse(text);
    let mutations = crate::formatter::format(&tree, text);
    let out: Vec<MutationOut> = mutations
        .iter()
        .map(|m| MutationOut {
            offset: m.offset,
            delete: m.delete,
            insert: &m.insert,
        })
        .collect();
    serde_json::to_string(&out).unwrap_or_else(|_| "[]".to_string())
}

// --- raw C ABI ------------------------------------------------------------

/// Allocate `len` bytes in the module's linear memory and return the pointer.
/// The host writes input there before calling an entry point. Free with
/// [`mc_dealloc`]`(ptr, len)`. Returns null for `len == 0`.
#[no_mangle]
pub extern "C" fn mc_alloc(len: usize) -> *mut u8 {
    if len == 0 {
        return std::ptr::null_mut();
    }
    // align 1: byte buffers; the host must pass the same `len` back to dealloc.
    match Layout::from_size_align(len, 1) {
        Ok(layout) => unsafe { alloc(layout) },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a buffer previously returned by [`mc_alloc`] or an `mc_*` entry point.
/// `len` must be the buffer's full size (for results, `4 + json_len`).
#[no_mangle]
pub extern "C" fn mc_dealloc(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    if let Ok(layout) = Layout::from_size_align(len, 1) {
        unsafe { dealloc(ptr, layout) };
    }
}

/// Pack a JSON string into a freshly allocated `[u32 LE length][bytes]` buffer.
fn pack(json: String) -> *mut u8 {
    let bytes = json.into_bytes();
    let total = 4 + bytes.len();
    let Ok(layout) = Layout::from_size_align(total, 1) else {
        return std::ptr::null_mut();
    };
    let ptr = unsafe { alloc(layout) };
    if ptr.is_null() {
        return ptr;
    }
    let len_le = (bytes.len() as u32).to_le_bytes();
    unsafe {
        std::ptr::copy_nonoverlapping(len_le.as_ptr(), ptr, 4);
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr.add(4), bytes.len());
    }
    ptr
}

/// Read the UTF-8 input at `[ptr, ptr+len)`, or `None` if null/invalid UTF-8.
///
/// # Safety
/// `ptr` must point to `len` initialized, readable bytes (from [`mc_alloc`]).
unsafe fn input_str<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    let slice = std::slice::from_raw_parts(ptr, len);
    std::str::from_utf8(slice).ok()
}

/// Diagnose the markdown at `[ptr, ptr+len)`. Returns a length-prefixed JSON
/// array of diagnostics (free with [`mc_dealloc`]). Invalid UTF-8 yields `[]`.
///
/// # Safety
/// See [`input_str`].
#[no_mangle]
pub unsafe extern "C" fn mc_diagnose(ptr: *const u8, len: usize) -> *mut u8 {
    let json = match input_str(ptr, len) {
        Some(text) => diagnostics_json(text),
        None => "[]".to_string(),
    };
    pack(json)
}

/// Format the markdown at `[ptr, ptr+len)`. Returns a length-prefixed JSON array
/// of mutations (free with [`mc_dealloc`]). Invalid UTF-8 yields `[]`.
///
/// # Safety
/// See [`input_str`].
#[no_mangle]
pub unsafe extern "C" fn mc_format(ptr: *const u8, len: usize) -> *mut u8 {
    let json = match input_str(ptr, len) {
        Some(text) => format_json(text),
        None => "[]".to_string(),
    };
    pack(json)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diagnostics_json_is_array() {
        let json = diagnostics_json("# A\n\n### C\n");
        assert!(json.starts_with('['), "got {json}");
        // h1 -> h3 skip is a heading-hierarchy diagnostic
        assert!(json.contains("heading-hierarchy"), "got {json}");
    }

    #[test]
    fn diagnostics_json_clean_doc_is_empty_array() {
        assert_eq!(diagnostics_json("# Title\n\nA paragraph.\n"), "[]");
    }

    #[test]
    fn format_json_is_array() {
        let json = format_json("# Title\nNo blank line after heading\n");
        assert!(json.starts_with('['), "got {json}");
    }

    #[test]
    fn pack_roundtrips_length_prefix() {
        let ptr = pack("hello".to_string());
        assert!(!ptr.is_null());
        unsafe {
            let len = u32::from_le_bytes([*ptr, *ptr.add(1), *ptr.add(2), *ptr.add(3)]) as usize;
            assert_eq!(len, 5);
            let body = std::slice::from_raw_parts(ptr.add(4), len);
            assert_eq!(body, b"hello");
        }
        mc_dealloc(ptr, 4 + 5);
    }

    #[test]
    fn alloc_dealloc_roundtrip() {
        let p = mc_alloc(16);
        assert!(!p.is_null());
        mc_dealloc(p, 16);
        assert!(mc_alloc(0).is_null());
    }
}
