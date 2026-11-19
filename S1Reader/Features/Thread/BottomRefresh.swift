import SwiftUI

/// Button under the last post: asks the server whether new replies arrived.
///
/// It used to be a hint that asked on an upward overscroll, which meant a
/// deliberate, fairly long drag just to poll. A plain button is easier to find
/// and impossible to trigger by accident while reading the end of a thread.
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

    var body: some View {
        if hasPosts {
            Button(action: action) {
                HStack(spacing: 6) {
                    if isChecking {
                        ProgressView()
                            .controlSize(.mini)
                        Text("正在检查新回复…")
                    } else if let shownMessage {
                        Image(systemName: symbol(for: shownMessage))
                        Text(shownMessage)
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("检查新回复")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                // 44pt is the smallest comfortable target; a text line plus this
                // padding clears it with room to spare.
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(NewRepliesButtonStyle())
            .frame(minHeight: 44)
            .disabled(isChecking || !isEnabled)
            .padding(.bottom, 16)
            .contentTransition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isChecking)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: shownMessage)
            .accessibilityIdentifier("checkNewReplies")
            .accessibilityLabel(label)
            .accessibilityHint("点按向服务器查询这个帖子有没有新回复")
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

    /// Spoken and displayed text for the current state.
    private var label: String {
        if isChecking { return "正在检查新回复…" }
        if let shownMessage { return shownMessage }
        return "检查新回复"
    }

    private func symbol(for result: String) -> String {
        result.hasPrefix("检查失败") ? "exclamationmark.triangle" : "checkmark.circle"
    }
}

/// A row that reads as a button: a soft fill marks the tap target, and a press
/// deepens it instead of dimming the whole line like a plain link would.
private struct NewRepliesButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color(.secondarySystemFill)
                            : Color(.quaternarySystemFill)
                    )
            }
            .opacity(isEnabled ? 1 : 0.55)
    }
}
