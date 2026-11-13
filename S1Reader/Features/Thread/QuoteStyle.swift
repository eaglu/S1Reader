import SwiftUI
import UIKit

/// Colours and metrics for a quoted block.
///
/// Kept in one place so the contrast checks in `QuoteStyleTests` measure exactly
/// what the card draws: the card owns its fill, so it is also the only place
/// that can promise the quoted text stays readable on top of it.
enum QuoteStyle {
    /// Quoted body text. `label` at 75% keeps the body one step below the reply
    /// without dropping under the 4.5:1 floor the screen has to hold; `.secondary`
    /// (label at 60%) measures about 3.5:1 on the light card, which is why the
    /// body is not simply `.secondary`.
    static let body = Color.primary.opacity(0.75)
    /// The "作者 发表于 时间" caption: lighter than the body, still readable
    /// (about 4.6:1 light, 6.1:1 dark).
    static let header = Color.primary.opacity(0.55)
    /// The card sits one layer below the reply, so it takes the faintest fill
    /// rather than a tinted block that competes with the text around it.
    static let fill = Color(uiColor: .quaternarySystemFill)
    /// The hairline between the caption row and the quoted body.
    static let hairline = Color(uiColor: .separator)

    static let cornerRadius: CGFloat = 8
    /// Nested quotes are indented instead of tinted again, so two frames of
    /// colour cannot stack into a smudge.
    static let nestIndent: CGFloat = 12
    /// A tappable quote marks itself with this glyph on the caption row.
    static let affordanceSymbol = "arrow.turn.up.left"
    static let affordanceSize: CGFloat = 12
}
