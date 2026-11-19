import SwiftUI

/// The Lock Screen card of the reading activity: the thread title, then a
/// quiet page line, then one line of the thread so the reader remembers what
/// they were in the middle of.
///
/// The card is a glance, not a page: one title line, one meta line, one excerpt
/// line. Everything is semantic (`.primary`/`.secondary`/`.quaternary`) so the
/// card follows light/dark and Dynamic Type instead of naming colours of its
/// own. It takes plain values rather than an `ActivityViewContext`, which keeps
/// it renderable outside ActivityKit (the previews below, and the debug screen
/// the simulator screenshots come from). `ReadingLiveActivityWidget` adds the
/// context initialiser on the widget side.
struct ReadingLockScreenView: View {
    let title: String
    let pageLabel: String
    let author: String?
    let excerpt: String
    let progress: Double

    /// "42%" — at a glance a percentage says more than a bar whose scale the
    /// reader has to guess, and it cannot turn into a slash across the card.
    private var percentLabel: String {
        "\(Int((min(1, max(0, progress)) * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "text.book.closed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 7) {
                // Page and progress in one small capsule that sits under the
                // title, not floated off to the right edge.
                Text("\(pageLabel) · \(percentLabel)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))

                if let author {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 2)
        // Live Activity type is already system-sized; the cap only stops an
        // accessibility size from pushing the excerpt off the card.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点继续阅读")
    }
}

#Preview("锁屏", traits: .sizeThatFitsLayout) {
    ReadingLockScreenView(
        title: "有生之年还能看到续作吗",
        pageLabel: "第 398/483 页",
        author: "eaglu",
        excerpt: "最近重看了一遍，还是觉得这一段的节奏最好……",
        progress: 0.82
    )
    .padding(20)
}

#Preview("锁屏 · 深色", traits: .sizeThatFitsLayout) {
    ReadingLockScreenView(
        title: "有生之年还能看到续作吗",
        pageLabel: "第 398/483 页",
        author: "eaglu",
        excerpt: "最近重看了一遍，还是觉得这一段的节奏最好……",
        progress: 0.82
    )
    .padding(20)
    .preferredColorScheme(.dark)
}
