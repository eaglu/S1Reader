import SwiftUI

/// The Lock Screen card of the reading activity: title, page, and one line of
/// the thread so the reader remembers what they were in the middle of.
///
/// It takes plain values rather than an `ActivityViewContext`, which keeps it
/// renderable outside ActivityKit (the previews below, and the debug screen the
/// simulator screenshots come from). `ReadingLiveActivityWidget` adds the
/// context initialiser on the widget side.
struct ReadingLockScreenView: View {
    let title: String
    let pageLabel: String
    let author: String?
    let excerpt: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "text.book.closed.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(pageLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
            }

            if let author, !excerpt.isEmpty {
                Text("\(author)：\(excerpt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let author {
                Text(author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // A hand-drawn bar instead of `ProgressView`: its tint comes from
            // the bundle's accent colour, which the app and the extension do not
            // share. Semantic fills follow light/dark on their own.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(.primary)
                        .frame(width: max(0, min(1, progress)) * geometry.size.width)
                }
            }
            .frame(height: 4)
            .accessibilityElement()
            .accessibilityLabel("阅读进度")
            .accessibilityValue(pageLabel)
        }
        .padding(.vertical, 4)
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
