import SwiftUI

struct BoardListView: View {
    @Environment(AppModel.self) private var model
    @State private var query = Self.initialQuery

    /// Debug hook so the search field can be filled from the command line.
    private static var initialQuery: String {
        #if DEBUG
        ProcessInfo.processInfo.environment["S1_SEARCH"] ?? ""
        #else
        ""
        #endif
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Filtered in place so the section headers keep their order.
    private var filteredSections: [(title: String, forums: [Forum])] {
        guard !trimmedQuery.isEmpty else {
            return model.sections.map { ($0.title, $0.forums) }
        }
        return model.sections.compactMap { section in
            let forums = section.forums.filter {
                $0.name.localizedStandardContains(trimmedQuery)
                    || $0.description.localizedStandardContains(trimmedQuery)
            }
            return forums.isEmpty ? nil : (section.title, forums)
        }
    }

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

            if model.isLoading && model.forums.isEmpty {
                Section {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonBoardRow()
                    }
                }
            } else if !trimmedQuery.isEmpty && filteredSections.isEmpty {
                Section {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }

            ForEach(Array(filteredSections.enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(section.forums) { forum in
                        NavigationLink(value: Route.forum(forum)) {
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
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索版块")
        .refreshable { await model.reload() }
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

/// Placeholder rows so the first load looks like content instead of a spinner.
private struct SkeletonBoardRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SkeletonBar(width: 96, height: 16)
            SkeletonBar(width: 232, height: 12)
            SkeletonBar(width: 148, height: 10)
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        BoardListView()
            .environment(AppModel())
    }
}
