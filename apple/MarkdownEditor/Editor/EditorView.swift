import SwiftUI
import MarkdownCore

enum EditorMode { case read, author }

/// The document editor: read mode by default (FEAT-049), tap / Edit / ⌘E into
/// TextKit 2 author mode. Status bar (via the Rust core), Format Document (M4),
/// and an outline for navigation (FEAT-039). IOS_BUILD_SPEC §4.
struct EditorView: View {
  @ObservedObject var document: MarkdownFileDocument
  @State private var mode: EditorMode = .read
  @State private var scrollTarget: Int?
  @State private var showOutline = false
  @State private var pdfFile: PDFFile?
  @State private var showPDFExport = false

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch mode {
        case .read:
          ReadModeView(text: document.text) { setMode(.author) }
        case .author:
          MarkdownTextView(text: $document.text, scrollTarget: $scrollTarget)
        }
      }
      Divider()
      CoreStatusBar(text: document.text, mode: mode,
                    onToggle: { setMode(mode == .read ? .author : .read) },
                    onFormat: formatDocument,
                    onOutline: { showOutline = true },
                    onExportPDF: exportPDF)
    }
    .navigationTitle("Markdown")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .sheet(isPresented: $showOutline) {
      OutlineSheet(items: Outline.of(document.text)) { item in
        showOutline = false
        setMode(.author)
        scrollTarget = item.utf16Offset
      }
    }
    .fileExporter(isPresented: $showPDFExport, document: pdfFile,
                  contentType: .pdf, defaultFilename: "Document") { _ in }
  }

  private func formatDocument() {
    if let formatted = FormatAction.formatted(document.text) { document.text = formatted }
  }

  /// Export the rendered document as a PDF (FEAT-043).
  private func exportPDF() {
    pdfFile = PDFFile(data: PDFExport.make(MarkdownRenderer.render(document.text)))
    showPDFExport = true
  }

  private func setMode(_ next: EditorMode) {
    if reduceMotionEnabled { mode = next }
    else { withAnimation(.easeInOut(duration: 0.2)) { mode = next } }
  }
}

/// The document outline (FEAT-039): a navigable list of headings; tapping one
/// scrolls the editor to it.
private struct OutlineSheet: View {
  let items: [OutlineItem]
  let onSelect: (OutlineItem) -> Void

  var body: some View {
    NavigationStack {
      Group {
        if items.isEmpty {
          ContentUnavailableView("No headings", systemImage: "list.bullet.indent")
        } else {
          List(items) { item in
            Button { onSelect(item) } label: {
              Text(item.title)
                .padding(.leading, CGFloat((item.level - 1) * 16))
                .font(item.level <= 1 ? .headline : .body)
                .foregroundStyle(.primary)
            }
          }
        }
      }
      .navigationTitle("Outline")
    }
    .presentationDetents([.medium, .large])
  }
}

/// Word count + doctor-issue count (via `markdown-core`), Format (author mode),
/// outline, and the read/author toggle — in our own bottom bar.
private struct CoreStatusBar: View {
  let text: String
  let mode: EditorMode
  let onToggle: () -> Void
  let onFormat: () -> Void
  let onOutline: () -> Void
  let onExportPDF: () -> Void

  var body: some View {
    let issues = diagnose(text: text).count
    let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    HStack(spacing: 10) {
      Text("\(words) word\(words == 1 ? "" : "s")")
      Label("\(issues)", systemImage: issues == 0 ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(issues == 0 ? Color.secondary : Color.orange)
        .accessibilityLabel(issues == 0 ? "No issues" : "\(issues) issue\(issues == 1 ? "" : "s")")
      Spacer()
      Button("Outline", systemImage: "list.bullet.indent", action: onOutline)
        .labelStyle(.iconOnly)
      Button("Export PDF", systemImage: "arrow.up.doc", action: onExportPDF)
        .labelStyle(.iconOnly)
      if mode == .author {
        Button("Format", action: onFormat)
          .buttonStyle(.bordered)
          .keyboardShortcut("f", modifiers: [.command, .shift])
      }
      Button(mode == .read ? "Edit" : "Done", action: onToggle)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("e", modifiers: .command)
    }
    .font(.footnote)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
  }
}
