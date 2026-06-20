import SwiftUI
import CoreText
import UniformTypeIdentifiers

/// Render a styled document (the read-mode `NSAttributedString`) to a paginated
/// PDF via Core Text. FEAT-043 / M-Phase4. Cross-platform (Core Text is shared).
enum PDFExport {
  static func make(_ attributed: NSAttributedString) -> Data {
    let pageSize = CGSize(width: 612, height: 792)            // US Letter
    let margin: CGFloat = 48
    let textRect = CGRect(x: margin, y: margin,
                          width: pageSize.width - 2 * margin,
                          height: pageSize.height - 2 * margin)

    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

    let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
    let total = attributed.length
    var cursor = 0

    while cursor < total {
      ctx.beginPDFPage(nil)
      ctx.textMatrix = .identity
      ctx.translateBy(x: 0, y: pageSize.height)
      ctx.scaleBy(x: 1, y: -1)                                // PDF origin is bottom-left

      let path = CGPath(rect: textRect, transform: nil)
      let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(cursor, 0), path, nil)
      CTFrameDraw(frame, ctx)

      let visible = CTFrameGetVisibleStringRange(frame)
      ctx.endPDFPage()
      if visible.length == 0 { break }                       // guard against no progress
      cursor += visible.length
    }

    ctx.closePDF()
    return data as Data
  }
}

/// A PDF wrapper so SwiftUI's cross-platform `.fileExporter` can save it.
struct PDFFile: FileDocument {
  static var readableContentTypes: [UTType] { [.pdf] }
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
