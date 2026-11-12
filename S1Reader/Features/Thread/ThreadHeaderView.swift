import SwiftUI

struct ThreadHeaderView: View {
    let title: String
    let author: String
    let posts: Int
    let views: Int
    /// Opens the author's profile sheet; nil leaves the name as plain text.
    var onAuthorTap: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            // Stacked at accessibility sizes: in a row the author's name is
            // squeezed to an ellipsis and the numbers wrap mid-word.
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { metadata }
                } else {
                    HStack(spacing: 12) { metadata }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var metadata: some View {
        if !author.isEmpty {
            if let onAuthorTap {
                Button(action: onAuthorTap) {
                    IconText(systemImage: "person", text: author)
                        // Grows the hit area to 44pt without making the header
                        // taller: the shape, not the layout, does the work.
                        .contentShape(Rectangle().inset(by: -11))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看作者 \(author)")
            } else {
                IconText(systemImage: "person", text: author)
            }
        }
        IconText(systemImage: "bubble.left.and.bubble.right", text: "\(posts) 楼")
        IconText(systemImage: "eye", text: Formatters.compactCount(views))
    }
}
