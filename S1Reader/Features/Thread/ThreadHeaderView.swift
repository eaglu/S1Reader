import SwiftUI

struct ThreadHeaderView: View {
    let title: String
    let author: String
    let posts: Int
    let views: Int

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
            IconText(systemImage: "person", text: author)
        }
        IconText(systemImage: "bubble.left.and.bubble.right", text: "\(posts) 楼")
        IconText(systemImage: "eye", text: Formatters.compactCount(views))
    }
}
