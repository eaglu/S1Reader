import SwiftUI

/// Row under the last post: asks the server whether new replies arrived.
///
/// It used to be a hint that asked on an upward overscroll, which meant a
/// deliberate, fairly long drag just to poll. A plain button is easier to find
/// and impossible to trigger by accident while reading the end of a thread.
///
/// The three states deliberately do not share the weight of a filled button:
/// "nothing new" is a result, not an action, so it is a line of footnote text
/// that fades away by itself. Only the idle state is a control.
struct NewRepliesButton: View {
    let isChecking: Bool
    let message: String?
    let hasPosts: Bool
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A result stays on screen for a few seconds, then the row turns back into
    /// the tappable label so the reader can ask again without reading a stale
    /// "已加载 3 条新回复" as if it were today's news.
    @State private var shownMessage: String?

    private static let resultLifetime: Duration = .seconds(4)
    /// Both the control and the result occupy this much height. Switching
    /// between them must not move the list under the reader's thumb.
    private static let rowHeight: CGFloat = 44

    var body: some View {
        if hasPosts {
            Group {
                if let shownMessage {
                    resultRow(shownMessage)
                } else {
                    checkRow
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .padding(.bottom, 16)
            .contentTransition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isChecking)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: shownMessage)
            .task(id: shownMessage) {
                guard shownMessage != nil else { return }
                try? await Task.sleep(for: Self.resultLifetime)
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    shownMessage = nil
                }
            }
            .onChange(of: message) { _, fresh in
                shownMessage = fresh
            }
            .onChange(of: isChecking) { _, checking in
                // A second tap starts a new request; the old result must not sit
                // there while the spinner is up.
                if checking { shownMessage = nil }
            }
            .onAppear { shownMessage = message }
        }
    }

    // MARK: - States

    /// The only tappable state: text plus an icon, no fill, secondary colour so
    /// the row sits below the posts instead of competing with them.
    private var checkRow: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isChecking {
                    ProgressView()
                        .controlSize(.mini)
                    Text("正在检查…")
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("检查新回复")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(NewRepliesRowButtonStyle())
        .disabled(isChecking || !isEnabled)
        // A disabled control that is already dim is hard to read; the spinner
        // itself is the "busy" signal, so only a genuinely unavailable row fades.
        .opacity(isChecking ? 1 : (isEnabled ? 1 : 0.55))
        .accessibilityIdentifier("checkNewReplies")
        .accessibilityLabel(isChecking ? "正在检查…" : "检查新回复")
        .accessibilityHint("点按向服务器查询这个帖子有没有新回复")
        .accessibilityAddTraits(.isButton)
    }

    /// A result is content, not a control: footnote text in a tertiary colour,
    /// no fill, no tap target. It reads as "nothing happened", which is what
    /// "暂无新回复" means.
    private func resultRow(_ text: String) -> some View {
        HStack(spacing: 5) {
            if let symbol = symbol(for: text) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .accessibilityIdentifier("checkNewReplies")
        }
        .foregroundStyle(
            isFailure(text) ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary
        )
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight)
    }

    // MARK: - Copy

    /// "暂无新回复" needs no icon at all; the other results get a hint of one.
    private func symbol(for result: String) -> String? {
        if isFailure(result) { return "exclamationmark.triangle" }
        if result.hasPrefix("暂无新回复") { return nil }
        return "checkmark"
    }

    /// A failed check is the one result that is not "all clear", so it keeps a
    /// slightly stronger grey than an informational result.
    private func isFailure(_ result: String) -> Bool {
        result.hasPrefix("检查失败")
    }
}

/// A row that reads as a button without painting a slab under it: a press dims
/// the line, and nothing is drawn when the finger is off it.
private struct NewRepliesRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}
