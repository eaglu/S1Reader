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
