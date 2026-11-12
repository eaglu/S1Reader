import SwiftUI

/// Lets the user drop cached pictures one thread at a time.
struct ImageCacheView: View {
    @State private var entries: [ImageCacheIndex.Entry] = []
    @State private var showClearAll = false

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "没有缓存",
                    systemImage: "photo.on.rectangle",
                    description: Text("看过的主题里的图片会出现在这里。")
                )
            } else {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title.isEmpty ? "主题 \(entry.tid)" : entry.title)
                                .font(.subheadline)
                                .lineLimitForAccessibility(2)
                            Text("\(entry.urls.count) 张图片 · \(Formatters.relative(entry.updatedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        let tids = offsets.map { entries[$0].tid }
                        Task {
                            for tid in tids {
                                await ImageCacheIndex.shared.remove(tid: tid)
                            }
                            reload()
                        }
                    }
                } footer: {
                    Text("左滑可以清除单个主题的图片缓存。")
                }

                Section {
                    Button("清除全部主题缓存", role: .destructive) {
                        showClearAll = true
                    }
                }
            }
        }
        .navigationTitle("图片缓存")
        .navigationBarTitleDisplayMode(.inline)
        .task { reload() }
        .confirmationDialog(
            "清除全部主题的图片缓存？",
            isPresented: $showClearAll,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                Task {
                    await ImageCacheIndex.shared.removeAll()
                    reload()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func reload() {
        entries = ImageCacheIndex.shared.entries
    }
}
