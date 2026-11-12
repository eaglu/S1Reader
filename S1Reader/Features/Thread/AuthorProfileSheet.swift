import SwiftUI

/// A quick look at one author, built from what is already in memory: the floors
/// they wrote in the thread being read. S1 has no profile endpoint worth the
/// round trip, so this deliberately shows local replies only.
struct AuthorProfileSheet: View {
    let name: String
    let authorID: String
    let replies: [Post]
    let isBlocked: Bool
    let canBlock: Bool
    let isFavorite: Bool
    var onOpen: (Post) -> Void = { _ in }
    var onToggleBlock: () -> Void = {}
    var onToggleFavorite: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        AvatarView(uid: authorID, name: name, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.headline)
                            Text("本帖回复 \(replies.count) 楼")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    if replies.isEmpty {
                        Text("本帖已加载的楼层里还没有 Ta 的回复。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(replies) { post in
                        Button {
                            onOpen(post)
                            dismiss()
                        } label: {
                            replyRow(post)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("本帖回复")
                } footer: {
                    Text("只列出已经加载的楼层；没有加载的页不会去请求服务器。")
                }

                Section {
                    Button(action: onToggleFavorite) {
                        Label(
                            isFavorite ? "取消收藏本帖" : "收藏本帖",
                            systemImage: isFavorite ? "bookmark.fill" : "bookmark"
                        )
                    }
                    if canBlock {
                        Button(action: onToggleBlock) {
                            Label(
                                isBlocked ? "取消屏蔽此作者" : "屏蔽此作者",
                                systemImage: isBlocked ? "person.badge.plus" : "person.slash"
                            )
                        }
                    }
                } footer: {
                    Text("屏蔽只保存在本机，只影响楼层和主题列表的显示。")
                }
            }
            .navigationTitle("作者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func replyRow(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("#\(post.position)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(Formatters.relative(post.dateline))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(snippet(post.message))
                .font(.callout)
                .lineLimitForAccessibility(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A full-width row that is at least 44pt tall.
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("跳到这一楼")
    }

    private func snippet(_ message: String) -> String {
        let text = HTMLParser.plainText(message)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 80 ? String(text.prefix(80)) + "…" : text
    }
}
