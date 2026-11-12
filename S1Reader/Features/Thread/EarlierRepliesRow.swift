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

    /// One page per approach. A rubber band reports an offset past the trigger
    /// for many frames, and the prepend itself keeps the list above the top, so
    /// firing on every update walks the reader through page after page.
    @State private var gate = OverscrollGate()
    /// A pull counts only while the reader is driving the scroll. Jumping to a
    /// page or pinning the top moves the offset too, and the jump is not a
    /// request for the page above.
    @State private var isPulling = false
    /// The latest offset, so a pull can be judged when it starts rather than one
    /// frame in: after a prepend the list rests above the content, and a pull
    /// from there must not count as leaving the top.
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, phase in
                    let pulling = phase == .interacting || phase == .decelerating
                    if pulling, !isPulling, offset > gate.reset { gate.rearm() }
                    isPulling = pulling
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newOffset in
                    offset = newOffset
                    guard isEnabled else {
                        // The list has nothing left above it; a later reload that
                        // brings earlier pages back starts from a clean gate.
                        gate.rearm()
                        return
                    }
                    guard isPulling else { return }
                    guard gate.update(offset: newOffset) else { return }
                    DebugHooks.log("S1 gate fire offset=\(Int(newOffset))")
                    action()
                }
        } else {
            content
        }
    }
}
