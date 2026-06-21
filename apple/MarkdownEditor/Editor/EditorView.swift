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
  @State private var showSettings = false
  @State private var showQuickOpen = false
  @AppStorage(AppSettings.appearanceKey) private var appearance = "system"
  @AppStorage("quickOpenFolderBookmark") private var folderBookmark = Data()
  #if os(macOS)
  @Environment(\.openDocument) private var openDocument
  #endif

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
                    onExportPDF: exportPDF,
                    onSettings: { showSettings = true },
                    onQuickOpen: { showQuickOpen = true })
    }
    .preferredColorScheme(AppSettings.colorScheme(appearance))
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
    .sheet(isPresented: $showSettings) { SettingsView() }
    .sheet(isPresented: $showQuickOpen) {
      QuickOpenView(
        folderBase: resolvedFolder(),
        onPickFolder: saveFolder,
        onOpen: openSelected
      )
    }
  }

  /// Resolve the saved security-scoped folder bookmark (Quick Open, FEAT-041).
  private func resolvedFolder() -> URL? {
    guard !folderBookmark.isEmpty else { return nil }
    var stale = false
    #if os(macOS)
    // Under the App Sandbox a plain bookmark does not yield a security-scoped
    // URL, so saved-folder access fails on relaunch. Resolve with security scope.
    return try? URL(resolvingBookmarkData: folderBookmark, options: .withSecurityScope,
                    relativeTo: nil, bookmarkDataIsStale: &stale)
    #else
    return try? URL(resolvingBookmarkData: folderBookmark, bookmarkDataIsStale: &stale)
    #endif
  }

  private func saveFolder(_ url: URL) {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    #if os(macOS)
    folderBookmark = (try? url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)) ?? Data()
    #else
    folderBookmark = (try? url.bookmarkData()) ?? Data()
    #endif
  }

  /// Open a chosen file. macOS opens it in a new window (`openDocument`); iOS has
  /// no programmatic DocumentGroup open, so it loads the content into this view.
  private func openSelected(_ url: URL) {
    #if os(macOS)
    Task { try? await openDocument(at: url) }
    #else
    let folder = resolvedFolder()
    let scoped = folder?.startAccessingSecurityScopedResource() ?? false
    defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }
    if let data = try? Data(contentsOf: url) {
      // load(from:) updates text AND the BOM flag together so the next save
      // doesn't write the previous file's byte prefix onto this content.
      try? document.load(from: data)
    }
    #endif
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
  let onSettings: () -> Void
  let onQuickOpen: () -> Void

  var body: some View {
    let issues = diagnose(text: text).count
    let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    HStack(spacing: 10) {
      Text("\(words) word\(words == 1 ? "" : "s")")
      Label("\(issues)", systemImage: issues == 0 ? "checkmark.circle" : "exclamationmark.triangle")
        .foregroundStyle(issues == 0 ? Color.secondary : Color.orange)
        .accessibilityLabel(issues == 0 ? "No issues" : "\(issues) issue\(issues == 1 ? "" : "s")")
      Spacer()
      Button("Quick Open", systemImage: "magnifyingglass", action: onQuickOpen)
        .labelStyle(.iconOnly)
      Button("Outline", systemImage: "list.bullet.indent", action: onOutline)
        .labelStyle(.iconOnly)
      Button("Export PDF", systemImage: "arrow.up.doc", action: onExportPDF)
        .labelStyle(.iconOnly)
      Button("Settings", systemImage: "gearshape", action: onSettings)
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
