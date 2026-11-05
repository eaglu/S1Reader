import SwiftUI

/// A tight icon + text pair for compact metadata lines.
///
/// `Label`'s own icon-to-title spacing is tuned for body-sized controls and at
/// caption sizes it reads as a hole between the glyph and the number, so the
/// two pieces are laid out explicitly here.
struct IconText: View {
    let systemImage: String
    let text: String
    var spacing: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            Image(systemName: systemImage)
                .font(.caption2)
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
