import Foundation
import SwiftMath

/// Renders a LaTeX string to a platform image via SwiftMath (FEAT-038). Used by
/// the read renderer to replace `$…$` / `$$…$$` regions (detected by the core's
/// `math_spans`) with rendered formulas.
enum MathRenderer {
  static func image(latex: String, display: Bool, fontSize: CGFloat) -> PlatformImage? {
    let mathImage = MTMathImage(
      latex: latex,
      fontSize: fontSize,
      textColor: PlatformColor.labelCompat,
      labelMode: display ? .display : .text
    )
    let (error, image) = mathImage.asImage()
    return error == nil ? image : nil
  }
}
