// Cross-platform shims so the editor shares one codebase across iOS (UIKit) and
// macOS (AppKit), per ARCHITECTURE §4 / IOS_BUILD_SPEC M9: iOS and macOS share
// the TextKit 2 surface (UITextView / NSTextView over the same Rust core).

import SwiftUI

#if os(macOS)
import AppKit

typealias PlatformColor = NSColor
typealias PlatformFont = NSFont

extension PlatformColor {
  static var labelCompat: NSColor { .labelColor }
  static var secondaryLabelCompat: NSColor { .secondaryLabelColor }
  static var tertiaryLabelCompat: NSColor { .tertiaryLabelColor }
  static var secondaryFillCompat: NSColor { .underPageBackgroundColor }
  static var linkCompat: NSColor { .linkColor }
}

extension PlatformFont {
  static func monospaced(_ size: CGFloat) -> NSFont {
    .monospacedSystemFont(ofSize: size, weight: .regular)
  }
  static var bodyFont: NSFont { .systemFont(ofSize: NSFont.systemFontSize) }
}

/// True when the user has asked for reduced motion.
var reduceMotionEnabled: Bool {
  NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

#else
import UIKit

typealias PlatformColor = UIColor
typealias PlatformFont = UIFont

extension PlatformColor {
  static var labelCompat: UIColor { .label }
  static var secondaryLabelCompat: UIColor { .secondaryLabel }
  static var tertiaryLabelCompat: UIColor { .tertiaryLabel }
  static var secondaryFillCompat: UIColor { .secondarySystemBackground }
  static var linkCompat: UIColor { .link }
}

extension PlatformFont {
  static func monospaced(_ size: CGFloat) -> UIFont {
    .monospacedSystemFont(ofSize: size, weight: .regular)
  }
  static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }
}

var reduceMotionEnabled: Bool {
  UIAccessibility.isReduceMotionEnabled
}
#endif

/// A bold/italic variant of `base`, cross-platform (the symbolic-trait API and
/// constants differ between UIKit and AppKit).
func styledFont(_ base: PlatformFont, bold: Bool, italic: Bool) -> PlatformFont {
  guard bold || italic else { return base }
  #if os(macOS)
  var traits = NSFontDescriptor.SymbolicTraits()
  if bold { traits.insert(.bold) }
  if italic { traits.insert(.italic) }
  let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
  return NSFont(descriptor: descriptor, size: 0) ?? base
  #else
  var traits = UIFontDescriptor.SymbolicTraits()
  if bold { traits.insert(.traitBold) }
  if italic { traits.insert(.traitItalic) }
  if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
    return UIFont(descriptor: descriptor, size: 0)
  }
  return base
  #endif
}
