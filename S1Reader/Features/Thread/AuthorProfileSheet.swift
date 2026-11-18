import SwiftUI

/// A quick look at one author.
///
/// The sheet opens on what the reader already has — the floors this author
/// wrote in the thread being read — and loads the author's own thread and
/// reply lists from their S1 space in the background. Those two lists need a
/// session cookie, so a signed-out reader gets a login invitation instead of
/// two empty sections.
struct AuthorProfileSheet: View {
    let name: String
    let authorID: String
    let replies: [Post]
    let isBlocked: Bool
    let canBlock: Bool
    let isFavorite: Bool
    let isLoggedIn: Bool
    var onOpen: (Post) -> Void = { _ in }
    var onToggleBlock: () -> Void = {}
    var onToggleFavorite: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app

    @State private var model: AuthorSpaceModel
    @State private var showLogin = false

    init(
        name: String,
        authorID: String,
        replies: [Post],
        isBlocked: Bool,
        canBlock: Bool,
        isFavorite: Bool,
        isLoggedIn: Bool,
        onOpen: @escaping (Post) -> Void = { _ in },
        onToggleBlock: @escaping () -> Void = {},
        onToggleFavorite: @escaping () -> Void = {}
    ) {
        self.name = name
        self.authorID = authorID
        self.replies = replies
        self.isBlocked = isBlocked
        self.canBlock = canBlock
        self.isFavorite = isFavorite
        self.isLoggedIn = isLoggedIn
        self.onOpen = onOpen
        self.onToggleBlock = onToggleBlock
        self.onToggleFavorite = onToggleFavorite
        _model = State(initialValue: AuthorSpaceModel(uid: authorID, isLoggedIn: isLoggedIn))
    }

    private var showsLoginInvitation: Bool {
        !app.isLoggedIn || model.needsLogin
    }

    /// A cookie that was there and stopped working, as opposed to a reader who
    /// never signed in.
    private var sessionExpired: Bool {
        app.isLoggedIn && model.needsLogin
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection

                if showsLoginInvitation {
                    loginSection
                } else {
                    threadsSection
                    repliesSection
                }

                localRepliesSection
                actionsSection
            }
            .navigationTitle("作者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView()
            }
            .onChange(of: app.isLoggedIn) { _, loggedIn in
                guard loggedIn else { return }
                Task { await model.didLogIn() }
            }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(uid: authorID, name: name, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.title3.weight(.semibold))
                    Text("本帖回复 \(replies.count) 楼")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var loginSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    sessionExpired ? "登录已过期，登录后可查看 Ta 的更多帖子" : "登录后可查看 Ta 的更多帖子",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .font(.callout.weight(.medium))

                Text(sessionExpired
                    ? "重新登录后会读取 Ta 的主题和回复；本帖回复不需要登录。"
                    : "Ta 的主题和回复要带 S1 登录态才能读取；本帖回复不需要登录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    showLogin = true
                } label: {
                    Label("登录", systemImage: "person.crop.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(minHeight: 32)
            }
            .padding(.vertical, 4)
        }
    }

    private var threadsSection: some View {
        Section {
            if model.isLoadingThreads && model.threadItems.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonAuthorRow()
                }
                .listRowSeparator(.hidden)
            } else if let error = model.threadsError, model.threadItems.isEmpty {
                InlineNotice(message: error) {
                    Task { await model.retryThreads() }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            } else if model.threadItems.isEmpty {
                Text("Ta 还没有发过主题。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.threadItems) { thread in
                    Button {
                        open(thread)
                    } label: {
                        threadRow(thread)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        guard thread.id == model.threadItems.last?.id else { return }
                        Task { await model.loadMoreThreads() }
                    }
                }

                if model.isLoadingMoreThreads {
                    ProgressRow()
                } else if let error = model.threadsError {
                    InlineNotice(message: error) {
                        Task { await model.loadMoreThreads() }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                } else if model.threadHasMore {
                    Button("加载更多主题") {
                        Task { await model.loadMoreThreads() }
                    }
                    .font(.callout.weight(.medium))
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Ta 的主题")
        } footer: {
            Text("来自 Ta 的个人空间，按页加载。")
        }
        .task { await model.loadThreadsIfNeeded() }
    }

    private var repliesSection: some View {
        Section {
            if model.isLoadingReplies && model.replyItems.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonAuthorRow()
                }
                .listRowSeparator(.hidden)
            } else if let error = model.repliesError, model.replyItems.isEmpty {
                InlineNotice(message: error) {
                    Task { await model.retryReplies() }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            } else if model.replyItems.isEmpty {
                Text("Ta 还没有回复过别的主题。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.replyItems) { reply in
                    Button {
                        open(reply)
                    } label: {
                        remoteReplyRow(reply)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        guard reply.id == model.replyItems.last?.id else { return }
                        Task { await model.loadMoreReplies() }
                    }
                }

                if model.isLoadingMoreReplies {
                    ProgressRow()
                } else if let error = model.repliesError {
                    InlineNotice(message: error) {
                        Task { await model.loadMoreReplies() }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                } else if model.replyHasMore {
                    Button("加载更多回复") {
                        Task { await model.loadMoreReplies() }
                    }
                    .font(.callout.weight(.medium))
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Ta 的回复")
        } footer: {
            Text("点一行跳到那一楼；已加载的楼层会显示楼层号和时间。")
        }
        .task { await model.loadRepliesIfNeeded() }
    }

    private var localRepliesSection: some View {
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
                    localReplyRow(post)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("本帖回复")
        } footer: {
            Text("只列出已经加载的楼层；没有加载的页不会去请求服务器。")
        }
    }

    private var actionsSection: some View {
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

    // MARK: - Rows

    private func threadRow(_ thread: AuthorSpaceParser.ThreadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(thread.subject)
                    .font(.callout.weight(.medium))
                    .lineLimitForAccessibility(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                if !thread.forumName.isEmpty {
                    Text(thread.forumName)
                }
                Text("\(thread.replies) 回复")
                Text("\(thread.views) 查看")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if !thread.lastPost.isEmpty {
                Text("最后回复 \(thread.lastPost)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开主题")
    }

    private func remoteReplyRow(_ reply: AuthorSpaceParser.ReplyItem) -> some View {
        let local = replies.first { $0.pid == reply.pid }
        let floor = local?.position ?? reply.position
        let time = local.map { Formatters.relative($0.dateline) }
            ?? (reply.dateline.isEmpty ? nil : Formatters.relative(reply.dateline))
        let body = local.map { snippet($0.message) } ?? snippet(reply.snippet)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(reply.threadSubject)
                    .font(.callout.weight(.medium))
                    .lineLimitForAccessibility(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(body)
                .font(.callout)
                .lineLimitForAccessibility(2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let floor {
                    Text("#\(floor)")
                }
                if !reply.forumName.isEmpty {
                    Text(reply.forumName)
                }
                if let time, !time.isEmpty {
                    Text(time)
                }
                // The stock space-reply table prints neither the floor nor the
                // time; say what the tap does instead of leaving the line blank.
                if floor == nil && (time ?? "").isEmpty {
                    Text("跳到该楼")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("跳到这一楼")
    }

    private func localReplyRow(_ post: Post) -> some View {
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
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("跳到这一楼")
    }

    // MARK: - Actions

    /// Threads and replies live in other screens, so the sheet closes first and
    /// the app's own link handler pushes the destination.
    private func open(_ thread: AuthorSpaceParser.ThreadItem) {
        guard let url = URL(string: "https://stage1st.com/2b/forum.php?mod=viewthread&tid=\(thread.tid)") else { return }
        dismiss()
        _ = openURL(url)
    }

    private func open(_ reply: AuthorSpaceParser.ReplyItem) {
        guard let url = URL(string: "https://stage1st.com/2b/forum.php?mod=redirect&goto=findpost&ptid=\(reply.tid)&pid=\(reply.pid)") else { return }
        dismiss()
        _ = openURL(url)
    }

    private func snippet(_ message: String) -> String {
        let text = HTMLParser.plainText(message)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 80 ? String(text.prefix(80)) + "…" : text
    }
}

private struct SkeletonAuthorRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonBar(height: 13)
            SkeletonBar(width: 140, height: 10)
        }
        .padding(.vertical, 2)
        .accessibilityHidden(true)
    }
}

private struct ProgressRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .listRowSeparator(.hidden)
    }
}
