import SwiftUI

/// The local block list. Everything here is undoable, and undo is what makes a
/// blocklist safe to hand to the reader.
struct BlockedAuthorsView: View {
    @Environment(BlockedAuthorsStore.self) private var store
    @State private var showUnblockAll = false

    var body: some View {
        List {
            if store.entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "没有屏蔽任何作者",
                        systemImage: "person.slash",
                        description: Text("在楼层或主题上长按，就可以屏蔽该作者。")
                    )
                }
                .listRowBackground(Color.clear)
            }

            ForEach(store.entries) { author in
                HStack(spacing: 12) {
                    AvatarView(uid: author.id, name: author.name, size: 32)
                    Text(author.name)
                    Spacer(minLength: 8)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.unblock(author.id)
                    } label: {
                        Label("解除屏蔽", systemImage: "person.badge.plus")
                    }
                }
                .contextMenu {
                    Button {
                        store.unblock(author.id)
                    } label: {
                        Label("解除屏蔽", systemImage: "person.badge.plus")
                    }
                }
            }

            if !store.entries.isEmpty {
                Section {
                    Button("全部解除", role: .destructive) {
                        showUnblockAll = true
                    }
                } footer: {
                    Text("黑名单只保存在本机。被屏蔽的作者在楼层和主题列表里不再显示，但你自己打开的主题仍会保留楼主那一楼。")
                }
            }
        }
        .overlay {
            if store.entries.isEmpty {
                Color.clear.allowsHitTesting(false)
            }
        }
        .navigationTitle("黑名单")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "解除全部 \(store.count) 位作者的屏蔽？",
            isPresented: $showUnblockAll,
            titleVisibility: .visible
        ) {
            Button("全部解除", role: .destructive) {
                for author in store.entries {
                    store.unblock(author.id)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .sensoryFeedback(.impact(weight: .light), trigger: store.count)
    }
}
