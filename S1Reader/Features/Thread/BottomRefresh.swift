import SwiftUI

/// Pulling up at the very bottom asks the server whether new replies arrived.
/// Offsets are only observable from iOS 18 on; older versions keep the hint row.
struct CheckNewRepliesOnOverscroll: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

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
                // Rubber-banding holds the gesture for several updates, so one
                // pull must ask the server exactly once.
                guard isEnabled, overshoot > 55 else { return }
                guard Date().timeIntervalSince(lastFired) > 1.5 else { return }
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
            .accessibilityElement(children: .combine)
        }
    }
}
