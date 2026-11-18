import SwiftUI

/// Pulling up at the very bottom asks the server whether new replies arrived.
/// Offsets are only observable from iOS 18 on; older versions keep the hint row.
struct CheckNewRepliesOnOverscroll: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    /// How far the list has to be dragged past its last post before the pull
    /// counts. iOS moves the content far less than the finger travels here, so
    /// this is deliberately small: a normal pull yields 40–60 points of
    /// overshoot, and the 55 this used to ask for never happened — the check
    /// simply never ran. One pull still asks once, through `isArmed`.
    private static let trigger: CGFloat = 14
    /// Overshoot below this means the list is back on its last post, so the
    /// next pull is a new approach.
    private static let rearm: CGFloat = 4

    @State private var isArmed = true
    @State private var lastFired = Date.distantPast

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                let resting = max(
                    0,
                    geometry.contentSize.height - geometry.containerSize.height
                        + geometry.contentInsets.bottom
                )
                return geometry.contentOffset.y - resting
            } action: { _, overshoot in
                guard isEnabled else {
                    // Nothing left to ask about; a later reload starts clean.
                    isArmed = true
                    return
                }
                guard overshoot >= Self.trigger else {
                    if overshoot < Self.rearm { isArmed = true }
                    return
                }
                // Rubber-banding holds the gesture for several updates, so one
                // pull must ask the server exactly once.
                guard isArmed else { return }
                guard Date().timeIntervalSince(lastFired) > 1 else { return }
                isArmed = false
                lastFired = Date()
                action()
            }
        } else {
            content
        }
    }
}

/// Hint under the last post: what a further pull does, or what it found.
struct NewRepliesHint: View {
    let isChecking: Bool
    let message: String?
    let hasPosts: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if hasPosts {
            HStack(spacing: 6) {
                if isChecking {
                    ProgressView()
                        .controlSize(.mini)
                    Text("正在检查新回复…")
                } else if let message {
                    Image(systemName: "checkmark.circle")
                    Text(message)
                } else {
                    Image(systemName: "arrow.down")
                    Text("继续上滑，看看有没有新回复")
                }
            }
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
            // The result replaces the hint in place; a short cross-fade keeps
            // the line from flickering while the request is in flight.
            .contentTransition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isChecking)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: message)
            .accessibilityElement(children: .combine)
        }
    }
}
