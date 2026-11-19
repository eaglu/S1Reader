import SwiftUI
import UIKit

/// Shown when the first page of a thread fails to load. Besides retrying it
/// offers the browser, a login shortcut and a diagnostics copy for reporting
/// the S1 side errors that only appear for signed-in sessions.
struct ThreadErrorState: View {
    let message: String
    let tid: String
    let isLoggedIn: Bool
    let onRetry: () -> Void
    let onLogin: () -> Void

    @State private var copiedDiagnostics = false

    var body: some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: onRetry)
                .buttonStyle(.borderedProminent)
            if let webURL = URL(string: "https://stage1st.com/2b/thread-\(tid)-1-1.html") {
                Link("在浏览器中打开", destination: webURL)
                    .buttonStyle(.bordered)
            }
            if !isLoggedIn {
                Button("登录", action: onLogin)
                    .buttonStyle(.bordered)
            }
            Button(copiedDiagnostics ? "已复制诊断信息" : "复制诊断信息") {
                Task {
                    let details = await APIClient.shared.diagnostics()
                    UIPasteboard.general.string = "tid: \(tid)\n\(details)"
                    copiedDiagnostics = true
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }
}

/// Footer of the thread list: a spinner while a page is loading, otherwise the
/// loaded page range and how many posts are in memory.
struct ThreadListFooter: View {
    let isLoadingMore: Bool
    let hasPosts: Bool
    let range: String
    let loaded: Int
    let total: Int

    var body: some View {
        if isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 20)
        } else if hasPosts {
            Text("\(range) · 已加载 \(loaded) / \(total) 楼")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }
}

/// Placeholder posts for the first load of a thread. The reader sees the shape
/// of what is coming instead of a spinner on an empty page.
struct SkeletonPostRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SkeletonBar(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBar(width: 110, height: 12)
                    SkeletonBar(width: 68, height: 9)
                }
            }
            SkeletonBar(height: 12)
            SkeletonBar(height: 12)
            SkeletonBar(width: 210, height: 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityHidden(true)
    }
}

/// How many placeholder rows it takes to cover the list while it is empty.
/// One row is the fixed height of `SkeletonPostRow` plus its divider; the two
/// spare rows cover the navigation bar and the thread header on the first-load
/// path, so a tall screen never shows a bare strip under the last bar.
enum ThreadSkeletonMetrics {
    static let rowHeight: CGFloat = 135
    static let minimumCount = 3

    static func rowCount(for height: CGFloat) -> Int {
        guard height.isFinite, height > 0 else { return minimumCount }
        return max(minimumCount, Int(ceil(height / rowHeight)) + 2)
    }
}

/// A full screen of placeholder posts. Used while the list has nothing to show
/// yet, and while a saved reading position is being restored: the reader sees
/// the shape of the replies from the first frame instead of a spinner.
struct ThreadSkeletonList: View {
    /// A fixed count when the caller has already measured the space; otherwise
    /// the list measures itself, which is what the linked-thread screen needs.
    var count: Int?

    init(count: Int? = nil) {
        self.count = count
    }

    var body: some View {
        GeometryReader { geometry in
            let rows = count ?? ThreadSkeletonMetrics.rowCount(for: geometry.size.height)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<rows, id: \.self) { _ in
                    SkeletonPostRow()
                    Divider()
                }
            }
            .modifier(ReadableWidth())
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载回复")
        .accessibilityIdentifier("threadSkeleton")
    }
}

/// A thread that loaded fine but came back without any reply.
struct ThreadEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "还没有回复",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("这个主题暂时没有内容，可以稍后刷新。")
        )
        .padding(.top, 40)
    }
}
