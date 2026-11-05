import SwiftUI

/// Reports whether a view is actually inside the scroll viewport.
///
/// `LazyVStack` builds rows a little before and after the visible area, and a
/// jump to an anchor can build a whole run of them, so "the row exists" is not
/// the same as "the row is on screen". Picture fetching hangs off this signal so
/// only what the reader can actually see is downloaded.
///
/// `onScrollVisibilityChange` needs iOS 18; on iOS 17 an appearing row is taken
/// as visible, which is the pre-existing behaviour.
private struct VisibleInScroll: ViewModifier {
    let threshold: Double
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: threshold, onChange)
        } else {
            content
                .onAppear { onChange(true) }
                .onDisappear { onChange(false) }
        }
    }
}

extension View {
    /// Calls `onChange` when the view enters or leaves the enclosing scroll
    /// viewport. `threshold` is the fraction of the view that must be visible.
    func visibleInScroll(
        threshold: Double = 0.01,
        _ onChange: @escaping (Bool) -> Void
    ) -> some View {
        modifier(VisibleInScroll(threshold: threshold, onChange: onChange))
    }
}
