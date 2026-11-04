import SwiftUI

struct BoardListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let error = model.loadError, model.forums.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") {
                            Task { await model.reload() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            ForEach(model.sections) { section in
                Section {
                    ForEach(section.forums) { forum in
                        NavigationLink(value: forum) {
                            ForumRow(forum: forum)
                        }
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Stage1st")
        .refreshable { await model.reload() }
        .overlay {
            if model.isLoading && model.forums.isEmpty {
                ProgressView("正在连接 S1…")
            }
        }
    }
}

private struct ForumRow: View {
    let forum: Forum

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(forum.name)
                    .font(.headline)
                Spacer(minLength: 8)
                if forum.todayPosts > 0 {
                    Text("今日 \(forum.todayPosts)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            if !forum.description.isEmpty {
                Text(forum.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text("主题 \(Formatters.compactCount(forum.threads)) · 帖数 \(Formatters.compactCount(forum.posts))")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if !forum.subforums.isEmpty {
                HStack(spacing: 6) {
                    ForEach(forum.subforums) { sub in
                        Text(sub.name)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(.secondarySystemFill), in: Capsule())
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        BoardListView()
            .environment(AppModel())
    }
}
