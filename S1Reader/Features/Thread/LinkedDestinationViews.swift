import SwiftUI

/// Opens a thread that was linked from inside a post.
///
/// The link only carries a tid, so the summary is loaded first; once it is known
/// the normal thread screen takes over, including any floor the link pointed at.
struct LinkedThreadView: View {
    let tid: String
    let pid: String?
    /// Page to land on when the thread is reopened from the Live Activity. A
    /// saved reading position is ignored in that case: the reader tapped "continue
    /// at page 398", not "wherever I last scrolled to".
    var page: Int?

    @State private var summary: ThreadSummary?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let summary {
                ThreadDetailView(summary: summary, focusPid: pid, startAtPage: page)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("打不开这个帖子", systemImage: "exclamationmark.bubble")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load(force: true) } }
                }
            } else {
                // The destination is always a thread: show the shape of the
                // replies while the summary is on the wire instead of a spinner.
                ThreadSkeletonList()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load(force: Bool = false) async {
        guard summary == nil || force else { return }
        errorMessage = nil
        do {
            let page: ThreadPage = try await APIClient.shared.fetch("viewthread", ["tid": tid, "page": "1"])
            guard let info = page.thread else {
                errorMessage = "这个帖子不存在或已被删除。"
                return
            }
            summary = ThreadSummary(
                tid: info.tid.isEmpty ? tid : info.tid,
                subject: info.subject,
                author: info.author,
                replies: info.replies,
                views: info.views
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Opens a board that was linked from inside a post.
///
/// Same idea: only the fid is known, so the board's name and counters are read
/// from the forum listing before the list appears.
struct LinkedForumView: View {
    let fid: String

    @State private var forum: Forum?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let forum {
                ThreadListView(forum: forum)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("打不开这个版块", systemImage: "exclamationmark.bubble")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await load(force: true) } }
                }
            } else {
                ProgressView("正在打开版块…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load(force: Bool = false) async {
        guard forum == nil || force else { return }
        errorMessage = nil
        do {
            let page: ThreadListPage = try await APIClient.shared.fetch(
                "forumdisplay",
                ["fid": fid, "page": "1"]
            )
            forum = Forum(
                fid: fid,
                name: page.forumName.isEmpty ? "版块 \(fid)" : page.forumName,
                description: page.description,
                threads: page.totalThreads,
                posts: 0,
                todayPosts: 0,
                subforums: []
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
