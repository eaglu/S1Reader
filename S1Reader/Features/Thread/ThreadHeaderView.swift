import SwiftUI

struct ThreadHeaderView: View {
    let title: String
    let author: String
    let posts: Int
    let views: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                if !author.isEmpty {
                    IconText(systemImage: "person", text: author)
                }
                IconText(systemImage: "bubble.left.and.bubble.right", text: "\(posts) 楼")
                IconText(systemImage: "eye", text: Formatters.compactCount(views))
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
}
