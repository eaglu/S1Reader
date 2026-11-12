import SwiftUI

/// A quiet entrance for rows that were just inserted (an earlier page, more
/// replies, or freshly fetched ones). The HIG asks motion to be purposeful and
/// brief, so this is a 0.2s fade with a 10pt rise — and only for the rows that
/// actually arrived, never for a whole page of existing content.
private struct RowEntrance: ViewModifier {
    let isNew: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    /// DEBUG hook: `S1_MOTION_SLOW=<factor>` stretches the entrance so it can be
    /// filmed on a simulator.
    private var duration: Double {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["S1_MOTION_SLOW"], let factor = Double(raw) {
            return 0.2 * max(1, factor)
        }
        #endif
        return 0.2
    }

    func body(content: Content) -> some View {
        content
            .opacity(isNew && !settled ? 0 : 1)
            .offset(y: isNew && !settled && !reduceMotion ? 10 : 0)
            // Animating through the transaction (not `withAnimation`) is the part
            // that survives being inserted into a `List`/`LazyVStack`.
            .animation(reduceMotion ? nil : .easeOut(duration: duration), value: settled)
            .task(id: isNew) {
                guard isNew, !settled else { return }
                try? await Task.sleep(for: .milliseconds(16))
                settled = true
            }
    }
}

extension View {
    /// Fades and lifts a row that was just inserted into the list.
    func rowEntrance(isNew: Bool) -> some View {
        modifier(RowEntrance(isNew: isNew))
    }
}

/// Pressed state for rows that act as buttons without looking like one. The tint
/// fill matches how system table rows respond, so the row still feels tappable.
struct PressableRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.primary.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}
