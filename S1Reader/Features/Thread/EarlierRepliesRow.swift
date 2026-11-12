import SwiftUI

/// Row above the first loaded post of a jumped-to page: fetches the replies
/// before it. The row is above the scroll anchor, so it shows up once the
/// reader scrolls up (or pulls past the top, which loads on its own).
struct EarlierRepliesRow: View {
    let isLoading: Bool
    let page: Int
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle")
                }
                Text(isLoading ? "正在加载第 \(page) 页…" : "加载更早的回复（第 \(page) 页）")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .contentTransition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isLoading)
        }
        .buttonStyle(PressableRow())
        .disabled(isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("载入上一页的回复")
    }
}

/// Watches the scroll offset so pulling up at the top of a page loads the
/// replies above it. Offsets are only observable from iOS 18 on; older versions
/// keep the explicit row in the list.
struct LoadEarlierOnOverscroll: ViewModifier {
    let isEnabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                guard isEnabled, offset < -55 else { return }
                action()
            }
        } else {
            content
        }
    }
}
