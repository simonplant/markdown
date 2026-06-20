// swift-tools-version:6.0
import PackageDescription

// Wraps the Rust markdown-core engine (built to MarkdownCore.xcframework by
// apple/scripts/build-rust.sh) + the uniffi-generated Swift bindings into a
// SwiftPM package the iOS/macOS app and its tests consume. EPIC-UNIFFI.
let package = Package(
  name: "MarkdownCore",
  // uniffi-generated bindings target the Swift 5 language mode (they use a global
  // `var initializationResult` for the one-time version check, which Swift 6's
  // strict-concurrency mode rejects). Pin v5 for the whole package.
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
  ],
  targets: [
    // The xcframework carries the static lib + the C FFI module (markdown_coreFFI)
    // for ios / ios-sim / macos. SwiftPM picks the host slice for `swift test`.
    .binaryTarget(
      name: "MarkdownCoreFFIBinary",
      path: "../../MarkdownCore.xcframework"
    ),
    // The uniffi-generated markdown_core.swift, which imports markdown_coreFFI.
    .target(
      name: "MarkdownCore",
      dependencies: ["MarkdownCoreFFIBinary"],
      path: "Sources/MarkdownCore"
    ),
    .testTarget(
      name: "MarkdownCoreTests",
      dependencies: ["MarkdownCore"],
      path: "Tests/MarkdownCoreTests"
    ),
  ],
  swiftLanguageModes: [.v5]
)
