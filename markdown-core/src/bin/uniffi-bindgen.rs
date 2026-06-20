//! uniffi binding generator (EPIC-UNIFFI). Built only with `--features uniffi-bin`.
//! Invoked in library mode against the compiled staticlib to emit Swift bindings:
//!   cargo run -p markdown-core --features uniffi-bin --bin uniffi-bindgen -- \
//!     generate --library <libmarkdown_core.a> --language swift --out-dir <dir>
fn main() {
    uniffi::uniffi_bindgen_main()
}
