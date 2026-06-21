import SwiftUI
import UniformTypeIdentifiers

/// Quick Open (FEAT-041): pick a folder once (security-scoped), then fuzzy-search
/// its `.md` files and open one. Uses iOS 17's `openDocument` to open in a new
/// scene — no vault, no index, just the folder the user chose.
enum QuickOpen {
  /// Enumerate `.md`/`.markdown` files under a security-scoped folder URL.
  static func markdownFiles(in folder: URL) -> [URL] {
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
    var files: [URL] = []
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                 options: [.skipsHiddenFiles]) else { return [] }
    for case let url as URL in e {
      let ext = url.pathExtension.lowercased()
      if ext == "md" || ext == "markdown" { files.append(url) }
    }
    return files.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
  }

  /// Subsequence fuzzy match with a light consecutive-run bonus; nil if no match.
  static func score(_ query: String, _ candidate: String) -> Int? {
    if query.isEmpty { return 0 }
    let q = Array(query.lowercased())
    let c = Array(candidate.lowercased())
    var qi = 0, score = 0, lastMatch = -2
    for (ci, ch) in c.enumerated() {
      if qi < q.count, ch == q[qi] {
        score += (ci == lastMatch + 1) ? 3 : 1
        lastMatch = ci
        qi += 1
      }
    }
    return qi == q.count ? score : nil
  }
}

struct QuickOpenView: View {
  let folderBase: URL?
  let onPickFolder: (URL) -> Void
  let onOpen: (URL) -> Void

  @State private var query = ""
  @State private var files: [URL] = []
  @State private var showFolderPicker = false
  @Environment(\.dismiss) private var dismiss

  private var matches: [URL] {
    guard !query.isEmpty else { return files }
    return files
      .compactMap { url -> (URL, Int)? in
        QuickOpen.score(query, url.lastPathComponent).map { (url, $0) }
      }
      .sorted { $0.1 > $1.1 }
      .map { $0.0 }
  }

  var body: some View {
    NavigationStack {
      Group {
        if files.isEmpty {
          ContentUnavailableView {
            Label("Choose a folder", systemImage: "folder")
          } description: {
            Text("Pick a folder of .md files to search across.")
          } actions: {
            Button("Choose Folder…") { showFolderPicker = true }
          }
        } else {
          List(matches, id: \.self) { url in
            Button {
              onOpen(url)
              dismiss()
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(url.deletingPathExtension().lastPathComponent)
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          .searchable(text: $query, prompt: "Search .md files")
        }
      }
      .navigationTitle("Quick Open")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Folder", systemImage: "folder") { showFolderPicker = true }
        }
      }
      .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
        if case .success(let url) = result {
          onPickFolder(url)
          files = QuickOpen.markdownFiles(in: url)
        }
      }
      .onAppear {
        if let base = folderBase { files = QuickOpen.markdownFiles(in: base) }
      }
    }
  }
}
