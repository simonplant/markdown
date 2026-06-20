import MarkdownCore

/// "Format Document" (FEAT-052 / M4): runs the five core formatter rules (list
/// continuation, table alignment, heading spacing, blank-line separation,
/// trailing-whitespace trim) through the Rust engine and returns the reformatted
/// text. All formatting logic stays in the core; the frontend only applies the
/// result. Returns nil when the document is already well-formed (no mutations).
enum FormatAction {
  static func formatted(_ text: String) -> String? {
    let mutations = format(text: text)
    guard !mutations.isEmpty else { return nil }
    return applyMutations(text: text, mutations: mutations)
  }
}
